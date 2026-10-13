// Convert the engine's single-surface DDS capture into a standard PNG.
// No game interfaces, hooks, or input ownership are used by this library.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wincodec.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <new>
#include <string>
#include <vector>

namespace {
constexpr uint32_t kMaxDimension = 16384;
constexpr uint64_t kMaxPixels = 64ULL * 1024 * 1024;
constexpr uint32_t kMaxRowPitch = kMaxDimension * 16 + 4096;
constexpr uint32_t kHeaderBytes = 148;

struct File {
    HANDLE handle = INVALID_HANDLE_VALUE;
    ~File() { if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle); }
};
template<class T> struct Com {
    T* pointer = nullptr;
    ~Com() { if (pointer) pointer->Release(); }
    T** address() { return &pointer; }
    T* operator->() const { return pointer; }
};
struct Apartment {
    HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~Apartment() { if (SUCCEEDED(result)) CoUninitialize(); }
};
struct TempFile {
    std::wstring path;
    bool moved = false;
    ~TempFile() { if (!moved && !path.empty()) DeleteFileW(path.c_str()); }
};
uint32_t word(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | (uint32_t(bytes[1]) << 8) |
           (uint32_t(bytes[2]) << 16) | (uint32_t(bytes[3]) << 24);
}
uint16_t half_word(const uint8_t* bytes) {
    return uint16_t(uint16_t(bytes[0]) | (uint16_t(bytes[1]) << 8));
}
float half_float(uint16_t bits) {
    const uint32_t exponent = (bits >> 10) & 31;
    const uint32_t fraction = bits & 1023;
    float value;
    if (exponent == 0) value = std::ldexp(static_cast<float>(fraction), -24);
    else if (exponent == 31) value = fraction ? NAN : INFINITY;
    else value = std::ldexp(static_cast<float>(1024 + fraction), static_cast<int>(exponent) - 25);
    return (bits & 0x8000) ? -value : value;
}
uint8_t linear_byte(float value) {
    if (std::isnan(value) || value <= 0) return 0;
    if (value >= 1) return 255;
    const float encoded = value <= 0.0031308F ? value * 12.92F :
        1.055F * std::pow(value, 1.0F / 2.4F) - 0.055F;
    return static_cast<uint8_t>(std::floor(encoded * 255.0F + 0.5F));
}
bool read_exact(HANDLE file, void* buffer, DWORD count) {
    DWORD read = 0;
    return ReadFile(file, buffer, count, &read, nullptr) && read == count;
}
DWORD com_error(HRESULT result) {
    if (HRESULT_FACILITY(result) == FACILITY_WIN32) return HRESULT_CODE(result);
    return result == E_OUTOFMEMORY ? ERROR_NOT_ENOUGH_MEMORY : ERROR_GEN_FAILURE;
}

float pq_nits(float encoded) {
    // SMPTE ST 2084 EOTF. PQ is absolute: normalized 1.0 means 10,000 nits.
    constexpr double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0;
    constexpr double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 128.0, c3 = 2392.0 / 128.0;
    const double power = std::pow(static_cast<double>(encoded), 1.0 / m2);
    return static_cast<float>(10000.0 * std::pow(std::max(power - c1, 0.0) / (c2 - c3 * power), 1.0 / m1));
}
void hdr10_bytes(float r, float g, float b, float white_nits,
                 uint8_t& red, uint8_t& green, uint8_t& blue) {
    // Rotate linear BT.2020 into BT.709/sRGB before tone mapping or encoding.
    const float sr = 1.660491F * r - 0.587641F * g - 0.072850F * b;
    const float sg = -0.124550F * r + 1.132900F * g - 0.008349F * b;
    const float sb = -0.018151F * r - 0.100579F * g + 1.118730F * b;
    const float luminance = std::max(0.0F, 0.2126F * sr + 0.7152F * sg + 0.0722F * sb);
    // Hue-preserving Reinhard mapping, with an explicit HDR diffuse-white scale.
    const float scale = 1.0F / (white_nits + luminance);
    red = linear_byte(sr * scale); green = linear_byte(sg * scale); blue = linear_byte(sb * scale);
}
using Color = std::array<float, 3>;
using Matrix = std::array<Color, 3>;
Color multiply(const Matrix& matrix, const Color& color) {
    Color result{};
    for (size_t i = 0; i < result.size(); ++i)
        result[i] = matrix[i][0] * color[0] + matrix[i][1] * color[1] + matrix[i][2] * color[2];
    return result;
}
void native_sdr_bytes(float r, float g, float b,
                      uint8_t& red, uint8_t& green, uint8_t& blue) {
    // The game's SDR final compositor converts the already tone-mapped PQ
    // scene with these exact float32 constants. Preserve that display transform
    // rather than applying a second Reinhard curve. Its normalization is fixed;
    // the legacy white_nits argument does not affect encoding 2.
    // Source: aaac81ae5fbabc7c-ace8 final-compositor DXBC, read-only disassembly.
    constexpr Matrix pre{{
        {{0.9599400162696838F, 0.010470000095665455F, 0.007029999978840351F}},
        {{0.0016199999954551458F, 0.9996899962425232F, 0.0014900000533089042F}},
        {{0.005289999768137932F, 0.023830000311136246F, 1.0501600503921509F}}
    }};
    constexpr Matrix xyz{{
        {{0.6624541878700256F, 0.13400420546531677F, 0.15618768334388733F}},
        {{0.2722287178039551F, 0.6740817427635193F, 0.053689517080783844F}},
        {{-0.005574649665504694F, 0.00406073359772563F, 1.0103391408920288F}}
    }};
    constexpr Matrix adapt{{
        {{1.6410233974456787F, -0.32480329275131226F, -0.23642469942569733F}},
        {{-0.663662850856781F, 1.6153316497802734F, 0.016756348311901093F}},
        {{0.011721894145011902F, -0.008284442126750946F, 0.9883948564529419F}}
    }};
    constexpr Matrix rgb{{
        {{3.2409698963165283F, -1.5373831987380981F, -0.4986107647418976F}},
        {{-0.9692436456680298F, 1.8759675025939941F, 0.04155505821108818F}},
        {{0.05563008040189743F, -0.20397695899009705F, 1.056971549987793F}}
    }};
    Color value = multiply(pre, Color{{r, g, b}});
    for (float& channel : value) channel = (channel - 0.001F) * 0.0036363769322633743F;
    value = multiply(xyz, value);
    const float sum = std::max(value[0] + value[1] + value[2], 0.0001F);
    const float x = value[0] / sum, y = value[1] / sum;
    const float luminance = std::pow(std::clamp(value[1], 0.0F, 65504.0F), 0.9811000227928162F);
    const float ratio = luminance / std::max(y, 0.0001F);
    value = Color{{ratio * x, luminance, ratio * (1.0F - x - y)}};
    value = multiply(rgb, multiply(xyz, multiply(adapt, value)));
    auto byte = [](float channel) {
        return static_cast<uint8_t>(std::floor(std::pow(std::clamp(channel, 0.0F, 1.0F),
                                                       0.4544999897480011F) * 255.0F + 0.5F));
    };
    // The frame-varying native +/-1 byte chroma dither is intentionally omitted
    // from a deterministic PNG. The display transfer itself is preserved.
    red = byte(value[0]); green = byte(value[1]); blue = byte(value[2]);
}
DWORD convert(const wchar_t* input_path, const wchar_t* output_path,
              uint32_t encoding, float white_nits) {
    if (encoding > 3 || (encoding == 1 && (!std::isfinite(white_nits) || white_nits <= 0 || white_nits > 10000)))
        return ERROR_INVALID_PARAMETER;
    if (!input_path || !output_path || !*input_path || !*output_path ||
        wcsnlen(input_path, 32761) > 32760 || wcsnlen(output_path, 32701) > 32700)
        return ERROR_INVALID_PARAMETER;
    // Screenshots always use unique names. The final move also enforces this atomically.
    if (GetFileAttributesW(output_path) != INVALID_FILE_ATTRIBUTES) return ERROR_FILE_EXISTS;
    File input;
    input.handle = CreateFileW(input_path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (input.handle == INVALID_HANDLE_VALUE) return GetLastError();
    LARGE_INTEGER file_size{};
    if (!GetFileSizeEx(input.handle, &file_size)) return GetLastError();
    if (file_size.QuadPart < kHeaderBytes ||
        static_cast<uint64_t>(file_size.QuadPart) > uint64_t(kMaxRowPitch) * kMaxDimension + kHeaderBytes)
        return ERROR_BAD_FORMAT;
    uint8_t header[kHeaderBytes]{};
    if (!read_exact(input.handle, header, kHeaderBytes)) return ERROR_READ_FAULT;
    const uint32_t flags = word(header + 8);
    const uint32_t height = word(header + 12), width = word(header + 16);
    if (word(header) != 0x20534444 || word(header + 4) != 124 ||
        (flags & 0x1007) != 0x1007 || word(header + 76) != 32 ||
        !(word(header + 80) & 4) || word(header + 84) != 0x30315844 ||
        !width || !height || width > kMaxDimension || height > kMaxDimension ||
        uint64_t(width) * height > kMaxPixels || word(header + 24) > 1 ||
        word(header + 28) > 1 || (word(header + 112) & 0x20fe00) ||
        word(header + 132) != 3 || (word(header + 136) & 4) || word(header + 140) != 1)
        return ERROR_BAD_FORMAT;
    uint32_t format = word(header + 128);
    // A verified SDR engine back-buffer capture advertises RGBA8 (28), but its
    // native BGRA surface bytes are preserved by save_render_target. This
    // explicit engine profile is deliberately unavailable for generic DDS or
    // typeless aliases; normal encoding 0 continues to honor the DDS header.
    if (encoding == 3 && format != 28) return ERROR_NOT_SUPPORTED;
    // Back-buffer readbacks may expose typeless storage. Use its compatible
    // screenshot interpretation, without changing component order or precision.
    switch (format) {
    case 27: format = 28; break; // RGBA8_TYPELESS -> RGBA8_UNORM
    case 90: format = 87; break; // BGRA8_TYPELESS -> BGRA8_UNORM
    case 92: format = 88; break; // BGRX8_TYPELESS -> BGRX8_UNORM
    case 23: format = 24; break; // RGB10A2_TYPELESS -> RGB10A2_UNORM
    case 9: format = 10; break;  // RGBA16_TYPELESS -> RGBA16_FLOAT
    case 1: format = 2; break;   // RGBA32_TYPELESS -> RGBA32_FLOAT
    default: break;
    }
    uint32_t pixel_bytes = 0;
    switch (format) {
    case 28: case 29: case 87: case 91: case 88: case 93: case 24: pixel_bytes = 4; break;
    case 10: pixel_bytes = 8; break;
    case 2: pixel_bytes = 16; break;
    default: return ERROR_NOT_SUPPORTED;
    }
    // Storage format does not imply a color space. Only an explicit HDR10
    // capture profile may request PQ/BT.2020 decoding; SDR RGB10 stays intact.
    if ((encoding == 1 || encoding == 2) && format != 24) return ERROR_NOT_SUPPORTED;
    std::array<float, 1024> pq{};
    if (encoding == 1 || encoding == 2) for (size_t i = 0; i < pq.size(); ++i) pq[i] = pq_nits(static_cast<float>(i) / 1023.0F);
    const uint32_t tight_pitch = width * pixel_bytes;
    const uint32_t pitch = (flags & 8) ? word(header + 20) : tight_pitch;
    if (pitch < tight_pitch || pitch > kMaxRowPitch ||
        uint64_t(pitch) * height + kHeaderBytes > static_cast<uint64_t>(file_size.QuadPart))
        return ERROR_BAD_FORMAT;
    std::vector<uint8_t> source(pitch), row(size_t(width) * 4);
    Apartment apartment;
    if (FAILED(apartment.result) && apartment.result != RPC_E_CHANGED_MODE)
        return com_error(apartment.result);
    GUID unique{};
    HRESULT result = CoCreateGuid(&unique);
    if (FAILED(result)) return com_error(result);
    wchar_t suffix[40]{};
    if (!StringFromGUID2(unique, suffix, 40)) return ERROR_GEN_FAILURE;
    TempFile temporary;
    temporary.path = std::wstring(output_path) + L".tmp-" + suffix;
    // Claim our sibling temporary before WIC reopens it, preventing accidental reuse.
    {
        File claim;
        claim.handle = CreateFileW(temporary.path.c_str(), GENERIC_WRITE, 0, nullptr,
                                  CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (claim.handle == INVALID_HANDLE_VALUE) return GetLastError();
    }
    {
        Com<IWICImagingFactory> factory;
        result = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(factory.address()));
        if (FAILED(result)) return com_error(result);
        Com<IWICStream> stream;
        result = factory->CreateStream(stream.address());
        if (FAILED(result)) return com_error(result);
        result = stream->InitializeFromFilename(temporary.path.c_str(), GENERIC_WRITE);
        if (FAILED(result)) return com_error(result);
        Com<IWICBitmapEncoder> encoder;
        result = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.address());
        if (FAILED(result)) return com_error(result);
        result = encoder->Initialize(stream.pointer, WICBitmapEncoderNoCache);
        if (FAILED(result)) return com_error(result);
        Com<IWICBitmapFrameEncode> frame;
        Com<IPropertyBag2> properties;
        result = encoder->CreateNewFrame(frame.address(), properties.address());
        if (FAILED(result)) return com_error(result);
        result = frame->Initialize(properties.pointer);
        if (FAILED(result)) return com_error(result);
        result = frame->SetSize(width, height);
        if (FAILED(result)) return com_error(result);
        WICPixelFormatGUID requested = GUID_WICPixelFormat32bppBGRA;
        result = frame->SetPixelFormat(&requested);
        if (FAILED(result)) return com_error(result);
        if (!IsEqualGUID(requested, GUID_WICPixelFormat32bppBGRA)) return ERROR_NOT_SUPPORTED;
        Com<IWICMetadataQueryWriter> metadata;
        result = frame->GetMetadataQueryWriter(metadata.address());
        if (FAILED(result)) return com_error(result);
        PROPVARIANT rendering_intent{}; rendering_intent.vt = VT_UI1; rendering_intent.bVal = 0;
        result = metadata->SetMetadataByName(L"/sRGB/RenderingIntent", &rendering_intent);
        if (FAILED(result)) return com_error(result);
        for (uint32_t y = 0; y < height; ++y) {
            if (!read_exact(input.handle, source.data(), pitch)) return ERROR_READ_FAULT;
            for (uint32_t x = 0; x < width; ++x) {
                const uint8_t* source_pixel = source.data() + size_t(x) * pixel_bytes;
                uint8_t* output_pixel = row.data() + size_t(x) * 4;
                uint8_t red, green, blue;
                if (format == 28 || format == 29) {
                    if (encoding == 3) {
                        blue = source_pixel[0]; green = source_pixel[1]; red = source_pixel[2];
                    } else {
                        red = source_pixel[0]; green = source_pixel[1]; blue = source_pixel[2];
                    }
                } else if (format == 87 || format == 91 || format == 88 || format == 93) {
                    blue = source_pixel[0]; green = source_pixel[1]; red = source_pixel[2];
                } else if (format == 24) {
                    const uint32_t packed = word(source_pixel);
                    if (encoding == 1) {
                        hdr10_bytes(pq[packed & 1023], pq[(packed >> 10) & 1023], pq[(packed >> 20) & 1023], white_nits, red, green, blue);
                    } else if (encoding == 2) {
                        native_sdr_bytes(pq[packed & 1023], pq[(packed >> 10) & 1023], pq[(packed >> 20) & 1023], red, green, blue);
                    } else {
                        red = static_cast<uint8_t>(((packed & 1023) * 255 + 511) / 1023);
                        green = static_cast<uint8_t>((((packed >> 10) & 1023) * 255 + 511) / 1023);
                        blue = static_cast<uint8_t>((((packed >> 20) & 1023) * 255 + 511) / 1023);
                    }
                } else if (format == 10) {
                    red = linear_byte(half_float(half_word(source_pixel)));
                    green = linear_byte(half_float(half_word(source_pixel + 2)));
                    blue = linear_byte(half_float(half_word(source_pixel + 4)));
                } else {
                    float channels[4]{};
                    std::memcpy(channels, source_pixel, sizeof(channels));
                    red = linear_byte(channels[0]); green = linear_byte(channels[1]); blue = linear_byte(channels[2]);
                }
                output_pixel[0] = blue; output_pixel[1] = green;
                output_pixel[2] = red; output_pixel[3] = 255;
            }
            result = frame->WritePixels(1, width * 4, width * 4, row.data());
            if (FAILED(result)) return com_error(result);
        }
        result = frame->Commit();
        if (FAILED(result)) return com_error(result);
        result = encoder->Commit();
        if (FAILED(result)) return com_error(result);
        result = stream->Commit(STGC_DEFAULT);
        if (FAILED(result)) return com_error(result);
    }
    if (!MoveFileExW(temporary.path.c_str(), output_path, MOVEFILE_WRITE_THROUGH))
        return GetLastError();
    temporary.moved = true;
    return ERROR_SUCCESS;
}
}

extern "C" __declspec(dllexport) int __cdecl PhotoDDSConvert(const wchar_t* input_path,
                                                            const wchar_t* output_path) {
    DWORD error = ERROR_GEN_FAILURE;
    try { error = convert(input_path, output_path, 0, 0); }
    catch (const std::bad_alloc&) { error = ERROR_NOT_ENOUGH_MEMORY; }
    catch (...) { error = ERROR_GEN_FAILURE; }
    SetLastError(error);
    return error == ERROR_SUCCESS ? 1 : 0;
}

extern "C" __declspec(dllexport) int __cdecl PhotoDDSConvertColor(const wchar_t* input_path,
        const wchar_t* output_path, uint32_t encoding, float white_nits) {
    DWORD error = ERROR_GEN_FAILURE;
    try { error = convert(input_path, output_path, encoding, white_nits); }
    catch (const std::bad_alloc&) { error = ERROR_NOT_ENOUGH_MEMORY; }
    catch (...) { error = ERROR_GEN_FAILURE; }
    SetLastError(error);
    return error == ERROR_SUCCESS ? 1 : 0;
}

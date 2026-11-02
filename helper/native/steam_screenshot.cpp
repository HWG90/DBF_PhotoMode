// External, one-shot WGC worker. Adapted from David's existing
// DBF_PhotoMode/freecam/native/window_capture.cpp; no game-loaded component.
// Physical client pixels only. SDR BGRA8; fail closed on unknown/HDR output.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "steam_screenshot.h"
#include <dwmapi.h>
#include <d3d11.h>
#include <dxgi1_6.h>
#include <wincodec.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cwchar>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace capture = winrt::Windows::Graphics::Capture;
namespace directx = winrt::Windows::Graphics::DirectX;
namespace d3d = winrt::Windows::Graphics::DirectX::Direct3D11;
namespace {
constexpr ULONGLONG kDeadlineMs = 5000;
constexpr ULONGLONG kConvertMs = 60000;
constexpr uint64_t kMaxPixels = 64ull * 1024 * 1024;

void require(bool condition, DWORD error = ERROR_INVALID_DATA) {
    if (!condition) throw winrt::hresult_error(HRESULT_FROM_WIN32(error));
}
void last_error() {
    const DWORD error = GetLastError();
    throw winrt::hresult_error(HRESULT_FROM_WIN32(error ? error : ERROR_GEN_FAILURE));
}
struct Operation {
    const WJLScreenshotRequest& request;
    const ULONGLONG begun = GetTickCount64();
    const ULONGLONG deadline = kDeadlineMs;
    void check() const {
        const DWORD waited = WaitForSingleObject(request.cancel_event, 0);
        if (waited == WAIT_FAILED) last_error();
        require(waited == WAIT_TIMEOUT &&
                InterlockedCompareExchange(request.publication, WJL_SCREENSHOT_OPEN, WJL_SCREENSHOT_OPEN) == WJL_SCREENSHOT_OPEN,
                ERROR_CANCELLED);
        require(GetTickCount64() - begun < deadline, ERROR_TIMEOUT);
    }
    DWORD remaining() const {
        check();
        const ULONGLONG elapsed = GetTickCount64() - begun;
        require(elapsed < deadline, ERROR_TIMEOUT);
        return static_cast<DWORD>(deadline - elapsed);
    }
};
struct Apartment {
    Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
    ~Apartment() {
        // save_window has already destroyed every per-job WinRT/COM object.
        // This helper has one WinRT worker at a time. Release its process-static
        // factory references before CoUninitialize can unload GraphicsCapture.
        winrt::clear_factory_cache();
        winrt::uninit_apartment();
    }
};
struct ThreadDpiContext {
    DPI_AWARENESS_CONTEXT previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ThreadDpiContext() { if (!previous) last_error(); }
    ~ThreadDpiContext() { SetThreadDpiAwarenessContext(previous); }
};
int64_t width(const RECT& rect) { return static_cast<int64_t>(rect.right) - rect.left; }
int64_t height(const RECT& rect) { return static_cast<int64_t>(rect.bottom) - rect.top; }
struct Geometry {
    RECT window{}, client{}, dwm{};
    bool has_dwm = false;
    HMONITOR monitor = nullptr;
    UINT dpi = 0;
};
Geometry geometry(HWND window) {
    Geometry value;
    RECT client{};
    if (!GetWindowRect(window, &value.window) || !GetClientRect(window, &client)) last_error();
    POINT first{client.left, client.top}, last{client.right, client.bottom};
    if (!ClientToScreen(window, &first) || !ClientToScreen(window, &last)) last_error();
    value.client = {first.x, first.y, last.x, last.y};
    require(width(value.window) > 0 && height(value.window) > 0 && width(value.client) > 0 && height(value.client) > 0);
    value.has_dwm = SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &value.dwm, sizeof(value.dwm))) &&
                    width(value.dwm) > 0 && height(value.dwm) > 0;
    value.monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
    value.dpi = GetDpiForWindow(window);
    require(value.monitor && value.dpi);
    return value;
}
struct Crop { UINT left, top, width, height; };
Crop client_crop(const Geometry& value, int64_t frame_width, int64_t frame_height) {
    require(frame_width > 0 && frame_height > 0 && frame_width <= 16384 && frame_height <= 16384 &&
            static_cast<uint64_t>(frame_width) * frame_height <= kMaxPixels);
    const bool matches_window = width(value.window) == frame_width && height(value.window) == frame_height;
    const bool matches_dwm = value.has_dwm && width(value.dwm) == frame_width && height(value.dwm) == frame_height;
    require(matches_window || matches_dwm);
    require(!(matches_window && matches_dwm) || EqualRect(&value.window, &value.dwm));
    const RECT frame = matches_dwm ? value.dwm : value.window;
    require(width(value.client) > 0 && height(value.client) > 0 && value.client.left >= frame.left && value.client.top >= frame.top &&
            value.client.right <= frame.right && value.client.bottom <= frame.bottom);
    return {static_cast<UINT>(static_cast<int64_t>(value.client.left) - frame.left),
            static_cast<UINT>(static_cast<int64_t>(value.client.top) - frame.top),
            static_cast<UINT>(width(value.client)), static_cast<UINT>(height(value.client))};
}
struct WindowSearch { DWORD pid; HWND window = nullptr; unsigned count = 0; bool unreadable = false; };
BOOL CALLBACK eligible_window(HWND window, LPARAM parameter) {
    auto& search = *reinterpret_cast<WindowSearch*>(parameter);
    DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
    if (pid != search.pid || !IsWindowVisible(window) || IsIconic(window)) return TRUE;
    DWORD cloaked = 0;
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked)))) search.unreadable = true;
    else if (!cloaked) { search.window = window; ++search.count; }
    return TRUE;
}
HWND unique_window(DWORD pid) {
    WindowSearch search{pid};
    if (!EnumWindows(eligible_window, reinterpret_cast<LPARAM>(&search))) last_error();
    require(!search.unreadable && search.count == 1, ERROR_INVALID_WINDOW_HANDLE);
    return search.window;
}
void expected_executable(HANDLE process, const std::wstring& expected) {
    wchar_t image[32768]; DWORD length = static_cast<DWORD>(std::size(image));
    if (!QueryFullProcessImageNameW(process, 0, image, &length)) last_error();
    require(length && CompareStringOrdinal(image, static_cast<int>(length), expected.c_str(), -1, TRUE) == CSTR_EQUAL,
            ERROR_INVALID_EXE_SIGNATURE);
}
struct Identity {
    const WJLScreenshotRequest& request;
    const std::wstring executable;
    winrt::handle process;
    HWND window = nullptr;
    DWORD thread = 0;
    Geometry bounds;
    explicit Identity(const WJLScreenshotRequest& value) : request(value), executable(value.executable) {
        require(std::filesystem::path(executable).is_absolute() &&
                _wcsicmp(std::filesystem::path(executable).filename().c_str(), L"helldivers2.exe") == 0,
                ERROR_INVALID_EXE_SIGNATURE);
        process.attach(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, request.pid));
        if (!process) last_error();
        expected_executable(process.get(), executable);
        window = unique_window(request.pid);
        DWORD owner = 0; thread = GetWindowThreadProcessId(window, &owner);
        require(thread && owner == request.pid, ERROR_INVALID_WINDOW_HANDLE);
        bounds = geometry(window);
        validate();
    }
    void validate() const {
        require(WaitForSingleObject(process.get(), 0) == WAIT_TIMEOUT, ERROR_PROCESS_ABORTED);
        FILETIME created{}, exited{}, kernel{}, user{};
        if (!GetProcessTimes(process.get(), &created, &exited, &kernel, &user)) last_error();
        require(CompareFileTime(&created, &request.created) == 0, ERROR_INVALID_PARAMETER);
        expected_executable(process.get(), executable);
        DWORD owner = 0;
        require(IsWindow(window) && GetWindowThreadProcessId(window, &owner) == thread && owner == request.pid &&
                unique_window(request.pid) == window && GetAncestor(window, GA_ROOT) == window && GetForegroundWindow() == window,
                ERROR_INVALID_WINDOW_HANDLE);
        const auto current = geometry(window);
        require(EqualRect(&bounds.window, &current.window) && EqualRect(&bounds.client, &current.client) &&
                bounds.has_dwm == current.has_dwm && (!bounds.has_dwm || EqualRect(&bounds.dwm, &current.dwm)) &&
                bounds.monitor == current.monitor && bounds.dpi == current.dpi, ERROR_RETRY);
    }
};
void require_sdr(HMONITOR monitor, const Operation& operation) {
    winrt::com_ptr<IDXGIFactory1> factory;
    winrt::check_hresult(CreateDXGIFactory1(__uuidof(IDXGIFactory1), factory.put_void()));
    unsigned matched = 0;
    for (UINT adapter_index = 0; adapter_index < 64; ++adapter_index) {
        operation.check();
        winrt::com_ptr<IDXGIAdapter1> adapter;
        const HRESULT adapter_result = factory->EnumAdapters1(adapter_index, adapter.put());
        if (adapter_result == DXGI_ERROR_NOT_FOUND) { require(matched == 1 && factory->IsCurrent(), ERROR_NOT_SUPPORTED); return; }
        winrt::check_hresult(adapter_result);
        bool finished = false;
        for (UINT output_index = 0; output_index < 64; ++output_index) {
            winrt::com_ptr<IDXGIOutput> output;
            const HRESULT result = adapter->EnumOutputs(output_index, output.put());
            if (result == DXGI_ERROR_NOT_FOUND) { finished = true; break; }
            winrt::check_hresult(result);
            DXGI_OUTPUT_DESC basic{}; winrt::check_hresult(output->GetDesc(&basic));
            if (basic.Monitor != monitor) continue;
            ++matched;
            auto extended = output.as<IDXGIOutput6>();
            DXGI_OUTPUT_DESC1 desc{}; winrt::check_hresult(extended->GetDesc1(&desc));
            require(desc.Monitor == monitor && desc.AttachedToDesktop &&
                    desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709, ERROR_NOT_SUPPORTED);
        }
        require(finished, ERROR_NOT_SUPPORTED);
    }
    require(false, ERROR_NOT_SUPPORTED);
}
struct FrameState {
    std::mutex mutex;
    HANDLE ready = nullptr; // Borrowed; cleanup clears it under mutex before closing.
    bool closed = false;
};
struct CaptureLifetime {
    winrt::handle ready{CreateEventW(nullptr, FALSE, FALSE, nullptr)};
    std::shared_ptr<FrameState> state = std::make_shared<FrameState>();
    capture::GraphicsCaptureItem item{nullptr};
    capture::Direct3D11CaptureFramePool pool{nullptr};
    capture::GraphicsCaptureSession session{nullptr};
    capture::Direct3D11CaptureFramePool::FrameArrived_revoker arrived;
    capture::GraphicsCaptureItem::Closed_revoker closed;
    CaptureLifetime() { if (!ready) last_error(); state->ready = ready.get(); }
    void check() const { std::lock_guard<std::mutex> lock(state->mutex); require(!state->closed, ERROR_INVALID_WINDOW_HANDLE); }
    void close() noexcept {
        { std::lock_guard<std::mutex> lock(state->mutex); state->closed = true; state->ready = nullptr; }
        arrived.revoke(); closed.revoke();
        if (session) { try { session.Close(); } catch (...) {} session = nullptr; }
        if (pool) { try { pool.Close(); } catch (...) {} pool = nullptr; }
        item = nullptr;
        ready.close();
    }
    ~CaptureLifetime() { close(); }
};
struct FrameLifetime {
    capture::Direct3D11CaptureFrame value{nullptr};
    ~FrameLifetime() { if (value) { try { value.Close(); } catch (...) {} } }
};
struct MappedTexture {
    ID3D11DeviceContext* context;
    ID3D11Texture2D* texture;
    ~MappedTexture() { context->Unmap(texture, 0); }
};
winrt::com_ptr<IStream> encode_png(UINT width, UINT height, const D3D11_MAPPED_SUBRESOURCE& pixels) {
    require(pixels.RowPitch >= width * 4 && static_cast<uint64_t>(pixels.RowPitch) * height <= MAXDWORD);
    auto factory = winrt::create_instance<IWICImagingFactory>(CLSID_WICImagingFactory);
    winrt::com_ptr<IStream> stream;
    winrt::check_hresult(CreateStreamOnHGlobal(nullptr, TRUE, stream.put()));
    winrt::com_ptr<IWICBitmapEncoder> encoder;
    winrt::check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.put()));
    winrt::check_hresult(encoder->Initialize(stream.get(), WICBitmapEncoderNoCache));
    winrt::com_ptr<IWICBitmapFrameEncode> image;
    winrt::check_hresult(encoder->CreateNewFrame(image.put(), nullptr));
    winrt::check_hresult(image->Initialize(nullptr));
    winrt::check_hresult(image->SetSize(width, height));
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    winrt::check_hresult(image->SetPixelFormat(&format));
    require(IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA));
    winrt::check_hresult(image->WritePixels(height, pixels.RowPitch, pixels.RowPitch * height, static_cast<BYTE*>(pixels.pData)));
    winrt::check_hresult(image->Commit());
    winrt::check_hresult(encoder->Commit());
    return stream;
}
std::wstring output_path(const wchar_t* text) {
    const std::filesystem::path path(text);
    require(path.is_absolute() && _wcsicmp(path.extension().c_str(), L".png") == 0, ERROR_INVALID_NAME);
    const auto normalized = path.lexically_normal();
    const auto raw = normalized.native();
    const auto colon = raw.find(L':');
    require(colon == std::wstring::npos || (colon == 1 && raw.find(L':', 2) == std::wstring::npos), ERROR_INVALID_NAME);
    const DWORD attributes = GetFileAttributesW(normalized.parent_path().c_str());
    require(attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) &&
            !(attributes & FILE_ATTRIBUTE_REPARSE_POINT), ERROR_PATH_NOT_FOUND);
    return raw;
}
struct ExclusiveOutput {
    winrt::handle file;
    explicit ExclusiveOutput(const std::wstring& path) {
        GUID unique{}; winrt::check_hresult(CoCreateGuid(&unique));
        wchar_t name[40]; require(StringFromGUID2(unique, name, static_cast<int>(std::size(name))) != 0);
        const auto temporary = std::filesystem::path(path).parent_path() / (std::wstring(L".lll-steam-screenshot-") + name + L".tmp");
        HANDLE created = CreateFileW(temporary.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
                                     FILE_ATTRIBUTE_NORMAL | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
        if (created == INVALID_HANDLE_VALUE) last_error();
        file.attach(created);
    }
    void publish(const std::wstring& path, const Operation& operation) {
        const size_t bytes = sizeof(FILE_RENAME_INFO) + path.size() * sizeof(wchar_t);
        require(bytes <= MAXDWORD, ERROR_FILENAME_EXCED_RANGE);
        std::vector<BYTE> storage(bytes, 0);
        auto* rename = reinterpret_cast<FILE_RENAME_INFO*>(storage.data());
        rename->ReplaceIfExists = FALSE;
        rename->FileNameLength = static_cast<DWORD>(path.size() * sizeof(wchar_t));
        std::copy(path.begin(), path.end(), rename->FileName);
        operation.check();
        require(InterlockedCompareExchange(operation.request.publication, WJL_SCREENSHOT_PUBLISHING, WJL_SCREENSHOT_OPEN) == WJL_SCREENSHOT_OPEN,
                ERROR_CANCELLED);
        if (!SetFileInformationByHandle(file.get(), FileRenameInfo, rename, static_cast<DWORD>(bytes))) last_error();
        FILE_DISPOSITION_INFO_EX keep{FILE_DISPOSITION_FLAG_ON_CLOSE};
        if (!SetFileInformationByHandle(file.get(), FileDispositionInfoEx, &keep, sizeof(keep))) last_error();
        file.close();
        InterlockedExchange(operation.request.publication, WJL_SCREENSHOT_PUBLISHED);
    }
};
void save_window(const WJLScreenshotRequest& request, WJLScreenshotResult& result, const Operation& operation) {
    operation.check();
    const std::wstring path = output_path(request.output_path);
    ThreadDpiContext dpi;
    Identity identity(request);
    require_sdr(identity.bounds.monitor, operation);
    require(capture::GraphicsCaptureSession::IsSupported(), ERROR_NOT_SUPPORTED);
    CaptureLifetime lifetime;
    auto interop = winrt::get_activation_factory<capture::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    winrt::check_hresult(interop->CreateForWindow(identity.window, winrt::guid_of<capture::GraphicsCaptureItem>(), winrt::put_abi(lifetime.item)));
    const auto size = lifetime.item.Size();
    const auto crop = client_crop(identity.bounds, size.Width, size.Height);
    operation.check();
    winrt::com_ptr<ID3D11Device> device;
    winrt::com_ptr<ID3D11DeviceContext> context;
    const D3D_FEATURE_LEVEL levels[]{D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels, static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
    auto dxgi = device.as<IDXGIDevice>();
    winrt::com_ptr<IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    const auto projected = inspectable.as<d3d::IDirect3DDevice>();
    lifetime.pool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(projected,
        directx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
    lifetime.session = lifetime.pool.CreateCaptureSession(lifetime.item);
    lifetime.session.IsCursorCaptureEnabled(false);
    const std::weak_ptr<FrameState> weak = lifetime.state;
    lifetime.arrived = lifetime.pool.FrameArrived(winrt::auto_revoke, [weak](const auto&, const auto&) noexcept {
        if (const auto state = weak.lock()) {
            std::lock_guard<std::mutex> lock(state->mutex);
            if (state->ready && !state->closed) SetEvent(state->ready);
        }
    });
    lifetime.closed = lifetime.item.Closed(winrt::auto_revoke, [weak](const auto&, const auto&) noexcept {
        if (const auto state = weak.lock()) {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->closed = true;
            if (state->ready) SetEvent(state->ready);
        }
    });
    LARGE_INTEGER ticks{}, frequency{};
    require(QueryPerformanceCounter(&ticks) && QueryPerformanceFrequency(&frequency));
    const int64_t fresh_after = static_cast<int64_t>(static_cast<long double>(ticks.QuadPart) * 10000000 / frequency.QuadPart);
    operation.check(); identity.validate();
    lifetime.session.StartCapture();
    FrameLifetime accepted;
    HANDLE waits[]{request.cancel_event, lifetime.ready.get(), identity.process.get()};
    while (!accepted.value) {
        const DWORD waited = WaitForMultipleObjects(static_cast<DWORD>(std::size(waits)), waits, FALSE, operation.remaining());
        if (waited == WAIT_FAILED) last_error();
        require(waited == WAIT_OBJECT_0 + 1, waited == WAIT_TIMEOUT ? ERROR_TIMEOUT : waited == WAIT_OBJECT_0 ? ERROR_CANCELLED : ERROR_PROCESS_ABORTED);
        operation.check(); lifetime.check();
        FrameLifetime pending;
        pending.value = lifetime.pool.TryGetNextFrame();
        if (!pending.value) continue; // Only retry after another FrameArrived notification.
        if (pending.value.SystemRelativeTime().count() < fresh_after) continue;
        const auto content = pending.value.ContentSize();
        require(content.Width == size.Width && content.Height == size.Height, ERROR_RETRY);
        accepted.value = pending.value; pending.value = nullptr;
    }
    identity.validate();
    auto access = accepted.value.Surface().as<Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> surface;
    winrt::check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), surface.put_void()));
    D3D11_TEXTURE2D_DESC desc{}; surface->GetDesc(&desc);
    require(desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM && desc.SampleDesc.Count == 1 &&
            desc.Width >= static_cast<UINT>(size.Width) && desc.Height >= static_cast<UINT>(size.Height), ERROR_NOT_SUPPORTED);
    desc.Width = crop.width; desc.Height = crop.height; desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ; desc.MiscFlags = 0;
    winrt::com_ptr<ID3D11Texture2D> staging;
    winrt::check_hresult(device->CreateTexture2D(&desc, nullptr, staging.put()));
    const D3D11_BOX content{crop.left, crop.top, 0, crop.left + crop.width, crop.top + crop.height, 1};
    context->CopySubresourceRegion(staging.get(), 0, 0, 0, 0, surface.get(), 0, &content);
    D3D11_MAPPED_SUBRESOURCE pixels{};
    winrt::check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &pixels));
    MappedTexture mapped{context.get(), staging.get()};
    operation.check(); identity.validate(); lifetime.check();
    auto png = encode_png(crop.width, crop.height, pixels);
    operation.check(); identity.validate(); lifetime.check();
    require_sdr(identity.bounds.monitor, operation);
    accepted.value.Close(); accepted.value = nullptr;
    surface = nullptr; access = nullptr;
    lifetime.close();
    STATSTG status{}; winrt::check_hresult(png->Stat(&status, STATFLAG_NONAME));
    require(status.cbSize.QuadPart > 8 && status.cbSize.QuadPart <= 512ull * 1024 * 1024);
    LARGE_INTEGER beginning{}; winrt::check_hresult(png->Seek(beginning, STREAM_SEEK_SET, nullptr));
    ExclusiveOutput output(path);
    uint64_t remaining = status.cbSize.QuadPart;
    BYTE buffer[65536];
    while (remaining) {
        operation.check();
        const ULONG requested = static_cast<ULONG>(std::min<uint64_t>(sizeof(buffer), remaining));
        ULONG read = 0; winrt::check_hresult(png->Read(buffer, requested, &read));
        require(read == requested, ERROR_HANDLE_EOF);
        DWORD written = 0;
        if (!WriteFile(output.file.get(), buffer, read, &written, nullptr)) last_error();
        require(written == read, ERROR_WRITE_FAULT); remaining -= read;
    }
    if (!FlushFileBuffers(output.file.get())) last_error();
    operation.check(); identity.validate();
    require_sdr(identity.bounds.monitor, operation);
    output.publish(path, operation);
    result.width = crop.width; result.height = crop.height;
}
// WJ: the engine's DDS screenshot, converted to the PNG beside it.
uint32_t dds_word(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | (uint32_t(bytes[1]) << 8) | (uint32_t(bytes[2]) << 16) | (uint32_t(bytes[3]) << 24);
}
float dds_pq_nits(float encoded) {
    // SMPTE ST 2084 EOTF. PQ is absolute: normalized 1.0 means 10,000 nits.
    constexpr double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0;
    constexpr double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 128.0, c3 = 2392.0 / 128.0;
    const double power = std::pow(static_cast<double>(encoded), 1.0 / m2);
    return static_cast<float>(10000.0 * std::pow(std::max(power - c1, 0.0) / (c2 - c3 * power), 1.0 / m1));
}
using DdsColor = std::array<float, 3>;
using DdsMatrix = std::array<DdsColor, 3>;
DdsColor dds_multiply(const DdsMatrix& matrix, const DdsColor& color) {
    DdsColor value{};
    for (size_t i = 0; i < value.size(); ++i)
        value[i] = matrix[i][0] * color[0] + matrix[i][1] * color[1] + matrix[i][2] * color[2];
    return value;
}
void dds_native_sdr(float r, float g, float b, uint8_t& red, uint8_t& green, uint8_t& blue) {
    // The game's SDR final compositor converts the already tone-mapped PQ scene with
    // these exact float32 constants (aaac81ae5fbabc7c-ace8 final-compositor DXBC).
    constexpr DdsMatrix pre{{
        {{0.9599400162696838F, 0.010470000095665455F, 0.007029999978840351F}},
        {{0.0016199999954551458F, 0.9996899962425232F, 0.0014900000533089042F}},
        {{0.005289999768137932F, 0.023830000311136246F, 1.0501600503921509F}}
    }};
    constexpr DdsMatrix xyz{{
        {{0.6624541878700256F, 0.13400420546531677F, 0.15618768334388733F}},
        {{0.2722287178039551F, 0.6740817427635193F, 0.053689517080783844F}},
        {{-0.005574649665504694F, 0.00406073359772563F, 1.0103391408920288F}}
    }};
    constexpr DdsMatrix adapt{{
        {{1.6410233974456787F, -0.32480329275131226F, -0.23642469942569733F}},
        {{-0.663662850856781F, 1.6153316497802734F, 0.016756348311901093F}},
        {{0.011721894145011902F, -0.008284442126750946F, 0.9883948564529419F}}
    }};
    constexpr DdsMatrix rgb{{
        {{3.2409698963165283F, -1.5373831987380981F, -0.4986107647418976F}},
        {{-0.9692436456680298F, 1.8759675025939941F, 0.04155505821108818F}},
        {{0.05563008040189743F, -0.20397695899009705F, 1.056971549987793F}}
    }};
    DdsColor value = dds_multiply(pre, DdsColor{{r, g, b}});
    for (float& channel : value) channel = (channel - 0.001F) * 0.0036363769322633743F;
    value = dds_multiply(xyz, value);
    const float sum = std::max(value[0] + value[1] + value[2], 0.0001F);
    const float x = value[0] / sum, y = value[1] / sum;
    const float luminance = std::pow(std::clamp(value[1], 0.0F, 65504.0F), 0.9811000227928162F);
    const float ratio = luminance / std::max(y, 0.0001F);
    value = DdsColor{{ratio * x, luminance, ratio * (1.0F - x - y)}};
    value = dds_multiply(rgb, dds_multiply(xyz, dds_multiply(adapt, value)));
    auto byte = [](float channel) {
        return static_cast<uint8_t>(std::floor(std::pow(std::clamp(channel, 0.0F, 1.0F), 0.4544999897480011F) * 255.0F + 0.5F));
    };
    red = byte(value[0]); green = byte(value[1]); blue = byte(value[2]);
}
std::wstring dds_sibling(const std::wstring& png) { return png.substr(0, png.size() - 4) + L".dds"; }
bool dds_present(const wchar_t* png) {
    if (!png) return false;
    const std::wstring path(png);
    if (path.size() < 5 || _wcsicmp(path.c_str() + path.size() - 4, L".png")) return false;
    const DWORD attributes = GetFileAttributesW(dds_sibling(path).c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
}
void dds_read(HANDLE file, void* buffer, DWORD count) {
    DWORD read = 0;
    if (!ReadFile(file, buffer, count, &read, nullptr)) last_error();
    require(read == count, ERROR_HANDLE_EOF);
}
void convert_dds(const WJLScreenshotRequest& request, WJLScreenshotResult& result, const Operation& operation) {
    operation.check();
    const std::wstring path = output_path(request.output_path);
    const HANDLE opened = CreateFileW(dds_sibling(path).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                      FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (opened == INVALID_HANDLE_VALUE) last_error();
    winrt::handle input{opened};
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(input.get(), &size)) last_error();
    uint8_t header[148]{};
    require(size.QuadPart >= 148, ERROR_BAD_FORMAT);
    dds_read(input.get(), header, 148);
    const uint32_t flags = dds_word(header + 8), height = dds_word(header + 12), width = dds_word(header + 16);
    require(dds_word(header) == 0x20534444 && dds_word(header + 4) == 124 && (flags & 0x1007) == 0x1007 &&
            dds_word(header + 76) == 32 && (dds_word(header + 80) & 4) && dds_word(header + 84) == 0x30315844 &&
            width && height && width <= 16384 && height <= 16384 && uint64_t(width) * height <= kMaxPixels &&
            dds_word(header + 24) <= 1 && dds_word(header + 28) <= 1 && !(dds_word(header + 112) & 0x20fe00) &&
            dds_word(header + 132) == 3 && !(dds_word(header + 136) & 4) && dds_word(header + 140) == 1, ERROR_BAD_FORMAT);
    uint32_t format = dds_word(header + 128);
    switch (format) {
    case 27: format = 28; break; case 90: format = 87; break; case 92: format = 88; break; case 23: format = 24; break;
    default: break;
    }
    // The engine writes SDR as BGRA bytes, labelled 87 once War Journalist corrected the
    // header, or 28 (its own label) when it could not; HDR as RGB10A2 HDR10 (PQ, BT.2020).
    require(format == 87 || format == 88 || format == 91 || format == 93 || format == 28 || format == 29 || format == 24,
            ERROR_NOT_SUPPORTED);
    const uint32_t pitch = (flags & 8) ? dds_word(header + 20) : width * 4;
    require(pitch >= width * 4 && pitch <= 16384u * 4 + 4096 &&
            uint64_t(pitch) * height + 148 <= static_cast<uint64_t>(size.QuadPart), ERROR_BAD_FORMAT);
    std::array<float, 1024> pq{};
    if (format == 24) for (size_t i = 0; i < pq.size(); ++i) pq[i] = dds_pq_nits(static_cast<float>(i) / 1023.0F);
    std::vector<uint8_t> source(pitch), pixels(size_t(width) * height * 4);
    for (uint32_t row = 0; row < height; ++row) {
        if (!(row & 63)) operation.check();
        dds_read(input.get(), source.data(), pitch);
        uint8_t* out = pixels.data() + size_t(row) * width * 4;
        for (uint32_t column = 0; column < width; ++column) {
            const uint8_t* in = source.data() + size_t(column) * 4;
            uint8_t red, green, blue;
            if (format == 24) {
                const uint32_t packed = dds_word(in);
                dds_native_sdr(pq[packed & 1023], pq[(packed >> 10) & 1023], pq[(packed >> 20) & 1023], red, green, blue);
            } else { blue = in[0]; green = in[1]; red = in[2]; }
            out[size_t(column) * 4] = blue; out[size_t(column) * 4 + 1] = green;
            out[size_t(column) * 4 + 2] = red; out[size_t(column) * 4 + 3] = 255;
        }
    }
    input.close();
    D3D11_MAPPED_SUBRESOURCE mapped{};
    mapped.pData = pixels.data(); mapped.RowPitch = width * 4;
    operation.check();
    auto png = encode_png(width, height, mapped);
    STATSTG status{}; winrt::check_hresult(png->Stat(&status, STATFLAG_NONAME));
    require(status.cbSize.QuadPart > 8 && status.cbSize.QuadPart <= 512ull * 1024 * 1024);
    LARGE_INTEGER beginning{}; winrt::check_hresult(png->Seek(beginning, STREAM_SEEK_SET, nullptr));
    ExclusiveOutput output(path);
    uint64_t remaining = status.cbSize.QuadPart;
    std::vector<BYTE> buffer(65536);
    while (remaining) {
        operation.check();
        const ULONG requested = static_cast<ULONG>(std::min<uint64_t>(buffer.size(), remaining));
        ULONG read = 0; winrt::check_hresult(png->Read(buffer.data(), requested, &read));
        require(read == requested, ERROR_HANDLE_EOF);
        DWORD written = 0;
        if (!WriteFile(output.file.get(), buffer.data(), read, &written, nullptr)) last_error();
        require(written == read, ERROR_WRITE_FAULT); remaining -= read;
    }
    if (!FlushFileBuffers(output.file.get())) last_error();
    output.publish(path, operation);
    result.width = width; result.height = height;
}
} // namespace

extern "C" DWORD wjl_steam_screenshot_capture(const WJLScreenshotRequest* request, WJLScreenshotResult* result) {
    if (!result) return ERROR_INVALID_PARAMETER;
    *result = {};
    const ULONGLONG begun = GetTickCount64();
    try {
        require(request && request->pid && request->executable && *request->executable && request->output_path &&
                *request->output_path && request->cancel_event && request->publication, ERROR_INVALID_PARAMETER);
        const Operation operation{*request};
        operation.check();
        Apartment apartment;
        if (dds_present(request->output_path)) {
            const Operation conversion{*request, GetTickCount64(), kConvertMs};
            convert_dds(*request, *result, conversion);
        } else save_window(*request, *result, operation);
    } catch (const winrt::hresult_error& error) { result->error = static_cast<uint32_t>(error.code().value); }
      catch (const std::bad_alloc&) { result->error = static_cast<uint32_t>(E_OUTOFMEMORY); }
      catch (...) { result->error = static_cast<uint32_t>(E_FAIL); }
    result->elapsed_ms = static_cast<uint32_t>(std::min<ULONGLONG>(GetTickCount64() - begun, MAXDWORD));
    return result->error;
}

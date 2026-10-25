// Standalone, one-shot WGC game-window capture proof. Never loaded by the game.
// SDR BGRA8 only; HDR capture/transfer is intentionally not qualified here.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
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
#include <cstdint>
#include <cstdio>
#include <cstddef>
#include <cmath>
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
constexpr DWORD kFrameWaitMs = 5000;
constexpr uint64_t kMaxPixels = 64ull * 1024 * 1024;

void require(bool value, const wchar_t* message) {
    if (!value) throw winrt::hresult_error(E_FAIL, message);
}
void last_error(const wchar_t* message) {
    throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()), message);
}
std::string json_string(const std::wstring& value) {
    const std::string utf8 = winrt::to_string(value);
    std::string result = "\"";
    for (unsigned char c : utf8) {
        if (c == '"' || c == '\\') { result += '\\'; result += static_cast<char>(c); }
        else if (c < 32) {
            char escaped[7]; sprintf_s(escaped, "\\u%04x", static_cast<unsigned>(c)); result += escaped;
        } else result += static_cast<char>(c);
    }
    return result + '"';
}
DWORD parse_pid(const wchar_t* text) {
    require(text && *text, L"Explicit positive --pid is required");
    uint64_t value = 0;
    for (const wchar_t* p = text; *p; ++p) {
        require(*p >= L'0' && *p <= L'9', L"PID must contain decimal digits only");
        value = value * 10 + static_cast<unsigned>(*p - L'0');
        require(value <= MAXDWORD, L"PID is out of range");
    }
    require(value != 0, L"PID must be positive");
    return static_cast<DWORD>(value);
}
std::wstring output_path(const wchar_t* text) {
    const std::filesystem::path path(text);
    require(path.is_absolute() && _wcsicmp(path.extension().c_str(), L".png") == 0,
            L"Output must be an absolute .png path");
    const std::wstring raw = path.native();
    const auto colon = raw.find(L':');
    require(colon == std::wstring::npos || (colon == 1 && raw.find(L':', 2) == std::wstring::npos),
            L"Alternate data streams are not supported");
    require(std::filesystem::is_directory(path.parent_path()), L"Output parent directory must already exist");
    return path.lexically_normal().native();
}

struct WindowSearch { DWORD pid; HWND window = nullptr; unsigned count = 0; bool unreadable = false; };
BOOL CALLBACK eligible_window(HWND window, LPARAM parameter) {
    auto& result = *reinterpret_cast<WindowSearch*>(parameter);
    DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
    if (pid != result.pid || !IsWindowVisible(window) || IsIconic(window)) return TRUE;
    DWORD cloaked = 0;
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked)))) {
        result.unreadable = true; return TRUE;
    }
    if (cloaked) return TRUE;
    result.window = window; ++result.count;
    return TRUE;
}
HWND unique_window(DWORD pid) {
    WindowSearch result{pid};
    require(EnumWindows(eligible_window, reinterpret_cast<LPARAM>(&result)) != FALSE, L"Window enumeration failed");
    require(!result.unreadable && result.count == 1,
            L"PID must own exactly one verified visible, non-minimized top-level window");
    return result.window;
}
struct ThreadDpiContext {
    DPI_AWARENESS_CONTEXT previous = nullptr;
    ThreadDpiContext() {
        previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        if (!previous) last_error(L"Cannot set helper thread DPI awareness");
    }
    ~ThreadDpiContext() { if (previous) SetThreadDpiAwarenessContext(previous); }
    ThreadDpiContext(const ThreadDpiContext&) = delete;
    ThreadDpiContext& operator=(const ThreadDpiContext&) = delete;
};
int64_t rect_width(const RECT& rect) { return static_cast<int64_t>(rect.right) - rect.left; }
int64_t rect_height(const RECT& rect) { return static_cast<int64_t>(rect.bottom) - rect.top; }
struct WindowGeometry {
    RECT window{}, client{}, dwm{};
    bool has_dwm = false;
    HRESULT dwm_result = E_FAIL;
    HMONITOR monitor = nullptr;
    UINT window_dpi = 0;
};
WindowGeometry window_geometry(HWND window) {
    WindowGeometry result;
    RECT client{};
    require(GetWindowRect(window, &result.window) && GetClientRect(window, &client), L"Cannot read physical window bounds");
    POINT first{client.left, client.top}, last{client.right, client.bottom};
    require(ClientToScreen(window, &first) && ClientToScreen(window, &last), L"Cannot read physical client bounds");
    result.client = {first.x, first.y, last.x, last.y};
    require(rect_width(result.window) > 0 && rect_height(result.window) > 0 &&
            rect_width(result.client) > 0 && rect_height(result.client) > 0, L"Window or client bounds are empty");
    result.dwm_result = DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &result.dwm, sizeof(result.dwm));
    result.has_dwm = SUCCEEDED(result.dwm_result) && rect_width(result.dwm) > 0 && rect_height(result.dwm) > 0;
    result.monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
    result.window_dpi = GetDpiForWindow(window); // Metadata only; never rescale physical coordinates.
    return result;
}
struct ClientCrop {
    UINT left, top, width, height;
    RECT frame;
    const char* basis;
};
ClientCrop client_crop(const WindowGeometry& geometry, int64_t width, int64_t height) {
    require(width > 0 && height > 0 && width <= 16384 && height <= 16384, L"Capture dimensions are out of bounds");
    const bool window_matches = rect_width(geometry.window) == width && rect_height(geometry.window) == height;
    const bool dwm_matches = geometry.has_dwm && rect_width(geometry.dwm) == width && rect_height(geometry.dwm) == height;
    require(window_matches || dwm_matches, L"WGC item size matches neither physical window nor DWM frame bounds");
    require(!(window_matches && dwm_matches) || EqualRect(&geometry.window, &geometry.dwm),
            L"WGC frame origin is ambiguous between physical window and DWM bounds");
    const RECT frame = dwm_matches ? geometry.dwm : geometry.window;
    const RECT client = geometry.client;
    require(rect_width(client) > 0 && rect_height(client) > 0 && client.left >= frame.left && client.top >= frame.top &&
            client.right <= frame.right && client.bottom <= frame.bottom, L"Physical client bounds are outside the captured frame");
    return {static_cast<UINT>(static_cast<int64_t>(client.left) - frame.left),
            static_cast<UINT>(static_cast<int64_t>(client.top) - frame.top),
            static_cast<UINT>(rect_width(client)), static_cast<UINT>(rect_height(client)), frame,
            dwm_matches ? (window_matches ? "identical DWM/window bounds" : "DWM extended frame bounds") : "physical window bounds"};
}
struct Identity {
    DWORD pid, thread;
    winrt::handle process;
    HWND window;
    FILETIME created{};
    WindowGeometry geometry;
    std::wstring executable;
    explicit Identity(DWORD value) : pid(value), thread(0), window(nullptr) {
        process.attach(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
        if (!process) last_error(L"Cannot query the explicitly selected process");
        wchar_t image[32768]; DWORD length = static_cast<DWORD>(std::size(image));
        if (!QueryFullProcessImageNameW(process.get(), 0, image, &length)) last_error(L"Cannot identify process image");
        executable.assign(image, length);
        require(_wcsicmp(std::filesystem::path(executable).filename().c_str(), L"helldivers2.exe") == 0,
                L"Selected PID is not helldivers2.exe");
        FILETIME exited{}, kernel{}, user{};
        if (!GetProcessTimes(process.get(), &created, &exited, &kernel, &user)) last_error(L"Cannot identify process creation");
        window = unique_window(pid);
        DWORD owner = 0; thread = GetWindowThreadProcessId(window, &owner);
        require(thread != 0 && owner == pid, L"Cannot identify game window");
        geometry = window_geometry(window);
        validate();
    }
    void validate() const {
        require(WaitForSingleObject(process.get(), 0) == WAIT_TIMEOUT, L"Selected process ended");
        FILETIME birth{}, exited{}, kernel{}, user{};
        require(GetProcessTimes(process.get(), &birth, &exited, &kernel, &user) &&
                CompareFileTime(&birth, &created) == 0, L"Process identity changed");
        DWORD owner = 0;
        require(IsWindow(window) && GetWindowThreadProcessId(window, &owner) == thread && owner == pid &&
                unique_window(pid) == window, L"Game window identity changed");
        const auto current = window_geometry(window);
        require(EqualRect(&geometry.window, &current.window) && EqualRect(&geometry.client, &current.client) &&
                geometry.has_dwm == current.has_dwm && (!geometry.has_dwm || EqualRect(&geometry.dwm, &current.dwm)) &&
                geometry.monitor == current.monitor && geometry.window_dpi == current.window_dpi,
                L"Game window bounds, DPI or monitor changed during operation");
    }
};

std::string rect_json(const RECT& rect) {
    char text[160]; sprintf_s(text, "{\"left\":%ld,\"top\":%ld,\"right\":%ld,\"bottom\":%ld,\"width\":%lld,\"height\":%lld}",
                             rect.left, rect.top, rect.right, rect.bottom, rect_width(rect), rect_height(rect));
    return text;
}
std::string geometry_json(const WindowGeometry& geometry) {
    char values[180]; sprintf_s(values, ",\"dwm_hresult\":\"0x%08x\",\"window_dpi\":%u,\"hmonitor\":\"0x%llx\"}",
        static_cast<unsigned>(geometry.dwm_result), geometry.window_dpi,
        static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(geometry.monitor)));
    return "{\"coordinate_units\":\"physical pixels\",\"helper_thread_dpi\":\"per-monitor-v2\",\"window_bounds\":" +
        rect_json(geometry.window) + ",\"client_screen_bounds\":" + rect_json(geometry.client) + ",\"dwm_extended_frame_bounds\":" +
        (geometry.has_dwm ? rect_json(geometry.dwm) : "null") + values;
}
struct DisplayColor {
    DXGI_OUTPUT_DESC1 description{};
    HRESULT result = E_FAIL;
    bool available = false;
    const char* reason = "matching monitor output unavailable";
};
DisplayColor display_color(HMONITOR monitor) {
    DisplayColor result;
    if (!monitor) { result.reason = "window has no intersecting monitor"; return result; }
    winrt::com_ptr<IDXGIFactory1> factory;
    result.result = CreateDXGIFactory1(__uuidof(IDXGIFactory1), factory.put_void());
    if (FAILED(result.result)) { result.reason = "DXGI factory unavailable"; return result; }
    unsigned matched = 0;
    for (UINT adapter_index = 0; adapter_index < 64; ++adapter_index) {
        winrt::com_ptr<IDXGIAdapter1> adapter;
        const HRESULT adapter_result = factory->EnumAdapters1(adapter_index, adapter.put());
        if (adapter_result == DXGI_ERROR_NOT_FOUND) {
            if (matched == 1 && result.available && factory->IsCurrent()) return result;
            result.available = false;
            if (matched > 1) result.reason = "multiple outputs matched the monitor";
            else if (matched == 1 && !factory->IsCurrent()) result.reason = "display configuration changed during query";
            return result;
        }
        if (FAILED(adapter_result)) { result.result = adapter_result; result.available = false; return result; }
        bool finished = false;
        for (UINT output_index = 0; output_index < 64; ++output_index) {
            winrt::com_ptr<IDXGIOutput> output;
            const HRESULT output_result = adapter->EnumOutputs(output_index, output.put());
            if (output_result == DXGI_ERROR_NOT_FOUND) { finished = true; break; }
            if (FAILED(output_result)) { result.result = output_result; result.available = false; return result; }
            DXGI_OUTPUT_DESC basic{};
            const HRESULT basic_result = output->GetDesc(&basic);
            if (FAILED(basic_result)) { result.result = basic_result; result.available = false; return result; }
            if (basic.Monitor != monitor) continue;
            ++matched;
            auto extended = output.try_as<IDXGIOutput6>();
            if (!extended) { result.result = E_NOINTERFACE; result.reason = "IDXGIOutput6 unavailable"; continue; }
            result.result = extended->GetDesc1(&result.description);
            result.available = SUCCEEDED(result.result) && result.description.Monitor == monitor && result.description.AttachedToDesktop;
            result.reason = result.available ? "OS-reported output metadata; capture pixel encoding is unqualified" : "GetDesc1 unavailable or output detached";
        }
        if (!finished) { result.available = false; result.reason = "DXGI output enumeration exceeded bound"; return result; }
    }
    result.available = false; result.reason = "DXGI adapter enumeration exceeded bound"; return result;
}
std::string finite_json(float value) {
    if (!std::isfinite(value)) return "null";
    char text[48]; sprintf_s(text, "%.9g", static_cast<double>(value)); return text;
}
std::string display_color_json(const DisplayColor& color) {
    char result[64]; sprintf_s(result, ",\"hresult\":\"0x%08x\"", static_cast<unsigned>(color.result));
    std::string text = std::string("{\"available\":") + (color.available ? "true" : "false") + result +
        ",\"source\":\"IDXGIOutput6::GetDesc1 matched HMONITOR\",\"note\":" + json_string(winrt::to_hstring(color.reason).c_str());
    if (!color.available) return text + ",\"status\":\"unknown\"}";
    const auto& desc = color.description;
    const char* status = desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709 ? "reported SDR/sRGB" :
        (desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020 ? "reported advanced color PQ/Rec2020" : "reported other color space");
    char values[144]; sprintf_s(values, ",\"bits_per_color\":%u,\"color_space_value\":%u,\"rotation\":%u",
                               desc.BitsPerColor, static_cast<unsigned>(desc.ColorSpace), static_cast<unsigned>(desc.Rotation));
    return text + ",\"status\":" + json_string(winrt::to_hstring(status).c_str()) + values +
        ",\"device\":" + json_string(desc.DeviceName) + ",\"desktop_bounds\":" + rect_json(desc.DesktopCoordinates) +
        ",\"red_primary\":[" + finite_json(desc.RedPrimary[0]) + "," + finite_json(desc.RedPrimary[1]) +
        "],\"green_primary\":[" + finite_json(desc.GreenPrimary[0]) + "," + finite_json(desc.GreenPrimary[1]) +
        "],\"blue_primary\":[" + finite_json(desc.BluePrimary[0]) + "," + finite_json(desc.BluePrimary[1]) +
        "],\"white_point\":[" + finite_json(desc.WhitePoint[0]) + "," + finite_json(desc.WhitePoint[1]) +
        "],\"min_luminance_nits\":" + finite_json(desc.MinLuminance) + ",\"max_luminance_nits\":" + finite_json(desc.MaxLuminance) +
        ",\"max_full_frame_luminance_nits\":" + finite_json(desc.MaxFullFrameLuminance) + "}";
}
void inspect_window(DWORD pid) {
    Identity identity(pid);
    const auto color = display_color(identity.geometry.monitor);
    identity.validate();
    printf("{\"ok\":true,\"mode\":\"inspect\",\"capture_executed\":false,\"pid\":%lu,\"hwnd\":\"0x%llx\","
           "\"process_created_filetime\":\"%08lx%08lx\",\"executable\":%s,\"window_metadata\":%s,\"display_color\":%s}\n",
           pid, static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(identity.window)),
           identity.created.dwHighDateTime, identity.created.dwLowDateTime, json_string(identity.executable).c_str(),
           geometry_json(identity.geometry).c_str(), display_color_json(color).c_str());
}

struct FrameState {
    std::mutex mutex;
    winrt::handle ready{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    capture::Direct3D11CaptureFrame frame{nullptr};
    int64_t fresh_after = 0;
    HRESULT failure = S_OK;
    bool closed = false;
    ~FrameState() { if (frame) { try { frame.Close(); } catch (...) {} } }
};
struct CaptureLifetime {
    capture::Direct3D11CaptureFramePool pool{nullptr};
    capture::GraphicsCaptureSession session{nullptr};
    ~CaptureLifetime() {
        if (session) { try { session.Close(); } catch (...) {} }
        if (pool) { try { pool.Close(); } catch (...) {} }
    }
};
struct FrameLifetime {
    capture::Direct3D11CaptureFrame frame{nullptr};
    ~FrameLifetime() { if (frame) { try { frame.Close(); } catch (...) {} } }
};
struct MappedTexture {
    ID3D11DeviceContext* context;
    ID3D11Texture2D* texture;
    ~MappedTexture() { context->Unmap(texture, 0); }
};
void require_open(const std::shared_ptr<FrameState>& state) {
    std::lock_guard<std::mutex> lock(state->mutex);
    require(!state->closed, L"Capture item closed");
    winrt::check_hresult(state->failure);
}

winrt::com_ptr<IStream> encode_png(UINT width, UINT height, const D3D11_MAPPED_SUBRESOURCE& pixels) {
    require(pixels.RowPitch >= width * 4 && static_cast<uint64_t>(pixels.RowPitch) * height <= MAXDWORD,
            L"Capture row pitch exceeds encoder bounds");
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
    require(IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA), L"PNG encoder refused BGRA8");
    winrt::check_hresult(image->WritePixels(height, pixels.RowPitch, pixels.RowPitch * height,
                                          static_cast<BYTE*>(pixels.pData)));
    winrt::check_hresult(image->Commit());
    winrt::check_hresult(encoder->Commit());
    return stream;
}
struct ExclusiveOutput {
    winrt::handle file;
    explicit ExclusiveOutput(const std::wstring& path) {
        GUID unique{}; winrt::check_hresult(CoCreateGuid(&unique));
        wchar_t name[40]; require(StringFromGUID2(unique, name, static_cast<int>(std::size(name))) != 0,
                                  L"Cannot name temporary PNG output");
        const auto temporary = std::filesystem::path(path).parent_path() /
            (std::wstring(L".dbf-window-capture-") + name + L".tmp");
        // Kernel-owned cleanup also runs when Python terminates this process.
        HANDLE created = CreateFileW(temporary.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
                                     FILE_ATTRIBUTE_NORMAL | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
        if (created == INVALID_HANDLE_VALUE) last_error(L"Cannot exclusively create temporary PNG output");
        file.attach(created);
    }
    void publish(const std::wstring& path) {
        const size_t bytes = sizeof(FILE_RENAME_INFO) + path.size() * sizeof(wchar_t);
        require(bytes <= MAXDWORD, L"Output path exceeds rename bounds");
        std::vector<BYTE> storage(bytes, 0);
        auto* rename = reinterpret_cast<FILE_RENAME_INFO*>(storage.data());
        rename->ReplaceIfExists = FALSE;
        rename->FileNameLength = static_cast<DWORD>(path.size() * sizeof(wchar_t));
        std::copy(path.begin(), path.end(), rename->FileName);
        // Same-directory handle rename publishes only completed, flushed bytes.
        // Keep delete-on-close armed until rename succeeds; never replace a target.
        if (!SetFileInformationByHandle(file.get(), FileRenameInfo, rename, static_cast<DWORD>(bytes)))
            last_error(L"Cannot publish PNG output; existing files are never replaced");
        // FILE_DISPOSITION_INFO cannot clear a CreateFile DELETE_ON_CLOSE flag.
        // The extended ON_CLOSE operation without DELETE clears it after commit.
        FILE_DISPOSITION_INFO_EX keep{FILE_DISPOSITION_FLAG_ON_CLOSE};
        if (!SetFileInformationByHandle(file.get(), FileDispositionInfoEx, &keep, sizeof(keep)))
            last_error(L"Cannot retain completed PNG output");
        file.close();
    }
};

void save_window(DWORD pid, const std::wstring& path) {
    Identity identity(pid);
    const auto color = display_color(identity.geometry.monitor);
    require(capture::GraphicsCaptureSession::IsSupported(), L"Windows Graphics Capture is unavailable");
    auto interop = winrt::get_activation_factory<capture::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    capture::GraphicsCaptureItem item{nullptr};
    winrt::check_hresult(interop->CreateForWindow(identity.window, winrt::guid_of<capture::GraphicsCaptureItem>(),
                                                 winrt::put_abi(item)));
    const auto size = item.Size();
    require(size.Width > 0 && size.Height > 0 && size.Width <= 16384 && size.Height <= 16384 &&
            static_cast<uint64_t>(size.Width) * size.Height <= kMaxPixels, L"Capture dimensions are out of bounds");
    const auto crop = client_crop(identity.geometry, size.Width, size.Height);
    winrt::com_ptr<ID3D11Device> device;
    winrt::com_ptr<ID3D11DeviceContext> context;
    const D3D_FEATURE_LEVEL levels[]{D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                                         levels, static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION,
                                         device.put(), nullptr, context.put()));
    auto dxgi = device.as<IDXGIDevice>();
    winrt::com_ptr<IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    const auto projected_device = inspectable.as<d3d::IDirect3DDevice>();
    CaptureLifetime lifetime;
    lifetime.pool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
        projected_device, directx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
    lifetime.session = lifetime.pool.CreateCaptureSession(item);
    // This property changes only captured pixels, never the system cursor state.
    lifetime.session.IsCursorCaptureEnabled(false);
    // Keep the system capture border at its default; do not request borderless access.
    auto state = std::make_shared<FrameState>();
    if (!state->ready) last_error(L"Cannot create frame-arrival event");
    LARGE_INTEGER ticks{}, frequency{};
    require(QueryPerformanceCounter(&ticks) && QueryPerformanceFrequency(&frequency), L"Capture clock unavailable");
    state->fresh_after = static_cast<int64_t>(static_cast<long double>(ticks.QuadPart) * 10000000 / frequency.QuadPart);
    auto arrived = lifetime.pool.FrameArrived(winrt::auto_revoke,
        [state, size](const capture::Direct3D11CaptureFramePool& sender, const auto&) noexcept {
            try {
                std::lock_guard<std::mutex> lock(state->mutex);
                if (state->frame || FAILED(state->failure) || state->closed) return;
                auto frame = sender.TryGetNextFrame();
                if (!frame) return;
                if (frame.SystemRelativeTime().count() < state->fresh_after) { frame.Close(); return; }
                const auto content = frame.ContentSize();
                if (content.Width != size.Width || content.Height != size.Height) {
                    frame.Close(); state->failure = E_BOUNDS;
                } else state->frame = frame;
                SetEvent(state->ready.get());
            } catch (...) {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->failure = winrt::to_hresult(); SetEvent(state->ready.get());
            }
        });
    auto closed = item.Closed(winrt::auto_revoke, [state](const auto&, const auto&) noexcept {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->closed = true; SetEvent(state->ready.get());
    });
    identity.validate();
    lifetime.session.StartCapture();
    HANDLE waits[]{state->ready.get(), identity.process.get()};
    const DWORD waited = WaitForMultipleObjects(static_cast<DWORD>(std::size(waits)), waits, FALSE, kFrameWaitMs);
    require(waited == WAIT_OBJECT_0, waited == WAIT_TIMEOUT ? L"No fresh game-window frame arrived within five seconds" :
            L"Game process ended or frame wait failed");
    identity.validate(); require_open(state);
    FrameLifetime accepted;
    { std::lock_guard<std::mutex> lock(state->mutex); accepted.frame = state->frame; state->frame = nullptr; }
    require(accepted.frame != nullptr, L"Frame event delivered no image");
    auto access = accepted.frame.Surface().as<Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> surface;
    winrt::check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), surface.put_void()));
    D3D11_TEXTURE2D_DESC description{}; surface->GetDesc(&description);
    require(description.Format == DXGI_FORMAT_B8G8R8A8_UNORM && description.SampleDesc.Count == 1 &&
            description.Width >= static_cast<UINT>(size.Width) && description.Height >= static_cast<UINT>(size.Height),
            L"Capture surface format or content bounds changed");
    description.Width = crop.width; description.Height = crop.height;
    description.MipLevels = 1; description.ArraySize = 1; description.Usage = D3D11_USAGE_STAGING;
    description.BindFlags = 0; description.CPUAccessFlags = D3D11_CPU_ACCESS_READ; description.MiscFlags = 0;
    winrt::com_ptr<ID3D11Texture2D> staging;
    winrt::check_hresult(device->CreateTexture2D(&description, nullptr, staging.put()));
    const D3D11_BOX content{crop.left, crop.top, 0, crop.left + crop.width, crop.top + crop.height, 1};
    context->CopySubresourceRegion(staging.get(), 0, 0, 0, 0, surface.get(), 0, &content);
    D3D11_MAPPED_SUBRESOURCE pixels{};
    winrt::check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &pixels));
    MappedTexture mapped{context.get(), staging.get()};
    auto png = encode_png(description.Width, description.Height, pixels);
    identity.validate(); require_open(state);
    STATSTG status{}; winrt::check_hresult(png->Stat(&status, STATFLAG_NONAME));
    require(status.cbSize.QuadPart > 8 && status.cbSize.QuadPart <= 512ull * 1024 * 1024, L"Encoded PNG size invalid");
    LARGE_INTEGER beginning{}; winrt::check_hresult(png->Seek(beginning, STREAM_SEEK_SET, nullptr));
    ExclusiveOutput output(path);
    uint64_t remaining = status.cbSize.QuadPart;
    BYTE buffer[65536];
    while (remaining) {
        const ULONG requested = static_cast<ULONG>(std::min<uint64_t>(sizeof(buffer), remaining));
        ULONG read = 0; winrt::check_hresult(png->Read(buffer, requested, &read));
        require(read == requested, L"Encoded PNG stream was truncated");
        DWORD written = 0;
        if (!WriteFile(output.file.get(), buffer, read, &written, nullptr)) last_error(L"PNG output write failed");
        require(written == read, L"PNG output write was incomplete"); remaining -= read;
    }
    if (!FlushFileBuffers(output.file.get())) last_error(L"PNG output flush failed");
    identity.validate(); require_open(state);
    output.publish(path);
    printf("{\"ok\":true,\"mode\":\"capture\",\"capture_executed\":true,\"pid\":%lu,\"hwnd\":\"0x%llx\",\"width\":%u,\"height\":%u,"
           "\"format\":\"BGRA8_UNORM\",\"color\":\"SDR prototype; HDR not qualified\","
           "\"capture\":\"WGC CreateForWindow\",\"cursor_in_image\":false,\"system_border\":\"default\","
           "\"process_created_filetime\":\"%08lx%08lx\",\"executable\":%s,\"output\":%s,"
           "\"item_width\":%d,\"item_height\":%d,\"crop\":{\"left\":%u,\"top\":%u,\"width\":%u,\"height\":%u,\"frame_basis\":%s},"
           "\"window_metadata\":%s,\"display_color\":%s}\n",
           pid, static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(identity.window)),
           description.Width, description.Height, identity.created.dwHighDateTime, identity.created.dwLowDateTime,
           json_string(identity.executable).c_str(), json_string(path).c_str(), size.Width, size.Height,
           crop.left, crop.top, crop.width, crop.height, json_string(winrt::to_hstring(crop.basis).c_str()).c_str(),
           geometry_json(identity.geometry).c_str(), display_color_json(color).c_str());
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc == 4 && wcscmp(argv[1], L"--inspect") == 0 && wcscmp(argv[2], L"--pid") == 0) {
            const DWORD pid = parse_pid(argv[3]);
            ThreadDpiContext dpi;
            inspect_window(pid);
            return 0;
        }
        require(argc == 5 && wcscmp(argv[1], L"--pid") == 0 && wcscmp(argv[3], L"--output") == 0,
                L"Usage: window_capture.exe --inspect --pid N | --pid N --output ABSOLUTE.png");
        const DWORD pid = parse_pid(argv[2]);
        const std::wstring path = output_path(argv[4]);
        ThreadDpiContext dpi;
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        save_window(pid, path);
        return 0;
    } catch (const winrt::hresult_error& error) {
        printf("{\"ok\":false,\"error\":%s,\"hresult\":\"0x%08x\"}\n",
               json_string(error.message().c_str()).c_str(), static_cast<unsigned>(error.code().value));
    } catch (const std::exception& error) {
        printf("{\"ok\":false,\"error\":%s}\n", json_string(winrt::to_hstring(error.what()).c_str()).c_str());
    }
    return 1;
}

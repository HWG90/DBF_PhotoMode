/* Optional pointer input for the external Steam service. This code runs only
 * in the service process: it never opens another process, installs a hook,
 * injects input, changes focus, or changes the game's RawInput registration.
 * Call start only while a frontend or camera owns its input lease; release on
 * lease end, focus loss, disconnect and shutdown. Coordinates use client top-left.
 * Include this file in the service and link user32.lib. */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <limits.h>
#include <string.h>

typedef struct WJLSteamPointerSnapshot {
    int32_t valid, x, y, width, height, buttons, wheel;
} WJLSteamPointerSnapshot;

/* Versioned extended sample. Keep the legacy seven-integer layout above. */
typedef struct WJLSteamPointerSample {
    int32_t valid, x, y, width, height, buttons, wheel, dx, dy;
} WJLSteamPointerSample;

typedef struct WJLSteamPointerMotion {
    int32_t wheel, dx, dy;
} WJLSteamPointerMotion;

typedef struct WJLSteamPointerState {
    HANDLE thread, ready, stop;
    HWND window;
    DWORD pid;
    LONG active;
    WJLSteamPointerMotion motion;
} WJLSteamPointerState;

static SRWLOCK wjl_pointer_lifecycle = SRWLOCK_INIT;
static SRWLOCK wjl_pointer_data = SRWLOCK_INIT;
static WJLSteamPointerState wjl_pointer_state;
static const wchar_t wjl_pointer_class[] = L"WJLSteamExternalPointer";

static int wjl_pointer_owner(DWORD wanted, DWORD foreground) {
    return wanted != 0 && foreground == wanted;
}

static DWORD wjl_pointer_foreground_pid(HWND *window) {
    DWORD pid = 0;
    *window = GetForegroundWindow();
    if (*window) GetWindowThreadProcessId(*window, &pid);
    return pid;
}

/* A fixed upper bound avoids unbounded allocation or work. A pre-existing
 * registration belongs to another component in this service process. */
static int wjl_pointer_registration(RAWINPUTDEVICE *mouse) {
    RAWINPUTDEVICE devices[64];
    UINT capacity = (UINT)(sizeof(devices) / sizeof(devices[0]));
    UINT count = GetRegisteredRawInputDevices(devices, &capacity, sizeof(devices[0]));
    if (count == (UINT)-1) return -1;
    for (UINT index = 0; index < count; ++index) {
        if (devices[index].usUsagePage == 1 && devices[index].usUsage == 2) {
            *mouse = devices[index];
            return 1;
        }
    }
    ZeroMemory(mouse, sizeof(*mouse));
    return 0;
}

/* The same bounded decoder is used by WM_INPUT and standalone fixtures. */
static int wjl_pointer_decode_motion(const void *bytes, size_t length,
                                    DWORD wanted, DWORD foreground, WJLSteamPointerMotion *out) {
    RAWINPUTHEADER header;
    RAWMOUSE mouse;
    const size_t end = offsetof(RAWINPUT, data.mouse) + sizeof(mouse);
    ZeroMemory(out, sizeof(*out));
    if (!wjl_pointer_owner(wanted, foreground) || length < end) return 0;
    memcpy(&header, bytes, sizeof(header));
    if (header.dwType != RIM_TYPEMOUSE || header.dwSize < end || header.dwSize > length) return 0;
    memcpy(&mouse, (const unsigned char *)bytes + offsetof(RAWINPUT, data.mouse), sizeof(mouse));
    if (mouse.usButtonFlags & RI_MOUSE_WHEEL) out->wheel = (int32_t)(SHORT)mouse.usButtonData;
    if (!(mouse.usFlags & MOUSE_MOVE_ABSOLUTE)) {
        out->dx = mouse.lLastX;
        out->dy = mouse.lLastY;
    }
    return 1;
}

static int32_t wjl_pointer_sum(int32_t value, int32_t delta) {
    int64_t sum = (int64_t)value + delta;
    return sum > INT32_MAX ? INT32_MAX : sum < INT32_MIN ? INT32_MIN : (int32_t)sum;
}

static void wjl_pointer_add_motion(const WJLSteamPointerMotion *delta) {
    AcquireSRWLockExclusive(&wjl_pointer_data);
    wjl_pointer_state.motion.wheel = wjl_pointer_sum(wjl_pointer_state.motion.wheel, delta->wheel);
    wjl_pointer_state.motion.dx = wjl_pointer_sum(wjl_pointer_state.motion.dx, delta->dx);
    wjl_pointer_state.motion.dy = wjl_pointer_sum(wjl_pointer_state.motion.dy, delta->dy);
    ReleaseSRWLockExclusive(&wjl_pointer_data);
}

static WJLSteamPointerMotion wjl_pointer_take_motion(void) {
    WJLSteamPointerMotion motion;
    AcquireSRWLockExclusive(&wjl_pointer_data);
    motion = wjl_pointer_state.motion;
    ZeroMemory(&wjl_pointer_state.motion, sizeof(wjl_pointer_state.motion));
    ReleaseSRWLockExclusive(&wjl_pointer_data);
    return motion;
}

static LRESULT CALLBACK wjl_pointer_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_INPUT && InterlockedCompareExchange(&wjl_pointer_state.active, 0, 0)) {
        HWND foreground;
        DWORD pid = wjl_pointer_foreground_pid(&foreground);
        /* Do not read even a RawInput packet while another application owns
         * the foreground. DefWindowProc still performs WM_INPUT cleanup. */
        if (wjl_pointer_owner(wjl_pointer_state.pid, pid)) {
            RAWINPUT input;
            UINT capacity = sizeof(input);
            UINT length = GetRawInputData((HRAWINPUT)lp, RID_INPUT, &input, &capacity, sizeof(RAWINPUTHEADER));
            if (length != (UINT)-1) {
                WJLSteamPointerMotion motion;
                if (wjl_pointer_decode_motion(&input, length, wjl_pointer_state.pid, pid, &motion) &&
                    (motion.wheel || motion.dx || motion.dy)) wjl_pointer_add_motion(&motion);
            }
        } else wjl_pointer_take_motion();
    }
    return DefWindowProcW(window, message, wp, lp);
}

static DWORD WINAPI wjl_pointer_thread(void *unused) {
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSW type;
    RAWINPUTDEVICE previous, device;
    HWND window = NULL;
    int registered = 0, owns_class = 0;
    (void)unused;
    ZeroMemory(&type, sizeof(type));
    type.lpfnWndProc = wjl_pointer_proc;
    type.hInstance = instance;
    type.lpszClassName = wjl_pointer_class;
    if (wjl_pointer_registration(&previous) != 0) goto done;
    if (WaitForSingleObject(wjl_pointer_state.stop, 0) == WAIT_OBJECT_0) goto done;
    if (!RegisterClassW(&type)) goto done;
    owns_class = 1;
    window = CreateWindowExW(0, wjl_pointer_class, L"", 0, 0, 0, 0, 0,
                             HWND_MESSAGE, NULL, instance, NULL);
    if (!window) goto done;
    device.usUsagePage = 1;
    device.usUsage = 2;
    device.dwFlags = RIDEV_INPUTSINK;
    device.hwndTarget = window;
    if (!RegisterRawInputDevices(&device, 1, sizeof(device))) goto done;
    registered = 1;
    wjl_pointer_state.window = window;
    if (WaitForSingleObject(wjl_pointer_state.stop, 0) == WAIT_OBJECT_0) goto done;
    InterlockedExchange(&wjl_pointer_state.active, 1);
    SetEvent(wjl_pointer_state.ready);
    for (;;) {
        DWORD reason = MsgWaitForMultipleObjectsEx(1, &wjl_pointer_state.stop,
            INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        MSG message;
        if (reason != WAIT_OBJECT_0 + 1) break;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) goto done;
            TranslateMessage(&message);
            DispatchMessageW(&message);
            if (WaitForSingleObject(wjl_pointer_state.stop, 0) == WAIT_OBJECT_0) goto done;
        }
    }
done:
    InterlockedExchange(&wjl_pointer_state.active, 0);
    if (registered && wjl_pointer_registration(&previous) == 1 && previous.hwndTarget == window) {
        device.usUsagePage = 1;
        device.usUsage = 2;
        device.dwFlags = RIDEV_REMOVE;
        device.hwndTarget = NULL;
        RegisterRawInputDevices(&device, 1, sizeof(device));
    }
    if (window) DestroyWindow(window);
    if (owns_class) UnregisterClassW(wjl_pointer_class, instance);
    wjl_pointer_state.window = NULL;
    wjl_pointer_take_motion();
    SetEvent(wjl_pointer_state.ready);
    return 0;
}

/* Lifecycle lock held. Timed-out threads retain their owned handles until a
 * later call can reap them; no handle is closed beneath a running thread. */
static int wjl_pointer_stop_locked(DWORD timeout) {
    if (!wjl_pointer_state.thread) return 1;
    InterlockedExchange(&wjl_pointer_state.active, 0);
    SetEvent(wjl_pointer_state.stop);
    if (WaitForSingleObject(wjl_pointer_state.thread, timeout) != WAIT_OBJECT_0) return 0;
    CloseHandle(wjl_pointer_state.thread);
    CloseHandle(wjl_pointer_state.ready);
    CloseHandle(wjl_pointer_state.stop);
    ZeroMemory(&wjl_pointer_state, sizeof(wjl_pointer_state));
    return 1;
}

int wjl_pointer_start(DWORD pid) {
    int ok = 0;
    ULONGLONG deadline = GetTickCount64() + 1000;
    AcquireSRWLockExclusive(&wjl_pointer_lifecycle);
    if (!pid) goto done;
    if (wjl_pointer_state.thread && wjl_pointer_state.pid == pid &&
        InterlockedCompareExchange(&wjl_pointer_state.active, 0, 0)) {
        ok = 1;
        goto done;
    }
    if (!wjl_pointer_stop_locked(0)) goto done;
    wjl_pointer_state.pid = pid;
    wjl_pointer_state.ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    wjl_pointer_state.stop = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!wjl_pointer_state.ready || !wjl_pointer_state.stop) {
        if (wjl_pointer_state.ready) CloseHandle(wjl_pointer_state.ready);
        if (wjl_pointer_state.stop) CloseHandle(wjl_pointer_state.stop);
        ZeroMemory(&wjl_pointer_state, sizeof(wjl_pointer_state));
        goto done;
    }
    wjl_pointer_state.thread = CreateThread(NULL, 0, wjl_pointer_thread, NULL, 0, NULL);
    if (!wjl_pointer_state.thread) {
        CloseHandle(wjl_pointer_state.ready);
        CloseHandle(wjl_pointer_state.stop);
        ZeroMemory(&wjl_pointer_state, sizeof(wjl_pointer_state));
        goto done;
    }
    if (WaitForSingleObject(wjl_pointer_state.ready, 800) == WAIT_OBJECT_0)
        ok = InterlockedCompareExchange(&wjl_pointer_state.active, 0, 0) != 0;
    if (!ok) {
        ULONGLONG now = GetTickCount64();
        wjl_pointer_stop_locked(now < deadline ? (DWORD)(deadline - now) : 0);
    }
done:
    ReleaseSRWLockExclusive(&wjl_pointer_lifecycle);
    return ok;
}

/* WJ: keep the cursor inside the game's client area while Photo Mode owns the
 * pointer. Windows and games drop a clip on focus and mode changes, so every
 * sample re-applies it. A clip that already keeps the cursor inside the window
 * (the game's own) is left alone, and release removes only a clip set here. */
static RECT wjl_pointer_clip;
static int wjl_pointer_clipped;
static void wjl_pointer_unconfine(void) {
    RECT current;
    if (!wjl_pointer_clipped) return;
    wjl_pointer_clipped = 0;
    if (GetClipCursor(&current) && EqualRect(&current, &wjl_pointer_clip)) ClipCursor(NULL);
}
static void wjl_pointer_confine(HWND window, const RECT *client) {
    POINT origin = {0, 0};
    RECT wanted, frame, current;
    if (!ClientToScreen(window, &origin) || !GetWindowRect(window, &frame) || !GetClipCursor(&current)) return;
    if (current.left >= frame.left && current.top >= frame.top && current.right <= frame.right && current.bottom <= frame.bottom) return;
    SetRect(&wanted, origin.x, origin.y, origin.x + (client->right - client->left), origin.y + (client->bottom - client->top));
    if (ClipCursor(&wanted)) { wjl_pointer_clip = wanted; wjl_pointer_clipped = 1; }
}
int wjl_pointer_snapshot_extended(WJLSteamPointerSample *out) {
    static const int keys[] = {VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2};
    HWND foreground = NULL, after;
    POINT point;
    RECT bounds = {0, 0, 0, 0};
    DWORD pid;
    int ok = 0, buttons = 0;
    WJLSteamPointerMotion motion;
    if (!out) return 0;
    ZeroMemory(out, sizeof(*out));
    AcquireSRWLockShared(&wjl_pointer_lifecycle);
    if (!InterlockedCompareExchange(&wjl_pointer_state.active, 0, 0)) goto done;
    ok = 1;
    motion = wjl_pointer_take_motion();
    pid = wjl_pointer_foreground_pid(&foreground);
    if (!wjl_pointer_owner(wjl_pointer_state.pid, pid)) goto done;
    if (!GetCursorPos(&point) || !ScreenToClient(foreground, &point) ||
        !GetClientRect(foreground, &bounds) || bounds.right <= bounds.left || bounds.bottom <= bounds.top) goto done;
    for (unsigned int index = 0; index < sizeof(keys) / sizeof(keys[0]); ++index)
        if (GetAsyncKeyState(keys[index]) & 0x8000) buttons |= 1 << index;
    pid = wjl_pointer_foreground_pid(&after);
    if (after != foreground || !wjl_pointer_owner(wjl_pointer_state.pid, pid)) goto done;
    out->valid = 1;
    out->x = point.x;
    out->y = point.y;
    out->width = bounds.right - bounds.left;
    out->height = bounds.bottom - bounds.top;
    out->buttons = buttons;
    out->wheel = motion.wheel;
    out->dx = motion.dx;
    out->dy = motion.dy;
done:
    if (out->valid) wjl_pointer_confine(foreground, &bounds); else wjl_pointer_unconfine();
    ReleaseSRWLockShared(&wjl_pointer_lifecycle);
    return ok;
}

int wjl_pointer_snapshot(WJLSteamPointerSnapshot *out) {
    WJLSteamPointerSample sample;
    int ok;
    if (!out) return 0;
    ok = wjl_pointer_snapshot_extended(&sample);
    /* Legacy clients consume the same atomic sample and discard raw motion.
     * Shared consumers must fan out one extended sample per frame in Lua. */
    memcpy(out, &sample, sizeof(*out));
    return ok;
}

int wjl_pointer_release(void) {
    int ok;
    AcquireSRWLockExclusive(&wjl_pointer_lifecycle);
    wjl_pointer_unconfine();
    ok = wjl_pointer_stop_locked(1000);
    ReleaseSRWLockExclusive(&wjl_pointer_lifecycle);
    return ok;
}

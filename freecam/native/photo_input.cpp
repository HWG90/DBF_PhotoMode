/* Photo-owned clone of DBF-MCM native/input_guard.c.
 * Copyright (C) 2026 CowboyBingus; Zero-Clause BSD.
 * See ../vendor/LICENSE-Bingus.txt.
 * Local change: physical Escape passes to native UI only in camera mode 3.
 */
/* Per-window input capture. No Lua callbacks from the window thread.
 * Does not hook another process or suppress OS shortcuts globally.
 */
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>

static HWND owner;
static WNDPROC previous;
static volatile LONG captured;
/* Menu artwork only. Keep one cursor for this pinned DLL's lifetime so the
 * window thread never selects a destroyed resource. Input policy is unchanged. */
static PVOID volatile menu_cursor;
extern "C" __declspec(dllexport) HCURSOR mcm_menu_cursor(void) {
    return (HCURSOR)InterlockedCompareExchangePointer(&menu_cursor,NULL,NULL);
}
extern "C" __declspec(dllexport) int mcm_load_menu_cursor(const char *path) {
    if (!path || !*path) return 0;
    int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,NULL,0);
    if (size <= 0 || size > 32768) return 0;
    WCHAR *wide=(WCHAR*)HeapAlloc(GetProcessHeap(),0,(SIZE_T)size*sizeof(WCHAR));
    if (!wide) return 0;
    HCURSOR loaded=NULL;
    if (MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,wide,size)==size) {
        bool absolute=(size>=4 && wide[1]==L':' && (wide[2]==L'\\' || wide[2]==L'/')) ||
            (size>=3 && wide[0]==L'\\' && wide[1]==L'\\');
        DWORD attributes=absolute ? GetFileAttributesW(wide) : INVALID_FILE_ATTRIBUTES;
        if (attributes!=INVALID_FILE_ATTRIBUTES && !(attributes&FILE_ATTRIBUTE_DIRECTORY)) {
            if (mcm_menu_cursor()) { HeapFree(GetProcessHeap(),0,wide);return 1; }
            loaded=LoadCursorFromFileW(wide);
        }
    }
    HeapFree(GetProcessHeap(),0,wide);
    if (!loaded) return 0;
    if (InterlockedCompareExchangePointer(&menu_cursor,loaded,NULL)) DestroyCursor(loaded);
    return 1;
}
static volatile LONG wheel;
static volatile LONG look_x, look_y;
static volatile LONG keys[256];
static volatile LONG buttons[5];
static volatile LONG previous_raw[256];
static volatile LONG previous_legacy[256];
static volatile LONG previous_mouse_raw,previous_mouse_legacy;

/* Capability is owned by this clone; shared MCM libraries remain unchanged. */
extern "C" __declspec(dllexport) int mcm_escape_passthrough(void) { return 1; }

extern "C" __declspec(dllexport) int mcm_policy(UINT message, UINT raw_type, int capture) {
    if (!capture) return 0;
    if (message == WM_INPUT) return raw_type == RIM_TYPEKEYBOARD || raw_type == RIM_TYPEMOUSE;
    if (message >= WM_KEYFIRST && message <= WM_KEYLAST) return 1;
    if (capture == 2 && message == WM_MOUSEMOVE) return 0;
    if (message >= WM_MOUSEFIRST && message <= WM_MOUSELAST) return 1;
    return 0;
}

static int keyboard_gate(UINT key, int up, int capture) {
    if (key >= 256) return capture;
    /* Camera Escape belongs to native UI; do not retain its key-up drain. */
    if (capture == 3 && key == VK_ESCAPE) { InterlockedExchange(&keys[key],0); return 0; }
    if (capture) { InterlockedExchange(&keys[key], up ? 0 : 1); return 1; }
    if (InterlockedCompareExchange(&keys[key], 0, 0)) {
        if (up) InterlockedExchange(&keys[key], 0);
        return 1;
    }
    return 0;
}

/* Both RAW and legacy routes use this exact tested event policy. */
static int keyboard_event_gate(UINT key, int up, int capture, volatile LONG *prior) {
    if (key < 256 && up && InterlockedExchange(&prior[key],0)) return 0;
    return keyboard_gate(key,up,capture);
}

static int mouse_gate(USHORT flags, int capture) {
    int gate = capture == 2 ? flags != 0 : capture;
    const USHORT down[5] = {RI_MOUSE_LEFT_BUTTON_DOWN,RI_MOUSE_RIGHT_BUTTON_DOWN,
        RI_MOUSE_MIDDLE_BUTTON_DOWN,RI_MOUSE_BUTTON_4_DOWN,RI_MOUSE_BUTTON_5_DOWN};
    const USHORT up[5] = {RI_MOUSE_LEFT_BUTTON_UP,RI_MOUSE_RIGHT_BUTTON_UP,
        RI_MOUSE_MIDDLE_BUTTON_UP,RI_MOUSE_BUTTON_4_UP,RI_MOUSE_BUTTON_5_UP};
    for (int i=0; i<5; ++i) {
        if (capture != 2 && InterlockedCompareExchange(&buttons[i],0,0)) gate=1;
        if (capture && (flags & down[i])) InterlockedExchange(&buttons[i],1);
        if (flags & up[i]) InterlockedExchange(&buttons[i],0);
    }
    return gate;
}

static int previous_mouse_release(volatile LONG *held, USHORT flags) {
    LONG released=InterlockedCompareExchange(held,0,0) & flags;
    if (!released) return 0;
    InterlockedAnd(held,~released);
    return 1;
}
static USHORT mouse_flags(UINT msg, WPARAM wp) {
    switch (msg) {
    case WM_LBUTTONDOWN:case WM_LBUTTONDBLCLK:return RI_MOUSE_LEFT_BUTTON_DOWN;
    case WM_LBUTTONUP:return RI_MOUSE_LEFT_BUTTON_UP;
    case WM_RBUTTONDOWN:case WM_RBUTTONDBLCLK:return RI_MOUSE_RIGHT_BUTTON_DOWN;
    case WM_RBUTTONUP:return RI_MOUSE_RIGHT_BUTTON_UP;
    case WM_MBUTTONDOWN:case WM_MBUTTONDBLCLK:return RI_MOUSE_MIDDLE_BUTTON_DOWN;
    case WM_MBUTTONUP:return RI_MOUSE_MIDDLE_BUTTON_UP;
    case WM_XBUTTONDOWN:case WM_XBUTTONDBLCLK:return HIWORD(wp)==XBUTTON1?RI_MOUSE_BUTTON_4_DOWN:RI_MOUSE_BUTTON_5_DOWN;
    case WM_XBUTTONUP:return HIWORD(wp)==XBUTTON1?RI_MOUSE_BUTTON_4_UP:RI_MOUSE_BUTTON_5_UP;
    default:return 0;
    }
}

static LRESULT CALLBACK guarded_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    int capture = hwnd==owner && GetForegroundWindow()==owner ? (int)InterlockedCompareExchange(&captured,0,0) : 0;
    if (msg==WM_KILLFOCUS || (msg==WM_ACTIVATEAPP && !wp)) {
        InterlockedExchange(&captured,0);
        InterlockedExchange(&look_x,0);InterlockedExchange(&look_y,0);
        for (int i=0;i<256;++i) { InterlockedExchange(&keys[i],0); InterlockedExchange(&previous_raw[i],0); InterlockedExchange(&previous_legacy[i],0); }
        for (int i=0;i<5;++i) InterlockedExchange(&buttons[i],0);
        InterlockedExchange(&previous_mouse_raw,0);InterlockedExchange(&previous_mouse_legacy,0);
        capture=0;
    }
    if (msg==WM_INPUT) {
        RAWINPUT raw;UINT size=sizeof raw;
        UINT read=GetRawInputData((HRAWINPUT)lp,RID_INPUT,&raw,&size,sizeof(RAWINPUTHEADER));
        if (read!=(UINT)-1 && read>=sizeof(RAWINPUTHEADER)) {
            int block=0;
            if (raw.header.dwType==RIM_TYPEKEYBOARD) {
                UINT key=raw.data.keyboard.VKey;int up=(raw.data.keyboard.Flags&RI_KEY_BREAK)!=0;
                /* Release keys that the game already saw before capture. */
                block=keyboard_event_gate(key,up,capture,previous_raw);
            }
            else if (raw.header.dwType==RIM_TYPEMOUSE) {
                if (capture && (raw.data.mouse.usButtonFlags & RI_MOUSE_WHEEL))
                    InterlockedExchangeAdd(&wheel,(SHORT)raw.data.mouse.usButtonData);
                if (capture == 3 && !(raw.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE)) {
                    InterlockedExchangeAdd(&look_x,raw.data.mouse.lLastX);
                    InterlockedExchangeAdd(&look_y,raw.data.mouse.lLastY);
                }
                block=previous_mouse_release(&previous_mouse_raw,raw.data.mouse.usButtonFlags) ? 0 : mouse_gate(raw.data.mouse.usButtonFlags,capture);
            }
            if (block) {
                /* WM_INPUT foreground packets require DefWindowProc cleanup. */
                return DefWindowProcW(hwnd,msg,wp,lp);
            }
        } else if (capture) return DefWindowProcW(hwnd,msg,wp,lp);
    } else if (msg==WM_KEYDOWN || msg==WM_SYSKEYDOWN || msg==WM_KEYUP || msg==WM_SYSKEYUP) {
        UINT key=(UINT)wp;int up=msg==WM_KEYUP || msg==WM_SYSKEYUP;
        if (keyboard_event_gate(key,up,capture,previous_legacy))return 0;
    } else if (msg>=WM_MOUSEFIRST && msg<=WM_MOUSELAST) {
        if (!previous_mouse_release(&previous_mouse_legacy,mouse_flags(msg,wp)) && mouse_gate(mouse_flags(msg,wp),capture))return 0;
    } else if (mcm_policy(msg,99,capture))return 0;
    if (capture == 1 && msg==WM_SETCURSOR) {
        HCURSOR graphic=mcm_menu_cursor();
        SetCursor(graphic ? graphic : LoadCursorW(NULL,IDC_ARROW));return TRUE;
    }
    return CallWindowProcW(previous,hwnd,msg,wp,lp);
}

extern "C" __declspec(dllexport) int mcm_install(HWND hwnd) {
    DWORD pid=0;GetWindowThreadProcessId(hwnd,&pid);
    if (!IsWindow(hwnd) || pid!=GetCurrentProcessId())return 0;
    if (owner) return owner==hwnd;
    previous=(WNDPROC)GetWindowLongPtrW(hwnd,GWLP_WNDPROC);
    if (!previous)return 0;
    /* Pin before installing a callback that other subclasses may retain. */
    HMODULE module;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        (LPCWSTR)guarded_proc,&module))return 0;
    owner=hwnd;SetLastError(0);
    LONG_PTR old=SetWindowLongPtrW(hwnd,GWLP_WNDPROC,(LONG_PTR)guarded_proc);
    if (!old && GetLastError()) {owner=NULL;previous=NULL;return 0;}
    previous=(WNDPROC)old;
    return 1;
}

extern "C" __declspec(dllexport) int mcm_capture(int active) {
    if (active < 0 || active > 3 || !owner || !IsWindow(owner))return 0;
    if (active && GetForegroundWindow()!=owner)return 0;
    if (active && !InterlockedCompareExchange(&captured,0,0)) {
        /* A held gameplay mouse button cannot be released through a raw packet
         * without also forwarding its movement. Refuse acquisition until up.
         */
        const int mouse_keys[5]={VK_LBUTTON,VK_RBUTTON,VK_MBUTTON,VK_XBUTTON1,VK_XBUTTON2};
        LONG held_mouse=0;
        const USHORT releases[5]={RI_MOUSE_LEFT_BUTTON_UP,RI_MOUSE_RIGHT_BUTTON_UP,RI_MOUSE_MIDDLE_BUTTON_UP,RI_MOUSE_BUTTON_4_UP,RI_MOUSE_BUTTON_5_UP};
        for (int i=0;i<5;++i)if (GetAsyncKeyState(mouse_keys[i])&0x8000) {
            if (active != 3) return 0;
            held_mouse |= releases[i];
        }
        InterlockedExchange(&previous_mouse_raw,held_mouse);InterlockedExchange(&previous_mouse_legacy,held_mouse);
        for (int i=0;i<256;++i) {
            LONG down=(GetAsyncKeyState(i)&0x8000)?1:0;
            InterlockedExchange(&previous_raw[i],down);InterlockedExchange(&previous_legacy[i],down);
        }
    }
    if (!active || !InterlockedCompareExchange(&captured,0,0))InterlockedExchange(&wheel,0);
    InterlockedExchange(&look_x,0);InterlockedExchange(&look_y,0);
    InterlockedExchange(&captured,active);return 1;
}
/* Session observations come from the engine on the calling Lua thread only.
 * Unknown/error observations default to denial. The DLL owns the decision;
 * freecam remains available; only pause is gated.
 */
typedef struct { int session_present, other_peers, joining_peers, connections; } MCM_PHOTO_SESSION;
typedef void (*MCM_PHOTO_QUERY)(MCM_PHOTO_SESSION *);
extern "C" __declspec(dllexport) int mcm_photo_policy(const MCM_PHOTO_SESSION *s) {
    if (!s) return 0;
    if (s->session_present == 1) return s->other_peers == 0 && s->joining_peers == 0;
    if (s->session_present == 0) return s->connections == 0;
    return 0;
}
static int photo_verified(MCM_PHOTO_QUERY query) {
    MCM_PHOTO_SESSION state = {-1,-1,-1,-1};
    if (!query) return 0;
    query(&state);
    return mcm_photo_policy(&state);
}
typedef int (*MCM_PHOTO_APPLY)(void);
extern "C" __declspec(dllexport) int mcm_photo_pause_allowed(MCM_PHOTO_QUERY query) {
    return photo_verified(query);
}
extern "C" __declspec(dllexport) int mcm_photo_pause(MCM_PHOTO_QUERY query, MCM_PHOTO_APPLY apply) {
    if (!apply || !photo_verified(query)) return 0;
    return apply() == 1;
}
extern "C" __declspec(dllexport) int mcm_captured(void) {
    return owner && GetForegroundWindow()==owner ? (int)InterlockedCompareExchange(&captured,0,0) : 0;
}
extern "C" __declspec(dllexport) void mcm_release(void) {
    InterlockedExchange(&captured,0);InterlockedExchange(&wheel,0);
    InterlockedExchange(&look_x,0);InterlockedExchange(&look_y,0);
    /* Keep an inert callback until held menu keys/buttons have released.
     * Its DLL is pinned; all ordinary traffic continues through previous.
     */
}

extern "C" __declspec(dllexport) int mcm_wheel(void) { return (int)InterlockedExchange(&wheel,0); }

extern "C" __declspec(dllexport) int mcm_mouse_x(void) { return (int)InterlockedExchange(&look_x,0); }
extern "C" __declspec(dllexport) int mcm_mouse_y(void) { return (int)InterlockedExchange(&look_y,0); }

extern "C" __declspec(dllexport) double mcm_seconds(void) { LARGE_INTEGER now,frequency;QueryPerformanceCounter(&now);QueryPerformanceFrequency(&frequency);return (double)now.QuadPart/(double)frequency.QuadPart; }

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
static volatile LONG observe_wheel;
static volatile LONG look_x, look_y;
static volatile LONG keys[256];
static volatile LONG buttons[5];
static volatile LONG previous_raw[256];
static volatile LONG previous_legacy[256];
static volatile LONG previous_mouse_raw,previous_mouse_legacy;

/* Only artwork-independent client confinement is owned here. ClipCursor is
 * thread independent; no SetCapture/button-routing ownership is acquired. */
static SRWLOCK clip_lock=SRWLOCK_INIT;
static RECT clip_previous,clip_applied;
static bool clip_owned;
extern "C" __declspec(dllexport) int mcm_cursor_confinement(void) { return 1; }
extern "C" __declspec(dllexport) int mcm_cursor_confined(void) {
    AcquireSRWLockShared(&clip_lock);
    RECT current;
    int confined=owner && GetForegroundWindow()==owner &&
        InterlockedCompareExchange(&captured,0,0)==3 && clip_owned &&
        GetClipCursor(&current) && EqualRect(&current,&clip_applied);
    ReleaseSRWLockShared(&clip_lock);return confined;
}
static void restore_clip_locked(void) {
    RECT current;
    if (clip_owned && GetClipCursor(&current)) {
        /* A saved game rectangle must not confine the newly foreground app. */
        const RECT *restore=owner && GetForegroundWindow()==owner ? &clip_previous : NULL;
        if (!EqualRect(&current,&clip_applied) || ClipCursor(restore)) clip_owned=false;
    }
}
static void camera_clip(int capture) {
    AcquireSRWLockExclusive(&clip_lock);
    RECT current;
    if (capture != 3 || !owner || GetForegroundWindow()!=owner) {
        restore_clip_locked();
        ReleaseSRWLockExclusive(&clip_lock);return;
    }
    RECT client;
    POINT first,last;
    if (!GetClientRect(owner,&client) || client.right<=client.left || client.bottom<=client.top) {
        restore_clip_locked();
        ReleaseSRWLockExclusive(&clip_lock);return;
    }
    first.x=client.left;first.y=client.top;last.x=client.right;last.y=client.bottom;
    if (!ClientToScreen(owner,&first) || !ClientToScreen(owner,&last) || !GetClipCursor(&current)) {
        ReleaseSRWLockExclusive(&clip_lock);return;
    }
    RECT target={first.x,first.y,last.x,last.y};
    if (!clip_owned) clip_previous=current;
    if (EqualRect(&current,&target)) { clip_applied=current;clip_owned=true; }
    else if (ClipCursor(&target)) {
        clip_applied=target;clip_owned=true;
        RECT observed;if (GetClipCursor(&observed)) clip_applied=observed;
    }
    ReleaseSRWLockExclusive(&clip_lock);
}

/* Queue physical edges rather than sampling a held state once per render.
 * RAW and legacy reports share held state plus a short counterpart history;
 * a complete RAW down/up preceding its legacy copy still emits one pair. */
typedef struct { double seconds; int x,y,button,down; } MCM_CLICK_EVENT;
typedef struct { double seconds; DWORD time; int button,down,routes; } MCM_CLICK_SEEN;
static SRWLOCK click_lock=SRWLOCK_INIT;
static MCM_CLICK_EVENT click_queue[64];
static MCM_CLICK_SEEN click_seen[64];
static unsigned click_read,click_count,click_seen_read,click_seen_count;
static int click_held[5];
static void clear_clicks_locked(void) {
    click_read=click_count=click_seen_read=click_seen_count=0;
    for (int i=0;i<5;++i) click_held[i]=0;
}
static void capture_mode(int active,bool force_clear=false) {
    AcquireSRWLockExclusive(&click_lock);
    LONG prior=InterlockedExchange(&captured,active);
    if (prior!=active || force_clear) clear_clicks_locked();
    ReleaseSRWLockExclusive(&click_lock);
}
static void click_edge(int button,int down,int x,int y,double seconds,DWORD time,int route) {
    for (unsigned i=0;i<click_seen_count;++i) {
        MCM_CLICK_SEEN *seen=&click_seen[(click_seen_read+i)%64];
        LONG delta=(LONG)(time-seen->time);
        if (seen->button==button && seen->down==down && !(seen->routes&route) &&
            seconds>=seen->seconds && seconds-seen->seconds<=0.25 && delta>=-2 && delta<=2) {
            seen->routes|=route;return;
        }
    }
    if (click_held[button-1]==down) return;
    click_held[button-1]=down;
    if (click_count==64) { click_read=(click_read+1)%64;--click_count; }
    MCM_CLICK_EVENT event={seconds,x,y,button,down};
    click_queue[(click_read+click_count)%64]=event;++click_count;
    if (click_seen_count==64) { click_seen_read=(click_seen_read+1)%64;--click_seen_count; }
    MCM_CLICK_SEEN seen={seconds,time,button,down,route};
    click_seen[(click_seen_read+click_seen_count)%64]=seen;++click_seen_count;
}
static void click_events(USHORT flags,int capture,int x,int y,double seconds,DWORD time,int route) {
    if (capture!=1 || (route!=1 && route!=2)) return;
    const USHORT down[5]={RI_MOUSE_LEFT_BUTTON_DOWN,RI_MOUSE_RIGHT_BUTTON_DOWN,
        RI_MOUSE_MIDDLE_BUTTON_DOWN,RI_MOUSE_BUTTON_4_DOWN,RI_MOUSE_BUTTON_5_DOWN};
    const USHORT up[5]={RI_MOUSE_LEFT_BUTTON_UP,RI_MOUSE_RIGHT_BUTTON_UP,
        RI_MOUSE_MIDDLE_BUTTON_UP,RI_MOUSE_BUTTON_4_UP,RI_MOUSE_BUTTON_5_UP};
    AcquireSRWLockExclusive(&click_lock);
    if (InterlockedCompareExchange(&captured,0,0)==1) {
        for (int i=0;i<5;++i) {
            if (flags&down[i]) click_edge(i+1,1,x,y,seconds,time,route);
            if (flags&up[i]) click_edge(i+1,0,x,y,seconds,time,route);
        }
    }
    ReleaseSRWLockExclusive(&click_lock);
}
extern "C" __declspec(dllexport) int mcm_next_click(MCM_CLICK_EVENT *event) {
    if (!event) return 0;
    AcquireSRWLockExclusive(&click_lock);
    if (!click_count || InterlockedCompareExchange(&captured,0,0)!=1) {
        ReleaseSRWLockExclusive(&click_lock);return 0;
    }
    *event=click_queue[click_read];click_read=(click_read+1)%64;--click_count;
    ReleaseSRWLockExclusive(&click_lock);return 1;
}
static double event_seconds(void) {
    LARGE_INTEGER now,frequency;QueryPerformanceCounter(&now);QueryPerformanceFrequency(&frequency);
    return (double)now.QuadPart/(double)frequency.QuadPart;
}
static LRESULT finish_message(LRESULT result) {
    camera_clip((int)InterlockedCompareExchange(&captured,0,0));return result;
}

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
        InterlockedExchange(&observe_wheel,0);InterlockedExchange(&wheel,0);
        capture_mode(0,true);
        InterlockedExchange(&look_x,0);InterlockedExchange(&look_y,0);
        for (int i=0;i<256;++i) { InterlockedExchange(&keys[i],0); InterlockedExchange(&previous_raw[i],0); InterlockedExchange(&previous_legacy[i],0); }
        for (int i=0;i<5;++i) InterlockedExchange(&buttons[i],0);
        InterlockedExchange(&previous_mouse_raw,0);InterlockedExchange(&previous_mouse_legacy,0);
        capture=0;
    }
    camera_clip(capture);
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
                POINT point;
                if (capture==1 && GetCursorPos(&point) && ScreenToClient(hwnd,&point))
                    click_events(raw.data.mouse.usButtonFlags,capture,point.x,point.y,event_seconds(),(DWORD)GetMessageTime(),1);
                if ((capture || InterlockedCompareExchange(&observe_wheel,0,0)) && (raw.data.mouse.usButtonFlags & RI_MOUSE_WHEEL))
                    InterlockedExchangeAdd(&wheel,(SHORT)raw.data.mouse.usButtonData);
                if (capture == 3 && !(raw.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE)) {
                    InterlockedExchangeAdd(&look_x,raw.data.mouse.lLastX);
                    InterlockedExchangeAdd(&look_y,raw.data.mouse.lLastY);
                }
                block=previous_mouse_release(&previous_mouse_raw,raw.data.mouse.usButtonFlags) ? 0 : mouse_gate(raw.data.mouse.usButtonFlags,capture);
            }
            if (block) {
                /* WM_INPUT foreground packets require DefWindowProc cleanup. */
                return finish_message(DefWindowProcW(hwnd,msg,wp,lp));
            }
        } else if (capture) return finish_message(DefWindowProcW(hwnd,msg,wp,lp));
    } else if (msg==WM_KEYDOWN || msg==WM_SYSKEYDOWN || msg==WM_KEYUP || msg==WM_SYSKEYUP) {
        UINT key=(UINT)wp;int up=msg==WM_KEYUP || msg==WM_SYSKEYUP;
        if (keyboard_event_gate(key,up,capture,previous_legacy))return finish_message(0);
    } else if (msg>=WM_MOUSEFIRST && msg<=WM_MOUSELAST) {
        USHORT flags=mouse_flags(msg,wp);
        if (capture==1 && flags)
            click_events(flags,capture,(short)LOWORD(lp),(short)HIWORD(lp),event_seconds(),(DWORD)GetMessageTime(),2);
        if (!previous_mouse_release(&previous_mouse_legacy,mouse_flags(msg,wp)) && mouse_gate(mouse_flags(msg,wp),capture))return finish_message(0);
    } else if (mcm_policy(msg,99,capture))return finish_message(0);
    if (capture == 1 && msg==WM_SETCURSOR) {
        HCURSOR graphic=mcm_menu_cursor();
        SetCursor(graphic ? graphic : LoadCursorW(NULL,IDC_ARROW));return finish_message(TRUE);
    }
    return finish_message(CallWindowProcW(previous,hwnd,msg,wp,lp));
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
    capture_mode(active);camera_clip(active);return 1;
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
    InterlockedExchange(&observe_wheel,0);
    capture_mode(0,true);camera_clip(0);InterlockedExchange(&wheel,0);
    InterlockedExchange(&look_x,0);InterlockedExchange(&look_y,0);
    /* Keep an inert callback until held menu keys/buttons have released.
     * Its DLL is pinned; all ordinary traffic continues through previous.
     */
}

extern "C" __declspec(dllexport) int mcm_wheel(void) { return (int)InterlockedExchange(&wheel,0); }

extern "C" __declspec(dllexport) int mcm_mouse_x(void) { return (int)InterlockedExchange(&look_x,0); }
extern "C" __declspec(dllexport) int mcm_mouse_y(void) { return (int)InterlockedExchange(&look_y,0); }

extern "C" __declspec(dllexport) double mcm_seconds(void) { LARGE_INTEGER now,frequency;QueryPerformanceCounter(&now);QueryPerformanceFrequency(&frequency);return (double)now.QuadPart/(double)frequency.QuadPart; }

/* Observe the existing raw-input stream without consuming gameplay messages.
 * Transitions discard queued wheel input, so menu scrolling cannot become zoom. */
static int gameplay_wheel_observe(LONG desired) {
    LONG prior=InterlockedExchange(&observe_wheel,desired);
    LONG delta=InterlockedExchange(&wheel,0);
    return desired && prior==desired ? (int)delta : 0;
}

extern "C" __declspec(dllexport) int mcm_gameplay_wheel(int enabled) {
    return gameplay_wheel_observe(enabled && owner && GetForegroundWindow()==owner ? 1 : 0);
}

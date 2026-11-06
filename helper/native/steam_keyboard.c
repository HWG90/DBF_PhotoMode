/* Opt-in external keyboard lease. RegisterHotKey runs only in this service's
 * own message thread. No target hooks, injected input, focus changes, process
 * memory access, or idle keyboard thread. This candidate's modifier behavior
 * requires physical qualification before the capability may be advertised.
 * Include in steam_service.c; standalone fixtures replace only Win32 seams. */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>

#define WJL_KEYBOARD_VERSION 1u
#define WJL_KEYBOARD_ARMING 1u
#define WJL_KEYBOARD_ACTIVE 2u
#define WJL_KEYBOARD_REVOKED 3u
#define WJL_KEYBOARD_CLOSING 4u
#define WJL_KEYBOARD_FAILED 5u
#define WJL_KEYBOARD_TTL_MS 2000u
#define WJL_KEYBOARD_ARM_MS 2000u
#define WJL_KEYBOARD_COMMAND_MS 1000u
#define WJL_KEYBOARD_MAX_TUPLES 2048u

typedef struct WJLSteamKeyboardReply {
    uint32_t version, client, generation, state, mask[8];
} WJLSteamKeyboardReply;
typedef struct WJLSteamKeyboardSample {
    uint32_t version, generation, state, keys[8];
} WJLSteamKeyboardSample;
typedef struct WJLSteamKeyboardLease {
    HANDLE thread, ready, stop, process;
    HWND target, window;
    HWINEVENTHOOK foreground_hook;
    FILETIME creation;
    DWORD pid;
    uint32_t client, generation, state, error, terminal, mask[8];
    ULONGLONG started, heartbeat, register_ms;
    int registrations[WJL_KEYBOARD_MAX_TUPLES];
    unsigned int registration_count;
    unsigned int shared_count; /* tuples another application already owns */
    uint32_t shared[8];        /* the first eight: key | modifiers << 8 */
    int revoking;
} WJLSteamKeyboardLease;
typedef struct WJLSteamKeyboardRetired {
    DWORD pid;
    uint32_t client, generation;
} WJLSteamKeyboardRetired;

/* This exact whitelist is shared with Lua. Side modifier bits are aliases:
 * requesting any member requires generic + left + right; only generic VKs
 * are registered. Windows/F12/PrintScreen/mouse/unassigned VKs are excluded.
 * Alt+Tab/Esc/F4/Enter/Space, Ctrl+Esc and Ctrl+Alt+Delete tuples are deliberately
 * omitted. The owned-window 39-tuple W/Space/generic-modifier proof passed;
 * the complete matrix and integrated gameplay behavior remain unqualified.
 * A successful registration alone does not establish suppression. */
static const uint32_t wjl_keyboard_allowed[8] = {
    0x081f3300u, 0x03ffe1ffu, 0x27fffffeu, 0xf7ffffffu,
    0x000300ffu, 0xfc00003fu, 0xf8000001u, 0x00000004u
};
static SRWLOCK wjl_keyboard_lifecycle = SRWLOCK_INIT;
static SRWLOCK wjl_keyboard_data = SRWLOCK_INIT;
static WJLSteamKeyboardLease wjl_keyboard_lease;
static WJLSteamKeyboardRetired wjl_keyboard_retired;
static uint32_t wjl_keyboard_highest_client, wjl_keyboard_last_generation;
static DWORD wjl_keyboard_session_pid;
static FILETIME wjl_keyboard_session_creation;
static const wchar_t wjl_keyboard_class[] = L"WJLSteamExternalKeyboard";

/* Production uses direct Win32 calls. Tests substitute deterministic fakes
 * at compilation; no mutable function table is exposed by the service. */
#ifndef WJL_KB_REGISTER
#define WJL_KB_REGISTER RegisterHotKey
#endif
#ifndef WJL_KB_UNREGISTER
#define WJL_KB_UNREGISTER UnregisterHotKey
#endif
#ifndef WJL_KB_ASYNC
#define WJL_KB_ASYNC GetAsyncKeyState
#endif
#ifndef WJL_KB_FOREGROUND
#define WJL_KB_FOREGROUND GetForegroundWindow
#endif
#ifndef WJL_KB_WINDOW_PID
#define WJL_KB_WINDOW_PID GetWindowThreadProcessId
#endif
#ifndef WJL_KB_VISIBLE
#define WJL_KB_VISIBLE IsWindowVisible
#endif
#ifndef WJL_KB_NOW
#define WJL_KB_NOW GetTickCount64
#endif
#ifndef WJL_KB_HOOK
#define WJL_KB_HOOK SetWinEventHook
#endif
#ifndef WJL_KB_UNHOOK
#define WJL_KB_UNHOOK UnhookWinEvent
#endif

static int wjl_keyboard_bit(const uint32_t mask[8], unsigned int key) {
    return (mask[key >> 5] & (1u << (key & 31))) != 0;
}
static int wjl_keyboard_mask_valid(const uint32_t mask[8]) {
    uint32_t any = 0;
    static const unsigned int groups[3][3] = {{16,160,161},{17,162,163},{18,164,165}};
    if (!mask) return 0;
    for (unsigned int i = 0; i < 8; ++i) {
        if (mask[i] & ~wjl_keyboard_allowed[i]) return 0;
        any |= mask[i];
    }
    if (!any) return 0;
    for (unsigned int i = 0; i < 3; ++i) {
        int bits = wjl_keyboard_bit(mask, groups[i][0]) + wjl_keyboard_bit(mask, groups[i][1]) +
                   wjl_keyboard_bit(mask, groups[i][2]);
        if (bits && bits != 3) return 0;
    }
    return 1;
}
static int wjl_keyboard_tuple(unsigned int key, unsigned int modifiers) {
    /* Preserve the desktop's Ctrl+Shift+Space shortcut. It is already owned
     * on this Windows host; a single collision otherwise aborts all gameplay keys. */
    if (key == VK_SPACE && modifiers == (MOD_CONTROL | MOD_SHIFT)) return 0;
    if (key >= 160 && key <= 165) return 0;
    if ((modifiers & MOD_ALT) && (key == VK_TAB || key == VK_ESCAPE || key == VK_F4 ||
        key == VK_RETURN || key == VK_SPACE)) return 0;
    if ((modifiers & MOD_CONTROL) && key == VK_ESCAPE) return 0;
    if ((modifiers & (MOD_CONTROL | MOD_ALT)) == (MOD_CONTROL | MOD_ALT) && key == VK_DELETE) return 0;
    return 1;
}
static unsigned int wjl_keyboard_modifiers(unsigned int index) {
    return ((index & 1) ? MOD_SHIFT : 0u) | ((index & 2) ? MOD_CONTROL : 0u) |
           ((index & 4) ? MOD_ALT : 0u);
}
static int wjl_keyboard_foreground(const WJLSteamKeyboardLease *lease) {
    DWORD pid = 0;
    HWND window = WJL_KB_FOREGROUND();
    if (!window || window != lease->target || !WJL_KB_VISIBLE(window)) return 0;
    WJL_KB_WINDOW_PID(window, &pid);
    return pid == lease->pid;
}
static int wjl_keyboard_held(const uint32_t mask[8]) {
    for (unsigned int key = 0; key < 256; ++key)
        if (wjl_keyboard_bit(mask, key) && (WJL_KB_ASYNC((int)key) & 0x8000)) return 1;
    return 0;
}

/* Read-only identity proof: an ordinary query handle, exact canonical stock
 * executable path, and process creation time. No target VM permissions. */
#ifndef WJL_KB_IDENTIFY
static int wjl_keyboard_canonical(const wchar_t *path, wchar_t result[32768]) {
    HANDLE file = CreateFileW(path, FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    DWORD count;
    if (file == INVALID_HANDLE_VALUE) return 0;
    count = GetFinalPathNameByHandleW(file, result, 32768, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    CloseHandle(file);
    return count > 0 && count < 32768;
}
static DWORD wjl_keyboard_identify(DWORD pid, const wchar_t *expected, HANDLE *process, FILETIME *creation) {
    wchar_t actual[32768], canonical_actual[32768], canonical_expected[32768];
    DWORD count = 32768, error = ERROR_ACCESS_DENIED;
    FILETIME exited, kernel, user;
    HANDLE handle;
    *process = NULL;
    if (!pid || !expected || !expected[0]) return ERROR_INVALID_PARAMETER;
    handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
    if (!handle) return GetLastError();
    if (GetProcessTimes(handle, creation, &exited, &kernel, &user) &&
        QueryFullProcessImageNameW(handle, 0, actual, &count) &&
        wjl_keyboard_canonical(actual, canonical_actual) && wjl_keyboard_canonical(expected, canonical_expected) &&
        CompareStringOrdinal(canonical_actual, -1, canonical_expected, -1, TRUE) == CSTR_EQUAL &&
        WaitForSingleObject(handle, 0) == WAIT_TIMEOUT) {
        *process = handle;
        return 0;
    }
    CloseHandle(handle);
    return error;
}
#define WJL_KB_IDENTIFY wjl_keyboard_identify
#endif

static void wjl_keyboard_reply_locked(WJLSteamKeyboardReply *out) {
    out->version = WJL_KEYBOARD_VERSION;
    out->client = wjl_keyboard_lease.client;
    out->generation = wjl_keyboard_lease.generation;
    AcquireSRWLockShared(&wjl_keyboard_data);
    out->state = wjl_keyboard_lease.state;
    memcpy(out->mask, wjl_keyboard_lease.mask, sizeof(out->mask));
    ReleaseSRWLockShared(&wjl_keyboard_data);
}
/* Only the message thread calls this function. Failed removal is retained as
 * FAILED until the actual thread has retired (thread exit frees its hotkeys). */
static int wjl_keyboard_unregister_worker(WJLSteamKeyboardLease *lease) {
    int clean = 1;
    while (lease->registration_count) {
        int id = lease->registrations[--lease->registration_count];
        if (!WJL_KB_UNREGISTER(lease->window, id)) clean = 0;
    }
    if (!clean) {
        AcquireSRWLockExclusive(&wjl_keyboard_data);
        lease->error = ERROR_BUSY;
        lease->terminal = WJL_KEYBOARD_FAILED;
        ReleaseSRWLockExclusive(&wjl_keyboard_data);
    }
    return clean;
}
static void wjl_keyboard_stop_request(uint32_t terminal, DWORD error) {
    AcquireSRWLockExclusive(&wjl_keyboard_data);
    if (wjl_keyboard_lease.state == WJL_KEYBOARD_ARMING || wjl_keyboard_lease.state == WJL_KEYBOARD_ACTIVE) {
        wjl_keyboard_lease.state = WJL_KEYBOARD_CLOSING;
        wjl_keyboard_lease.terminal = terminal;
        wjl_keyboard_lease.error = error;
    }
    ReleaseSRWLockExclusive(&wjl_keyboard_data);
    if (wjl_keyboard_lease.stop) SetEvent(wjl_keyboard_lease.stop);
}
/* Checking/renewing the deadline and changing its state use the same lock.
 * A snapshot cannot revive an expired lease, and a worker using an earlier
 * deadline cannot revoke a heartbeat that has just renewed it. */
static uint32_t wjl_keyboard_deadline(int renew) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    uint32_t state;
    int expired = 0;
    AcquireSRWLockExclusive(&wjl_keyboard_data);
    if (lease->state == WJL_KEYBOARD_ACTIVE) {
        ULONGLONG now = WJL_KB_NOW();
        if (now - lease->heartbeat >= WJL_KEYBOARD_TTL_MS) {
            lease->state = WJL_KEYBOARD_CLOSING;
            lease->terminal = WJL_KEYBOARD_REVOKED;
            lease->error = ERROR_TIMEOUT;
            expired = 1;
        } else if (renew) lease->heartbeat = now;
    }
    state = lease->state;
    ReleaseSRWLockExclusive(&wjl_keyboard_data);
    if (expired) SetEvent(lease->stop);
    return state;
}
static void CALLBACK wjl_keyboard_foreground_event(HWINEVENTHOOK hook, DWORD event, HWND window,
                                                  LONG object, LONG child, DWORD thread, DWORD time) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    (void)hook; (void)object; (void)child; (void)thread; (void)time;
    if (event != EVENT_SYSTEM_FOREGROUND || window == lease->target || lease->revoking) return;
    lease->revoking = 1;
    wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
    wjl_keyboard_unregister_worker(lease);
}
static LRESULT CALLBACK wjl_keyboard_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_HOTKEY) return 0;
    return DefWindowProcW(window, message, wp, lp);
}
static int wjl_keyboard_messages(void) {
    MSG message;
    for (unsigned int count = 0; count < 64 && PeekMessageW(&message, NULL, 0, 0, PM_REMOVE); ++count) {
        if (message.message == WM_QUIT) return 0;
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return 1;
}
static int wjl_keyboard_register_worker(WJLSteamKeyboardLease *lease) {
    ULONGLONG started = WJL_KB_NOW();
    for (unsigned int key = 0; key < 256; ++key) {
        if (!wjl_keyboard_bit(lease->mask, key) || (key >= 160 && key <= 165)) continue;
        for (unsigned int variant = 0; variant < 8; ++variant) {
            unsigned int modifiers = wjl_keyboard_modifiers(variant);
            int id = 1 + (int)(key * 8 + variant);
            if (!wjl_keyboard_tuple(key, modifiers)) continue;
            /* Registration is a bounded transition; foreground notifications
             * are dispatched between tuples rather than queued until the end. */
            if (!wjl_keyboard_messages() || WaitForSingleObject(lease->stop, 0) != WAIT_TIMEOUT ||
                !wjl_keyboard_foreground(lease) || WaitForSingleObject(lease->process, 0) != WAIT_TIMEOUT) {
                wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
                return 0;
            }
            if (WJL_KB_NOW() - started >= WJL_KEYBOARD_COMMAND_MS) {
                wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, ERROR_TIMEOUT);
                return 0;
            }
            if (!WJL_KB_REGISTER(lease->window, id, modifiers | MOD_NOREPEAT, key)) {
                DWORD error = GetLastError();
                /* Another application owns this exact shortcut (GPU overlays,
                 * recorders, chat). Windows delivers it to that owner, never to
                 * the game, so it is isolated already. Keep the other keys. */
                if (error == ERROR_HOTKEY_ALREADY_REGISTERED) {
                    if (lease->shared_count < 8) lease->shared[lease->shared_count] = key | modifiers << 8;
                    ++lease->shared_count;
                    continue;
                }
                wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, error ? error : ERROR_HOTKEY_ALREADY_REGISTERED);
                return 0;
            }
            lease->registrations[lease->registration_count++] = id;
        }
    }
    /* The bulk reservation is not atomic. A key pressed before its tuple was
     * reserved may already be held by the game. Never claim ACTIVE in that
     * state, and never return to ARMING with existing IDs registered. */
    if (wjl_keyboard_held(lease->mask)) {
        wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, ERROR_BUSY);
        return 0;
    }
    if (WJL_KB_NOW() - started >= WJL_KEYBOARD_COMMAND_MS) {
        wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, ERROR_TIMEOUT);
        return 0;
    }
    if (WaitForSingleObject(lease->stop, 0) != WAIT_TIMEOUT || !wjl_keyboard_foreground(lease) ||
        WaitForSingleObject(lease->process, 0) != WAIT_TIMEOUT) {
        wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
        return 0;
    }
    AcquireSRWLockExclusive(&wjl_keyboard_data);
    lease->register_ms = WJL_KB_NOW() - started;
    if (lease->state == WJL_KEYBOARD_ARMING) {
        lease->heartbeat = WJL_KB_NOW();
        lease->state = WJL_KEYBOARD_ACTIVE;
    }
    ReleaseSRWLockExclusive(&wjl_keyboard_data);
    return 1;
}
static DWORD WINAPI wjl_keyboard_thread(void *unused) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSW type;
    HANDLE waits[2];
    int owns_class = 0;
    (void)unused;
    ZeroMemory(&type, sizeof(type));
    type.lpfnWndProc = wjl_keyboard_proc;
    type.hInstance = instance;
    type.lpszClassName = wjl_keyboard_class;
    if (!RegisterClassW(&type)) goto setup_failed;
    owns_class = 1;
    lease->window = CreateWindowExW(0, wjl_keyboard_class, L"", 0, 0, 0, 0, 0,
                                   HWND_MESSAGE, NULL, instance, NULL);
    if (!lease->window) goto setup_failed;
    lease->foreground_hook = WJL_KB_HOOK(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL,
        wjl_keyboard_foreground_event, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (!lease->foreground_hook) goto setup_failed;
    waits[0] = lease->stop;
    waits[1] = lease->process;
    for (;;) {
        uint32_t state;
        ULONGLONG now, heartbeat;
        DWORD timeout, result;
        AcquireSRWLockShared(&wjl_keyboard_data);
        state = lease->state;
        heartbeat = lease->heartbeat;
        ReleaseSRWLockShared(&wjl_keyboard_data);
        now = WJL_KB_NOW();
        if (state != WJL_KEYBOARD_ARMING && state != WJL_KEYBOARD_ACTIVE) break;
        if (state == WJL_KEYBOARD_ARMING) {
            if (!wjl_keyboard_foreground(lease)) {
                wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED); break;
            }
            if (now - lease->started >= WJL_KEYBOARD_ARM_MS) {
                wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, ERROR_TIMEOUT); break;
            }
            /* No raw sink is registered. This finite qualification is the only
             * timed key sampling: at most 2 seconds, then no idle retry/rearm. */
            if (!wjl_keyboard_held(lease->mask)) {
                if (!wjl_keyboard_register_worker(lease)) break;
                SetEvent(lease->ready);
                continue;
            }
            now = WJL_KB_NOW();
            if (now - lease->started >= WJL_KEYBOARD_ARM_MS) {
                wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, ERROR_TIMEOUT); break;
            }
            timeout = WJL_KEYBOARD_ARM_MS - (DWORD)(now - lease->started);
            if (timeout > 16) timeout = 16;
        } else {
            ULONGLONG elapsed = now - heartbeat;
            if (elapsed >= WJL_KEYBOARD_TTL_MS) {
                if (wjl_keyboard_deadline(0) != WJL_KEYBOARD_ACTIVE) break;
                continue;
            }
            timeout = WJL_KEYBOARD_TTL_MS - (DWORD)elapsed;
        }
        result = MsgWaitForMultipleObjectsEx(2, waits, timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (result == WAIT_OBJECT_0) break;
        if (result == WAIT_OBJECT_0 + 1) {
            wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_PROCESS_ABORTED); break;
        }
        if (result == WAIT_OBJECT_0 + 2) {
            if (!wjl_keyboard_messages()) { wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED); break; }
        } else if (result != WAIT_TIMEOUT) {
            wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, GetLastError()); break;
        }
        /* A heartbeat does not wake this thread. At the previous deadline the
         * next loop recomputes the remaining TTL without key/foreground reads. */
    }
    goto done;
setup_failed:
    { DWORD error = GetLastError(); wjl_keyboard_stop_request(WJL_KEYBOARD_FAILED, error ? error : ERROR_NOT_READY); }
done:
    wjl_keyboard_unregister_worker(lease);
    if (lease->foreground_hook && !WJL_KB_UNHOOK(lease->foreground_hook)) {
        AcquireSRWLockExclusive(&wjl_keyboard_data);
        lease->terminal = WJL_KEYBOARD_FAILED;
        lease->error = ERROR_BUSY;
        ReleaseSRWLockExclusive(&wjl_keyboard_data);
    }
    lease->foreground_hook = NULL;
    if (lease->window) DestroyWindow(lease->window);
    lease->window = NULL;
    if (owns_class) UnregisterClassW(wjl_keyboard_class, instance);
    AcquireSRWLockExclusive(&wjl_keyboard_data);
    lease->state = lease->terminal ? lease->terminal : WJL_KEYBOARD_REVOKED;
    ReleaseSRWLockExclusive(&wjl_keyboard_data);
    SetEvent(lease->ready);
    return 0;
}

/* Lifecycle lock held. Never close a handle or reset storage under a live
 * worker. Keeping one retired pair makes explicit release idempotent without
 * a token history; a stale pair can never close a new lease. */
static int wjl_keyboard_reap_locked(DWORD timeout) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    if (!lease->thread) return 1;
    if (WaitForSingleObject(lease->thread, timeout) != WAIT_OBJECT_0) return 0;
    wjl_keyboard_retired.pid = lease->pid;
    wjl_keyboard_retired.client = lease->client;
    wjl_keyboard_retired.generation = lease->generation;
    CloseHandle(lease->thread);
    CloseHandle(lease->ready);
    CloseHandle(lease->stop);
    CloseHandle(lease->process);
    ZeroMemory(lease, sizeof(*lease));
    return 1;
}
static int wjl_keyboard_same_session(DWORD pid, const FILETIME *creation) {
    return !wjl_keyboard_session_pid || (pid == wjl_keyboard_session_pid &&
        CompareFileTime(creation, &wjl_keyboard_session_creation) == 0);
}

DWORD wjl_keyboard_acquire(DWORD pid, const wchar_t *expected, uint32_t client,
                           const uint32_t mask[8], WJLSteamKeyboardReply *out) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    HANDLE process = NULL;
    FILETIME creation;
    DWORD error = ERROR_INVALID_PARAMETER, foreground_pid = 0;
    HWND foreground;
    if (!out || !client || !wjl_keyboard_mask_valid(mask)) return ERROR_INVALID_PARAMETER;
    ZeroMemory(out, sizeof(*out));
    AcquireSRWLockExclusive(&wjl_keyboard_lifecycle);
    wjl_keyboard_reap_locked(0);
    if (lease->thread) {
        if (pid == lease->pid && client == lease->client && !memcmp(mask, lease->mask, sizeof(lease->mask))) {
            wjl_keyboard_reply_locked(out); error = 0;
        } else error = ERROR_BUSY;
        goto done;
    }
    if (client <= wjl_keyboard_highest_client || wjl_keyboard_last_generation == UINT32_MAX) goto done;
    error = WJL_KB_IDENTIFY(pid, expected, &process, &creation);
    if (error) goto done;
    if (!wjl_keyboard_same_session(pid, &creation)) { error = ERROR_ACCESS_DENIED; goto done; }
    foreground = WJL_KB_FOREGROUND();
    if (foreground) WJL_KB_WINDOW_PID(foreground, &foreground_pid);
    if (!foreground || foreground_pid != pid || !WJL_KB_VISIBLE(foreground)) { error = ERROR_NOT_READY; goto done; }
    lease->ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!lease->ready) { error = GetLastError(); goto failed_setup; }
    lease->stop = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!lease->stop) { error = GetLastError(); goto failed_setup; }
    lease->pid = pid; lease->target = foreground; lease->process = process; process = NULL;
    lease->creation = creation; lease->client = client;
    lease->generation = ++wjl_keyboard_last_generation;
    lease->state = WJL_KEYBOARD_ARMING;
    lease->terminal = WJL_KEYBOARD_REVOKED;
    memcpy(lease->mask, mask, sizeof(lease->mask));
    lease->started = lease->heartbeat = WJL_KB_NOW();
    /* Accepted ownership is recorded BEFORE a worker can register anything.
     * A lost reply can therefore always be rolled back by exact client/gen0. */
    wjl_keyboard_highest_client = client;
    wjl_keyboard_session_pid = pid;
    wjl_keyboard_session_creation = creation;
    lease->thread = CreateThread(NULL, 0, wjl_keyboard_thread, NULL, 0, NULL);
    if (!lease->thread) {
        error = GetLastError();
        wjl_keyboard_retired.pid = pid; wjl_keyboard_retired.client = client;
        wjl_keyboard_retired.generation = lease->generation;
        goto failed_setup;
    }
    /* Do not wait on UI activation. ARMING is an accepted lease, never a
     * promise that keys are suppressed; a later explicit sample sees ACTIVE. */
    wjl_keyboard_reply_locked(out);
    error = 0;
    goto done;
failed_setup:
    if (lease->process) CloseHandle(lease->process);
    if (lease->ready) CloseHandle(lease->ready);
    if (lease->stop) CloseHandle(lease->stop);
    ZeroMemory(lease, sizeof(*lease));
done:
    if (process) CloseHandle(process);
    ReleaseSRWLockExclusive(&wjl_keyboard_lifecycle);
    return error;
}

DWORD wjl_keyboard_snapshot(DWORD pid, uint32_t client, uint32_t generation, WJLSteamKeyboardSample *out) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    DWORD error = ERROR_NOT_FOUND;
    uint32_t state;
    if (!out || !client || !generation) return ERROR_INVALID_PARAMETER;
    ZeroMemory(out, sizeof(*out));
    AcquireSRWLockShared(&wjl_keyboard_lifecycle);
    if (!lease->thread || pid != lease->pid || client != lease->client || generation != lease->generation) goto done;
    out->version = WJL_KEYBOARD_VERSION; out->generation = generation;
    state = wjl_keyboard_deadline(0);
    if (state == WJL_KEYBOARD_ACTIVE) {
        if (!wjl_keyboard_foreground(lease) || WaitForSingleObject(lease->process, 0) != WAIT_TIMEOUT) {
            wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
        } else {
            /* One physical read per captured key, only on an explicit active
             * sample. The high bit is current state; the low bit is ignored.
             * No engine keyboard reader is replaced or modified. */
            for (unsigned int key = 0; key < 256; ++key)
                if (wjl_keyboard_bit(lease->mask, key) && (WJL_KB_ASYNC((int)key) & 0x8000))
                    out->keys[key >> 5] |= 1u << (key & 31);
            if (!wjl_keyboard_foreground(lease)) {
                ZeroMemory(out->keys, sizeof(out->keys));
                wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
            } else {
                wjl_keyboard_deadline(1);
            }
        }
    }
    AcquireSRWLockShared(&wjl_keyboard_data);
    out->state = lease->state;
    ReleaseSRWLockShared(&wjl_keyboard_data);
    if (out->state != WJL_KEYBOARD_ACTIVE) ZeroMemory(out->keys, sizeof(out->keys));
    error = 0;
done:
    ReleaseSRWLockShared(&wjl_keyboard_lifecycle);
    return error;
}

/* Final fence after the service takes its single pointer sample. This does
 * not read keys or renew the heartbeat, and cannot revive an expired lease. */
uint32_t wjl_keyboard_confirm(DWORD pid, uint32_t client, uint32_t generation) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    uint32_t state = WJL_KEYBOARD_FAILED;
    AcquireSRWLockShared(&wjl_keyboard_lifecycle);
    if (!lease->thread || pid != lease->pid || client != lease->client || generation != lease->generation) goto done;
    state = wjl_keyboard_deadline(0);
    if (state == WJL_KEYBOARD_ACTIVE && (!wjl_keyboard_foreground(lease) ||
        WaitForSingleObject(lease->process, 0) != WAIT_TIMEOUT)) {
        wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
        AcquireSRWLockShared(&wjl_keyboard_data);
        state = lease->state;
        ReleaseSRWLockShared(&wjl_keyboard_data);
    }
done:
    ReleaseSRWLockShared(&wjl_keyboard_lifecycle);
    return state;
}

DWORD wjl_keyboard_release(DWORD pid, const wchar_t *expected, uint32_t client, uint32_t generation,
                           uint32_t *released_generation) {
    WJLSteamKeyboardLease *lease = &wjl_keyboard_lease;
    DWORD error = ERROR_NOT_FOUND;
    HANDLE process = NULL;
    FILETIME creation;
    if (!client || !released_generation) return ERROR_INVALID_PARAMETER;
    *released_generation = 0;
    AcquireSRWLockExclusive(&wjl_keyboard_lifecycle);
    /* A matching current pair is preferred over any retired acknowledgement. */
    if (lease->thread && pid == lease->pid && client == lease->client &&
        (!generation || generation == lease->generation)) {
        uint32_t owned_generation = lease->generation;
        wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
        if (!wjl_keyboard_reap_locked(WJL_KEYBOARD_COMMAND_MS)) { error = ERROR_TIMEOUT; goto done; }
        *released_generation = owned_generation; error = 0; goto done;
    }
    if (pid == wjl_keyboard_retired.pid && client == wjl_keyboard_retired.client &&
        (!generation || generation == wjl_keyboard_retired.generation)) {
        *released_generation = wjl_keyboard_retired.generation; error = 0; goto done;
    }
    /* Never-owned rollback after an explicit refusal/lost request. Serialized
     * authenticated pipe requests cannot later accept this old request. This
     * acknowledgement changes neither a current lease nor the retired pair. */
    if (!generation && client > wjl_keyboard_highest_client) {
        error = WJL_KB_IDENTIFY(pid, expected, &process, &creation);
        if (!error && !wjl_keyboard_same_session(pid, &creation)) error = ERROR_ACCESS_DENIED;
    }
done:
    if (process) CloseHandle(process);
    ReleaseSRWLockExclusive(&wjl_keyboard_lifecycle);
    return error;
}

void wjl_keyboard_cancel_all(void) {
    AcquireSRWLockShared(&wjl_keyboard_lifecycle);
    if (wjl_keyboard_lease.thread) wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
    ReleaseSRWLockShared(&wjl_keyboard_lifecycle);
}
int wjl_keyboard_shutdown(void) {
    int clean;
    AcquireSRWLockExclusive(&wjl_keyboard_lifecycle);
    if (wjl_keyboard_lease.thread) wjl_keyboard_stop_request(WJL_KEYBOARD_REVOKED, ERROR_CANCELLED);
    clean = wjl_keyboard_reap_locked(WJL_KEYBOARD_COMMAND_MS);
    ReleaseSRWLockExclusive(&wjl_keyboard_lifecycle);
    return clean;
}

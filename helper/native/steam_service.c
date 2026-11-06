/* External filesystem, leased pointer and bulk codec service. No DLL is loaded into Helldivers 2; no process
 * memory, hooks or changes to code-integrity policy. Local byte pipes only. */
#include "steam_files.c"
#include "steam_pointer.c"
#include "steam_screenshot_jobs.c"
#include "steam_keyboard.c"
#include "steam_codec.c"
#include <shellapi.h>
#include <share.h>

static HANDLE io_event;
static FILE *service_log;
static unsigned char *listing_bytes;
static uint32_t listing_capacity;
static void note(const char *message) {
    if (service_log) { fprintf(service_log, "%s\n", message); fflush(service_log); }
}
static int transfer(HANDLE pipe, void *bytes, DWORD size, int writing) {
    unsigned char *at = bytes;
    while (size) {
        OVERLAPPED pending = {0};
        DWORD count = 0, error;
        BOOL ok;
        pending.hEvent = io_event; ResetEvent(io_event);
        ok = writing ? WriteFile(pipe, at, size, &count, &pending) : ReadFile(pipe, at, size, &count, &pending);
        error = ok ? 0 : GetLastError();
        if (!ok && error == ERROR_IO_PENDING) {
            if (WaitForSingleObject(io_event, INFINITE) != WAIT_OBJECT_0) return 0;
            ok = GetOverlappedResult(pipe, &pending, &count, FALSE);
        }
        if (!ok || !count) return 0;
        at += count; size -= count;
    }
    return 1;
}
static int connect_pipe(HANDLE pipe) {
    OVERLAPPED pending = {0};
    DWORD error, count;
    pending.hEvent = io_event; ResetEvent(io_event);
    if (ConnectNamedPipe(pipe, &pending)) return 1;
    error = GetLastError();
    if (error == ERROR_PIPE_CONNECTED) return 1;
    if (error != ERROR_IO_PENDING) return 0;
    if (WaitForSingleObject(io_event, 30 * 60 * 1000) != WAIT_OBJECT_0) {
        CancelIoEx(pipe, &pending); GetOverlappedResult(pipe, &pending, &count, TRUE); return 0;
    }
    return GetOverlappedResult(pipe, &pending, &count, FALSE) != 0;
}
static int send_file(HANDLE pipe) {
    FILE *stream = NULL;
    unsigned char *bytes;
    long length;
    DWORD size;
    int ok;
    if (_wfopen_s(&stream, response_file, L"rb")) return 0;
    if (fseek(stream, 0, SEEK_END) || (length=ftell(stream))<8 || length>MAX_REQUEST || fseek(stream,0,SEEK_SET)) { fclose(stream);return 0; }
    size=(DWORD)length; bytes=malloc(size);
    if (!bytes) { fclose(stream);return 0; }
    ok=fread(bytes,1,size,stream)==size; fclose(stream);
    if (ok) ok=transfer(pipe,&size,4,1) && transfer(pipe,bytes,size,1);
    free(bytes);return ok;
}

/* Reuse one bounded buffer across explicit discovery requests. Enumeration
 * never creates transport files or wakes a watcher on the service directory. */
static DWORD listing_reserve(uint32_t needed) {
    uint32_t capacity;
    unsigned char *larger;
    if (needed > MAX_REQUEST) return ERROR_MORE_DATA;
    if (needed <= listing_capacity) return 0;
    capacity = listing_capacity ? listing_capacity : 4096;
    while (capacity < needed) capacity = capacity > MAX_REQUEST / 2 ? MAX_REQUEST : capacity * 2;
    larger = realloc(listing_bytes, capacity);
    if (!larger) return ERROR_NOT_ENOUGH_MEMORY;
    listing_bytes = larger;
    listing_capacity = capacity;
    return 0;
}

static int decode_path(const unsigned char *bytes, uint32_t size, uint32_t path_size, wchar_t path[32768]) {
    int count = 0;
    if (path_size && path_size <= 32760 && size == 12 + path_size && !memchr(bytes + 12, 0, path_size))
        count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)bytes + 12, (int)path_size, path, 32767);
    if (count <= 0) return 0;
    path[count] = 0;
    for (int index = 0; index < count; ++index) if (path[index] == L'/') path[index] = L'\\';
    return 1;
}

static int send_listing(uint32_t nonce, const wchar_t *path, HANDLE outgoing) {
    uint32_t header[2] = {nonce, ERROR_INVALID_DATA}, length = 8, count = 0;
    WIN32_FIND_DATAW data;
    HANDLE handle = INVALID_HANDLE_VALUE;
    wchar_t pattern[32768];
    DWORD status;
    if (!path) goto header_only;
    status = listing_reserve(length);
    if (status) { header[1] = status; goto header_only; }
    swprintf_s(pattern, 32768, L"%s\\*", path);
    handle = FindFirstFileW(pattern, &data);
    if (handle == INVALID_HANDLE_VALUE) { header[1] = GetLastError(); goto header_only; }
    do {
        uint32_t fields[6], name_size;
        char name[4 * MAX_PATH];
        int encoded;
        if (!wcscmp(data.cFileName, L".") || !wcscmp(data.cFileName, L"..")) continue;
        if (++count > 100000) { status = ERROR_MORE_DATA; goto finished; }
        encoded = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, data.cFileName, -1,
                                      name, (int)sizeof(name), NULL, NULL);
        /* Match the legacy text serializer for an invalid UTF-16 name. */
        name_size = encoded > 0 ? (uint32_t)encoded - 1 : 0;
        status = listing_reserve(length + 24 + name_size);
        if (status) goto finished;
        fields[0] = data.dwFileAttributes;
        fields[1] = data.nFileSizeHigh;
        fields[2] = data.nFileSizeLow;
        fields[3] = data.ftLastWriteTime.dwHighDateTime;
        fields[4] = data.ftLastWriteTime.dwLowDateTime;
        fields[5] = name_size;
        memcpy(listing_bytes + length, fields, sizeof(fields)); length += 24;
        memcpy(listing_bytes + length, name, name_size); length += name_size;
    } while (FindNextFileW(handle, &data));
    status = GetLastError() == ERROR_NO_MORE_FILES ? 0 : ERROR_MORE_DATA;
finished:
    FindClose(handle);
    header[1] = status;
    memcpy(listing_bytes, header, sizeof(header));
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, listing_bytes, length, 1) ? 2 : 0;
header_only:
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, header, length, 1) ? 2 : 0;
}

static int send_screenshot(uint32_t nonce,uint32_t operation,const wchar_t *path,HANDLE outgoing) {
    WJLScreenshotJobStatus status;
    uint32_t fields[8]={nonce,ERROR_INVALID_DATA,0},length=8,path_size;
    int encoded;
    if (!path) goto header_only;
    if (operation==13) {
        /* Allocate and encode the exact immutable reply path BEFORE accepting
         * a worker: a rejected request must never leave an unacknowledged job. */
        encoded=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,path,-1,NULL,0,NULL,NULL);
        if (encoded<=0) goto header_only;
        path_size=(uint32_t)encoded-1;length=68+path_size;
        fields[1]=listing_reserve(length+1);if (fields[1]) goto header_only;
        if (WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,path,-1,(char*)listing_bytes+68,encoded,NULL,NULL)!=encoded) { fields[1]=ERROR_INVALID_DATA;goto header_only; }
        fields[1]=wjl_screenshot_job_request(session_pid,executable,path,&status);
        if (fields[1]) goto header_only;
        if (strlen(status.id)!=32) return 0; /* Accepted: transport-uncertain, never a false rejection. */
    } else {
        fields[1]=operation==14?wjl_screenshot_job_status(path,&status):wjl_screenshot_job_cancel(path,&status);
        if (fields[1]) goto header_only;
        encoded=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,status.output_path,-1,NULL,0,NULL,NULL);
        if (encoded<=0||strlen(status.id)!=32) { fields[1]=ERROR_INVALID_DATA;goto header_only; }
        path_size=(uint32_t)encoded-1;length=68+path_size;
        fields[1]=listing_reserve(length+1);if (fields[1]) goto header_only;
        if (WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,status.output_path,-1,(char*)listing_bytes+68,encoded,NULL,NULL)!=encoded) { fields[1]=ERROR_INVALID_DATA;goto header_only; }
    }
    fields[2]=status.state;fields[3]=status.error;fields[4]=status.width;fields[5]=status.height;fields[6]=status.elapsed_ms;fields[7]=32;
    memcpy(listing_bytes,fields,sizeof(fields));memcpy(listing_bytes+32,status.id,32);memcpy(listing_bytes+64,&path_size,4);
    return transfer(outgoing,&length,4,1)&&transfer(outgoing,listing_bytes,length,1)?2:0;
header_only:
    length=8;
    return transfer(outgoing,&length,4,1)&&transfer(outgoing,fields,length,1)?2:0;
}

/* Keyboard v1 never uses filesystem transport files. Error replies contain
 * only nonce/status; accepted replies have fixed 56/88/20-byte layouts. */
static int send_keyboard(uint32_t nonce, uint32_t operation, const unsigned char *bytes,
                         uint32_t size, uint32_t path_size, HANDLE outgoing) {
    static const char path[] = "keyboard-v1";
    uint32_t reply[22] = {0}, fields[10] = {0}, length = 8, extra;
    reply[0] = nonce; reply[1] = ERROR_INVALID_DATA;
    if (path_size != sizeof(path) - 1 || size < 12 + path_size ||
        memcmp(bytes + 12, path, sizeof(path) - 1)) goto done;
    extra = size - 12 - path_size;
    if ((operation == 16 && extra != 40) || (operation == 17 && extra != 12) ||
        (operation == 18 && extra != 8)) goto done;
    memcpy(fields, bytes + 12 + path_size, extra);
    if (operation == 16) {
        WJLSteamKeyboardReply accepted;
        if (fields[0] != WJL_KEYBOARD_VERSION) { reply[1] = ERROR_REVISION_MISMATCH; goto done; }
        reply[1] = wjl_keyboard_acquire(session_pid, executable, fields[1], fields + 2, &accepted);
        if (!reply[1]) { memcpy(reply + 2, &accepted, sizeof(accepted)); length = 56; }
    } else if (operation == 17) {
        WJLSteamKeyboardSample keyboard;
        WJLSteamPointerSample pointer;
        if (fields[2] > 1) { reply[1] = ERROR_INVALID_PARAMETER; goto done; }
        ZeroMemory(&pointer, sizeof(pointer));
        reply[1] = wjl_keyboard_snapshot(session_pid, fields[0], fields[1], &keyboard);
        if (reply[1]) goto done;
        {
            static uint32_t last_generation, last_state;
            if (last_generation != keyboard.generation || last_state != keyboard.state) {
                char message[384]; DWORD keyboard_error; uint32_t shared_count, shared[8]; int written;
                AcquireSRWLockShared(&wjl_keyboard_data);
                keyboard_error = wjl_keyboard_lease.error;
                shared_count = wjl_keyboard_lease.shared_count;
                memcpy(shared, wjl_keyboard_lease.shared, sizeof(shared));
                ReleaseSRWLockShared(&wjl_keyboard_data);
                written = sprintf_s(message, sizeof(message), "Keyboard generation=%u state=%u error=%lu shared=%u", keyboard.generation, keyboard.state, (unsigned long)keyboard_error, shared_count);
                for (uint32_t i = 0; i < shared_count && i < 8 && written > 0; ++i) {
                    uint32_t modifiers = shared[i] >> 8;
                    int added = _snprintf_s(message + written, sizeof(message) - (size_t)written, _TRUNCATE, "%s%s%s%sVK 0x%02X", i ? ", " : " owned elsewhere: ",
                        (modifiers & MOD_CONTROL) ? "Ctrl+" : "", (modifiers & MOD_SHIFT) ? "Shift+" : "", (modifiers & MOD_ALT) ? "Alt+" : "", shared[i] & 0xffu);
                    written = added > 0 ? written + added : -1;
                }
                note(message); last_generation=keyboard.generation; last_state=keyboard.state;
            }
        }
        if (keyboard.state == WJL_KEYBOARD_ACTIVE) {
            if (!wjl_pointer_start(session_pid) || !wjl_pointer_snapshot_extended(&pointer)) {
                reply[1] = ERROR_NOT_READY; goto done;
            }
            if (!fields[2]) { pointer.dx = 0; pointer.dy = 0; }
            keyboard.state = wjl_keyboard_confirm(session_pid, fields[0], fields[1]);
            if (keyboard.state != WJL_KEYBOARD_ACTIVE) {
                ZeroMemory(&pointer, sizeof(pointer)); ZeroMemory(keyboard.keys, sizeof(keyboard.keys));
            }
        }
        memcpy(reply + 2, &pointer, sizeof(pointer));
        memcpy(reply + 11, &keyboard, sizeof(keyboard));
        length = 88;
    } else {
        uint32_t generation = 0;
        reply[1] = wjl_keyboard_release(session_pid, executable, fields[0], fields[1], &generation);
        if (!reply[1]) {
            reply[2] = WJL_KEYBOARD_VERSION; reply[3] = fields[0]; reply[4] = generation; length = 20;
        }
    }
done:
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, reply, length, 1) ? 2 : 0;
}

/* Clipboard text read: read-only, CF_UNICODETEXT only, bounded and synchronous.
 * The service never owns the clipboard and never writes it. */
static int send_clipboard(uint32_t nonce, const unsigned char *bytes, uint32_t size,
                          uint32_t path_size, HANDLE outgoing) {
    static const char path[] = "clipboard";
    uint32_t reply[3] = {nonce, ERROR_INVALID_DATA, 0};
    uint32_t length = 12, needed = 0;
    HANDLE data = NULL;
    const wchar_t *text = NULL;
    SIZE_T units = 0;
    int encoded = 0;
    if (path_size != sizeof(path) - 1 || size != 12 + path_size ||
        memcmp(bytes + 12, path, sizeof(path) - 1)) goto done;
    if (!OpenClipboard(NULL)) { reply[1] = GetLastError(); goto done; }
    data = GetClipboardData(CF_UNICODETEXT);
    if (!data) { reply[1] = GetLastError(); goto finished; }
    text = (const wchar_t *)GlobalLock(data);
    if (!text) { reply[1] = GetLastError(); goto finished; }
    units = GlobalSize(data) / sizeof(wchar_t);
    while (units > 0 && text[units - 1] == 0) units--;
    if (units > 131072) units = 131072;
    encoded = units ? WideCharToMultiByte(CP_UTF8, 0, text, (int)units, NULL, 0, NULL, NULL) : 0;
    if (units && encoded <= 0) { reply[1] = ERROR_NO_UNICODE_TRANSLATION; goto finished; }
    needed = 12 + (uint32_t)encoded;
    reply[1] = listing_reserve(needed);
    if (reply[1]) goto finished;
    if (encoded && WideCharToMultiByte(CP_UTF8, 0, text, (int)units,
                                       (char *)listing_bytes + 12, encoded, NULL, NULL) != encoded) {
        reply[1] = ERROR_NO_UNICODE_TRANSLATION; goto finished;
    }
    reply[1] = 0;
    reply[2] = (uint32_t)encoded;
finished:
    if (text) GlobalUnlock(data);
    CloseClipboard();
done:
    if (reply[1] || !listing_bytes) {
        length = 12;
        return transfer(outgoing, &length, 4, 1) && transfer(outgoing, reply, length, 1) ? 2 : 0;
    }
    memcpy(listing_bytes, reply, sizeof(reply));
    length = needed;
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, listing_bytes, length, 1) ? 2 : 0;
}

/* Codec v1: one bounded LZNT1/XPRESS job per request. Request extra bytes are
 * version, mode, format, expected raw size, then the payload. Replies are
 * nonce/status/size followed by exactly size output bytes. */
static int send_codec(uint32_t nonce, const unsigned char *bytes, uint32_t size,
                      uint32_t path_size, HANDLE outgoing) {
    static const char path[] = "codec-v1";
    uint32_t reply[3] = {nonce, ERROR_INVALID_DATA, 0}, fields[4], length = 12, payload, capacity;
    if (path_size != sizeof(path) - 1 || size < 12 + path_size + 16 ||
        memcmp(bytes + 12, path, sizeof(path) - 1)) goto refused;
    memcpy(fields, bytes + 12 + path_size, sizeof(fields));
    if (fields[0] != WJL_CODEC_VERSION) { reply[1] = ERROR_REVISION_MISMATCH; goto refused; }
    payload = size - 12 - path_size - 16;
    if (payload > WJL_CODEC_MAX_PACKED || fields[3] > WJL_CODEC_MAX_RAW) { reply[1] = ERROR_INVALID_PARAMETER; goto refused; }
    capacity = wjl_codec_capacity(fields[1], payload, fields[3]);
    reply[1] = listing_reserve(12 + capacity);
    if (reply[1]) goto refused;
    reply[1] = wjl_codec_run(fields[1], fields[2], bytes + 12 + path_size + 16, payload, fields[3],
                             listing_bytes + 12, capacity, &reply[2]);
    if (reply[1]) { reply[2] = 0; goto refused; }
    memcpy(listing_bytes, reply, sizeof(reply));
    length = 12 + reply[2];
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, listing_bytes, length, 1) ? 2 : 0;
refused:
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, reply, length, 1) ? 2 : 0;
}

static int send_layout(uint32_t nonce, const unsigned char *bytes, uint32_t size,
                       uint32_t path_size, HANDLE outgoing) {
    static const char path[] = "layout-v1";
    static const UINT scancodes[6] = {0x11, 0x1E, 0x1F, 0x20, 0x10, 0x12};
    uint32_t reply[10] = {nonce, ERROR_INVALID_DATA, 0}, length = 12;
    DWORD owner = 0, thread = 0;
    HWND window = GetForegroundWindow();
    HKL layout;
    if (path_size != sizeof(path) - 1 || size != 12 + path_size || memcmp(bytes + 12, path, sizeof(path) - 1)) goto refused;
    if (window) thread = GetWindowThreadProcessId(window, &owner);
    layout = GetKeyboardLayout(thread && owner == session_pid ? thread : 0);
    for (int index = 0; index < 6; ++index) {
        reply[3 + index] = MapVirtualKeyExW(scancodes[index], MAPVK_VSC_TO_VK, layout);
        if (!reply[3 + index]) { reply[1] = ERROR_NOT_FOUND; goto refused; }
    }
    reply[1] = 0; reply[2] = 6; reply[9] = (uint32_t)(uintptr_t)layout; length = sizeof(reply);
refused:
    return transfer(outgoing, &length, 4, 1) && transfer(outgoing, reply, length, 1) ? 2 : 0;
}

static int dispatch(const unsigned char *bytes, uint32_t size, HANDLE outgoing) {
    uint32_t nonce, operation, path_size;
    FILE *stream = NULL;
    if (size<12) return 0;
    memcpy(&nonce,bytes,4);memcpy(&operation,bytes+4,4);memcpy(&path_size,bytes+8,4);
    if (operation==0) {
        if (size!=12 || nonce!=0 || path_size!=0) return 0;
        wjl_steam_boot(NULL);return 1;
    }
    if (operation==10 || operation==11 || operation==12) {
        uint32_t reply[11]={0},length=8;
        reply[0]=nonce;
        if (operation==11) {
            if (!wjl_pointer_release()) reply[1]=ERROR_BUSY;
        } else if (operation==10) {
            WJLSteamPointerSnapshot snapshot;
            if (!wjl_pointer_start(session_pid) || !wjl_pointer_snapshot(&snapshot)) reply[1]=ERROR_NOT_READY;
            else { memcpy(reply+2,&snapshot,sizeof(snapshot));length=8+(uint32_t)sizeof(snapshot); }
        } else {
            WJLSteamPointerSample snapshot;
            if (!wjl_pointer_start(session_pid) || !wjl_pointer_snapshot_extended(&snapshot)) reply[1]=ERROR_NOT_READY;
            else { memcpy(reply+2,&snapshot,sizeof(snapshot));length=8+(uint32_t)sizeof(snapshot); }
        }
        return transfer(outgoing,&length,4,1)&&transfer(outgoing,reply,length,1) ? 2 : 0;
    }
    if (operation==8 || operation==9) {
        uint32_t reply[MAX_WATCHES+4],length;
        if (operation==8) wjl_steam_poll(NULL);
        else { wjl_keyboard_cancel_all();wjl_screenshot_jobs_cancel_all();wjl_pointer_release();wjl_keyboard_shutdown();wjl_steam_close(NULL); }
        reply[0]=nonce;reply[1]=0;length=8;
        if (operation==8) {
            reply[2]=session_pid;reply[3]=watch_count;length=16+watch_count*4;
            for (uint32_t index=0;index<watch_count;++index) reply[index+4]=watches[index].generation;
        }
        /* Idle notifications never touch disk or invalidate a watched root. */
        return transfer(outgoing,&length,4,1)&&transfer(outgoing,reply,length,1) ? 2 : 0;
    }
    if (!nonce || path_size>size-12) return 0;
    if (operation>=16 && operation<=18) return send_keyboard(nonce,operation,bytes,size,path_size,outgoing);
    if (operation==19) return send_clipboard(nonce,bytes,size,path_size,outgoing);
    if (operation==20) return send_codec(nonce,bytes,size,path_size,outgoing);
    if (operation==21) return send_layout(nonce,bytes,size,path_size,outgoing);
    if (operation==13||operation==14||operation==15) {
        wchar_t path[32768];
        return send_screenshot(nonce,operation,decode_path(bytes,size,path_size,path)?path:NULL,outgoing);
    }
    if (operation==1) {
        wchar_t path[32768];
        return send_listing(nonce,decode_path(bytes,size,path_size,path)?path:NULL,outgoing);
    }
    if (operation==2) {
        uint32_t reply[7]={0},length=8;
        wchar_t path[32768];
        WIN32_FILE_ATTRIBUTE_DATA data;
        reply[0]=nonce;reply[1]=ERROR_INVALID_DATA;
        if (decode_path(bytes,size,path_size,path)) {
            if (GetFileAttributesExW(path,GetFileExInfoStandard,&data)) {
                reply[1]=0;reply[2]=data.dwFileAttributes;
                reply[3]=data.nFileSizeHigh;reply[4]=data.nFileSizeLow;
                reply[5]=data.ftLastWriteTime.dwHighDateTime;reply[6]=data.ftLastWriteTime.dwLowDateTime;length=28;
            } else reply[1]=GetLastError();
        }
        return transfer(outgoing,&length,4,1)&&transfer(outgoing,reply,length,1) ? 2 : 0;
    }
    if (_wfopen_s(&stream,request_file,L"wb")) return 0;
    if (fwrite(bytes,1,size,stream)!=size) { fclose(stream);return 0; }
    fclose(stream);wjl_steam_request(NULL);return 1;
}

#define WJL_CONTRACT_CHECKS 32u
#define WJL_CONTRACT_BUDGET (16u * 1024u * 1024u)
typedef struct WJLContractCheck { wchar_t file[64]; unsigned long long offset; DWORD size; char sha[65]; } WJLContractCheck;
static wchar_t wjl_resolved_root[32768];
static int wjl_decimal(const wchar_t *text, size_t length, unsigned long long limit, unsigned long long *value) {
    unsigned long long total = 0;
    if (!length || length > 20) return 0;
    for (size_t index = 0; index < length; ++index) {
        if (text[index] < L'0' || text[index] > L'9') return 0;
        total = total * 10u + (unsigned long long)(text[index] - L'0');
        if (total > limit) return 0;
    }
    *value = total; return 1;
}
static int wjl_hex_digit(wchar_t c) { return (c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || (c >= L'A' && c <= L'F'); }
static int wjl_hex64(const wchar_t *text, unsigned long long *value) {
    unsigned long long total = 0;
    if (!text || wcslen(text) != 16) return 0;
    for (size_t index = 0; index < 16; ++index) {
        wchar_t c = text[index];
        if (!wjl_hex_digit(c)) return 0;
        total = total << 4 | (unsigned long long)(c <= L'9' ? c - L'0' : (c | 0x20) - L'a' + 10);
    }
    *value = total; return 1;
}
static int wjl_lower_hex(const wchar_t *text, size_t length) {
    if (!text || wcslen(text) != length) return 0;
    for (size_t index = 0; index < length; ++index) if (!((text[index] >= L'0' && text[index] <= L'9') || (text[index] >= L'a' && text[index] <= L'f'))) return 0;
    return 1;
}
/* The game's own image, read with query-only access; the installation is the
 * folder above its bin folder. */
static int wjl_game_root(const wchar_t *text, DWORD *pid, wchar_t root[32768]) {
    unsigned long long value;
    DWORD size = 32768;
    HANDLE process;
    wchar_t *end;
    int ok = 0;
    if (!text || !wjl_decimal(text, wcslen(text), 0xffffffffu, &value) || !value) return 0;
    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)value);
    if (!process) return 0;
    if (QueryFullProcessImageNameW(process, 0, root, &size)) {
        end = wcsrchr(root, L'\\');
        if (end) { *end = 0; end = wcsrchr(root, L'\\'); ok = end && !_wcsicmp(end, L"\\bin"); if (ok) *end = 0; }
    }
    CloseHandle(process);
    *pid = (DWORD)value;
    return ok;
}
/* bundles.nxa or bundles.<digits>.nxa:offset:size:sha256 */
static int wjl_contract_check(const wchar_t *text, WJLContractCheck *check) {
    const wchar_t *colon[3] = {NULL, NULL, NULL};
    unsigned long long value;
    size_t found = 0, length;
    for (const wchar_t *at = text; *at; ++at) if (*at == L':') { if (found == 3) return 0; colon[found++] = at; }
    if (found != 3) return 0;
    length = (size_t)(colon[0] - text);
    if (!length || length >= 64) return 0;
    wmemcpy(check->file, text, length); check->file[length] = 0;
    if (wcscmp(check->file, L"bundles.nxa")) {
        if (length < 13 || wcsncmp(check->file, L"bundles.", 8) || wcscmp(check->file + length - 4, L".nxa")) return 0;
        for (size_t index = 8; index < length - 4; ++index) if (check->file[index] < L'0' || check->file[index] > L'9') return 0;
    }
    if (!wjl_decimal(colon[0] + 1, (size_t)(colon[1] - colon[0] - 1), 9007199254740991ull, &check->offset)) return 0;
    if (!wjl_decimal(colon[1] + 1, (size_t)(colon[2] - colon[1] - 1), WJL_CONTRACT_BUDGET, &value) || !value) return 0;
    check->size = (DWORD)value;
    if (!wjl_lower_hex(colon[2] + 1, 64)) return 0;
    for (size_t index = 0; index < 64; ++index) check->sha[index] = (char)colon[2][1 + index];
    check->sha[64] = 0;
    return 1;
}
static int wjl_hash_range(const wchar_t *path, unsigned long long offset, DWORD size, char output[65]) {
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    HANDLE file;
    LARGE_INTEGER length, at;
    unsigned char buffer[65536], value[32];
    DWORD count, want;
    int ok = 0;
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    at.QuadPart = (LONGLONG)offset;
    if (!GetFileSizeEx(file, &length) || (unsigned long long)length.QuadPart < offset + size || !SetFilePointerEx(file, at, NULL, FILE_BEGIN)) goto done;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0) goto done;
    if (BCryptCreateHash(algorithm, &hash, NULL, 0, NULL, 0, 0) < 0) goto done;
    while (size) {
        want = size < (DWORD)sizeof(buffer) ? size : (DWORD)sizeof(buffer);
        if (!ReadFile(file, buffer, want, &count, NULL) || count != want) goto done;
        if (BCryptHashData(hash, buffer, count, 0) < 0) goto done;
        size -= count;
    }
    if (BCryptFinishHash(hash, value, sizeof(value), 0) < 0) goto done;
    for (count = 0; count < 32; ++count) sprintf_s(output + count * 2, 3, "%02x", value[count]);
    ok = 1;
done:
    CloseHandle(file);
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    return ok;
}
/* <16 hex>.patch_<digits>, as the game names archive patches. */
static int wjl_patch_name(const wchar_t *name) {
    size_t length = wcslen(name);
    if (length < 24 || wcsncmp(name + 16, L".patch_", 7)) return 0;
    for (size_t index = 0; index < 16; ++index) if (!wjl_hex_digit(name[index])) return 0;
    for (size_t index = 23; index < length; ++index) if (name[index] < L'0' || name[index] > L'9') return 0;
    return 1;
}
/* No installed patch may replace the stock renderer configuration. The limits bound the
 * work for very large mod setups (1.3.1's 128 patches / 8,192 entries refused ordinary
 * ones and hid every scene effect); entry tables are read in 4,096-row blocks. */
#define WJL_RENDER_PATCHES 4096u
#define WJL_RENDER_TYPES 1024u
#define WJL_RENDER_ENTRIES 262144u
#define WJL_RENDER_TOTAL 4194304u
static unsigned char wjl_render_rows[4096 * 80];
static int wjl_renderer_untouched(const wchar_t *data, unsigned long long resource, unsigned long long type) {
    WIN32_FIND_DATAW found;
    wchar_t pattern[32768], path[32768];
    HANDLE search;
    unsigned int patches = 0, total = 0;
    int ok = 1;
    swprintf_s(pattern, 32768, L"%s\\*.patch_*", data);
    search = FindFirstFileW(pattern, &found);
    if (search == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
    for (;;) {
        if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && wjl_patch_name(found.cFileName)) {
            HANDLE file;
            unsigned char head[72];
            DWORD count;
            uint32_t magic = 0, types = 0, entries = 0;
            LARGE_INTEGER length, at;
            length.QuadPart = 0;
            if (++patches > WJL_RENDER_PATCHES) { ok = 0; break; }
            swprintf_s(path, 32768, L"%s\\%s", data, found.cFileName);
            file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
            if (file == INVALID_HANDLE_VALUE) { ok = 0; break; }
            ok = ReadFile(file, head, 72, &count, NULL) && count == 72 && GetFileSizeEx(file, &length);
            if (ok) {
                memcpy(&magic, head, 4); memcpy(&types, head + 4, 4); memcpy(&entries, head + 8, 4);
                ok = magic == 0xf0000011u && types <= WJL_RENDER_TYPES && entries <= WJL_RENDER_ENTRIES;
            }
            if (ok) { total += entries; ok = total <= WJL_RENDER_TOTAL && 72ull + 32ull * types + 80ull * entries <= (unsigned long long)length.QuadPart; }
            if (ok) { at.QuadPart = 72 + 32 * (LONGLONG)types; ok = SetFilePointerEx(file, at, NULL, FILE_BEGIN); }
            for (uint32_t done = 0; ok && done < entries;) {
                const uint32_t block = entries - done < 4096u ? entries - done : 4096u;
                ok = ReadFile(file, wjl_render_rows, block * 80u, &count, NULL) && count == block * 80u;
                for (uint32_t index = 0; ok && index < block; ++index) {
                    unsigned long long name, kind;
                    memcpy(&name, wjl_render_rows + index * 80u, 8); memcpy(&kind, wjl_render_rows + index * 80u + 8, 8);
                    if (name == resource && kind == type) ok = 0;
                }
                done += block;
            }
            CloseHandle(file);
            if (!ok) break;
        }
        if (!FindNextFileW(search, &found)) { ok = GetLastError() == ERROR_NO_MORE_FILES; break; }
    }
    FindClose(search);
    return ok;
}
static int wjl_verify_contract(const wchar_t *root, const WJLContractCheck *checks, unsigned int count,
                               unsigned long long resource, unsigned long long type) {
    wchar_t data[32768], path[32768];
    char hash[65];
    unsigned long long total = 0;
    swprintf_s(data, 32768, L"%s\\data", root);
    for (unsigned int index = 0; index < count; ++index) {
        total += checks[index].size;
        if (total > WJL_CONTRACT_BUDGET) return 0;
        swprintf_s(path, 32768, L"%s\\%s", data, checks[index].file);
        if (!wjl_hash_range(path, checks[index].offset, checks[index].size, hash) || strcmp(hash, checks[index].sha)) return 0;
    }
    return wjl_renderer_untouched(data, resource, type);
}
/* The proof Lua reads: <contract id>|<pipe token>, removed first so a stale
 * proof never survives a failed check. */
static void wjl_contract_proof(DWORD pid, const wchar_t *id, const wchar_t *token, int verified) {
    wchar_t path[MAX_PATH];
    char text[192];
    size_t length = 0;
    FILE *stream = NULL;
    DWORD size = GetEnvironmentVariableW(L"APPDATA", path, MAX_PATH);
    if (!size || size + 64 >= MAX_PATH) return;
    swprintf_s(path + size, MAX_PATH - size, L"\\Arrowhead\\Helldivers2\\wjl-render-contract-%lu.txt", (unsigned long)pid);
    DeleteFileW(path);
    if (!verified) return;
    for (const wchar_t *at = id; *at && length < 64; ++at) text[length++] = (char)*at;
    text[length++] = '|';
    for (const wchar_t *at = token; *at && length < sizeof(text) - 1; ++at) text[length++] = (char)*at;
    if (_wfopen_s(&stream, path, L"wb") || !stream) return;
    fwrite(text, 1, length, stream);
    fclose(stream);
}
/* --launch: start the service as a detached copy of this executable with the
 * same arguments, then wait for its readiness event or its exit. */
static int wjl_launch(LPWSTR *arguments, int count, const wchar_t *token) {
    wchar_t module[32768], name[160], *line;
    size_t size;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    HANDLE ready, waits[2];
    DWORD length = GetModuleFileNameW(NULL, module, 32768);
    int result = 1;
    if (!length || length >= 32768) return 1;
    size = wcslen(module) + 3;
    for (int index = 1; index < count; ++index) {
        if (!wcscmp(arguments[index], L"--launch")) continue;
        if (wcspbrk(arguments[index], L" \t\"")) return 1;
        size += wcslen(arguments[index]) + 1;
    }
    line = calloc(size + 1, sizeof(wchar_t));
    if (!line) return 1;
    swprintf_s(line, size + 1, L"\"%s\"", module);
    for (int index = 1; index < count; ++index) {
        if (!wcscmp(arguments[index], L"--launch")) continue;
        wcscat_s(line, size + 1, L" "); wcscat_s(line, size + 1, arguments[index]);
    }
    swprintf_s(name, 160, L"Local\\WJL_Steam_Ready_%s", token);
    ready = CreateEventW(NULL, TRUE, FALSE, name);
    ZeroMemory(&startup, sizeof(startup)); startup.cb = sizeof(startup);
    ZeroMemory(&process, sizeof(process));
    if (ready && CreateProcessW(module, line, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &process)) {
        waits[0] = ready; waits[1] = process.hProcess;
        result = WaitForMultipleObjects(2, waits, FALSE, 15000) == WAIT_OBJECT_0 ? 0 : 1;
        CloseHandle(process.hThread); CloseHandle(process.hProcess);
    }
    if (ready) CloseHandle(ready);
    free(line);
    return result;
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR command,int show) {
    int count, result=1;
    LPWSTR *arguments=CommandLineToArgvW(GetCommandLineW(),&count);
    const wchar_t *root=NULL,*token=NULL,*game_pid_text=NULL,*contract_id=NULL,*contract_resource=NULL,*contract_type=NULL;
    const wchar_t *exe_sha=NULL,*game_sha=NULL;
    WJLContractCheck checks[WJL_CONTRACT_CHECKS];
    unsigned int check_count=0;
    unsigned long long resource_value=0,type_value=0;
    DWORD game_pid=0;
    int launch=0;
    wchar_t incoming_name[256],outgoing_name[256],log_path[MAX_PATH],dll[32768];
    char hash[65];
    HANDLE incoming=INVALID_HANDLE_VALUE,outgoing=INVALID_HANDLE_VALUE;
    HANDLE single_instance=NULL;
    HANDLE ready_event=NULL;
    wchar_t ready_name[160];
    wchar_t mutex_name[96];
    DWORD peer=0;
    (void)instance;(void)previous;(void)command;(void)show;
    if (!arguments) return 1;
    for (int index=1;index<count;) {
        if (!wcscmp(arguments[index],L"--launch")) { launch=1;++index;continue; }
        if (index+1>=count) goto done;
        if (!wcscmp(arguments[index],L"--game")) root=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--game-pid")) game_pid_text=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--pipe")) token=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--exe-sha")) exe_sha=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--game-sha")) game_sha=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract")) contract_id=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract-resource")) contract_resource=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract-type")) contract_type=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--check")) {
            if (check_count>=WJL_CONTRACT_CHECKS || !wjl_contract_check(arguments[index+1],&checks[check_count])) goto done;
            ++check_count;
        } else goto done;
        index+=2;
    }
    if (game_pid_text) {
        if (root || !wjl_game_root(game_pid_text,&game_pid,wjl_resolved_root)) goto done;
        root=wjl_resolved_root;
    }
    if (contract_id && (!game_pid || !wjl_lower_hex(contract_id,64) || !wjl_hex64(contract_resource,&resource_value) ||
        !wjl_hex64(contract_type,&type_value) || !check_count)) goto done;
    /* The game build the mod was made for, as two SHA-256s; a missing one refuses. */
    if (!wjl_lower_hex(exe_sha,64) || !wjl_lower_hex(game_sha,64)) goto done;
    for (int index=0;index<64;++index) { EXE_SHA[index]=(char)exe_sha[index];GAME_SHA[index]=(char)game_sha[index]; }
    if (!root || !token || wcslen(root)>32000 || wcslen(token)>96 || wcslen(token)<16) goto done;
    for (size_t index=0;index<wcslen(token);++index) if (!((token[index]>=L'a'&&token[index]<=L'z')||(token[index]>=L'0'&&token[index]<=L'9')||token[index]==L'_')) goto done;
    if (launch) { result=game_pid?wjl_launch(arguments,count,token):1;goto done; }
    initialize();  /* Establish only the transport's ordinary output paths. */
    inline_events=1;
    if (!home[0] || !response_file[0]) goto done;
    swprintf_s(mutex_name,96,L"Local\\WJL_Steam_FS_%016llx",
        (unsigned long long)resource_hash((const unsigned char *)home,wcslen(home)*sizeof(wchar_t)));
    single_instance=CreateMutexW(NULL,FALSE,mutex_name);
    if (!single_instance || GetLastError()==ERROR_ALREADY_EXISTS) goto done;
    swprintf_s(log_path,MAX_PATH,L"%s\\service.log",home);
    service_log=_wfsopen(log_path,L"wb",_SH_DENYNO);
    wcscpy_s(game_root,32768,root);
    swprintf_s(executable,32768,L"%s\\bin\\helldivers2.exe",root);
    swprintf_s(dll,32768,L"%s\\data\\game\\game.dll",root);
    supported=hash_file(executable,hash)&&!strcmp(hash,EXE_SHA)&&hash_file(dll,hash)&&!strcmp(hash,GAME_SHA);
    if (!supported) { note("Refused: installed game hashes do not match the build War Journalist names");goto done; }
    note("Stock game hashes verified; awaiting local Lua filesystem client");
    if (contract_id) {
        int verified=wjl_verify_contract(root,checks,check_count,resource_value,type_value);
        wjl_contract_proof(game_pid,contract_id,token,verified);
        note(verified?"Stock renderer contract verified without GPU readback":"Scene backend unavailable: stock renderer contract not verified");
    }
    {
        /* WJ: the engine writes its DDS screenshot into this folder before asking for
         * the PNG, so it must exist before the first job (which would create it). */
        wchar_t shots[MAX_PATH];DWORD shots_length=GetEnvironmentVariableW(L"LOCALAPPDATA",shots,MAX_PATH);
        if (shots_length&&shots_length<MAX_PATH-40&&!wcscat_s(shots,MAX_PATH,L"\\WJL\\Helldivers2\\Screenshots")) CreateDirectoryW(shots,NULL);
    }
    swprintf_s(incoming_name,256,L"\\\\.\\pipe\\%s_request",token);
    swprintf_s(outgoing_name,256,L"\\\\.\\pipe\\%s_response",token);
    io_event=CreateEventW(NULL,TRUE,FALSE,NULL);if (!io_event) goto done;
    incoming=CreateNamedPipeW(incoming_name,PIPE_ACCESS_INBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE|FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,65536,65536,0,NULL);
    outgoing=CreateNamedPipeW(outgoing_name,PIPE_ACCESS_OUTBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE|FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,65536,65536,0,NULL);
    if (incoming==INVALID_HANDLE_VALUE || outgoing==INVALID_HANDLE_VALUE) { note("Cannot create exclusive local pipes");goto done; }
    swprintf_s(ready_name,160,L"Local\\WJL_Steam_Ready_%s",token);
    ready_event=CreateEventW(NULL,TRUE,FALSE,ready_name);
    if (!ready_event || !SetEvent(ready_event)) { note("Cannot signal filesystem service readiness");goto done; }
    if (!connect_pipe(incoming)||!connect_pipe(outgoing)) { note("No complete client connection within startup timeout");goto done; }
    if (!GetNamedPipeClientProcessId(incoming,&session_pid)||!GetNamedPipeClientProcessId(outgoing,&peer)||peer!=session_pid) {
        note("Refused: request and response clients differ");goto done;
    }
    note("Local Lua client connected; filesystem and visible-menu pointer service ready");
    for (;;) {
        uint32_t size;
        unsigned char *bytes;
        int ok;
        if (!transfer(incoming,&size,4,0)) break;
        if (size<12||size>MAX_REQUEST) { note("Refused oversized or truncated request");break; }
        bytes=malloc(size);if (!bytes) break;
        ok=transfer(incoming,bytes,size,0) ? dispatch(bytes,size,outgoing) : 0;free(bytes);
        if (!ok||(ok==1&&!send_file(outgoing))) break;
    }
    note("Client disconnected; service stopped");result=0;
done:
    if (ready_event) ResetEvent(ready_event);
    if (incoming!=INVALID_HANDLE_VALUE) { CloseHandle(incoming);incoming=INVALID_HANDLE_VALUE; }
    if (outgoing!=INVALID_HANDLE_VALUE) { CloseHandle(outgoing);outgoing=INVALID_HANDLE_VALUE; }
    wjl_keyboard_cancel_all();
    wjl_keyboard_shutdown();
    wjl_screenshot_jobs_shutdown();
    wjl_pointer_release();
    free(listing_bytes);
    if (ready_event) { ResetEvent(ready_event);CloseHandle(ready_event); }
    wjl_steam_close(NULL);
    if (incoming!=INVALID_HANDLE_VALUE) CloseHandle(incoming);
    if (outgoing!=INVALID_HANDLE_VALUE) CloseHandle(outgoing);
    if (io_event) CloseHandle(io_event);
    if (single_instance) CloseHandle(single_instance);
    if (service_log) fclose(service_log);
    LocalFree(arguments);return result;
}

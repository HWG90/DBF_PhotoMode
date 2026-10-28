"""Build the bundled WJL input helper from a read-only LLL checkout's native sources.

On Windows this uses LLL's tools/build_steam_service.py (Visual Studio 2022). Elsewhere,
--wine-msvc runs the same MSVC compiler and Windows SDK under wine, from a copy laid out as
vc/{bin/x64,include,lib/x64} and sdk/include/{ucrt,um,shared,winrt,cppwinrt},
sdk/lib/{um,ucrt}/x64. With identical sources both produce identical code; only the link
timestamp and path-derived anonymous-namespace names differ."""
from pathlib import Path
import argparse,difflib,hashlib,json,os,re,shutil,subprocess

root=Path.cwd()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lll',type=Path,default=root/'../LLL',help='LLL checkout holding native/ and tools/ (read only)')
parser.add_argument('--wine-msvc',type=Path,help='MSVC + Windows SDK copy to run under wine instead of Visual Studio')
args=parser.parse_args()
source=args.lll.resolve();review=root/'dist/review/windows-wjl-helper';native=review/'native'
if native.exists():shutil.rmtree(native)
native.mkdir(parents=True)
def patch_once(text,old,new,what):
 assert text.count(old)==1,'Upstream source changed: '+what
 return text.replace(old,new)
for p in (source/'native').iterdir():
 if p.suffix in ('.c','.cpp','.h'):shutil.copy2(p,native/p.name)
p=native/'steam_keyboard.c';s=p.read_text();s=s.replace('    if (key >= 160 && key <= 165) return 0;', '''    /* Preserve the desktop's Ctrl+Shift+Space shortcut. It is already owned
     * on this Windows host; a single collision otherwise aborts all gameplay keys. */
    if (key == VK_SPACE && modifiers == (MOD_CONTROL | MOD_SHIFT)) return 0;
    if (key >= 160 && key <= 165) return 0;''',1)
# 1.3.0 failed the whole lease when any one tuple was already registered elsewhere. Players
# run GPU overlays, recorders and chat apps that own Alt/Ctrl+Shift shortcuts, so Photo Mode
# flashed and closed for them. Windows delivers such a shortcut to its owner, never to the
# game, so leave it there and isolate everything else. Every other failure stays fatal.
s=patch_once(s,'''    unsigned int registration_count;
''','''    unsigned int registration_count;
    unsigned int shared_count; /* tuples another application already owns */
    uint32_t shared[8];        /* the first eight: key | modifiers << 8 */
''','lease fields')
s=patch_once(s,'''                DWORD error = GetLastError();
                lll_keyboard_stop_request(LLL_KEYBOARD_FAILED, error ? error : ERROR_HOTKEY_ALREADY_REGISTERED);
''','''                DWORD error = GetLastError();
                /* Another application owns this exact shortcut (GPU overlays,
                 * recorders, chat). Windows delivers it to that owner, never to
                 * the game, so it is isolated already. Keep the other keys. */
                if (error == ERROR_HOTKEY_ALREADY_REGISTERED) {
                    if (lease->shared_count < 8) lease->shared[lease->shared_count] = key | modifiers << 8;
                    ++lease->shared_count;
                    continue;
                }
                lll_keyboard_stop_request(LLL_KEYBOARD_FAILED, error ? error : ERROR_HOTKEY_ALREADY_REGISTERED);
''','registration failure')
p.write_text(s)
p=native/'test_steam_keyboard.c';s=p.read_text().replace('880','879');s=s.replace('    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_ALT));','    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_CONTROL|MOD_SHIFT));\n    CHECK(lll_keyboard_tuple(VK_SPACE,0));\n    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_ALT));')
# The rollback fixtures keep testing a fatal error; collisions get their own fixture.
s=patch_once(s,'static volatile LONG test_register_thread;\n','static volatile LONG test_register_thread,test_successes,test_collide[2049];\n','fixture state')
s=patch_once(s,'''    LONG call=InterlockedIncrement(&test_registers);
''','''    LONG call=InterlockedIncrement(&test_registers),stored;
''','fake register locals')
s=patch_once(s,'''        SetLastError(ERROR_HOTKEY_ALREADY_REGISTERED);return FALSE;
    }
    if (call<1||call>2048||id<1||id>2048) { InterlockedIncrement(&test_fake_errors);return FALSE; }
    test_tuples[call-1].id=id;test_tuples[call-1].modifiers=modifiers;test_tuples[call-1].key=key;
''','''        SetLastError(ERROR_NOT_ENOUGH_MEMORY);return FALSE;
    }
    if (call<1||call>2048||id<1||id>2048) { InterlockedIncrement(&test_fake_errors);return FALSE; }
    if (InterlockedCompareExchange(&test_collide[id],0,0)) { SetLastError(ERROR_HOTKEY_ALREADY_REGISTERED);return FALSE; }
    stored=InterlockedIncrement(&test_successes);
    test_tuples[stored-1].id=id;test_tuples[stored-1].modifiers=modifiers;test_tuples[stored-1].key=key;
''','fake register')
s=patch_once(s,'''    test_registers=test_unregisters=test_reads=test_focus_reads=test_identifies=0;
''','''    test_registers=test_unregisters=test_reads=test_focus_reads=test_identifies=test_successes=0;
    ZeroMemory((void *)test_collide,sizeof(test_collide));
''','fixture reset')
s=patch_once(s,'''static void test_identity_and_ownership(void) {''','''static void test_shared_shortcuts(void) {
    uint32_t mask[8]={0};
    const uint32_t alt_r='R'|(uint32_t)MOD_ALT<<8,control_shift_s='S'|(uint32_t)(MOD_CONTROL|MOD_SHIFT)<<8;
    key_bit(mask,'R');key_bit(mask,'S');
    /* Alt+R and Ctrl+Shift+S belong to another application (GPU overlay
     * defaults). They stay with it; the other 14 tuples are reserved. */
    direct_begin(mask);test_collide[1+'R'*8+4]=1;test_collide[1+'S'*8+3]=1;
    CHECK(lll_keyboard_register_worker(&lll_keyboard_lease));
    CHECK(current_state()==LLL_KEYBOARD_ACTIVE);
    CHECK(test_registers==16&&lll_keyboard_lease.registration_count==14&&test_successes==14);
    CHECK(lll_keyboard_lease.shared_count==2&&lll_keyboard_lease.shared[0]==alt_r&&lll_keyboard_lease.shared[1]==control_shift_s);
    direct_end(14);
    /* Every tuple of a key may be owned elsewhere; that key is simply not ours. */
    direct_begin(mask);
    for (unsigned int variant=0;variant<8;++variant) test_collide[1+'R'*8+variant]=1;
    CHECK(lll_keyboard_register_worker(&lll_keyboard_lease));
    CHECK(current_state()==LLL_KEYBOARD_ACTIVE&&lll_keyboard_lease.registration_count==8&&lll_keyboard_lease.shared_count==8);
    direct_end(8);
    /* More than eight: all are counted, the first eight are recorded. */
    direct_begin(lll_keyboard_allowed);
    for (unsigned int key='A';key<='L';++key) test_collide[1+key*8]=1;
    CHECK(lll_keyboard_register_worker(&lll_keyboard_lease));
    CHECK(current_state()==LLL_KEYBOARD_ACTIVE&&lll_keyboard_lease.shared_count==12&&lll_keyboard_lease.registration_count==867);
    CHECK(lll_keyboard_lease.shared[0]=='A'&&lll_keyboard_lease.shared[7]=='H');
    direct_end(867);
    /* Through the real worker thread: ACTIVE, then a clean release. */
    reset_fixture();test_collide[1+'R'*8+4]=1;
    { LLLSteamKeyboardReply reply;uint32_t released=0;
      CHECK(lll_keyboard_acquire(test_pid,test_expected,1,mask,&reply)==0);
      wait_event(test_hook_seen);wait_event(lll_keyboard_lease.ready);CHECK(current_state()==LLL_KEYBOARD_ACTIVE);
      CHECK(lll_keyboard_release(test_pid,test_expected,1,reply.generation,&released)==0);
      CHECK(released==reply.generation&&!lll_keyboard_lease.thread);
      CHECK(test_registers==16&&test_successes==15&&test_unregisters==15&&test_hooks==test_unhooks);
      CHECK(!test_fake_errors); }
}
static void test_identity_and_ownership(void) {''','collision fixture')
s=patch_once(s,'test_registration_rollback();test_identity_and_ownership();','test_registration_rollback();test_shared_shortcuts();test_identity_and_ownership();','fixture order')
p.write_text(s)
p=native/'steam_files.c';s=p.read_text()
s=re.sub(r'(static const char EXE_SHA\[\] = ")[^"]+',r'\g<1>0acc07debe04714ae04281e1a66bd2eb9d3d85232953e32a93c8a3dd0874eabe',s)
s=re.sub(r'(static const char GAME_SHA\[\] = ")[^"]+',r'\g<1>6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f',s);p.write_text(s)
p=native/'steam_service.c';s=p.read_text();s=s.replace('        if (reply[1]) goto done;\n        if (keyboard.state == LLL_KEYBOARD_ACTIVE)', '''        if (reply[1]) goto done;
        {
            static uint32_t last_generation, last_state;
            if (last_generation != keyboard.generation || last_state != keyboard.state) {
                char message[192]; DWORD keyboard_error;
                AcquireSRWLockShared(&lll_keyboard_data);
                keyboard_error = lll_keyboard_lease.error;
                ReleaseSRWLockShared(&lll_keyboard_data);
                sprintf_s(message, sizeof(message), "Keyboard generation=%u state=%u error=%lu", keyboard.generation, keyboard.state, (unsigned long)keyboard_error);
                note(message); last_generation=keyboard.generation; last_state=keyboard.state;
            }
        }
        if (keyboard.state == LLL_KEYBOARD_ACTIVE)''')
# Name the shortcuts left to their owners in service.log, for player reports.
s=patch_once(s,'''                char message[192]; DWORD keyboard_error;
                AcquireSRWLockShared(&lll_keyboard_data);
                keyboard_error = lll_keyboard_lease.error;
                ReleaseSRWLockShared(&lll_keyboard_data);
                sprintf_s(message, sizeof(message), "Keyboard generation=%u state=%u error=%lu", keyboard.generation, keyboard.state, (unsigned long)keyboard_error);
''','''                char message[384]; DWORD keyboard_error; uint32_t shared_count, shared[8]; int written;
                AcquireSRWLockShared(&lll_keyboard_data);
                keyboard_error = lll_keyboard_lease.error;
                shared_count = lll_keyboard_lease.shared_count;
                memcpy(shared, lll_keyboard_lease.shared, sizeof(shared));
                ReleaseSRWLockShared(&lll_keyboard_data);
                written = sprintf_s(message, sizeof(message), "Keyboard generation=%u state=%u error=%lu shared=%u", keyboard.generation, keyboard.state, (unsigned long)keyboard_error, shared_count);
                for (uint32_t i = 0; i < shared_count && i < 8 && written > 0; ++i) {
                    uint32_t modifiers = shared[i] >> 8;
                    int added = _snprintf_s(message + written, sizeof(message) - (size_t)written, _TRUNCATE, "%s%s%s%sVK 0x%02X", i ? ", " : " owned elsewhere: ",
                        (modifiers & MOD_CONTROL) ? "Ctrl+" : "", (modifiers & MOD_SHIFT) ? "Shift+" : "", (modifiers & MOD_ALT) ? "Alt+" : "", shared[i] & 0xffu);
                    written = added > 0 ? written + added : -1;
                }
''','service shared log')
# 1.3.0 started the helper from a PowerShell script, which Proton does not have and some
# Windows installs block. The game now starts it with cmd.exe: --launch starts the service
# as a detached copy and waits for its readiness event (the script's job), --game-pid
# resolves the installation with query-only access, and the stock renderer contract the
# script checked is verified here before the pipes are offered.
s=patch_once(s,'int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR command,int show) {\n',r'''#define LLL_CONTRACT_CHECKS 32u
#define LLL_CONTRACT_BUDGET (16u * 1024u * 1024u)
typedef struct LLLContractCheck { wchar_t file[64]; unsigned long long offset; DWORD size; char sha[65]; } LLLContractCheck;
static wchar_t lll_resolved_root[32768];
static int lll_decimal(const wchar_t *text, size_t length, unsigned long long limit, unsigned long long *value) {
    unsigned long long total = 0;
    if (!length || length > 20) return 0;
    for (size_t index = 0; index < length; ++index) {
        if (text[index] < L'0' || text[index] > L'9') return 0;
        total = total * 10u + (unsigned long long)(text[index] - L'0');
        if (total > limit) return 0;
    }
    *value = total; return 1;
}
static int lll_hex_digit(wchar_t c) { return (c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || (c >= L'A' && c <= L'F'); }
static int lll_hex64(const wchar_t *text, unsigned long long *value) {
    unsigned long long total = 0;
    if (!text || wcslen(text) != 16) return 0;
    for (size_t index = 0; index < 16; ++index) {
        wchar_t c = text[index];
        if (!lll_hex_digit(c)) return 0;
        total = total << 4 | (unsigned long long)(c <= L'9' ? c - L'0' : (c | 0x20) - L'a' + 10);
    }
    *value = total; return 1;
}
static int lll_lower_hex(const wchar_t *text, size_t length) {
    if (!text || wcslen(text) != length) return 0;
    for (size_t index = 0; index < length; ++index) if (!((text[index] >= L'0' && text[index] <= L'9') || (text[index] >= L'a' && text[index] <= L'f'))) return 0;
    return 1;
}
/* The game's own image, read with query-only access; the installation is the
 * folder above its bin folder. */
static int lll_game_root(const wchar_t *text, DWORD *pid, wchar_t root[32768]) {
    unsigned long long value;
    DWORD size = 32768;
    HANDLE process;
    wchar_t *end;
    int ok = 0;
    if (!text || !lll_decimal(text, wcslen(text), 0xffffffffu, &value) || !value) return 0;
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
static int lll_contract_check(const wchar_t *text, LLLContractCheck *check) {
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
    if (!lll_decimal(colon[0] + 1, (size_t)(colon[1] - colon[0] - 1), 9007199254740991ull, &check->offset)) return 0;
    if (!lll_decimal(colon[1] + 1, (size_t)(colon[2] - colon[1] - 1), LLL_CONTRACT_BUDGET, &value) || !value) return 0;
    check->size = (DWORD)value;
    if (!lll_lower_hex(colon[2] + 1, 64)) return 0;
    for (size_t index = 0; index < 64; ++index) check->sha[index] = (char)colon[2][1 + index];
    check->sha[64] = 0;
    return 1;
}
static int lll_hash_range(const wchar_t *path, unsigned long long offset, DWORD size, char output[65]) {
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
static int lll_patch_name(const wchar_t *name) {
    size_t length = wcslen(name);
    if (length < 24 || wcsncmp(name + 16, L".patch_", 7)) return 0;
    for (size_t index = 0; index < 16; ++index) if (!lll_hex_digit(name[index])) return 0;
    for (size_t index = 23; index < length; ++index) if (name[index] < L'0' || name[index] > L'9') return 0;
    return 1;
}
/* No installed patch may replace the stock renderer configuration. The limits bound the
 * work for very large mod setups (1.3.1's 128 patches / 8,192 entries refused ordinary
 * ones and hid every scene effect); entry tables are read in 4,096-row blocks. */
#define LLL_RENDER_PATCHES 4096u
#define LLL_RENDER_TYPES 1024u
#define LLL_RENDER_ENTRIES 262144u
#define LLL_RENDER_TOTAL 4194304u
static unsigned char lll_render_rows[4096 * 80];
static int lll_renderer_untouched(const wchar_t *data, unsigned long long resource, unsigned long long type) {
    WIN32_FIND_DATAW found;
    wchar_t pattern[32768], path[32768];
    HANDLE search;
    unsigned int patches = 0, total = 0;
    int ok = 1;
    swprintf_s(pattern, 32768, L"%s\\*.patch_*", data);
    search = FindFirstFileW(pattern, &found);
    if (search == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
    for (;;) {
        if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && lll_patch_name(found.cFileName)) {
            HANDLE file;
            unsigned char head[72];
            DWORD count;
            uint32_t magic = 0, types = 0, entries = 0;
            LARGE_INTEGER length, at;
            length.QuadPart = 0;
            if (++patches > LLL_RENDER_PATCHES) { ok = 0; break; }
            swprintf_s(path, 32768, L"%s\\%s", data, found.cFileName);
            file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
            if (file == INVALID_HANDLE_VALUE) { ok = 0; break; }
            ok = ReadFile(file, head, 72, &count, NULL) && count == 72 && GetFileSizeEx(file, &length);
            if (ok) {
                memcpy(&magic, head, 4); memcpy(&types, head + 4, 4); memcpy(&entries, head + 8, 4);
                ok = magic == 0xf0000011u && types <= LLL_RENDER_TYPES && entries <= LLL_RENDER_ENTRIES;
            }
            if (ok) { total += entries; ok = total <= LLL_RENDER_TOTAL && 72ull + 32ull * types + 80ull * entries <= (unsigned long long)length.QuadPart; }
            if (ok) { at.QuadPart = 72 + 32 * (LONGLONG)types; ok = SetFilePointerEx(file, at, NULL, FILE_BEGIN); }
            for (uint32_t done = 0; ok && done < entries;) {
                const uint32_t block = entries - done < 4096u ? entries - done : 4096u;
                ok = ReadFile(file, lll_render_rows, block * 80u, &count, NULL) && count == block * 80u;
                for (uint32_t index = 0; ok && index < block; ++index) {
                    unsigned long long name, kind;
                    memcpy(&name, lll_render_rows + index * 80u, 8); memcpy(&kind, lll_render_rows + index * 80u + 8, 8);
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
static int lll_verify_contract(const wchar_t *root, const LLLContractCheck *checks, unsigned int count,
                               unsigned long long resource, unsigned long long type) {
    wchar_t data[32768], path[32768];
    char hash[65];
    unsigned long long total = 0;
    swprintf_s(data, 32768, L"%s\\data", root);
    for (unsigned int index = 0; index < count; ++index) {
        total += checks[index].size;
        if (total > LLL_CONTRACT_BUDGET) return 0;
        swprintf_s(path, 32768, L"%s\\%s", data, checks[index].file);
        if (!lll_hash_range(path, checks[index].offset, checks[index].size, hash) || strcmp(hash, checks[index].sha)) return 0;
    }
    return lll_renderer_untouched(data, resource, type);
}
/* The proof Lua reads: <contract id>|<pipe token>, removed first so a stale
 * proof never survives a failed check. */
static void lll_contract_proof(DWORD pid, const wchar_t *id, const wchar_t *token, int verified) {
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
static int lll_launch(LPWSTR *arguments, int count, const wchar_t *token) {
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
    swprintf_s(name, 160, L"Local\\LLL_Steam_Ready_%s", token);
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
''','service helpers')
s=patch_once(s,'''    const wchar_t *root=NULL,*token=NULL;
''','''    const wchar_t *root=NULL,*token=NULL,*game_pid_text=NULL,*contract_id=NULL,*contract_resource=NULL,*contract_type=NULL;
    LLLContractCheck checks[LLL_CONTRACT_CHECKS];
    unsigned int check_count=0;
    unsigned long long resource_value=0,type_value=0;
    DWORD game_pid=0;
    int launch=0;
''','service locals')
s=patch_once(s,'''    for (int index=1;index+1<count;index+=2) {
        if (!wcscmp(arguments[index],L"--game")) root=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--pipe")) token=arguments[index+1];
        else goto done;
    }
    if (!root || !token || wcslen(root)>32000 || wcslen(token)>96 || wcslen(token)<16) goto done;
    for (size_t index=0;index<wcslen(token);++index) if (!((token[index]>=L'a'&&token[index]<=L'z')||(token[index]>=L'0'&&token[index]<=L'9')||token[index]==L'_')) goto done;
''','''    for (int index=1;index<count;) {
        if (!wcscmp(arguments[index],L"--launch")) { launch=1;++index;continue; }
        if (index+1>=count) goto done;
        if (!wcscmp(arguments[index],L"--game")) root=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--game-pid")) game_pid_text=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--pipe")) token=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract")) contract_id=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract-resource")) contract_resource=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--contract-type")) contract_type=arguments[index+1];
        else if (!wcscmp(arguments[index],L"--check")) {
            if (check_count>=LLL_CONTRACT_CHECKS || !lll_contract_check(arguments[index+1],&checks[check_count])) goto done;
            ++check_count;
        } else goto done;
        index+=2;
    }
    if (game_pid_text) {
        if (root || !lll_game_root(game_pid_text,&game_pid,lll_resolved_root)) goto done;
        root=lll_resolved_root;
    }
    if (contract_id && (!game_pid || !lll_lower_hex(contract_id,64) || !lll_hex64(contract_resource,&resource_value) ||
        !lll_hex64(contract_type,&type_value) || !check_count)) goto done;
    if (!root || !token || wcslen(root)>32000 || wcslen(token)>96 || wcslen(token)<16) goto done;
    for (size_t index=0;index<wcslen(token);++index) if (!((token[index]>=L'a'&&token[index]<=L'z')||(token[index]>=L'0'&&token[index]<=L'9')||token[index]==L'_')) goto done;
    if (launch) { result=game_pid?lll_launch(arguments,count,token):1;goto done; }
''','service arguments')
s=patch_once(s,'''    note("Stock game hashes verified; awaiting local Lua filesystem client");
''','''    note("Stock game hashes verified; awaiting local Lua filesystem client");
    if (contract_id) {
        int verified=lll_verify_contract(root,checks,check_count,resource_value,type_value);
        lll_contract_proof(game_pid,contract_id,token,verified);
        note(verified?"Stock renderer contract verified without GPU readback":"Scene backend unavailable: stock renderer contract not verified");
    }
    {
        /* WJ: the engine writes its DDS screenshot into this folder before asking for
         * the PNG, so it must exist before the first job (which would create it). */
        wchar_t shots[MAX_PATH];DWORD shots_length=GetEnvironmentVariableW(L"LOCALAPPDATA",shots,MAX_PATH);
        if (shots_length&&shots_length<MAX_PATH-40&&!wcscat_s(shots,MAX_PATH,L"\\\\LLL\\\\Helldivers2\\\\Screenshots")) CreateDirectoryW(shots,NULL);
    }
''','service contract')
p.write_text(s)
# PNG screenshots: Windows Graphics Capture of the game window failed on a tester's PC,
# and the engine's own DDS works everywhere. A PNG request with a same-named DDS beside it
# converts that DDS (DBF_PhotoMode's 0.9.x photo_capture.cpp, SDR and HDR10), outside the
# game; any other PNG request keeps LLL's window capture.
p=native/'steam_screenshot.cpp';s=p.read_text()
s=patch_once(s,'#include <algorithm>\n','#include <algorithm>\n#include <array>\n#include <cmath>\n','conversion includes')
s=patch_once(s,'constexpr ULONGLONG kDeadlineMs = 5000;\n','constexpr ULONGLONG kDeadlineMs = 5000;\nconstexpr ULONGLONG kConvertMs = 60000;\n','conversion deadline')
s=patch_once(s,'''    const ULONGLONG begun = GetTickCount64();
    void check() const {''','''    const ULONGLONG begun = GetTickCount64();
    const ULONGLONG deadline = kDeadlineMs;
    void check() const {''','operation deadline')
s=patch_once(s,'        require(GetTickCount64() - begun < kDeadlineMs, ERROR_TIMEOUT);\n','        require(GetTickCount64() - begun < deadline, ERROR_TIMEOUT);\n','check deadline')
s=patch_once(s,'''        require(elapsed < kDeadlineMs, ERROR_TIMEOUT);
        return static_cast<DWORD>(kDeadlineMs - elapsed);''','''        require(elapsed < deadline, ERROR_TIMEOUT);
        return static_cast<DWORD>(deadline - elapsed);''','remaining deadline')
s=patch_once(s,'} // namespace\n',r'''// WJ: the engine's DDS screenshot, converted to the PNG beside it.
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
void convert_dds(const LLLScreenshotRequest& request, LLLScreenshotResult& result, const Operation& operation) {
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
''','DDS conversion')
s=patch_once(s,'''        save_window(*request, *result, operation);''','''        if (dds_present(request->output_path)) {
            const Operation conversion{*request, GetTickCount64(), kConvertMs};
            convert_dds(*request, *result, conversion);
        } else save_window(*request, *result, operation);''','conversion branch')
p.write_text(s)
# The engine's clip flag does not hold while Photo Mode has taken the game's mouse focus
# (seen under Proton; the LLL build clipped from an in-game DLL, which Windows refuses).
# The helper confines the cursor itself, from outside the game, as Windows allows.
p=native/'steam_pointer.c';s=p.read_text()
s=patch_once(s,'int lll_pointer_snapshot_extended(LLLSteamPointerSample *out) {\n','''/* WJ: keep the cursor inside the game's client area while Photo Mode owns the
 * pointer. Windows and games drop a clip on focus and mode changes, so every
 * sample re-applies it. A clip that already keeps the cursor inside the window
 * (the game's own) is left alone, and release removes only a clip set here. */
static RECT lll_pointer_clip;
static int lll_pointer_clipped;
static void lll_pointer_unconfine(void) {
    RECT current;
    if (!lll_pointer_clipped) return;
    lll_pointer_clipped = 0;
    if (GetClipCursor(&current) && EqualRect(&current, &lll_pointer_clip)) ClipCursor(NULL);
}
static void lll_pointer_confine(HWND window, const RECT *client) {
    POINT origin = {0, 0};
    RECT wanted, frame, current;
    if (!ClientToScreen(window, &origin) || !GetWindowRect(window, &frame) || !GetClipCursor(&current)) return;
    if (current.left >= frame.left && current.top >= frame.top && current.right <= frame.right && current.bottom <= frame.bottom) return;
    SetRect(&wanted, origin.x, origin.y, origin.x + (client->right - client->left), origin.y + (client->bottom - client->top));
    if (ClipCursor(&wanted)) { lll_pointer_clip = wanted; lll_pointer_clipped = 1; }
}
int lll_pointer_snapshot_extended(LLLSteamPointerSample *out) {
''','pointer confinement helpers')
s=patch_once(s,'''    HWND foreground, after;
    POINT point;
    RECT bounds;
''','''    HWND foreground = NULL, after;
    POINT point;
    RECT bounds = {0, 0, 0, 0};
''','pointer sample locals')
s=patch_once(s,'''    out->dy = motion.dy;
done:
    ReleaseSRWLockShared(&lll_pointer_lifecycle);
''','''    out->dy = motion.dy;
done:
    if (out->valid) lll_pointer_confine(foreground, &bounds); else lll_pointer_unconfine();
    ReleaseSRWLockShared(&lll_pointer_lifecycle);
''','pointer sample confinement')
s=patch_once(s,'''int lll_pointer_release(void) {
    int ok;
    AcquireSRWLockExclusive(&lll_pointer_lifecycle);
''','''int lll_pointer_release(void) {
    int ok;
    AcquireSRWLockExclusive(&lll_pointer_lifecycle);
    lll_pointer_unconfine();
''','pointer release confinement')
p.write_text(s)
# WJL owns a separate namespace and settings/log directory. The upstream
# checkout is read-only; all compilation inputs here are private copies.
for owned in native.iterdir():
 if owned.suffix in ('.c','.cpp','.h'):
  body=owned.read_text(encoding='utf-8').replace('LLL','WJL').replace('lll_','wjl_')
  owned.write_text(body,encoding='utf-8')
# Preserve the source delta as a reviewable patch; owning LLL checkout stays untouched.
patch=''
for name in ('steam_keyboard.c','test_steam_keyboard.c','steam_files.c','steam_service.c','steam_pointer.c','steam_screenshot.cpp'):
 a=(source/'native'/name).read_text().splitlines(keepends=True);b=(native/name).read_text().splitlines(keepends=True)
 patch+=''.join(difflib.unified_diff(a,b,fromfile='a/native/'+name,tofile='b/native/'+name))
(root/'tools/windows_input_shortcut.patch').write_text(patch)

def wine_build(output,toolchain):
 """LLL's build_steam_service.build(), with MSVC run under wine. The D3D capture
 runtime test needs a real desktop and is skipped; the other four fixtures run."""
 output.mkdir(parents=True,exist_ok=True);toolchain=toolchain.resolve()
 z=lambda path:'Z:'+str(Path(path).resolve()).replace('/','\\')
 env=dict(os.environ,WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
 env['INCLUDE']=';'.join(z(toolchain/d) for d in ('vc/include','sdk/include/ucrt','sdk/include/um','sdk/include/shared','sdk/include/winrt','sdk/include/cppwinrt'))
 env['LIB']=';'.join(z(toolchain/d) for d in ('vc/lib/x64','sdk/lib/um/x64','sdk/lib/ucrt/x64'))
 cl=lambda *a:subprocess.run(['wine',str(toolchain/'vc/bin/x64/cl.exe'),*a],check=True,cwd=output,env=env)
 run=lambda name,timeout:subprocess.run(['wine',str(output/name)],check=True,cwd=output,env=env,timeout=timeout)
 n,o=z(native),z(output)
 strict=['/nologo','/O2','/GS','/W4','/WX','/MT']
 cl(*strict[:1],'/std:c++17','/EHsc','/permissive-','/Zc:__cplusplus',*strict[1:],'/utf-8','/c',n+'\\steam_screenshot.cpp','/Fo'+o+'\\steam_screenshot.obj')
 cl(*strict,'/DUNICODE','/D_UNICODE',n+'\\steam_service.c','/Fo'+o+'\\steam_service.obj','/Fe'+o+'\\steam_service.exe',o+'\\steam_screenshot.obj',
    '/link','/SUBSYSTEM:WINDOWS','/DYNAMICBASE','/NXCOMPAT','/HIGHENTROPYVA','/DELAYLOAD:d3d11.dll','/DELAYLOAD:dxgi.dll','/DELAYLOAD:dwmapi.dll','delayimp.lib',
    'bcrypt.lib','kernel32.lib','shell32.lib','user32.lib','d3d11.lib','dxgi.lib','dwmapi.lib','windowscodecs.lib','windowsapp.lib','runtimeobject.lib','ole32.lib','uuid.lib')
 for test,extra,libs in (('test_steam_files',[],['bcrypt.lib','kernel32.lib']),('test_steam_pointer',[],['kernel32.lib','user32.lib']),
                         ('test_steam_keyboard',['/std:c11'],['kernel32.lib','user32.lib']),
                         ('test_steam_screenshot_jobs',[],['bcrypt.lib','kernel32.lib','shell32.lib','user32.lib'])):
  cl('/nologo',*extra,*strict[1:],n+'\\'+test+'.c','/Fo'+o+'\\'+test+'.obj','/Fe'+o+'\\'+test+'.exe','/link',*libs)
  run(test+'.exe',60)
 value=(output/'steam_service.exe').read_bytes()
 built=output/('wjl_steam_service_'+hashlib.sha256(value).hexdigest()[:16]+'.exe');built.write_bytes(value)
 return built

if args.wine_msvc:built=wine_build(review/'build',args.wine_msvc)
else:
 spec=__import__('importlib.util',fromlist=['spec_from_file_location']);sp=spec.spec_from_file_location('builder',source/'tools/build_steam_service.py');builder=spec.module_from_spec(sp);sp.loader.exec_module(builder);builder.ROOT=review
 built=builder.build(review/'build')
binary=built.with_name('wjl_steam_service_'+hashlib.sha256(built.read_bytes()).hexdigest()[:16]+'.exe')
binary.write_bytes(built.read_bytes())
(review/'HELPER.json').write_text(json.dumps({'binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'preserved_shortcut':'Ctrl+Shift+Space',
 'shared_shortcuts':'tuples another application already owns stay with it',
 'compiler':'MSVC under wine' if args.wine_msvc else 'Visual Studio 2022',
 'sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in native.iterdir()}},indent=2)+'\n')
print(binary)

# One helper file under one name; the game checks its bytes against sha256 before each start.
(root/'freecam/wjl_helper_payload.lua').write_text('return {name="wjl_steam_service.exe",sha256='+json.dumps(hashlib.sha256(binary.read_bytes()).hexdigest())+',hex='+json.dumps(binary.read_bytes().hex())+'}\n')

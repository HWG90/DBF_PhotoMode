/* Test-only stand-ins for tools/test_wjl_helper_launch.py. Never shipped.
 *   probe.exe sleep <pid-file>   a "game" process: writes its pid, then waits
 *   probe.exe client <token>     the Lua side's first exchange on the helper's pipes, once they exist
 *   probe.exe popen <file> <out> io.popen(command):close(): how long cmd.exe runs the launcher
 *                                (the game itself never closes it before the helper answers) */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int sleeper(const char *path) {
    FILE *file = fopen(path, "wb");
    if (!file) return 2;
    fprintf(file, "%lu", (unsigned long)GetCurrentProcessId());
    fclose(file);
    Sleep(180000);
    return 0;
}
static void text(const unsigned char *reply, uint32_t size, uint32_t *at, char *out, size_t capacity) {
    uint32_t length = 0;
    out[0] = 0;
    if (*at + 4 > size) return;
    memcpy(&length, reply + *at, 4); *at += 4;
    if (*at + length > size || length >= capacity) return;
    memcpy(out, reply + *at, length); out[length] = 0; *at += length;
}
static int client(const char *token) {
    char name[256], exe[4096], root[4096];
    unsigned char request[16] = {12}, reply[16384];
    uint32_t size = 0, status[3] = {0}, at = 12;
    DWORD count;
    HANDLE outgoing, incoming;
    /* The game polls for the pipes once a frame; poll every 50 ms for up to 20 s. */
    for (int attempt = 0; attempt < 400; ++attempt) {
        snprintf(name, sizeof(name), "\\\\.\\pipe\\%s_request", token);
        outgoing = CreateFileA(name, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (outgoing != INVALID_HANDLE_VALUE) break;
        Sleep(50);
    }
    snprintf(name, sizeof(name), "\\\\.\\pipe\\%s_response", token);
    incoming = CreateFileA(name, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (outgoing == INVALID_HANDLE_VALUE || incoming == INVALID_HANDLE_VALUE) { printf("{\"connected\":false,\"error\":%lu}\n", GetLastError()); return 3; }
    if (!WriteFile(outgoing, request, 16, &count, NULL) || count != 16) return 4;
    if (!ReadFile(incoming, &size, 4, &count, NULL) || count != 4 || size < 12 || size > sizeof(reply)) return 5;
    for (uint32_t got = 0; got < size; got += count) if (!ReadFile(incoming, reply + got, size - got, &count, NULL) || !count) return 6;
    memcpy(status, reply, 12);
    text(reply, size, &at, exe, sizeof(exe)); text(reply, size, &at, root, sizeof(root));
    for (char *c = exe; *c; ++c) if (*c == '\\') *c = '/';
    for (char *c = root; *c; ++c) if (*c == '\\') *c = '/';
    printf("{\"connected\":true,\"nonce\":%u,\"status\":%u,\"pid\":%u,\"client_pid\":%lu,\"exe\":\"%s\",\"root\":\"%s\"}\n",
           status[0], status[1], status[2], (unsigned long)GetCurrentProcessId(), exe, root);
    CloseHandle(outgoing); CloseHandle(incoming);
    return 0;
}
static int launcher(const char *path, const char *result) {
    char command[8192];
    size_t length;
    FILE *file = fopen(path, "rb"), *pipe;
    if (!file) return 2;
    length = fread(command, 1, sizeof(command) - 1, file); fclose(file); command[length] = 0;
    pipe = _popen(command, "r");
    if (!pipe) return 3;
    length = (size_t)_pclose(pipe);
    file = fopen(result, "wb");
    if (!file) return 4;
    fprintf(file, "%d", (int)length); fclose(file);
    return 0;
}
/* One PNG job, as the game's Lua asks for it: the handshake, request (13), then status
 * (14) every 50 ms until it is no longer pending. Prints state, error and size. */
static int exchange(HANDLE outgoing, HANDLE incoming, const unsigned char *request, uint32_t length,
                    unsigned char *reply, uint32_t capacity, uint32_t *size) {
    DWORD count;
    if (!WriteFile(outgoing, &length, 4, &count, NULL) || count != 4) return 0;
    if (!WriteFile(outgoing, request, length, &count, NULL) || count != length) return 0;
    if (!ReadFile(incoming, size, 4, &count, NULL) || count != 4 || *size > capacity) return 0;
    for (uint32_t got = 0; got < *size; got += count) if (!ReadFile(incoming, reply + got, *size - got, &count, NULL) || !count) return 0;
    return 1;
}
static int shot(const char *token, const char *path) {
    char name[256];
    static unsigned char request[4096], reply[70000];
    uint32_t size = 0, words[8] = {0}, length, nonce = 1;
    HANDLE outgoing = INVALID_HANDLE_VALUE, incoming;
    char id[33] = {0};
    for (int attempt = 0; attempt < 400 && outgoing == INVALID_HANDLE_VALUE; ++attempt) {
        snprintf(name, sizeof(name), "\\\\.\\pipe\\%s_request", token);
        outgoing = CreateFileA(name, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (outgoing == INVALID_HANDLE_VALUE) Sleep(50);
    }
    snprintf(name, sizeof(name), "\\\\.\\pipe\\%s_response", token);
    incoming = CreateFileA(name, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (outgoing == INVALID_HANDLE_VALUE || incoming == INVALID_HANDLE_VALUE) { printf("{\"connected\":false}\n"); return 3; }
    memset(request, 0, 12);
    if (!exchange(outgoing, incoming, request, 12, reply, sizeof(reply), &size)) return 4;
    for (uint32_t operation = 13;; operation = 14) {
        const char *argument = operation == 13 ? path : id;
        length = (uint32_t)strlen(argument);
        memcpy(request, &nonce, 4); memcpy(request + 4, &operation, 4); memcpy(request + 8, &length, 4);
        memcpy(request + 12, argument, length);
        if (!exchange(outgoing, incoming, request, 12 + length, reply, sizeof(reply), &size)) return 5;
        memcpy(words, reply, size < 32 ? size : 32);
        if (words[1]) { printf("{\"refused\":%u}\n", words[1]); return 0; }
        if (size < 64) return 6;
        memcpy(id, reply + 32, 32);
        if (words[2] != 1) {
            printf("{\"state\":%u,\"error\":%u,\"width\":%u,\"height\":%u,\"elapsed_ms\":%u}\n", words[2], words[3], words[4], words[5], words[6]);
            return 0;
        }
        ++nonce; Sleep(50);
    }
}
int main(int argc, char **argv) {
    if (argc == 4 && !strcmp(argv[1], "shot")) return shot(argv[2], argv[3]);
    if (argc == 3 && !strcmp(argv[1], "sleep")) return sleeper(argv[2]);
    if (argc == 3 && !strcmp(argv[1], "client")) return client(argv[2]);
    if (argc == 4 && !strcmp(argv[1], "popen")) return launcher(argv[2], argv[3]);
    return 1;
}

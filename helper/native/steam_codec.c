/* Bounded LZNT1/XPRESS bulk codec jobs. Runs inside the external helper only:
 * ntdll's Rtl compression routines are resolved in this process, never in the game. */
#ifndef WJL_STEAM_CODEC_C
#define WJL_STEAM_CODEC_C
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>

#define WJL_CODEC_VERSION 1u
#define WJL_CODEC_COMPRESS 0u
#define WJL_CODEC_DECOMPRESS 1u
#define WJL_CODEC_LZNT1 2u
#define WJL_CODEC_XPRESS 3u
#define WJL_CODEC_XPRESS_HUFF 4u
#define WJL_CODEC_MAXIMUM 0x100u
#define WJL_CODEC_MAX_RAW (4u * 1024u * 1024u)
/* Worst case for every supported format: XPRESS literals add 4 bytes per 32. */
#define WJL_CODEC_MAX_PACKED (WJL_CODEC_MAX_RAW + WJL_CODEC_MAX_RAW / 8u + 4096u)
#define WJL_CODEC_MAX_WORKSPACE (16u * 1024u * 1024u)
/* XPRESS refuses output that would not be smaller than its input. */
#define WJL_CODEC_INCOMPRESSIBLE ERROR_BUFFER_OVERFLOW

typedef LONG (NTAPI *wjl_workspace_fn)(USHORT, PULONG, PULONG);
typedef LONG (NTAPI *wjl_compress_fn)(USHORT, PUCHAR, ULONG, PUCHAR, ULONG, ULONG, PULONG, PVOID);
typedef LONG (NTAPI *wjl_decompress_fn)(USHORT, PUCHAR, ULONG, PUCHAR, ULONG, PULONG, PVOID);
static wjl_workspace_fn wjl_codec_workspace_size;
static wjl_compress_fn wjl_codec_compress_buffer;
static wjl_decompress_fn wjl_codec_decompress_buffer;

static int wjl_codec_resolve(void) {
    HMODULE ntdll;
    if (wjl_codec_compress_buffer) return 1;
    ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) return 0;
    wjl_codec_workspace_size = (wjl_workspace_fn)(void *)GetProcAddress(ntdll, "RtlGetCompressionWorkSpaceSize");
    wjl_codec_decompress_buffer = (wjl_decompress_fn)(void *)GetProcAddress(ntdll, "RtlDecompressBufferEx");
    wjl_codec_compress_buffer = (wjl_compress_fn)(void *)GetProcAddress(ntdll, "RtlCompressBuffer");
    return wjl_codec_workspace_size && wjl_codec_decompress_buffer && wjl_codec_compress_buffer;
}

static DWORD wjl_codec_status(LONG status) {
    switch ((ULONG)status) {
    case 0x00000000u: return 0;                          /* STATUS_SUCCESS */
    case 0x00000117u: return 0;                          /* STATUS_BUFFER_ALL_ZEROS: output is valid */
    case 0xC0000023u: return ERROR_INSUFFICIENT_BUFFER;  /* STATUS_BUFFER_TOO_SMALL */
    case 0xC0000242u: return ERROR_INVALID_DATA;         /* STATUS_BAD_COMPRESSION_BUFFER */
    case 0xC00000BBu: return ERROR_NOT_SUPPORTED;        /* STATUS_NOT_SUPPORTED */
    case 0xC000025Fu: return ERROR_NOT_SUPPORTED;        /* STATUS_UNSUPPORTED_COMPRESSION */
    default: return ERROR_INVALID_DATA;
    }
}

/* Upper bound of the output for a request; the caller reserves exactly this.
 * Decompression gets one spare byte so longer data is detected, not truncated. */
static uint32_t wjl_codec_capacity(uint32_t mode, uint32_t size, uint32_t expected) {
    return mode == WJL_CODEC_COMPRESS ? size + size / 8u + 4096u : expected + 1u;
}

/* One synchronous job. Decompression succeeds only when the output size is
 * exactly `expected`; compression requires 1..MAX_RAW input bytes. */
static DWORD wjl_codec_run(uint32_t mode, uint32_t format, const unsigned char *input, uint32_t size,
                           uint32_t expected, unsigned char *output, uint32_t capacity, uint32_t *produced) {
    uint32_t engine = format & WJL_CODEC_MAXIMUM, base = format & ~WJL_CODEC_MAXIMUM;
    ULONG workspace_size = 0, fragment = 0, final = 0;
    void *workspace;
    LONG status;
    *produced = 0;
    if (base != WJL_CODEC_LZNT1 && base != WJL_CODEC_XPRESS && base != WJL_CODEC_XPRESS_HUFF)
        return ERROR_NOT_SUPPORTED;
    if (mode == WJL_CODEC_COMPRESS) {
        if (!size || size > WJL_CODEC_MAX_RAW || expected) return ERROR_INVALID_PARAMETER;
    } else if (mode == WJL_CODEC_DECOMPRESS) {
        if (engine || !size || size > WJL_CODEC_MAX_PACKED || !expected || expected > WJL_CODEC_MAX_RAW)
            return ERROR_INVALID_PARAMETER;
    } else return ERROR_INVALID_PARAMETER;
    if (capacity < wjl_codec_capacity(mode, size, expected)) return ERROR_INSUFFICIENT_BUFFER;
    if (!wjl_codec_resolve()) return ERROR_PROC_NOT_FOUND;
    status = wjl_codec_workspace_size((USHORT)format, &workspace_size, &fragment);
    if (status) return wjl_codec_status(status);
    if (workspace_size > WJL_CODEC_MAX_WORKSPACE) return ERROR_NOT_ENOUGH_MEMORY;
    workspace = malloc(workspace_size ? workspace_size : 1);
    if (!workspace) return ERROR_NOT_ENOUGH_MEMORY;
    if (mode == WJL_CODEC_COMPRESS)
        status = wjl_codec_compress_buffer((USHORT)format, (PUCHAR)input, size, output, capacity,
                                           4096, &final, workspace);
    else
        status = wjl_codec_decompress_buffer((USHORT)format, output, expected + 1u, (PUCHAR)input, size,
                                             &final, workspace);
    free(workspace);
    if (mode == WJL_CODEC_COMPRESS && (ULONG)status == 0xC0000023u) return WJL_CODEC_INCOMPRESSIBLE;
    if (status && (ULONG)status != 0x00000117u) return wjl_codec_status(status);
    if (mode == WJL_CODEC_DECOMPRESS && final != expected) return ERROR_INVALID_DATA;
    if (final > capacity) return ERROR_INVALID_DATA;
    *produced = final;
    return 0;
}
#endif

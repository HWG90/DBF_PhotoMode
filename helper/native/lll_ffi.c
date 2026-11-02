/* In-process FFI kernel for the Steam Lua 5.1 VM (draft).
 *
 * The game links Lua 5.1 statically and exports no lua_* API, so this module
 * never calls the Lua C API. Every export is a lua_CFunction that Lua itself
 * wraps through package.loadlib(path, "wjl_ffi_<name>"). Arguments are read
 * and results written directly through the stock Lua 5.1.5 x64 lua_State /
 * TValue layout. wjl_ffi_probe checks that layout against known arguments;
 * until it succeeds every other entry point returns no values.
 *
 * Results are restricted to nil, booleans, numbers and light userdata, which
 * need no VM allocation. Strings, tables and cdata objects are built by the
 * Lua side (sdk/ffi/wjl_ffi.lua). Failures return nil plus a numeric code and
 * never raise Lua errors. Memory access and native calls run under SEH so a
 * bad pointer reports WJL_FFI_FAULT instead of terminating the game. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <string.h>

#define WJL_FFI_VERSION 1
#define WJL_FFI_MAX_ARGS 24
#define WJL_FFI_MAX_BYTES 16

/* Stock Lua 5.1.5 x64 layout (lstate.h, lobject.h). */
#define LUA_TNIL 0
#define LUA_TBOOLEAN 1
#define LUA_TLIGHTUSERDATA 2
#define LUA_TNUMBER 3
#define LUA_TSTRING 4
#define LUA_TTABLE 5
#define LUA_TFUNCTION 6
#define LUA_TTHREAD 8
#define STATE_TT 8      /* CommonHeader.tt */
#define STATE_TOP 16    /* StkId top */
#define STATE_BASE 24   /* StkId base */
#define STATE_GLOBAL 32 /* global_State *l_G */
#define GC_TT 8         /* CommonHeader.tt of any GC object */
#define TSTRING_LEN 16
#define TSTRING_DATA 24 /* sizeof(union TString) */

typedef struct wjl_tvalue {
    union { void *p; double n; int b; } value;
    int tt;
} wjl_tvalue;

/* Error codes returned after nil. The Lua side maps them to messages. */
enum {
    WJL_FFI_UNVERIFIED = 1,
    WJL_FFI_BAD_ARGUMENT = 2,
    WJL_FFI_FAULT = 3,
    WJL_FFI_NOT_FOUND = 4,
    WJL_FFI_NO_MEMORY = 5,
    WJL_FFI_TOO_MANY = 6
};

typedef struct wjl_ffi_result { uint64_t integer; double real; } wjl_ffi_result;
/* wjl_ffi_call.asm: loads slots 0-3 into both RCX/RDX/R8/R9 and XMM0-3,
 * spills the rest to the stack, calls fn and stores RAX and XMM0. */
extern void wjl_ffi_invoke(void *fn, const uint64_t *slots, size_t count, wjl_ffi_result *out);

static volatile LONG wjl_verified;
static DWORD wjl_last_error;

static wjl_tvalue **wjl_top(void *L) { return (wjl_tvalue **)((char *)L + STATE_TOP); }
static wjl_tvalue *wjl_base(void *L) { return *(wjl_tvalue **)((char *)L + STATE_BASE); }
static int wjl_count(void *L) { return (int)(*wjl_top(L) - wjl_base(L)); }
static wjl_tvalue *wjl_arg(void *L, int index) {
    return index < wjl_count(L) ? wjl_base(L) + index : NULL;
}

/* A C function always has LUA_MINSTACK (20) free slots above its arguments;
 * no entry point pushes more than WJL_FFI_MAX_BYTES + 2 values. */
static void wjl_push(void *L, int tt, wjl_tvalue value) {
    wjl_tvalue **top = wjl_top(L);
    value.tt = tt;
    **top = value;
    ++*top;
}
static int wjl_nil(void *L) { wjl_tvalue v = {0}; wjl_push(L, LUA_TNIL, v); return 1; }
static int wjl_bool(void *L, int b) { wjl_tvalue v = {0}; v.value.b = b != 0; wjl_push(L, LUA_TBOOLEAN, v); return 1; }
static int wjl_number(void *L, double n) { wjl_tvalue v = {0}; v.value.n = n; wjl_push(L, LUA_TNUMBER, v); return 1; }
static int wjl_pointer(void *L, void *p) { wjl_tvalue v = {0}; v.value.p = p; wjl_push(L, LUA_TLIGHTUSERDATA, v); return 1; }
static int wjl_fail(void *L, int code) { wjl_nil(L); wjl_number(L, code); return 2; }

static int wjl_get_number(void *L, int index, double *out) {
    wjl_tvalue *v = wjl_arg(L, index);
    if (!v || v->tt != LUA_TNUMBER) return 0;
    *out = v->value.n;
    return 1;
}
static int wjl_get_size(void *L, int index, size_t *out) {
    double n;
    if (!wjl_get_number(L, index, &n) || n < 0 || n > 9007199254740992.0 || n != (double)(uint64_t)n) return 0;
    *out = (size_t)n;
    return 1;
}
static const char *wjl_get_string(void *L, int index, size_t *length) {
    wjl_tvalue *v = wjl_arg(L, index);
    if (!v || v->tt != LUA_TSTRING) return NULL;
    *length = *(size_t *)((char *)v->value.p + TSTRING_LEN);
    return (const char *)v->value.p + TSTRING_DATA;
}
/* Pointer arguments: light userdata, nil (NULL), integral number, or a string
 * (its immutable bytes; valid while the caller keeps the string referenced). */
static int wjl_get_pointer(void *L, int index, void **out) {
    wjl_tvalue *v = wjl_arg(L, index);
    size_t length;
    if (!v) { *out = NULL; return 1; }
    switch (v->tt) {
    case LUA_TNIL: *out = NULL; return 1;
    case LUA_TLIGHTUSERDATA: *out = v->value.p; return 1;
    case LUA_TNUMBER:
        if (v->value.n < 0 || v->value.n != (double)(uint64_t)v->value.n) return 0;
        *out = (void *)(uintptr_t)(uint64_t)v->value.n;
        return 1;
    case LUA_TSTRING: *out = (void *)wjl_get_string(L, index, &length); return 1;
    default: return 0;
    }
}
/* Number to integer bits: values above INT64_MAX keep their unsigned meaning. */
static uint64_t wjl_bits(double n) {
    if (n >= 9223372036854775808.0) return (uint64_t)n;
    return (uint64_t)(int64_t)n;
}

/* probe(12.5, true, "lll-ffi", {}, function) -> true, version
 * Returns no values when the layout does not match, so a mismatch never
 * writes through the unverified layout. */
__declspec(dllexport) int wjl_ffi_probe(void *L) {
    int ok = 0;
    __try {
        wjl_tvalue *base = wjl_base(L);
        const char *text;
        size_t length;
        ok = *((unsigned char *)L + STATE_TT) == LUA_TTHREAD
            && *(void **)((char *)L + STATE_GLOBAL) != NULL
            && wjl_count(L) == 5
            && base[0].tt == LUA_TNUMBER && base[0].value.n == 12.5
            && base[1].tt == LUA_TBOOLEAN && base[1].value.b == 1
            && base[2].tt == LUA_TSTRING && *((unsigned char *)base[2].value.p + GC_TT) == LUA_TSTRING
            && base[3].tt == LUA_TTABLE && *((unsigned char *)base[3].value.p + GC_TT) == LUA_TTABLE
            && base[4].tt == LUA_TFUNCTION && *((unsigned char *)base[4].value.p + GC_TT) == LUA_TFUNCTION;
        if (ok) {
            text = wjl_get_string(L, 2, &length);
            ok = length == 7 && memcmp(text, "lll-ffi", 8) == 0;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        ok = 0;
    }
    if (!ok) return 0;
    InterlockedExchange(&wjl_verified, 1);
    wjl_bool(L, 1);
    wjl_number(L, WJL_FFI_VERSION);
    return 2;
}

#define WJL_REQUIRE_VERIFIED() do { if (!wjl_verified) return 0; } while (0)

/* alloc(size) -> pointer (zeroed). free(pointer) -> true */
__declspec(dllexport) int wjl_ffi_alloc(void *L) {
    size_t size;
    void *p;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_size(L, 0, &size)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    p = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size ? size : 1);
    return p ? wjl_pointer(L, p) : wjl_fail(L, WJL_FFI_NO_MEMORY);
}
__declspec(dllexport) int wjl_ffi_free(void *L) {
    void *p;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    return wjl_bool(L, !p || HeapFree(GetProcessHeap(), 0, p));
}

/* Scalar kinds shared with the Lua side. */
enum {
    K_I8 = 1, K_U8, K_I16, K_U16, K_I32, K_U32, K_I64, K_U64, K_F32, K_F64, K_PTR, K_BOOL
};
static size_t wjl_kind_size(int kind) {
    static const size_t sizes[] = {0, 1, 1, 2, 2, 4, 4, 8, 8, 4, 8, 8, 1};
    return kind >= K_I8 && kind <= K_BOOL ? sizes[kind] : 0;
}

/* read(pointer, offset, kind) -> value */
__declspec(dllexport) int wjl_ffi_read(void *L) {
    void *p;
    double offset, kind_n;
    int kind, result = 0;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p) || !wjl_get_number(L, 1, &offset) || !wjl_get_number(L, 2, &kind_n))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    kind = (int)kind_n;
    if (!p || !wjl_kind_size(kind)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    p = (char *)p + (intptr_t)offset;
    __try {
        switch (kind) {
        case K_I8: result = wjl_number(L, *(int8_t *)p); break;
        case K_U8: result = wjl_number(L, *(uint8_t *)p); break;
        case K_I16: result = wjl_number(L, *(int16_t *)p); break;
        case K_U16: result = wjl_number(L, *(uint16_t *)p); break;
        case K_I32: result = wjl_number(L, *(int32_t *)p); break;
        case K_U32: result = wjl_number(L, *(uint32_t *)p); break;
        case K_I64: result = wjl_number(L, (double)*(int64_t *)p); break;
        case K_U64: result = wjl_number(L, (double)*(uint64_t *)p); break;
        case K_F32: result = wjl_number(L, *(float *)p); break;
        case K_F64: result = wjl_number(L, *(double *)p); break;
        case K_PTR: result = wjl_pointer(L, *(void **)p); break;
        case K_BOOL: result = wjl_bool(L, *(uint8_t *)p); break;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return result;
}

/* write(pointer, offset, kind, value) -> true */
__declspec(dllexport) int wjl_ffi_write(void *L) {
    void *p, *pointer_value = NULL;
    double offset, kind_n, n = 0;
    int kind;
    wjl_tvalue *value;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p) || !wjl_get_number(L, 1, &offset) || !wjl_get_number(L, 2, &kind_n))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    kind = (int)kind_n;
    value = wjl_arg(L, 3);
    if (!p || !wjl_kind_size(kind)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (kind == K_PTR) {
        if (!wjl_get_pointer(L, 3, &pointer_value)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    } else if (kind == K_BOOL && value && value->tt == LUA_TBOOLEAN) {
        n = value->value.b;
    } else if (!wjl_get_number(L, 3, &n)) {
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    }
    p = (char *)p + (intptr_t)offset;
    __try {
        uint64_t bits = wjl_bits(n);
        switch (kind) {
        case K_I8: case K_U8: *(uint8_t *)p = (uint8_t)bits; break;
        case K_I16: case K_U16: *(uint16_t *)p = (uint16_t)bits; break;
        case K_I32: case K_U32: *(uint32_t *)p = (uint32_t)bits; break;
        case K_I64: case K_U64: *(uint64_t *)p = bits; break;
        case K_F32: *(float *)p = (float)n; break;
        case K_F64: *(double *)p = n; break;
        case K_PTR: *(void **)p = pointer_value; break;
        case K_BOOL: *(uint8_t *)p = n != 0; break;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return wjl_bool(L, 1);
}

/* bytes(pointer, offset, count<=16) -> byte, ... */
__declspec(dllexport) int wjl_ffi_bytes(void *L) {
    void *p;
    double offset;
    size_t count, i;
    unsigned char copy[WJL_FFI_MAX_BYTES];
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p) || !wjl_get_number(L, 1, &offset) || !wjl_get_size(L, 2, &count))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (!p || count > WJL_FFI_MAX_BYTES) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    __try {
        memcpy(copy, (char *)p + (intptr_t)offset, count);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    for (i = 0; i < count; ++i) wjl_number(L, copy[i]);
    return (int)count;
}

/* store(pointer, offset, string[, count]) -> true. Copies min(count, #string) bytes. */
__declspec(dllexport) int wjl_ffi_store(void *L) {
    void *p;
    double offset;
    size_t length, count;
    const char *text;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p) || !wjl_get_number(L, 1, &offset) || !(text = wjl_get_string(L, 2, &length)))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    count = length;
    if (wjl_arg(L, 3) && (!wjl_get_size(L, 3, &count) || count > length)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (!p) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    __try {
        memcpy((char *)p + (intptr_t)offset, text, count);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return wjl_bool(L, 1);
}

/* copy(destination, source, count) -> true */
__declspec(dllexport) int wjl_ffi_copy(void *L) {
    void *destination, *source;
    size_t count;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &destination) || !wjl_get_pointer(L, 1, &source) || !wjl_get_size(L, 2, &count))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (count && (!destination || !source)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    __try {
        memmove(destination, source, count);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return wjl_bool(L, 1);
}

/* fill(destination, count, byte) -> true */
__declspec(dllexport) int wjl_ffi_fill(void *L) {
    void *destination;
    size_t count;
    double byte = 0;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &destination) || !wjl_get_size(L, 1, &count)
        || (wjl_arg(L, 2) && !wjl_get_number(L, 2, &byte)))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (count && !destination) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    __try {
        memset(destination, (int)wjl_bits(byte) & 0xff, count);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return wjl_bool(L, 1);
}

/* strlen(pointer[, limit]) -> length */
__declspec(dllexport) int wjl_ffi_strlen(void *L) {
    const char *p;
    size_t limit = (size_t)1 << 30, length = 0;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, (void **)&p) || (wjl_arg(L, 1) && !wjl_get_size(L, 1, &limit)))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (!p) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    __try {
        while (length < limit && p[length]) ++length;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    return wjl_number(L, (double)length);
}

/* offset(pointer, delta) -> pointer; address(pointer) -> number */
__declspec(dllexport) int wjl_ffi_offset(void *L) {
    void *p;
    double delta;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p) || !wjl_get_number(L, 1, &delta)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    return wjl_pointer(L, (char *)p + (intptr_t)delta);
}
__declspec(dllexport) int wjl_ffi_address(void *L) {
    void *p;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &p)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    return wjl_number(L, (double)(uintptr_t)p);
}

/* load(name) -> module handle */
__declspec(dllexport) int wjl_ffi_load(void *L) {
    size_t length;
    const char *name;
    HMODULE module;
    WJL_REQUIRE_VERIFIED();
    if (!(name = wjl_get_string(L, 0, &length)) || strlen(name) != length) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    module = LoadLibraryA(name);
    wjl_last_error = GetLastError();
    return module ? wjl_pointer(L, module) : wjl_fail(L, WJL_FFI_NOT_FOUND);
}

/* sym(module handle or nil, name) -> function/data address.
 * nil searches the default namespace like LuaJIT's ffi.C on Windows. */
__declspec(dllexport) int wjl_ffi_sym(void *L) {
    static const wchar_t *defaults[] = {L"kernel32.dll", L"user32.dll", L"gdi32.dll", L"msvcrt.dll", L"ntdll.dll"};
    void *module_pointer;
    size_t length, i;
    const char *name;
    FARPROC found = NULL;
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &module_pointer) || !(name = wjl_get_string(L, 1, &length)) || strlen(name) != length)
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (module_pointer) {
        found = GetProcAddress((HMODULE)module_pointer, name);
    } else {
        found = GetProcAddress(GetModuleHandleW(NULL), name);
        for (i = 0; !found && i < sizeof(defaults) / sizeof(defaults[0]); ++i) {
            HMODULE module = GetModuleHandleW(defaults[i]);
            if (!module) module = LoadLibraryW(defaults[i]);
            if (module) found = GetProcAddress(module, name);
        }
    }
    return found ? wjl_pointer(L, (void *)found) : wjl_fail(L, WJL_FFI_NOT_FOUND);
}

/* call(function, result_kind, argument_kinds, ...) -> result
 * Argument kinds: 'i' integer, 'f' float, 'd' double, 'p' pointer.
 * Result kinds: 'v' void, 'b' bool, 'c'/'C' int8/uint8, 's'/'S' int16/uint16,
 * 'i'/'u' int32/uint32, 'I'/'U' int64/uint64 (as a number), 'f', 'd', 'p'.
 * Win64 passes each of the first four arguments in the integer or vector
 * register of its position, so both are loaded with the same bits. */
__declspec(dllexport) int wjl_ffi_call(void *L) {
    void *fn;
    const char *kinds, *result_kind;
    size_t count, result_length, i;
    uint64_t slots[WJL_FFI_MAX_ARGS] = {0};
    wjl_ffi_result out = {0, 0};
    WJL_REQUIRE_VERIFIED();
    if (!wjl_get_pointer(L, 0, &fn) || !fn || !(result_kind = wjl_get_string(L, 1, &result_length))
        || result_length != 1 || !(kinds = wjl_get_string(L, 2, &count)))
        return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    if (count > WJL_FFI_MAX_ARGS) return wjl_fail(L, WJL_FFI_TOO_MANY);
    if (wjl_count(L) != (int)count + 3) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    for (i = 0; i < count; ++i) {
        int index = (int)i + 3;
        double n;
        void *p;
        wjl_tvalue *value = wjl_arg(L, index);
        switch (kinds[i]) {
        case 'i':
            if (value->tt == LUA_TBOOLEAN) slots[i] = (uint64_t)value->value.b;
            else if (wjl_get_number(L, index, &n)) slots[i] = wjl_bits(n);
            else return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
            break;
        case 'f': {
            float f;
            if (!wjl_get_number(L, index, &n)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
            f = (float)n;
            memcpy(&slots[i], &f, sizeof(f));
            break;
        }
        case 'd':
            if (!wjl_get_number(L, index, &n)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
            memcpy(&slots[i], &n, sizeof(n));
            break;
        case 'p':
            if (!wjl_get_pointer(L, index, &p)) return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
            slots[i] = (uint64_t)(uintptr_t)p;
            break;
        default:
            return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
        }
    }
    __try {
        SetLastError(0);
        wjl_ffi_invoke(fn, slots, count, &out);
        wjl_last_error = GetLastError();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return wjl_fail(L, WJL_FFI_FAULT);
    }
    switch (result_kind[0]) {
    case 'v': return wjl_bool(L, 1);
    case 'b': return wjl_bool(L, (uint8_t)out.integer);
    case 'c': return wjl_number(L, (int8_t)out.integer);
    case 'C': return wjl_number(L, (uint8_t)out.integer);
    case 's': return wjl_number(L, (int16_t)out.integer);
    case 'S': return wjl_number(L, (uint16_t)out.integer);
    case 'i': return wjl_number(L, (int32_t)out.integer);
    case 'u': return wjl_number(L, (uint32_t)out.integer);
    case 'I': return wjl_number(L, (double)(int64_t)out.integer);
    case 'U': return wjl_number(L, (double)out.integer);
    case 'f': { float f; memcpy(&f, &out.real, sizeof(f)); return wjl_number(L, f); }
    case 'd': return wjl_number(L, out.real);
    case 'p': return wjl_pointer(L, (void *)(uintptr_t)out.integer);
    default: return wjl_fail(L, WJL_FFI_BAD_ARGUMENT);
    }
}

/* errno() -> GetLastError() captured after the last call/load */
__declspec(dllexport) int wjl_ffi_errno(void *L) {
    WJL_REQUIRE_VERIFIED();
    return wjl_number(L, wjl_last_error);
}

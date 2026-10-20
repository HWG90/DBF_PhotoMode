// Photo-owned zero-delta guard for the verified Jumppack movement update.
// MinHook v1.3.4 is statically linked; installation is explicitly outside DllMain.
// Once hook creation begins, this module and its trampoline remain resident.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include "../vendor/minhook/include/MinHook.h"

static_assert(sizeof(void*) == 8, "The verified game ABI is x64 only");
using Movement = void (__fastcall*)(void*, uint32_t, float);
using Verifier = bool (*)(Movement&);
using ProtectCallback = BOOL (WINAPI*)(LPVOID,SIZE_T,DWORD,PDWORD);
static SRWLOCK install_lock = SRWLOCK_INIT;
// Used only by the synchronous installer while it holds install_lock. Never
// retained by the detour, a trampoline, or a later game update.
static ProtectCallback protection_callback=nullptr;
static std::atomic<Movement> original{nullptr};
static std::atomic<uint32_t> installed{0}, armed{0}, last_error{0};
static std::atomic<uint64_t> skipped{0}, forwarded{0};
static std::atomic<uint32_t> protection_error{0};
extern "C" BOOL WINAPI PhotoHoverGuardProtectDispatch(LPVOID address,SIZE_T size,DWORD requested,PDWORD previous) {
    const ProtectCallback callback=protection_callback;
    const BOOL result=callback?callback(address,size,requested,previous):VirtualProtect(address,size,requested,previous);
    const DWORD code=result?ERROR_SUCCESS:GetLastError();
    protection_error.store(code,std::memory_order_release);
    if (!result) SetLastError(code);
    return result;
}
#if defined(HG_DIAGNOSTIC)
static std::atomic<uint64_t> protection_address{0}, protection_size{0}, protection_calls{0};
static std::atomic<uint32_t> protection_requested{0}, protection_result{0};
#if defined(HG_TEST_PROTECT_FAILURE)
static bool deny_protection_for_fixture=false;
#endif
// Called only by a generated compilation wrapper around unchanged hook.c.
// Preserve the exact request/result and capture the error BEFORE MinHook's
// Unfreeze/ResumeThread/CloseHandle cleanup can replace this thread's last error.
extern "C" BOOL WINAPI PhotoHoverGuardProtectTrace(LPVOID address,SIZE_T size,DWORD requested,PDWORD previous) {
    BOOL result;
#if defined(HG_TEST_PROTECT_FAILURE)
    if (deny_protection_for_fixture) { SetLastError(ERROR_ACCESS_DENIED);result=FALSE; }
    else
#endif
    result=PhotoHoverGuardProtectDispatch(address,size,requested,previous);
    const DWORD code=result?ERROR_SUCCESS:GetLastError();
    protection_address.store(reinterpret_cast<uintptr_t>(address),std::memory_order_relaxed);
    protection_size.store(size,std::memory_order_relaxed);
    protection_requested.store(requested,std::memory_order_relaxed);
    protection_result.store(result!=FALSE,std::memory_order_relaxed);
    protection_error.store(code,std::memory_order_release);
    protection_calls.fetch_add(1,std::memory_order_release);
    if (!result) SetLastError(code);
    return result;
}
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardProtectError(void) { return protection_error.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardProtectAddress(void) { return protection_address.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardProtectSize(void) { return protection_size.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardProtectRequested(void) { return protection_requested.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardProtectResult(void) { return protection_result.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardProtectCalls(void) { return protection_calls.load(std::memory_order_acquire); }
#endif
static bool installation_failed = false;
enum GuardError : uint32_t {
    NONE=0, NOT_INSTALLED=1, MODULE_MISSING=2, IMAGE_INVALID=3,
    GAME_BUILD_MISMATCH=4, EXE_BUILD_MISMATCH=5, FINGERPRINT_MISMATCH=6,
    MODULE_PIN_FAILED=7, INVALID_ARM_ARGUMENT=8, TARGET_NOT_EXECUTABLE=9, INVALID_CALLBACK=10,
    MINHOOK_INITIALIZE=0x10000, MINHOOK_CREATE=0x20000,
    MINHOOK_QUEUE=0x30000, MINHOOK_APPLY=0x40000
};
static void error(uint32_t value) { last_error.store(value, std::memory_order_release); }
static bool read(const void* address, void* output, size_t size) {
    SIZE_T actual=0;
    return ReadProcessMemory(GetCurrentProcess(), address, output, size, &actual)!=0 && actual==size;
}
static bool image(HMODULE module, IMAGE_NT_HEADERS64& nt) {
    IMAGE_DOS_HEADER dos{};
    if (!module || !read(module,&dos,sizeof dos) || dos.e_magic!=IMAGE_DOS_SIGNATURE ||
        dos.e_lfanew<static_cast<LONG>(sizeof dos) || dos.e_lfanew>0x100000) return false;
    if (!read(reinterpret_cast<const uint8_t*>(module)+dos.e_lfanew,&nt,sizeof nt)) return false;
    return nt.Signature==IMAGE_NT_SIGNATURE && nt.FileHeader.Machine==IMAGE_FILE_MACHINE_AMD64 &&
        nt.FileHeader.SizeOfOptionalHeader==sizeof(IMAGE_OPTIONAL_HEADER64) &&
        nt.OptionalHeader.Magic==IMAGE_NT_OPTIONAL_HDR64_MAGIC &&
        nt.OptionalHeader.SizeOfImage>=0x1000 && nt.OptionalHeader.SizeOfImage<=0x40000000;
}
static bool executable(const void* address) {
    MEMORY_BASIC_INFORMATION info{};
    if (VirtualQuery(address,&info,sizeof info)!=sizeof info || info.State!=MEM_COMMIT ||
        (info.Protect & (PAGE_GUARD|PAGE_NOACCESS))) return false;
    const DWORD protection=info.Protect & 0xff;
    return protection==PAGE_EXECUTE || protection==PAGE_EXECUTE_READ ||
        protection==PAGE_EXECUTE_READWRITE || protection==PAGE_EXECUTE_WRITECOPY;
}
static int hex(char c) {
    if (c>='0' && c<='9') return c-'0';
    if (c>='a' && c<='f') return c-'a'+10;
    return -1;
}
static bool bytes(HMODULE module, uint32_t image_size, uint32_t rva, const char* expected) {
    const size_t length=std::strlen(expected);
    if ((length&1) || length==0 || length>128 || rva>image_size || length/2>image_size-rva) return false;
    uint8_t actual[64]{};
    if (!read(reinterpret_cast<const uint8_t*>(module)+rva,actual,length/2)) return false;
    for (size_t i=0;i<length/2;++i) {
        const int high=hex(expected[i*2]), low=hex(expected[i*2+1]);
        if (high<0 || low<0 || actual[i]!=static_cast<uint8_t>((high<<4)|low)) return false;
    }
    return true;
}
static constexpr uint32_t TARGET_RVA=0x9B4790, GAME_STAMP=0x6AB3B43F,
    GAME_SIZE=0x4744000, EXE_STAMP=0x6AB382E4;
static constexpr const char* ENTRY16="48895c24185556574154415541564157";
static constexpr const char* ENTRY64="48895c24185556574154415541564157488dac2450ffffff4881ecb0010000440f29b42420010000488b055178c8014833c4488945004c8be948894c24508bca";
struct Fingerprint { uint32_t rva; const char* expected; };
static constexpr Fingerprint fingerprints[]={
    {TARGET_RVA,ENTRY16}, {TARGET_RVA,ENTRY64},
    {0x9B47D0,"440f28f2f30f11542458"}, // original dt XMM2 -> XMM14 and stack
    {0x9B507C,"f3440f10742458"},       // reload original dt
    {0x9B50FA,"f3450f5eee"},           // divss XMM13,XMM14
    {0x9B5127,"f3410f5efe"},           // divss XMM7,XMM14
    {0x9B512C,"f3410f5ef6"},           // divss XMM6,XMM14
    {0x9B5186,"f3410f114500"},         // velocity x
    {0x9B5190,"f3410f115d04"},         // velocity y
    {0x9B5196,"f3410f114d08"}          // velocity z
};
static bool verify_game(Movement& target) {
    const HMODULE game=GetModuleHandleW(L"game.dll"), exe=GetModuleHandleW(nullptr);
    if (!game || !exe) { error(MODULE_MISSING);return false; }
    IMAGE_NT_HEADERS64 game_nt{},exe_nt{};
    if (!image(game,game_nt) || !image(exe,exe_nt)) { error(IMAGE_INVALID);return false; }
    if (game_nt.FileHeader.TimeDateStamp!=GAME_STAMP || game_nt.OptionalHeader.SizeOfImage!=GAME_SIZE) {
        error(GAME_BUILD_MISMATCH);return false;
    }
    if (exe_nt.FileHeader.TimeDateStamp!=EXE_STAMP) { error(EXE_BUILD_MISMATCH);return false; }
    for (const auto& fingerprint:fingerprints) {
        if (!bytes(game,GAME_SIZE,fingerprint.rva,fingerprint.expected)) { error(FINGERPRINT_MISMATCH);return false; }
    }
    const auto address=reinterpret_cast<const uint8_t*>(game)+TARGET_RVA;
    if (!executable(address)) { error(TARGET_NOT_EXECUTABLE);return false; }
    target=reinterpret_cast<Movement>(const_cast<uint8_t*>(address));return true;
}
#if defined(HG_DIAGNOSTIC)
static uint32_t probe_target(Movement target) {
    DWORD previous=0,ignored=0;
    if (!PhotoHoverGuardProtectTrace(reinterpret_cast<void*>(target),5,PAGE_EXECUTE_READWRITE,&previous)) return 0;
    // Permission test only: never write any instruction/data or start a hook.
    // Restore exactly the protection returned by this same imported API.
    if (!PhotoHoverGuardProtectTrace(reinterpret_cast<void*>(target),5,previous,&ignored)) return 0;
    return 1;
}
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardProbeProtect(void) {
    AcquireSRWLockExclusive(&install_lock);
    Movement target=nullptr;
    const uint32_t result=verify_game(target)?probe_target(target):0;
    ReleaseSRWLockExclusive(&install_lock);
    return result;
}
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardVirtualProtectImportAddress(void) {
    return reinterpret_cast<uintptr_t>(&VirtualProtect);
}
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardVirtualProtectExportAddress(void) {
    const HMODULE kernel=GetModuleHandleW(L"kernel32.dll");
    return kernel?reinterpret_cast<uintptr_t>(GetProcAddress(kernel,"VirtualProtect")):0;
}
#endif
static void __fastcall detour(void* manager, uint32_t row, float dt) {
    // Bit testing is equivalent to dt==0 for both signed zeros and avoids
    // changing FP exception state when an unrelated NaN must forward unchanged.
    uint32_t bits=0;std::memcpy(&bits,&dt,sizeof bits);
    if (armed.load(std::memory_order_acquire)!=0 && (bits&0x7fffffffU)==0) {
        skipped.fetch_add(1,std::memory_order_relaxed);return;
    }
    forwarded.fetch_add(1,std::memory_order_relaxed);
    original.load(std::memory_order_acquire)(manager,row,dt);
}
static bool pin(const void* address) {
    HMODULE module=nullptr;
    return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(address),&module)!=0;
}
static uint32_t install(Verifier verify,ProtectCallback callback=nullptr) {
    AcquireSRWLockExclusive(&install_lock);
    struct Unlock { ~Unlock() { ReleaseSRWLockExclusive(&install_lock); } } unlock;
    struct ResetCallback { ~ResetCallback() { protection_callback=nullptr; } } reset_callback;
    if (callback && !executable(reinterpret_cast<const void*>(callback))) { error(INVALID_CALLBACK);return 0; }
    protection_callback=callback;
    if (installed.load(std::memory_order_acquire)!=0) { error(NONE);return 1; }
    if (installation_failed) return 0;
    Movement target=nullptr;
    // Every module/build/code guard runs before any hook is created.
    if (!verify(target)) return 0;
    if (!target || !pin(reinterpret_cast<const void*>(&install)) || !pin(reinterpret_cast<const void*>(target))) {
        error(MODULE_PIN_FAILED);return 0;
    }
    MH_STATUS status=MH_Initialize();
    if (status!=MH_OK && status!=MH_ERROR_ALREADY_INITIALIZED) { error(MINHOOK_INITIALIZE+static_cast<uint32_t>(status));return 0; }
    Movement trampoline=nullptr;
    status=MH_CreateHook(reinterpret_cast<void*>(target),reinterpret_cast<void*>(&detour),reinterpret_cast<void**>(&trampoline));
    if (status!=MH_OK || !trampoline) { error(MINHOOK_CREATE+static_cast<uint32_t>(status));installation_failed=true;return 0; }
    original.store(trampoline,std::memory_order_release);
    // CreateHook has not enabled a patch. Reject a changed target before the
    // thread transaction. Keep this disabled trampoline resident even on failure.
    Movement checked=nullptr;
    if (!verify(checked) || checked!=target) { installation_failed=true;return 0; }
    status=MH_QueueEnableHook(reinterpret_cast<void*>(target));
    if (status!=MH_OK) { error(MINHOOK_QUEUE+static_cast<uint32_t>(status));installation_failed=true;return 0; }
    status=MH_ApplyQueued();
    if (status!=MH_OK) {
        // A failed transaction may already have relocated a suspended thread IP
        // into the trampoline. Never free it or uninitialize/unload this DLL.
        armed.store(0,std::memory_order_release);error(MINHOOK_APPLY+static_cast<uint32_t>(status));installation_failed=true;return 0;
    }
    installed.store(1,std::memory_order_release);error(NONE);return 1;
}
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardInstall(void) { return install(verify_game); }
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardInstallWithProtection(ProtectCallback callback) {
    // The caller retains callback until this call returns. It must not yield,
    // throw, or re-enter guard APIs; it returns the ordinary WinAPI BOOL result.
    return install(verify_game,callback);
}
#if !defined(HG_DIAGNOSTIC)
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardProtectError(void) { return protection_error.load(std::memory_order_acquire); }
#endif
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardArm(uint32_t enabled) {
    if (enabled>1) { error(INVALID_ARM_ARGUMENT);return 0; }
    if (enabled!=0 && installed.load(std::memory_order_acquire)==0) {
        uint32_t expected=NONE;last_error.compare_exchange_strong(expected,NOT_INSTALLED);return 0;
    }
    armed.store(enabled,std::memory_order_release);return 1;
}
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardSkipped(void) { return skipped.load(std::memory_order_relaxed); }
extern "C" __declspec(dllexport) uint64_t PhotoHoverGuardForwarded(void) { return forwarded.load(std::memory_order_relaxed); }
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardInstalled(void) { return installed.load(std::memory_order_acquire); }
extern "C" __declspec(dllexport) uint32_t PhotoHoverGuardError(void) { return last_error.load(std::memory_order_acquire); }
// There is deliberately no unhook/unload API or hook work in DllMain. Lua owns
// arm(true) only during its acquired zero pause and disarms after positive update.

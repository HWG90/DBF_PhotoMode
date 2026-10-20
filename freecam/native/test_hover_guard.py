"""Isolated native guard tests; synthetic target only, never opens the game process."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import build_hover_guard as builder

HARNESS=r'''
#include "__GUARD_SOURCE__"
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>
#define CHECK(x) do { if (!(x)) { std::fprintf(stderr,"check failed line %d: %s\n",__LINE__,#x);std::abort(); } } while (0)
struct State { uint64_t before=0x1122334455667788ULL; uint32_t row=0,bits=0;uint64_t after=0x8877665544332211ULL; };
static std::atomic<uint64_t> actual_calls{0};
__declspec(noinline) static void __fastcall synthetic(void* manager,uint32_t row,float dt) {
    State* state=static_cast<State*>(manager);
    state->row=row;std::memcpy(&state->bits,&dt,sizeof dt);
    actual_calls.fetch_add(1,std::memory_order_relaxed);
}
static char prefix[129]{};
static bool permit=false;
static bool verify_synthetic(Movement& target) {
    if (!permit || !bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix)) { error(FINGERPRINT_MISMATCH);return false; }
    target=&synthetic;return true;
}
static float as_float(uint32_t bits) { float value;std::memcpy(&value,&bits,sizeof value);return value; }
static uint32_t delegated_calls=0;
static bool delegate_deny=false;
static BOOL WINAPI delegated_protection(LPVOID address,SIZE_T size,DWORD requested,PDWORD previous) {
    ++delegated_calls;
    if (delegate_deny) { SetLastError(ERROR_ACCESS_DENIED);return FALSE; }
    return VirtualProtect(address,size,requested,previous);
}
int main(int argc,char** argv) {
#if !defined(HG_DIAGNOSTIC)
    (void)argc;(void)argv;
#endif
    IMAGE_NT_HEADERS64 actual_nt{};CHECK(image(GetModuleHandleW(nullptr),actual_nt));
    auto* fake=static_cast<uint8_t*>(VirtualAlloc(nullptr,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE));CHECK(fake);
    IMAGE_DOS_HEADER dos{};dos.e_magic=IMAGE_DOS_SIGNATURE;dos.e_lfanew=128;std::memcpy(fake,&dos,sizeof dos);
    IMAGE_NT_HEADERS64 nt=actual_nt;std::memcpy(fake+128,&nt,sizeof nt);IMAGE_NT_HEADERS64 got{};
    CHECK(image(reinterpret_cast<HMODULE>(fake),got));
    fake[0]=0;CHECK(!image(reinterpret_cast<HMODULE>(fake),got));std::memcpy(fake,&dos,sizeof dos);
    dos.e_lfanew=-1;std::memcpy(fake,&dos,sizeof dos);CHECK(!image(reinterpret_cast<HMODULE>(fake),got));dos.e_lfanew=128;std::memcpy(fake,&dos,sizeof dos);
    nt.FileHeader.Machine=IMAGE_FILE_MACHINE_I386;std::memcpy(fake+128,&nt,sizeof nt);CHECK(!image(reinterpret_cast<HMODULE>(fake),got));
    nt=actual_nt;nt.OptionalHeader.SizeOfImage=0xFFFFFFFF;std::memcpy(fake+128,&nt,sizeof nt);CHECK(!image(reinterpret_cast<HMODULE>(fake),got));
    CHECK(!image(reinterpret_cast<HMODULE>(1),got));
    fake[512]=0x12;fake[513]=0x34;CHECK(bytes(reinterpret_cast<HMODULE>(fake),4096,512,"1234"));
    CHECK(!bytes(reinterpret_cast<HMODULE>(fake),4096,512,"1235"));CHECK(!bytes(reinterpret_cast<HMODULE>(fake),4096,4095,"1234"));
    CHECK(!bytes(reinterpret_cast<HMODULE>(fake),4096,512,"1"));CHECK(!bytes(reinterpret_cast<HMODULE>(fake),4096,512,"zz"));
    CHECK(!executable(fake));CHECK(executable(reinterpret_cast<const void*>(&synthetic)));CHECK(VirtualFree(fake,0,MEM_RELEASE));
    uint8_t entry[64]{};CHECK(read(reinterpret_cast<const void*>(&synthetic),entry,sizeof entry));
    for (size_t i=0;i<64;++i)std::snprintf(prefix+i*2,3,"%02x",entry[i]);
    CHECK(PhotoHoverGuardInstalled()==0 && PhotoHoverGuardSkipped()==0 && PhotoHoverGuardForwarded()==0);
    CHECK(PhotoHoverGuardArm(1)==0 && PhotoHoverGuardArm(0)==1);
    // Signature rejection performs no patch and remains retryable before create.
    CHECK(install(verify_synthetic)==0);CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix));
    CHECK(install(verify_synthetic,&delegated_protection)==0 && delegated_calls==0 && protection_callback==nullptr);
    CHECK(install(verify_synthetic,reinterpret_cast<ProtectCallback>(1))==0 && PhotoHoverGuardError()==INVALID_CALLBACK && protection_callback==nullptr);
    permit=true;
    if (argc==2 && std::strcmp(argv[1],"--callback-denial")==0) {
        delegate_deny=true;CHECK(install(verify_synthetic,&delegated_protection)==0);
        CHECK(PhotoHoverGuardError()==MINHOOK_APPLY+MH_ERROR_MEMORY_PROTECT && PhotoHoverGuardProtectError()==ERROR_ACCESS_DENIED);
        CHECK(delegated_calls==1 && protection_callback==nullptr && installed==0 && armed==0);
        CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix) && original!=nullptr);
        SetLastError(ERROR_INVALID_PARAMETER);CHECK(PhotoHoverGuardProtectError()==ERROR_ACCESS_DENIED);
        delegate_deny=false;CHECK(install(verify_synthetic,&delegated_protection)==0 && delegated_calls==1 && protection_callback==nullptr);
        std::puts("Protection callback denial: exact error retained, bytes unchanged, disarmed, callback cleared, no retry passed");return 0;
    }
#if defined(HG_DIAGNOSTIC)
    CHECK(PhotoHoverGuardProtectError()==0);
    CHECK(PhotoHoverGuardVirtualProtectImportAddress()!=0 && PhotoHoverGuardVirtualProtectExportAddress()!=0);
    if (argc==2 && std::strcmp(argv[1],"--probe-only")==0) {
        MEMORY_BASIC_INFORMATION before{},after{};
        CHECK(VirtualQuery(reinterpret_cast<const void*>(&synthetic),&before,sizeof before)==sizeof before);
        CHECK(probe_target(&synthetic)==1);
        CHECK(VirtualQuery(reinterpret_cast<const void*>(&synthetic),&after,sizeof after)==sizeof after && before.Protect==after.Protect);
        CHECK(PhotoHoverGuardProtectCalls()==2 && PhotoHoverGuardProtectResult()==1 && PhotoHoverGuardProtectError()==0);
        CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix) && PhotoHoverGuardInstalled()==0 && original==nullptr);
        deny_protection_for_fixture=true;CHECK(probe_target(&synthetic)==0);
        CHECK(PhotoHoverGuardProtectCalls()==3 && PhotoHoverGuardProtectError()==ERROR_ACCESS_DENIED);
        CHECK(PhotoHoverGuardProtectAddress()==reinterpret_cast<uintptr_t>(&synthetic) && PhotoHoverGuardProtectSize()==5);
        CHECK(PhotoHoverGuardProtectRequested()==PAGE_EXECUTE_READWRITE && PhotoHoverGuardProtectResult()==0);
        CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix) && PhotoHoverGuardInstalled()==0 && original==nullptr);
        CHECK(PhotoHoverGuardForwarded()==0 && PhotoHoverGuardSkipped()==0);
        std::puts("Permission-only probe: same import, protection restored, code unchanged, denial captured, no hook/trampoline created passed");return 0;
    }
    if (argc==2 && std::strcmp(argv[1],"--deny-protection")==0) {
        deny_protection_for_fixture=true;
        CHECK(install(verify_synthetic)==0 && PhotoHoverGuardError()==MINHOOK_APPLY+MH_ERROR_MEMORY_PROTECT);
        CHECK(PhotoHoverGuardInstalled()==0 && PhotoHoverGuardArm(1)==0 && armed==0);
        CHECK(PhotoHoverGuardProtectError()==ERROR_ACCESS_DENIED);
        CHECK(PhotoHoverGuardProtectAddress()==reinterpret_cast<uintptr_t>(&synthetic));
        CHECK(PhotoHoverGuardProtectSize()==5 && PhotoHoverGuardProtectRequested()==PAGE_EXECUTE_READWRITE);
        CHECK(PhotoHoverGuardProtectResult()==0 && PhotoHoverGuardProtectCalls()==1);
        CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix));
        State state;volatile Movement direct=&synthetic;direct(&state,77,as_float(0x3F800000));
        CHECK(state.row==77 && state.bits==0x3F800000 && actual_calls==1);
        CHECK(original!=nullptr);original.load()(&state,88,as_float(0x40000000));
        CHECK(state.row==88 && state.bits==0x40000000 && actual_calls==2);
        SetLastError(ERROR_INVALID_PARAMETER);CHECK(PhotoHoverGuardProtectError()==ERROR_ACCESS_DENIED);
        deny_protection_for_fixture=false;CHECK(install(verify_synthetic)==0);
        CHECK(bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix) && PhotoHoverGuardSkipped()==0 && PhotoHoverGuardForwarded()==0);
        std::puts("Injected VirtualProtect denial: exact pre-cleanup error retained, target unchanged, guard disarmed, resident trampoline valid, no retry passed");return 0;
    }
#endif
    const bool use_callback=argc==2 && std::strcmp(argv[1],"--callback-success")==0;
    CHECK(install(verify_synthetic,use_callback?&delegated_protection:nullptr)==1);CHECK(PhotoHoverGuardInstalled()==1);CHECK(PhotoHoverGuardError()==0);
    CHECK(protection_callback==nullptr && delegated_calls==(use_callback?2U:0U));
#if defined(HG_DIAGNOSTIC)
    CHECK(PhotoHoverGuardProtectCalls()==2 && PhotoHoverGuardProtectResult()==1 && PhotoHoverGuardProtectError()==0);
#endif
    CHECK(!bytes(reinterpret_cast<HMODULE>(&synthetic),64,0,prefix));
    // The installed fast path is idempotent even though target bytes are now a hook.
    permit=false;CHECK(install(verify_synthetic)==1);CHECK(PhotoHoverGuardInstall()==1);
    CHECK(install(verify_synthetic,&delegated_protection)==1 && protection_callback==nullptr && delegated_calls==(use_callback?2U:0U));
    volatile Movement invoke=&synthetic;State state;
    invoke(&state,0xDEADBEEF,0.0f);CHECK(actual_calls==1 && state.row==0xDEADBEEF && state.bits==0 && PhotoHoverGuardForwarded()==1);
    CHECK(PhotoHoverGuardArm(1)==1);invoke(nullptr,0xCAFEBABE,0.0f);invoke(nullptr,0xCAFEBABE,as_float(0x80000000));
    CHECK(PhotoHoverGuardSkipped()==2 && actual_calls==1 && PhotoHoverGuardForwarded()==1);
    // All non-zero patterns forward unchanged: positive/negative, minimum normal,
    // subnormal, infinity, quiet NaN, and signaling NaN without FP comparison.
    const uint32_t patterns[]={0x3C888889,0xBF800000,0x00800000,1,0x7F800000,0x7FC12345,0x7F812345};
    uint32_t row=0xFEDCBA98;
    for (uint32_t bits:patterns) { invoke(&state,row,as_float(bits));CHECK(state.row==row && state.bits==bits);--row; }
    CHECK(PhotoHoverGuardSkipped()==2 && actual_calls==8 && PhotoHoverGuardForwarded()==8);
    CHECK(state.before==0x1122334455667788ULL && state.after==0x8877665544332211ULL);
    CHECK(PhotoHoverGuardArm(2)==0 && PhotoHoverGuardError()==INVALID_ARM_ARGUMENT);
    // Invalid arm requests preserve the previous valid arm state.
    invoke(nullptr,10,0.0f);CHECK(PhotoHoverGuardSkipped()==3);
    CHECK(PhotoHoverGuardArm(0)==1);invoke(&state,10,as_float(0x80000000));CHECK(state.bits==0x80000000 && actual_calls==9);
    // Idempotent installation, atomic counters, and exact argument forwarding
    // remain safe across concurrent callers; no uninstall is attempted.
    std::vector<std::thread> workers;
    for (uint32_t i=0;i<4;++i)workers.emplace_back([i]() {
        State local;volatile Movement call=&synthetic;
        for (uint32_t k=0;k<1000;++k) { CHECK(PhotoHoverGuardInstall()==1);call(&local,k+i,as_float(0x3F800000));CHECK(local.row==k+i && local.bits==0x3F800000); }
    });
    for (auto& worker:workers)worker.join();
    CHECK(actual_calls==4009 && PhotoHoverGuardForwarded()==4009 && PhotoHoverGuardSkipped()==3);
    CHECK(PhotoHoverGuardInstalled()==1 && PhotoHoverGuardArm(0)==1);
    std::puts("Synthetic MinHook fixture: guarded signature, actual transaction, idempotence, signed-zero skip, ABI/bit-exact forwarding, counters, and concurrency passed");
    return 0;
}
'''

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build',type=Path,default=builder.REPO/'dist/review/hover-guard-native-20261013')
    args=parser.parse_args();output=args.build.resolve();metadata=json.loads((output/'hover-guard-native.json').read_text())
    library=output/metadata['library']
    assert hashlib.sha256(library.read_bytes()).hexdigest()==metadata['sha256'],'Built candidate identity changed'
    builder.dependency_identity()
    # Validate hard-coded hazard fingerprints against the independent mapped-image
    # evidence, rather than merely generating expected bytes from the implementation.
    evidence=builder.REPO/'dist/review/hoverpack-input-20261013'
    static=json.loads((evidence/'JUMPPACK-ZERO-DT-STATIC.json').read_text())
    source=(ROOT/'hover_guard.cpp').read_text()
    for key,name in [('entry16_hex','ENTRY16'),('entry64_hex','ENTRY64')]:
        expected=static['review_guard_boundary'][key]
        assert name+'="'+expected+'"' in source
    with (evidence/static['image']['file']).open('rb')as image:
        for match in re.finditer(r'\{0x([0-9A-F]+),"([0-9a-f]+)"\}',source):
            rva=int(match[1],16);expected=bytes.fromhex(match[2]);image.seek(rva)
            assert image.read(len(expected))==expected,hex(rva)+' fingerprint disagrees with observed image'
    # Production DLL in this standalone Python host fails closed: no game module
    # is available, counters remain zero, no synthetic/game function is hooked.
    dll=ctypes.CDLL(str(library))
    for name,signature in metadata['exports'].items():
        fn=getattr(dll,name);fn.restype=ctypes.c_uint64 if signature.startswith('uint64')else ctypes.c_uint32
        fn.argtypes=[ctypes.c_uint32]if name=='PhotoHoverGuardArm'else [ctypes.c_void_p]if name=='PhotoHoverGuardInstallWithProtection'else []
    assert dll.PhotoHoverGuardInstalled()==0
    assert dll.PhotoHoverGuardInstall()==0 and dll.PhotoHoverGuardError()==2
    assert dll.PhotoHoverGuardInstallWithProtection(None)==0 and dll.PhotoHoverGuardError()==2
    assert dll.PhotoHoverGuardArm(1)==0 and dll.PhotoHoverGuardInstalled()==0
    assert dll.PhotoHoverGuardArm(0)==1
    assert dll.PhotoHoverGuardForwarded()==0 and dll.PhotoHoverGuardSkipped()==0
    fixture=output/'hover_guard_fixture.cpp'
    fixture.write_text(HARNESS.replace('__GUARD_SOURCE__',(ROOT/'hover_guard.cpp').as_posix()),encoding='utf-8')
    obj=output/'hover_guard_fixture.obj';exe=output/'hover_guard_fixture.exe'
    flags='/DHG_DIAGNOSTIC /DHG_TEST_PROTECT_FAILURE 'if metadata.get('diagnostic_virtualprotect_error')else ''
    commands=['cl /nologo /c /MT /EHsc /std:c++17 /O2 /W4 /WX '+flags+'"'+str(fixture)+'" /Fo"'+str(obj)+'"',
              'link /nologo /OUT:"'+str(exe)+'" "'+str(obj)+'" '+
              ' '.join('"'+str(output/('minhook-'+str(i)+'.obj'))+'"'for i in range(4))+' kernel32.lib']
    builder.compile_at(output,commands)
    subprocess.run([str(exe)],cwd=output,check=True,timeout=30)
    subprocess.run([str(exe),'--callback-success'],cwd=output,check=True,timeout=30)
    subprocess.run([str(exe),'--callback-denial'],cwd=output,check=True,timeout=30)
    if metadata.get('diagnostic_virtualprotect_error'):
        assert dll.PhotoHoverGuardProtectError()==0,'Missing-module rejection must not request protection'
        assert dll.PhotoHoverGuardProbeProtect()==0 and dll.PhotoHoverGuardProtectCalls()==0,'Probe metadata must reject before permission change'
        assert dll.PhotoHoverGuardVirtualProtectImportAddress()!=0 and dll.PhotoHoverGuardVirtualProtectExportAddress()!=0
        subprocess.run([str(exe),'--probe-only'],cwd=output,check=True,timeout=30)
        subprocess.run([str(exe),'--deny-protection'],cwd=output,check=True,timeout=30)
    receipt={'passed':True,'isolated_tests_only':True,'game_process_accessed':False,'production_sha256':metadata['sha256'],
             'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),
             'checks':['production missing-module refusal','PE/header/bounds/executable guards','mapped-image signature agreement',
                       'real MinHook enable transaction','idempotent install','inactive zero forwards','armed +/-zero skips',
                       'nonzero dt bit-exact ABI forwarding','invalid arm rejection','atomic counters and four concurrent callers',
                       'synchronous protection callback success/denial, exact error and pointer cleared on every outcome']}
    if metadata.get('diagnostic_virtualprotect_error'):
        receipt['checks'].extend(['permission-only same-import probe restores protection and preserves code with no hook/trampoline',
                                  'injected VirtualProtect denial with exact error, unchanged target, resident trampoline and no retry'])
    (output/'hover-guard-native-tests.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print('Production fail-closed and actual synthetic hook fixtures passed; no game process accessed')

if __name__=='__main__':main()

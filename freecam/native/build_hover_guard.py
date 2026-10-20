"""Build an isolated x64 hover guard candidate with static MinHook/CRT; never installs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
VENDOR=ROOT.parent/'vendor/minhook'
SOURCES=('src/buffer.c','src/hook.c','src/trampoline.c','src/hde/hde64.c')
EXPORTS={'PhotoHoverGuardInstall':'uint32_t (void)','PhotoHoverGuardArm':'uint32_t (uint32_t enabled)',
         'PhotoHoverGuardSkipped':'uint64_t (void)','PhotoHoverGuardForwarded':'uint64_t (void)',
         'PhotoHoverGuardInstalled':'uint32_t (void)','PhotoHoverGuardError':'uint32_t (void)',
         'PhotoHoverGuardInstallWithProtection':'uint32_t (BOOL WINAPI (*callback)(void*,SIZE_T,DWORD,DWORD*))',
         'PhotoHoverGuardProtectError':'uint32_t (void)'}

def vcvars():
    value=Path(r'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat')
    if not value.is_file():raise RuntimeError('MSVC x64 environment missing')
    return value

def compile_at(output,commands):
    script=output/'compile-hover-guard.cmd'
    script.write_text('@echo off\ncall "'+str(vcvars())+'" >nul\nif errorlevel 1 exit /b %errorlevel%\n'+
                      ''.join(command+'\nif errorlevel 1 exit /b %errorlevel%\n'for command in commands),encoding='utf-8')
    subprocess.run(['cmd','/d','/c',str(script)],cwd=output,check=True)

def dependency_identity():
    provenance=json.loads((VENDOR/'PROVENANCE.json').read_text())
    if provenance.get('commit')!='c3fcafdc10146beb5919319d0683e44e3c30d537':raise RuntimeError('Unexpected MinHook commit')
    identities={p.relative_to(VENDOR).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                for p in VENDOR.rglob('*')if p.is_file()and p.name!='PROVENANCE.json'}
    expected=provenance['files']
    for identity in expected:
        name=identity['path']
        if identities.get(name)!=identity['sha256']:raise RuntimeError('MinHook source identity changed: '+name)
    if len(identities)!=len(expected):raise RuntimeError('Unexpected files in minimal MinHook dependency')
    return identities

def build(output,diagnostic=False):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    identities=dependency_identity();source=ROOT/'hover_guard.cpp'
    digest=hashlib.sha256(source.read_bytes()+json.dumps(identities,sort_keys=True).encode()+str(diagnostic).encode()).hexdigest()
    name='PhotoHoverGuard_'+digest[:16]+'.dll'
    commands=[];objects=[]
    wrapper=output/'minhook-hook-protection.c';dispatch='PhotoHoverGuardProtectTrace'if diagnostic else 'PhotoHoverGuardProtectDispatch'
    wrapper.write_text('#define WIN32_LEAN_AND_MEAN\n#include <windows.h>\n'
                       'extern BOOL WINAPI '+dispatch+'(LPVOID,SIZE_T,DWORD,PDWORD);\n'
                       '#define VirtualProtect '+dispatch+'\n'
                       '#include "'+(VENDOR/'src/hook.c').as_posix()+'"\n',encoding='utf-8')
    for i,name_c in enumerate(SOURCES):
        obj=output/('minhook-'+str(i)+'.obj');objects.append(obj)
        input_source=wrapper if name_c=='src/hook.c'else VENDOR/name_c
        commands.append('cl /nologo /c /TC /MT /O2 /W3 "'+str(input_source)+'" /Fo"'+str(obj)+'"')
    obj=output/'hover_guard.obj';objects.append(obj)
    commands.append('cl /nologo /c /MT /EHsc /std:c++17 /O2 /W4 /WX '+('/DHG_DIAGNOSTIC 'if diagnostic else '')+'"'+str(source)+'" /Fo"'+str(obj)+'"')
    commands.append('link /nologo /DLL /DYNAMICBASE /NXCOMPAT /OUT:"'+str(output/name)+'" /IMPLIB:"'+str(output/'hover_guard.lib')+'" '+
                    ' '.join('"'+str(obj)+'"'for obj in objects)+' kernel32.lib')
    compile_at(output,commands)
    exports=dict(EXPORTS)
    if diagnostic:
        exports.update({name:'uint64_t (void)'for name in ('PhotoHoverGuardProtectAddress','PhotoHoverGuardProtectSize','PhotoHoverGuardProtectCalls')})
        exports.update({name:'uint32_t (void)'for name in ('PhotoHoverGuardProtectError','PhotoHoverGuardProtectRequested','PhotoHoverGuardProtectResult')})
        exports.update({name:'uint64_t (void)'for name in ('PhotoHoverGuardVirtualProtectImportAddress','PhotoHoverGuardVirtualProtectExportAddress')})
        exports['PhotoHoverGuardProbeProtect']='uint32_t (void)'
    metadata={'library':name,'sha256':hashlib.sha256((output/name).read_bytes()).hexdigest(),
              'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'minhook_commit':'c3fcafdc10146beb5919319d0683e44e3c30d537',
              'minhook_files_sha256':identities,'exports':exports,'runtime':'Windows x64, static CRT and static MinHook',
              'diagnostic_virtualprotect_error':diagnostic,'generated_hook_wrapper_sha256':hashlib.sha256(wrapper.read_bytes()).hexdigest()if wrapper else None,
              'target':{'game_timestamp':'6AB3B43F','game_image_size':'4744000','exe_timestamp':'6AB382E4','rva':'9B4790','abi':'void(void* RCX,uint32_t EDX,float XMM2)'},
              'predicate':'Photo-armed and exactly signed-zero dt; all other calls forward unchanged',
              'protection_callback_contract':'Only synchronous during InstallWithProtection under install_lock; cleared before unlock/return. No yield, throw, or re-entry. Ordinary VirtualProtect request and MinHook transaction unchanged; detour never retains callback.',
              'lifetime':'process-pinned; no unhook/unload API','failure':'0; PhotoHoverGuardError returns validation or MinHook stage/status code',
              'deployment':'not installed','live_validation':False}
    (output/'hover-guard-native.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (output/'hover-library.txt').write_text(name+'\n')
    (output/'LICENSE-MINHOOK.txt').write_bytes((VENDOR/'LICENSE.txt').read_bytes())
    print(json.dumps({'library':name,'sha256':metadata['sha256'],'output':str(output),'deployment':'not installed'},indent=2))
    return metadata

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=REPO/'dist/review/hover-guard-native-20261013')
    parser.add_argument('--diagnostic',action='store_true',help='Record VirtualProtect failure before MinHook cleanup; unchanged protection strategy')
    args=parser.parse_args();build(args.output,args.diagnostic)

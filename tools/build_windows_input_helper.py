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
p.write_text(s)
# WJL owns a separate namespace and settings/log directory. The upstream
# checkout is read-only; all compilation inputs here are private copies.
for owned in native.iterdir():
 if owned.suffix in ('.c','.cpp','.h'):
  body=owned.read_text(encoding='utf-8').replace('LLL','WJL').replace('lll_','wjl_')
  owned.write_text(body,encoding='utf-8')
# Preserve the source delta as a reviewable patch; owning LLL checkout stays untouched.
patch=''
for name in ('steam_keyboard.c','test_steam_keyboard.c','steam_files.c','steam_service.c'):
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

(root/'freecam/wjl_helper_payload.lua').write_text('return {name='+json.dumps(binary.name)+',sha256='+json.dumps(hashlib.sha256(binary.read_bytes()).hexdigest())+',hex='+json.dumps(binary.read_bytes().hex())+'}\n')

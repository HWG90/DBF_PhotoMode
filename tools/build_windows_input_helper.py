from pathlib import Path
import shutil,hashlib,json
root=Path.cwd();source=(root/'../LLL').resolve();review=root/'dist/review/windows-wjl-helper';native=review/'native';native.mkdir(parents=True,exist_ok=True)
for p in (source/'native').iterdir():
 if p.suffix in ('.c','.cpp','.h'):shutil.copy2(p,native/p.name)
p=native/'steam_keyboard.c';s=p.read_text();s=s.replace('    if (key >= 160 && key <= 165) return 0;', '''    /* Preserve the desktop's Ctrl+Shift+Space shortcut. It is already owned
     * on this Windows host; a single collision otherwise aborts all gameplay keys. */
    if (key == VK_SPACE && modifiers == (MOD_CONTROL | MOD_SHIFT)) return 0;
    if (key >= 160 && key <= 165) return 0;''',1);p.write_text(s)
p=native/'test_steam_keyboard.c';s=p.read_text().replace('880','879');s=s.replace('    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_ALT));','    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_CONTROL|MOD_SHIFT));\n    CHECK(lll_keyboard_tuple(VK_SPACE,0));\n    CHECK(!lll_keyboard_tuple(VK_SPACE,MOD_ALT));');p.write_text(s)
p=native/'steam_files.c';s=p.read_text();import re
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
        if (keyboard.state == LLL_KEYBOARD_ACTIVE)''');p.write_text(s)
# WJL owns a separate namespace and settings/log directory. The upstream
# checkout is read-only; all compilation inputs here are private copies.
for owned in native.iterdir():
 if owned.suffix in ('.c','.cpp','.h'):
  body=owned.read_text(encoding='utf-8').replace('LLL','WJL').replace('lll_','wjl_')
  owned.write_text(body,encoding='utf-8')
# Preserve the source delta as a reviewable patch; owning LLL checkout stays untouched.
import subprocess
patch=''
for name in ('steam_keyboard.c','test_steam_keyboard.c','steam_files.c','steam_service.c'):
 a=(source/'native'/name).read_text().splitlines(keepends=True);b=(native/name).read_text().splitlines(keepends=True)
 import difflib
 patch+=''.join(difflib.unified_diff(a,b,fromfile='a/native/'+name,tofile='b/native/'+name))
(root/'tools/windows_input_shortcut.patch').write_text(patch)
spec=__import__('importlib.util',fromlist=['spec_from_file_location']);sp=spec.spec_from_file_location('builder',source/'tools/build_steam_service.py');builder=spec.module_from_spec(sp);sp.loader.exec_module(builder);builder.ROOT=review
built=builder.build(review/'build')
binary=built.with_name('wjl_steam_service_'+hashlib.sha256(built.read_bytes()).hexdigest()[:16]+'.exe')
binary.write_bytes(built.read_bytes())
(review/'HELPER.json').write_text(json.dumps({'binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'preserved_shortcut':'Ctrl+Shift+Space','sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in native.iterdir()}},indent=2)+'\n')
print(binary)

(root/'freecam/wjl_helper_payload.lua').write_text('return {name='+json.dumps(binary.name)+',sha256='+json.dumps(hashlib.sha256(binary.read_bytes()).hexdigest())+',hex='+json.dumps(binary.read_bytes().hex())+'}\n')

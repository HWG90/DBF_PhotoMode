"""Offline exact RAW/legacy keyboard-event gate harness; no windows, hooks or injected input."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess
from build_photo_input import compile_at

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
HARNESS = r'''
#include <assert.h>
#include <stdio.h>
#include "__SOURCE__"
int main(void) {
    assert(mcm_escape_passthrough()==1);
    InterlockedExchange(&wheel,120);assert(gameplay_wheel_observe(1)==0);
    InterlockedExchange(&wheel,240);assert(gameplay_wheel_observe(1)==240);
    assert(gameplay_wheel_observe(1)==0);
    InterlockedExchange(&wheel,120);assert(gameplay_wheel_observe(0)==0);
    InterlockedExchange(&wheel,120);assert(gameplay_wheel_observe(1)==0);
    mcm_release();assert(!observe_wheel && !wheel);

    volatile LONG *paths[2]={previous_raw,previous_legacy};
    for (int path=0;path<2;++path) {
        volatile LONG *prior=paths[path];
        for (int mode=1;mode<=3;++mode) {
            InterlockedExchange(&keys[VK_ESCAPE],0);InterlockedExchange(&prior[VK_ESCAPE],0);
            assert(keyboard_event_gate(VK_ESCAPE,0,mode,prior)==(mode==3?0:1));
            assert(keyboard_event_gate(VK_ESCAPE,1,mode,prior)==(mode==3?0:1));
            assert(!keyboard_event_gate(VK_ESCAPE,1,0,prior));
            assert(keyboard_event_gate('A',0,mode,prior));
            assert(keyboard_event_gate('A',0,0,prior));
            assert(keyboard_event_gate('A',1,0,prior));
            assert(!keyboard_event_gate('A',0,0,prior));
            /* A key seen by gameplay before acquisition releases through. */
            InterlockedExchange(&prior['B'],1);
            assert(!keyboard_event_gate('B',1,mode,prior));
            assert(!InterlockedCompareExchange(&prior['B'],0,0));
            assert(keyboard_event_gate('B',0,mode,prior));
            assert(keyboard_event_gate('B',1,mode,prior));
            assert(!keyboard_event_gate('B',1,0,prior));
        }
        /* Escape forwarded in mode 3 must not become stuck when capture drops. */
        assert(!keyboard_event_gate(VK_ESCAPE,0,3,prior));
        assert(!keyboard_event_gate(VK_ESCAPE,1,0,prior));
        assert(keyboard_event_gate(VK_ESCAPE,0,1,prior));
        assert(!keyboard_event_gate(VK_ESCAPE,1,3,prior));
        assert(!keyboard_event_gate(VK_ESCAPE,1,0,prior));
        InterlockedExchange(&prior[VK_ESCAPE],1);
        assert(!keyboard_event_gate(VK_ESCAPE,1,1,prior));
    }
    assert(mouse_gate(RI_MOUSE_RIGHT_BUTTON_DOWN,3));
    assert(mouse_gate(0,0));assert(mouse_gate(RI_MOUSE_RIGHT_BUTTON_UP,0));assert(!mouse_gate(0,0));
    InterlockedExchange(&previous_mouse_raw,RI_MOUSE_RIGHT_BUTTON_UP);
    assert(!previous_mouse_release(&previous_mouse_raw,0));
    assert(previous_mouse_release(&previous_mouse_raw,RI_MOUSE_RIGHT_BUTTON_UP));
    assert(!previous_mouse_release(&previous_mouse_raw,RI_MOUSE_RIGHT_BUTTON_UP));
    assert(!mcm_policy(WM_MOUSEMOVE,0,2));assert(mcm_policy(WM_MOUSEMOVE,0,3));
    assert(mcm_policy(WM_CHAR,0,1));assert(mcm_policy(WM_INPUT,RIM_TYPEMOUSE,3));
    assert(!mcm_policy(WM_INPUT,RIM_TYPEHID,3));
    assert(!mcm_install(NULL));assert(!mcm_capture(3));mcm_release();assert(!mcm_captured());
    puts("RAW/legacy Escape down+up forwards only in camera mode 3; menu/overlay blocking, key/button drain and preheld releases unchanged. No window attached or input injected.");
    return 0;
}
'''

def test(build):
    build=build.resolve(); build.mkdir(parents=True,exist_ok=True)
    source=ROOT/'photo_input.cpp'; harness=build/'test_photo_input.cpp'
    harness.write_text(HARNESS.replace('__SOURCE__',source.as_posix()), encoding='utf-8')
    compile_at(build, [f'cl /nologo /MT /EHsc /O2 /W4 /WX "{harness}" /Fo"{build / "test_photo_input.obj"}" /Fe"{build / "test_photo_input.exe"}" /link user32.lib'])
    subprocess.run([str(build/'test_photo_input.exe')], check=True)
    metadata=json.loads((build/'photo-input-native.json').read_text())
    assert hashlib.sha256((build/metadata['library']).read_bytes()).hexdigest()==metadata['sha256']
    library=ctypes.CDLL(str(build/metadata['library']))
    library.mcm_escape_passthrough.argtypes=[];library.mcm_escape_passthrough.restype=ctypes.c_int
    assert library.mcm_escape_passthrough()==1, 'Built DLL must expose the owned Escape capability'
    result={'passed':True,'exact_source_keyboard_event_gate':True,'raw_and_legacy_paths':True,
            'windows_attached':False,'input_injected':False,'library_sha256':metadata['sha256']}
    (build/'photo-input-tests.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build',type=Path,default=REPO/'dist/review/native-menu-gate-098/native-input')
    test(parser.parse_args().build)

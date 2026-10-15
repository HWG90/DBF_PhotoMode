"""Exact-source native queue/clip tests with fake OS boundaries; no attached windows."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from build_photo_input import compile_at

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
HARNESS = r'''
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <assert.h>
#include <stdio.h>

static HWND fixture_foreground=(HWND)1;
static RECT fixture_clip={0,0,3840,2160};
static RECT fixture_client={0,0,1280,720};
static POINT fixture_origin={200,100};
static bool fixture_clear_after_previous,fixture_fail_clip;
static unsigned fixture_clip_calls;
static BOOL WINAPI fake_clip(const RECT *rect) {
    ++fixture_clip_calls;
    if (fixture_fail_clip) return FALSE;
    fixture_clip=rect ? *rect : RECT{0,0,3840,2160};return TRUE;
}
static BOOL WINAPI fake_get_clip(RECT *rect) { *rect=fixture_clip;return TRUE; }
static HWND WINAPI fake_foreground(void) { return fixture_foreground; }
static BOOL WINAPI fake_client(HWND hwnd,RECT *rect) { assert(hwnd==(HWND)1);*rect=fixture_client;return TRUE; }
static BOOL WINAPI fake_to_screen(HWND hwnd,POINT *point) { assert(hwnd==(HWND)1);point->x+=fixture_origin.x;point->y+=fixture_origin.y;return TRUE; }
static BOOL WINAPI fake_is_window(HWND hwnd) { return hwnd==(HWND)1; }
static SHORT WINAPI fake_key(int key) { (void)key;return 0; }
static LRESULT WINAPI fake_previous(WNDPROC proc,HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    (void)proc;(void)hwnd;(void)msg;(void)wp;(void)lp;
    if (fixture_clear_after_previous) fixture_clip=RECT{0,0,3840,2160};
    return 17;
}
#define ClipCursor fake_clip
#define GetClipCursor fake_get_clip
#define GetForegroundWindow fake_foreground
#define GetClientRect fake_client
#define ClientToScreen fake_to_screen
#define IsWindow fake_is_window
#define GetAsyncKeyState fake_key
#define CallWindowProcW fake_previous
#include "__SOURCE__"

static void assert_rect(LONG left,LONG top,LONG right,LONG bottom) {
    assert(fixture_clip.left==left && fixture_clip.top==top && fixture_clip.right==right && fixture_clip.bottom==bottom);
}
static void expect(int button,int down,int x,int y,double seconds) {
    MCM_CLICK_EVENT event={};
    assert(mcm_next_click(&event));
    assert(event.button==button && event.down==down && event.x==x && event.y==y && event.seconds==seconds);
}
static void empty(void) { MCM_CLICK_EVENT event={};assert(!mcm_next_click(&event)); }

int main(void) {
    static_assert(sizeof(MCM_CLICK_EVENT)==24,"Lua FFI click ABI changed");
    assert(mcm_cursor_confinement()==1);
    assert(!mcm_cursor_confined());
    owner=(HWND)1;
    assert(mcm_capture(3));assert_rect(200,100,1480,820);
    assert(clip_owned);
    assert(mcm_cursor_confined());
    fixture_clip=RECT{0,0,3840,2160};
    unsigned readback_writes=fixture_clip_calls;
    assert(!mcm_cursor_confined());assert(fixture_clip_calls==readback_writes);
    fixture_clear_after_previous=true;
    assert(guarded_proc(owner,WM_MOVE,0,0)==17);
    assert_rect(200,100,1480,820);
    assert(mcm_cursor_confined());
    fixture_clear_after_previous=false;
    fixture_origin=POINT{300,150};fixture_client=RECT{0,0,1600,900};
    assert(guarded_proc(owner,WM_SIZE,0,0)==17);
    assert_rect(300,150,1900,1050);
    assert(mcm_capture(1));assert_rect(0,0,3840,2160);assert(!clip_owned);
    assert(!mcm_cursor_confined());
    unsigned writes=fixture_clip_calls;
    assert(mcm_capture(2));assert(fixture_clip_calls==writes);
    assert(mcm_capture(3));
    fixture_client=RECT{0,0,0,0};camera_clip(3);assert_rect(0,0,3840,2160);assert(!clip_owned);
    fixture_client=RECT{0,0,1600,900};camera_clip(3);assert(clip_owned);
    fixture_fail_clip=true;mcm_release();assert(clip_owned);
    fixture_fail_clip=false;mcm_release();assert(!clip_owned);assert_rect(0,0,3840,2160);
    assert(mcm_capture(3));fixture_clip=RECT{10,20,110,220};fixture_foreground=(HWND)2;
    mcm_release();assert_rect(10,20,110,220);assert(!clip_owned);
    assert(!mcm_cursor_confined());
    fixture_foreground=(HWND)1;fixture_clip=RECT{0,0,3840,2160};
    /* A pre-existing game client clip is restored exactly in foreground,
     * but must never confine another foreground application after Alt-Tab. */
    fixture_clip=RECT{50,60,1050,760};
    assert(mcm_capture(3));assert(mcm_capture(1));assert_rect(50,60,1050,760);
    assert(mcm_capture(3));fixture_foreground=(HWND)2;
    mcm_release();assert_rect(0,0,3840,2160);assert(!clip_owned);
    fixture_foreground=(HWND)1;

    assert(mcm_capture(1));
    /* A RAW click may finish before its legacy duplicate is dispatched. */
    click_events(RI_MOUSE_LEFT_BUTTON_DOWN,1,11,22,1.0,1000,1);
    click_events(RI_MOUSE_LEFT_BUTTON_UP,1,12,23,1.01,1010,1);
    click_events(RI_MOUSE_LEFT_BUTTON_DOWN,1,11,22,1.02,1000,2);
    click_events(RI_MOUSE_LEFT_BUTTON_UP,1,12,23,1.03,1010,2);
    assert(!mcm_next_click(NULL));
    expect(1,1,11,22,1.0);expect(1,0,12,23,1.01);empty();
    /* Both complete click pairs survive until the next render, with either
     * source first. Duplicate route reports do not create extra edges. */
    for (int i=0;i<4;++i) {
        USHORT flag=(i&1)?RI_MOUSE_LEFT_BUTTON_UP:RI_MOUSE_LEFT_BUTTON_DOWN;
        int route=(i&1)?2:1;
        double seconds=2.0+i*0.01;
        click_events(flag,1,100+i,200+i,seconds,2000+i*10,route);
        click_events(flag,1,100+i,200+i,seconds+0.001,2001+i*10,3-route);
    }
    assert(mcm_capture(1));
    for (int i=0;i<4;++i) expect(1,(i&1)?0:1,100+i,200+i,2.0+i*0.01);
    empty();
    click_events(RI_MOUSE_RIGHT_BUTTON_DOWN|RI_MOUSE_MIDDLE_BUTTON_DOWN,1,-3,44,3.0,3000,1);
    expect(2,1,-3,44,3.0);expect(3,1,-3,44,3.0);
    click_events(RI_MOUSE_RIGHT_BUTTON_UP|RI_MOUSE_MIDDLE_BUTTON_UP,1,-4,45,3.1,3100,2);
    expect(2,0,-4,45,3.1);expect(3,0,-4,45,3.1);empty();

    /* Retain the newest 64 bounded events on overflow. */
    for (int i=0;i<80;++i) click_events((i&1)?RI_MOUSE_LEFT_BUTTON_UP:RI_MOUSE_LEFT_BUTTON_DOWN,
        1,i,i,4.0+i*0.01,4000+i*10,1);
    assert(click_count==64);
    for (int i=16;i<80;++i) expect(1,(i&1)?0:1,i,i,4.0+i*0.01);
    empty();
    click_events(RI_MOUSE_LEFT_BUTTON_DOWN,1,0,0,5.0,5000,1);
    assert(mcm_capture(3));empty();
    for (int mode=0;mode<=3;++mode) if (mode!=1) {
        assert(mcm_capture(mode));
        click_events(RI_MOUSE_LEFT_BUTTON_DOWN,mode,0,0,5.1,5100,1);empty();
    }
    assert(mcm_capture(1));click_events(RI_MOUSE_LEFT_BUTTON_DOWN,1,0,0,5.2,5200,1);
    mcm_release();empty();assert(!mcm_captured());
    assert(mcm_capture(1));click_events(RI_MOUSE_LEFT_BUTTON_DOWN,1,0,0,5.3,5300,1);
    fixture_foreground=(HWND)2;
    assert(guarded_proc(owner,WM_KILLFOCUS,0,0)==17);empty();assert(!mcm_captured());
    fixture_foreground=(HWND)1;assert(mcm_capture(3));fixture_foreground=(HWND)2;
    assert(guarded_proc(owner,WM_ACTIVATEAPP,0,0)==17);assert(!clip_owned);assert_rect(0,0,3840,2160);
    puts("Native confinement leases restore/retain foreign writers and reassert after previous callback; bounded RAW/legacy click edges deduplicate, survive fast pairs and clear on mode/release/focus. OS boundaries mocked; no window attached, hooks installed or input injected.");
    return 0;
}
'''


def test(build):
    build = build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'photo_input.cpp'
    harness = build / 'test_photo_input_reliability.cpp'
    harness.write_text(HARNESS.replace('__SOURCE__', source.as_posix()), encoding='utf-8')
    executable = build / 'test_photo_input_reliability.exe'
    compile_at(build, [
        f'cl /nologo /MT /EHsc /O2 /W4 /WX "{harness}" '
        f'/Fo"{build / "test_photo_input_reliability.obj"}" /Fe"{executable}" /link user32.lib'
    ])
    subprocess.run([str(executable)], check=True)
    result = {'passed': True, 'exact_source': True,
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'click_abi_bytes': 24, 'click_capacity': 64,
              'raw_legacy_deduplication': True, 'fast_pairs_retained': True,
              'mode_release_focus_clear': True, 'foreign_clip_preserved': True,
              'clip_restore_retry': True, 'after_previous_callback_reassertion': True,
              'confinement_readback': True,
              'focus_loss_releases_saved_game_clip': True,
              'windows_attached': False, 'hooks_installed': False, 'input_injected': False,
              'os_boundaries': 'mocked'}
    (build / 'photo-input-reliability-tests.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path,
                        default=REPO / 'dist/review/native-input-reliability-20261014')
    test(parser.parse_args().build)

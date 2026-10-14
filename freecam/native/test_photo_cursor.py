"""Offline exact-source cursor fixture; no windows, hooks or injected input."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from build_photo_input import compile_at

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
ASSET = REPO / 'freecam/assets/helldivers_cursor.cur'

HARNESS = r'''
#include <assert.h>
#include <stdio.h>
#include "__SOURCE__"

int wmain(int argc, wchar_t **argv) {
    assert(argc == 2);
    char path[32768];
    assert(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[1], -1,
        path, (int)sizeof path, NULL, NULL) > 0);

    assert(!mcm_menu_cursor());
    assert(!mcm_captured());
    assert(!mcm_load_menu_cursor(NULL));
    assert(!mcm_load_menu_cursor(""));
    assert(!mcm_load_menu_cursor("relative.cur"));
    assert(!mcm_load_menu_cursor("C:/__war_journalist_missing_cursor_fixture__/missing.cur"));
    assert(!mcm_menu_cursor());
    assert(!mcm_captured());

    assert(mcm_load_menu_cursor(path) == 1);
    HCURSOR cursor = mcm_menu_cursor();
    assert(cursor);
    ICONINFO info = {};
    assert(GetIconInfo(cursor, &info));
    assert(!info.fIcon);
    assert(info.xHotspot == 0 && info.yHotspot == 0);
    BITMAP bitmap = {};
    HBITMAP image = info.hbmColor ? info.hbmColor : info.hbmMask;
    assert(image);
    assert(GetObjectW(image, (int)sizeof bitmap, &bitmap) == (int)sizeof bitmap);
    assert(bitmap.bmWidth == 32);
    assert(bitmap.bmHeight == (info.hbmColor ? 32 : 64));
    if (info.hbmColor) assert(DeleteObject(info.hbmColor));
    if (info.hbmMask) assert(DeleteObject(info.hbmMask));

    assert(mcm_load_menu_cursor(path) == 1);
    assert(mcm_menu_cursor() == cursor);
    assert(!mcm_load_menu_cursor(NULL));
    assert(!mcm_load_menu_cursor("C:/__war_journalist_missing_cursor_fixture__/missing.cur"));
    assert(mcm_menu_cursor() == cursor);
    assert(!mcm_captured());
    mcm_release();
    assert(!mcm_captured());
    assert(mcm_menu_cursor() == cursor);
    assert(mcm_load_menu_cursor(path) == 1);
    assert(mcm_menu_cursor() == cursor);
    puts("Custom menu cursor loads at 32x32/hotspot 0,0; same path is cached; invalid loads and release preserve artwork. No window attached or input injected.");
    return 0;
}
'''


def test(build, asset=ASSET):
    build = build.resolve()
    asset = asset.resolve()
    assert asset.is_file(), 'Bundled Helldivers cursor asset missing'
    build.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'photo_input.cpp'
    harness = build / 'test_photo_cursor.cpp'
    harness.write_text(HARNESS.replace('__SOURCE__', source.as_posix()), encoding='utf-8')
    executable = build / 'test_photo_cursor.exe'
    compile_at(build, [
        f'cl /nologo /MT /EHsc /O2 /W4 /WX "{harness}" '
        f'/Fo"{build / "test_photo_cursor.obj"}" /Fe"{executable}" '
        '/link user32.lib gdi32.lib'
    ])
    subprocess.run([str(executable), str(asset)], check=True)
    result = {
        'passed': True,
        'exact_source': True,
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'asset_sha256': hashlib.sha256(asset.read_bytes()).hexdigest(),
        'cursor_size': [32, 32],
        'hotspot': [0, 0],
        'cached_identity': True,
        'invalid_load_preserves_cursor': True,
        'release_preserves_cursor': True,
        'windows_attached': False,
        'input_injected': False,
    }
    (build / 'photo-cursor-tests.json').write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path,
                        default=REPO / 'dist/review/helldivers-cursor/native-cursor')
    parser.add_argument('--asset', type=Path, default=ASSET)
    args = parser.parse_args()
    test(args.build, args.asset)

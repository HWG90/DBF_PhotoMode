"""Exercise the ownership adapter against the actual vendored ActionCam."""
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from run_lua import run

spec = importlib.util.spec_from_file_location('photo_compat_build', ROOT / 'freecam/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def quote(value):
    assert ']====]' not in value
    return '[====[' + value + ']====]'


if __name__ == '__main__':
    source = (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_text(encoding='utf-8')
    adapter = build.actioncam_compat_source()
    lll = (ROOT / 'freecam/lll.lua').read_text(encoding='utf-8')
    fixture = (ROOT / 'freecam/actioncam_compat_tests.lua').read_text(encoding='utf-8')
    run(('local ACTIONCAM_SOURCE=' + quote(source) + '\nlocal ADAPTER_SOURCE=' + quote(adapter) + '\nlocal LLL_SOURCE='+quote(lll)+'\n' + fixture).encode(), 'ActionCam-ownership-fixtures')

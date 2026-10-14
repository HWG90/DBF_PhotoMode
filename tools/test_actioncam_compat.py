"""Exercise the ownership adapter against the actual vendored ActionCam."""
import importlib.util
import argparse
import hashlib
import json
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
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,help='Also test the unchanged locally supplied original ActionCam 2.4 archive')
    args=parser.parse_args()
    source = (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_text(encoding='utf-8')
    adapter = build.actioncam_compat_source()
    lll = (ROOT / 'freecam/lll.lua').read_text(encoding='utf-8')
    fixture = (ROOT / 'freecam/actioncam_compat_tests.lua').read_text(encoding='utf-8')
    run(('local ACTIONCAM_SOURCE=' + quote(source) + '\nlocal ADAPTER_SOURCE=' + quote(adapter) + '\nlocal LLL_SOURCE='+quote(lll)+'\n' + fixture).encode(), 'ActionCam-ownership-fixtures')
    if args.archive:
        from actioncam_signatures import archive_source,generate
        original,archive_hash=archive_source(args.archive)
        expected=json.loads((ROOT/'freecam/vendor/actioncam-signatures.json').read_text())['supported']['10.32']
        assert archive_hash==expected['archive_sha256'],'ActionCam archive differs from the verified version'
        assert hashlib.sha256(original).hexdigest()==expected['source_sha256']
        assert generate(original,'2.4','10.32')['closures']==expected['closures'],'ActionCam 2.4 closure signatures changed'
        run(('local ACTIONCAM_SOURCE='+quote(original.decode())+'\nlocal ADAPTER_SOURCE='+quote(adapter)+'\nlocal LLL_SOURCE='+quote(lll)+'\n'+fixture).encode(),'ActionCam-2.4-ownership-fixtures')

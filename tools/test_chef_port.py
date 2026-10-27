"""Isolated PUC Lua 5.1 fixtures, including the pinned upstream Chef sandbox."""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SANDBOX_BLOB = '737728a5911189c3f02b13b21487ab8dbac97310'


def run(source, sandbox, shared_fixtures=True):
    from lupa.lua51 import LuaRuntime
    text = sandbox.read_text(encoding='utf-8').rstrip('\r\n') + '\n'
    raw = text.encode('utf-8')
    blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    assert blob == SANDBOX_BLOB, 'Use sandbox.lua from Chef commit 429516a243392bc724ce7b41ef2712cf4e5a0157'
    fixtures = ['chef/runtime_tests.lua', 'chef/camera_tests.lua', 'chef/controls_tests.lua', 'chef/simulation_tests.lua',
                'chef/shots_tests.lua', 'chef/bloom_tests.lua', 'chef/composition_tests.lua','chef/lights_tests.lua',
                'chef/director_tests.lua','chef/subject_tests.lua']
    if shared_fixtures:
        fixtures += ['steam_camera_tests.lua', 'steam_view_tests.lua', 'steam_composition_asset_tests.lua','steam_path_tests.lua',
                     'steam_subject_tests.lua','steam_subject_native_tests.lua','steam_pose_bank_tests.lua']
    results = []
    previous = Path.cwd()
    try:
        os.chdir(ROOT)
        for fixture in fixtures:
            lua = LuaRuntime()
            assert lua.eval('_VERSION') == 'Lua 5.1' and lua.eval('jit == nil and package.loaded.ffi == nil')
            lua.globals().CHEF_SOURCE = source.decode('utf-8')
            lua.globals().SANDBOX_SOURCE = text
            lua.execute((ROOT / 'freecam/chef/test_support.lua').read_text(encoding='utf-8'))
            lua.execute((ROOT / 'freecam' / fixture).read_text(encoding='utf-8'))
            results.append({'fixture': fixture, 'passed': True})
    finally:
        os.chdir(previous)
    return {'fixtures': results, 'sandbox_git_blob': blob, 'live_game_verified': False}


if __name__ == '__main__':
    from build_chef_candidate import bundle
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sandbox', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(run(bundle(), args.sandbox), indent=2))

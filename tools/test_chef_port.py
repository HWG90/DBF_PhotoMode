"""Isolated PUC Lua 5.1 fixtures, run inside a real upstream Chef sandbox.lua.

The sandbox is the loader's own file (pass one per --sandbox); the loader's chef
helpers are modelled by freecam/chef/test_support.lua, with and without the
Chef 1.4.0 services. Nothing here runs the game or proves in-game behaviour.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# git blob of src/chef_loader/sandbox.lua -> the Chef Shared Loader tags that ship it.
SANDBOX_BLOBS = {
    '737728a5911189c3f02b13b21487ab8dbac97310': '1.2.3/1.2.4',
    '7876938935a5054ad774ee5a021e3850740008e6': '1.3.0/1.3.1',
    'ebdcfafc5d6d4914fbf6e240f449bf8b324b3e3f': '1.4.0',
}
FIXTURES = ['chef/runtime_tests.lua', 'chef/camera_tests.lua', 'chef/controls_tests.lua', 'chef/simulation_tests.lua',
            'chef/shots_tests.lua', 'chef/bloom_tests.lua', 'chef/composition_tests.lua', 'chef/lights_tests.lua',
            'chef/director_tests.lua', 'chef/subject_tests.lua', 'chef/parity_tests.lua', 'chef/loader_features_tests.lua']
SHARED_FIXTURES = ['steam_camera_tests.lua', 'steam_view_tests.lua', 'steam_composition_asset_tests.lua', 'steam_path_tests.lua',
                   'steam_subject_tests.lua', 'steam_subject_native_tests.lua', 'steam_pose_bank_tests.lua']


def sandbox_text(sandbox):
    text = sandbox.read_text(encoding='utf-8').rstrip('\r\n') + '\n'
    raw = text.encode('utf-8')
    blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    assert blob in SANDBOX_BLOBS, 'Unknown Chef sandbox.lua blob %s; known: %s' % (blob, ', '.join(
        '%s (%s)' % (v, k[:8]) for k, v in SANDBOX_BLOBS.items()))
    return text, blob


def run(source, sandbox, shared_fixtures=True):
    from lupa.lua51 import LuaRuntime
    text, blob = sandbox_text(sandbox)
    fixtures = FIXTURES + (SHARED_FIXTURES if shared_fixtures else [])
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
    return {'fixtures': results, 'sandbox_git_blob': blob, 'sandbox_chef_versions': SANDBOX_BLOBS[blob],
            'live_game_verified': False}


if __name__ == '__main__':
    from build_chef_candidate import bundle
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sandbox', type=Path, required=True, action='append',
                        help='Chef src/chef_loader/sandbox.lua; repeat to run against several loader versions')
    args = parser.parse_args()
    source = bundle()
    print(json.dumps([run(source, path) for path in args.sandbox], indent=2))

"""Run the portable camera/input/controller contracts in actual Lua 5.1."""
from pathlib import Path
import argparse
import json
import os

ROOT=Path(__file__).resolve().parents[1]
FIXTURES=('steam_camera_tests.lua','steam_input_tests.lua','steam_path_tests.lua','steam_simulation_tests.lua','steam_runtime_tests.lua','steam_lighting_tests.lua','steam_view_tests.lua',
          'steam_capture_tests.lua','steam_capture_runtime_tests.lua','steam_entry_tests.lua','steam_composition_asset_tests.lua','steam_grain_tests.lua','steam_overlay_tests.lua','steam_overlay_runtime_tests.lua',
          'steam_bloom_tests.lua','steam_bloom_runtime_tests.lua',
          'steam_pose_bank_tests.lua','steam_subject_tests.lua','steam_subject_native_tests.lua','steam_subject_runtime_tests.lua')
FEATURE_FIXTURES=('cinema_camera_tests.lua','cinema_controls_tests.lua','cinema_hint_tests.lua',
                  'saved_camera_tests.lua','director_tests.lua','photo_lights_tests.lua','photo_light_presets_tests.lua',
                  'subject_poses_tests.lua','ragdoll_pause_tests.lua','photo_menu_cache_tests.lua','photo_light_gizmos_tests.lua')

def run():
    from lupa.lua51 import LuaRuntime
    previous=Path.cwd()
    rows=[]
    try:
        os.chdir(ROOT)
        for fixture in FIXTURES:
            lua=LuaRuntime()
            assert lua.eval('_VERSION')=='Lua 5.1' and lua.eval('jit==nil and package.loaded.ffi==nil')
            lua.execute((ROOT/'freecam'/fixture).read_text(encoding='utf-8'))
            rows.append({'fixture':fixture,'passed':True,'runtime':'Lua 5.1'})
        # These exercise shared feature models/controllers using mock native
        # adapters. Passing proves VM compatibility, never a live backend.
        os.chdir(ROOT.parent/'DBF-MCM')
        for fixture in FEATURE_FIXTURES:
            lua=LuaRuntime()
            lua.globals().DBF_PHOTO_TEST_ROOT=(ROOT/'freecam').as_posix()+'/'
            lua.globals().DBF_PHOTO_REPO_ROOT=ROOT.as_posix()+'/'
            lua.execute((ROOT/'freecam'/fixture).read_text(encoding='utf-8'))
            rows.append({'fixture':fixture,'passed':True,'runtime':'Lua 5.1','native_adapter':'fixture only'})
    finally:
        os.chdir(previous)
    return {'passed':True,'fixtures':rows,'live_game_verified':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt',type=Path)
    args=parser.parse_args()
    result=run()
    if args.receipt:
        args.receipt.parent.mkdir(parents=True,exist_ok=True)
        args.receipt.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

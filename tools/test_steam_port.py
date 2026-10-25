"""Run the portable camera/input/controller contracts in actual Lua 5.1."""
from pathlib import Path
import argparse
import json
import os
import re

ROOT=Path(__file__).resolve().parents[1]
FIXTURES=('steam_control_updates_tests.lua','steam_director_runtime_tests.lua','steam_input_refusal_tests.lua','steam_render_flags_tests.lua','steam_bookmark_runtime_tests.lua','steam_camera_tests.lua','steam_input_tests.lua','steam_path_tests.lua','steam_simulation_tests.lua','steam_runtime_tests.lua','steam_lighting_tests.lua','steam_view_tests.lua',
          'steam_capture_tests.lua','linux_capture_tests.lua','steam_capture_runtime_tests.lua','steam_entry_tests.lua','steam_composition_asset_tests.lua','steam_grain_tests.lua','steam_overlay_tests.lua','steam_overlay_runtime_tests.lua',
          'steam_bloom_tests.lua','steam_bloom_runtime_tests.lua',
          'steam_pose_bank_tests.lua','steam_subject_tests.lua','steam_subject_native_tests.lua','steam_subject_runtime_tests.lua')
FIXTURES+=('steam_scene_sdr_tests.lua','steam_scene_resources_tests.lua','steam_scene_tests.lua','steam_focus_sampler_tests.lua','steam_scene_overlay_tests.lua','steam_required_input_tests.lua','steam_hud_tests.lua','steam_hud_runtime_tests.lua','steam_handycam_tests.lua')

FIXTURES+=('steam_engine_capture_tests.lua','steam_native_diagnostics_tests.lua','steam_bindings_tests.lua','steam_engine_input_tests.lua','steam_native_library_tests.lua','steam_pick_tests.lua','steam_handoff_runtime_tests.lua','steam_native_lens_runtime_tests.lua','steam_ragdoll_runtime_tests.lua','steam_hover_pause_tests.lua','steam_hover_runtime_tests.lua','steam_hover_backend_tests.lua')

FEATURE_FIXTURES=('cinema_camera_tests.lua','cinema_controls_tests.lua','cinema_hint_tests.lua',
                  'saved_camera_tests.lua','director_tests.lua','photo_lights_tests.lua','photo_light_presets_tests.lua',
                  'subject_poses_tests.lua','subject_pose_cape_tests.lua','ragdoll_pause_tests.lua','photo_menu_cache_tests.lua','photo_light_gizmos_tests.lua')

def run():
    from lupa.lua51 import LuaRuntime
    previous=Path.cwd()
    rows=[]
    try:
        os.chdir(ROOT)
        # Compare runtime paths against the retained asset manifest, not a
        # fixture that duplicates an assumed namespace.
        manifest=json.loads((ROOT/'freecam/assets/shaders/manifest.json').read_text())
        materials={row['id']:row['material'] for row in manifest['overlays']}
        composition=LuaRuntime().execute((ROOT/'freecam/composition.lua').read_text())
        catalog=composition.shaders
        prefix=re.search(r"material='([^']+)'\.\.name",(ROOT/'freecam/steam_overlay.lua').read_text())[1]
        assert len(materials)==40
        for index in range(2,len(catalog)+1):
            name=catalog[index];assert prefix+name==materials[name],name
        # Replacement identities must name the exact maintained HLSL content.
        import hashlib
        # Aligned builds salt the content ID so they never alias the
        # withdrawn decorative-v2-r3 resources.
        replacements=dict(composition.shader_materials.items())
        import generate_decorative_v2 as generator
        assert set(replacements)<=set(catalog.values())-{''}
        assert set(replacements)==set(generator.PATTERNS)|set(generator.SMOOTH),'Map every generated replacement'
        for name,path in replacements.items():
            source=(ROOT/'freecam/assets/decorative-v2'/f'{name}.hlsl').read_bytes()
            content=hashlib.sha256(source+b':aligned-v2').hexdigest()[:16]
            assert path==f'mods/dbf_photo/materials/decorative_{name}_{content}'
        rows.append({'fixture':'decorative_asset_path_closure','passed':True,'materials':40})
        # lll/ pins the last Lua 5.1 loader (R35 insert-fix.2); the input
        # service the fixtures load must stay byte-identical to it.
        service=ROOT/'lll/src/steam/input_service.lua'
        if service.is_file():
            assert (ROOT/'freecam/test_reference/input_service_r35.lua').read_bytes()==service.read_bytes(),'Input service reference differs from lll/'
            rows.append({'fixture':'lll_r35_input_service_reference','passed':True})
        else:
            rows.append({'fixture':'lll_r35_input_service_reference','passed':None,'skipped':'lll submodule not checked out'})
        for fixture in FIXTURES:
            lua=LuaRuntime()
            assert lua.eval('_VERSION')=='Lua 5.1' and lua.eval('jit==nil and package.loaded.ffi==nil')
            lua.execute((ROOT/'freecam'/fixture).read_text(encoding='utf-8'))
            rows.append({'fixture':fixture,'passed':True,'runtime':'Lua 5.1'})
        # These exercise shared feature models/controllers using mock native
        # adapters. Passing proves VM compatibility, never a live backend.
        mcm=ROOT.parent/'DBF-MCM'
        if not mcm.is_dir():
            # The shared MCM checkout can be an unmounted link; record the gap.
            rows.extend({'fixture':fixture,'passed':None,'skipped':'DBF-MCM checkout unavailable'}for fixture in FEATURE_FIXTURES)
            return {'passed':True,'fixtures':rows,'live_game_verified':False,'feature_fixtures_skipped':len(FEATURE_FIXTURES)}
        (ROOT/'dist/validation').mkdir(parents=True,exist_ok=True)  # Light presets write a fixture file here.
        os.chdir(mcm)
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

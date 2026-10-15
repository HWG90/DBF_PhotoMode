"""Run isolated release fixtures with LuaJIT; never attaches to the game.

Usage: python tools/run_tests.py --mcm-root ../DBF-MCM --native
HD2_LUA51_DLL or --lua-dll selects the Lua 5.1/LuaJIT library.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = (
    'actioncam_compat_tests.lua', 'actioncam_controls_tests.lua',
    'cinema_camera_tests.lua', 'cinema_controls_tests.lua', 'cinema_hint_tests.lua', 'tests.lua', 'look_tests.lua', 'simulation_tests.lua', 'simulation_controls_tests.lua', 'hover_pause_tests.lua', 'hover_pause_backend_tests.lua', 'hover_pause_integration_tests.lua', 'input_release_tests.lua', 'studio_tests.lua',
    'menu_tests.lua', 'resize_menu_tests.lua', 'photo_menu_interaction_tests.lua', 'slider_scrub_tests.lua', 'control_legend_tests.lua', 'cursor_confinement_tests.lua',
    'numeric_menu_tests.lua', 'numeric_blur_tests.lua', 'panel_lifecycle_tests.lua', 'input_lease_recovery_tests.lua', 'controller_input_recovery_tests.lua', 'close_cleanup_tests.lua', 'photo_runtime_lifecycle_tests.lua', 'menu_reopen_tests.lua', 'postfx_tests.lua',
    'native_lens_tests.lua', 'animation_state_tests.lua', 'chat_context_tests.lua', 'subject_tests.lua','subject_poses_tests.lua','subject_pose_cape_tests.lua','subject_poses_controls_tests.lua', 'subject_backend_tests.lua', 'director_tests.lua', 'director_controls_tests.lua', 'ai_control_tests.lua', 'ai_controls_integration_tests.lua', 'focus_sampler_tests.lua', 'autofocus_controls_tests.lua', 'photo_lights_tests.lua','photo_light_presets_tests.lua','photo_light_gizmos_tests.lua','light_tools_controls_tests.lua', 'crest_runtime_tests.lua', 'saved_camera_tests.lua', 'shader_runtime_tests.lua', 'screenshot_tests.lua',
    'screenshot_backend_tests.lua', 'stable_gates_tests.lua', 'mdl_tests.lua', 'depth_resource_tests.lua', 'dof_overlay_tests.lua', 'dof_runtime_tests.lua', 'shader_template_guard_tests.lua', 'dof_controls_tests.lua', 'scene_overlay_tests.lua', 'scene_runtime_tests.lua', 'scene_dof_overlay_tests.lua',
)


def lua_string(value):
    equals = '='
    while ']'+equals+']' in value:
        equals += '='
    return '['+equals+'['+value+']'+equals+']'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mcm-root', type=Path, default=Path(os.environ.get('DBF_MCM_TEST_ROOT', str(ROOT.parent/'DBF-MCM'))))
    parser.add_argument('--lua-dll', type=Path)
    parser.add_argument('--fixture', action='append', choices=FIXTURES)
    parser.add_argument('--native', action='store_true', help='Also run the built standalone PNG converter fixtures')
    parser.add_argument('--native-build', type=Path, help='Use an explicitly named native converter build for --native')
    parser.add_argument('--receipt', type=Path, default=ROOT/'dist/validation/release-fixtures.json')
    args = parser.parse_args()
    mcm = args.mcm_root.resolve()
    if not (mcm/'src/core.lua').is_file():
        parser.error('MCM source checkout missing src/core.lua; use --mcm-root or DBF_MCM_TEST_ROOT')
    if args.lua_dll:
        os.environ['HD2_LUA51_DLL'] = str(args.lua_dll.resolve())
    sys.path.insert(0, str(ROOT))
    import run_lua
    if not run_lua.DLL.is_file():
        parser.error('LuaJIT library missing; use --lua-dll or HD2_LUA51_DLL')
    (ROOT/'dist/validation').mkdir(parents=True, exist_ok=True)
    original_cwd = Path.cwd()
    bootstrap = ('DBF_PHOTO_TEST_ROOT='+lua_string((ROOT/'freecam').as_posix()+'/')+'\n'
                 'DBF_PHOTO_REPO_ROOT='+lua_string(ROOT.as_posix()+'/')+'\n').encode()
    results = []
    try:
        # The fixtures deliberately exercise the owning MCM core through its
        # relative dependency imports. Photo modules use the explicit test root.
        os.chdir(mcm)
        for name in args.fixture or FIXTURES:
            path = ROOT/'freecam'/name
            source = path.read_bytes()
            if name=='actioncam_compat_tests.lua':
                from freecam.build import actioncam_compat_source
                source=('local ACTIONCAM_SOURCE='+lua_string((ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_text(encoding='utf-8'))+'\nlocal ADAPTER_SOURCE='+lua_string(actioncam_compat_source())+'\nlocal LLL_SOURCE='+lua_string((ROOT/'freecam/lll.lua').read_text(encoding='utf-8'))+'\n').encode()+source
            started = time.monotonic()
            result = {'fixture': name, 'sha256': hashlib.sha256(source).hexdigest()}
            try:
                run_lua.run(bootstrap+source, name)
                result['passed'] = True
            except Exception as error:
                result.update(passed=False, error=str(error))
                print('FAIL '+name+': '+str(error), file=sys.stderr)
            result['duration_ms'] = round((time.monotonic()-started)*1000, 2)
            results.append(result)
    finally:
        os.chdir(original_cwd)
    if args.native:
        test = ROOT/'freecam/native/test_photo_capture.py'
        native_command = [sys.executable, str(test)]
        if args.native_build:
            native_command.extend(['--build', str(args.native_build.resolve())])
        completed = subprocess.run(native_command, cwd=ROOT, check=False)
        results.append({'fixture': 'native/test_photo_capture.py', 'sha256': hashlib.sha256(test.read_bytes()).hexdigest(),
                        'passed': completed.returncode == 0, 'exit_code': completed.returncode})
    passed = all(result['passed'] for result in results)
    receipt = {'version': (ROOT/'VERSION').read_text().strip(), 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
               'passed': passed, 'isolated_tests_only': True, 'game_process_accessed': False,
               'mcm_core_sha256': hashlib.sha256((mcm/'src/core.lua').read_bytes()).hexdigest(),
               'source_modules_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                        for path in sorted((ROOT/'freecam').glob('*.lua')) if not path.name.endswith('_tests.lua') and path.name != 'tests.lua'},
               'results': results}
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(f'{sum(result["passed"] for result in results)}/{len(results)} fixture groups passed; receipt: {args.receipt}')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

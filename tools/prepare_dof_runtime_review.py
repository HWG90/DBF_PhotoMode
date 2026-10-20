"""Build an isolated 0.6-based LLL DoF review; never install or publish it."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'dist/release-source-0.6'
OUT = ROOT / 'dist/releases/photo-dof-runtime-review'
SOURCE = OUT / 'Source'
INSTALLED = Path('C:/Users/david/AppData/Local/LLL/Helldivers2/Mods/dbf_freecam')
CORE_ORDER = ROOT / 'dist/releases/photo-dof-core-order-review/War-Journalist-DoF-Assets-Core-Order-Review.zip'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def zip_checked(target, files):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, body in sorted(files.items()):
            archive.writestr(name, body)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None and len(archive.namelist()) == len(files) == len(set(archive.namelist()))
        for name, body in files.items():
            assert archive.read(name) == body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true', help='Refresh this explicitly named review output in place; never installs')
    parser.add_argument('--dof-gpu', type=Path, help='Use the validated composition GPU payload')
    args = parser.parse_args()
    assert not OUT.exists() or args.refresh, 'Preserve the named review output; use --refresh only for an authorized revision'
    assert subprocess.check_output(['git', '-C', str(BASE), 'status', '--porcelain'], text=True) == ''
    base_commit = subprocess.check_output(['git', '-C', str(BASE), 'rev-parse', 'HEAD'], text=True).strip()
    selected = subprocess.check_output(['git', '-C', str(BASE), 'ls-files', 'freecam', 'tools/lua_archive.py', 'tools/photo_assets.py', 'run_lua.py', 'VERSION', 'AGENTS.md'], text=True).splitlines()
    for name in selected:
        write(SOURCE / name, (BASE / name).read_bytes())
    # Own the review's runner/fixtures without editing the preserved release.
    write(SOURCE / 'tools/run_tests.py', (ROOT / 'tools/run_tests.py').read_bytes())
    for name in ('controller.lua', 'photo_runtime.lua', 'depth_resource.lua', 'dof_overlay.lua', 'shader_template_guard.lua',
                 'stable_gates_tests.lua', 'dof_runtime_tests.lua', 'depth_resource_tests.lua', 'dof_overlay_tests.lua', 'shader_template_guard_tests.lua'):
        write(SOURCE / 'freecam' / name, (ROOT / 'freecam' / name).read_bytes())
    options = (SOURCE / 'freecam/photo_options.lua').read_text()
    trio = " toggle('dof','Depth of field'),slider('focus_distance','Focus distance (m)',0.1,200,0.1),slider('aperture','Aperture (f-stop)',1.2,22,0.1),\n"
    assert options.count(trio) == 1
    options = options.replace(trio, '')
    anchor = " slider('fov','Vertical field of view (0 = gameplay)',0,120,1),slider('roll','Camera tilt (degrees)',-180,180,0.01),\n"
    assert options.count(anchor) == 1
    options = options.replace(anchor, anchor + trio)
    options = options.replace("label='Focus/f-stop unavailable in this release'", "label='Depth-aware focus and aperture'")
    options = options.replace("label='Known issues: focus/f-stop and scene shaders disabled; exposure/contrast/saturation unavailable.'", "label='Exposure, contrast and saturation unavailable.'")
    write(SOURCE / 'freecam/photo_options.lua', options.encode())
    # Port only the candidate hook, retaining the self-contained 0.6 payload builder.
    builder = (SOURCE / 'freecam/build.py').read_text()
    candidate_builder = (ROOT / 'freecam/build.py').read_text()
    builder = builder.replace('def patch(source):', 'def patch(source,dof_candidate=False):', 1)
    builder = builder.replace('local DBF_PHOTO_RUNTIME=(function()', '__PHOTO_DOF_CANDIDATE__\nlocal DBF_PHOTO_RUNTIME=(function()', 1)
    signature = 'end)().new(sr,DBF_PHOTO_LENS,DBF_PHOTO_COMPOSITION,DBF_PHOTO_POSTFX,log,DBF_PHOTO_HUD,DBF_PHOTO_PROFILE)'
    assert builder.count(signature) == 1
    builder = builder.replace(signature, signature[:-1] + '__PHOTO_DOF_ARGUMENT__)')
    start = candidate_builder.index("    candidate=''\n")
    end = candidate_builder.index('    for token,filename', start)
    candidate_hook = candidate_builder[start:end]
    insertion = builder.index('    for token,filename')
    builder = builder[:insertion] + candidate_hook + builder[insertion:]
    replace_anchor = "    replace('local function bindings_step()', 'local function legacy_bindings_step()')\n"
    assert builder.count(replace_anchor) == 1
    builder = builder.replace(replace_anchor, replace_anchor + "    source,count=re.subn(r'(CFG\\.LOG_EVERY\\s*=\\s*)1\\.0\\b',r'\\g<1>30.0',source,count=1)\n    if count!=1:raise ValueError('ActionCam diagnostic interval contract changed')\n")
    write(SOURCE / 'freecam/build.py', builder.encode())
    sys.path.insert(0, str(SOURCE / 'tools'))
    build = load('dof_review_build', SOURCE / 'freecam/build.py')
    identity = json.loads((SOURCE / 'freecam/vendor/PROVENANCE.json').read_text())
    foundation = (SOURCE / 'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
    assert sha(foundation) == identity['actioncam_source_sha256']
    generated = build.patch(foundation.decode(), dof_candidate=True).encode()
    build.compile_lua(generated, '0.6-DoF-LLL-review-runtime')
    write(OUT / 'ActionCam-Freecam.lua', generated)
    modules = ('photo_options.lua', 'lens.lua', 'composition.lua', 'postfx.lua', 'photo_runtime.lua', 'hud.lua', 'render_profile.lua', 'camera_profile.lua',
        'saved_camera.lua', 'photo_menu.lua', 'controller.lua', 'depth_resource.lua', 'dof_overlay.lua', 'shader_template_guard.lua')
    provenance = {'source_archive': 'ActionCam 2.3.1 (0.6 vendored source)', 'source_sha256': identity['actioncam_archive_sha256'],
        'base_source_commit': base_commit, 'candidate': True, 'dof_candidate_preview': True, 'version': '0.6-dof-review',
        'photo_modules_sha256': {name: sha((SOURCE / 'freecam' / name).read_bytes()) for name in modules},
        'deployment': 'not installed', 'live_validation': False}
    write(OUT / 'PROVENANCE.json', (json.dumps(provenance, indent=2) + '\n').encode())
    runtime = build.payload_files(OUT)
    # LLL host/lifecycle is the currently installed, restart-only adapter.
    runtime['main.lua'] = (INSTALLED / 'main.lua').read_bytes()
    runtime['config/defaults.cfg'] = b'{}\n'
    runtime['manifest.json'] = (json.dumps({'id': 'dbf_freecam', 'name': 'War Journalist', 'version': '0.6-dof-review', 'author': 'Goose',
        'lll': {'entry': 'main.lua', 'defaults': 'config/defaults.cfg', 'modules': sorted(name for name in runtime if name.startswith('src/') and name.endswith('.lua')),
                'restart_only': True, 'retain_until_exit': True}}, indent=2) + '\n').encode()
    runtime['INSTALL.txt'] = b'''War Journalist 0.6 DoF LLL review candidate

Copy dbf_freecam into %LOCALAPPDATA%/LLL/Helldivers2/Mods.
Import the included Arsenal asset ZIP, preserve its selected DoF assets option,
deploy normally, then restart the game normally. MCM is optional.
Enable only one Photo Mode provider and disable original ActionCam.

The Camera page places Depth of field, Focus distance and Aperture together.
Numeric lens controls enable only when renderer registration and scene depth
are ready. A successful custom draw disables the native DoF pass; failure keeps
native DoF available. Exiting Photo Mode restores original native settings.
Default focus is 5 metres and aperture is f/5.6; DoF starts disabled.

This review contains all 40 decorative overlays, private standalone menu/input,
PNG capture and the DoF candidate. It is not installed or live-verified.
Whole-addon reload is blocked because camera hooks require a normal restart.
'''
    for name, body in runtime.items():
        if name.endswith('.lua'):
            build.compile_lua(body, 'LLL-review-' + name)
    runtime['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(runtime.items())).encode()
    for name, body in runtime.items():
        write(OUT / 'Runtime/dbf_freecam' / name, body)
    # The working boot-order registry already references all 40 owned overlays.
    import photo_assets
    with zipfile.ZipFile(CORE_ORDER) as source:
        manifest = json.loads(source.read('manifest.json'))
        core = photo_assets.read_archive(source.read('Assets/ee6b1ba7e22d71ed.patch_0'), source.read('Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'))
        materials = photo_assets.read_archive(source.read('Assets/9ba626afa44a3aa3.patch_0'))
    assert len(core) == 2 and len(materials) == 1
    composition_receipt = None
    if args.dof_gpu:
        gpu_path = args.dof_gpu.resolve()
        composition_receipt = json.loads((gpu_path.parent / 'BUILD-RECEIPT.json').read_text())
        replacement = gpu_path.read_bytes()
        assert sha(replacement) == composition_receipt['sha256'] == 'b65ce7835b42666da7873815cea2f575260ce9f968f1ee5145f4ffdebf634119'
        assert composition_receipt['native_vertex_byte_identity'] and composition_receipt['all_native_metadata_byte_identity']
        at = next(index for index, row in enumerate(core) if row[1] == photo_assets.SHADER)
        current = core[at]
        assert current[0] == photo_assets.hash64('mods/dbf_photo/shaders/dof_local_depth_v1')
        assert sha(current[3]) == composition_receipt['original_candidate_sha256'] and len(current[3]) == len(replacement)
        core[at] = (current[0], current[1], current[2], replacement)
    registry = next(row for row in core if row[1] == photo_assets.GROUP)
    ids = set(photo_assets.registry_ids(registry[2]))
    owned = photo_assets.load_resources()
    shader_rows = [row for row in owned if row[1] == photo_assets.SHADER]
    material_rows = [row for row in owned if row[1] == photo_assets.MATERIAL]
    assert len(shader_rows) == len(material_rows) == 40 and all(row[0] in ids for row in shader_rows) and len(ids) == 316
    expected_core, expected_materials = core + shader_rows, materials + material_rows
    core_cpu, core_gpu = photo_assets.archive_rows(expected_core)
    material_cpu, material_gpu = photo_assets.archive_rows(expected_materials)
    assert sorted(photo_assets.read_archive(core_cpu, core_gpu)) == sorted(expected_core)
    assert sorted(photo_assets.read_archive(material_cpu, material_gpu)) == sorted(expected_materials) and not material_gpu
    assert manifest['Guid'] == 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
    assert manifest['Options'] == [{'Name': 'DoF shader assets and registry', 'Include': ['Assets']}]
    manifest['Name'] = 'War Journalist DoF Assets - Self-Contained Core Order Review'
    manifest['Description'] = 'Review candidate with all 40 decorative overlays and DoF assets. All shader libraries share the renderer core archive with their exact 316-ID registry. Live controls require validation.'
    asset_files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(), 'INSTALL.txt': runtime['INSTALL.txt']}
    for name, cpu, gpu in [('ee6b1ba7e22d71ed.patch_0', core_cpu, core_gpu), ('9ba626afa44a3aa3.patch_0', material_cpu, material_gpu)]:
        for suffix, body in [('', cpu), ('.gpu_resources', gpu), ('.stream', b'')]:
            asset_files['Assets/' + name + suffix] = body
    asset_files['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(asset_files.items())).encode()
    asset_target = OUT / 'War-Journalist-DoF-Assets-Self-Contained-Core-Order-Review.zip'
    zip_checked(asset_target, asset_files)
    for name, body in asset_files.items():
        write(OUT / 'Asset-Package' / name, body)
    combined = {'dbf_freecam/' + name: body for name, body in runtime.items()}
    combined['Arsenal/' + asset_target.name] = asset_target.read_bytes()
    combined['INSTALL.txt'] = runtime['INSTALL.txt']
    combined['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(combined.items())).encode()
    target = OUT / 'War-Journalist-0.6-DoF-LLL-Review.zip'
    zip_checked(target, combined)
    findings = {'base_source_commit': base_commit, 'base_worktree_unchanged': True, 'installed_version': json.loads((INSTALLED / 'manifest.json').read_text())['version'],
        'main_lua_preserved_sha256': sha(runtime['main.lua']), 'generated_runtime_sha256': sha(generated),
        'ports': ['Candidate controller/runtime capability gates', 'Depth resource getter/binder', 'Renderer shader-template guard', 'Candidate factory wiring', 'DoF trio moved to Camera rows 3-5', '30-second diagnostic interval'],
        'preserved': ['0.6 private vendor services and native DLL hashes', 'MCM optional input', 'Current restart-only LLL lifecycle', '0.6 menu numeric editing/resizing/dropdowns', 'Simulation controls', 'Saved camera', 'PNG capture', 'All 40 decorative assets'],
        'focus_default_m': 5, 'aperture_default_f_stop': 5.6, 'dof_default': False, 'scene_depth_calibration_default': False,
        'ui': 'DoF/focus/aperture visible together at Camera rows 3-5; authoritative disabled-state gates remain until candidate readiness',
        'lifecycle': 'Whole LLL addon replacement needs normal restart. Existing controller can be replaced only through an explicitly scoped reversible live bridge, after releasing current provider/menu/effects; no automatic hot reload.',
        'asset_counts': {'core_shader_libraries': 41, 'core_registry': 1, 'shared_materials': 41, 'registry_ids': 316},
        'registry_exact_core_order_sha256': sha(registry[2]), 'asset_guid': manifest['Guid'], 'asset_option': manifest['Options'][0]['Name'],
        'artifact': target.name, 'artifact_sha256': sha(target.read_bytes()), 'asset_zip': asset_target.name, 'asset_zip_sha256': sha(asset_target.read_bytes()),
        'runtime_files_sha256': {name: sha(body) for name, body in sorted(runtime.items())},
        'validation': 'Generated/runtime Lua compiled; vendored hashes checked; assets roundtripped and registry closure checked; both ZIP CRCs and exact entries verified',
        'composition_gpu': composition_receipt,
        'install_mapping': {'runtime_source': str(OUT / 'Runtime/dbf_freecam'), 'runtime_target': str(INSTALLED),
            'runtime_entry': 'main.lua', 'runtime_manifest': 'manifest.json',
            'arsenal_zip': str(asset_target), 'arsenal_guid': manifest['Guid'], 'arsenal_option': manifest['Options'][0]['Name'],
            'assets_source': str(OUT / 'Asset-Package/Assets'), 'restart_required': True, 'configuration_changes_required': False},
        'installed_target_files': {str(INSTALLED / name): {'candidate_sha256': sha(body),
            'currently_installed_sha256': sha((INSTALLED / name).read_bytes()) if (INSTALLED / name).is_file() else None} for name, body in sorted(runtime.items())},
        'installed': False, 'live_controls_verified': False, 'completed_fix': False}
    write(OUT / 'INTEGRATION-RECEIPT.json', (json.dumps(findings, indent=2) + '\n').encode())
    print(json.dumps({key: findings[key] for key in ['artifact', 'artifact_sha256', 'asset_zip', 'asset_zip_sha256', 'generated_runtime_sha256', 'asset_counts', 'installed']}, indent=2))


if __name__ == '__main__':
    main()

"""Package current Photo precision controls with the unchanged explicit fallback."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist/releases/photo-focus-precision-review'
INSTALLED = Path('C:/Users/david/AppData/Local/LLL/Helldivers2/Mods/dbf_freecam')
ASSET_ZIP = ROOT / 'dist/releases/photo-dof-runtime-review/War-Journalist-DoF-Assets-Self-Contained-Core-Order-Review.zip'
EXPECTED_BEFORE = '291146b261b2299bbb312cd283f686ffc504e2b3a37022f228d508208e123fbb'
EXPECTED_AFTER = 'fdc755143ef35a2772afa3c7ef794287494e32de1582fc15c836e480169a96db'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh',action='store_true',help='Refresh this explicitly named precision review output; never installs')
    args=parser.parse_args()
    assert not OUT.exists()or args.refresh, 'Preserve an existing named review output'
    checks = json.loads((ROOT / 'dist/validation/dof-focus-precision-blur-fixtures.json').read_text())
    assert checks['passed'] and len(checks['results']) == 22
    assert sha((INSTALLED / 'src/actioncam.lua').read_bytes()) == EXPECTED_BEFORE
    sys.path.insert(0, str(ROOT / 'tools'))
    spec = importlib.util.spec_from_file_location('precision_photo_build', ROOT / 'freecam/build.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    source = (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
    vendor = json.loads((ROOT / 'freecam/vendor/PROVENANCE.json').read_text())
    assert sha(source) == vendor['actioncam_source_sha256']
    # Explicitly preserve the installed fallback; ordinary builds still disable it.
    generated = build.patch(source.decode(), dof_candidate=True).encode()
    assert sha(generated) == EXPECTED_AFTER
    build.compile_lua(generated, 'focus-precision-LLL-runtime')
    write(OUT / 'ActionCam-Freecam.lua', generated)
    module_names = ('controller.lua', 'photo_options.lua', 'photo_menu.lua', 'photo_runtime.lua', 'depth_resource.lua',
        'dof_overlay.lua', 'shader_template_guard.lua', 'lens.lua', 'postfx.lua', 'render_profile.lua', 'camera_profile.lua',
        'composition.lua', 'hud.lua', 'saved_camera.lua', 'look.lua', 'simulation.lua', 'simulation_backend.lua')
    provenance = {'base_source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'source_archive': 'ActionCam 2.3.1 (owned vendored source)', 'source_sha256': vendor['actioncam_archive_sha256'],
        'source_modules_sha256': {name: sha((ROOT / 'freecam' / name).read_bytes()) for name in module_names},
        'candidate': True, 'dof_candidate_preview': True, 'ordinary_build_custom_dof_default': False,
        'fallback_status': 'Existing working shader fallback preserved; visual quality remains under review; native camera DoF preferred',
        'focus_step_m': .01, 'focus_fine_step_m': .001, 'focus_fine_modifier': 'Shift+A/D inside numeric editor',
        'commit_on_blur': True, 'escape_cancels': True, 'isolated_fixture_groups_passed': 22,
        'runtime_before_sha256': EXPECTED_BEFORE, 'runtime_after_sha256': EXPECTED_AFTER,
        'shader_gpu_sha256': 'b65ce7835b42666da7873815cea2f575260ce9f968f1ee5145f4ffdebf634119',
        'deployment': 'not installed', 'precision_live_verified': False, 'completed_dof_fix': False}
    write(OUT / 'PROVENANCE.json', (json.dumps(provenance, indent=2) + '\n').encode())
    runtime = build.payload_files(OUT)
    # The 0.6 history import normalized this unchanged host module's line endings.
    # Preserve installed byte identity when its source text is exactly equivalent.
    previous_standalone=(INSTALLED/'src/standalone.lua').read_bytes()
    if runtime['src/standalone.lua'].replace(b'\r\n',b'\n')==previous_standalone.replace(b'\r\n',b'\n'):
        runtime['src/standalone.lua']=previous_standalone
    runtime['main.lua'] = (INSTALLED / 'main.lua').read_bytes()
    runtime['config/defaults.cfg'] = b'{}\n'
    manifest = json.loads((INSTALLED / 'manifest.json').read_text())
    manifest['version'] = '0.6-focus-precision-review'
    manifest['lll']['modules'] = sorted(name for name in runtime if name.startswith('src/') and name.endswith('.lua'))
    assert manifest['lll']['restart_only'] and manifest['lll']['retain_until_exit']
    runtime['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    runtime['SOURCE-PROVENANCE.json'] = runtime['PROVENANCE.json']
    runtime['INSTALL.txt'] = b'''War Journalist - Focus Precision LLL review

Copy dbf_freecam into %LOCALAPPDATA%/LLL/Helldivers2/Mods using the included
installation map. Preserve existing screenshots and saved settings. The addon
retains camera hooks until the process exits; a normal game restart is required.
MCM is optional. If MCM is active, its matching opt-in numeric input patch is
supplied separately by the current task.

Focus adjusts in 0.01 m steps. Enter the numeric editor, then hold Shift+A/D for
0.001 m fine adjustment. The focus readout shows three decimal places and typed
values retain millimetre precision. Leaving a numeric field by clicking outside,
changing page/row or switching camera focus commits a valid value. Escape cancels.
Invalid pending values block focus transfer rather than silently saving.

The already working shader fallback is explicitly retained in this review.
Native camera DoF is preferred; fallback visual quality remains under review.
This is not a final DoF fix and does not add scene exposure/contrast/saturation.
The included Arsenal ZIP preserves the exact successful 41-library/41-material
asset bytes, GUID and selected option. Already installed identical assets need
no replacement. For a fresh install, import that ZIP and use its existing option.
Choose one Photo Mode provider and disable original ActionCam.

22 isolated fixture groups passed. Precision changes still need an in-game check.
No saved preferences, screenshots, logs or unrelated component changes are included.
'''
    for name, body in runtime.items():
        if name.endswith('.lua'):
            build.compile_lua(body, 'focus-precision-' + name)
    runtime['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(runtime.items())).encode()
    install_map = {}
    for name, body in sorted(runtime.items()):
        destination = INSTALLED / name
        previous = destination.read_bytes() if destination.is_file() else None
        install_map[name] = {'source': 'Runtime/dbf_freecam/' + name, 'target': str(destination),
            'before_sha256': sha(previous) if previous is not None else None, 'after_sha256': sha(body), 'changed': previous != body}
        write(OUT / 'Runtime/dbf_freecam' / name, body)
    # Copy the successful composition package exactly; no shader or asset edits.
    asset_bytes = ASSET_ZIP.read_bytes()
    assert sha(asset_bytes) == 'ae688bb81171aee538934490252c39f0e4efb732c6e67908224fbdfe1cd21d59'
    import photo_assets
    with zipfile.ZipFile(ASSET_ZIP) as zipped:
        assert zipped.testzip() is None
        asset_manifest = json.loads(zipped.read('manifest.json'))
        assert asset_manifest['Guid'] == 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
        assert asset_manifest['Options'] == [{'Name': 'DoF shader assets and registry', 'Include': ['Assets']}]
        core = photo_assets.read_archive(zipped.read('Assets/ee6b1ba7e22d71ed.patch_0'), zipped.read('Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'))
        shared = photo_assets.read_archive(zipped.read('Assets/9ba626afa44a3aa3.patch_0'), zipped.read('Assets/9ba626afa44a3aa3.patch_0.gpu_resources'))
        assert len(core) == 42 and len(shared) == 41
        group = next(row for row in core if row[1] == photo_assets.GROUP)
        assert len(photo_assets.registry_ids(group[2])) == 316
        dof = next(row for row in core if row[0] == photo_assets.hash64('mods/dbf_photo/shaders/dof_local_depth_v1'))
        assert sha(dof[3]) == provenance['shader_gpu_sha256']
    write(OUT / ASSET_ZIP.name, asset_bytes)
    map_body = (json.dumps({'runtime_target': str(INSTALLED), 'changed_runtime_files': {name: item for name, item in install_map.items() if item['changed']},
        'all_runtime_files': install_map, 'asset_zip': ASSET_ZIP.name, 'asset_zip_sha256': sha(asset_bytes),
        'asset_guid': asset_manifest['Guid'], 'asset_option': asset_manifest['Options'][0]['Name'],
        'asset_bytes_unchanged': True, 'preferences_preserved': True, 'restart_required': True}, indent=2) + '\n').encode()
    write(OUT / 'INSTALL-MAP.json', map_body)
    package = {'dbf_freecam/' + name: body for name, body in runtime.items()}
    package['Arsenal/' + ASSET_ZIP.name] = asset_bytes
    package['INSTALL.txt'] = runtime['INSTALL.txt']
    package['INSTALL-MAP.json'] = map_body
    package['SOURCE-PROVENANCE.json'] = runtime['SOURCE-PROVENANCE.json']
    package['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(package.items())).encode()
    target = OUT / 'War-Journalist-Focus-Precision-LLL.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as zipped:
        for name, body in sorted(package.items()):
            zipped.writestr(name, body)
    with zipfile.ZipFile(target) as zipped:
        assert zipped.testzip() is None and len(zipped.namelist()) == len(package) == len(set(zipped.namelist()))
        for name, body in package.items():
            assert zipped.read(name) == body
    receipt = {'artifact': target.name, 'artifact_sha256': sha(target.read_bytes()), 'artifact_bytes': target.stat().st_size,
        'zip_crc_and_exact_entries': True, 'runtime_before_sha256': EXPECTED_BEFORE, 'runtime_after_sha256': EXPECTED_AFTER,
        'asset_zip_sha256': sha(asset_bytes), 'asset_bytes_unchanged': True,
        'changed_runtime_files': [name for name, item in install_map.items() if item['changed']],
        'source_fixture_groups': 22, 'all_runtime_lua_compiled': True, 'source_provenance': provenance,
        'installed': False, 'preferences_modified': False, 'precision_live_verified': False, 'completed_dof_fix': False}
    write(OUT / 'PACKAGE-RECEIPT.json', (json.dumps(receipt, indent=2) + '\n').encode())
    print(json.dumps({key: receipt[key] for key in ('artifact', 'artifact_sha256', 'artifact_bytes', 'runtime_before_sha256', 'runtime_after_sha256', 'changed_runtime_files', 'asset_bytes_unchanged', 'installed')}, indent=2))


if __name__ == '__main__':
    main()

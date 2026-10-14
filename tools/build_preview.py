"""Build the self-contained 0.7 BSL/MDL preview from owned source/assets. Never installs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import photo_assets
import dof_assets

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def resources(output):
    folder = ROOT / 'freecam/assets/shaders'
    identity = json.loads((folder / 'preview-assets.json').read_text())
    bodies = {}
    for name, expected in identity['files'].items():
        assert Path(name).name == name
        body = (folder / name).read_bytes()
        assert hashlib.sha256(body).hexdigest() == expected, name
        bodies[name] = body
    originals = photo_assets.load_resources()
    core = [row for row in originals if row[1] == photo_assets.SHADER]
    shared = [row for row in originals if row[1] == photo_assets.MATERIAL]
    # The retained 315-entry group came from a whole HUD build. Its extra
    # registrations are not bundled here. Start with the exact stock registry
    # and the 40 owned decorative libraries, then append our two scene pairs.
    group = photo_assets.registry_resource()[2]
    ids = list(photo_assets.registry_ids(group))
    assert len(ids) == 117
    for item in identity['effects']:
        shader_id = photo_assets.hash64(item['shader'])
        assert shader_id not in ids
        ids.append(shader_id)
        gpu, material = bodies[item['gpu']], bodies[item['material_file']]
        assert len(gpu) == 16592 and len(material) == 144
        assert struct.unpack_from('<I', material, 128)[0] == shader_id >> 32
        core.append((shader_id, photo_assets.SHADER, struct.pack('<I', 4), gpu))
        shared.append((photo_assets.hash64(item['material']), photo_assets.MATERIAL, material, b''))
    registry = bytearray(group[:24])
    struct.pack_into('<I', registry, 16, len(ids))
    registry += struct.pack('<%dQ' % len(ids), *ids)
    core.append((photo_assets.hash64(photo_assets.GROUP_NAME), photo_assets.GROUP, bytes(registry), b''))
    assert len(core) == 43 and len(shared) == 42 and len(ids) == 119
    stock = set(photo_assets.registry_ids((folder / 'original-default-shaders.bin').read_bytes()))
    assert set(ids) == stock | {row[0] for row in core if row[1] == photo_assets.SHADER}, 'Shader registry has unbundled or missing libraries'
    for rows in (core, shared):
        cpu, gpu = photo_assets.archive_rows(rows)
        assert sorted(photo_assets.read_archive(cpu, gpu)) == sorted(rows)
    return core, shared, {'shader_libraries_core': 42, 'materials_shared': 42,
        'registry_ids': 119, 'decorative_pairs': 40, 'shader_dof_focus_aperture_user_confirmed': True,
        'native_numeric_dof_functional': False, 'scene_visual_verified': False,
        'asset_files_sha256': identity['files']}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/releases/photo-0.7-preview')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    build = load('preview_photo_build', ROOT / 'freecam/build.py')
    foundation = (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
    vendor = json.loads((ROOT / 'freecam/vendor/PROVENANCE.json').read_text())
    assert hashlib.sha256(foundation).hexdigest() == vendor['actioncam_source_sha256']
    generated = build.patch(foundation.decode(), dof_candidate=True, scene_candidate=True).encode()
    build.compile_lua(generated, 'photo-0.7-preview')
    (out / 'ActionCam-Freecam.lua').write_bytes(generated)
    provenance = {'version': (ROOT / 'VERSION').read_text().strip(), 'runtime_sha256': hashlib.sha256(generated).hexdigest(),
        'source_modules_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / 'freecam').glob('*.lua')) if not p.name.endswith('_tests.lua')},
        'dof_candidate_preview': True, 'scene_candidate_preview': True, 'deployment': 'not installed'}
    (out / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    dof_assets.resources = resources
    bsl = build.package_bsl(out, dof_candidate=True)
    mdl = load('preview_mdl', ROOT / 'tools/build_mdl.py').package(out)
    (out / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in (bsl, mdl)))

if __name__ == '__main__':
    main()

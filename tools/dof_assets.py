"""Photo-owned DoF assets and renderer-core ordering; no installed/HUD inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

import photo_assets

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'freecam/assets/shaders'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def resources(output, gpu_path=None):
    """Return shader libraries/registry for core and materials for shared base."""
    identity = json.loads((FOLDER / 'dof-source-inputs.json').read_text())
    inputs = {}
    for name, expected in identity['files'].items():
        assert Path(name).name == name, 'DoF input must stay in owned asset folder'
        body = (FOLDER / name).read_bytes()
        assert sha(body) == expected['sha256'] and len(body) == expected['bytes'], 'DoF input identity mismatch: ' + name
        inputs[name] = body
    if gpu_path is None:
        shader_output = Path(output) / 'dof-shader'
        subprocess.run([sys.executable, str(ROOT / 'tools/build_dof_composition.py'), '--output', str(shader_output)], check=True)
        gpu_path = shader_output / 'dof_local_depth.gpu'
    gpu_path = Path(gpu_path)
    gpu = gpu_path.read_bytes()
    compiled = json.loads((gpu_path.parent / 'BUILD-RECEIPT.json').read_text())
    assert sha(gpu) == compiled['sha256'] and compiled['native_vertex_byte_identity'] and compiled['all_native_metadata_byte_identity']
    template = inputs['dof_library_template.gpu']
    assert compiled['original_candidate_sha256'] == sha(template) and len(gpu) == len(template) == 16592
    assert gpu[:0x2468] == template[:0x2468] and gpu[0x2468 + 7152:] == template[0x2468 + 7152:]
    original_group = inputs['dof_registry_base.bin']
    ids = list(photo_assets.registry_ids(original_group))
    assert len(ids) == 315
    shader_name, material_name = identity['shader'], identity['material']
    shader_id = photo_assets.hash64(shader_name)
    assert shader_id not in ids
    ids.append(shader_id)
    group = bytearray(original_group[:24])
    struct.pack_into('<I', group, 16, len(ids))
    group += struct.pack('<316Q', *ids)
    material = inputs['dof_local_depth.material.bin']
    assert len(material) == 144 and struct.unpack_from('<I', material, 128)[0] == shader_id >> 32
    owned = photo_assets.load_resources()
    libraries = [row for row in owned if row[1] == photo_assets.SHADER]
    materials = [row for row in owned if row[1] == photo_assets.MATERIAL]
    assert len(libraries) == len(materials) == 40 and all(row[0] in ids for row in libraries)
    core = libraries + [(shader_id, photo_assets.SHADER, struct.pack('<I', 4), gpu),
        (photo_assets.hash64(photo_assets.GROUP_NAME), photo_assets.GROUP, bytes(group), b'')]
    shared = materials + [(photo_assets.hash64(material_name), photo_assets.MATERIAL, material, b'')]
    for rows in (core, shared):
        cpu, external = photo_assets.archive_rows(rows)
        assert sorted(photo_assets.read_archive(cpu, external)) == sorted(rows)
    proof=json.loads((ROOT/'docs/DOF-VISUAL-VERIFICATION.json').read_text())
    assert proof['shader_gpu_sha256']==sha(gpu),'DoF shader differs from visually verified build'
    audit = {'candidate': True, 'dof_visual_response_verified': True, 'shader_quality': 'under review', 'shader_libraries_core': 41, 'registry_resources_core': 1, 'materials_shared': 41,
        'registry_count': 316, 'original_315_ids_preserved': True, 'registry_sha256': sha(group),
        'dof_shader_gpu_sha256': sha(gpu), 'dof_material_sha256': sha(material),
        'owned_input_manifest_sha256': sha((FOLDER / 'dof-source-inputs.json').read_bytes()),
        'composition_build': compiled, 'visual_verification':proof, 'installed': False, 'live_verified': True}
    return core, shared, audit


def package(output, gpu_path=None):
    output = Path(output)
    core, shared, audit = resources(output, gpu_path)
    manifest = {'Version': 1, 'Guid': 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df',
        'Name': 'War Journalist DoF Assets - Fallback Preview',
        'Description': 'All 40 decorative overlays and depth-aware focus/aperture assets. Photo runtime is supplied separately.',
        'Options': [{'Name': 'DoF shader assets and registry', 'Include': ['Assets']}]}
    files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'ASSET-RECEIPT.json': (json.dumps(audit, indent=2) + '\n').encode()}
    for name, rows in [('ee6b1ba7e22d71ed.patch_0', core), ('9ba626afa44a3aa3.patch_0', shared)]:
        cpu, gpu = photo_assets.archive_rows(rows)
        for suffix, body in [('', cpu), ('.gpu_resources', gpu), ('.stream', b'')]:
            files['Assets/' + name + suffix] = body
    files['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(files.items())).encode()
    output.mkdir(parents=True, exist_ok=True)
    target = output / 'War-Journalist-DoF-Fallback-Assets.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, body in sorted(files.items()):
            archive.writestr(name, body)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None and len(archive.namelist()) == len(files) == len(set(archive.namelist()))
        for name, body in files.items():
            assert archive.read(name) == body
    audit.update(artifact=target.name, artifact_sha256=sha(target.read_bytes()),
        files={name: {'sha256': sha(body), 'bytes': len(body)} for name, body in sorted(files.items())})
    (output / 'PACKAGE-RECEIPT.json').write_text(json.dumps(audit, indent=2) + '\n')
    print(target)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/releases/photo-dof-fallback-assets')
    parser.add_argument('--dof-gpu', type=Path)
    args = parser.parse_args()
    package(args.output, args.dof_gpu)

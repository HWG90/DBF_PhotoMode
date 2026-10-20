"""Package a separate DoF boot-order review candidate; never deploy it."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'DBF-HUD/tools'))
from build_scene_depth_probe import archive_rows
from build_depth_state_test import hash64

OUT = ROOT / 'dist/releases/photo-dof-core-order-review'
SOURCE = ROOT / 'dist/releases/photo-dof-local-depth-review/War-Journalist-DoF-Assets-Candidate-1.zip'
ORIGINAL = ROOT / 'dist/deployment-backups/dof-registration-v2-20261011/ee6b1ba7e22d71ed.patch_0'
GUID = 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
SHADER = 'mods/dbf_photo/shaders/dof_local_depth_v1'
MATERIAL = 'mods/dbf_photo/materials/dof_local_depth_v1'
GROUP = 'core/stingray_renderer/shader_libraries/default_shaders'
CORE = 'ee6b1ba7e22d71ed.patch_0'
SHARED = '9ba626afa44a3aa3.patch_0'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_resources(cpu, gpu=b''):
    magic, types, count = struct.unpack_from('<III', cpu)
    assert magic == 0xf0000011 and 0 < types <= count
    start = 72 + types * 32
    assert start + count * 80 <= len(cpu)
    resources = {}
    for row in struct.iter_unpack('<7Q6I', cpu[start:start + count * 80]):
        name, kind = row[:2]
        assert (name, kind) not in resources
        assert row[2] + row[7] <= len(cpu) and row[4] + row[9] <= len(gpu)
        resources[name, kind] = (name, kind, cpu[row[2]:row[2] + row[7]], gpu[row[4]:row[4] + row[9]])
    return resources


def main():
    assert not OUT.exists(), 'Named review output already exists; preserve it and choose a new candidate name'
    source_bytes = SOURCE.read_bytes()
    with zipfile.ZipFile(SOURCE) as archive:
        assert archive.testzip() is None
        source_manifest = json.loads(archive.read('manifest.json'))
        assert source_manifest['Guid'] == 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
        shared_cpu = archive.read('Assets/' + SHARED)
        shared_gpu = archive.read('Assets/' + SHARED + '.gpu_resources')
        registry_cpu = archive.read('Assets/' + CORE)
        assert not archive.read('Assets/' + CORE + '.gpu_resources')
        assert not archive.read('Assets/' + CORE + '.stream')
        assert not archive.read('Assets/' + SHARED + '.stream')
    # Confirm the source ZIP contains the exact previously packaged asset pair.
    split = SOURCE.parent / 'split-archive-candidate'
    split_receipt = json.loads((split / 'PACKAGE-RECEIPT.json').read_text())
    assert sha(shared_cpu) == split_receipt['files']['9ba626afa44a3aa3.patch_85']['sha256']
    assert sha(shared_gpu) == split_receipt['files']['9ba626afa44a3aa3.patch_85.gpu_resources']['sha256']
    assets = read_resources(shared_cpu, shared_gpu)
    registry = read_resources(registry_cpu)
    shader_key = (hash64(SHADER), hash64('shader_library'))
    material_key = (hash64(MATERIAL), hash64('material'))
    group_key = (hash64(GROUP), hash64('shader_library_group'))
    assert set(assets) == {shader_key, material_key} and set(registry) == {group_key}
    shader, material, group = assets[shader_key], assets[material_key], registry[group_key]
    assert shader[2] == struct.pack('<I', 4) and shader[3]
    assert len(material[2]) == 144 and not material[3]
    assert struct.unpack_from('<I', material[2], 128)[0] == hash64(SHADER) >> 32
    original_bytes = ORIGINAL.read_bytes()
    # The original archive contains external shader payloads. Only inspect its
    # CPU registry row; no game shader bytes are copied into this package.
    types, count = struct.unpack_from('<II', original_bytes, 4)
    rows = struct.iter_unpack('<7Q6I', original_bytes[72 + types * 32:72 + types * 32 + count * 80])
    original_row = next(row for row in rows if row[:2] == group_key)
    original_group = original_bytes[original_row[2]:original_row[2] + original_row[7]]
    assert sha(original_group) == '5b83c424902bb429d476253edeeb400bb02e2f92fbc4c863f7430e251a8a24b1'
    assert struct.unpack_from('<I', original_group, 16)[0] == 315 and len(original_group) == 24 + 315 * 8
    assert struct.unpack_from('<I', group[2], 16)[0] == 316 and len(group[2]) == 24 + 316 * 8
    assert group[2][:16] == original_group[:16] and group[2][20:24] == original_group[20:24]
    assert group[2][24:24 + 315 * 8] == original_group[24:]
    assert struct.unpack_from('<Q', group[2], 24 + 315 * 8)[0] == shader_key[0]
    assert shader_key[0] not in struct.unpack_from('<315Q', original_group, 24)
    core_cpu, core_gpu = archive_rows([shader, group])
    material_cpu, material_gpu = archive_rows([material])
    core_resources = read_resources(core_cpu, core_gpu)
    material_resources = read_resources(material_cpu, material_gpu)
    assert core_resources == {shader_key: shader, group_key: group}
    assert material_resources == {material_key: material} and not material_gpu
    manifest = {'Version': 1, 'Guid': GUID, 'Name': 'War Journalist DoF Assets - Core Order Review',
        'Description': 'Development review candidate: the DoF shader library and its registry share the renderer core archive. Material remains in the shared base archive. Runtime registration and visual behavior require a normal-start check.',
        'Options': [{'Name': 'DoF shader assets and registry', 'Include': ['Assets']}]}
    receipt = {'candidate': True, 'completed_fix': False, 'installed': False, 'live_verified': False,
        'manifest_guid': GUID, 'source_package': SOURCE.name, 'source_package_sha256': sha(source_bytes),
        'manifest_guid_preserved_from_candidate_1': True, 'original_registry_source': str(ORIGINAL.relative_to(ROOT)),
        'original_registry_sha256': sha(original_group), 'original_shader_count': 315,
        'candidate_shader_count': 316, 'previous_315_ids_preserved_in_order': True,
        'shader_library_archive': CORE, 'shader_registry_archive': CORE, 'material_archive': SHARED,
        'resource_counts': {CORE: 2, SHARED: 1},
        'payload_sha256': {'shader_cpu': sha(shader[2]), 'shader_gpu': sha(shader[3]),
            'material_cpu': sha(material[2]), 'registry_cpu': sha(group[2])},
        'shader_and_material_payloads_identical_to_candidate_1': True,
        'registry_payload_identical_to_candidate_1': True,
        'validation': 'Exact serialized resource roundtrips; resource owners/counts checked; original 315 IDs preserved; ZIP exact entry bytes and CRC checked',
        'required_next_check': 'Normal-start renderer registration and GPU draw validation; this package alone does not prove a working DoF fix'}
    files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'CANDIDATE-STATUS.json': (json.dumps(receipt, indent=2) + '\n').encode(),
        'INSTALL.txt': b'''WAR JOURNALIST DOF ASSETS - CORE ORDER REVIEW

Import this ZIP into HD2 Arsenal and select its DoF assets option for review.
The Photo Mode Lua runtime is supplied separately. A normal game restart is
required after asset deployment. This archive has not been installed or live
verified and is not a completed DoF fix.

This candidate moves the existing shader library from the shared base archive
into the renderer core archive alongside its registry. The material stays in
the shared base archive. All shader/material bytes and the original 315 shader
IDs are preserved. The registry contains those 315 IDs plus the candidate ID.

Disable earlier DoF asset candidates when selecting this review package.
Disable this review package and redeploy to remove its additive assets.
'''}
    for name, cpu, gpu in ((CORE, core_cpu, core_gpu), (SHARED, material_cpu, material_gpu)):
        for suffix, value in (('', cpu), ('.gpu_resources', gpu), ('.stream', b'')):
            files['Assets/' + name + suffix] = value
    files['FILES-SHA256.txt'] = ''.join(sha(value) + '  ' + name + '\n' for name, value in sorted(files.items())).encode()
    OUT.mkdir(parents=True)
    for name, value in files.items():
        path = OUT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
    target = OUT / 'War-Journalist-DoF-Assets-Core-Order-Review.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, value in sorted(files.items()):
            archive.writestr(name, value)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(files) == len(set(archive.namelist()))
        for name, value in files.items():
            assert archive.read(name) == value
    receipt['zip'] = {'name': target.name, 'sha256': sha(target.read_bytes()), 'bytes': target.stat().st_size, 'entry_count': len(files)}
    receipt['files'] = {name: {'sha256': sha(value), 'bytes': len(value)} for name, value in sorted(files.items())}
    (OUT / 'PACKAGE-RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'zip': str(target), 'guid': GUID, 'zip_sha256': receipt['zip']['sha256'],
        'resource_counts': receipt['resource_counts'], 'payload_sha256': receipt['payload_sha256'], 'installed': False}, indent=2))


if __name__ == '__main__':
    main()

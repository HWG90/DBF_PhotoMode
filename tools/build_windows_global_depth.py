"""WITHDRAWN: menu-open crash on Windows with portable.5.

Never edits installed files. Retains both DXBC stages and slot/sampler numbers;
copies the existing global color binding's category to the depth binding.
The footer field changed from 3 to 4 was subsequently identified as a
declaration index, not a binding category. This converter remains withdrawn.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import photo_assets as assets

SHA = lambda b: hashlib.sha256(b).hexdigest()
OLD = ('76ff992884d03475', 'da4d644cfee69b09')


def convert(gpu, material, suffix):
    original = bytes(gpu)
    body = bytearray(gpu)
    tail = len(body) - 120
    windows = assets._dxbc_windows(body)
    assert windows[0] == (0xff0, 5160) and windows[1][0] == 0x2468
    assert windows[1][0] + windows[1][1] == tail
    u = lambda at: struct.unpack_from('<I', original, at)[0]
    local = assets.hash64('diffuse_map') >> 32
    global_color = assets.hash64('output_target') >> 32
    depth = assets.hash64('linear_depth') >> 32
    # The two records have identical shapes and each keeps its own t/s slot.
    assert tuple(u(at) for at in (0xf18, 0xf20, 0xf28)) == (6, local, 0)
    assert tuple(u(at) for at in (0xf30, 0xf38, 0xf40)) == (5, global_color, 1)
    assert tuple(u(tail + at) for at in (56, 60, 64, 68)) == (local, 3, 0, 1)
    assert tuple(u(tail + at) for at in (72, 76, 80, 84)) == (global_color, 4, 1, 1)
    offsets = (0x5ec, 0xf20, tail + 56, tail + 88)
    assert all(u(at) == local for at in offsets)
    identity = SHA(original + b':global-linear-depth-v1')[:16]
    shader = 'mods/dbf_photo/shaders/windows_global_depth_' + identity
    name = 'mods/dbf_photo/materials/windows_global_depth_' + identity
    allowed = set()
    def put(at, value):
        struct.pack_into('<I', body, at, value)
        allowed.update(range(at, at + 4))
    for at in offsets:
        put(at, depth)
    put(0xf18, u(0xf30))
    put(tail + 60, u(tail + 76))
    # Separate identities prevent collision with the deployed local-depth test.
    identities = {u(0x88): assets.hash64(shader + ':default:PLATFORM_WIN32:RENDERER_D3D11') >> 32,
                  u(0xe0): assets.hash64(shader) >> 32,
                  u(0xbec): assets.hash64(shader + ':pixel') >> 32}
    counts = {key: 0 for key in identities}
    for at in range(0, len(body) - 3, 4):
        if any(start <= at < start + size for start, size in windows):
            continue
        if u(at) in identities:
            put(at, identities[u(at)])
            counts[u(at)] += 1
    assert sorted(counts.values()) == [1, 2, 2]
    assert all(at in allowed for at, (a, b) in enumerate(zip(original, body)) if a != b)
    assert all(body[start:start+size] == original[start:start+size] for start, size in windows)
    mat = bytearray(material)
    assert struct.unpack_from('<I', mat, 128)[0] == u(0xe0)
    struct.pack_into('<I', mat, 128, identities[u(0xe0)])
    return shader, name, bytes(body), bytes(mat), {
        'source_suffix': suffix, 'source_gpu_sha256': SHA(original),
        'shader': shader, 'material': name, 'gpu_sha256': SHA(body),
        'depth_hash_offsets': [hex(at) for at in offsets],
        'category_changes': {'parameter': [6, 5], 'binding': [3, 4]},
        'depth_slot': 0, 'color_slot': 1, 'both_dxbc_stages_unchanged': True,
        'live_verified': False}


def build(source, output, converter=None):
    assert not output.exists(), 'Preserve named candidates'
    archives = {}
    for path in source.iterdir():
        if path.is_file() and '.patch_' in path.name and not path.suffix in ('.stream', '.gpu_resources'):
            gpu = Path(str(path) + '.gpu_resources')
            archives[path.name] = assets.read_archive(path.read_bytes(), gpu.read_bytes() if gpu.exists() else b'')
    lookup = {row[:2]: (archive, row) for archive, rows in archives.items() for row in rows}
    receipts, shader_ids = [], []
    for suffix in OLD:
        old_shader = assets.hash64('mods/dbf_photo/shaders/scene_dof_resolved_v2_' + suffix)
        old_material = assets.hash64('mods/dbf_photo/materials/scene_dof_resolved_v2_' + suffix)
        shader_archive, (_, kind, cpu, gpu) = lookup[(old_shader, assets.SHADER)]
        material_archive, (_, _, mat, _) = lookup[(old_material, assets.MATERIAL)]
        shader, name, new_gpu, new_mat, receipt = (converter or convert)(gpu, mat, suffix)
        shader_ids.append(assets.hash64(shader))
        archives[shader_archive].append((assets.hash64(shader), kind, cpu, new_gpu))
        archives[material_archive].append((assets.hash64(name), assets.MATERIAL, new_mat, b''))
        receipts.append(receipt)
    registry_archive = None
    for archive, rows in archives.items():
        for index, row in enumerate(rows):
            if row[1] != assets.GROUP:
                continue
            assert registry_archive is None, 'Expected one owned registry'
            registry_archive = archive
            ids = list(assets.registry_ids(row[2]))
            assert all(key not in ids for key in shader_ids)
            ids.extend(shader_ids)
            data = bytearray(row[2][:24])
            struct.pack_into('<I', data, 16, len(ids))
            data += struct.pack('<' + str(len(ids)) + 'Q', *ids)
            rows[index] = (row[0], row[1], bytes(data), row[3])
    assert registry_archive
    output.mkdir(parents=True)
    for archive, rows in archives.items():
        body, gpu = assets.archive_rows(rows)
        roundtrip = assets.read_archive(body, gpu)
        assert sorted(roundtrip) == sorted(rows)
        # Every previous non-registry resource must survive byte for byte.
        for key, (owner, row) in lookup.items():
            if owner == archive and row[1] != assets.GROUP:
                assert row in roundtrip
        (output / archive).write_bytes(body)
        (output / (archive + '.gpu_resources')).write_bytes(gpu)
        (output / (archive + '.stream')).write_bytes(b'')
    registry = (output / registry_archive).read_bytes()
    return {'candidate': True, 'live_verified': False, 'shaders': receipts,
            'registry': {'name': registry_archive, 'hex': registry.hex()},
            'preserved_resources': len(lookup) - 1}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    parser.error('Withdrawn after portable.5 menu-open crash; metadata conversion is not runtime-qualified')
    receipt = build(args.source, args.output)
    (args.output.parent / 'GLOBAL-DEPTH.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'registry'}, indent=2))

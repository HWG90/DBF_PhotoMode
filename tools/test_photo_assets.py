"""Verify that startup registrations contain only stock and shipped libraries.

No game, installed patches, GPU device, compiler, or release build is used.
"""
import json
from pathlib import Path
import struct

import build_preview
import build_release
import photo_assets
import photo_light_assets

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'freecam/assets/shaders'


def check_registry(core, expected_count):
    groups = [row for row in core if row[1] == photo_assets.GROUP]
    assert len(groups) == 1, 'Exactly one startup shader registry is required'
    ids = photo_assets.registry_ids(groups[0][2])
    stock = photo_assets.registry_ids((FOLDER / 'original-default-shaders.bin').read_bytes())
    shipped = {row[0] for row in core if row[1] == photo_assets.SHADER}
    assert len(stock) == 77 and len(ids) == expected_count
    assert tuple(ids[:len(stock)]) == stock, 'Stock order or membership changed'
    assert set(ids) == set(stock) | shipped, 'Unbundled or missing shader registration'
    return ids, stock, shipped


def changed_group(core, ids):
    group = next(row for row in core if row[1] == photo_assets.GROUP)
    header = bytearray(group[2][:24])
    struct.pack_into('<I', header, 16, len(ids))
    replacement = group[:2] + (bytes(header) + struct.pack('<%dQ' % len(ids), *ids), group[3])
    return [replacement if row[:2] == group[:2] else row for row in core]


def rejected(core, count):
    try:
        check_registry(core, count)
    except (AssertionError, ValueError):
        return
    raise AssertionError('Invalid startup registration closure accepted')


def verify():
    preview_core, preview_shared, _ = build_preview.resources(None)
    check_registry(preview_core, 119)
    core, shared, audit = build_release.resources(None)
    ids, stock, shipped = check_registry(core, 121)
    assert len(shipped) == 44 and audit['registry_closed_over_bundled_libraries']
    assert len(core) == 45 and len(shared) == 45
    legacy = photo_assets.registry_ids((FOLDER / 'dof_registry_base.bin').read_bytes())
    unbundled = set(legacy) - set(stock) - shipped
    assert len(unbundled) == 198 and not set(ids) & unbundled
    # A historical valid binary group is insufficient: its membership must be
    # closed over the libraries that actually ship alongside it.
    rejected(changed_group(core, list(legacy) + [value for value in ids if value not in legacy]), 319)
    rejected(changed_group(core, list(ids[:-1])), 120)
    rejected(changed_group(core, list(ids) + [ids[-1]]), 122)
    rejected(changed_group(core, [ids[1], ids[0]] + list(ids[2:])), 121)
    # The fix must not modify any shader program, material, or the light unit.
    original = photo_assets.load_resources()
    all_rows = {row[:2]: row for row in core + shared}
    assert all(all_rows[row[:2]] == row for row in original)
    effects = json.loads((FOLDER / 'preview-assets.json').read_text())['effects']
    for item in effects:
        shader = photo_assets.hash64(item['shader'])
        material = photo_assets.hash64(item['material'])
        assert all_rows[shader, photo_assets.SHADER] == (shader, photo_assets.SHADER, struct.pack('<I', 4), (FOLDER / item['gpu']).read_bytes())
        assert all_rows[material, photo_assets.MATERIAL] == (material, photo_assets.MATERIAL, (FOLDER / item['material_file']).read_bytes(), b'')
    manifest = json.loads((build_release.SNAPSHOTS / 'manifest.json').read_text())
    for pair in manifest['pairs']:
        shader = photo_assets.hash64(pair['shader'])
        material = photo_assets.hash64(pair['material'])
        label = pair['label']
        assert all_rows[shader, photo_assets.SHADER] == (shader, photo_assets.SHADER, struct.pack('<I', 4), (build_release.SNAPSHOTS / (label + '.gpu')).read_bytes())
        assert all_rows[material, photo_assets.MATERIAL] == (material, photo_assets.MATERIAL, (build_release.SNAPSHOTS / (label + '.material.bin')).read_bytes(), b'')
    light = photo_light_assets.resource()
    assert all_rows[light[:2]] == light
    for rows in (core, shared):
        assert photo_assets.read_archive(*photo_assets.archive_rows(rows)) == sorted(rows, key=lambda row: (row[1], row[0]))
    return {'passed': True, 'stock_registrations': 77, 'bundled_libraries': 44,
            'startup_registrations': 121, 'historical_unbundled_ids_removed': 198,
            'shader_material_light_bytes_preserved': True,
            'invalid_membership_and_duplicates_rejected': True,
            'game_process_accessed': False}


if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))

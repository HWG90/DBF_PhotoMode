"""Bounded resource closure and preservation checks for the Photo light asset."""
import argparse
import json
from pathlib import Path
import struct
import zipfile

import photo_assets
import photo_light_assets as lights


def rejects(body):
    try:
        lights.validate_unit(body)
    except ValueError:
        return
    raise AssertionError('Malformed light unit accepted')


def verify(base_zip=None):
    row = lights.resource()
    info = lights.validate_unit(row[2])
    assert info['external_dependencies'] == [] and info['meshes'] == 0
    assert struct.unpack_from('<4f', row[2], 0xa8) == (1, 1, 1, 3)
    assert struct.unpack_from('<f', row[2], 0xbc)[0] == 8
    rejects(row[2][:-1])
    for at, value in ((8, 1), (16, 1), (24, 1), (32, 1),
                      (92, 128), (96, 128), (100, 128), (112, 128),
                      (0x90, 0), (0xa4, 1), (0xec, 2)):
        altered = bytearray(row[2])
        struct.pack_into('<I', altered, at, value)
        rejects(bytes(altered))
    resources = photo_assets.load_resources()
    base_description = 'All 40 exact owned decorative material/library pairs'
    if base_zip:
        with zipfile.ZipFile(base_zip) as archive:
            candidates = [name for name in archive.namelist()
                          if name.endswith('/' + lights.SHARED_ARCHIVE)]
            assert len(candidates) == 1 and archive.testzip() is None
            name = candidates[0]
            resources = photo_assets.read_archive(archive.read(name),
                                                   archive.read(name + '.gpu_resources'),
                                                   archive.read(name + '.stream'))
            base_description = str(base_zip)
    original = {item[:2]: item for item in resources}
    augmented = lights.merge_resources(resources)
    assert resources == list(original.values()), 'Merge modified the caller resource list'
    assert lights.merge_resources(augmented) == augmented, 'Exact merge must be idempotent'
    cpu, gpu = photo_assets.archive_rows(augmented)
    merged = {item[:2]: item for item in photo_assets.read_archive(cpu, gpu)}
    assert len(merged) == len(original) + (row[:2] not in original) and merged[row[:2]] == row
    assert all(merged[key] == value for key, value in original.items())
    audit = lights.validate_bundled_archive(cpu, gpu)
    assert audit['testing_status'] == 'Not tested fully' and audit['self_contained']
    assert not audit['engine_loaded'] and not audit['rendered_light_verified']
    manager = (lights.ROOT/'freecam/photo_lights.lua').read_text()
    assert "resource='"+info['resource_id']+"'" in manager and "resource_name='"+lights.RESOURCE_NAME+"'" in manager
    assert "testing_status='Not tested fully'" in manager
    def rejected(call):
        try:call()
        except ValueError:return
        raise AssertionError('Invalid bundled unit/merge accepted')
    changed = (row[0], row[1], row[2][:-1]+b'\1', row[3])
    rejected(lambda: lights.merge_resources(resources+[changed]))
    rejected(lambda: lights.merge_resources(augmented+[row]))
    rejected(lambda: lights.split_bundled_resources(resources if row[:2] not in original else [r for r in resources if r[:2]!=row[:2]]))
    rejected(lambda: lights.split_bundled_resources([changed]))
    rejected(lambda: lights.split_bundled_resources([(row[0],row[1],row[2],b'external GPU')]))
    if not base_zip:
        normal = lights.validate_archive(cpu,gpu)
        assert normal['photo_light']['external_dependencies']==[]
        foreign=(row[0]+1,row[1],row[2],b'')
        foreign_cpu,foreign_gpu=photo_assets.archive_rows(augmented+[foreign])
        rejected(lambda:lights.validate_archive(foreign_cpu,foreign_gpu))
    return {'passed': True, 'resource': info,
            'malformed_structure_cases_rejected': 13,
            'merge_base': base_description, 'base_resources_preserved_exactly': len(original),
            'merged_resources': len(merged), 'testing_status': 'Not tested fully',
            'idempotent_exact_merge': True, 'runtime_resource_matches': True,
            'malformed_merge_and_closure_rejected': True,
            'engine_loaded': False, 'rendered_light_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-zip', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.base_zip)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

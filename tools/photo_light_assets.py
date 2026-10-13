"""Dependency-free Photo light unit and additive shared-boot review package.

This module never reads installed settings, writes game files, or spawns units.
The compiled light-only structure retains the validated root light, embedded
node transforms, and generic unit metadata. The ship archive's optional global
geometry/material references are absent, as they are in a stock boot light.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zipfile

import photo_assets

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_NAME = 'mods/dbf_photo/units/photo_light_v1'
RESOURCE_ID = photo_assets.hash64(RESOURCE_NAME)
UNIT = photo_assets.hash64('unit')
SHARED_ARCHIVE = '9ba626afa44a3aa3.patch_0'
TESTING_STATUS = 'Not tested fully'
SOURCE_SHA256 = '1414abb0d5df9037a3072eaefdf4a22d23033f83c501e68c6c57f07873bd857a'

# Compiled generic light/node/property sections from the verified light-only
# structure. This is not the ship unit identity and references no ship assets.
_COMPILED_STRUCTURE = bytes.fromhex(
    '0000000000000000000000000000000070e39423893bf8dde31548e74d3e767c00000000000000000200000036cda400'
    '10010000200100009000000080000000000000000000000000000000d0020000b0030000000000000000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '010000000000000000000000000000004f22d77d000000000000803f0000803f0000803f0000803f000000000000a040'
    '0000803f00000000db0f493f00000000cdcccc3e0000000000000000cdcccc3dcdcccc3d000000006000000000000000'
    '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
    '030000000000000000000000000000000000803f0000000000000000000000000000803f000000000000000000000000'
    '0000803f0000000000000000000000000000803f0000803f0000803f000000000000803f000000000000000000000000'
    '32318d240000803f00000000000080bf32318d240000000000000000000000000000803f0000803f0000803f00000000'
    '0000803f0000000000000000000000000000803f0000000000000000000000000000803f000000000000000000000000'
    '0000803f0000803f0000803f000000000000803f000000000000000000000000000000000000803f0000000000000000'
    '00000000000000000000803f000000000000000000000000000000000000803f0000803f000000000000000000000000'
    '0000000032318d240000803f0000000000000000000080bf32318d24000000000000000000000000000000000000803f'
    '0000803f0000000000000000000000000000000032318d240000803f0000000000000000000080bf32318d2400000000'
    '0000000000000000000000000000803f0000000001000000010001004127184a1ce6307fe739b95c0000000000000000'
    'dc000000080000000000000065df029920000000030000000800000064796e616d69630014dc8f4e70000000ffffffff'
    '0400000034000000bf406927ffffffffffffffff0400000048000000cfea3d1d5c000000010000000400000000000000'
    'bf0fd9c6ffffffff010000000400000000000000d000f05788000000030000000800000064656661756c740058920788'
    '9c000000010000000400000001000000df8f72e6ffffffffffffffff04000000b0000000a4ab4d7ec800000003000000'
    '080000006c696768740000000a7376d3ffffffff010000000400000001000000020000004f22d77de39d38fb1c000000'
    '000000001c0000000000000000000000'
)


def sha(body):
    return hashlib.sha256(body).hexdigest()


def validate_unit(body):
    if len(body) != 976:
        raise ValueError('Photo light compiled structure size changed')
    # Header resource references: bones, geometry group, auxiliary material,
    # state machine. All are absent; transforms are embedded in the unit.
    if struct.unpack_from('<4Q', body, 8) != (0, 0, 0, 0):
        raise ValueError('Photo light unexpectedly references an external asset')
    header = struct.unpack_from('<32I', body)
    if header[10:16] != (2, 10800438, 0x110, 0x120, 0x90, 0x80):
        raise ValueError('Photo light format or section layout changed')
    if header[19:21] != (0x2d0, 0x3b0):
        raise ValueError('Photo light unit metadata layout changed')
    # Mesh, GPU layout/data, terrain, skeleton resources, and material table
    # offsets are zero. There is no geometry to hide or render.
    if any(header[index] for index in (17, 18, 22, 23, 24, 25, 26, 28)):
        raise ValueError('Photo light contains a render/physics dependency section')
    if struct.unpack_from('<I', body, 0x110)[0] != 0:
        raise ValueError('Photo light contains geometry LODs')
    if struct.unpack_from('<I', body, 0x90)[0] != 1:
        raise ValueError('Photo light must contain exactly one light')
    if struct.unpack_from('<II', body, 0xa0) != (photo_assets.hash64('light') >> 32, 0):
        raise ValueError('Photo light must attach to root node 1')
    if struct.unpack_from('<I', body, 0xec)[0] != 0:
        raise ValueError('Photo light must start as a point light')
    if struct.unpack_from('<I', body, 0x120)[0] != 3:
        raise ValueError('Photo light embedded node structure changed')
    return {'resource_name': RESOURCE_NAME, 'resource_id': f'{RESOURCE_ID:016x}',
            'unit_type': f'{UNIT:016x}', 'cpu_bytes': len(body),
            'gpu_bytes': 0, 'stream_bytes': 0, 'light_count': 1,
            'light_root_node': 1, 'initial_type': 'point',
            'embedded_transform_nodes': 3, 'meshes': 0, 'external_dependencies': [],
            'unit_sha256': sha(body)}


def resource():
    if sha(_COMPILED_STRUCTURE) != SOURCE_SHA256:
        raise ValueError('Compiled light-only structural template identity changed')
    body = bytearray(_COMPILED_STRUCTURE)
    # These references are optional in the independently inspected stock
    # shared-boot light (6906ba0515f518d7). The light-only unit has no meshes,
    # material slots, or geometry fields requiring either archive reference.
    struct.pack_into('<2Q', body, 0x10, 0, 0)
    struct.pack_into('<f', body, 0xb4, 3.0)  # light intensity
    struct.pack_into('<f', body, 0xbc, 8.0)  # default falloff end
    body = bytes(body)
    validate_unit(body)
    return RESOURCE_ID, UNIT, body, b''


def resources():
    return [resource()]


def merge_resources(existing):
    """Add the exact owned unit without modifying existing resource payloads."""
    rows = list(existing)
    if len({row[:2] for row in rows}) != len(rows):
        raise ValueError('Duplicate base resource identity before Photo light merge')
    light = resource()
    found = [row for row in rows if row[:2] == light[:2]]
    if found:
        if found != [light]:
            raise ValueError('Photo light identity collides with different native bytes')
    else:
        rows.append(light)
    return rows


def split_bundled_resources(rows):
    """Validate the explicit unit and return unchanged rows for existing checks."""
    rows = list(rows)
    light = resource()
    found = [row for row in rows if row[:2] == light[:2]]
    if found != [light]:
        raise ValueError('Bundled Photo light is missing, duplicated, or changed')
    validate_unit(found[0][2])
    return [row for row in rows if row[:2] != light[:2]]


def validate_bundled_archive(cpu, gpu=b'', stream=b''):
    """Check packaged unit bytes/closure, independently of shader validation."""
    rows = photo_assets.read_archive(cpu, gpu, stream)
    split_bundled_resources(rows)
    audit = validate_unit(resource()[2])
    audit.update(testing_status=TESTING_STATUS, self_contained=True,
                 engine_loaded=False, rendered_light_verified=False,
                 archive=SHARED_ARCHIVE, resource_count=1,
                 loading='Existing shared boot archive; restart required')
    return audit


def validate_archive(cpu, gpu=b'', **kwargs):
    """Preserve existing asset checks while allowing only the exact owned unit."""
    rows = photo_assets.read_archive(cpu, gpu)
    other_cpu, other_gpu = photo_assets.archive_rows(split_bundled_resources(rows))
    audit = photo_assets.validate_archive(other_cpu, other_gpu, **kwargs)
    audit.update(cpu_sha256=sha(cpu), gpu_sha256=sha(gpu),
                 archive_resources=len(rows), photo_light=validate_bundled_archive(cpu, gpu))
    return audit


def package(output):
    output = Path(output)
    if output.exists():
        raise ValueError('Preserve an existing named candidate output')
    row = resource()
    audit = validate_unit(row[2])
    cpu, gpu = photo_assets.archive_rows([row])
    if gpu or photo_assets.read_archive(cpu) != [row]:
        raise ValueError('Photo light archive serialization differs')
    audit.update(candidate=True, installed=False, live_verified=False, testing_status=TESTING_STATUS,
                 archive=SHARED_ARCHIVE, loading='Additive resource in existing shared boot archive; no ResourcePackage constructor assumed',
                 source_light_only_structure_sha256=SOURCE_SHA256,
                 optional_reference_zero_proof='Stock shared boot unit 6906ba0515f518d7; both header references are already zero',
                 required_next_check='Startup can_get(unit, resource ID), then root-node light readback and a visible light in a mission')
    manifest = {'Version': 1, 'Guid': '92cb59c6-d426-4a45-a13e-fb8369963693',
                'Name': 'War Journalist Photo Light - Boot Asset Review',
                'Description': 'Dedicated light-only Photo unit. No ship geometry, meshes, materials, textures, GPU payload, or runtime included. Not installed or live verified.',
                'Options': [{'Name': 'Photo light boot asset review', 'Include': ['Assets']}]}
    files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
             'PHOTO-LIGHT-ASSET.json': (json.dumps(audit, indent=2) + '\n').encode(),
             'Assets/' + SHARED_ARCHIVE: cpu,
             'Assets/' + SHARED_ARCHIVE + '.gpu_resources': b'',
             'Assets/' + SHARED_ARCHIVE + '.stream': b'',
             'INSTALL.txt': b'''PHOTO LIGHT BOOT ASSET - DEVELOPMENT REVIEW

This candidate contains one dedicated light-only unit in the shared boot
archive. The owning complete Photo Mode build must merge this resource with
its existing shaders/materials/Lua startup and select the resource ID from
PHOTO-LIGHT-ASSET.json. Do not replace the running Photo archive directly
with this single-resource archive. No runtime/game files are deployed here.

The unit does not reference ship geometry, material, texture, state machine,
or skeleton resources. Its one point light is attached to root node 1.
Startup availability and a rendered light on a mission remain unverified.
Removal consists of removing this additive resource from the next Photo
package after the runtime has released all units it owns.
'''}
    files['FILES-SHA256.txt'] = ''.join(sha(data) + '  ' + name + '\n'
                                      for name, data in sorted(files.items())).encode()
    output.mkdir(parents=True)
    (output / 'photo_light.unit.bin').write_bytes(row[2])
    for name, data in files.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    target = output / 'War-Journalist-Photo-Light-Boot-Asset-Review.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr(name, data)
    with zipfile.ZipFile(target) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(files):
            raise ValueError('Photo light ZIP integrity failed')
        if any(archive.read(name) != data for name, data in files.items()):
            raise ValueError('Photo light ZIP entry identity differs')
    audit.update(zip=target.name, zip_sha256=sha(target.read_bytes()),
                 archive_sha256=sha(cpu), exact_resource_roundtrip=True,
                 zip_crc_and_exact_entries=True)
    (output / 'BUILD-RECEIPT.json').write_text(json.dumps(audit, indent=2) + '\n')
    return target, audit


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'dist/releases/photo-light-boot-review-20261013')
    args = parser.parse_args()
    target, audit = package(args.output.resolve())
    print(json.dumps({'zip': str(target), **audit}, indent=2))

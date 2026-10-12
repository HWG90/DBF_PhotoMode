"""Photo Mode-owned decorative assets; builds use only the local vendor directory.

Keep the established mapped material and shader identities. These untextured
overlays require no HUD Lua, fonts, image atlases or additional mod. The registry
starts with the original game's 77 default shader references and adds exactly
the 40 owned libraries. A different mod replacing default_shaders must merge
registrations: archive stacking alone cannot guarantee coexistence.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'freecam/assets/shaders'
GROUP_NAME = 'core/stingray_renderer/shader_libraries/default_shaders'
MAX_RESOURCES = 100000
MAX_PAYLOAD = 64 * 1024 * 1024


def hash64(name):
    data = name.encode('ascii')
    mask, mix = (1 << 64) - 1, 0xc6a4a7935bd1e995
    value = len(data) * mix & mask
    end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack('<Q', data[:end]):
        word = word * mix & mask
        word ^= word >> 47
        value = (value ^ (word * mix & mask)) * mix & mask
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], 'little')) * mix & mask
    value ^= value >> 47
    value = value * mix & mask
    return value ^ (value >> 47)


SHADER = hash64('shader_library')
MATERIAL = hash64('material')
GROUP = hash64('shader_library_group')
LUA = hash64('lua')


def sha256(body):
    return hashlib.sha256(body).hexdigest()


def archive_index(body, gpu_size=0, stream_size=0):
    """Read bounded native table rows without loading a large GPU companion."""
    if len(body) < 72:
        raise ValueError('Native archive header missing')
    magic, types, count = struct.unpack_from('<III', body)
    if magic != 0xf0000011 or types > 128 or count > MAX_RESOURCES:
        raise ValueError('Unsupported native archive header')
    start = 72 + types * 32
    end = start + count * 80
    if end > len(body):
        raise ValueError('Native archive table exceeds CPU bytes')
    kinds = list(struct.iter_unpack('<IIQIIII', body[72:start]))
    rows = list(struct.iter_unpack('<7Q6I', body[start:end]))
    if len({row[2] for row in kinds}) != types:
        raise ValueError('Duplicate native type table entries')
    if len({row[:2] for row in rows}) != count:
        raise ValueError('Duplicate native resource identities')
    if Counter(row[1] for row in rows) != Counter({row[2]: row[3] for row in kinds}):
        raise ValueError('Native type counts differ from resource table')
    for row in rows:
        for offset, size, total in ((row[2], row[7], len(body)),
                                    (row[3], row[8], stream_size),
                                    (row[4], row[9], gpu_size)):
            if size > MAX_PAYLOAD or offset + size > total:
                raise ValueError('Native resource exceeds payload bounds')
        if row[2] < end or row[10] not in (16, 256) or row[2] % row[10]:
            raise ValueError('Invalid native CPU resource alignment')
        if row[11] not in (16, 64, 256) or (row[9] and row[4] % row[11]):
            raise ValueError('Invalid native GPU resource alignment')
    return rows


def read_archive(body, gpu=b'', stream=b''):
    rows = archive_index(body, len(gpu), len(stream))
    if any(row[8] for row in rows):
        raise ValueError('Streamed assets are not part of Photo Mode')
    return [(row[0], row[1], body[row[2]:row[2] + row[7]],
             gpu[row[4]:row[4] + row[9]]) for row in rows]


def archive_rows(resources):
    """Serialize mixed native/Lua resources with verified CPU/GPU bounds."""
    resources = sorted(resources, key=lambda row: (row[1], row[0]))
    if not resources or len(resources) > MAX_RESOURCES:
        raise ValueError('Invalid native resource count')
    if len({row[:2] for row in resources}) != len(resources):
        raise ValueError('Duplicate native resource identities')
    kinds = sorted({row[1] for row in resources})
    body = bytearray((72 + 32 * len(kinds) + 80 * len(resources) + 15) & ~15)
    external, table = bytearray(), bytearray()
    cpu_buffer = gpu_buffer = 0
    for index, (name, kind, main, gpu) in enumerate(resources):
        if not isinstance(main, bytes) or not isinstance(gpu, bytes):
            raise ValueError('Native resource payload must be bytes')
        if len(main) > MAX_PAYLOAD or len(gpu) > MAX_PAYLOAD:
            raise ValueError('Native resource payload too large')
        alignment = 256 if kind == SHADER else 16
        body += b'\0' * (-len(body) % alignment)
        table += struct.pack('<7Q6I', name, kind, len(body), 0, len(external),
                             cpu_buffer, gpu_buffer if gpu else 0,
                             len(main), 0, len(gpu), alignment, 256 if gpu else 16, index)
        cpu_buffer += (len(main) + 255) & ~255
        if gpu:
            gpu_buffer += (len(gpu) + 255) & ~255
        body += main
        body += b'\0' * (-len(body) % 16)
        external += gpu
        external += b'\0' * (-len(external) % 256)
    header = struct.pack('<III20sQQ24s', 0xf0000011, len(kinds), len(resources),
                         b'', cpu_buffer, gpu_buffer, b'')
    types = b''.join(struct.pack('<IIQIIII', 0, 0, kind,
                                sum(row[1] == kind for row in resources), 0,
                                256 if kind == SHADER else 16,
                                256 if kind == SHADER else 64 if kind == GROUP else 16)
                     for kind in kinds)
    body[:len(header + types + table)] = header + types + table
    result = bytes(body), bytes(external)
    if read_archive(*result) != resources:
        raise ValueError('Native archive payload round-trip failed')
    return result


def _manifest(asset_root=None):
    folder = Path(asset_root or ASSETS)
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['schema'] != 1 or len(manifest['overlays']) != 40:
        raise ValueError('Photo decorative asset manifest invalid')
    return folder, manifest


def _blob(folder, spec):
    name = spec['file']
    if Path(name).name != name:
        raise ValueError('Photo vendor path must be a leaf filename')
    body = (folder / name).read_bytes()
    if len(body) != spec['bytes'] or sha256(body) != spec['sha256']:
        raise ValueError('Photo vendor bytes differ: ' + name)
    return body


def load_resources(asset_root=None):
    folder, manifest = _manifest(asset_root)
    resources = []
    for overlay in manifest['overlays']:
        resources.append((hash64(overlay['material']), MATERIAL,
                          _blob(folder, overlay['material_cpu']), b''))
        resources.append((hash64(overlay['shader']), SHADER,
                          _blob(folder, overlay['shader_cpu']),
                          _blob(folder, overlay['shader_gpu'])))
    return resources


def registry_ids(body):
    if len(body) < 24:
        raise ValueError('Shader registry header missing')
    count = struct.unpack_from('<I', body, 16)[0]
    if count > 10000 or len(body) != 24 + count * 8:
        raise ValueError('Shader registry length/count invalid')
    ids = struct.unpack_from('<' + str(count) + 'Q', body, 24)
    if len(set(ids)) != count:
        raise ValueError('Shader registry contains duplicate IDs')
    return ids


def registry_resource(asset_root=None):
    folder, manifest = _manifest(asset_root)
    base = _blob(folder, manifest['original_registry'])
    ids = list(registry_ids(base))
    if len(ids) != 77:
        raise ValueError('Original game shader registry must contain 77 IDs')
    added = [hash64(overlay['shader']) for overlay in manifest['overlays']]
    if set(ids) & set(added) or len(set(added)) != 40:
        raise ValueError('Photo shader registry identities collide')
    header = bytearray(base[:24])
    struct.pack_into('<I', header, 16, len(ids) + len(added))
    group = bytes(header) + struct.pack('<117Q', *(ids + added))
    return hash64(GROUP_NAME), GROUP, group, b''


def _dxbc_windows(gpu):
    windows, position = [], 0
    while True:
        position = gpu.find(b'DXBC', position)
        if position < 0:
            return windows
        if position + 32 > len(gpu):
            raise ValueError('Truncated shader DXBC header')
        size = struct.unpack_from('<I', gpu, position + 24)[0]
        if size < 32 or position + size > len(gpu):
            raise ValueError('Shader DXBC exceeds library bounds')
        windows.append((position, size))
        position += size


def validate_assets(asset_root=None):
    folder, manifest = _manifest(asset_root)
    resources = load_resources(folder)
    if len(resources) != 80 or len({row[:2] for row in resources}) != 80:
        raise ValueError('Photo native asset closure must have exactly 80 resources')
    variants = []
    for overlay in manifest['overlays']:
        material = _blob(folder, overlay['material_cpu'])
        gpu = _blob(folder, overlay['shader_gpu'])
        _blob(folder, overlay['hlsl'])
        if not overlay['hlsl_validation']['instruction_reflection_and_signature_sections_match']:
            raise ValueError('Photo HLSL does not describe its preserved pixel program')
        variant = hash64(overlay['shader']) >> 32
        if len(material) != 144 or struct.unpack_from('<I', material, 128)[0] != variant:
            raise ValueError('Photo material shader variant mismatch: ' + overlay['id'])
        if material[132:] != b'\0' * 12:
            raise ValueError('Photo material has unexpected texture binding')
        windows = _dxbc_windows(gpu)
        if len(windows) != 2 or struct.unpack_from('<I', gpu, 0xe0)[0] != variant:
            raise ValueError('Photo shader library variant/DXBC mismatch')
        program = hash64(overlay['shader'] + ':default:PLATFORM_WIN32:RENDERER_D3D11') >> 32
        if struct.unpack_from('<I', gpu, 0x88)[0] != program:
            raise ValueError('Photo shader program identity mismatch')
        variants.append({'id': overlay['id'], 'material': overlay['material'],
                         'shader': overlay['shader'], 'variant_id': f'{variant:08x}',
                         'material_sha256': sha256(material), 'shader_gpu_sha256': sha256(gpu),
                         'hlsl_sha256': overlay['hlsl']['sha256'], 'dxbc_programs': len(windows)})
    group = registry_resource(folder)
    ids = registry_ids(group[2])
    if set(ids[77:]) != {row[0] for row in resources if row[1] == SHADER}:
        raise ValueError('Photo shader registry/resource closure differs')
    return {'passed': True, 'materials': 40, 'shader_libraries': 40,
            'additional_textures': 0, 'additional_fonts': 0, 'streamed_resources': 0,
            'original_shader_registrations': 77, 'photo_shader_registrations': 40,
            'total_shader_registrations': len(ids), 'registry_sha256': sha256(group[2]),
            'original_registry_sha256': manifest['original_registry']['sha256'],
            'manifest_sha256': sha256((folder / 'manifest.json').read_bytes()),
            'overlays': variants, 'live_validation': False,
            'coexistence_limit': manifest['coexistence_limit']}


def validate_archive(body, gpu=b'', include_registry=False, asset_root=None):
    """Require all owned native bytes; permit a BSL Lua bootstrap alongside them."""
    audit = validate_assets(asset_root)
    actual = {row[:2]: row for row in read_archive(body, gpu)}
    expected = load_resources(asset_root)
    if include_registry:
        expected.append(registry_resource(asset_root))
    for row in expected:
        if actual.get(row[:2]) != row:
            raise ValueError('Bundled native asset missing or changed: ' + hex(row[0]))
    extras = [row for key, row in actual.items() if key not in {r[:2] for r in expected}]
    if any(row[1] != LUA for row in extras):
        raise ValueError('Unexpected native resource bundled with Photo Mode')
    audit.update({'archive_resources': len(actual), 'extra_lua_resources': len(extras),
                  'cpu_sha256': sha256(body), 'gpu_sha256': sha256(gpu),
                  'registry_included': include_registry})
    return audit

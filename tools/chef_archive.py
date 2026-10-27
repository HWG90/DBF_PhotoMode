"""Minimal Lua-source patch codec for the Chef addon build (no game IO).

Parts adapted from Chef Shared Loader by Th3chef
Source: tools/hd2_patch.py and tools/pack_addon.py at
debc6aaa7840eb645b9773a55fa1d42c7b7ee00e; see chef-LICENSE.txt.
"""
import struct

MAGIC = 0xF0000011
LUA = 0xA14E8DFA2CD117E2
HEADER = bytes.fromhex(
    '0000000000000000000000000000000000000000ea7b0000000000000000'
    '000000000000000000000000000000000000000000000000000000000000')


def resource_hash(name):
    data = name.encode('utf-8')
    mask, mix = (1 << 64) - 1, 0xC6A4A7935BD1E995
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


def pack(resource, source):
    data = struct.pack('<II', len(source), 2) + source
    header = struct.pack('<III', MAGIC, 1, 1) + HEADER
    header += struct.pack('<QQQII', 0, LUA, 1, 16, 16)
    offset = (len(header) + 80 + 15) // 16 * 16
    row = struct.pack('<7Q6I', resource_hash(resource), LUA, offset, 0, 0, 0, 0,
                      len(data), 0, 0, 16, 16, 0)
    patch = (header + row).ljust(offset, b'\0') + data
    return patch + b'\0' * (-len(patch) % 16)


def unpack(patch, resource):
    assert len(patch) >= 200 and len(patch) % 16 == 0, 'Invalid Lua archive size'
    assert struct.unpack_from('<III', patch) == (MAGIC, 1, 1), 'Expected exactly one Lua resource'
    assert patch[12:72] == HEADER, 'Unexpected engine header'
    assert struct.unpack_from('<QQQII', patch, 72) == (0, LUA, 1, 16, 16)
    row = struct.unpack_from('<7Q6I', patch, 104)
    fid, tid, offset, stream, gpu, a, b, size, ssize, gsize, x, y, index = row
    assert (fid, tid) == (resource_hash(resource), LUA), 'Unexpected resource (boot is never shipped)'
    assert (stream, gpu, a, b, ssize, gsize, x, y, index) == (0, 0, 0, 0, 0, 0, 16, 16, 0)
    assert offset >= 184 and offset % 16 == 0 and size >= 8 and offset + size <= len(patch)
    length, flag = struct.unpack_from('<II', patch, offset)
    assert flag == 2 and length == size - 8, 'Only source Lua is supported'
    assert not any(patch[184:offset]) and not any(patch[offset + size:])
    return patch[offset + 8:offset + size]


def pack_candidate(resource, source):
    """One source Lua resource plus WJ's exact self-contained point-light unit."""
    import photo_assets
    import photo_light_assets
    lua = (resource_hash(resource), LUA, struct.pack('<II', len(source), 2) + source, b'')
    patch, gpu = photo_assets.archive_rows([lua, photo_light_assets.resource()])
    assert not gpu
    return patch


def unpack_candidate(patch, resource):
    import photo_assets
    import photo_light_assets
    rows = photo_assets.read_archive(patch)
    other = photo_light_assets.split_bundled_resources(rows)
    assert len(rows) == 2 and len(other) == 1, 'Expected one addon and one owned light unit'
    fid, tid, body, gpu = other[0]
    assert (fid, tid) == (resource_hash(resource), LUA) and not gpu, 'Unexpected addon resource'
    assert len(body) >= 8
    length, flag = struct.unpack_from('<II', body)
    assert flag == 2 and length == len(body) - 8, 'Only source Lua is supported'
    assert photo_assets.archive_rows(rows) == (patch, b''), 'Noncanonical or hidden archive data'
    return body[8:]

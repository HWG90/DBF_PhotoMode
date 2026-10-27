"""Offline local-depth binding candidate; does not install or run the game.

The GUI image parameter diffuse_map may be rebound by retained GUI drawing.
Give depth a private parameter name while preserving local category, declaration
index, GPU slots, both programs, and the working global color binding. This is a
testable hypothesis, not proof that the GUI currently overwrites that parameter.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct

import photo_assets as assets
from build_windows_global_depth import build
from build_windows_indexed_depth import verify_texture_declarations

PARAMETER = 'wjl_scene_depth'
CONTRACT = 'private-local-v1'


def convert(gpu, material, suffix):
    original = bytes(gpu)
    body = bytearray(original)
    tail = len(body) - 120
    windows = assets._dxbc_windows(original)
    assert windows[0] == (0xff0, 5160) and windows[1][0] == 0x2468
    assert windows[1][0] + windows[1][1] == tail
    u = lambda at: struct.unpack_from('<I', original, at)[0]
    old = assets.hash64('diffuse_map') >> 32
    depth = assets.hash64(PARAMETER) >> 32
    color = assets.hash64('output_target') >> 32
    assert (u(0xf18), u(0xf20), u(0xf28)) == (6, old, 0)
    assert (u(0xf30), u(0xf38), u(0xf40)) == (5, color, 1)
    before = verify_texture_declarations(original, 0x5c8, 6, [tail+56, tail+72])
    assert [row['declaration_index'] for row in before] == [3, 4]
    offsets = (0x5ec, 0xf20, tail+56, tail+88)
    assert all(u(at) == old for at in offsets)
    identity = hashlib.sha256(original + b':private-local-depth-v1').hexdigest()[:16]
    shader = 'mods/dbf_photo/shaders/windows_private_depth_' + identity
    name = 'mods/dbf_photo/materials/windows_private_depth_' + identity
    allowed = set()

    def put(at, value):
        struct.pack_into('<I', body, at, value)
        allowed.update(range(at, at+4))

    for at in offsets:
        put(at, depth)
    identities = {u(0x88): assets.hash64(shader+':default:PLATFORM_WIN32:RENDERER_D3D11') >> 32,
                  u(0xe0): assets.hash64(shader) >> 32,
                  u(0xbec): assets.hash64(shader+':pixel') >> 32}
    counts = dict.fromkeys(identities, 0)
    for at in range(0, len(body)-3, 4):
        if any(start <= at < start+size for start, size in windows):
            continue
        if u(at) in identities:
            put(at, identities[u(at)])
            counts[u(at)] += 1
    assert sorted(counts.values()) == [1, 2, 2]
    assert all(at in allowed for at, (a, b) in enumerate(zip(original, body)) if a != b)
    assert all(body[start:start+size] == original[start:start+size] for start, size in windows)
    after = verify_texture_declarations(body, 0x5c8, 6, [tail+56, tail+72])
    assert after[0] == dict(before[0], name=f'{depth:08x}')
    assert after[1] == before[1]
    assert struct.unpack_from('<I', body, 0xf18)[0] == 6
    mat = bytearray(material)
    assert len(mat) == 144 and struct.unpack_from('<I', mat, 128)[0] == u(0xe0)
    struct.pack_into('<I', mat, 128, identities[u(0xe0)])
    return shader, name, bytes(body), bytes(mat), {
        'source_suffix': suffix, 'source_gpu_sha256': hashlib.sha256(original).hexdigest(),
        'shader': shader, 'material': name, 'gpu_sha256': hashlib.sha256(body).hexdigest(),
        'parameter': PARAMETER, 'binding_contract': CONTRACT, 'bindings': after,
        'local_category': 6, 'both_dxbc_stages_unchanged': True,
        'global_color_binding_unchanged': True, 'live_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    receipt = build(args.source, args.output, converter=convert)
    receipt['binding_contract'] = CONTRACT
    receipt['parameter'] = PARAMETER
    (args.output.parent/'PRIVATE-DEPTH.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'registry'}, indent=2))

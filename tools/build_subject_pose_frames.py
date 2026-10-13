"""Reproducibly sample three authored poses offline; never access a game process.

The exact decoder in subject_pose_decoder.lua is copied from Epic-LUT
src/preview/player_authored_clip.lua at 9d4f69e9a67f68124cf2b3aeb50425eab797e57e.
Copyright (C) 2026 HWG90, Zero-Clause BSD. Format reference: HD2SDK Community
Edition 5a886256e54db52b5d228335eae20ce796f87fc0. Game resources are build inputs
only, supplied with --cache; the runtime module has no cache/decoder dependency.
"""
import argparse
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DECODER = Path(__file__).with_name('subject_pose_decoder.lua')
DECODER_SHA = '268e6e3629c2c9dd6d2aca8f0a9b90d4bfbccaa5ab9efb942cca23ef817783a0'
DEFAULT_CACHE = ROOT.parent / 'Epic-LUT/dist/review/preview-poses-20261010/runtime-cache-v2/6E3A4E8C89BE8D376F34B8118FAFE3048756B96B7BDF3F3110306193B7B0945F'
DEFAULT_OUTPUT = ROOT / 'freecam/assets/subject_pose_frames.lua'
FILES = {
    'unit': '4d1c334d294dfa97.e0a48d0be9a7453f.bin',
    'bones': '4d1c334d294dfa97.18dead01056b72e9.bin',
    'standing': '759c08277f1296d0.931e336d7646cc26.bin',
    'enter': '070b422612518deb.931e336d7646cc26.bin',
    'hold': 'e32b270524630569.931e336d7646cc26.bin',
    'exit': '39250e5b6313a0b2.931e336d7646cc26.bin',
    'wave': 'f7d81dbe0142b9ee.931e336d7646cc26.bin',
    'taunt': 'a4950a590f729419.931e336d7646cc26.bin',
    'highfive': '75205314048dcdaa.931e336d7646cc26.bin',
}
POSES = {'salute': ('Salute', 'hold', 0), 'wave': ('Wave', 'wave', .58), 'taunt': ('Taunt', 'taunt', .4)}

# This extension runs inside the unchanged decoder's lexical scope. It exposes
# the exact per-node local matrix before FK, and the original sampler output.
EXTENSION = r'''
function Clip.subject_frames(folder)
 local set=Clip.load(folder);local out={};local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v)end;out[#out+1]=table.concat(t,'\t')end
 local function vector(v)local t={};for i,x in ipairs(v)do t[i]=string.format('%.17g',x)end;return table.concat(t,',')end
 row('R',#set.nodes,#set.names)
 for i,node in ipairs(set.nodes)do row('N',i,node.parent,node.bone or 0,node.name or '')end
 for _,id in ipairs({'salute','wave','taunt'})do
  local spec=Clip.find_pose(id);local clip=set.clips[spec.clip];local original=Clip.sample(set,0,id)
  row('P',id,spec.clip,string.format('%.17g',spec.time),string.format('%.17g',clip.duration))
  for i,node in ipairs(set.nodes)do
   local local_pose=node.rest
   if node.bone then local b=clip.channels[node.bone];local_pose=matrix(curve(b.p,spec.time),curve(b.q,spec.time,true),curve(b.s,spec.time))end
   local p,q,s=Clip.pose(local_pose)
   row('T',id,i,vector(p),vector(q),vector(s),vector(local_pose),node.name and vector(original[node.name])or '')
  end
 end
 return table.concat(out,'\n')
end
return Clip
'''


def lua_result(source, dll):
    """Isolated LuaJIT DLL: no attach, remote memory, SDK or live bridge."""
    lua = ctypes.CDLL(str(dll))
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype = ctypes.c_void_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    assert state, 'Cannot allocate isolated Lua state'
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadbuffer(state, source, len(source), b'subject-pose-frame-generator')
        if not status:
            status = lua.lua_pcall(state, 0, 1, 0)
        length = ctypes.c_size_t()
        pointer = lua.lua_tolstring(state, -1, ctypes.byref(length))
        result = ctypes.string_at(pointer, length.value).decode() if pointer else ''
        assert status == 0, result
        return result
    finally:
        lua.lua_close(state)


def multiply(a, b):
    return [sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)) for r in range(4) for c in range(4)]


def matrix(p, q, s):
    x, y, z, w = q
    m = [1-2*(y*y+z*z), 2*(x*y+z*w), 2*(x*z-y*w), 0,
         2*(x*y-z*w), 1-2*(x*x+z*z), 2*(y*z+x*w), 0,
         2*(x*z+y*w), 2*(y*z-x*w), 1-2*(x*x+y*y), 0, *p, 1]
    for r in range(3):
        for c in range(3):
            m[r * 4 + c] *= s[r]
    return m


def parse_and_validate(text):
    rig, poses, locals_ref, model_ref = {}, {}, {}, {}
    for line in text.splitlines():
        row = line.split('\t')
        if row[0] == 'R':
            assert row[1:] == ['107', '90'], 'Captured rig layout changed'
        elif row[0] == 'N':
            i, parent, bone = map(int, row[1:4])
            assert 1 <= i <= 107 and 0 <= parent < i and 0 <= bone <= 90
            assert i not in rig
            rig[i] = {'parent': parent}
            if row[4]:
                rig[i].update(name=row[4], bone=bone)
            else:
                assert bone == 0
        elif row[0] == 'P':
            id, clip, at, duration = row[1], row[2], float(row[3]), float(row[4])
            label, expected_clip, expected_time = POSES[id]
            assert clip == expected_clip and at == expected_time and 0 <= at <= duration < 60
            poses[id] = {'label': label, 'resource': FILES[clip].split('.')[0], 'time': at, 'duration': duration, 'nodes': {}}
            locals_ref[id], model_ref[id] = {}, {}
        elif row[0] == 'T':
            id, i = row[1], int(row[2])
            p, q, s, local = [[float(v) for v in field.split(',')] for field in row[3:7]]
            assert [len(p), len(q), len(s), len(local)] == [3, 4, 3, 16]
            assert all(math.isfinite(v) for v in p+q+s+local)
            assert max(map(abs, p)) < 100000 and all(1e-6 < v <= 128 for v in s)
            assert abs(sum(v*v for v in q)-1) < 1e-10, 'Quaternion is not normalized'
            poses[id]['nodes'][i] = {'p': p, 'q': q, 's': s}
            locals_ref[id][i] = local
            if row[7]:
                model_ref[id][i] = [float(v) for v in row[7].split(',')]
    assert len(rig) == 107 and sum('name' in n for n in rig.values()) == 90
    assert len({n['name'] for n in rig.values() if 'name' in n}) == 90
    assert {n['bone'] for n in rig.values() if 'bone' in n} == set(range(1, 91))
    assert set(poses) == set(POSES)
    assert rig[1]['name'] == 'StingrayEntityRoot' and rig[5]['name'] == 'root'
    assert rig[8]['name'] == 'boss' and rig[8]['parent'] == 5 and rig[10]['name'] == 'hips' and rig[10]['parent'] == 8
    maximum = 0.0
    for id, pose in poses.items():
        assert len(pose['nodes']) == 107 and len(model_ref[id]) == 90
        world = {}
        for i in range(1, 108):
            node = pose['nodes'][i]
            local = matrix(node['p'], node['q'], node['s'])
            assert max(abs(a-b) for a, b in zip(local, locals_ref[id][i])) < 1e-5, 'PQS roundtrip changed local transform'
            parent = rig[i]['parent']
            world[i] = multiply(local, world[parent]) if parent else local
            if i in model_ref[id]:
                error = max(abs(a-b) for a, b in zip(world[i], model_ref[id][i]))
                maximum = max(maximum, error)
                assert error < 1e-5, 'Rebuilt local hierarchy differs from original sampled model pose'
    return rig, poses, maximum


def lua_value(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        assert math.isfinite(value)
        return format(value, '.17g')
    if isinstance(value, list):
        return '{' + ','.join(lua_value(v) for v in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('['+lua_value(k)+']='+lua_value(v) for k, v in value.items()) + '}'
    raise TypeError(type(value))


def build(cache, output, dll, check=False):
    decoder = DECODER.read_bytes()
    assert hashlib.sha256(decoder).hexdigest() == DECODER_SHA, 'Pinned decoder changed'
    # Normalize only for lexical insertion; provenance hashes the exact copy.
    source = decoder.decode().replace('\r\n', '\n')
    assert source.endswith('return Clip\n')
    source = source[:-len('return Clip\n')] + EXTENSION
    hashes = {name: hashlib.sha256((cache / name).read_bytes()).hexdigest() for name in FILES.values()}
    chunk = ('local Clip=(function()\n'+source+'\nend)()\nreturn Clip.subject_frames('+lua_value(cache.resolve().as_posix())+')').encode()
    rig, poses, error = parse_and_validate(lua_result(chunk, dll))
    result = {'version': 1, 'build': {'game_timestamp': 0x6AB3B43F, 'exe_timestamp': 0x6AB382E4},
              'rig': {'resource': '4d1c334d294dfa97', 'node_count': 107, 'bone_count': 90, 'nodes': rig},
              'poses': poses, 'provenance': {'decoder_sha256': DECODER_SHA,
              'decoder_source': 'Epic-LUT/src/preview/player_authored_clip.lua',
              'decoder_revision': '9d4f69e9a67f68124cf2b3aeb50425eab797e57e',
              'sdk_revision': '5a886256e54db52b5d228335eae20ce796f87fc0', 'resource_sha256': hashes}}
    header = '-- Generated by tools/build_subject_pose_frames.py; local PQS frames, not animation events.\n-- 1-based scene-node indexes and parents; preserve live placement anchors and restore borrowed poses.\n'
    body = header + 'return {\n' + ',\n'.join(' ['+lua_value(k)+']='+lua_value(v) for k, v in result.items()) + '\n}\n'
    # Parse the emitted module in the isolated interpreter as a final syntax/count check.
    loaded = lua_result(('local d=(function()\n'+body+'\nend)();assert(d.rig.node_count==107 and #d.rig.nodes==107);for _,id in ipairs({"salute","wave","taunt"})do assert(#d.poses[id].nodes==107)end;return "ok"').encode(), dll)
    assert loaded == 'ok'
    encoded = body.encode()
    if check:
        assert output.read_bytes() == encoded, 'Generated pose frame module differs'
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(encoded)
    print(json.dumps({'output': str(output), 'poses': list(poses), 'nodes': 107, 'bones': 90,
                      'max_fk_error': error, 'sha256': hashlib.sha256(encoded).hexdigest(), 'check': check}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=DEFAULT_CACHE, help='Explicit directory containing the exact nine decoded resources')
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--lua-dll', type=Path, default=Path(os.environ.get('HD2_LUA51_DLL', 'C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/lua51.dll')))
    parser.add_argument('--check', action='store_true', help='Validate inputs and compare without rewriting output')
    args = parser.parse_args()
    build(args.cache, args.output, args.lua_dll, args.check)

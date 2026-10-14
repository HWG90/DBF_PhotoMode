"""Pin supported ActionCam Lua closures without loading them in the game."""
import ctypes
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def archive_source(path):
    from lua_archive import LUA_TYPE, hash_name, read
    archive = Path(path).read_bytes()
    kind, body = read(archive)[hash_name('mods/actioncam/actioncam')]
    assert kind == LUA_TYPE and len(body) > 8
    source = body[8:].rstrip(b'\0')
    assert source.startswith(b'-- HD2-Addon: mods/actioncam/actioncam')
    return source, hashlib.sha256(archive).hexdigest()


def generate(source=None, vendor_version='2.3.1', runtime_version='10.31'):
    source = source if source is not None else (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
    assert ("CFG.VERSION = '"+runtime_version+"'").encode() in source
    library = Path(os.environ.get('HD2_LUA51_DLL', 'C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/lua51.dll'))
    lua = ctypes.CDLL(str(library))
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_getfield.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    script = b'local SOURCE=[====[' + source + b']====]\n' + br'''
local function up(fn,wanted)
 for i=1,120 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==wanted then return value end end
end
local env=setmetatable({stingray={Vector3={},Matrix4x4={}},io={open=function()return nil end},os={getenv=function()return nil end,remove=function()end,rename=function()end,date=function()return ''end},update=function()end,render=function()end},{__index=_G});env._G=env
local chunk=assert(loadstring(SOURCE,'@mods/actioncam/actioncam'));setfenv(chunk,env);chunk()
local step=assert(up(env.update,'step'));local hook=assert(up(step,'hook_render'));local apply=assert(up(hook,'apply'))
local records={{'update',env.update},{'step',step},{'hook_render',hook},{'apply',apply},{'bindings_step',assert(up(step,'bindings_step'))},{'restore_fov',assert(up(apply,'restore_fov'))},{'drop_all',assert(up(apply,'drop_all'))}}
local result={}
for _,record in ipairs(records)do
 local bytes=string.dump(record[2],true)
 local hex=bytes:gsub('.',function(byte)return string.format('%02x',byte:byte())end)
 result[#result+1]=record[1]..'='..hex
end
ACTIONCAM_SIGNATURE_RESULT=table.concat(result,'\n')
'''
    state = lua.luaL_newstate()
    assert state
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadbuffer(state, script, len(script), b'ActionCam-signatures')
        if status == 0:
            status = lua.lua_pcall(state, 0, 0, 0)
        if status:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        lua.lua_getfield(state, -10002, b'ACTIONCAM_SIGNATURE_RESULT')
        body = lua.lua_tolstring(state, -1, None).decode()
        return {'source_sha256': hashlib.sha256(source).hexdigest(), 'vendor_version': vendor_version,
                'runtime_version': runtime_version, 'closures': dict(line.split('=', 1) for line in body.splitlines())}
    finally:
        lua.lua_close(state)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,help='Locally supplied original ActionCam 2.4 archive; source is never copied into the release')
    args=parser.parse_args()
    result = generate()
    target = ROOT / 'freecam/vendor/actioncam-signatures.json'
    previous=json.loads(target.read_text(encoding='utf-8')) if target.exists() else {}
    result['supported']=previous.get('supported',{})
    result['supported']['10.31']={key:value for key,value in result.items() if key!='supported'}
    if args.archive:
        source,archive_hash=archive_source(args.archive)
        record=generate(source,'2.4','10.32')
        record.update(archive_sha256=archive_hash,resource_name='mods/actioncam/actioncam',source_url='https://www.nexusmods.com/helldivers2/mods/16752?tab=files&file_id=68485',nexus_file_id=68485,source_bundled=False)
        result['supported']['10.32']=record
    target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Pinned ActionCam runtime versions:', ', '.join(result['supported']))

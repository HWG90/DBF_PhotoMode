"""Pin supported ActionCam Lua closures without loading them in the game."""
import ctypes
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate():
    source = (ROOT / 'freecam/vendor/actioncam-2.3.1.lua').read_bytes()
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
        return {'source_sha256': hashlib.sha256(source).hexdigest(), 'vendor_version': '2.3.1',
                'runtime_version': '10.31', 'closures': dict(line.split('=', 1) for line in body.splitlines())}
    finally:
        lua.lua_close(state)


if __name__ == '__main__':
    result = generate()
    target = ROOT / 'freecam/vendor/actioncam-signatures.json'
    target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Pinned', len(result['closures']), 'ActionCam closures; source', result['source_sha256'])

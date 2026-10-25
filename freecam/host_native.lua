-- Normal Lua 5.1 extension: no LuaJIT or CFFI dependency.
local M={};local native
-- Folder installs keep the bridges in port51/; the archive build sets mod.native_dir.
function M.library(name)return(mod.native_dir or mod.dir..'/port51')..'/'..name end
function M.open()
 if not native then
  local open,why=package.loadlib(M.library('hd2_nativeinfo_f6d3465944c1aea1.dll'),'luaopen_hd2_nativeinfo')
  assert(open,why);native=assert(open(),'War Journalist native bridge refused this host')
  for _,name in ipairs({'function_address','userdata_address','read_memory','module_base'})do assert(type(native[name])=='function','Native bridge API differs: '..name)end
 end
 return native
end
function M.memory()
 local bridge=M.open()
 local memory={game=bridge.module_base('game.dll'),exe=bridge.module_base('helldivers2.exe'),read=bridge.read_memory,function_address=bridge.function_address}
 function memory.handle_ref(handle)return math.floor(bridge.userdata_address(handle)/4)end
 function memory.world_address(world)
  local bytes=memory.read(bridge.userdata_address(world),8)
  local a,b,c,d,e,f,g,h=bytes:byte(1,8)
  return a+b*256+c*65536+d*16777216+(e+f*256+g*65536+h*16777216)*4294967296
 end
 return memory
end
return M

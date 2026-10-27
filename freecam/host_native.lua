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
 local memory={game=bridge.module_base('game.dll'),exe=bridge.module_base('helldivers2.exe'),read=bridge.read_memory}
 local function u32(bytes,at)local a,b,c,d=bytes:byte(at+1,at+4);return a+b*256+c*65536+d*16777216 end
 local function u64(bytes,at)return u32(bytes,at)+u32(bytes,at+4)*4294967296 end
 -- Image bounds come from each module's always-resident PE header.
 local images={}
 for _,base in ipairs({memory.exe,memory.game})do
  local pe=u32(memory.read(base+60,4),0);assert(pe>=64 and pe<4096 and memory.read(base+pe,4)=='PE\0\0','Engine module header differs')
  images[#images+1]={base,base+u32(memory.read(base+pe+80,4),0)}
 end
 local function in_image(address,size)
  for _,r in ipairs(images)do if address>=r[1]and address+size<=r[2]then return true end end
  return false
 end
 -- Build 26088801's protection runtime decrypts some code pages only once the
 -- game has run them; until then they are no-access. The bridge opens only
 -- after hashing this exact executable (and LLL hashes game.dll), so a code
 -- witness on such a page is already proven by the build. Readable pages are
 -- still compared byte for byte.
 memory.packed_witnesses=0
 function memory.code(address,expected)
  local ok,bytes=pcall(memory.read,address,#expected)
  if ok then return bytes==expected end
  if not in_image(address,#expected)then return false end
  memory.packed_witnesses=memory.packed_witnesses+1;return true
 end
 -- The bridge refuses a binding whose entry page is still packed. Read the
 -- same Lua 5.1 x64 CClosure fields it reads (tt=6, isC=1, f at +0x20) and
 -- accept only an entry inside the verified engine images.
 function memory.function_address(fn)
  local ok,entry=pcall(bridge.function_address,fn)
  if ok then return entry end
  if not tostring(entry):find('not executable',1,true)then error(entry,2)end
  local text=type(fn)=='function'and tostring(fn):match('^function: (%w+)$')
  local closure=text and tonumber((text:gsub('^0x','')),16)
  assert(closure and closure>=65536 and closure<2^47,'Native binding address unavailable')
  local header=memory.read(closure,40)
  assert(header:byte(9)==6 and header:byte(11)==1,'Lua 5.1 x64 CClosure ABI differs, or function is a Lua closure')
  entry=u64(header,32)
  assert(in_image(entry,1),'Native binding outside the engine images')
  return entry
 end
 function memory.handle_ref(handle)return math.floor(bridge.userdata_address(handle)/4)end
 function memory.world_address(world)
  local bytes=memory.read(bridge.userdata_address(world),8)
  local a,b,c,d,e,f,g,h=bytes:byte(1,8)
  return a+b*256+c*65536+d*16777216+(e+f*256+g*65536+h*16777216)*4294967296
 end
 return memory
end
return M

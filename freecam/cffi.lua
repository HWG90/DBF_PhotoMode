-- Private Lua 5.1/cffi adapter. No process-wide ffi, bit, type or tonumber aliases.
local loaded,ffi=pcall(require,'cffi')
if not loaded then local name='ffi';ffi=require(name)end
local native_type,native_number=type,tonumber
local function userdata_address(value)
 local native=package.loaded.hd2_nativeinfo
 if not native or native_type(native.userdata_address)~='function'then
  local path=assert(mod and mod.dir,'Engine userdata bridge directory unavailable')..'/port51/hd2_nativeinfo_f6d3465944c1aea1.dll'
  local open,why=package.loadlib(path,'luaopen_hd2_nativeinfo');assert(open,why)
  native=assert(open(),'Engine userdata bridge refused current host')
  assert(native_type(native.userdata_address)=='function','Engine userdata bridge API differs')
  package.loaded.hd2_nativeinfo=native
 end
 return native.userdata_address(value)
end
-- CFFI reparses string type arguments. HUD hot paths must retain CType objects
-- rather than invoke that parser for every protected read/vector allocation.
local cast_types,new_types={},{}
local function cached_type(cache,kind)
 if native_type(kind)~='string'then return kind end
 local value=cache[kind]
 if not value then value=ffi.typeof(kind);cache[kind]=value end
 return value
end
local private_ffi=setmetatable({
 cast=function(kind,value,...)
  -- Engine handles are Lua userdata, not CFFI cdata. LuaJIT accepted these
  -- casts; stock CFFI requires the host Lua API to expose their exact address.
  if native_type(value)=='userdata'and not pcall(ffi.typeof,value)then value=userdata_address(value)end
  return ffi.cast(cached_type(cast_types,kind),value,...)
 end,
 new=function(kind,...)return ffi.new(cached_type(new_types,kind),...)end,
},{__index=ffi})
local M={ffi=private_ffi}
function M.number(value,base)
 if base and native_type(value)=='string' then
  assert(base>=2 and base<=36 and base%1==0,'base out of range')
  local sign,digits=value:match('^%s*([+-]?)(%w+)%s*$')
  if not digits then return nil end
  if base==16 then digits=digits:gsub('^0[xX]','')end
  local n=0
  for i=1,#digits do
   local b=digits:lower():byte(i);local digit=b>=48 and b<=57 and b-48 or b>=97 and b<=122 and b-87 or base
   if digit>=base then return nil end
   n=n*base+digit
  end
  return sign=='-' and -n or n
 end
 if base or native_type(value)~='userdata' then return native_number(value,base) end
 local ok,n=pcall(ffi.tonumber,value);if ok then return n end
end
function M.kind(value)
 local k=native_type(value)
 if k=='userdata' and pcall(ffi.typeof,value) then return 'cdata' end
 return k
end
local integers={}
function M.u64(text)
 if integers[text] then return integers[text] end
 local hex=text:match('^0[xX](%x+)$')
 if not hex then
  local n=assert(native_number(text));assert(n>=0 and n<=9007199254740991 and n%1==0)
  local low=n%4294967296;local high=math.floor(n/4294967296)
  hex=string.format('%08x%08x',high,low)
 end
 assert(#hex<=16,'uint64 literal overflow');hex=string.rep('0',16-#hex)..hex
 local bytes={}
 for i=15,1,-2 do bytes[#bytes+1]=string.char(assert(native_number(hex:sub(i,i+1),16))) end
 local value=ffi.new('uint64_t[1]');ffi.copy(value,table.concat(bytes),8)
 integers[text]=value[0];return integers[text]
end
local bit={};M.bit=bit
local U=4294967296
local function unsigned(n)
 if native_type(n)=='userdata'then n=ffi.tonumber(ffi.cast('uint32_t',n))end
 return n%U
end
local function signed(n)n=unsigned(n);return n>=2147483648 and n-U or n end
local function pair(a,b,op)
 a,b=unsigned(a),unsigned(b);local n,p=0,1
 for _=1,32 do
  local x,y=a%2,b%2
  if (op=='and' and x==1 and y==1)or(op=='or' and(x==1 or y==1))or(op=='xor' and x~=y)then n=n+p end
  a,b,p=math.floor(a/2),math.floor(b/2),p*2
 end
 return signed(n)
end
for name,op in pairs({band='and',bor='or',bxor='xor'}) do
 local operation=op
 bit[name]=function(a,b,...)
  local n=pair(a,b,operation)
  for i=1,select('#',...)do n=pair(n,select(i,...),operation)end
  return n
 end
end
function bit.tobit(n)return signed(n)end
function bit.bnot(n)return signed(U-1-unsigned(n))end
function bit.lshift(n,b)b=b%32;return signed((unsigned(n)%2^(32-b))*2^b)end
function bit.rshift(n,b)return math.floor(unsigned(n)/2^(b%32))end
function bit.arshift(n,b)return signed(math.floor(signed(n)/2^(b%32)))end
function bit.ror(n,b)b=b%32;if b==0 then return signed(n)end;return signed(bit.rshift(n,b)+(unsigned(n)%2^b)*2^(32-b))end
function bit.rol(n,b)return bit.ror(n,-b)end
function bit.bswap(n)
 n=unsigned(n);local out=0
 for _=1,4 do out=out*256+n%256;n=math.floor(n/256)end
 return signed(out)
end
function bit.tohex(n,d)
 d=d or 8;local s=string.format('%08x',unsigned(n)):sub(9-math.min(math.abs(d),8))
 return d<0 and s:upper()or s
end
M.jit={off=function()end}
-- Lua 5.1.4 x64 CClosure inspection replaces LuaJIT funcinfo for C bindings only.
-- Object reads are protected; the target must belong to executable committed memory.
function M.inspect_function(fn,read,is_executable)
 assert(_VERSION=='Lua 5.1' and ffi.arch=='x64','Unsupported Lua closure ABI')
 assert(native_type(fn)=='function' and debug.getinfo(fn,'S').what=='C','Native C function required')
 local identity=tostring(fn)
 local hex=identity:match('0[xX](%x+)$') or identity:match('function:%s*(%x+)$')
 local address=assert(hex and M.number(hex,16),'Native closure identity unavailable')
 assert(address>=65536 and address<2^47 and address%8==0,'Invalid native closure identity')
 local bytes=assert(read(address,40),'Native closure is unreadable')
 assert(#bytes==40 and bytes:byte(9)==6 and bytes:byte(11)==1,'Lua 5.1 CClosure header differs')
 local function u32(at)
  local a,b,c,d=bytes:byte(at+1,at+4);return a+b*256+c*65536+d*16777216
 end
 local entry=u32(32)+u32(36)*4294967296
 assert(entry>=65536 and entry<2^47 and is_executable(entry),'Native closure target is not executable')
 return {addr=entry,what='C'}
end
local function_reader,function_executable
local function function_info(fn)
 local native=package.loaded.hd2_nativeinfo
 if not native and tostring(fn)=='[function]' then
  local path=assert(mod and mod.dir,'Native binding module directory unavailable')..'/port51/hd2_nativeinfo_f6d3465944c1aea1.dll'
  local open,why=package.loadlib(path,'luaopen_hd2_nativeinfo')
  assert(open,why);native=assert(open(),'Native binding helper refused current host')
  assert(native_type(native.function_address)=='function','Native binding helper API differs')
  package.loaded.hd2_nativeinfo=native
 end
 if native then return {addr=native.function_address(fn),what='C'}end
 if not function_reader then
  assert(ffi.os=='Windows','Windows protected closure reader required')
  ffi.cdef [[
   typedef struct {
    void *base,*allocation_base; uint32_t allocation_protection;
    uint16_t partition,reserved; size_t size;
    uint32_t state,protection,type;
   } PORT51FN_Region;
   void *PORT51FN_GetCurrentProcess(void) __asm__("GetCurrentProcess");
   int PORT51FN_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");
   size_t PORT51FN_VirtualQuery(const void *,PORT51FN_Region *,size_t) __asm__("VirtualQuery");
  ]]
  local kernel=ffi.load('kernel32');local process=kernel.PORT51FN_GetCurrentProcess()
  function_reader=function(address,size)
   local data,count=ffi.new('uint8_t[?]',size),ffi.new('size_t[1]')
   if kernel.PORT51FN_ReadProcessMemory(process,ffi.cast('const void *',address),data,size,count)==0 or M.number(count[0])~=size then return nil end
   return ffi.string(data,size)
  end
  function_executable=function(address)
   local region=ffi.new('PORT51FN_Region[1]')
   if M.number(kernel.PORT51FN_VirtualQuery(ffi.cast('const void *',address),region,ffi.sizeof(region[0])))~=ffi.sizeof(region[0])then return false end
   local protection=M.number(region[0].protection)
   return M.number(region[0].state)==0x1000 and bit.band(protection,0x100)==0 and bit.band(protection,0xf0)~=0
  end
 end
 return M.inspect_function(fn,function_reader,function_executable)
end
M.jit_util={funcinfo=function_info}
-- MSVCRT's %X truncates pointers to unsigned long (32 bits on Windows).
function M.format(pattern,...)
 local values={...};local at=0
 return (pattern:gsub('%%[-+ #0]*%d*%.?%d*[cdiouxXeEfgGqs%%]',function(spec)
  if spec=='%%'then return '%'end
  at=at+1;local value=values[at]
  local kind=spec:sub(-1)
  if (kind=='x' or kind=='X') and native_type(value)=='number' and value>=4294967296 then
   assert(value<2^53 and value%1==0,'Hex value outside exact integer range')
   local high,low=math.floor(value/4294967296),value%4294967296
   local text=string.format('%x%08x',high,low)
   if kind=='X'then text=text:upper()end
   if spec:find('#',1,true)then text=(kind=='X'and'0X'or'0x')..text end
   local width=native_number(spec:match('%%[-+ #]*(%d+)'))or 0
   if #text<width then text=string.rep(spec:find('0',1,true)and'0'or' ',width-#text)..text end
   return text
  end
  return string.format(spec,value)
 end))
end
return M

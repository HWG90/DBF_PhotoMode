-- Read-only chat widget predicate adapted from Link's Link to Memory.
-- Copyright (c) 2026 Link. MIT; see vendor/LICENSE-Link.txt.
-- No dependency on the addon, input events, chat messages, or game calls.
local M={}
M.layout={stamp=0x6ab3b43f,image_size=0x4744000,manager=0x346d538,feed=0x14498,open=0x139b8,writer=0x185f500,
 writer_prefix='\x48\x89\x5c\x24\x10\x48\x89\x6c\x24\x18\x48\x89\x74\x24\x20\x57\x48\x83\xec\x60\xf3\x0f\x10\x81\xf8\x25\x00\x00\x48\x8b\xd9\x48',
 writer_store='\x40\x88\xbb\xb8\x39\x01\x00'}
local function u32(bytes,offset)
 local a,b,c,d=bytes:byte(offset+1,offset+4);assert(d,'Chat context read truncated');return a+b*256+c*65536+d*16777216
end
local function pointer(bytes)return u32(bytes,0)+u32(bytes,4)*4294967296 end
local function native_backend()
 local ffi=require('ffi')
 pcall(ffi.cdef,[[void *FCH_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void *FCH_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FCH_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local process=kernel.FCH_GetCurrentProcess();local buffer=ffi.new('uint8_t[128]');local count=ffi.new('size_t[1]')
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=128,'Chat context read bounds invalid')
  if kernel.FCH_ReadProcessMemory(process,ffi.cast('void*',address),buffer,size,count)==0 or tonumber(count[0])~=size then return end
  return ffi.string(buffer,size)
 end
 local module_base,identity
 local function module()
  local base=tonumber(ffi.cast('uintptr_t',kernel.FCH_GetModuleHandleA('game.dll')))
  if base<65536 then module_base,identity=nil,nil;return end
  if base==module_base then return identity end
  local header=read(base,64);assert(header and header:sub(1,2)=='MZ','Chat game module header unavailable')
  local pe=u32(header,60);assert(pe>=64 and pe<1048576,'Chat game module PE bounds changed')
  local image=assert(read(base+pe,84),'Chat game module PE header unavailable')
  assert(image:sub(1,4)=='PE\0\0'and image:sub(5,6)=='\x64\x86'and image:sub(25,26)=='\x0b\x02','Chat game module identity changed')
  identity={base=base,stamp=u32(image,8),image_size=u32(image,80)};module_base=base;return identity
 end
 return {module=module,read=read}
end
function M.new(backend)
 local self={};local checked;local init_error
 if not backend then local ok,value=pcall(native_backend);if ok then backend=value else init_error=tostring(value)end end
 local function active()
  assert(backend,init_error or 'Chat context unavailable')
  local module=backend.module();if not module then return nil,'Game chat module unavailable' end
  assert(module.stamp==M.layout.stamp and module.image_size==M.layout.image_size,'Game chat layout unsupported')
  local base=module.base;assert(base>=65536 and base<2^47,'Game chat module address invalid')
  if checked~=base then
   assert(backend.read(base+M.layout.writer,#M.layout.writer_prefix)==M.layout.writer_prefix,'Chat widget writer identity changed')
   assert(backend.read(base+M.layout.writer+0x66,#M.layout.writer_store)==M.layout.writer_store,'Chat widget field offset changed')
   checked=base
  end
  local address=base+M.layout.manager
  local raw=backend.read(address,8);if not raw then return nil,'Chat manager unavailable' end
  local manager=pointer(raw);if manager==0 then return nil,'Game chat not created yet' end
  assert(manager>=65536 and manager<2^47 and manager%8==0,'Chat manager identity invalid')
  local flag=backend.read(manager+M.layout.feed+M.layout.open,1)
  if not flag then return nil,'Chat widget unavailable' end
  if backend.read(address,8)~=raw then return nil,'Chat widget changed during observation' end
  local value=flag:byte();assert(value==0 or value==1,'Chat widget open state changed type')
  return value==1
 end
 function self.chat_active()
  local ok,value,why=pcall(active);if not ok then self.reason=tostring(value);return nil,self.reason end
  self.reason=why;return value,why
 end
 self.active=self.chat_active
 function self.attach(api)
  local input=api and api.camera_input
  if type(input)~='table'then return false end
  if input.chat_active==nil then input.chat_active=self.chat_active end
  return input.chat_active==self.chat_active
 end
 return self
end
return M

-- Look up only the existing scene-depth target; never create a renderer target.
local M={}
function M.new(sr,verify)
 local validate=verify;local validate_resource;local bind_resource
 if not validate then
  local ffi=require('ffi');local util=require('jit.util')
  pcall(ffi.cdef,[[void *FDR_GetCurrentProcess(void) __asm__("GetCurrentProcess");void *FDR_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");int FDR_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");]])
  local kernel=ffi.load('kernel32');local process=kernel.FDR_GetCurrentProcess()
  local base=tonumber(ffi.cast('uintptr_t',kernel.FDR_GetModuleHandleA(nil)))
  local buffers={small=ffi.new('uint8_t[32]'),bulk=ffi.new('uint8_t[131072]')};local read_count=ffi.new("size_t[1]")
  local function bytes(address,size,bulk)
   assert(address>=65536 and address<2^47 and size>0 and size<=131072,'Depth target read bounds invalid')
   local data=buffers[(bulk or size>32)and 'bulk'or 'small'];local got=read_count
   assert(kernel.FDR_ReadProcessMemory(process,ffi.cast('void *',address),data,size,got)~=0 and tonumber(got[0])==size,'Depth target read failed')
   return (bulk or size>32)and data or ffi.string(data,size)
  end
  local function ptr(address)local v=ffi.new('uint64_t[1]');ffi.copy(v,bytes(address,8),8);return tonumber(v[0])end
  local function u32(address)local v=ffi.new('uint32_t[1]');ffi.copy(v,bytes(address,4),4);return tonumber(v[0])end
  validate=function()
   assert(sr.Renderer and type(sr.Renderer.resource)=='function','Renderer resource lookup unavailable')
   assert(util.funcinfo(sr.Renderer.resource).addr==base+0x417cd0,'Renderer resource binding changed')
   assert(bytes(base+0x417cd0,16)=='\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x40\x45\x33\xc0\x48\x8b\xd9','Renderer resource code changed')
   local renderer=ptr(ptr(base+0x23621a8)+0x338);local map=renderer+0x1600
   local count=u32(map);assert(count>0 and count<=4096,'Depth target registry invalid')
   local records=bytes(ptr(map+8),count*32,true);local found
   local integer=ffi.new('uint32_t[1]');local pointer=ffi.new('uint64_t[1]')
   for i=0,count-1 do local at=i*32
    ffi.copy(integer,records+at+24,4);local occupied=tonumber(integer[0])~=4294967294
    ffi.copy(integer,records+at,4)
    if occupied and tonumber(integer[0])==0x9b8038e0 then
     assert(not found,'Depth target ambiguous');ffi.copy(pointer,records+at+8,8);found=tonumber(pointer[0])
    end
   end
   assert(found and found>=65536 and found<2^47,'Existing depth target unavailable')
   local backend=ptr(renderer+0x1168);if backend<65536 then backend=ptr(renderer+0x1138)end
   local cache=ptr(backend+0x468)+u32(backend+0x478)*40
   local textures=u32(cache);assert(textures>0 and textures<=4096,'Depth texture cache invalid')
   local entries=bytes(ptr(cache+8),textures*24,true);local backing
   for i=0,textures-1 do local at=i*24
    ffi.copy(integer,entries+at+16,4)
    if tonumber(integer[0])~=4294967294 then
     ffi.copy(pointer,entries+at,8)
     if tonumber(pointer[0])==found then
      assert(not backing,'Depth texture backing ambiguous');ffi.copy(pointer,entries+at+8,8);backing=tonumber(pointer[0])
     end
    end
   end
   assert(backing and backing>=65536 and backing<2^47,'Depth GPU backing unavailable')
   local id=u32(backing);assert(id%16777216~=16777215 and math.floor(id/16777216)==2,'Depth GPU texture ID invalid')
   local w,h=u32(backing+20),u32(backing+24);assert(w>0 and h>0 and w<=16384 and h<=16384,'Depth GPU dimensions invalid')
   return true,found,backing,id
  end
  validate_resource=function(resource,expected)
   local address=tonumber(ffi.cast('uintptr_t',resource))
   assert(address==expected,'Depth resource identity mismatch');return true
  end
  bind_resource=function(material,slot,resource)
   assert(slot=='diffuse_map','Only the candidate depth texture slot may be bound')
   local ready,expected,backing=validate();assert(ready,'Depth target unavailable');validate_resource(resource,expected)
   local address=tonumber(ffi.cast('uintptr_t',material))
   assert(u32(address)==0xd92a8333,'Material instance layout changed')
   assert(bytes(base+0x4f3230,32)=='\x48\x89\x5c\x24\x10\x48\x89\x6c\x24\x18\x57\x41\x56\x41\x57\x48\x83\xec\x30\x44\x8b\x49\x18\x45\x33\xff\x4d\x8b\xf0\x8b\xda\x48','Material resource setter changed')
   -- The SDK wrapper has an invalid GPU index; this verified setter queues only
   -- the backing texture's first DWORD and retains a non-owning pointer.
   local setter=ffi.cast('void (*)(void *,uint32_t,void *)',base+0x4f3230)
   setter(ffi.cast('void *',address),0x3aa8b87e,ffi.cast('void *',backing));return true
  end
 end
 local self={};local cached,cached_identity
 self.bind=bind_resource
 function self.available()
  local ok,ready=pcall(validate)
  return ok and ready==true,ok and nil or tostring(ready)
 end
 function self.get()
  local ok,ready,expected,backing,id=pcall(validate)
  if not ok or ready~=true then return nil,ok and 'Existing depth target unavailable'or tostring(ready)end
  self.binding_identity=backing and tostring(backing)..':'..tostring(id)or nil
  if expected and expected==cached_identity and cached then return cached end
  local passed,resource=pcall(sr.Renderer.resource,'linear_depth')
  if not passed or resource==nil then return nil,passed and 'Depth resource lookup returned nil'or tostring(resource)end
  if validate_resource then local valid,why=pcall(validate_resource,resource,expected);if not valid then return nil,tostring(why)end end
  cached,cached_identity=resource,expected
  return resource
 end
 return self
end
return M

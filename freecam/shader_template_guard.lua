-- Resource availability alone does not prove registration in the renderer.
local M={}
function M.new(sr,verify,template_id)
 template_id=template_id or 0x9eb0127e
 assert(type(template_id)=='number'and template_id>=0 and template_id<2^32 and template_id==math.floor(template_id),'Invalid Photo shader template')
 if not verify then
  local ffi=require('ffi')
  pcall(ffi.cdef,[[void *FSG_GetCurrentProcess(void) __asm__("GetCurrentProcess");void *FSG_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");int FSG_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");]])
  local kernel=ffi.load('kernel32');local process=kernel.FSG_GetCurrentProcess()
  local base=tonumber(ffi.cast('uintptr_t',kernel.FSG_GetModuleHandleA(nil)))
  local function bytes(address,size)
   assert(address>=65536 and address<2^47 and size>0 and size<=32,'Shader template read bounds invalid')
   local data=ffi.new('uint8_t[?]',size);local got=ffi.new('size_t[1]')
   assert(kernel.FSG_ReadProcessMemory(process,ffi.cast('void *',address),data,size,got)~=0 and tonumber(got[0])==size,'Shader template read failed')
   return ffi.string(data,size)
  end
  local function ptr(address)local value=ffi.new('uint64_t[1]');ffi.copy(value,bytes(address,8),8);return tonumber(value[0])end
  local function u32(address)local value=ffi.new('uint32_t[1]');ffi.copy(value,bytes(address,4),4);return tonumber(value[0])end
  local function lookup(manager,wanted)
   local slots,capacity=u32(manager+0x100),u32(manager+0x104)
   local buckets=u32(manager+0x11c);local records=ptr(manager+0x108)
   assert(slots>0 and slots<=capacity and capacity<=100000 and buckets>0 and buckets<=slots,'Shader template table invalid')
   local index=wanted%buckets;local visited={}
   for _=1,slots do
    assert(index<slots and not visited[index],'Shader template chain invalid');visited[index]=true
    local row=records+index*32;local next_index=u32(row+24)
    if next_index==4294967294 then return false end
    if u32(row)==wanted then local definition=ptr(row+8);assert(definition>=65536 and definition<2^47,'Shader template definition invalid');return true end
    index=next_index%2147483648;if index==2147483647 then return false end
   end
   error('Shader template chain exceeded bounds')
  end
  verify=function()
   assert(bytes(base+0x51df00,16)=='\x48\x89\x5c\x24\x08\x48\x89\x6c\x24\x18\x89\x54\x24\x10\x56\x57','Shader template lookup code changed')
   local app=ptr(base+0x23621a8);local renderer=ptr(app+0x338);local manager=ptr(renderer+0x1208)
   assert(lookup(manager,0x9fcfe126),'Native GUI shader template unavailable')
   return lookup(manager,template_id)
  end
 end
 return {present=function()
  local ok,result=pcall(verify)
  if not ok then return false,tostring(result)end
  return result==true,result==true and nil or 'Photo shader is not registered with the renderer'
 end}
end
return M

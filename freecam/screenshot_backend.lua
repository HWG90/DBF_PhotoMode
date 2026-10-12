-- Engine back-buffer capture. The native writer produces DDS, including a
-- DX10 header, regardless of the extension. PNG encoding is a separate step.
local M={}
local function integer(data,offset)
 local a,b,c,d=data:byte(offset+1,offset+4);assert(d,'Screenshot header truncated')
 return a+b*256+c*65536+d*16777216
end
function M.inspect(header,size)
 assert(type(header)=='string'and header:sub(1,4)=='DDS ','Engine screenshot is not DDS')
 assert(integer(header,4)==124 and size>=128,'Screenshot DDS header invalid')
 local width,height=integer(header,16),integer(header,12)
 assert(width>0 and width<=16384 and height>0 and height<=16384,'Screenshot dimensions invalid')
 local dx10=header:sub(85,88)=='DX10';local start=dx10 and 148 or 128
 assert(#header>=start and size>start,'Screenshot image data unavailable')
 local format=dx10 and integer(header,128)or nil
 return {width=width,height=height,bytes=size,format=format,dx10=dx10}
end
local function native_guard(sr)
 local ffi=require('ffi');local util=require('jit.util')
 pcall(ffi.cdef,[[
  void *FCP_GetCurrentProcess(void) __asm__("GetCurrentProcess");
  void *FCP_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");
  int FCP_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");
 ]])
 local kernel=ffi.load('kernel32');local process=kernel.FCP_GetCurrentProcess()
 local base=tonumber(ffi.cast('uintptr_t',kernel.FCP_GetModuleHandleA(nil)))
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=4096*32,'Screenshot native address invalid')
  local buffer=ffi.new('uint8_t[?]',size);local count=ffi.new('size_t[1]')
  assert(kernel.FCP_ReadProcessMemory(process,ffi.cast('void *',address),buffer,size,count)~=0 and tonumber(count[0])==size,'Screenshot native read failed')
  return ffi.string(buffer,size)
 end
 local function pointer(address)local value=ffi.new('uint64_t[1]');ffi.copy(value,read(address,8),8);return tonumber(value[0])end
 return function()
  assert(type(sr.Application.save_render_target)=='function','Engine screenshot API unavailable')
  assert(util.funcinfo(sr.Application.save_render_target).addr==base+0x3fe7c0,'Screenshot binding unsupported')
  assert(read(base+0x3fe7c0,8)=='\x48\x8b\xd1\xe9\x68\xf9\xff\xff','Screenshot binding changed')
  assert(read(base+0x3fe130,16)=='\x48\x89\x5c\x24\x18\x48\x89\x4c\x24\x08\x55\x56\x57\x41\x54\x41','Screenshot implementation changed')
  local renderer=pointer(pointer(base+0x23621a8)+0x338);local map=renderer+0x1600
  local count=integer(read(map,4),0);local active=integer(read(map+0x18,4),0);local buckets=integer(read(map+0x1c,4),0)
  assert(count>0 and count<=4096 and active>0 and active<=count and buckets>0 and buckets<=count,'Screenshot target registry invalid')
  local records=read(pointer(map+8),count*32)
  -- The engine lookup inserts missing keys. Check existence without calling it.
  for offset=0,#records-32,32 do
   if integer(records,offset+24)~=4294967294 and integer(records,offset)==0x2b269c03 then
    local value=ffi.new('uint64_t[1]');ffi.copy(value,records:sub(offset+9,offset+16),8)
    local resource=tonumber(value[0]);assert(resource>=65536 and resource<2^47,'Back buffer resource unavailable')
    read(resource,8)
    local backend=pointer(renderer+0x1168);if backend<65536 then backend=pointer(renderer+0x1138)end
    local cache=pointer(backend+0x468)+integer(read(backend+0x478,4),0)*40
    local textures=integer(read(cache,4),0);assert(textures>0 and textures<=4096,'Screenshot texture cache invalid')
    local entries=read(pointer(cache+8),textures*24)
    for at=0,#entries-24,24 do
     local key=ffi.new('uint64_t[1]');ffi.copy(key,entries:sub(at+1,at+8),8)
     if tonumber(key[0])==resource and integer(entries,at+16)~=4294967294 then
      local cell=ffi.new('uint64_t[1]');ffi.copy(cell,entries:sub(at+9,at+16),8);local texture=tonumber(cell[0]);local descriptor=read(texture,36)
      return true,{format=integer(descriptor,8),width=integer(descriptor,20),height=integer(descriptor,24),mips=integer(descriptor,28),array=integer(descriptor,32),kind=descriptor:byte(4)}
     end
    end
    error('Screenshot texture descriptor unavailable')
   end
  end
  error('Back buffer target unavailable')
 end
end
function M.new(sr,verify)
 local guard
 local ok,why=pcall(function()guard=verify or native_guard(sr)end)
 if not ok then return nil,tostring(why)end
 local self={}
 function self.ready()
  local passed,reason,metadata=pcall(guard,sr)
  if not passed or reason~=true then return false,passed and 'Screenshot target verification refused'or tostring(reason)end
  self.verified_target=metadata;return true
 end
 function self.capture(path)
  if type(path)~='string'or not path:match('^[A-Za-z]:[/\\]')or path:sub(-4):lower()~='.dds'or path:find('%z')or path:find('[\r\n]')or path:find('[/\\]%.%.[/\\]')then
   return false,'Engine screenshot needs an absolute DDS output path'
  end
  local existing=io.open(path,'rb');if existing then existing:close();return false,'Screenshot output already exists'end
  local passed,reason=self.ready();if not passed then return false,reason end
  local captured,err=pcall(sr.Application.save_render_target,'back_buffer',path)
  if not captured then return false,tostring(err)end
  local file=io.open(path,'rb');if not file then return false,'Engine screenshot file was not written'end
  local size=file:seek('end');file:seek('set',0);local header=file:read(148);file:close()
  local valid,result=pcall(M.inspect,header,size)
  if not valid then return false,tostring(result)end
  if result.format==0 then
   -- This HD2 writer emits UNKNOWN for its HDR RGB10 back buffer. Correct only
   -- our captured header after proving the native format and exact surface.
   local t=self.verified_target
   if not(t and t.format==16 and t.kind==4 and t.mips==1 and t.array==1 and t.width==result.width and t.height==result.height and size==148+result.width*result.height*4 and integer(header,20)==result.width*4)then return false,'Unknown screenshot pixel format'end
   local output=io.open(path,'r+b');if not output then return false,'Screenshot header could not be normalized'end
   output:seek('set',128);output:write('\24\0\0\0');output:close();result.format=24
  end
  result.path=path;return true,result
 end
 if jit then jit.off(self.capture,true);jit.off(self.ready,true)end
 return self
end
return M

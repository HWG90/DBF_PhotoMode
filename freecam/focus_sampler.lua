-- Existing linear_depth readback only. The GPU copies the full surface;
-- Lua reads a small median window. UVs use a top-left origin.
local M={};local sequence=0
local function integer(data,offset)
 local a,b,c,d=data:byte(offset+1,offset+4);assert(d,'Focus DDS header truncated')
 return a+b*256+c*65536+d*16777216
end
local function finite(value)return type(value)=='number'and value==value and math.abs(value)<math.huge end
local function uv(u,v)return finite(u)and finite(v)and u>=0 and u<=1 and v>=0 and v<=1 end
local function float(data,offset)
 local bits=integer(data,offset);local sign=bits>=2147483648 and -1 or 1
 local exponent=math.floor(bits/8388608)%256;local fraction=bits%8388608
 if exponent==255 then return fraction==0 and sign*math.huge or 0/0 end
 if exponent==0 then return sign*fraction*2^-149 end
 return sign*(1+fraction/8388608)*2^(exponent-127)
end
function M.inspect(header,size)
 assert(type(header)=='string'and header:sub(1,4)=='DDS 'and integer(header,4)==124,'Focus depth is not a DDS surface')
 assert(finite(size)and size>=148 and #header>=148,'Focus DDS data unavailable')
 assert(integer(header,76)==32 and integer(header,80)%8>=4 and header:sub(85,88)=='DX10','Focus DDS requires a DX10 pixel format')
 assert(integer(header,128)==41 and integer(header,132)==3,'Focus DDS must be R32_FLOAT Texture2D')
 assert(integer(header,136)==0 and integer(header,140)==1 and integer(header,112)==0,'Focus DDS must contain one non-cubemap surface')
 assert(integer(header,24)<=1 and integer(header,28)<=1,'Focus DDS cannot have volume slices or mip levels')
 local width,height=integer(header,16),integer(header,12)
 assert(width>0 and height>0 and width<=16384 and height<=16384,'Focus DDS dimensions invalid')
 assert(integer(header,20)==width*4 and size==148+width*height*4,'Focus DDS size or pitch invalid')
 return {width=width,height=height,bytes=size,format=41}
end
function M.read(file,u,v,options)
 assert(uv(u,v),'Focus coordinates must be normalized top-left UVs')
 options=options or{};local maximum=options.max_distance or 10000
 assert(finite(maximum)and maximum>0,'Focus maximum distance invalid')
 local radius=options.radius or 1;assert(radius>=0 and radius<=2 and radius==math.floor(radius),'Focus sample window invalid')
 local size=assert(file:seek('end'));assert(file:seek('set',0)==0)
 local info=M.inspect(assert(file:read(148)),size)
 local x=math.min(info.width-1,math.floor(u*info.width));local y=math.min(info.height-1,math.floor(v*info.height))
 local left,right=math.max(0,x-radius),math.min(info.width-1,x+radius);local values={};local center
 for row=math.max(0,y-radius),math.min(info.height-1,y+radius)do
  local start=148+(row*info.width+left)*4;assert(file:seek('set',start)==start)
  local data=assert(file:read((right-left+1)*4),'Focus depth row unavailable');assert(#data==(right-left+1)*4,'Focus depth row truncated')
  for col=left,right do
   local value=float(data,(col-left)*4)
   if col==x and row==y then center=value end
   if finite(value)and value>0 and value<maximum then values[#values+1]=value end
  end
 end
 assert(finite(center)and center>0 and center<maximum,'No focusable surface at this point')
 assert(#values>0,'Focus sample contains only sky or invalid depth');table.sort(values)
 local distance=values[math.floor((#values+1)/2)]
 info.x,info.y,info.samples=x,y,#values;return distance,info
end
local function platform()
 local ffi=require('ffi')
 pcall(ffi.cdef,[[
  uint64_t FFS_GetTickCount64(void) __asm__("GetTickCount64");
  unsigned long FFS_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
  void *FFS_GetCurrentProcess(void) __asm__("GetCurrentProcess");
  void *FFS_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");
  int FFS_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");
  int FFS_MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int) __asm__("MultiByteToWideChar");
  int FFS_CreateDirectoryW(const wchar_t*,void*) __asm__("CreateDirectoryW");
  unsigned long FFS_GetLastError(void) __asm__("GetLastError");
 ]])
 local kernel=ffi.load('kernel32')
 local function mkdir(path)
  local count=kernel.FFS_MultiByteToWideChar(65001,8,path,-1,nil,0);assert(count>0,'Focus cache path invalid')
  local out=ffi.new('wchar_t[?]',count);assert(kernel.FFS_MultiByteToWideChar(65001,8,path,-1,out,count)==count,'Focus cache path conversion failed')
  return kernel.FFS_CreateDirectoryW(out,nil)~=0 or tonumber(kernel.FFS_GetLastError())==183
 end
 return {ffi=ffi,kernel=kernel,now=function()return tonumber(kernel.FFS_GetTickCount64())/1000 end,pid=tonumber(kernel.FFS_GetCurrentProcessId()),mkdir=mkdir}
end
local function native_guard(sr,depth,system)
 local ffi,kernel=system.ffi,system.kernel;local util=require('jit.util')
 local process=kernel.FFS_GetCurrentProcess();local base=tonumber(ffi.cast('uintptr_t',kernel.FFS_GetModuleHandleA(nil)))
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=131072,'Focus target read bounds invalid')
  local data=ffi.new('uint8_t[?]',size);local got=ffi.new('size_t[1]')
  assert(kernel.FFS_ReadProcessMemory(process,ffi.cast('void*',address),data,size,got)~=0 and tonumber(got[0])==size,'Focus target descriptor unavailable')
  return ffi.string(data,size)
 end
 local function pointer(address)local value=ffi.new('uint64_t[1]');ffi.copy(value,read(address,8),8);return tonumber(value[0])end
 local function display_identity()
  local renderer=pointer(pointer(base+0x23621a8)+0x338);local map=renderer+0x1600
  local count=integer(read(map,4),0);assert(count>0 and count<=4096,'Focus display target registry invalid')
  local records=read(pointer(map+8),count*32);local resource
  for at=0,#records-32,32 do
   if integer(records,at+24)~=4294967294 and integer(records,at)==0x2b269c03 then
    assert(not resource,'Focus back buffer resource ambiguous')
    local value=ffi.new('uint64_t[1]');ffi.copy(value,records:sub(at+9,at+16),8);resource=tonumber(value[0])
   end
  end
  assert(resource and resource>=65536 and resource<2^47,'Focus back buffer resource unavailable')
  local backend=pointer(renderer+0x1168);if backend<65536 then backend=pointer(renderer+0x1138)end
  local cache=pointer(backend+0x468)+integer(read(backend+0x478,4),0)*40
  local count=integer(read(cache,4),0);assert(count>0 and count<=4096,'Focus display texture cache invalid')
  local entries=read(pointer(cache+8),count*24);local backing
  for at=0,#entries-24,24 do
   if integer(entries,at+16)~=4294967294 then
    local key=ffi.new('uint64_t[1]');ffi.copy(key,entries:sub(at+1,at+8),8)
    if tonumber(key[0])==resource then
     assert(not backing,'Focus back buffer backing ambiguous')
     local value=ffi.new('uint64_t[1]');ffi.copy(value,entries:sub(at+9,at+16),8);backing=tonumber(value[0])
    end
   end
  end
  assert(backing and backing>=65536 and backing<2^47,'Focus back buffer backing unavailable')
  local data=read(backing,36);local id=integer(data,0)
  local width,height=integer(data,20),integer(data,24)
  assert(id%16777216~=16777215 and width>0 and height>0 and width<=16384 and height<=16384,'Focus display descriptor invalid')
  assert(integer(data,28)==1 and integer(data,32)==1,'Focus display must be a single surface')
  local hdr;local setting=sr.Application.render_setting
  if type(setting)=='function'then
   local address=util.funcinfo(setting).addr
   if address and read(address,8)=='\x48\x8b\xd1\xe9\x38\xfe\xff\xff'then
    local ok,value=pcall(setting,'hdr_enabled');if ok and type(value)=='boolean'then hdr=value end
   end
  end
  return table.concat({renderer,resource,backing,id,width,height,integer(data,8),tostring(hdr)},':')
 end
 return function()
  assert(type(sr.Application.save_render_target)=='function','Focus readback API unavailable')
  assert(util.funcinfo(sr.Application.save_render_target).addr==base+0x3fe7c0,'Focus readback binding unsupported')
  assert(read(base+0x3fe7c0,8)=='\x48\x8b\xd1\xe9\x68\xf9\xff\xff'and read(base+0x3fe130,16)=='\x48\x89\x5c\x24\x18\x48\x89\x4c\x24\x08\x55\x56\x57\x41\x54\x41','Focus readback implementation changed')
  local available,why=depth.available();assert(available,why)
  local resource,reason=depth.get();assert(resource,reason)
  local address,id=tostring(depth.binding_identity):match('^(%d+):(%d+)$');address,id=tonumber(address),tonumber(id)
  assert(address and id,'Focus target identity unavailable');local data=read(address,36)
  assert(integer(data,0)==id and math.floor(id/16777216)==2,'Focus depth texture identity changed')
  return true,{format=integer(data,8),width=integer(data,20),height=integer(data,24),mips=integer(data,28),array=integer(data,32),kind=data:byte(4),identity=depth.binding_identity,display_identity=display_identity()}
 end
end
function M.new(sr,depth,verify,options)
 options=options or{};local ok,self=pcall(function()
  local system
  if not(verify and options.now and options.mkdir and options.pid)then system=platform()end
  local clock=options.now or system.now;local mkdir=options.mkdir or system.mkdir;local pid=options.pid or system.pid
  local guard=verify or native_guard(sr,assert(depth,'Existing depth resource is required'),system)
  local interval=options.interval or 1;assert(finite(interval)and interval>=.5 and interval<=60,'Focus cooldown must be at least 0.5 seconds')
  local localdir=assert(os.getenv('LOCALAPPDATA'),'LocalAppData unavailable'):gsub('\\','/'):gsub('/+$','')
  assert(localdir:match('^[A-Za-z]:/')and not localdir:find('%z')and not localdir:find('[\r\n]')and not localdir:find('/%.%./'),'Focus cache root must be absolute LocalAppData')
  sequence=sequence+1;local folder=localdir..'/DBF_PhotoMode/FocusCache'
  local path=folder..'/depth-'..tostring(pid)..'-'..string.format('%.0f',clock()*1000)..'-'..sequence..'.dds'
  local self={now=clock,interval=interval,path=path,status='Focus sampling ready'};local owned=false;local cached;local next_capture=0;local last_error;local identity;local display_generation;local display_stable_at
  local function remove()
   if owned then
    local done,why=os.remove(path);local check=io.open(path,'rb');if check then check:close();return false,why or'Focus cache cleanup refused'end
    owned=false;cached=nil
   end
   return true
  end
  function self.ready()
   local ran,allowed,meta=pcall(guard,sr)
   if not ran or allowed~=true then return false,ran and'Focus target verification refused'or tostring(allowed)end
   if not(type(meta)=='table'and meta.format==1 and meta.kind==2 and meta.mips==1 and meta.array==1 and finite(meta.width)and finite(meta.height)and meta.width>0 and meta.height>0 and meta.width<=16384 and meta.height<=16384)then return false,'Focus target is not a single R32_FLOAT depth surface'end
   if meta.display_identity~=nil and not(type(meta.display_identity)=='string'and #meta.display_identity>0 and #meta.display_identity<=512)then return false,'Focus display identity invalid'end
   return true,meta
  end
  function self.release()local done,why=remove();if done then cached,identity=nil,nil;display_generation,display_stable_at=nil,nil;self.status='Focus sampler released'end;return done,why end
  function self.sample(u,v)
   if not uv(u,v)then return nil,'Focus coordinates must be normalized top-left UVs'end
   local now=clock();if not finite(now)then return nil,'Focus clock unavailable'end
   local ready,meta=self.ready();if not ready then display_generation,display_stable_at=nil,nil;local done,why=remove();self.status=tostring(meta);return nil,done and self.status or why end
   -- Display changes can retire the depth surface while the DDS writer runs.
   -- Observe the live back buffer before every readback and discard old focus
   -- samples until the same generation has remained visible for two seconds.
   if meta.display_identity then
    if display_generation~=meta.display_identity then
     display_generation=meta.display_identity;display_stable_at=now+2
     cached,identity,self.last_sample=nil,nil,nil
    end
    if now<display_stable_at then
     local done,why=remove();self.status='Auto-focus paused: display settling'
     return nil,done and self.status or why
    end
   end
   if identity and meta.identity~=identity then local done,why=remove();if not done then return nil,why end;identity=nil end
   if now>=next_capture then
    next_capture=now+interval;local cleared,why=remove();if not cleared then return nil,why end
    local prior=io.open(path,'rb');if prior then prior:close();return nil,'Focus cache path already belongs to another file'end
    if not(mkdir(localdir..'/DBF_PhotoMode')and mkdir(folder))then return nil,'Focus cache directory unavailable'end
    local start=clock();owned=true
    local captured,error=pcall(sr.Application.save_render_target,'linear_depth',path)
    local finish=clock();self.last_capture_ms=math.max(0,(finish-start)*1000)
    next_capture=finish+math.max(interval,self.last_capture_ms/1000*3)
    if not captured then remove();last_error='Focus readback failed: '..tostring(error);self.status=last_error;return nil,last_error end
    cached={captured_at=finish,capture_ms=self.last_capture_ms};identity=meta.identity;last_error=nil
   end
   if not cached then return nil,last_error or'Focus readback cooling down'end
   local file=io.open(path,'rb');if not file then remove();cached=nil;last_error='Focus depth file was not written';self.status=last_error;return nil,last_error end
   local ran,distance,info=pcall(M.read,file,u,v,options);file:close()
   if not ran then
    -- Bad surfaces are discarded; a valid surface with no subject stays cached.
    if not tostring(distance):find('No focusable surface',1,true)then remove();cached=nil end
    self.status=tostring(distance);return nil,self.status
   end
   if info.width~=meta.width or info.height~=meta.height then remove();cached=nil;self.status='Focus depth dimensions changed';return nil,self.status end
   info.capture_ms=cached.capture_ms;info.age=math.max(0,now-cached.captured_at);info.cached=info.age>0;info.next_capture=next_capture
   self.status=string.format('Focus %.3f m; depth readback %.0f ms',distance,info.capture_ms)
   self.last_sample=info;return distance,nil,info
  end
  if jit then jit.off(self.sample,true);jit.off(self.ready,true)end
  return self
 end)
 if not ok then return nil,tostring(self)end;return self
end
return M

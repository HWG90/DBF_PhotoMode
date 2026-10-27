-- Existing linear_depth readback only. The GPU copies the full surface;
-- Lua reads a small median window for autofocus, the exact pixel for explicit
-- selection. UVs use a top-left origin.
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
function M.new(sr,depth,verify,options)
 options=options or{};local ok,self=pcall(function()
  assert(verify and options.now and options.mkdir and options.pid,'Ordinary Lua focus platform/verifier required')
  local system={}
  local clock=options.now or system.now;local mkdir=options.mkdir or system.mkdir;local pid=options.pid or system.pid
  -- Scheduling may use a frame-latched engine clock. Operation cost must use
  -- an independently advancing clock or a slow readback looks instantaneous.
  local measure=options.measure or clock
  local function stamp()
   local ok,value=pcall(measure)
   if ok and finite(value)and value>=0 then return value end
  end
  local guard=assert(verify)
  local interval=options.interval or 1;assert(finite(interval)and interval>=.5 and interval<=60,'Focus cooldown must be at least 0.5 seconds')
  local auto_budget=options.auto_budget_ms
  assert(auto_budget==nil or finite(auto_budget)and auto_budget>0,'Invalid automatic depth budget')
  local auto_blocked;local captures,max_capture=0,0
  -- A silhouette click belongs to its center pixel. A neighborhood median can
  -- replace that surface with the background (or a foreground neighbor), then
  -- incorrectly reject/select a character in the picker's occlusion check.
  local selection_options={radius=0,max_distance=options.max_distance}
  local localdir=assert(os.getenv('LOCALAPPDATA'),'LocalAppData unavailable'):gsub('\\','/'):gsub('/+$','')
  assert(localdir:match('^[A-Za-z]:/')and not localdir:find('%z')and not localdir:find('[\r\n]')and not localdir:find('/%.%./'),'Focus cache root must be absolute LocalAppData')
  sequence=sequence+1;local folder=options.directory or localdir..'/DBF_PhotoMode/FocusCache'
  assert(type(folder)=='string'and folder:match('^[A-Za-z]:/')and not folder:find('%z')and not folder:find('[\r\n]')and not folder:find('/%.%./'),'Focus cache directory must be absolute')
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
  function self.sample(u,v,fresh,automatic)
   -- A synchronous full-surface GPU read cannot be preempted. After one measured
   -- over-budget read, stop continuous sampling for this generation. Explicit
   -- clicks remain available and no background retry can recreate the spikes.
   if automatic and auto_blocked then return nil,auto_blocked end
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
     return nil,done and self.status or why,done and{pending=true,retry_at=display_stable_at}or nil
    end
   end
   if identity and meta.identity~=identity then local done,why=remove();if not done then return nil,why end;identity=nil end
   -- Explicit subject selection must not combine an old image with this
   -- frame's camera/units. Respect the readback cooldown and retry once due.
   if fresh and now<next_capture and cached and now>cached.captured_at+.001 then
    return nil,'Selection waiting for fresh depth',{pending=true,retry_at=next_capture}
   end
   if now>=next_capture then
    next_capture=now+interval;local cleared,why=remove();if not cleared then return nil,why end
    local prior=io.open(path,'rb');if prior then prior:close();return nil,'Focus cache path already belongs to another file'end
    if not((options.directory or mkdir(localdir..'/DBF_PhotoMode'))and mkdir(folder))then return nil,'Focus cache directory unavailable'end
    local start=stamp();owned=true
    local captured,error=pcall(sr.Application.save_render_target,'linear_depth',path)
    local measured=stamp();local finish=clock()
    self.last_capture_ms=start and measured and measured>=start and(measured-start)*1000 or -1
    captures=captures+1;max_capture=math.max(max_capture,self.last_capture_ms)
    if auto_budget and (self.last_capture_ms<0 or self.last_capture_ms>auto_budget)then
     if not auto_blocked then
      auto_blocked='Centre autofocus paused: synchronous depth read exceeds frame budget; use manual or click focus'
      if options.log then options.log(string.format('Depth readback budget: %.3f ms; budget %.3f ms; continuous autofocus suspended',self.last_capture_ms,auto_budget))end
     end
    elseif captures==1 and options.log then options.log(string.format('Depth readback first sample: %.3f ms',self.last_capture_ms))end
    next_capture=finish+math.max(interval,math.max(0,self.last_capture_ms)/1000*3)
    if not captured then remove();last_error='Focus readback failed: '..tostring(error);self.status=last_error;return nil,last_error end
    cached={captured_at=finish,capture_ms=self.last_capture_ms};identity=meta.identity;last_error=nil
   end
   if not cached then return nil,last_error or'Focus readback cooling down',not last_error and{pending=true,retry_at=next_capture}or nil end
   local file=io.open(path,'rb');if not file then remove();cached=nil;last_error='Focus depth file was not written';self.status=last_error;return nil,last_error end
   local ran,distance,info=pcall(M.read,file,u,v,fresh and selection_options or options);file:close()
   if not ran then
    -- Bad surfaces are discarded; a valid surface with no subject stays cached.
    if not tostring(distance):find('No focusable surface',1,true)then remove();cached=nil end
    self.status=tostring(distance);return nil,self.status
   end
   if info.width~=meta.width or info.height~=meta.height then remove();cached=nil;self.status='Focus depth dimensions changed';return nil,self.status end
   info.capture_ms=cached.capture_ms;info.age=math.max(0,now-cached.captured_at);info.cached=info.age>0;info.next_capture=next_capture
   self.status=string.format('Focus %.3f m; depth readback %s',distance,info.capture_ms>=0 and string.format('%.0f ms',info.capture_ms)or'timing unavailable')
   self.last_sample=info;return distance,nil,info
  end
  function self.metrics()return{captures=captures,max_capture_ms=max_capture,automatic_suspended=auto_blocked~=nil}end
  if jit then jit.off(self.sample,true);jit.off(self.ready,true)end
  return self
 end)
 if not ok then return nil,tostring(self)end;return self
end
return M

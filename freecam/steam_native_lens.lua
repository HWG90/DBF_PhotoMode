-- Current native photographic lens; ordinary Lua5.1 + typed bridge, no FFI.
local M={}
local keys={distance=0xf617a000,region=0x1ed5746a,start=0xf2cba64d,finish=0x594c123a,near_scale=0xd8108f78,far_scale=0xb18edf0c,near_max=0xa7990477,far_max=0xf07fc12e,close_distance=0x834c73c0,close_region=0xa5fecfc7,close_start=0xa3b92674,close_finish=0xf90f260e,close_near_scale=0xbcb7968f,close_far_scale=0x32af31e5,close_near_max=0x0db64441,close_far_max=0x209f72cf}
local function word(s,i)local a,b,c,d=s:byte(i,i+3);assert(d,'Truncated lens read');return a+b*256+c*65536+d*16777216 end
local function rounded(v)
 if v==0 then return 0 end
 local m,e=math.frexp(v);local s=m*16777216;local q=math.floor(s);local f=s-q
 if f>.5 or f==.5 and q%2==1 then q=q+1 end
 return math.ldexp(q,e-24)
end
function M.new(sr,host,model,lens,bridge_name,dir)
 local open,why=package.loadlib(dir..'/port51/'..bridge_name,'luaopen_hd2_nativeinfo');assert(open,why)
 local bridge=open();assert(type(bridge.profile_float)=='function','Numeric lens bridge unavailable')
 local mem=host.memory();local exe=mem.exe
 local function read(a,n)return mem.read(a,n)end
 local function u32(a)return word(read(a,4),1)end
 local function ptr(a)local s=read(a,8);local n=word(s,1)+word(s,5)*4294967296;assert(n>=65536 and n<2^47,'Lens pointer unavailable');return n end
 local function float(a)
  local v=u32(a);local sign=v>=2147483648 and -1 or 1;local e=math.floor(v/8388608)%256;local m=v%8388608
  assert(e~=255,'Nonfinite lens field');return sign*(e==0 and m*2^-149 or(1+m/8388608)*2^(e-127))
 end
 assert(read(exe+0x3d4129,7)=='\072\139\005\184\088\003\002','Lens renderer global differs')
 assert(read(exe+0x104a23,7)=='\068\057\131\000\022\000\000','Lens world binding differs')
 local self={ready=false,message='Native lens waits for Depth of field'}
 local observer,previous_update,observer_switch
 local current,selected,observed,observed_at,last_revision,next_attach,next_observe,history,next_check,mismatch,mismatch_at,last_seen
 local function identity(frame)
  return{world=frame.world,native=mem.world_address(frame.world),camera=bridge.userdata_address(frame.camera),generation=frame.generation}
 end
 local function same(a,b)return a and b and a.native==b.native and a.camera==b.camera and a.generation==b.generation end
 local function profile(index,entity,instance,provider,world)
  local blobs=ptr(provider+0xe8);local blob=ptr(blobs+index*8);local count=u32(blob+4);assert(count>0 and count<=512)
  local signature=read(blob+0x10,count*4);local offsets,fields={},{}
  for i=0,count-1 do for name,key in pairs(keys)do if word(signature,i*4+1)==key then
   assert(not offsets[name],'Duplicate lens key');local at=blob+0x10+count*4+i*16;assert(u32(at)==2,'Lens field is not float')
   offsets[name]=at+8;fields[name]=float(at+8)
  end end end
  for name in pairs(keys)do assert(offsets[name]and math.abs(fields[name])<=20000,'Incomplete photographic lens')end
  local p={index=index,fields=fields,offsets=offsets,saved={},written={}}
  function p.valid()
   local ok,value=pcall(function()
    if mem.world_address(sr.Application.main_world())~=world or ptr(world+0x230b58)~=provider then return false end
    if u32(ptr(provider+0xc8)+index*4)~=entity or u32(ptr(provider+0xd0)+index*4)~=0xf7a3101f or u32(ptr(provider+0xd8)+index*4)~=instance then return false end
    return ptr(ptr(provider+0xe8)+index*8)==blob and u32(blob+4)==count and read(blob+0x10,count*4)==signature
   end)
   if not ok then return nil,tostring(value)end;return value
  end
  function p.write(name,value)
   assert(p.valid()==true,'Lens lifetime unavailable');local before=float(offsets[name]);local target=rounded(value)
   if p.written[name]~=nil then assert(before==p.written[name],'Lens field changed by another writer')end
   if before==target then return end
   if p.saved[name]==nil then p.saved[name]=before end;p.written[name]=target
   assert(bridge.profile_float(current.world,index,entity,instance,keys[name],before,value)==target,'Lens write acknowledgement differs')
  end
  function p.release()
   local alive,why=p.valid();if alive==false then p.saved={};p.written={};return true end
   if alive~=true then return false,why end
   for name,before in pairs(p.saved)do
    local ok,reason=pcall(function()
     local actual=float(offsets[name]);if actual==p.written[name]then assert(bridge.profile_float(current.world,index,entity,instance,keys[name],actual,before)==before)end
    end)
    if not ok then return false,tostring(reason)end;p.saved[name]=nil;p.written[name]=nil
   end
   return true
  end
  return p
 end
 function self.release()
  if observer_switch then observer_switch.active=false end
  if observer and rawget(_G,'update')==observer then rawset(_G,'update',previous_update)end
  observer,previous_update,observer_switch=nil,nil,nil
  if selected then local ok,why=selected.release();if not ok then self.message=why;return false,why end end
  self.foreign=nil
  selected,current,observed,observed_at,last_revision,next_attach,next_observe,history,next_check,mismatch,mismatch_at,last_seen=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil;self.ready=false;return true
 end
 function self.observe()
  if not current then return end
  local now=sr.Application.time_since_launch();if next_observe and now<next_observe then return end;next_observe=now+.05
  local ok,value=pcall(function()
   local renderer=ptr(ptr(exe+0x24099e8)+0x338);local n=u32(renderer+0x1600);assert(n>0 and n<=64)
   local rows=read(ptr(renderer+0x1608),n*32);local binding
   for i=0,n-1 do if word(rows,i*32+1)+word(rows,i*32+5)*4294967296==current.native then
    assert(not binding,'Ambiguous world binding');binding=word(rows,i*32+9)+word(rows,i*32+13)*4294967296
   end end
   if not binding then return end
   local gpu={[0x1b44f1e6]='distance',[0x440008]='region',[0xd28fa04f]='close_distance',[0x388fd484]='close_region'}
   local heads=read(renderer+0x1260,288);local camera_id=u32(current.camera+4);local seen={};local views={}
   for j=0,5 do for _,start in ipairs({8,16})do
    local at=word(heads,j*48+start+1)+word(heads,j*48+start+5)*4294967296
    for _=1,32 do
     if at<65536 or at>=2^47 or at%8~=0 or seen[at]then break end;seen[at]=true
     local ran,next_at,fields=pcall(function()
      local size=u32(at+8);local t=read(at+12,4);local kind=t:byte(1)+t:byte(2)*256;local off=t:byte(3)+t:byte(4)*256
      if size<16 or size>65536 or off<16 or off>256 or off>=size then return end
      if kind==7 and size==96 and ptr(at+off)==binding and u32(at+off+24)==camera_id then
       local owner=ptr(at+off+48);local count=u32(owner+0x50);assert(count>0 and count<=1024)
       local metadata,data=ptr(owner+0x58),ptr(owner+0x20);local values={};local found=0
       for i=0,count-1 do local row=read(metadata+i*20,20);local name=gpu[word(row,1)]
        if name then assert(word(row,5)==0 and word(row,9)==1 and word(row,13)<16384);values[name]=float(data+word(row,13));found=found+1 end
       end
       if found==4 then return ptr(at),values end
      end
      return ptr(at)
     end)
     if not ran or not next_at then break end;if fields then views[#views+1]=fields end;at=next_at
    end
   end end
   return model.select_observed_view(views,history and history.accept or nil)
  end)
  if ok and value then observed,observed_at=value,now end
 end
 function self.tick(options,fov,frame,revision)
  if self.foreign and options.dof then return true end
  if not options.dof then self.foreign=nil end
  if not options.dof or options.dof_mode~=1 then local ok,why=self.release();self.message='Native lens waits for Depth of field';return ok,why end
  local id=identity(frame);if current and not same(id,current)then local ok,why=self.release();if not ok then return false,why end end
  current=current or id
  if not observer then
   local previous=assert(rawget(_G,'update'),'Game update callback unavailable');local switch={active=true}
   local function after(...)if switch.active then pcall(self.observe)end;return ...end
   local function wrapped(...)if switch.active then pcall(self.observe)end;return after(previous(...))end
   previous_update,observer,observer_switch=previous,wrapped,switch;rawset(_G,'update',wrapped)
  end
  self.observe()
  local now=sr.Application.time_since_launch()
  if not selected then
   if next_attach and now<next_attach then return true end;next_attach=now+.1
   if not observed or now-observed_at>.5 then self.message='Waiting for current camera lens';return true end
   local ok,p=pcall(function()
    local provider=ptr(current.native+0x230b58);local vt=ptr(provider)
    assert(ptr(vt+0x28)==exe+0x2ad310 and ptr(vt+0x30)==exe+0x2ad520)
    local count,cap=u32(provider+0xb8),u32(provider+0xbc);assert(count<=cap and cap<=4096)
    local entities,classes,instances=ptr(provider+0xc8),ptr(provider+0xd0),ptr(provider+0xd8);local candidates={}
    for i=0,count-1 do if u32(classes+i*4)==0xf7a3101f then
     local worked,value=pcall(profile,i,u32(entities+i*4),u32(instances+i*4),provider,current.native)
     if worked then candidates[#candidates+1]=value end
    end end
    return model.select_lens_source(observed,candidates)
   end)
   if not ok or not p then self.message=ok and'Current lens source unavailable'or tostring(p);return true end
   selected=p;self.ready=true;last_revision=nil;history=model.selection_history(observed,function()return sr.Application.time_since_launch()end)
  end
  if selected.valid()~=true then return false,'Native lens source lifetime changed'end
  if not next_check or now>=next_check then
   next_check=now+.1
   for name,value in pairs(selected.written)do if float(selected.offsets[name])~=value then
    local ok,why=self.release();if not ok then return false,why end
    self.foreign=true;self.message='Lens changed by another writer; toggle Depth of field to reacquire';return true
   end end
   local fields={};for _,name in ipairs({'distance','region','close_distance','close_region'})do fields[name]=float(selected.offsets[name])end
   history.record(fields)
   if observed and observed_at~=last_seen and now-observed_at<.5 then
    last_seen=observed_at
    if history.accept(observed)then mismatch,mismatch_at=nil,nil else
     mismatch=(mismatch or 0)+1;mismatch_at=mismatch_at or now
     if mismatch>=3 and now-mismatch_at>=.25 then
      local ok,why=self.release();if not ok then return false,why end
      self.foreign=true;self.message='Rendered lens changed; toggle Depth of field to reacquire';return true
     end
    end
   end
  end
  if last_revision~=revision or self.last_fov~=fov then
   -- Same physical near/far mapping as the recovered branch postfx.lua.
   local d=lens.depth(options.focus_distance,options.aperture,fov)
   local values={distance=d.near,region=d.region,start=math.max(.05,d.near*.5),finish=math.max(.05,math.min(200,d.region*.5)),near_scale=1,far_scale=1,near_max=1,far_max=1}
   local ok,why=pcall(function()for name,value in pairs(values)do selected.write(name,value);selected.write('close_'..name,value)end end)
   if not ok then self.message=tostring(why);return false,why end
   local fields={};for _,name in ipairs({'distance','region','close_distance','close_region'})do fields[name]=float(selected.offsets[name])end;history.record(fields)
   last_revision,self.last_fov=revision,fov
  end
  self.message='Native focus and aperture active';return true
 end
 return self
end
return M

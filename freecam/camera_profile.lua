-- Verified native world-parameter lens source. Candidate opt-in only.
local M={};local backend
local lens_fields={'distance','region','close_distance','close_region'}
function M.same_lens_values(a,b)
 if not a or not b then return false end
 for _,name in ipairs(lens_fields)do
  local x,y=a[name],b[name]
  if type(x)~='number'or type(y)~='number'or x~=x or y~=y or math.abs(x)>=math.huge or math.abs(y)>=math.huge or math.abs(x-y)>.0001 then return false end
 end
 return true
end
function M.same_camera_identity(a,b)
 for _,name in ipairs({'world_address','native','provider','camera_address','camera_id'})do if a[name]~=b[name]then return false end end
 return true
end
-- Render command packets are temporary observations, not ownership records.
-- Retain a live owned lens across absent/stock packets; only an independently
-- validated different source may transfer its ownership.
function M.retain_lens_source(owned,same_identity,observed,baseline,accept,other_source,observed_at)
 if not owned or not same_identity then return false,'Native lens ownership changed'end
 if not observed or accept(observed)then return true end
 if other_source and other_source(observed,observed_at)then return false,'Different native lens source'end
 return true
end
function M.changed_source_probe(clock,lookup,interval,retry)
 interval=interval or .1;retry=retry or 1;local previous;local changed=false;local last=clock()-interval
 return function(fields)
  local signature={};for _,name in ipairs(lens_fields)do signature[#signature+1]=string.format('%.9g',fields[name])end
  signature=table.concat(signature,'|');local time=clock()
  local delay=signature==previous and(changed and interval or retry)or interval
  if time-last<delay then return false,false end
  previous,last=signature,time
  local found,owner=lookup(fields);changed=found==true
  return changed,true,owner
 end
end
-- Multiple queued views may briefly describe an auxiliary stock lens. A handoff
-- needs repeated independent matches to the same replacement owner, while an
-- own view or absent queue clears suspicion without releasing the valid lens.
function M.confirmed_source_probe(clock,lookup)
 local probe=M.changed_source_probe(clock,lookup);local pending,last_seen
 local function reset()pending,last_seen=nil,nil end
 local function confirm(fields,observed_at)
  if observed_at~=nil and last_seen==observed_at then return false end
  local changed,checked,owner=probe(fields)
  if not checked then return false end
  last_seen=observed_at
  if not changed or owner==nil then reset();return false end
  local time=clock()
  if not pending or pending.owner~=owner or time<pending.time then
   pending={owner=owner,time=time,count=1};return false
  end
  pending.count=pending.count+1
  return pending.count>=3 and time-pending.time>=.25
 end
 return confirm,reset
end
function M.profile_owner_snapshot(entity,class,instance)
 local function identifier(value)return type(value)=='number'and value==value and value%1==0 and value>=0 and value<4294967295 end
 assert(identifier(entity)and entity>0 and class==0xf7a3101f and identifier(instance),'Native profile owner changed')
 return{entity=entity,class=class,instance=instance}
end
function M.same_profile_owner(saved,entity,class,instance)
 return saved.entity==entity and saved.class==class and saved.instance==instance
end
function M.select_lens_source(observed,candidates)
 local names={'distance','region','close_distance','close_region'}
 for _,name in ipairs(names)do local value=observed[name];assert(type(value)=='number'and value==value and math.abs(value)<math.huge,'Incomplete native camera observation')end
 local selected
 for _,candidate in ipairs(candidates)do
  local matches=true
  for _,name in ipairs(names)do local value=candidate.fields[name]
   if type(value)~='number'or value~=value or math.abs(value-observed[name])>.0001 then matches=false;break end
  end
  if matches then assert(not selected,'Native lens source is ambiguous');selected=candidate end
 end
 return selected
end
-- A camera can have more than one queued parameter packet. During validation,
-- prefer the packet for our owned lens instead of treating a stock packet as
-- proof that the active source changed. A missing match is only an observation;
-- transfer still requires the separate validated-source continuity decision.
function M.select_observed_view(candidates,accept)
 local first
 for _,fields in ipairs(candidates)do
  if not first then first=fields end
  if accept and accept(fields)then return fields end
 end
 return first
end
-- Queue ownership exists only during part of render. Keep one pending camera
-- and copied scalar observations for the following frame, never queue pointers.
function M.observation_cache(identity,observe,clock,ttl)
 ttl=ttl or .5
 local pending,cached
 local ids={'world_address','native','provider','camera_address','camera_id'}
 local fields={'distance','region','close_distance','close_region'}
 local function copy(value,names)local out={};for _,key in ipairs(names)do
  local n=assert(value[key],'Native observation field missing: '..key)
  assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'Native observation field invalid: '..key);out[key]=n
 end;return out end
 local function same(a,b)return M.same_camera_identity(a,b)end
 local self={}
 function self.clear()pending,cached=nil,nil end
 function self.request(world,cam,retain)
  local current=copy(identity(world,cam),ids);local time=clock()
  if cached and same(current,cached.identity)and time>=cached.time and time-cached.time<=ttl then
   local values,seen=copy(cached.fields,fields),cached.time;if not retain then self.clear()end;return values,seen
  end
  cached=nil
  pending={world=world,cam=cam,identity=current}
 end
 function self.observe()
  if not pending then return false,'No pending native camera' end
  local ok,current=pcall(identity,pending.world,pending.cam)
  if not ok then self.clear();error(current)end
  current=copy(current,ids)
  if not same(current,pending.identity)then self.clear();return false,'Native observation owner changed' end
  local values=observe(current.native,current.camera_id)
  if not values then cached=nil;return false,'Waiting for a current native camera view' end
  cached={identity=current,fields=copy(values,fields),time=clock()}
  return true
 end
 return self
end
function M.selection_history(initial,clock)
 local history={};local keys={'distance','region','close_distance','close_region'};local self={}
 local function same(a,b)for _,key in ipairs(keys)do if math.abs(a[key]-b[key])>.0001 then return false end end;return true end
 function self.record(fields)
  local copy={};for _,key in ipairs(keys)do copy[key]=assert(fields[key])end
  if history[#history]and same(history[#history].fields,copy)then history[#history].time=clock();return end
  history[#history+1]={fields=copy,time=clock()};while #history>4 do table.remove(history,1)end
 end
 function self.accept(fields)
  local time=clock()
  for i=#history,1,-1 do local item=history[i];if time>=item.time and time-item.time<=.5 and same(fields,item.fields)then return true end end
  return false
 end
 self.record(initial);return self
end
function M.owns_fields(written,valid,read)
 if not valid()then return false end
 for name,value in pairs(written)do if read(name)~=value then return false end end
 return true
end
function M.restore_owned(saved,written,valid,read,write)
 if not valid()then return true,'retired' end
 local foreign=false
 for name,value in pairs(saved)do
  if read(name)==written[name]then write(name,value);assert(read(name)==value,'Native restore readback mismatch')else foreign=true end
 end
 return true,foreign and 'foreign writer preserved' or nil
end
function M.clear_observations()if backend then backend.clear_observations()end end
function M.observe()
 if rawget(_G,'DBF_PHOTO_NATIVE_LENS_CANDIDATE')~=true then M.clear_observations();return false end
 if backend then return backend.observe()end
 return false
end
local function observed_call(previous,is_active,log,before)
 local failures=0
 local function pack(...)return {n=select('#',...),...}end
 local function observe()
  if is_active()then
   local ok,why=pcall(M.observe)
   if not ok then
    failures=failures+1
    if failures==1 or failures%300==0 then pcall(log,'Native camera observation refused: '..tostring(why))end
   else failures=0 end
  else M.clear_observations();failures=0 end
 end
 return function(...)
  if before then observe()end
  -- An original error propagates unchanged. The after-call observation is
  -- skipped on failure; the before-update observation only copied values.
  local result=pack(previous(...))
  observe()
  return unpack(result,1,result.n)
 end
end
function M.after_render(previous,is_active,log)return observed_call(previous,is_active,log,false)end
function M.around_update(previous,is_active,log)return observed_call(previous,is_active,log,true)end
function M.new(sr,world,unit,cam)
 if rawget(_G,'DBF_PHOTO_NATIVE_LENS_CANDIDATE')~=true then return nil end
 if not backend then backend=(function()
local ffi=require('ffi')
pcall(ffi.cdef,[[void *NST_GetCurrentProcess(void) __asm__("GetCurrentProcess");void *NST_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");int NST_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");uint64_t NST_GetTickCount64(void) __asm__("GetTickCount64");]])
local kernel=ffi.load('kernel32');local process=kernel.NST_GetCurrentProcess();local base=tonumber(ffi.cast('uintptr_t',kernel.NST_GetModuleHandleA(nil)))
local address_type=ffi.typeof('uintptr_t');local bytes_type=ffi.typeof('uint8_t[?]');local size_type=ffi.typeof('size_t[1]');local u32_type=ffi.typeof('uint32_t[1]');local u64_type=ffi.typeof('uint64_t[1]');local float_type=ffi.typeof('float[1]');local variant=ffi.new('uint8_t[24]')
local function now()return tonumber(kernel.NST_GetTickCount64())/1000 end
local function read(address,size)
 assert(address>=65536 and address<2^47 and size>0 and size<=65536,'Trial read bounds')
 local data=ffi.new(bytes_type,size);local got=ffi.new(size_type)
 assert(kernel.NST_ReadProcessMemory(process,ffi.cast('void*',address),data,size,got)~=0 and tonumber(got[0])==size,'Trial read failed');return ffi.string(data,size)
end
local function number(address,ctype,size)local v=ffi.new(ctype);ffi.copy(v,read(address,size),size);return tonumber(v[0])end
local function ptr(address)return number(address,u64_type,8)end
local function u32(address)return number(address,u32_type,4)end
local function float(address)return number(address,float_type,4)end
local function rounded(value)local v=ffi.new(float_type,value);return tonumber(v[0])end
local setter_type=ffi.typeof('void(__fastcall *)(void*,uint32_t,uint32_t,const void*)')
local prefix='\x40\x53\x55\x41\x55\x41\x57\x48\x83\xec\x58\x48\x8b\x81\xe8\x00\x00\x00\x4c\x8b\xf9\x44\x8b\xea\x49\x8b\xe9\x4a\x8b\x0c\xe8\x41'
local keys={distance=0xf617a000,region=0x1ed5746a,start=0xf2cba64d,finish=0x594c123a,near_scale=0xd8108f78,far_scale=0xb18edf0c,near_max=0xa7990477,far_max=0xf07fc12e,
 close_distance=0x834c73c0,close_region=0xa5fecfc7,close_start=0xa3b92674,close_finish=0xf90f260e,close_near_scale=0xbcb7968f,close_far_scale=0x32af31e5,close_near_max=0x0db64441,close_far_max=0x209f72cf}
local function profile(world,index,entity)
 local native=ptr(tonumber(ffi.cast(address_type,world)));local provider=ptr(native+0x230c78);local vt=ptr(provider)
 assert(ptr(vt+0x30)==base+0x2dd7f0 and ptr(vt+0x28)==base+0x2dd5e0,'Native parameter methods changed')
 assert(read(base+0x2dd5e0,#prefix)==prefix,'Native setter code changed')
 local capacity=u32(provider+0xc4);assert(index>=0 and index<capacity and capacity<=4096,'Native profile index invalid')
 local entities,classes,instances,blobs=ptr(provider+0xc8),ptr(provider+0xd0),ptr(provider+0xd8),ptr(provider+0xe8)
 local owner=M.profile_owner_snapshot(u32(entities+index*4),u32(classes+index*4),u32(instances+index*4));assert(owner.entity==entity,'Native profile owner changed')
 local blob=ptr(blobs+index*8);local count=u32(blob+4);assert(count>0 and count<=512,'Native parameter field count invalid')
 local signature=read(blob+0x10,count*4);local offsets={};local fields={}
 for i=0,count-1 do local n=ffi.new(u32_type);ffi.copy(n,signature:sub(i*4+1,i*4+4),4)
  for name,key in pairs(keys)do if tonumber(n[0])==key then
   assert(not offsets[name],'Duplicate native parameter');local record=blob+0x10+count*4+i*16
   assert(u32(record)==2,'Native parameter is not float');offsets[name]=record+8;fields[name]=float(record+8)
  end end
 end
 for name in pairs(keys)do assert(offsets[name]and fields[name]==fields[name]and math.abs(fields[name])<100000,'Incomplete native parameter set')end
 local self={fields=fields,saved={},written={},owner=owner,index=index}
 function self.valid()
  return ptr(tonumber(ffi.cast(address_type,world)))==native and ptr(native+0x230c78)==provider and ptr(provider)==vt and ptr(vt+0x28)==base+0x2dd5e0 and
   ptr(provider+0xc8)==entities and ptr(provider+0xd0)==classes and ptr(provider+0xd8)==instances and ptr(provider+0xe8)==blobs and
   M.same_profile_owner(owner,u32(entities+index*4),u32(classes+index*4),u32(instances+index*4))and ptr(blobs+index*8)==blob and u32(blob+4)==count and read(blob+0x10,count*4)==signature
 end
 function self.read(name)assert(self.valid(),'Native profile ownership retired');return float(offsets[name])end
 local raw_valid=self.valid
 function self.valid()local ok,result=pcall(raw_valid);return ok and result==true end
 function self.owned()
  return M.owns_fields(self.written,self.valid,function(name)return float(offsets[name])end)
 end
 local setter=ffi.cast(setter_type,base+0x2dd5e0)
 function self.write(name,value)
  assert(self.valid(),'Native profile ownership retired');assert(type(value)=='number'and value==value and value>=0 and value<=20000,'Native trial value invalid')
  local current=float(offsets[name]);if self.written[name]~=nil then assert(current==self.written[name],'Native field changed by another writer')end
  if current==rounded(value)then return end
  if self.saved[name]==nil then self.saved[name]=current end
  ffi.fill(variant,24,0);local tag=ffi.new(u32_type,2);ffi.copy(variant,tag,4);local v=ffi.new(float_type,value);ffi.copy(variant+8,v,4)
  setter(ffi.cast('void*',provider),index,keys[name],variant)
  assert(self.valid()and float(offsets[name])==rounded(value),'Native setter readback failed');self.written[name]=rounded(value)
 end
 function self.restore()
  local ok,why=M.restore_owned(self.saved,self.written,self.valid,function(name)return float(offsets[name])end,self.write)
  self.saved,self.written={},{}
  return ok,why
 end
 return self
end

local function view_fields(native,camera_id,accept)
 local renderer=ptr(ptr(base+0x23621a8)+0x338);local n=u32(renderer+0x1488);assert(n>0 and n<=64)
 local rows=read(ptr(renderer+0x1490),n*32);local binding
 for i=0,n-1 do local v=ffi.new(u64_type);ffi.copy(v,rows:sub(i*32+1,i*32+8),8);if tonumber(v[0])==native then ffi.copy(v,rows:sub(i*32+9,i*32+16),8);binding=tonumber(v[0])end end
 if not binding then return end
 local gpu={ [0x1b44f1e6]='distance',[0x440008]='region',[0xd28fa04f]='close_distance',[0x388fd484]='close_region'}
 local headers=read(renderer+0x1260,288);local views={}
 for j=0,5 do local seen={}
  for _,start in ipairs({8,16})do local p=ffi.new(u64_type);ffi.copy(p,headers:sub(j*48+start+1,j*48+start+8),8);local at=tonumber(p[0])
   for _=1,32 do
    if at<65536 or at>=2^47 or at%8~=0 or seen[at]then break end;seen[at]=true
    local ran,next_at,fields=pcall(function()
     local size=u32(at+8);local h=read(at+12,4);local k=ffi.new('uint16_t[2]');ffi.copy(k,h,4);local kind,off=tonumber(k[0]),tonumber(k[1])
     if size<16 or size>65536 or off<16 or off>256 or off>=size then return end
     if kind==7 and size==96 and ptr(at+off)==binding and u32(at+off+24)==camera_id then
      local payload=read(at+off,64);local owner=ptr(at+off+48);local count=u32(owner+0x50);assert(count>0 and count<=1024)
      local metadata,data=ptr(owner+0x58),ptr(owner+0x20);local all=read(metadata,count*20);local values={};local found=0
      for i=0,count-1 do local row=ffi.new('uint32_t[5]');ffi.copy(row,all:sub(i*20+1,i*20+20),20);local name=gpu[tonumber(row[0])]
       if name then assert(tonumber(row[1])==0 and tonumber(row[2])==1 and tonumber(row[3])<16384);values[name]=float(data+tonumber(row[3]));found=found+1 end
      end
      assert(ptr(owner+0x58)==metadata and ptr(owner+0x20)==data and read(at+off,64)==payload,'Native view changed during observation')
      if found==4 then return ptr(at),values end
     end
     return ptr(at)
    end)
    if not ran or not next_at then break end
    if fields then
     if not accept then return fields end
     views[#views+1]=fields
    end;at=next_at
   end
  end
 end
 return M.select_observed_view(views,accept)
end
local aliases={focal_distance='distance',focal_region='region',focal_region_start='start',focal_region_end='finish',focal_near_scale='near_scale',focal_far_scale='far_scale',focal_near_max='near_max',focal_far_max='far_max',focal_far_max_close='close_far_max'}
local function identity(world,cam)
 local address=tonumber(ffi.cast(address_type,world));local native=ptr(address)
 local camera=tonumber(ffi.cast(address_type,cam));assert(u32(camera)==0x967d35e4,'Native camera type changed')
 assert(ptr(tonumber(ffi.cast(address_type,sr.Application.main_world())))==native,'Native lens only owns the main world')
 return {world_address=address,native=native,provider=ptr(native+0x230c78),camera_address=camera,camera_id=u32(camera+4)}
end
local observations=M.observation_cache(identity,view_fields,now)
local function lens_sources(world,native)
 local provider=ptr(native+0x230c78);local capacity=u32(provider+0xc4);assert(capacity>0 and capacity<=4096)
 local entities,classes=ptr(provider+0xc8),ptr(provider+0xd0);local candidates={}
 for i=0,capacity-1 do
  local entity=u32(entities+i*4)
  if entity>0 and u32(classes+i*4)==0xf7a3101f then
   local worked,candidate=pcall(profile,world,i,entity)
   if worked and candidate.valid()then candidates[#candidates+1]=candidate end
  end
 end
 return candidates
end
local function new(sr,world,unit,cam)
 local current=identity(world,cam);local native=current.native
 local observed=view_fields(native,current.camera_id)
 if observed then observations.clear()else observed=observations.request(world,cam)end
 if not observed then return nil,'Waiting for a current native camera view' end
 local candidates=lens_sources(world,native)
 local selected=M.select_lens_source(observed,candidates)
 if not selected then return nil,'Current native camera source unavailable'end
 local self={world=world,unit=unit,cam=cam,native_numeric_candidate=true,parameters={}}
 local history=M.selection_history(observed,now)
 local different_source,reset_source_probe=M.confirmed_source_probe(now,function(fields)
  local ok,candidate=pcall(function()return M.select_lens_source(fields,lens_sources(world,native))end)
  if not ok or not candidate then return false end
  local changed=candidate.index~=selected.index or not M.same_profile_owner(selected.owner,candidate.owner.entity,candidate.owner.class,candidate.owner.instance)
  return changed,table.concat({candidate.index,candidate.owner.entity,candidate.owner.class,candidate.owner.instance},':')
 end)
 local function current_fields()local values={};for _,name in ipairs({'distance','region','close_distance','close_region'})do values[name]=selected.read(name)end;return values end
 for alias in pairs(aliases)do self.parameters[alias]=true end
 function self.read(alias)return selected.read(assert(aliases[alias],'Unknown native lens parameter'))end
 function self.write(alias,value)
  local name=assert(aliases[alias],'Unknown native lens parameter');selected.write(name,value)
  if keys['close_'..name]then selected.write('close_'..name,value)end
 end
 function self.restore()local ok,why=selected.restore();assert(ok,why);self.retired=why=='retired';return true end
 function self.flush()if not self.retired then assert(selected.valid(),'Native lens source retired');history.record(current_fields())end end
 function self.tick()
  local owned=selected.owned();local same_identity=M.same_camera_identity(current,identity(world,cam))
  if not owned or not same_identity then self.handoff=true;return false end
  local values,seen=observations.request(world,cam,true)
  if not values or not history.accept(values)then
   local current_view=view_fields(native,current.camera_id,history.accept)
   if current_view then values=current_view;seen=now()end
  end
  if values and(not seen or now()<seen or now()-seen>.5)then values=nil end
  if not values or history.accept(values)then reset_source_probe()end
  if not M.retain_lens_source(owned,same_identity,values,selected.fields,history.accept,different_source,seen)then self.handoff=true;return false end
  return true
 end
 function self.release()if not self.handoff then observations.clear()end;local ok,why=selected.restore();self.retired=why=='retired';return ok,why end
 observations.clear()
 return self
end
return {new=new,observe=observations.observe,clear_observations=observations.clear}

end)()end
 return backend.new(sr,world,unit,cam)
end
return M

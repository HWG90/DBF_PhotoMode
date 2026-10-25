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

return M

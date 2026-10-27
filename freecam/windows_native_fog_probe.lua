-- Explicit one-shot, read-only native fog inventory. Never applies a profile.
local M={}
local mapping='core/stingray_renderer/shading_environment_components/fog'
local fields={{'fog_enabled','boolean'},{'fog_parameters',3},{'fog_color',3},{'fog_dustiness',1},
 {'near_ground_fog_height',1},{'near_ground_fog_density',1},{'near_ground_fog_color',3}}
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<math.huge end
function M.consume(folder,pid)
 local path=folder..'/wj-native-fog.request';local f=io.open(path,'rb');if not f then return false end
 local text=f:read(64);f:close()
 return text=='native-fog-read-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
function M.new(sr,now,measure,log)
 local A,W,E,R,V=sr.Application,sr.World,sr.EntityManager,sr.RenderDataComponent,sr.Vector3
 local self={done=false,complete=false,profiles={}};local state;local calls=0;local ending
 local function call(fn,...)calls=calls+1;return fn(...)end
 local function clock()local n=measure();assert(finite(n)and n>=0,'Fog operation clock unavailable');return n end
 local function finish(complete,reason)
  self.done=true;self.complete=complete;self.reason=reason
  log(string.format('Native fog probe: complete=%s profiles=%d entities=%d instances=%d calls=%d max_step_ms=%.3f reason=%s; writes=0; idle',
   tostring(complete),#self.profiles,state and state.scanned or 0,state and state.instances or 0,
   state and state.calls or 0,state and state.max_ms or 0,reason))
  state=nil -- Release all engine handles and enumeration tables.
 end
 local function ids(entity)
  local out={call(R.instances,state.manager,entity)}
  if #out==1 and type(out[1])=='table'then out=out[1]end
  assert(#out<=64,'Fog component bound exceeded')
  local count=0
  for k,id in pairs(out)do
   count=count+1;assert(count<=64 and type(k)=='number'and k%1==0 and k>=1 and k<=#out,'Invalid fog instance list')
   assert(type(id)=='userdata'or finite(id)and id%1==0 and id>=-2147483648 and id<=4294967295,'Invalid fog instance token')
  end
  assert(count==#out,'Sparse fog instance list');return out
 end
 local function get(entity,id,key)return call(R.get_property,state.manager,entity,id,{key})end
 local function vector(value,key)
  -- Only accept the engine's Vector3 userdata. Copy it within this update.
  assert(type(value)=='userdata','Fog '..key..' expected Vector3, got '..type(value))
  local values={call(V.x,value),call(V.y,value),call(V.z,value)}
  for i=1,3 do assert(finite(values[i]),'Nonfinite fog vector')end
  return values
 end
 local function stop(complete,reason)ending={complete,reason}end
 local function step(active)
  if not active then if state then stop(false,'Photo Mode closed')end;return end
  if not state then
   local world=call(A.main_world);assert(world,'Fog world unavailable')
   local entities=call(W.entities,world);assert(type(entities)=='table'and #entities<=4096,'Fog entity inventory exceeds 4096')
   local count=0;for k,e in pairs(entities)do
    count=count+1;assert(count<=4096 and type(k)=='number'and k%1==0 and k>=1 and k<=#entities and type(e)=='userdata','Invalid fog entity list')
   end
   assert(count==#entities,'Sparse fog entity list')
   state={world=world,manager=assert(call(E.render_data_component,world)),entities=entities,index=1,scanned=0,instances=0,calls=0,max_ms=0,started=now()}
   log('Native fog probe started; read-only; exact mapping required; 4096 entities/16 profiles/10 seconds maximum')
  end
  if call(A.main_world)~=state.world then stop(false,'World changed');return end
  if now()-state.started>10 then stop(false,'Ten-second budget');return end
  local pending=state.pending
  if pending then
   assert(call(E.alive,pending.entity)==true,'Fog entity retired')
   local current=ids(pending.entity)
   assert(#current==#pending.ids,'Fog component membership changed')
   for i,id in ipairs(current)do assert(id==pending.ids[i],'Fog component identity changed')end
  end
  local examined=0;local began=clock()
  while state.index<=#state.entities and examined<8 and calls<32 and clock()-began<.002 do
   if not state.pending then
    local entity=state.entities[state.index];state.scanned=state.scanned+1;examined=examined+1
    if call(E.alive,entity)==true then state.pending={entity=entity,ids=ids(entity),index=1}
    else state.index=state.index+1 end
   end
   pending=state.pending
   if pending then
    local id=pending.ids[pending.index]
    if id~=nil then
     pending.index=pending.index+1;state.instances=state.instances+1
     if state.instances>8192 then stop(false,'Instance budget');return end
     local name=get(pending.entity,id,'shading_environment_mapping')
     if name==mapping then
      if #self.profiles>=16 then stop(false,'Profile budget');return end
      local profile={entity=tostring(pending.entity),instance=tostring(id),values={},types={}}
      for _,field in ipairs(fields)do
       local key=field[1];local value=get(pending.entity,id,key);profile.types[key]=type(value)
       if field[2]=='boolean'then assert(type(value)=='boolean','Fog '..key..' expected boolean, got '..type(value))
       elseif field[2]==3 then value=vector(value,key)else assert(finite(value),'Fog '..key..' expected scalar, got '..type(value))end
       profile.values[key]=value
      end
      assert(get(pending.entity,id,'shading_environment_mapping')==mapping,'Fog mapping changed')
      self.profiles[#self.profiles+1]=profile
      local parts={}
      for _,field in ipairs(fields)do
       local key=field[1];local v=profile.values[key]
       parts[#parts+1]=key..'='..(type(v)=='table'and string.format('(%.9g,%.9g,%.9g)',v[1],v[2],v[3])or type(v)=='boolean'and tostring(v)or string.format('%.9g',v))
      end
      log('Native fog profile: entity='..profile.entity..' instance='..profile.instance..' '..table.concat(parts,' '))
      if pending.index>#pending.ids then state.pending=nil;state.index=state.index+1 end
      break -- At most one complete profile per update.
     end
    end
    if pending.index>#pending.ids then state.pending=nil;state.index=state.index+1 end
   end
  end
  if state.index>#state.entities then state.finished=true end
 end
 function self.tick(active)
  if self.done or not active and not state then return end
  calls=0;ending=nil;local elapsed=0
  local ok,why=pcall(function()
   local began=clock();step(active);elapsed=(clock()-began)*1000
  end)
  if state then state.calls=state.calls+calls;state.max_ms=math.max(state.max_ms,elapsed)end
  if not ok then finish(false,tostring(why))
  elseif ending then finish(ending[1],ending[2])
  elseif state and state.finished then finish(true,'Inventory exhausted; live rendering unverified')end
 end
 function self.release()if not self.done then finish(false,'Disposed')end end
 return self
end
return M

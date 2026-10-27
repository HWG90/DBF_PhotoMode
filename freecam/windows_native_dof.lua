-- Read-only native lens discovery. No profile is written until its active-view
-- ownership is established. One bounded inventory per camera activation.
local M={}
local keys={}
for _,suffix in ipairs({'distance','region','region_start','region_end','near_scale','far_scale','near_max','far_max'})do
 for _,close in ipairs({'','_close'})do keys[#keys+1]='dof_focal_'..suffix..close end
end
function M.new(sr,log,contract)
 assert(contract==nil or contract=='entity-getter-v1'or contract=='entity-owner-v1','Unknown native lens reader contract')
 local entity_reader=contract~=nil
 local owner_reader=contract=='entity-owner-v1'
 local self={ready=false,message='Native lens controller: locating active profile'}
 local state,finished,last_world,last_camera,last_generation
 local function instances(provider,entity)
  local result={provider.api.instances(provider.handle,entity)}
  local shape=#result==1 and type(result[1])or('tuple:'..#result)
  if #result==1 and type(result[1])=='table'then
   result=result[1]
   assert(#result<=64,'Native component instance count exceeds bound')
   local count=0
   for key in pairs(result)do
    count=count+1;assert(count<=64 and type(key)=='number'and key%1==0 and key>=1 and key<=#result,'Non-array native instance table')
   end
   assert(count==#result,'Sparse native instance table')
  end
  assert(#result<=64,'Native component instance count exceeds bound')
  local signature=shape..':'..(#result>0 and type(result[1])or'empty')
  if not provider.shapes[signature]then
   provider.shapes[signature]=true;log('Native DoF instances: provider='..provider.name..' shape='..signature..' count='..#result)
  end
  for i=1,#result do
   local value=result[i];local kind=type(value)
   -- Windows exposes some 32-bit IDs as signed Lua integers, including the
   -- observed lens ID -140308449 (0xf7a3101f). Preserve the returned token.
   assert(kind=='userdata'or kind=='number'and value>=-2147483648 and value<=4294967295 and value%1==0,
    'Native instance rejected: type='..kind..' value='..(kind=='number'and string.format('%.17g',value)or tostring(value)))
  end
  return result
 end
 local function disable(provider,reason)
  if not provider.disabled then
   provider.disabled=true;state.failures=state.failures+1
   log('Native DoF provider unavailable: '..provider.name..'; '..tostring(reason)..'; continuing other providers')
  end
 end
 local function read_instances(provider,entity)
  if provider.disabled then return{}end
  local ok,value=pcall(instances,provider,entity)
  if not ok then disable(provider,value);return{}end
  return value
 end
 local function property(provider,entity,instance,key)
  if provider.disabled then return nil end
  local ok,value
  if entity_reader then
   -- Qualified on Windows build 26088801. Entity and component ID both come
   -- from this provider's live inventory; no fabricated object or numeric write.
   ok,value=pcall(provider.api.get_property,provider.handle,entity,instance,{key})
  else ok,value=pcall(provider.api.get_property,provider.handle,instance,key)end
  if not ok then disable(provider,value);return nil end
  return value
 end
 local function report(text)self.message=text;log('Native DoF discovery: '..text)end
 -- Read associations once for complete lens candidates. A matching unit is
 -- evidence to investigate, not authority to modify a renderer profile.
 local function owner(entity,instance,provider,frame)
  local count=0
  local function read(label,fn,...)
   if state.owner_failed[label]or type(fn)~='function'then return nil end
   count=count+1
   local ok,value=pcall(fn,...)
   if not ok then
    state.owner_failed[label]=true
    log('Native DoF association unavailable: '..label..'; '..tostring(value))
    return nil
   end
   return value
  end
  local name=read('entity name',sr.EntityManager.debug_name,entity)
  local mapping=read('mapping',provider.api.get_property,provider.handle,entity,instance,{'shading_environment_mapping'})
  local unit
  if state.unit_provider then
   local component=state.unit_provider
   local ids=read('unit instances',function()return{sr.UnitComponent.instances(component,entity)}end)
   if ids and #ids>0 and #ids<=64 then unit=read('entity unit',sr.UnitComponent.unit,component,entity)end
  end
  local resource,cameras
  if unit and read('unit alive',sr.Unit.alive,unit)then
   resource=read('unit resource',sr.Unit.resource_name,unit)
   cameras=read('unit cameras',sr.Unit.num_cameras,unit)
  end
  log('Native DoF association: entity='..tostring(entity)..' name='..tostring(name)..' mapping='..tostring(mapping)..
   ' unit='..tostring(unit)..' resource='..tostring(resource)..' cameras='..tostring(cameras)..
   ' matches_camera_unit='..tostring(unit~=nil and frame.unit~=nil and unit==frame.unit))
  return count
 end
 local function finish(reason)
  self.profile_count=state and state.matches or 0;self.done=true
  self.complete=state and state.cursor>#state.entities and state.failures==0 or false
  if state then
   log(string.format('Native DoF inventory: entities=%d/%d instances=%d matches=%d calls=%d max_step_ms=%.3f provider_failures=%d; writes=0; %s',
    state.cursor-1,#state.entities,state.instances,state.matches,state.calls,state.max_ms,state.failures,reason))
  end
  state=nil;finished=true;self.ready=false;report(reason)
 end
 function self.release()
  state,finished,last_world,last_camera,last_generation=nil,nil,nil,nil,nil
  self.profile_count,self.done=0,false
  self.profiles,self.complete=nil,false
  self.ready=false;return true
 end
 local function step(options,fov,frame)
  if last_world and(frame.world~=last_world or frame.camera~=last_camera or frame.generation~=last_generation)then self.release()end
  if finished then return true end
  last_world,last_camera,last_generation=frame.world,frame.camera,frame.generation
  if not state then
   local entities=assert(sr.World.entities(frame.world),'Native world entities unavailable')
   assert(type(entities)=='table'and #entities<=32768,'Native entity inventory exceeds bound')
   local providers={}
   for _,entry in ipairs({{'RenderDataComponent','render_data_component',true},{'DataComponent','data_component',false}})do
    local api,factory=sr[entry[1]],sr.EntityManager[entry[2]]
    if (not entity_reader or entry[1]=='RenderDataComponent')and type(api)=='table'and type(api.instances)=='function'and type(api.get_property)=='function'and type(factory)=='function'then
     local handle=entry[3]and factory(frame.world)or factory()
     assert(handle,'Native component unavailable: '..entry[1])
     providers[#providers+1]={name=entry[1],api=api,handle=handle,shapes={}}
    end
   end
   state={entities=entities,providers=providers,cursor=1,provider=1,instances=0,matches=0,calls=0,max_ms=0,failures=0,started=sr.Application.time_since_launch()}
   self.profiles={}
   if owner_reader then
    state.owner_failed={}
    log('Native DoF active camera: unit='..tostring(frame.unit)..' camera='..tostring(frame.camera))
    if sr.UnitComponent and type(sr.UnitComponent.instances)=='function'and type(sr.UnitComponent.unit)=='function'and type(sr.EntityManager.unit_component)=='function'then
     local ok,value=pcall(sr.EntityManager.unit_component,frame.world)
     if ok then state.unit_provider=value else log('Native DoF unit provider unavailable: '..tostring(value))end
    end
   end
   report('Reading native lens profiles; contract='..tostring(contract or'legacy-instance')..'; no writes')
   if #providers==0 then finish('Native component APIs unavailable');return true end
  end
  local started=os.clock();local calls=0
  if state.pending then
   local entity=state.entities[state.cursor]
   if not sr.EntityManager.alive(entity)then finish('Entity retired during discovery');return true end
   local current=read_instances(state.providers[state.provider],entity);calls=calls+1
   local previous=state.pending.instances
   if #current~=#previous then finish('Components changed during discovery; reopen Photo Mode to retry');return true end
   for i,value in ipairs(current)do
    if value~=previous[i]then finish('Components changed during discovery; reopen Photo Mode to retry');return true end
   end
   state.pending.instances=current
  end
  while state.cursor<=#state.entities and calls<128 do
   if sr.Application.main_world()~=frame.world then finish('World changed during discovery');return true end
   local entity=state.entities[state.cursor]
   local provider=state.providers[state.provider]
   if not state.pending then
    local current={}
    if not provider.disabled and sr.EntityManager.alive(entity)then current=read_instances(provider,entity);calls=calls+1 end
    state.pending={instances=current,cursor=1}
   end
   local pending=state.pending
   local instance=pending.instances[pending.cursor]
   if instance~=nil then
    pending.cursor=pending.cursor+1
    if sr.EntityManager.alive(entity)and(not entity_reader or instance==-140308449 or instance==4154658847)then
     if entity_reader then assert(type(entity)=='userdata','Entity getter requires an engine entity object')end
     state.instances=state.instances+1
     if entity_reader and state.instances>16 then finish('Entity getter reached sixteen-lens limit');return true end
     local first=property(provider,entity,instance,keys[1]);calls=calls+1
     if entity_reader then log('Native DoF entity getter: candidate='..state.instances..' id='..tostring(instance)..' first_type='..type(first)..' first='..tostring(first))end
     if type(first)=='number'and first==first and math.abs(first)<=20000 then
      local values={keys[1]..'='..string.format('%.6g',first)};local complete=true;local fields={[keys[1]]=first}
      for i=2,#keys do
       local value=property(provider,entity,instance,keys[i]);calls=calls+1
       if type(value)~='number'or value~=value or math.abs(value)>20000 then complete=false;break end
       values[#values+1]=keys[i]..'='..string.format('%.6g',value)
       fields[keys[i]]=value
      end
      if complete then
       state.matches=state.matches+1
       self.profiles[#self.profiles+1]={entity=entity,id=instance,values=fields}
       if state.matches<=16 then log('Native DoF profile: provider='..provider.name..' entity='..tostring(entity)..' instance='..tostring(instance)..' '..table.concat(values,' '))end
       if owner_reader then calls=calls+owner(entity,instance,provider,frame)end
      end
     end
     if state.instances>=8192 then finish('Native profile inventory reached instance limit');return true end
    end
   end
   if pending.cursor>#pending.instances then
    state.pending=nil;state.provider=state.provider+1
    if state.provider>#state.providers then state.provider=1;state.cursor=state.cursor+1 end
   end
   if (os.clock()-started)*1000>=1 then break end
  end
  state.calls=state.calls+calls;state.max_ms=math.max(state.max_ms,(os.clock()-started)*1000)
  if state.cursor>#state.entities then
   finish(state.matches>0 and 'Native profiles found; active-camera ownership unverified' or 'No complete native lens profile exposed by component APIs')
  elseif sr.Application.time_since_launch()-state.started>=4 then finish('Native profile discovery reached four-second limit')end
  return true
 end
 function self.tick(options,fov,frame)
  local ok,value=pcall(step,options,fov,frame)
  if not ok then finish('Native profile discovery unavailable: '..tostring(value))end
  return true
 end
 function self.observe()end
 return self
end
return M

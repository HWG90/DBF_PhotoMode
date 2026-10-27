-- Read-only bridge qualification: legacy Unit -> entity -> animation blender.
-- One bounded inventory per explicit capture; no setters or idle discovery.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function instances(api,handle,entity)
 local rows={api.instances(handle,entity)}
 if #rows==1 and type(rows[1])=='table'then rows=rows[1]end
 local result={};local count=0
 for key,id in pairs(rows)do
  count=count+1;assert(count<=16,'Animation owner instance bound exceeded')
  assert(finite(key)and key>=1 and key%1==0,'Animation owner instance key invalid')
  assert(finite(id)and id%1==0 and id>=-2147483648 and id<=4294967295,'Animation owner instance token invalid')
  result[#result+1]=id
 end
 table.sort(result);return result
end
function M.new(sr,world,rows,log,measure)
 local U,E,UC,BC=sr.Unit,sr.EntityManager,sr.UnitComponent,sr.AnimationBlenderComponent
 local self={done=false,max_ms=0};local state;local owners={};local scanned,linked,blenders=0,0,0
 local function emit(s)pcall(log,'Animation source: '..s)end
 local function finish(reason,complete)
  if self.slice_started then self.max_ms=math.max(self.max_ms,(measure()-self.slice_started)*1000)end
  if self.max_ms>8 then complete=false;reason='8 ms work limit'end
  state=nil;self.done=true;self.complete=complete==true
  if not self.complete then owners={}end
  emit(string.format('inventory complete entities=%d linked_units=%d blenders=%d max_step_ms=%.3f; %s; writes=0',scanned,linked,blenders,self.max_ms,reason))
 end
 local ok,why=pcall(function()
  assert(type(sr.World.entities)=='function'and type(E.unit_component)=='function'and type(E.animation_blender_component)=='function','Component providers unavailable')
  assert(type(UC.instances)=='function'and type(UC.unit)=='function'and type(BC.instances)=='function'and type(BC.delta_transform)=='function','Component getters unavailable')
  local targets={};for _,row in ipairs(rows)do if row.count==107 and row.resource:find('4d1c334d294dfa97',1,true)then targets[row.unit]=true end end
  if not next(targets)then finish('no qualified Helldivers');return end
  local started=measure()
  self.slice_started=started
  local entities=sr.World.entities(world);assert(type(entities)=='table','Entity inventory unavailable')
  local unit_provider=assert(E.unit_component(world),'Unit provider unavailable')
  local blender_provider=assert(E.animation_blender_component(world),'Animation provider unavailable')
  assert(type(unit_provider)=='userdata'and type(blender_provider)=='userdata','Component provider types changed')
  state={entities=entities,targets=targets,unit_provider=unit_provider,blender_provider=blender_provider}
  self.max_ms=math.max(self.max_ms,(measure()-started)*1000)
  assert(self.max_ms<=8,'Animation owner initialization exceeded 8 ms')
 end)
 if not ok then finish(tostring(why))end
 function self.tick()
  if self.done then return end
  local started=measure();local count=0;self.slice_started=started
  local ok,why=pcall(function()
   assert(sr.Application.main_world()==world,'Animation owner world retired')
   while count<8 and measure()-started<.002 do
    local key,entity=next(state.entities,state.key);state.key=key
    if key==nil then finish('bounded lookup finished',true);return end
    scanned=scanned+1;count=count+1;assert(scanned<=4096,'Animation owner entity bound exceeded')
    assert(type(entity)=='userdata','Entity inventory type changed')
    if E.alive(entity)and #instances(UC,state.unit_provider,entity)>0 then
     local unit=UC.unit(state.unit_provider,entity)
     if state.targets[unit]and U.alive(unit)and U.world(unit)==world then
      local previous=owners[unit]
      if previous then previous.ambiguous=true
      else
       local ids=instances(BC,state.blender_provider,entity)
       owners[unit]={entity=entity,ids=ids,unit_provider=state.unit_provider,blender_provider=state.blender_provider}
       linked=linked+1;if #ids==1 then blenders=blenders+1 end
       emit('matched Helldiver entity='..tostring(entity)..' blender_instances='..#ids)
      end
     end
    end
   end
  end)
  self.max_ms=math.max(self.max_ms,(measure()-started)*1000)
  if not ok or self.max_ms>8 then finish(not ok and tostring(why)or'8 ms work limit')end
 end
 function self.read(unit)
  assert(self.done,'Animation owner inventory incomplete')
  local owner=owners[unit]
  if not owner then return nil,'no entity mapping'end
  if owner.ambiguous or #owner.ids~=1 then return nil,'no unique animation component'end
  assert(sr.Application.main_world()==world and U.alive(unit)and U.world(unit)==world,'Animation owner subject retired')
  assert(E.alive(owner.entity),'Animation owner entity retired')
  assert(#instances(UC,owner.unit_provider,owner.entity)>0 and UC.unit(owner.unit_provider,owner.entity)==unit,'Animation owner unit changed')
  local ids=instances(BC,owner.blender_provider,owner.entity)
  assert(#ids==1 and ids[1]==owner.ids[1],'Animation component changed')
  local values={sr.Matrix4x4.to_elements(BC.delta_transform(owner.blender_provider,owner.entity))}
  assert(#values==12,'Animation delta matrix shape changed')
  for i=1,12 do assert(finite(values[i]),'Animation delta matrix invalid')end
  return values
 end
 return self
end
return M

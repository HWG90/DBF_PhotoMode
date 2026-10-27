-- Windows native DoF controller. Override all fully qualified DoF profiles
-- uniformly so the engine retains its blend selection. Never select by proximity.
local M={}
local mapping='core/stingray_renderer/shading_environment_components/dof'
local names={'distance','region','region_start','region_end','near_scale','far_scale','near_max','far_max'}
local keys={};for _,name in ipairs(names)do for _,close in ipairs({'','_close'})do keys[#keys+1]='dof_focal_'..name..close end end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<=20000 end
local function rounded(v)
 if v==0 then return 0 end
 local m,e=math.frexp(v);local s=m*16777216;local q=math.floor(s);local f=s-q
 if f>.5 or f==.5 and q%2==1 then q=q+1 end
 return math.ldexp(q,e-24)
end
function M.new(sr,log,lens,discovery)
 local reader=discovery.new(sr,log,'entity-getter-v1')
 local self={ready=false,message='Native DoF override: locating profiles'}
 local world,camera,generation,manager,profiles,targets,cursor,last_focus,last_aperture,last_fov,blocked,max_step_ms
 local api=assert(sr.RenderDataComponent)
 assert(type(api.set_property)=='function','Render-data setter unavailable')
 local function get(p,key)return api.get_property(manager,p.entity,p.id,{key})end
 local function valid(p)
  if sr.Application.main_world()~=world or not sr.EntityManager.alive(p.entity)then return false end
  local ids={api.instances(manager,p.entity)}
  if #ids==1 and type(ids[1])=='table'then ids=ids[1]end
  assert(#ids<=64,'Lens membership exceeds bound')
  for _,id in ipairs(ids)do if id==p.id then return get(p,'shading_environment_mapping')==mapping end end
  return false
 end
 local function set(p,key,before,target)
  assert(get(p,key)==before,'Native lens changed before write')
  p.saved[key]=p.saved[key]or before
  p.written[key]=target -- Retain cleanup authority if the setter mutates then errors.
  assert(api.set_property(manager,p.entity,p.id,{key},target)~=false,'Native lens setter refused')
  assert(get(p,key)==target,'Native lens setter readback differs')
 end
 function self.release()
  self.ready=false
  for _,p in ipairs(profiles or{})do
   local ok,why=pcall(function()
    if valid(p)then
     for _,key in ipairs(keys)do
      local written=p.written[key]
      if written~=nil and get(p,key)==written then
       assert(api.set_property(manager,p.entity,p.id,{key},p.saved[key])~=false,'Native lens restoration refused')
       assert(get(p,key)==p.saved[key],'Native lens restoration readback differs')
      end
      p.written[key]=nil
     end
    else p.written={}end
   end)
   if not ok then self.message=tostring(why);return false,self.message end
  end
  if profiles then log('Native DoF override: restored owned fields; foreign changes preserved')end
  reader.release();world,camera,generation,manager,profiles,targets,cursor,last_focus,last_aperture,last_fov=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
  return true
 end
 local function step(o,fov,frame)
  if not o.dof or o.dof_mode~=1 then
   local ok,why=self.release();if ok then blocked=nil;self.message='Native DoF override inactive'end;return ok,why
  end
  if blocked then if profiles then return self.release()end;return true end
  if world and(frame.world~=world or frame.camera~=camera or frame.generation~=generation)then
   local ok,why=self.release();if not ok then return false,why end
  end
  world,camera,generation=frame.world,frame.camera,frame.generation
  if not profiles then
   reader.tick(o,fov,frame)
   if not reader.done then return true end
   assert(reader.complete and reader.profile_count>0 and reader.profile_count<=16,'Complete native lens inventory unavailable')
   manager=assert(sr.EntityManager.render_data_component(world));profiles=reader.profiles
   for _,p in ipairs(profiles)do p.saved={};p.written={}end
   -- Validate the entire set before the first write. A profile merely having
   -- numeric keys is insufficient: its schema mapping must be exact too.
   for _,p in ipairs(profiles)do
    assert(valid(p),'Native DoF profile identity changed')
    for _,key in ipairs(keys)do assert(finite(p.values[key]),'Native DoF baseline unavailable')end
   end
  end
  -- Finish the current bounded pass before taking the latest requested values.
  -- Continuous slider/autofocus changes must not starve the later profiles.
  if not cursor and(last_focus~=o.focus_distance or last_aperture~=o.aperture or last_fov~=fov)then
   assert(finite(o.focus_distance)and o.focus_distance>=.05 and finite(o.aperture)and o.aperture>0 and finite(fov)and fov>0 and fov<math.pi,'Invalid photographic lens')
   local d=lens.depth(o.focus_distance,o.aperture,fov)
   local values={distance=d.near,region=d.region,region_start=math.max(.05,d.near*.5),region_end=math.max(.05,math.min(200,d.region*.5)),near_scale=1,far_scale=1,near_max=1,far_max=1}
   targets={};for _,name in ipairs(names)do assert(finite(values[name]));for _,close in ipairs({'','_close'})do targets['dof_focal_'..name..close]=rounded(values[name])end end
   cursor=1;max_step_ms=0;last_focus,last_aperture,last_fov=o.focus_distance,o.aperture,fov
  end
  if cursor then
   local started=os.clock();local p=profiles[cursor];assert(valid(p),'Native DoF profile retired')
   for _,key in ipairs(keys)do
    local expected=p.written[key]or p.values[key];local actual=get(p,key)
    assert(actual==expected,'Native DoF changed by the game; override stopped')
    if actual~=targets[key]then set(p,key,actual,targets[key])end
   end
   max_step_ms=math.max(max_step_ms,(os.clock()-started)*1000)
   cursor=cursor+1
   if cursor>#profiles then
    cursor=nil;self.ready=true;self.message='Native focus and aperture active'
    log(string.format('Native DoF override: focus=%.6g aperture=%.6g; all %d profiles acknowledged; max_step_ms=%.3f; steady state idle',last_focus,last_aperture,#profiles,max_step_ms))
   end
  end
  return true
 end
 function self.tick(o,fov,frame)
  local ok,result,why=pcall(step,o,fov,frame)
  if ok then return result,why end
  blocked=true;local failure=tostring(result);log('Native DoF override stopped: '..failure)
  local restored,reason=self.release();self.message=failure
  return restored,reason
 end
 function self.observe()end
 return self
end
return M

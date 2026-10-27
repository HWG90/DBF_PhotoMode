-- Ordinary Lua engine lens candidate. Uses an environment actually submitted by
-- the game's render callback; never constructs an environment or guesses a handle.
local M={}
local names={'distance','region','start','finish','near_scale','far_scale','near_max','far_max'}
local suffix={distance='distance',region='region',start='region_start',finish='region_end',near_scale='near_scale',far_scale='far_scale',near_max='near_max',far_max='far_max'}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<=20000 end
function M.new(sr,lens,log)
 local A,S=assert(sr.Application),assert(sr.ShadingEnvironment,'Engine shading environment API unavailable')
 for _,name in ipairs({'scalar','set_scalar','apply'})do assert(type(S[name])=='function','Engine lens missing '..name)end
 assert(type(A.render_world)=='function','Engine render submission unavailable')
 local self={ready=false,message='Windows lens waits for the active camera environment'}
 local env,world,camera,generation,saved,written,targets,revision,previous_render,render_wrapper,previous_apply,apply_wrapper,frames,blocked
 local function detach_render()
  if render_wrapper and A.render_world==render_wrapper then A.render_world=previous_render end
  render_wrapper,previous_render=nil,nil
 end
 local function apply_targets()
  assert(sr.Application.main_world()==world,'Lens world retired')
  for key,value in pairs(targets)do
   local actual=S.scalar(env,key);assert(finite(actual),'Lens field unavailable: '..key)
   if actual~=value then
    written[key]=value -- Retain restoration authority before a setter may fail.
    assert(S.set_scalar(env,key,value)~=false,'Engine lens write refused')
    assert(math.abs(S.scalar(env,key)-value)<.0001,'Engine lens readback differs')
   end
  end
 end
 function self.release()
  detach_render()
  if apply_wrapper and S.apply==apply_wrapper then S.apply=previous_apply end
  apply_wrapper,previous_apply=nil,nil
  if env and sr.Application.main_world()==world then
   for key,value in pairs(saved)do
    if written[key]~=nil then
     local ok,why=pcall(function()
      if math.abs(S.scalar(env,key)-written[key])<.0001 then
       assert(S.set_scalar(env,key,value)~=false,'Lens restoration refused')
       assert(math.abs(S.scalar(env,key)-value)<.0001,'Lens restoration unacknowledged')
      end
     end)
     if not ok then return false,tostring(why)end
     written[key]=nil
    end
   end
   local ok,why=pcall(S.apply,env);if not ok then return false,tostring(why)end
  end
  env,world,camera,generation,saved,written,targets,revision=nil,nil,nil,nil,nil,nil,nil,nil
  self.ready=false;return true
 end
 local function capture(candidate)
  local baseline={}
  for _,name in ipairs(names)do for _,close in ipairs({'','_close'})do
   local key='dof_focal_'..suffix[name]..close
   local value=S.scalar(candidate,key);assert(finite(value),'Submitted environment lacks '..key)
   baseline[key]=value
  end end
  env,saved,written=candidate,baseline,{}
  previous_apply=S.apply
  local original_apply=previous_apply
  apply_wrapper=function(...)
   local value=...
   if value==env and targets and not blocked and sr.Application.main_world()==world then
    local ok,why=pcall(apply_targets)
    if not ok then self.ready=false;self.message=tostring(why);blocked=true end
   end
   return original_apply(...)
  end
  S.apply=apply_wrapper
  apply_targets();S.apply(env);assert(not blocked,self.message)
  self.ready=true;self.message='Windows engine lens applied; visual validation pending'
  log(self.message)
 end
 function self.tick(options,fov,frame,current_revision)
  if not options.dof or options.dof_mode~=1 then
   local ok,why=self.release();blocked=false;self.message='Windows lens waits for Depth of field';return ok,why
  end
  if world and (frame.world~=world or frame.camera~=camera or frame.generation~=generation)then
   local ok,why=self.release();if not ok then return false,why end;blocked=false
  end
  if blocked then return true end
  world,camera,generation=frame.world,frame.camera,frame.generation
  if revision~=current_revision or self.last_fov~=fov then
   local d=lens.depth(options.focus_distance,options.aperture,fov)
   local values={distance=d.near,region=d.region,start=math.max(.05,d.near*.5),finish=math.max(.05,math.min(200,d.region*.5)),near_scale=1,far_scale=1,near_max=1,far_max=1}
   targets={};for name,value in pairs(values)do for _,close in ipairs({'','_close'})do targets['dof_focal_'..suffix[name]..close]=value end end
   revision,self.last_fov=current_revision,fov
   if env then local ok,why=pcall(function()apply_targets();S.apply(env)end);if not ok then return false,why end end
  end
  if not env and not render_wrapper then
   frames=0;previous_render=A.render_world
   local original_render=previous_render
   local observer
   observer=function(...)
    local w,c,v,environment=...
    if render_wrapper==observer and w==world and c==camera and environment~=nil then
     local ok,why=pcall(capture,environment);detach_render()
     if not ok then blocked=true;self.message='Windows lens unavailable: '..tostring(why);log(self.message)end
    end
    -- Keep the original callable locally: capture may detach the observer.
    return original_render(...)
   end
   render_wrapper=observer;A.render_world=observer
  end
  return true
 end
 function self.observe()
  if not render_wrapper then return end
  frames=frames+1
  if frames>=4 then
   detach_render();blocked=true;self.message='Game render did not expose a camera shading environment';log(self.message)
   -- One bounded metadata inventory; no engine getters/setters are guessed.
   local spaces={};for key,value in pairs(sr)do
    if type(key)=='string'and type(value)=='table'then spaces[#spaces+1]=key end
   end;table.sort(spaces);log('Windows lens namespaces: '..table.concat(spaces,','))
   for _,name in ipairs({'World','Application','Level','WorldParameter','WorldParameters','ShadingEnvironmentBlendComponent'})do
    local api=sr[name];local members={}
    if type(api)=='table'then for key,value in pairs(api)do if type(key)=='string'then members[#members+1]=key..':'..type(value)end end end
    table.sort(members);log('Windows lens API '..name..': '..table.concat(members,','))
   end
  end
 end
 return self
end
return M

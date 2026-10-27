local lens=dofile('freecam/windows_lens.lua')
local depth=dofile('freecam/lens.lua')
local function test(missing)
 local world,camera,environment={},{},{}
 local values={};local originals={};local writes,applies,logs=0,0,0
 local sr={Application={main_world=function()return world end},ShadingEnvironment={}}
 for _,suffix in ipairs({'distance','region','region_start','region_end','near_scale','far_scale','near_max','far_max'})do
  for _,close in ipairs({'','_close'})do local key='dof_focal_'..suffix..close;values[key]=4;originals[key]=4 end
 end
 local original_render=function(...)return select('#',...),nil,'game'end
 sr.Application.render_world=original_render
 sr.ShadingEnvironment.scalar=function(e,k)assert(e==environment);if missing then error('missing property')end;return values[k]end
 sr.ShadingEnvironment.set_scalar=function(e,k,v)assert(e==environment and values[k]~=nil);writes=writes+1;values[k]=v end
 local original_apply=function(...)applies=applies+1;return select('#',...),nil,'applied'end
 sr.ShadingEnvironment.apply=original_apply
 local backend=lens.new(sr,depth,function()logs=logs+1 end)
 local options={dof=true,dof_mode=1,focus_distance=3,aperture=1.4}
 local frame={world=world,camera=camera,generation=1}
 assert(backend.tick(options,1,frame,1))
 local cached_render=sr.Application.render_world
 local a,b,c=sr.Application.render_world(world,camera,{},environment)
 assert(a==4 and b==nil and c=='game','Preserve original callback results')
 assert(sr.Application.render_world==original_render,'Capture detaches after one submitted environment')
 if missing then assert(not backend.ready and writes==0,'Missing schema must not write');assert(backend.release());return end
 assert(backend.ready and writes>0)
 local unchanged=writes;assert(backend.tick(options,1,frame,1));backend.observe();assert(writes==unchanged)
 local cached_apply=sr.ShadingEnvironment.apply
 a,b,c=sr.ShadingEnvironment.apply(environment);assert(a==1 and b==nil and c=='applied');assert(writes==unchanged)
 -- A real game environment blend is an explicit invalidation event.
 values.dof_focal_distance=4;sr.ShadingEnvironment.apply(environment);assert(writes==unchanged+1)
 options.focus_distance=8;assert(backend.tick(options,1,frame,2));assert(values.dof_focal_distance~=4)
 -- A foreign field must survive cleanup.
 values.dof_focal_near_max=7
 assert(backend.release());assert(sr.ShadingEnvironment.apply==original_apply)
 for key,v in pairs(values)do assert(v==(key=='dof_focal_near_max'and 7 or originals[key]),'Restore only owned fields')end
 -- Cached Lua callbacks remain safe after detachment and cleanup.
 a,b,c=cached_render(world,camera);assert(a==2 and b==nil and c=='game')
 a,b,c=cached_apply(environment);assert(a==1 and b==nil and c=='applied')
end
test(false);test(true)
-- A renderer that submits no shading environment retires discovery after 4 frames.
local world,camera={},{}
local original=function(...)return select('#',...)end
local sr={Application={main_world=function()return world end,render_world=original},ShadingEnvironment={scalar=function()error('No handle supplied')end,set_scalar=function()error('No writes permitted')end,apply=function()end}}
local backend=lens.new(sr,depth,function()end)
assert(backend.tick({dof=true,dof_mode=1,focus_distance=3,aperture=2},1,{world=world,camera=camera,generation=1},1))
for i=1,4 do backend.observe()end
assert(sr.Application.render_world==original and not backend.ready)
for i=1,50 do assert(backend.tick({dof=true,dof_mode=1},1,{world=world,camera=camera,generation=1},1));backend.observe()end
assert(sr.Application.render_world==original,'Unavailable path stays idle until explicit reactivation')
assert(backend.release())
print('Windows engine lens: observed handles, complete schema, callback ABI/lifetime, lens mapping, blend events, idle, bounded discovery and owned restoration passed; visual validation pending')

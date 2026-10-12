-- Candidate integration uses the actual compositor and owned postfx restore.
-- Native GPU draw behavior remains a separate visual validation step.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local runtime_factory=dofile(root..'photo_runtime.lua')
local postfx_factory=dofile(root..'postfx.lua');local lens_math=dofile(root..'lens.lua')
local defaults=dofile(root..'photo_options.lua').defaults
local o={};for key,value in pairs(defaults)do o[key]=value end;o.dof=true;o.bloom=true;o.dof_mode=2
local native={dof=1,bloom=0,focus_distance=10,aperture=8}
local parameters={dof=true,bloom=true,focus_distance=true,aperture=true}
DBF_PHOTO_RENDER_PROFILE={world=10,parameters=parameters,
 read=function(key)return native[key]end,write=function(key,value)native[key]=value end}
local lens_applies,lens_releases,gui_creates,gui_releases=0,0,0,0
local sr={Application={main_world=function()return 10 end,worlds=function()return {10,20}end},
 World={create_screen_gui=function(owner)assert(owner==20);gui_creates=gui_creates+1;return {}end,destroy_gui=function()gui_releases=gui_releases+1 end},
 Gui={resolution=function()return 1920,1080 end}}
local lens={depth=lens_math.depth,new=function()return {apply=function()lens_applies=lens_applies+1;return .9 end,release=function()lens_releases=lens_releases+1;return true end}end}
local composition={shaders={''},layout=function()return {}end}
local applies,checks,releases=0,0,0;local can_draw,available,throws=false,true,false;local cleanup=true
local overlay={apply=function(options,fov)
 applies=applies+1;assert(options==o and fov==.9)
 if throws then error('candidate draw failure')end
 return can_draw,'candidate draw status'
end,ready=function()checks=checks+1;return available,'candidate available'end,
 release=function()releases=releases+1;return cleanup,'candidate release failure'end}
local function apply(runtime,scene)return runtime.apply(1,2,scene or 10,{0,1,0},{1,0,0},o,0)end
local function numeric(runtime,ready)
 assert(runtime.custom_dof_ready==ready)
 assert((runtime.parameters.focus_distance==true)==ready and (runtime.parameters.aperture==true)==ready)
end
local runtime=runtime_factory.new(sr,lens,composition,postfx_factory,function()end,nil,nil,{new=function()return overlay end})
assert(runtime.custom_dof_candidate==true)
-- A failed overlay must keep the native pass active and numeric gates closed.
assert(apply(runtime));numeric(runtime,false);assert(native.dof==1 and applies==1)
can_draw=true;assert(apply(runtime));numeric(runtime,true)
assert(native.dof==0 and native.bloom==1 and o.dof==true,'Successful candidate must suppress only native DoF, without mutating saved user options')
can_draw=false;assert(apply(runtime));numeric(runtime,false);assert(native.dof==1,'Lost custom pass must restore native fallback in the same frame')
throws=true;assert(apply(runtime));numeric(runtime,false);assert(native.dof==1 and releases>0,'Thrown draw must preserve camera and release partial candidate resources')
throws=false;can_draw=true;assert(apply(runtime));assert(native.dof==0)
-- DoF-off controls use resource readiness without creating a DoF bitmap.
o.dof=false;local draws=applies;assert(apply(runtime));numeric(runtime,true)
assert(applies==draws and checks==1 and native.dof==0)
available=false;assert(apply(runtime));numeric(runtime,false);assert(applies==draws)
-- Switching scenes follows ordinary restoration before acquiring new state.
o.dof=true;available=true;local before=releases;DBF_PHOTO_RENDER_PROFILE.world=30
assert(apply(runtime,30));assert(releases>before and lens_releases>0 and native.dof==0)
assert(runtime.release());numeric(runtime,false)
assert(native.dof==1 and native.bloom==0 and native.focus_distance==10 and native.aperture==8,'Release must restore all original native values')
assert(gui_creates==gui_releases,'World changes or release leaked composition GUIs')
-- Method changes retire only the shader pass; native DoF is never stacked under it.
DBF_PHOTO_RENDER_PROFILE.world=10;o.dof_mode=1
local draws,lens_closed,composition_closed=applies,lens_releases,gui_releases
assert(apply(runtime));numeric(runtime,false)
assert(applies==draws and native.dof==1,'Native mode must skip the custom draw and enable native DoF')
assert(lens_releases==lens_closed and gui_releases==composition_closed,'Method selection must preserve camera/composition ownership')
o.dof_mode=2;assert(apply(runtime));numeric(runtime,true);assert(native.dof==0)
o.dof_mode=1;draws=applies;assert(apply(runtime));assert(applies==draws and native.dof==1 and not runtime.custom_dof_ready)
assert(runtime.release());o.dof_mode=2
-- The release keeps failed cleanup visible and retries rather than discarding it.
cleanup=false;local done,why=runtime.release();assert(done==false and why=='candidate release failure')
cleanup=true;assert(runtime.release())
-- Constructor failure is contained, so the standard camera remains usable.
local bad=runtime_factory.new(sr,lens,composition,postfx_factory,function()end,nil,nil,{new=function()error('factory failure')end})
DBF_PHOTO_RENDER_PROFILE.world=10;assert(not bad.custom_dof_candidate);assert(apply(bad));numeric(bad,false);assert(bad.release())
assert(lens_applies>=8,'Candidate failures prevented ordinary camera updates')
-- Asset lookup cannot lift the numeric gates without renderer registration.
local registered=false;local validation_error=false;local asset_queries=0
sr.Application.can_get=function()asset_queries=asset_queries+1;return true end
local guard=dofile(root..'shader_template_guard.lua').new(sr,function()
 if validation_error then error('renderer template validation failed')end
 return registered
end)
local guarded_overlay=dofile(root..'dof_overlay.lua').new(sr,{available=function()return true end,get=function()error('Unregistered shader must not query a draw resource')end},true,guard)
local guarded=runtime_factory.new(sr,lens,composition,postfx_factory,function()end,nil,nil,{new=function()return guarded_overlay end})
o.dof=true;assert(apply(guarded));numeric(guarded,false)
assert(native.dof==1 and asset_queries==0,'Missing renderer registration must stop before asset queries or native suppression')
registered=true;o.dof=false;assert(apply(guarded));numeric(guarded,true)
assert(asset_queries==2,'Registered off-state should check shader and material without drawing')
validation_error=true;assert(apply(guarded));numeric(guarded,false)
assert(guarded.release(),'Guard validation failure must leave normal restoration usable')
DBF_PHOTO_RENDER_PROFILE=nil
print('DoF runtime candidate: successful-pass native suppression, same-frame fallback, off-state readiness, constructor/draw failures, scene restoration, cleanup retry and renderer registration guard passed')

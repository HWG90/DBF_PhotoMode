-- Exercise the production compositor/postfx with a verified native DoF-only
-- profile. These tests do not treat a successful Lua draw as GPU visual proof.
local root=assert(DBF_PHOTO_TEST_ROOT)
local factory=dofile(root..'photo_runtime.lua')
local postfx=dofile(root..'postfx.lua')
local lens_math=dofile(root..'lens.lua')
local scene_math=dofile(root..'scene_overlay.lua')
local defaults=dofile(root..'photo_options.lua').defaults
local o={};for key,value in pairs(defaults)do o[key]=value end
o.dof=true;o.dof_mode=1;o.bloom=true;o.scene_shader=1;o.scene_strength=100
o.fog_distance=25;o.fog_density=50;o.scene_depth_range=100
local native={dof=0,bloom=0};local writes={};local logs={}
local profile={world=10,parameters={dof=true,bloom=true},
 read=function(key)return native[key]end,
 write=function(key,value)writes[#writes+1]={key,value};native[key]=value end}
DBF_PHOTO_RENDER_PROFILE=profile
local gui_creates,gui_releases,lens_applies,lens_releases=0,0,0,0
local sr={Application={main_world=function()return 10 end,worlds=function()return {10,20}end},
 World={create_screen_gui=function(owner)assert(owner==20);gui_creates=gui_creates+1;return {}end,destroy_gui=function()gui_releases=gui_releases+1 end},
 Gui={resolution=function()return 1920,1080 end}}
local lens={depth=lens_math.depth,new=function()return {
 apply=function()lens_applies=lens_applies+1;return .9 end,
 release=function()lens_releases=lens_releases+1;return true end}end}
local composition={shaders={''},layout=function()return {}end}
local dof_draws,dof_releases=0,0
local custom_dof={ready=function()return true end,
 apply=function(options,fov)assert(options==o and fov==.9);dof_draws=dof_draws+1;return true end,
 release=function()dof_releases=dof_releases+1;return true end}
local checks,applies,draws,releases=0,0,0,0
local available,throws,ready_throws,cleanup=true,false,false,true
local carrier=false
local overlay={
 active=function(options)return scene_math.uniforms(options).active end,
 ready=function()checks=checks+1;if ready_throws then error('scene readiness failure')end;return available,'scene availability'end,
 apply=function(options)
  assert(options==o);applies=applies+1
  carrier=scene_math.uniforms(options).active
  if carrier then draws=draws+1 end
  if throws then error('scene draw failure')end
  return true,'Scene preview active'
 end,
 release=function()releases=releases+1;if not cleanup then return false,'scene cleanup failure'end;carrier=false;return true end}
local scene_factory={new=function(runtime_sr)assert(runtime_sr==sr);return overlay end}
local dof_factory={new=function(runtime_sr)assert(runtime_sr==sr);return custom_dof end}
local function make(candidate)
 return factory.new(sr,lens,composition,postfx,function(message)logs[#logs+1]=message end,nil,nil,dof_factory,candidate or scene_factory)
end
local function apply(runtime,world)
 return runtime.apply(1,2,world or 10,{0,1,0},{1,0,0},o,0)
end
local function parameters(runtime,expected)
 for _,key in ipairs({'exposure','contrast','saturation','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do
  assert((runtime.parameters[key]==true)==expected,key..' availability did not follow scene readiness/mode')
 end
end
local runtime=make()
assert(apply(runtime));parameters(runtime,true)
assert(runtime.fov==.9,'Lens metadata must expose the actual applied vertical FOV in radians')
assert(native.dof==1 and native.bloom==1 and not carrier and draws==0,'Neutral-ready scene controls must preserve native DoF without submitting scene pixels')
-- A real effect is allowed alongside the native pass without stacking custom DoF.
o.scene_shader=10;local camera_closed=lens_releases
assert(apply(runtime));parameters(runtime,true)
assert(carrier and draws==1 and native.dof==1 and dof_draws==0 and lens_releases==camera_closed,'Scene fog must retain native DoF and camera ownership')
-- Shader DoF and scene grading are deliberately gated until their transforms
-- can be shared. Saved options survive this gate for a later method switch.
o.dof_mode=2;local scene_draws=draws;local scene_releases=releases
assert(apply(runtime));parameters(runtime,false)
assert(not carrier and draws==scene_draws and releases>scene_releases and native.dof==0 and dof_draws==1,'Shader DoF must release the scene carrier before suppressing native DoF')
assert(o.scene_shader==10 and o.dof==true,'Method gate must not rewrite saved effect/toggle options')
assert(runtime.scene_status=='Shader DoF Enabled. Scene Effects disabled' and runtime.color_status==runtime.scene_status,'Disabled scene and color pages must explain the Shader DoF gate')
assert(lens_releases==camera_closed,'Selecting Shader DoF must not release the camera')
-- Turning DoF off admits scene effects even while the shader method is selected.
o.dof=false;assert(apply(runtime));parameters(runtime,true)
assert(runtime.scene_status~='Shader DoF Enabled. Scene Effects disabled','Notice must clear when DoF is off')
assert(carrier and draws==scene_draws+1 and native.dof==0 and dof_draws==1,'DoF-off state must allow scene effects without a custom blur draw')
-- Returning to Native admits tonal grading with a neutral artistic effect.
o.dof=true;o.dof_mode=1;o.scene_shader=1;o.exposure=.5
assert(apply(runtime));parameters(runtime,true)
assert(carrier and native.dof==1 and dof_draws==1,'Native tonal grading must retain the native pass')
-- A lost shader/depth resource closes scene controls, removes only its own
-- carrier, and continues ordinary native camera/postfx updates.
available=false;scene_draws=draws;camera_closed=lens_releases
assert(apply(runtime));parameters(runtime,false)
assert(not carrier and draws==scene_draws and native.dof==1 and lens_releases==camera_closed)
available=true;ready_throws=true;assert(apply(runtime));parameters(runtime,false)
assert(not carrier and native.dof==1,'Thrown readiness must preserve native DoF')
ready_throws=false;throws=true;scene_releases=releases
assert(apply(runtime));assert(not carrier and releases>scene_releases and native.dof==1,'Partial scene draw failure must release its carrier without changing native DoF')
assert(lens_releases==camera_closed,'Scene failure must leave the camera active')
throws=false;assert(apply(runtime));parameters(runtime,true);assert(carrier and native.dof==1)
-- A scene/world transition follows the production release path before reuse.
scene_releases=releases;camera_closed=lens_releases;profile.world=30
assert(apply(runtime,30));parameters(runtime,true)
assert(releases>scene_releases and lens_releases>camera_closed and carrier and native.dof==1)
assert(runtime.release());parameters(runtime,false)
assert(not carrier and native.dof==0 and native.bloom==0,'Photo exit must restore original native settings and remove the scene carrier')
assert(gui_creates==gui_releases,'Scene transition/exit leaked a composition GUI')
-- Failed cleanup is reported and can be retried without discarding ownership.
cleanup=false;local done,why=runtime.release();assert(done==false and why=='scene cleanup failure')
cleanup=true;assert(runtime.release())
-- An invalid factory remains contained inside the production compositor.
profile.world=10;local broken=make({new=function()error('scene factory failure')end})
assert(apply(broken));parameters(broken,false)
assert(native.dof==1 and broken.release()and native.dof==0)
assert(#logs>0 and lens_applies>=10 and checks>0 and applies>0 and dof_releases>0)
DBF_PHOTO_RENDER_PROFILE=nil
print('Scene runtime: neutral readiness, Native coexistence, Shader/DoF-off gates, saved options, resource/readiness/draw/factory failures, world transition, release retry and native restoration passed; no game process accessed')

-- The combined candidate admits scene controls with shader blur and suppresses
-- native DoF only after the compositor explicitly confirms a shader DoF draw.
profile.world=10;DBF_PHOTO_RENDER_PROFILE=profile
local composite_available,composite_draw=true,true
local combined={combined_scene_dof_candidate=true,
 ready=function()return composite_available,'combined unavailable'end,
 release=function()return true end}
-- Declare the captured object separately so the closure sees its actual table.
combined.apply=function(options)
 if not composite_draw then return false,'combined draw failed',false end
 combined.scene_active=options.scene_shader>1
 return true,'combined submitted',options.dof and options.dof_mode==2
end
local joined=factory.new(sr,lens,composition,postfx,function()end,nil,nil,{new=function()return combined end})
o.scene_shader=3;o.dof=true;o.dof_mode=2
assert(apply(joined));parameters(joined,true)
assert(joined.custom_dof_ready and native.dof==0 and joined.scene_status=='Combined scene and DoF preview')
assert(joined.color_status~='Shader DoF Enabled. Scene Effects disabled','Combined draw must admit grading with bokeh')
o.dof_mode=1;assert(apply(joined));parameters(joined,true)
assert(not joined.custom_dof_ready and native.dof==1,'Scene-only draw must retain native DoF')
o.dof_mode=2;composite_draw=false;assert(apply(joined));parameters(joined,false)
assert(not joined.custom_dof_ready and native.dof==1,'Failed combined draw must preserve native fallback')
composite_draw=true;o.dof=false;assert(apply(joined));parameters(joined,true);assert(native.dof==0)
composite_available=false;o.dof=true;assert(apply(joined));parameters(joined,false);assert(native.dof==1)
assert(joined.release());DBF_PHOTO_RENDER_PROFILE=nil
print('Combined runtime: scene plus Shader DoF admission, successful-draw suppression, Native scene coexistence, DoF-off grading and same-frame failure fallback passed')

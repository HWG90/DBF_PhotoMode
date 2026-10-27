DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps,sr)
 deps.engine_shader_lens=true
 deps.load_scene=function()
  return{ready=function()return true end,rearm=function()end,release=function()f.scene_released=true;return true end,
   focus=function()end,render=function(o)
    if o.dof_mode~=2 then return true,'Native camera selected',false end
    f.rendered_focus=o.focus_distance;f.rendered_aperture=o.aperture
    return true,'fixture shader',o.dof==true
   end}
 end
 f.flags={dof_enabled=true,bloom_enabled=true}
 sr.Application.render_setting=function(key)return f.flags[key]end
 sr.Application.set_render_setting=function(key,value)f.flags[key]=value=='true'end
end)
f.open();assert(f.runtime.handle.set('dof',true));for i=1,4 do f.step(.3,1)end
assert(f.runtime.active,'Shader lens must keep Photo Mode open')
assert(f.runtime.handle.get('dof_mode')==1,'Scene initialization must preserve Native camera')
assert(f.controls.focus_distance.disabled and f.controls.aperture.disabled,'Native sliders need a ready native controller')
assert(f.flags.dof_enabled==true,'Native DoF must remain enabled when Native camera is selected')
assert(f.runtime.handle.set('dof_mode',2));f.step(.016,1)
assert(not f.controls.focus_distance.disabled and not f.controls.aperture.disabled)
assert(f.runtime.handle.set('focus_distance',3));assert(f.runtime.handle.set('aperture',1.2));f.step(.016,1)
for i=1,4 do f.step(.3,1)end
assert(f.rendered_focus==3 and f.rendered_aperture==1.2,'Sliders must drive the qualified shader backend')
assert(f.flags.dof_enabled==false,'Native DoF is suppressed only after shader draw acknowledgement')
f.runtime.close(true)
for i=1,8 do if f.runtime.state=='closed'then break end;f.step(.2)end
assert(f.runtime.state=='closed'and f.scene_released and f.flags.dof_enabled==true,'Close restores the native DoF baseline')
f.finish()
print('Windows lens routing: preserves Native camera, gates native numeric sliders, explicit Shader selection, suppression only after shader draw and cleanup passed')

DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(true,function(f,deps,sr)
 local flags={dof_enabled=true,bloom_enabled=true}
 sr.Application.render_setting=function(k)return flags[k]end
 sr.Application.set_render_setting=function(k,v)flags[k]=v=='true'end
 local factory=deps.camera.new;deps.camera.new=function(...)
  local c=factory(...);c.identity=function()return{world=f.world,camera={},generation=f.generation}end;return c
 end
 f.numeric={ready=false,message='warming'};f.numeric_loads=0;f.numeric_ticks=0;f.numeric_observations=0
 function f.numeric.tick(o)f.numeric_ticks=f.numeric_ticks+1;f.numeric.ready=o.dof;return true end
 function f.numeric.observe()f.numeric_observations=f.numeric_observations+1 end
 function f.numeric.release()
  assert(not f.camera_open and not f.lease,'Numeric cleanup must follow camera/input release')
  if f.numeric_refuse then return false,'fixture lens restoration pending'end;f.numeric.ready=false;return true
 end
 deps.load_native_lens=function()f.numeric_loads=f.numeric_loads+1;return f.numeric end
end)
for i=1,100 do f.step(.016)end;assert(f.numeric_loads==0 and f.numeric_ticks==0)
f.open();assert(f.numeric_loads==0 and f.controls.focus_distance.disabled)
f.menu.handle.set('dof',true);f.step(.016,1)
assert(f.numeric_loads==1 and not f.controls.focus_distance.disabled and not f.controls.aperture.disabled)
assert(f.numeric_observations>0,'Observe only after real game render callback')
f.numeric_refuse=true;assert(not f.runtime.close(true));assert(not f.lease and not f.camera_open)
f.numeric_refuse=false;for i=1,8 do f.step(.25);if f.runtime.state=='closed'then break end end
assert(f.runtime.state=='closed',f.runtime.reason);f.finish()
print('Numeric lens runtime: no closed work, lazy explicit DoF activation, current ready controls, post-render observations and input-first restoration retry passed')

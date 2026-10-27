DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps,sr)
 f.native_calls=0
 local native=f.native_render
 f.native_render=function(...)
  f.native_calls=f.native_calls+1;f.visible_pose=f.native_calls
  return native(...)
 end
 render=f.native_render
 f.held=false;f.acquisitions=0;f.hold_renders=0;f.releases=0;f.prepares=0
 deps.freeze_root_hold={prepare=function()
  assert(f.rate>0,'Capture must run before the zero-time setter')
  f.prepares=f.prepares+1;return true
 end,tick=function(enabled,point)
  if enabled then assert(type(point)=='table'and f.rate==0);f.acquisitions=f.acquisitions+1 end
  f.held=enabled;return true
 end,render=function(enabled)
  if enabled then
   assert(f.rate==0 and f.native_calls>0,'Hold runs after native render')
   f.visible_pose=0
   -- The real holder safely skips a render until its next update acquires a
   -- root inventory. Ramp completion may occur after that update's hold tick.
   if f.held then f.hold_renders=f.hold_renders+1 end
  end;return true
 end,release=function()f.held=false;f.releases=f.releases+1;return true end}
 local policy=sr.Application.set_time_step_policy
 sr.Application.set_time_step_policy=function(key,value)
  if value~=0 then assert(not f.held,'Root hold must release before nonzero time')end
  return policy(key,value)
 end
end)
for i=1,100 do f.step(.016,1)end
assert(f.acquisitions==0 and f.hold_renders==0,'No closed root work')
f.open();assert(f.held and f.hold_renders==1 and f.rate==0)
assert(f.prepares==1,'Ordinary Freeze captures its root baseline before zero')
assert(f.visible_pose==0,'Native render must not overwrite the hold')
for i=1,10 do f.step(.016,1);assert(f.visible_pose==0,'Each native overwrite is corrected after rendering')end
local before_error=f.hold_renders;f.native_error=true;assert(not pcall(render));f.native_error=false
assert(f.hold_renders==before_error,'Failed game render never runs the post-render hold')
assert(f.menu.actions.smooth_freeze==nil and f.runtime.toggle_smooth_freeze==nil,'Removed experiment cannot be enabled')
assert(f.runtime.handle.set('freeze_player',false));assert(not f.held and f.rate==1)
local renders=f.hold_renders;for i=1,10 do f.step(.016,1)end
assert(f.hold_renders==renders,'No hold when time runs')
assert(f.runtime.handle.set('freeze_player',true));f.step(.016,1);assert(f.held and f.hold_renders>renders)
assert(f.runtime.close(true));assert(not f.held and f.rate==1 and not f.lease)
renders=f.hold_renders;for i=1,10 do f.step(.016,1)end;assert(f.hold_renders==renders)
f.finish();assert(not f.held)
print('Root hold runtime: manual zero-time ownership, post-native ordering/error propagation, closed idle and release before resume/close/dispose passed')

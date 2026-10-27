-- Runtime ownership/order coverage for the continuous transfer-lease adapter.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps,sr)
 f.mode='position_and_rotation';f.skeleton_active=false;f.prepares=0;f.hold_renders=0;f.mode_writes=0;f.releases=0;f.native_calls=0
 local native=f.native_render
 f.native_render=function(...)f.native_calls=f.native_calls+1;f.visible='native';return native(...)end
 render=f.native_render
 local function release()
  if not f.skeleton_active then return true end
  if f.refuse then return false,'Transfer restoration pending'end
  if f.mode=='ignore'then f.mode='position_and_rotation';f.mode_writes=f.mode_writes+1 end
  f.skeleton_active=false;f.releases=f.releases+1;return true
 end
 deps.freeze_pose_hold={active=function()return f.skeleton_active end,
 prepare=function(subject,now)
  assert(f.rate>0 and f.mode=='position_and_rotation','Capture precedes zero-time and transfer acquisition')
  f.prepares=f.prepares+1;f.skeleton_active=true;return true
 end,
 tick=function(enabled)if not enabled then return release()end;return true end,
 render=function(enabled)
  assert(enabled and f.rate==0 and f.native_calls>0,'Only owned zero time after native render can acquire transfer')
  if f.mode~='ignore'then f.mode='ignore';f.mode_writes=f.mode_writes+1 end
  f.hold_renders=f.hold_renders+1;f.visible='held';return true
 end,release=release}
 local time=sr.Application.set_time_step_policy
 sr.Application.set_time_step_policy=function(key,value)
  if value~=0 then assert(not f.skeleton_active and f.mode~='ignore','Restore transfer before nonzero time')end
  return time(key,value)
 end
end)
for i=1,100 do f.step(.016,1)end
assert(f.prepares==0 and f.mode_writes==0 and f.hold_renders==0,'Closed lifecycle stays idle')
f.open();assert(f.prepares==1 and f.mode=='ignore'and f.mode_writes==1 and f.visible=='held')
for i=1,50 do f.step(.016,1);assert(f.visible=='held')end
assert(f.mode_writes==1,'Steady hold never reacquires transfer')
f.foreground=false;f.step(.016,1);assert(f.mode=='ignore','Focus loss retains a valid continuous Freeze lease')
f.foreground=true;f.step(.016,1)
assert(f.runtime.handle.set('freeze_player',false));assert(f.rate==1 and f.mode=='position_and_rotation'and not f.skeleton_active)
local renders=f.hold_renders;for i=1,20 do f.step(.016,1)end;assert(f.hold_renders==renders,'Running time has no skeleton replay')
assert(f.runtime.handle.set('freeze_player',true));f.step(.016,1);assert(f.mode=='ignore'and f.rate==0)
f.refuse=true;assert(not f.runtime.close(true));assert(f.rate==0 and f.mode=='ignore','Failed restoration holds zero time')
f.refuse=false;assert(f.runtime.close(true));assert(f.rate==1 and f.mode=='position_and_rotation'and not f.lease)
f.finish();assert(not f.skeleton_active)
print('Transfer runtime: pre-zero capture, post-native acquisition, focus retention, one mode lease, idle running/closed and restore-before-resume with failure recovery passed')

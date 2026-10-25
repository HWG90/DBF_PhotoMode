DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(true,function(f,deps)
 f.hud={sets={},ticks=0,releases=0,hidden=false}
 deps.hud={new=function()return{
  set=function(hidden)f.hud.sets[#f.hud.sets+1]=hidden;f.hud.hidden=hidden;if f.hud_refuse then return false,'fixture HUD state unknown'end;return true end,
  tick=function()f.hud.ticks=f.hud.ticks+1;return true end,
  release=function()f.hud.releases=f.hud.releases+1;if f.hud_release_refuse then return false,'fixture HUD restore pending'end;f.hud.hidden=false;return true end,
  status=function()return{hidden=f.hud.hidden,pending_restore=f.hud_release_refuse==true}end}
 end}
end)
f.open();assert(not f.controls.hide_hud.disabled and f.hud.hidden)
assert(f.runtime.handle.set('hide_hud',false));f.step(.016,1);assert(not f.hud.hidden)
assert(f.menu.actions.hud());f.step(.016,1);assert(f.hud.hidden and f.runtime.handle.get('hide_hud'))
assert(f.runtime.handle.set('hide_hud',false));f.step(.016,1)
f.hud_refuse=true;f.start()
for i=1,20 do f.step(.016,1)end;f.step(0)
assert(f.requests==0 and f.capture().active(),'Unknown native HUD state cannot certify a clean screenshot frame')
f.hud_refuse=false
for i=1,12 do f.step(.016,1)end;f.step(0);assert(f.requests==1)
f.status_state='succeeded';f.step(.101,1);assert(not f.hud.hidden,'Capture completion must restore the saved HUD preference')
f.hud_release_refuse=true
assert(not f.runtime.close(true)and f.runtime.state=='closing'and not f.lease and not f.camera_open,'HUD cleanup must not retain camera/input')
assert(not f.runtime.open(),'HUD cleanup must fence re-entry')
f.hud_release_refuse=false;assert(f.runtime.close(true)and f.runtime.state=='closed')
f.finish()
print('WJ HUD runtime: registered preference/shortcut, capture hide and clean-frame fence, preference restoration and input-first cleanup retry passed')

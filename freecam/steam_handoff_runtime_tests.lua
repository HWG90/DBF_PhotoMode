-- Other menus over Photo Mode: MCM/LLL keys yield input while camera, freeze
-- and Photo Mode stay; focus loss never unfreezes or closes. No game access.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local mcm_open,opens=false,0
DBFMCM={is_open=function()return mcm_open end,open=function()opens=opens+1;mcm_open=true;return true end,
 menu_binding_status=function()return{global_key=46}end}
local f=fixture()
f.open();assert(f.runtime.active and f.lease and f.rate==0,'Photo Mode opens frozen with input')
f.pressed.delete=true;f.step(.016,1)
assert(f.runtime.active and not f.lease and f.rate==0,'The MCM key yields input and keeps Photo Mode and Freeze Action')
assert(f.last_hidden==true,'The Photo panel hides while another menu has input')
f.step(.016,1);assert(opens==0,'Wait for the key release before opening explicitly')
f.pressed.delete=false;for _=1,3 do f.step(.016,1)end
assert(opens==1 and mcm_open,'MCM opens once after its key is released')
for _=1,20 do f.step(.05,1)end
assert(not f.lease and f.runtime.active and f.rate==0 and opens==1,'Photo Mode waits while MCM is open')
mcm_open=false;for _=1,6 do f.step(.05,1)end
assert(f.lease and f.runtime.active and f.rate==0,'Input returns after MCM closes; Freeze Action is intact')
-- Focus loss yields input only: no close, no resume.
f.foreground=false;for _=1,10 do f.step(.016,1)end
assert(f.runtime.active and f.rate==0 and not f.lease,'Focus loss keeps Photo Mode open and frozen')
f.foreground=true;f.step(.016,1);f.step(.016,1)
assert(f.runtime.active and f.lease and f.rate==0,'Refocus retakes input with Freeze Action intact')
-- Unexplained lease loss yields, but ESC still exits Photo Mode.
f.lease=nil;f.step(.016,1);assert(f.runtime.active and not f.lease)
f.pressed.esc=true;f.step(.016,1);f.pressed.esc=false
for _=1,10 do if f.runtime.state=='closed'then break end;f.step(.1)end
assert(not f.runtime.active and f.rate==1,'ESC exits a generic handoff and restores time')
-- Repeated input loss ends in the ordinary full close, never a held scene.
assert(f.runtime.open());f.step(0,1)
for _=1,8 do if not f.runtime.active then break end;f.lease=nil;f.step(.3,1);f.step(.3,1)end
for _=1,10 do if f.runtime.state=='closed'then break end;f.step(.1)end
assert(not f.runtime.active and f.rate==1,'Repeated input loss closes Photo Mode instead of holding it')
DBFMCM=nil;f.finish();assert(f.rate==1,'Exit restores time')
print('Steam menu handoff: MCM key yield, explicit open after release, wait, input return, focus loss keeps freeze and Photo Mode passed')

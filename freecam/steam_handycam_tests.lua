local H=dofile('freecam/steam_handycam.lua')
local h=H.new();local o={camera_smoothing=true,smoothing_strength=50,handycam_intensity=0}
local p,f,r,roll=h.step({1,2,3},{1,0,0},0,o)
assert(p[1]==1 and p[3]==3 and f[1]==1 and roll==0)
p=h.step({2,2,3},{1,0,0},.05,o);assert(p[1]>1 and p[1]<2)
h.reset();p=h.step({9,8,7},{0,1,0},.1,o);assert(p[1]==9 and p[3]==7)
-- Echoes of our own output must not accumulate sway into gameplay aim.
o.handycam_intensity=100;h.reset();local aim={1,0,0}
for i=1,600 do p,aim=h.step({0,0,2},aim,i/60,o);assert(math.abs(aim[2])<.02)end
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local function setup(f,deps)
 f.head_identity='player';f.head={0,0,2};f.head_reads=0;f.hidden=false
 deps.handycam=H
 deps.subject_backend={new=function()return{head_frame=function()
  f.head_reads=f.head_reads+1;if f.head_error then error('Head retired')end
  return{identity=f.head_identity,head=f.head}
 end}end}
 deps.subject_visibility={new=function()return{
 ready=function()return true end,refresh=function()return true,'ready',{}end,
 queue=function(o)f.queued=o end,flush=function()if f.queued then f.hidden=f.queued.hide_player;f.queued=nil end;return true end,
 release=function()f.hidden=false;return true end}end}
 local old=deps.camera.new;deps.camera.new=function(...)
  local c=old(...);local write=c.write_view
  c.write_view=function(p,forward,up,...)f.position={unpack(p)};f.up={unpack(up)};return write(p,forward,up,...)end;return c
 end
end
local f=fixture(false,setup)
for i=1,100 do f.step(.016)end;assert(f.head_reads==0,'Closed runtime must not read head')
f.open();assert(not f.controls.handycam_intensity.disabled)
assert(f.menu.handle.set('roll',45));assert(f.menu.handle.set('handycam_intensity',0));assert(f.menu.handle.set('action_camera_mode',2));assert(f.runtime.begin_shot())
assert(f.runtime.mode=='shot'and not f.lease and f.hidden,'Action releases keyboard and hides avatar')
f.step(.016,1);assert(f.position[3]==2);assert(math.abs(f.up[3]-1)<1e-8,'Handycam must ignore placement roll')
f.head={0,0,3};f.step(.016,1);assert(f.position[3]==3)
assert(f.runtime.reposition_shot());f.step(.016,1);assert(not f.hidden and f.lease,'Placement restores avatar and input lease');assert(math.abs(f.up[3]-math.sqrt(.5))<1e-8,'Returning must restore placement roll')
assert(f.runtime.begin_shot());f.head_identity='replacement';f.step(.016,1)
assert(not f.runtime.active and not f.hidden and not f.lease,'Player replacement closes and cleans up')
f.finish()
local g=fixture(false,setup);g.open();g.menu.handle.set('action_camera_mode',2);g.head_error=true
assert(not g.runtime.begin_shot()and g.runtime.mode=='menu'and g.lease,'Missing head preserves placement')
g.finish()
print('Handycam: branch tracking, output-echo rejection, no idle head reads, gameplay lease handoff, owned visibility restore and replacement/missing-head cleanup passed')

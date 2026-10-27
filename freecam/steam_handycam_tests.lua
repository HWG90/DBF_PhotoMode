local H=dofile('freecam/steam_handycam.lua')
local h=H.new();local o={camera_smoothing=true,smoothing_strength=50,handycam_intensity=0,handycam_lag_ms=0,handycam_forward_cm=0,handycam_up_cm=0}
local p,f,r,roll=h.step({1,2,3},{1,0,0},0,o)
assert(p[1]==1 and p[3]==3 and f[1]==1 and roll==0)
p=h.step({2,2,3},{1,0,0},.05,o);assert(p[1]==2,'Head mount must not trail a moving subject')
p,f=h.step({20,5,9},{0,1,0},.06,o);assert(p[1]==20 and p[2]==5 and p[3]==9 and f[1]>0,'Movement stays exact while aim smoothing remains active')
h.reset();p=h.step({9,8,7},{0,1,0},.1,o);assert(p[1]==9 and p[3]==7)
do
 local lagged=H.new();local opts={handycam_lag_ms=150,handycam_intensity=0,camera_smoothing=false,handycam_forward_cm=0,handycam_up_cm=0}
 lagged.step({0,0,0},{1,0,0},0,opts)
 local pos=lagged.step({3,0,0},{1,0,0},.05,opts)
 assert(math.abs(pos[1]-3*(1-math.exp(-.05/.15)))<1e-9,'Movement lag has its own time constant and does not require aim smoothing')
 opts.handycam_lag_ms=0;pos=lagged.step({8,0,0},{1,0,0},.06,opts);assert(pos[1]==8,'Zero lag snaps to the current head')
end
-- Echoes of our own output must not accumulate sway into gameplay aim.
o.handycam_intensity=100;h.reset();local aim={1,0,0}
for i=1,600 do p,aim=h.step({0,0,2},aim,i/60,o);assert(math.abs(aim[2])<.02)end
for i=1,60 do local head={i*.3,i*.2,2+i*.1};p=h.step(head,{1,0,0},10+i/60,o)
 for axis=1,3 do assert(p[axis]==head[axis],'Sway cannot offset the camera mount')end
end
-- Default eye-level mount, view-local axes and no accumulated offset.
do
 local c=H.new();local opts={handycam_lag_ms=0,handycam_intensity=0,camera_smoothing=false}
 local p=c.step({0,0,2},{1,0,0},0,opts)
 assert(math.abs(p[1]-.14)<1e-9 and math.abs(p[3]-2.07)<1e-9)
 for i=1,120 do p=c.step({0,0,2},{1,0,0},i/60,opts)end
 assert(math.abs(p[1]-.14)<1e-9 and math.abs(p[3]-2.07)<1e-9,'Offsets must not accumulate')
 p=c.step({0,0,2},{0,1,0},3,opts);assert(math.abs(p[1])<1e-9 and math.abs(p[2]-.14)<1e-9)
 p=c.step({0,0,2},{0,0,1},3.1,opts);assert(math.abs(p[1]+.07)<1e-9 and math.abs(p[3]-2.14)<1e-9,'Up and forward follow clean camera pitch')
 opts.handycam_forward_cm=-10;opts.handycam_up_cm=-5
 p=c.step({0,0,2},{1,0,0},3.2,opts);assert(math.abs(p[1]+.1)<1e-9 and math.abs(p[3]-1.95)<1e-9)
 opts.handycam_forward_cm=0;opts.handycam_up_cm=0;p=c.step({0,0,2},{1,0,0},3.3,opts);assert(p[1]==0 and p[3]==2,'Zero offsets restore exact bone position')
end
-- Side translation uses the clean view's right axis; orientation never feeds back.
do
 local c=H.new();local opts={handycam_intensity=0,handycam_lag_ms=0,handycam_forward_cm=0,handycam_up_cm=0,handycam_right_cm=10,handycam_yaw_deg=90,handycam_pitch_deg=30}
 local p,f=c.step({0,0,2},{1,0,0},0,opts)
 assert(math.abs(p[2]+.1)<1e-9 and math.abs(p[1])<1e-9)
 assert(math.abs(f[1])<1e-9 and math.abs(f[2]-math.sqrt(.75))<1e-9 and math.abs(f[3]-.5)<1e-9)
 for i=1,120 do p,f=c.step({0,0,2},f,i/60,opts)end
 assert(math.abs(p[2]+.1)<1e-9 and math.abs(f[3]-.5)<1e-9,'User rotation must not accumulate through output echo')
 opts.handycam_yaw_deg=0;opts.handycam_pitch_deg=0;opts.handycam_right_cm=-10
 p,f=c.step({0,0,2},{0,1,0},3,opts);assert(math.abs(p[1]+.1)<1e-9 and math.abs(p[2])<1e-9)
end
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
f.open();assert(not f.controls.handycam_intensity.disabled and not f.controls.handycam_lag_ms.disabled)
assert(f.runtime.handle.get('handycam_forward_cm')==14 and f.runtime.handle.get('handycam_up_cm')==7);
assert(f.runtime.handle.set('handycam_forward_cm',0));assert(f.runtime.handle.set('handycam_up_cm',0));
assert(f.runtime.handle.get('handycam_lag_ms')==0);assert(f.runtime.handle.set('handycam_lag_ms',0))
assert(f.menu.handle.set('roll',45));assert(f.menu.handle.set('handycam_intensity',0));assert(f.menu.handle.set('action_camera_mode',2));assert(f.runtime.begin_shot())
assert(f.runtime.mode=='shot'and not f.lease and f.hidden,'Action releases keyboard and hides avatar')
f.step(.016,1);assert(f.position[3]==2);assert(math.abs(f.up[3]-1)<1e-8,'Handycam must ignore placement roll')
f.head={0,0,3};f.step(.016,1);assert(f.position[3]==3)
assert(f.runtime.reposition_shot());f.step(.016,1)
assert(f.hidden and f.lease and f.rate==0,'Settings keeps avatar hidden and reacquires input/freeze')
assert(not f.controls.handycam_position_handle.disabled)
local before_saves=f.saves
assert(f.menu.actions.handycam_adjust({handycam_right_cm=12,handycam_up_cm=5,handycam_yaw_deg=10}));f.step(.016,1)
assert(f.saves==before_saves and math.abs(f.position[2]+.12)<1e-8 and math.abs(f.position[3]-3.05)<1e-8,'Drag previews without disk writes and invalidates option cache')
assert(f.menu.actions.handycam_adjust(nil,false));f.step(.016,1)
assert(f.saves==before_saves and f.position[2]==0 and f.position[3]==3,'Cancelled drag restores stored offsets')
assert(f.menu.actions.handycam_adjust({handycam_right_cm=8}));assert(f.menu.actions.handycam_adjust(nil,true));f.step(.016,1)
assert(f.saves==before_saves+1 and math.abs(f.position[2]+.08)<1e-8,'Release commits a single settings batch')
assert(f.runtime.handle.set('handycam_right_cm',0))

assert(math.abs(f.up[3]-1)<1e-8,'Settings must retain Handycam roll')
f.head={0,0,4};f.step(.016,1);assert(f.position[3]==4,'Handycam continues following while its settings are open')
assert(f.controls.action_camera_mode.disabled,'End the attached session before changing camera type')
assert(f.runtime.handle.set('handycam_forward_cm',10));assert(f.runtime.handle.set('handycam_up_cm',5));f.step(.016,1)
assert(math.abs(f.position[3]-4.05)<1e-8 and f.runtime.mode=='menu','Offset edits apply while attached in settings')
assert(f.runtime.handle.set('handycam_forward_cm',0));assert(f.runtime.handle.set('handycam_up_cm',0));f.step(.016,1)
assert(f.position[3]==4,'Offset edits must not change tracking history')
assert(f.runtime.handle.set('handycam_lag_ms',150))
f.head={0,0,5};f.step(.016,1);local before=f.position[3];assert(before>4 and before<5)
assert(f.runtime.focus());f.step(.016,1)
assert(f.runtime.mode=='shot'and not f.lease and f.rate==1 and f.hidden)
assert(f.position[3]>before and f.position[3]<5,'Returning must preserve the smoothing history')
local function key(name)
 f.pressed[name]=true;f.step(.016,1);f.pressed[name]=false;f.step(.016,1)
end
key('p');assert(f.runtime.mode=='menu'and f.hidden and f.lease)
key('p');assert(f.runtime.mode=='shot'and f.hidden and not f.lease,'Photo toggle resumes attached shot')
key('p');key('esc');assert(f.runtime.mode=='shot'and f.hidden and not f.lease,'ESC dismisses settings without ending Handycam')
assert(f.runtime.reposition_shot())
assert(f.runtime.begin_shot());f.head_identity='replacement';f.step(.016,1)
assert(not f.runtime.active and not f.hidden and not f.lease,'Player replacement closes and cleans up')
f.finish()
local g=fixture(false,setup);g.open();g.menu.handle.set('action_camera_mode',2);g.head_error=true
assert(not g.runtime.begin_shot()and g.runtime.mode=='menu'and g.lease,'Missing head preserves placement')
g.finish()
local e=fixture(false,setup);e.open();e.menu.handle.set('action_camera_mode',2);assert(e.runtime.begin_shot())
assert(e.runtime.reposition_shot());assert(e.runtime.close());e.step(.016,1)
assert(not e.runtime.active and not e.hidden and not e.lease and e.rate==1,'Explicit exit restores camera, visibility, time and controls')
e.finish()
local w=fixture(false,setup);w.open();w.menu.handle.set('action_camera_mode',2);assert(w.runtime.begin_shot())
assert(w.runtime.reposition_shot());w.session={};w.step(1.1,1)
assert(not w.runtime.active and not w.hidden and not w.lease,'Session retirement is checked even in settings')
w.finish()
-- F11 starts from gameplay, toggles once per press and explicitly ends even
-- while settings are open; editing and foreground guards consume held edges.
do
 local k=fixture(false,setup)
 local function press(key)k.pressed[key]=true;k.step(.016,1);k.pressed[key]=false;k.step(.016,1)end
 assert(k.runtime.handle.get('handycam_key')==122)
 press('f11');assert(k.runtime.active and k.runtime.mode=='shot'and not k.lease)
 k.pressed.f11=true;k.step(.016,1);assert(not k.runtime.active and not k.lease)
 for _=1,60 do k.step(.016,1)end;assert(not k.runtime.active,'Held F11 cannot restart')
 k.pressed.f11=false;k.step(.016,1)
 press('f11');press('p');assert(k.runtime.mode=='menu'and k.lease)
 press('f11');assert(not k.runtime.active and not k.lease,'F11 explicitly ends from settings')
 k.menu.editing_key=function()return true end
 k.pressed.f11=true;k.step(.016,1);assert(not k.runtime.active)
 k.menu.editing_key=function()return false end;k.step(.016,1);assert(not k.runtime.active,'Rebinding key must not trigger after editor closes')
 k.pressed.f11=false;k.step(.016,1)
 k.foreground=false;press('f11');assert(not k.runtime.active);k.foreground=true
 k.runtime.handle.set('handycam_key',120);press('f11');assert(not k.runtime.active)
 press('f9');assert(k.runtime.mode=='shot','Custom binding replaces F11')
 k.finish()
 local missing=fixture(false,setup);missing.head_error=true
 missing.pressed.f11=true;missing.step(.016,1)
 assert(missing.runtime.mode=='menu'and missing.lease,'Missing target leaves selection available without retrying each frame')
 local reads=missing.head_reads;for _=1,10 do missing.step(.016,1)end;assert(missing.head_reads==reads)
 missing.finish()
end
print('Handycam: branch tracking, output-echo rejection, no idle head reads, gameplay lease handoff, owned visibility restore and replacement/missing-head cleanup passed')

-- First-person handoff keeps the shot/settings/visibility while releasing camera writes.
do
 local t=fixture(false,function(f,deps)
  setup(f,deps)
  f.native_position={0,0,0};f.yields=0;f.resumes=0;f.resume_attempts=0;f.resume_failures=0
  deps.handycam_ads=dofile('freecam/windows_handycam_ads.lua')
  deps.camera_signals={new=function(sr,log,on_event)
   return{tick=function(active)if active and f.ads_event then on_event(unpack(f.ads_event));f.ads_event=nil end end,
    observe=function()end,release=function()end}
  end}
  local old=deps.camera.new;deps.camera.new=function(...)
   local c=old(...);c.yield_view=function()f.yields=f.yields+1;return true end
   c.resume_view=function()
    f.resume_attempts=f.resume_attempts+1
    if f.resume_failures>0 then f.resume_failures=f.resume_failures-1;return false,'Rendered camera still settling','pending'end
    f.resumes=f.resumes+1;return true
   end
   c.frame=function()return{position=f.native_position,forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}end
   return c
  end
 end)
 t.open();t.runtime.handle.set('action_camera_mode',2);assert(t.runtime.begin_shot());t.step(.016,2)
 local saves=t.saves;t.native_position={.163,0,2};t.ads_event={'middle',true};t.step(.016,2)
 assert(t.yields==1 and t.runtime.active and t.hidden and not t.lease,'ADS keeps Handycam intent and POV visibility')
 local writes=t.camera_writes;t.step(.016,20);assert(t.camera_writes==writes and t.saves==saves,'Native ADS receives zero camera writes or settings saves')
 t.native_position={1.132,0,2};t.ads_event={'middle',true};t.step(.016,1)
 assert(t.resumes==1 and t.camera_writes>writes and t.saves==saves and t.hidden,'Leaving ADS resumes the existing shot without settings writes')
 t.ads_event={'middle',false};t.step(.016,1)
 t.native_position={.163,0,2};t.ads_event={'middle',true};t.step(.016,2);assert(t.yields==2)
 t.ads_event={'middle',false};t.step(.016,1)
 t.resume_failures=2;t.native_position={1.132,0,2};t.ads_event={'middle',true};writes=t.camera_writes;t.step(.016,2)
 assert(t.runtime.active and t.hidden and t.camera_writes==writes and t.resumes==1,'Dive/ADS camera mismatch retains shot and visibility with no camera writes')
 for i=1,10 do t.step(.016,1)end;assert(t.resumes==2 and t.camera_writes>writes and t.saves==saves,'Camera publication can settle before owned Handycam resumes')
 t.ads_event={'middle',false};t.step(.016,1)
 t.native_position={.163,0,2};t.ads_event={'middle',true};t.step(.016,2)
 t.ads_event={'middle',false};t.step(.016,1)
 t.resume_failures=1000;t.native_position={1.132,0,2};t.ads_event={'middle',true};writes=t.camera_writes
 local attempts=t.resume_attempts;for i=1,200 do t.step(.016,1)end
 assert(t.runtime.active and t.hidden and t.camera_writes==writes and t.resume_attempts-attempts<=40,'Unavailable camera never steals a foreign view; recovery work is bounded')
 attempts=t.resume_attempts;for i=1,200 do t.step(.016,1)end;assert(t.resume_attempts==attempts,'Expired recovery window stays idle')
 t.resume_failures=0;t.ads_event={'right',false};t.step(.016,3)
 assert(t.resumes==3 and t.camera_writes>writes and t.saves==saves,'A fresh aim event can recover the retained shot after timeout')
 t.native_position={.163,0,2};t.ads_event={'middle',false};t.step(.016,2)
 assert(t.yields==4,'Release-only notification can identify native ADS entry')
 t.native_position={1.132,0,2};t.ads_event={'middle',false};t.step(.016,2)
 assert(t.resumes==4 and t.runtime.active,'Release-only ADS exit reacquires Handycam without requiring aim release')
 t.native_position={.163,0,2};t.ads_event={'middle',true};t.step(.016,2)
 for _=1,60 do t.step(.016,1)end;writes=t.camera_writes
 t.native_position={1.132,0,2};t.step(.016,1)
 assert(t.resumes==5 and t.runtime.active and t.hidden and t.camera_writes>writes and t.saves==saves,'Late native return without either mouse edge must restore the retained Handycam shot')
 assert(t.runtime.close(true));assert(not t.hidden and not t.runtime.handycam_ads.suspended,'Explicit exit clears ADS intent and restores visibility')
 t.finish()
end
print('Handycam ADS runtime: yield/resume, persistent shot, zero suspended camera writes/settings commits and explicit cleanup passed')

-- The opt-in movement experiment follows existing input/render lifetimes.
do
 local t=fixture(false,function(f,deps)
  setup(f,deps);f.probe_events=0;f.probe_ticks=0
  deps.movement_probe={event=function(name,pressed)
   f.probe_events=f.probe_events+1;f.probe_owned=pressed;return true
  end,tick=function(head,enabled,now,forward)
   assert(head and forward and type(now)=='number');f.probe_ticks=f.probe_ticks+1
   if not enabled then f.probe_owned=false end;return true
  end,release=function()
   if f.probe_refuse and f.probe_owned then return false,'movement restore pending'end
   f.probe_owned=false;return true
  end}
  deps.camera_signals={new=function(sr,log,ads,diagnostics,movement)
   assert(type(movement)=='function')
   return{tick=function(active)if active and f.movement_event then movement(unpack(f.movement_event));f.movement_event=nil end end,
    observe=function()end,release=function()end}
  end}
 end)
 t.open();t.runtime.handle.set('action_camera_mode',2);assert(t.runtime.begin_shot())
 t.movement_event={'s',true};t.step(.016,1);assert(t.probe_events==1 and t.probe_owned and t.probe_ticks>0)
 assert(t.runtime.reposition_shot());t.step(.016,1);assert(not t.probe_owned,'Menu entry cancels the experiment')
 assert(t.runtime.focus());t.movement_event={'a',true};t.step(.016,1);assert(t.probe_owned)
 t.foreground=false;t.step(.016,1);assert(not t.probe_owned,'Focus loss cancels the experiment')
 t.foreground=true;t.step(.016,1);t.movement_event={'d',true};t.step(.016,1);assert(t.probe_owned)
 t.probe_refuse=true;assert(not t.runtime.close(true),'Failed experiment restoration blocks successful cleanup reporting')
 t.probe_refuse=false;assert(t.runtime.close(true)and not t.probe_owned);t.finish()
end

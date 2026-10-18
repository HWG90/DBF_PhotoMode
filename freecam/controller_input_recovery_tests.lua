-- Real controller/service/cursor-lease integration. Only OS/engine boundaries
-- are simulated; no game process, native hook or injected input is used.
local root=assert(rawget(_G,'DBF_PHOTO_TEST_ROOT'))
local Core=dofile('src/core.lua')
local Controller=dofile(root..'controller.lua')
local Camera=dofile(root..'vendor/camera_input.lua')
local Capture=dofile(root..'photo_input_capture.lua')
local Options=dofile(root..'photo_options.lua')
local Simulation=dofile(root..'simulation.lua')
local ChatContext=dofile(root..'chat_context.lua')

local function fixture(hover)
 local f={keys={},clock=1,epoch=1,world_time=20,rate=1,focused=true,available=true,parent=false,mcm=false,
  focus=true,cursor=false,clip=true,mode=0,installs=0,releases=0,leases=0,events={},logs={},dx=0,dy=0}
 local function event(name)f.events[#f.events+1]=name end
 local window={mouse_focus=function()return f.focus end,show_cursor=function()return f.cursor end,clip_cursor=function()return f.clip end,
  set_mouse_focus=function(value)
   if value and f.fail_restore_focus or not value and f.fail_lock_focus then return false end
   f.focus=value;event(value and'focus_restore'or'focus_lock');return true
  end,
  set_show_cursor=function(value)f.cursor=value;event(value and'cursor_show'or'cursor_hide');return true end,
  set_clip_cursor=function(value)f.clip=value;event(value and'clip_on'or'clip_off');return true end}
 f.window=window
 f.capture=Capture.new(window,function()return f.parent end)
 local lease_acquire=f.capture.acquire
 f.capture.acquire=function(...)f.leases=f.leases+1;return lease_acquire(...)end
 local native={mcm_captured=function()return f.mode end,
  mcm_install=function()f.installs=f.installs+1;return f.fail_install and 0 or 1 end,
  mcm_capture=function(mode)
   if mode==1 and f.fail_set_focus then return 0 end
   f.mode=mode;event('capture_'..mode);return 1
  end,
  mcm_release=function()
   if hover then assert(f.rate>0 and not f.guard_owned,'Hover must resume time and release its guard before native input release')end
   f.releases=f.releases+1;f.mode=0;event('native_release')
  end,
  mcm_photo_pause_allowed=function()return 1 end}
 local input={poll=function()end,down=function(key)return f.keys[key]==true end,
  focused=function()return f.focused end,window=function()return 1 end,now=function()return f.clock end,
  lock_aim=function()return window.set_mouse_focus(false)and not window.mouse_focus()end,
  menu_cursor=function(menu)
   if menu and f.fail_menu_cursor then return false end
   window.set_show_cursor(menu);window.set_clip_cursor(not menu);return true
  end,
  look=function()local x,y=f.dx,f.dy;f.dx,f.dy=0,0;return x,y end,
  wheel=function()return 0 end,mouse=function()return 700,200 end,photo_check={}}
 f.input=Camera.new(native,f.capture,input,function()return f.available and not f.parent end)
 local api=Core.new(nil,function()end)
 api.is_open=function()return f.mcm end
 api.close=function()f.mcm=false;return true end
 api.camera_input=f.input;api.photo_resolution=function()return 1920,1080 end
 api.create_photo_view=function()return{}end
 f.api=api
 local factory={new=function(_,actions)
  f.actions=actions
  return{bind=function()end,draw=function()end,tick=function()f.menu_ticks=(f.menu_ticks or 0)+1 end,
   suspend=function()f.suspends=(f.suspends or 0)+1 end,close=function()return true end,
   dismiss=function()return false end,editing_key=function()return false end,editing_text=function()return false end}
 end}
 if hover then
  local sr={Network={game_session=function()return 1 end},GameSession={other_peers=function()return{}end,synchronizing_peers=function()return{}end},
   World={time=function()return f.world_time end,delta_time=function()return f.rate==0 and 0 or .016*f.rate end}}
   local backend={snapshot=function()return{value=f.rate}end,value=function()return f.rate end,now=function()return f.clock end,
    set=function(_,rate)
     if f.require_scene_proof then assert(f.scene_ready==true,'Simulation write preceded fresh scene proof')end
     f.time_writes=(f.time_writes or 0)+1;f.rate=rate;event(rate==0 and'time_freeze'or'time_resume')
    end}
  local guard={prepare=function()f.prepared=f.epoch;f.guard_owned=true;return true end,
   ready=function()return f.epoch>(f.prepared or f.epoch),'Waiting for a gameplay update'end,
   acquire=function()assert(f.epoch>f.prepared);f.guard_owned=true;return true end,
   release=function()f.guard_owned=false;event('hover_release');return true end,
   hold=function()return true end,status=function()return{owned=f.guard_owned}end}
  f.freeze=Simulation.new(sr,function()return 1,2,true end,backend,guard)
 end
 f.photo={};DBFMCM=api
 f.controller=Controller.new(f.photo,{},function()if f.scene_ready==false then return false,'Rendered camera is warming up',f.scene_retry==true end;return true end,function(message)f.logs[#f.logs+1]=message end,
  f.freeze,Options,nil,factory,nil,nil,nil,nil,nil,nil,nil,nil,function()return f.epoch end)
 function f.tick()f.clock=f.clock+.016;f.controller.tick(.016)end
 function f.press(key)f.keys[key]=true;f.tick();f.keys[key]=false;f.tick()end
 function f.update()f.epoch=f.epoch+1;f.world_time=f.world_time+.016*f.rate;f.tick()end
 function f.start()
  f.press(80)
  if hover then f.update()end
  assert(f.photo.active and f.mode==1 and f.input.status().ready,'Photo must enter with a live menu lease')
 end
 function f.close()
  assert(f.controller.close());assert(f.mode==0 and not f.capture.status().active and not f.input.status().active,'Fixture leaked input ownership')
  DBFMCM=nil
 end
 f.tick();f.handle=assert(api.mods.dbf_freecam.handle)
 return f
end

-- Native capture can disappear while the application stays foreground and the
-- menu-focus selection stays true. The controller owns cleanup and reacquisition.
local disabled=fixture();disabled.api.photo_standalone=true
assert(disabled.handle.set('enabled',false));disabled.press(80)
assert(not disabled.photo.active and disabled.mode==1 and disabled.input.status().active,'Disabled-camera settings must own a real lease')
local loan=disabled.controller.editor_bridge
assert(loan.acquire('Epic LUT') and disabled.mode==0 and not disabled.input.status().active and disabled.focus,'Inactive settings loan must release Photo native and cursor capture')
assert(loan.release('Epic LUT'));disabled.close()

local cleanup=fixture();cleanup.start();cleanup.fail_restore_focus=true
assert(not cleanup.controller.editor_bridge.acquire('Epic LUT') and cleanup.input.status().cleanup_pending,'An unacknowledged release cannot grant an editor loan')
assert(cleanup.controller.editor_bridge.status().owner==nil)
cleanup.fail_restore_focus=false;assert(cleanup.controller.editor_bridge.acquire('Epic LUT'))
assert(cleanup.controller.editor_bridge.release('Epic LUT'));cleanup.close()

local f=fixture();f.start();local installs=f.installs;local drawn=f.menu_ticks
f.mode=0;f.tick()
assert(f.photo.active and f.mode==0 and not f.input.status().active and f.suspends>0,'Lost menu capture must cleanly relinquish its old lease while retaining the shot')
f.tick()
assert(f.photo.active and f.mode==1 and f.input.status().ready and f.installs==installs+1 and f.menu_ticks>drawn,'A fresh lease must restore the selected menu focus')
f.press(9);assert(f.mode==3 and f.input.status().ready,'Tab must regain camera focus after recovery')
f.dx,f.dy=17,-5;f.tick()
assert(f.photo.input.mouse_x==17 and f.photo.input.mouse_y==-5,'Recovered input must deliver native look deltas again')
f.close()

-- Failed cursor restoration retains the actual token/provider for a retry.
-- Starting another acquisition over the failed snapshot would trap mouse focus.
f=fixture();f.start();f.fail_restore_focus=true;local leases=f.leases;installs=f.installs
f.mode=0;f.tick();local status=f.input.status()
assert(f.photo.active and status.active and status.owned and status.cleanup_pending and f.capture.status().active,'Failed restoration must retain its cleanup lease')
for _=1,3 do f.tick()end
assert(f.leases==leases and f.installs==installs and f.input.status().cleanup_pending,'Cleanup must retry before another capture acquisition')
f.fail_restore_focus=false;f.tick();f.tick()
assert(f.mode==1 and f.input.status().ready and f.leases==leases+1,'Successful cleanup must allow one fresh menu lease')
f.close()

-- Acquisition may fail after the engine mouse flags changed. Keep ownership
-- until restoration succeeds, and allow an ordinary later toggle to retry.
f=fixture();f.fail_install=true;f.fail_restore_focus=true;f.press(80)
status=f.input.status()
assert(not f.photo.active and status.active and status.cleanup_pending and f.capture.status().active,'Partial acquisition must retain a refused cleanup snapshot')
leases=f.leases;f.press(80)
assert(f.leases==leases and f.input.status().cleanup_pending,'A second toggle must not acquire over pending cleanup')
f.fail_install=false;f.fail_restore_focus=false;f.start()
assert(f.leases==leases+1 and f.mode==1,'A cleaned partial acquisition must remain retryable')
f.close()

-- Focus switching can fail after acquisition; neither native nor cursor state
-- may leave an apparently live provider that rejects every later start.
f=fixture();f.fail_set_focus=true;f.press(80)
assert(not f.photo.active and f.mode==0 and not f.input.status().active and f.focus,'Failed initial menu focus must release its partial native/cursor ownership')
f.fail_set_focus=false;f.start();f.press(9);assert(f.mode==3)
f.fail_menu_cursor=true;f.press(9)
assert(f.photo.active and f.mode==0 and not f.input.status().active,'A failed menu cursor handoff must enter recovery')
f.fail_menu_cursor=false;f.tick()
assert(f.mode==1 and f.input.status().ready,'A cursor handoff failure must not leave a dead provider')
f.close()

-- An external LLL/MCM frontend owns its current Window flags. Losing Photo's
-- availability must not restore the old gameplay flags over that frontend.
for _,kind in ipairs({'lll','mcm'})do
 f=fixture();f.start();f.available=false;f.parent=true;f.mcm=kind=='mcm'
 f.focus,f.cursor,f.clip=false,true,false
 f.tick();local acquired=f.leases
 assert(f.photo.active and f.mode==0 and not f.input.status().active,'An external frontend must receive Photo input handoff')
 for _=1,3 do f.tick()end
 assert(f.focus==false and f.cursor==true and f.clip==false and f.leases==acquired,'Photo must preserve external Window flags and refuse capture while unavailable')
 f.parent,f.mcm,f.available=false,false,true;f.focus,f.cursor,f.clip=true,false,true;f.tick()
 assert(f.mode==1 and f.input.status().ready,'Photo must resume only after the external frontend releases ownership')
 f.close()
end

-- A hover zero-time pause cannot safely relinquish suppression first. Exercise
-- the real Simulation adapter and require resume/guard release before native.
f=fixture(true);f.start()
assert(f.rate==0 and f.guard_owned and f.freeze.needs_input_capture(),'Fixture must own an actual hover-dependent zero-time pause')
local before=#f.events;f.mode=0;f.tick()
assert(not f.photo.active and f.rate==1 and not f.guard_owned and f.mode==0 and not f.capture.status().active,'Lost hover capture must stop Photo and resume safely')
local resumed,released
for index=before+1,#f.events do
 if f.events[index]=='time_resume'then resumed=index end
 if f.events[index]=='native_release'then released=index end
end
assert(resumed and released and resumed<released,'Hover recovery must restore positive time before native input release')
f.close()

-- Native Escape handoff uses the real ChatContext hooks. Its bounded native
-- stack reader is independently exercised by chat_context_tests; only the
-- observed open/closed state is replaced here, never the cursor ownership code.
local function attach_context(f)
 local reader=ChatContext.new({module=function()return nil end,read=function()error('No native reads in the controller fixture')end},f.window)
 reader.native_menu_active=function()return f.native_menu==true end
 reader.chat_active=function()return false end
 assert(reader.attach(f.api))
 assert(type(f.input.native_menu_handoff)=='function'and type(f.input.native_menu_resume)=='function','Native handoff and resume must attach as one owned hook pair')
 f.reader=reader
end
local function open_native(f)
 f.native_menu=true;f.tick()
 assert(f.photo.active and f.mode==0 and not f.capture.status().active and not f.input.status().active,'Escape must release the Photo lease while retaining its placement')
 assert(f.focus==false and f.cursor==true,'Native UI must receive its owned visible cursor')
end
local function gameplay_restored(f,message)
 assert(not f.photo.active and f.mode==0 and f.focus==true and f.cursor==false,message or'Normal gameplay mouse focus must be restored on Photo exit')
end

-- Reacquiring Photo after native Escape must never snapshot its own temporary
-- UI focus=false as the final gameplay baseline, even after repeated cycles.
f=fixture();attach_context(f)
for _=1,20 do
 f.start();open_native(f);f.native_menu=false;f.tick()
 assert(f.photo.active and f.mode==1 and f.input.status().ready,'Escape close must resume the selected Photo menu')
 f.press(80);gameplay_restored(f,'Repeated Escape/Photo cycles must retain the original gameplay focus and hidden cursor')
end
f.close()

-- The native UI can hide its cursor before our resume callback runs. That
-- independent change stays untouched while the still-owned focus flag restores.
f=fixture();attach_context(f);f.start();open_native(f)
f.native_menu=false;f.cursor=false
local writes=#f.events
assert(f.input.native_menu_resume())
assert(f.focus==true and f.cursor==false,'Native UI cursor hiding must not prevent restoration of the remaining focus flag')
for index=writes+1,#f.events do assert(f.events[index]~='cursor_show'and f.events[index]~='cursor_hide','Resume must not rewrite a cursor flag already changed by native UI')end
f.tick();assert(f.mode==1);f.press(80);gameplay_restored(f);f.close()

-- A closed Photo camera still owns the temporary native-menu handoff record.
-- Idle controller ticks must restore it once Escape closes, without reacquiring.
f=fixture();attach_context(f);f.start();open_native(f)
assert(f.controller.stop());assert(not f.photo.active and f.focus==false and f.cursor==true)
f.tick();assert(f.focus==false and f.cursor==true,'Photo exit must leave the still-open native menu cursor usable')
local leases=f.leases;f.native_menu=false;f.cursor=false;f.tick()
gameplay_restored(f,'Escape close after Photo exit must restore normal gameplay focus through idle cleanup')
assert(f.leases==leases,'Idle native-menu cleanup must not start a Photo input lease')
f.start();f.press(80);gameplay_restored(f);f.close()

-- A refused native-menu resume keeps its record and prevents a new Photo lease
-- from capturing the un-restored UI flags. Retrying restores the original pair.
f=fixture();attach_context(f);f.start();open_native(f)
leases=f.leases;f.fail_restore_focus=true;f.native_menu=false
for _=1,3 do f.tick()end
assert(f.photo.active and f.mode==0 and not f.input.status().active and f.leases==leases and f.focus==false,'Failed handoff resume must block new capture while retaining restoration work')
f.fail_restore_focus=false;f.tick()
assert(f.mode==1 and f.input.status().ready and f.leases==leases+1,'A later successful native-menu resume must permit exactly one fresh lease')
f.press(80);gameplay_restored(f);f.close()

-- Another frontend can take ownership with exactly the same visible flags.
-- Availability is the ownership signal: matching values do not permit a write.
f=fixture();attach_context(f);f.start();open_native(f)
f.available=false;f.parent=true;writes=#f.events;leases=f.leases
assert(f.input.native_menu_resume())
assert(#f.events==writes and f.focus==false and f.cursor==true,'Known external ownership must retire handoff work without touching matching foreign flags')
f.native_menu=false
for _=1,3 do f.tick()end
assert(f.leases==leases and #f.events==writes and f.focus==false and f.cursor==true,'Photo must not steal flags or capture after an external frontend takes over')
f.parent=false;f.available=true;f.focus,f.cursor,f.clip=true,false,true;f.tick()
assert(f.mode==1 and f.input.status().ready)
f.press(80);gameplay_restored(f);f.close()

print('Controller input recovery: real camera/cursor leases, lost menu capture, Tab/look recovery, retained cleanup retries, partial acquire/focus failures, LLL/MCM ownership and hover resume-before-release passed')
print('Native Escape lifecycle: repeated handoff/reacquire/final exit, native cursor changes, idle cleanup, refused resume retry and same-value foreign ownership passed')

-- Ordinary gameplay retains cheap hotkeys/native-menu resume, but no longer
-- repeats all camera/effect/menu release callbacks after one successful stop.
f=fixture()
local idle_stops=0;local real_stop=f.controller.stop
f.controller.stop=function(...)idle_stops=idle_stops+1;return real_stop(...)end
assert(f.controller.scene_required()==false)
for _=1,1000 do f.tick()end
assert(idle_stops==0,'Clean idle renders repeated full Photo cleanup')
f.start();assert(f.controller.scene_required()==true)
f.press(80);assert(idle_stops==1 and not f.controller.scene_required(),'Photo exit must acknowledge cleanup once')
for _=1,1000 do f.tick()end
assert(idle_stops==1,'Successful exit kept invoking release callbacks during normal gameplay')
f.close()

-- A refused cursor restoration keeps the idle latch dirty and retains the
-- exact input provider until its retry is acknowledged, then becomes quiet.
f=fixture();f.start();f.fail_restore_focus=true
idle_stops=0;real_stop=f.controller.stop
f.controller.stop=function(...)idle_stops=idle_stops+1;return real_stop(...)end
assert(f.controller.stop()==false and not f.photo.active and f.controller.scene_required())
for _=1,3 do f.tick()end
assert(idle_stops==4 and f.input.status().cleanup_pending,'Pending cleanup stopped retrying while Photo was inactive')
f.fail_restore_focus=false;f.tick()
assert(idle_stops==5 and not f.controller.scene_required())
for _=1,100 do f.tick()end
assert(idle_stops==5,'Acknowledged cleanup never reached clean idle')
f.close()

-- Acquisition can fail after native capture has partly changed the cursor.
-- Its public owned/pending status must retain a provider for cleanup retries.
f=fixture();f.fail_install=true;f.fail_restore_focus=true
f.press(80)
assert(not f.photo.active and f.input.status().cleanup_pending and f.controller.scene_required(),'Partial acquisition cleanup was orphaned')
f.fail_restore_focus=false;f.tick()
assert(not f.input.status().active and not f.input.status().cleanup_pending and not f.controller.scene_required())
f.fail_install=false;f.start();f.press(80);f.close()
print('Idle controller: 1000 clean renders and 1000 post-exit renders perform zero repeated stops; failed and partial-acquire cleanup retries remain live')

-- Cold idle discovery may need another render while the avatar is moving.
-- Keep one opening edge, but acquire no input/pause ownership before proof.
f=fixture();f.scene_ready=false;f.scene_retry=true;f.press(80)
assert(f.controller._scene_start_pending and not f.photo.active and f.leases==0 and f.mode==0)
assert(f.controller.scene_required()and f.controller.camera_owned())
for _=1,3 do f.tick()end
assert(f.leases==0,'Scene warming captured input before camera proof')
f.scene_ready=true;f.tick()
assert(f.photo.active and f.leases==1 and not f.controller._scene_start_pending,'Delayed proof required a second opening key press')
f.press(80);f.close()

for _,cancel in ipairs({'toggle','focus','chat','native','escape','disabled','provider','editor'})do
 f=fixture();f.scene_ready=false;f.scene_retry=true;f.press(80)
 assert(f.controller._scene_start_pending)
 if cancel=='toggle'then f.press(80)
 elseif cancel=='focus'then f.focused=false;f.tick()
 elseif cancel=='chat'then f.input.chat_active=function()return true end;f.tick()
 elseif cancel=='native'then f.mcm=true;f.tick()
 elseif cancel=='escape'then f.keys[27]=true;f.tick()
 elseif cancel=='disabled'then assert(f.handle.set('enabled',false));f.tick()
 elseif cancel=='provider'then local replacement={};for k,v in pairs(f.input)do replacement[k]=v end;f.api.camera_input=replacement;f.tick()
 else assert(f.controller.editor_bridge.acquire('Epic LUT'));assert(f.controller.editor_bridge.release('Epic LUT'))end
 assert(not f.controller._scene_start_pending and not f.photo.active and f.leases==0,'Cold scene request did not cancel: '..cancel)
 f.close()
end
f=fixture();f.scene_ready=false;f.scene_retry=true;f.press(80)
for _=1,120 do f.tick()end
assert(not f.controller._scene_start_pending and f.leases==0 and not f.controller.scene_required(),'Cold scene request did not time out cleanly')
f.close()
f=fixture(true);f.scene_ready=false;f.scene_retry=true;f.press(80)
assert(f.leases==0 and not f.guard_owned and f.rate==1,'Cold proof started hover preparation prematurely')
f.scene_ready=true;f.tick();assert(f.controller._pending_start and f.leases==0 and f.rate==1)
f.update();assert(f.photo.active and f.mode==1 and f.rate==0,'Scene-ready retry bypassed the ordinary hover update qualification')
f.press(80);f.close()
print('Cold scene opening: delayed proof retains one key edge, cancellation/timeout own no native input, and hover preparation still requires its gameplay update')

-- Closed-Photo slow motion also needs on-demand discovery after idle drops its
-- camera context. Its pending action must never open Photo or capture input.
f=fixture(true);f.scene_ready=false;f.scene_retry=true;f.require_scene_proof=true
f.press(220)
assert(f.controller._scene_start_pending and f.controller._scene_start_pending.action=='slowmo')
assert(not f.photo.active and not f.controller.slowmo_active and f.leases==0 and not f.time_writes and f.rate==1)
for _=1,3 do f.tick()end
assert(f.leases==0 and not f.time_writes,'Cold slow motion acquired input or changed time before proof')
f.scene_ready=true;f.tick()
assert(not f.photo.active and f.controller.slowmo_active and f.rate==.2 and f.leases==0 and not f.controller._scene_start_pending)
for _=1,5 do f.tick()end
assert(f.controller.slowmo_active and f.rate==.2 and f.leases==0,'Idle stop dropped the standalone slow-motion policy')
f.press(220);assert(not f.controller.slowmo_active and f.rate==1 and not f.photo.active and f.leases==0);f.close()

f=fixture(true);f.scene_ready=false;f.scene_retry=true;f.press(220);f.press(220)
assert(not f.controller._scene_start_pending and not f.controller.slowmo_active and f.leases==0 and f.rate==1,'Second slow-motion edge did not cancel cold warming')
f.close()
f=fixture(true);f.scene_ready=false;f.scene_retry=true;f.press(220)
for _=1,120 do f.tick()end
assert(not f.controller._scene_start_pending and not f.controller.slowmo_active and f.leases==0 and f.rate==1,'Cold slow motion did not time out without ownership')
f.close()
-- The independent slow-motion shortcut remains available when Photo itself is
-- disabled; active/off transitions do not need fresh discovery before release.
f=fixture(true);assert(f.handle.set('enabled',false));f.scene_ready=false;f.scene_retry=true;f.press(220)
assert(f.controller._scene_start_pending and f.controller._scene_start_pending.action=='slowmo')
f.scene_ready=true;f.tick();assert(f.controller.slowmo_active and not f.photo.active and f.leases==0)
f.scene_ready=false;f.scene_retry=false;f.press(220)
assert(not f.controller.slowmo_active and f.rate==1 and f.leases==0);f.close()
f=fixture(true);f.start();f.scene_ready=false;f.scene_retry=false
assert(f.controller._toggle_slow_motion()and f.controller.slowmo_active and f.rate==0,'Active paused Photo must retain its zero-time pose when slow motion is selected')
f.scene_ready=true;f.press(80);assert(not f.photo.active and f.controller.slowmo_active and f.rate==.2)
f.press(220);assert(f.rate==1 and not f.controller.slowmo_active);f.close()
print('Cold standalone slow motion: delayed scene proof changes time without Photo/native lease; second-key cancellation, timeout, disabled Photo and active/off behavior preserved')

-- Editor loans hide the menu and consume mouse input; return is menu-first.
do
 local f=fixture();f.press(80);f.press(9)
 assert(f.photo.active)
 local before=f.suspends or 0
 assert(f.controller.editor_bridge.acquire('Epic LUT'))
 assert((f.suspends or 0)>before and f.controller.camera_suspended(),'Editor handoff must hide and suspend Photo')
 f.dx=100;f.tick();assert(not f.photo.input.mouse_x,'Editor mouse movement entered Photo')
 assert(f.controller.editor_bridge.release('Epic LUT'));f.dx=0;f.tick()
 assert(f.mode==1,'Closing Epic LUT must return to Photo menu, not camera movement')
 f.close()
end

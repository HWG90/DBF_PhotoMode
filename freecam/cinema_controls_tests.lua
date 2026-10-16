local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Options=dofile(root..'photo_options.lua')
local Cinema=dofile(root..'cinema_camera.lua');local Menu=dofile(root..'photo_menu.lua')
local photo={};local context={world='mission',epoch=1,player='local:1',gameplay_input=true}
local now=100
local cinema=Cinema.new(photo,function()return context end,function()return now end)
local keys={};local native_open=false;local captured=false;local acquire_count,release_count=0,0;local focused=true;local chat=false
local rate=1;local hover_pending=false;local fail_release=false;local effect_releases=0;local snapshot_requests=0;local screenshot_active=false
local camera_lease=false;local camera_acquires,camera_releases=0,0;local effect_ok=true
local commands={};local owned_bone='original';local order={};local pose_request=false
local poses={active=false,pending=false,status='fixture'}
function poses.refresh()return false,'fixture',{}end
function poses.release()if poses.active then poses.pending=true;pose_request=true end;return true end
local freeze={start=function(v)rate=v or 0;return true end,hold=function()return true end,paused=function()return rate==0 end,
 release=function()assert(not poses.active and not poses.pending,'Cinema resumed time before restoring fixed pose');rate=1;order[#order+1]='resume';return true end,
 cleanup_pending=function()return hover_pending end,needs_input_capture=function()return captured and rate==0 end}
local api=Core.new(nil,function()end);api.photo_standalone=true;api.is_open=function()return false end;api.close=function()return true end
api.create_photo_view=function()return {draw=function(value)commands=value end,release=function()commands={}end}end
api.photo_resolution=function()return 1920,1080 end
api.camera_input={down=function(k)return keys[k]or false end,focused=function()return focused end,chat_active=function()return chat end,native_menu_active=function()return native_open end,
 acquire=function()assert(camera_lease,'Input acquired before exclusive camera ownership');assert(not captured);captured=true;acquire_count=acquire_count+1;return{}end,
 release=function()
  assert(rate>0 and not poses.active and not poses.pending and not hover_pending,'Gameplay input released before restoration')
  if fail_release then return false,'Cursor restoration pending'end
  captured=false;release_count=release_count+1;order[#order+1]='input';return true
 end,set_focus=function()return true end,
 sample=function()return {wheel=0,mouse_x=5,mouse_y=2,forward=true,dt=.016}end,
 menu_sample=function()return{x=0,y=0,click=false,dt=.016}end}
local screenshots={active=function()return screenshot_active end,request=function()snapshot_requests=snapshot_requests+1;screenshot_active=true;return true end,
 tick=function()screenshot_active=false;return true,'saved'end,cancel=function()screenshot_active=false end}
local effects={fov=.9,parameters={},release=function()effect_releases=effect_releases+1;return effect_ok,'Render cleanup pending'end}
local camera_compat={held=false};camera_compat.acquire=function()camera_acquires=camera_acquires+1;camera_lease=true;camera_compat.held=true;return true end
camera_compat.release=function()
  if not camera_lease then return true end
  assert(not captured and not poses.active and not poses.pending and rate>0 and effect_ok,'Camera ownership released before Photo cleanup')
  camera_releases=camera_releases+1;camera_lease=false;camera_compat.held=false;return true
 end
DBFMCM=api;DBF_PHOTO_STANDALONE_API=nil
local ctrl=Controller.new(photo,{},function()return true end,function()end,freeze,Options,effects,Menu,nil,nil,screenshots,nil,nil,nil,nil,nil,nil,nil,poses,camera_compat,cinema)
local function tick()ctrl.tick(.016)end
local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
tick();local h=api.mods.dbf_freecam.handle;local controls={}
for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do controls[control.id]=control end end
assert(controls.cinema_begin.disabled and cinema.state=='off')
press(80);photo.pos={2,3,4};photo.view={yaw=.3,pitch=.1};tick()
assert(photo.active and captured and rate==0 and cinema.state=='place'and not controls.cinema_begin.disabled and camera_lease and camera_acquires==1)
local effect_baseline=effect_releases
poses.active=true;owned_bone='fixed';hover_pending=true
assert(h.activate('cinema_begin'));tick();tick()
assert(pose_request and rate==0 and captured and ctrl.camera_owned()and not ctrl.cinema_performing(),'Deferred pose restoration must retain camera/time/input ownership')
poses.active=false;poses.pending=false;owned_bone='original';tick()
assert(rate==1 and captured and cinema.state=='place','Hover restoration must finish before input returns')
hover_pending=false;fail_release=true;tick();assert(captured and cinema.state=='place','Failed native input restoration must retain capture for retry')
fail_release=false;tick()
assert(cinema.state=='perform'and photo.active and not captured and ctrl.camera_owned()and rate==1 and owned_bone=='original')
assert(h.get('freeze_player')==false,'Pause checkbox must reflect resumed Cinema gameplay')
assert(camera_lease and camera_releases==0,'Releasing gameplay input released the Photo camera lease')
assert(effect_releases==effect_baseline,'Beginning gameplay must retain render effects and lens ownership')
assert(order[#order]=='input'and order[#order-1]=='resume')
local acquisition=acquire_count;local position={photo.pos[1],photo.pos[2],photo.pos[3]}
for i=1,30 do photo.pos={500,500,500};keys[87]=true;tick();assert(not captured and photo.pos[1]==position[1]and photo.input.dt==0)end
assert(acquire_count==acquisition and camera_acquires==1 and camera_lease,'Cinema gameplay branch reacquired capture or lost camera ownership')
local badge=false;for _,command in ipairs(commands)do if command.text=='CINEMA CAMERA'then badge=true end end;assert(badge,'Cinema status must be visible')
-- Expiration must survive a failed clock read or a clock moving backward.
-- Use a separate UI clock so this cannot advance the recorded path timeline.
local hint_time=100;local hint_clock_failure=false
api.camera_input.now=function()if hint_clock_failure then error('UI clock unavailable')end;return hint_time end
tick();hint_time=104;tick();assert(#commands==0,'The Cinema hint must expire after three real seconds')
hint_clock_failure=true;tick();assert(#commands==0,'An expired Cinema hint reappeared when its real clock failed')
hint_clock_failure=false;hint_time=0/0;tick();assert(#commands==0,'An invalid real clock resurrected the expired Cinema hint')
hint_time=99;tick();assert(#commands==0,'A backward real clock resurrected the expired Cinema hint')
hint_time=108;tick();assert(#commands==0,'Clock recovery must retain an expired Cinema hint')
keys[87]=false;assert(h.set('hide_hud',false));assert(h.set('grid',2))
keys[19]=true;tick();assert(#commands==0 and photo.options.hide_hud and photo.options.grid==1,'Cinema indicator, HUD and guides leaked into capture')
keys[19]=false;tick();assert(snapshot_requests==1 and not captured and camera_lease,'Screenshot shortcut must work without an input lease')
assert(photo.options.hide_hud==false and photo.options.grid==2,'Screenshot policy did not restore the saved scene options')
-- Native menu readers retain the shot and Photo camera lease without taking gameplay input.
native_open=true;local input_before,lease_before=acquire_count,camera_acquires;tick();press(19);press(80)
assert(cinema.state=='perform'and photo.active and not captured and acquire_count==input_before and camera_acquires==lease_before and camera_lease and snapshot_requests==1,'Native-menu input ownership must not recapture Photo or release the static camera lease')
assert(not ctrl.reposition_camera(),'Direct reposition must refuse while the native menu owns input')
photo.pos={500,500,500};assert(cinema.hold()and photo.pos[1]==position[1],'The rendered Cinema shot must hold position behind native menus')
native_open=false;tick();assert(cinema.state=='perform'and not captured and acquire_count==input_before,'Closing native menus must not automatically reacquire Photo input in perform mode')
-- Escape passes through; native menu cursor blocks only Photo shortcuts.
context.gameplay_input=false;press(27);press(19);press(80)
assert(cinema.state=='perform'and photo.active and not captured and snapshot_requests==1,'Native menu must retain static camera without recapturing gameplay')
chat=true;context.gameplay_input=true;press(80);assert(not captured and cinema.state=='perform');chat=false
focused=false;tick();assert(not captured and photo.active);focused=true
assert(h.set('lock_camera',true));press(80);assert(h.get('lock_camera')==false and captured and cinema.state=='place'and photo.pos[1]==position[1]and rate==0 and h.get('freeze_player'),'Normal Photo shortcut must restore placement at the held pose and refreeze a previously frozen scene')
tick();assert(h.activate('cinema_begin'));tick();assert(cinema.state=='perform'and not captured)
badge=false;for _,command in ipairs(commands)do if command.text=='CINEMA CAMERA'then badge=true end end
assert(badge,'A new action shot must reset its own Cinema hint after the previous shot expired')
effect_ok=false;context.player='respawned';tick()
assert(not photo.active and cinema.state=='off'and camera_lease and ctrl.camera_owned()and camera_releases==0,'Failed Cinema render cleanup released the Photo camera lease')
effect_ok=true;tick();assert(not camera_lease and camera_releases==1,'Photo camera ownership did not release after successful Cinema cleanup retry')
-- Exercise the registered Director controls through real Core callbacks. New
-- point storage is runtime-only; editing one selected segment must not modify
-- another segment when synchronizing the duration/transition fields.
assert(controls.path_play.disabled and controls.path_point.disabled)
press(80);photo.pos={0,0,0};photo.view={yaw=math.rad(179),pitch=0};effects.fov=.8;tick()
assert(photo.active and captured and not controls.path_add.disabled and controls.path_play.disabled)
assert(h.activate('path_add'));tick()
assert(cinema.path_snapshot().count==1 and h.get('path_point')==1 and not controls.path_duration.disabled and controls.path_play.disabled)
assert(h.set('path_duration',2)and h.set('path_transition',2));tick()
photo.pos={10,0,0};photo.view={yaw=math.rad(-179),pitch=0};effects.fov=1.2
assert(h.activate('path_add'));tick()
assert(h.get('path_point')==2 and not controls.path_play.disabled)
assert(h.set('path_duration',4)and h.set('path_transition',1));tick()
photo.pos={20,0,0};effects.fov=1.4;assert(h.activate('path_add'));tick()
assert(h.set('path_point',1)and h.get('path_duration')==2 and h.get('path_transition')==2)
local list=cinema.path_points();assert(#list==3 and list[1].duration==2 and list[1].transition=='cut'and list[2].duration==4 and list[2].transition=='smooth','Selecting a point recursively overwrote another recorded segment')
assert(h.set('freeze_player',true));tick();tick();assert(rate==0 and captured)
local path_lease_count=camera_acquires;local path_input_count=acquire_count;local released_before=release_count
poses.active=true;owned_bone='fixed';hover_pending=true
assert(h.activate('path_play'));tick();tick()
assert(pose_request and captured and rate==0 and cinema.state=='place'and not cinema.path_playing,'Path playback bypassed the fixed-pose/zero-time restoration handoff')
poses.active=false;poses.pending=false;owned_bone='original';tick()
assert(captured and rate==1 and not cinema.path_playing,'Path playback started before the hover guard restored')
hover_pending=false;tick()
assert(cinema.path_playing and cinema.state=='perform'and not captured and rate==1 and photo.pos[1]==0)
assert(camera_lease and camera_acquires==path_lease_count and camera_releases==1 and release_count==released_before+1,'Path playback changed exclusive camera ownership instead of releasing only avatar input')
now=101.9;tick();assert(photo.pos[1]==0 and photo.options.fov==math.deg(.8),'A cut must hold the outgoing position and lens while avatar controls remain free')
now=102;tick();assert(photo.pos[1]==10 and math.abs(photo.options.fov-math.deg(1.2))<1e-8)
now=104;tick();local moving_position=photo.pos[1]
assert(moving_position>10 and moving_position<20 and math.abs(photo.options.fov-math.deg(1.3))<1e-8 and cinema.path_snapshot().index==2,'Real wall time must advance the next smooth camera segment and its FOV')
assert(not captured and acquire_count==path_input_count and camera_acquires==path_lease_count)
press(80)
assert(cinema.state=='place'and not cinema.path_playing and captured and photo.pos[1]==moving_position and acquire_count==path_input_count+1 and camera_acquires==path_lease_count and rate==0 and h.get('freeze_player'),'The Photo Mode key must stop a moving path, recapture placement and restore Freeze without reacquiring the camera lease')
now=120;tick();assert(photo.pos[1]==moving_position,'Stopped playback advanced after returning to placement')
assert(h.activate('path_remove'));tick();assert(cinema.path_snapshot().count==2)
assert(h.activate('path_clear'));tick()
assert(cinema.path_snapshot().count==0 and controls.path_point.disabled and controls.path_play.disabled and controls.path_remove.disabled,'Clearing the runtime path must refresh its usable controls')
assert(ctrl.stop()and not camera_lease and not captured and rate==1,'Ending the edited path session must restore gameplay/camera/input ownership')
-- Returning from a shot begun with live action must not invent a Freeze policy.
assert(h.set('freeze_player',false));press(80);photo.pos={7,8,9};photo.view={yaw=.1,pitch=.2};tick()
assert(rate==1 and h.activate('cinema_begin'));tick();assert(cinema.state=='perform'and not captured and rate==1)
press(80);assert(cinema.state=='place'and captured and rate==1 and not h.get('freeze_player'),'An unfrozen action shot must return to unfrozen placement')
assert(ctrl.stop()and not camera_lease and not captured and rate==1)
assert(ctrl.close());DBFMCM=nil
print('Cinema Director lifecycle: paused pose/hover restoration, cursor retry, static gameplay, exclusive camera ownership, uncaptured screenshots, native-menu/chat/focus handoffs, reposition and respawn cleanup passed')
print('Director camera paths: real registered point/segment controls, selected-field synchronization, paused restoration, avatar handoff, cut/curve/FOV playback, Photo-key stop/refreeze, unfrozen placement and complete cleanup passed')

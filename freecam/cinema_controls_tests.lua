local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Options=dofile(root..'photo_options.lua')
local Cinema=dofile(root..'cinema_camera.lua');local Menu=dofile(root..'photo_menu.lua')
local photo={};local context={world='mission',epoch=1,player='local:1',gameplay_input=true}
local cinema=Cinema.new(photo,function()return context end)
local keys={};local native_open=false;local captured=false;local acquire_count,release_count=0,0;local focused=true;local chat=false
local rate=1;local hover_pending=false;local fail_release=false;local effect_releases=0;local snapshot_requests=0;local screenshot_active=false
local camera_lease=false;local camera_acquires,camera_releases=0,0;local effect_ok=true
local commands={};local owned_bone='original';local order={};local pose_request=false
local poses={active=false,pending=false,status='fixture'}
function poses.refresh()return false,'fixture',{}end
function poses.release()if poses.active then poses.pending=true;pose_request=true end;return true end
local freeze={start=function(v)rate=v or 0;return true end,hold=function()return true end,
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
  assert(not captured and not poses.active and not poses.pending and rate>0 and effect_ok,'ActionCam resumed before Photo cleanup')
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
assert(camera_lease and camera_releases==0,'Releasing gameplay input returned camera ownership to ActionCam')
assert(effect_releases==effect_baseline,'Beginning gameplay must retain render effects and lens ownership')
assert(order[#order]=='input'and order[#order-1]=='resume')
local acquisition=acquire_count;local position={photo.pos[1],photo.pos[2],photo.pos[3]}
for i=1,30 do photo.pos={500,500,500};keys[87]=true;tick();assert(not captured and photo.pos[1]==position[1]and photo.input.dt==0)end
assert(acquire_count==acquisition and camera_acquires==1 and camera_lease,'Cinema gameplay branch reacquired capture or lost camera ownership')
local badge=false;for _,command in ipairs(commands)do if command.text=='CINEMA CAMERA'then badge=true end end;assert(badge,'Cinema status must be visible')
keys[87]=false;assert(h.set('hide_hud',false));assert(h.set('grid',2))
keys[19]=true;tick();assert(#commands==0 and photo.options.hide_hud and photo.options.grid==1,'Cinema indicator, HUD and guides leaked into capture')
keys[19]=false;tick();assert(snapshot_requests==1 and not captured and camera_lease,'Screenshot shortcut must work without an input lease')
assert(photo.options.hide_hud==false and photo.options.grid==2,'Screenshot policy did not restore the saved scene options')
-- Native menu readers retain the shot and ActionCam camera lease without taking gameplay input.
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
assert(h.set('lock_camera',true));press(80);assert(h.get('lock_camera')==false and captured and cinema.state=='place'and photo.pos[1]==position[1]and rate==1,'Normal Photo shortcut must restore placement at the held pose')
tick();assert(h.activate('cinema_begin'));tick();assert(cinema.state=='perform'and not captured)
effect_ok=false;context.player='respawned';tick()
assert(not photo.active and cinema.state=='off'and camera_lease and ctrl.camera_owned()and camera_releases==0,'Failed Cinema render cleanup returned camera to ActionCam')
effect_ok=true;tick();assert(not camera_lease and camera_releases==1,'ActionCam ownership did not restore after successful Cinema cleanup retry')
assert(ctrl.close());DBFMCM=nil
print('Cinema Director lifecycle: paused pose/hover restoration, cursor retry, static gameplay, exclusive camera ownership, uncaptured screenshots, native-menu/chat/focus handoffs, reposition and respawn cleanup passed')

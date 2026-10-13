local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile(root..'vendor/core.lua');local Controller=dofile(root..'controller.lua')
local Options=dofile(root..'photo_options.lua');local Menu=dofile(root..'photo_menu.lua')
local Poses=dofile(root..'subject_poses.lua')
local phase='render';local keys={};local rate=1;local state=0;local graph=true;local draws=0;local events={};local release_count=0
local unit={};local U={alive=function(u)assert(u==unit);return true end,
 has_animation_state_machine=function(u)assert(u==unit);return graph end,
 animation_get_state=function(u)assert(u==unit and graph);local values={};for i=1,31 do values[i]=0 end;values[9]=state;return unpack(values)end,
 has_animation_event=function(u,event)assert(u==unit and graph and type(event)=='string');return true end,
 animation_event=function(...)
  assert(phase=='update','Controller/menu dispatched a native animation event')
  assert(select('#',...)==2);local u,event=...;assert(u==unit and graph);events[#events+1]=event
 end}
local poses=Poses.new({Unit=U},{frame=function()return{local_owner=true,identity='local:1',root_handle=unit}end},function()return rate==0 end)
local release=poses.release;poses.release=function()release_count=release_count+1;return release()end
local freeze={rate=function()return rate end,start=function(value)rate=value or 0;return true end,release=function()rate=1;return true end,hold=function()return true end}
local api=Core.new(nil,function()end);api.is_open=function()return false end;api.close=function()return true end
api.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()return{}end,release=function()return true end,
 set_focus=function()return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,
 menu_sample=function()return{x=0,y=0,click=false,dt=.016}end}
api.photo_resolution=function()return 1920,1080 end
api.create_photo_view=function()return{draw=function()draws=draws+1 end,release=function()end}end
DBFMCM=api
local photo={active=false};local controller=Controller.new(photo,{},function()return true end,function()end,freeze,Options,nil,Menu,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,poses)
local function tick()phase='render';controller.tick(.1)end
local function update()phase='update';local ok,why=poses.flush(.016);phase='render';return ok,why end
local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
tick();local handle=api.mods.dbf_freecam.handle;local controls={}
for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do controls[control.id]=control end end
assert(controls.subject_pose.disabled and controls.subject_pose_play.disabled and controls.subject_pose_stop.disabled,'Pose controls enabled before a local session')
assert(#controls.subject_pose.choices==3 and controls.subject_pose.choices[1]=='Salute'and controls.subject_pose.choices[2]=='Wave'and controls.subject_pose.choices[3]=='Taunt')
assert(table.concat(Options.subject_poses,',')=='salute,wave,taunt','UI catalog differs from verified events')
press(80);assert(photo.active and rate==0);tick()
assert(not controls.subject_pose.disabled and controls.subject_pose_play.disabled and controls.subject_pose_status.label:find('Pause entire action',1,true))
assert(not controller._pose_action(false)and not poses.pending and#events==0,'Paused Play bypassed controller guard')
assert(handle.set('freeze_player',false));tick();assert(rate==1 and not controls.subject_pose_play.disabled)
assert(handle.set('subject_pose',2));tick();assert(handle.activate('subject_pose_play')and poses.pending and#events==0,'Play callback must only queue')
tick();assert(#events==0 and poses.pending and draws>0,'Menu/render tick consumed a native event')
assert(update()and events[1]=='action_wave_01');state=199;assert(update());tick()
assert(not controls.subject_pose_stop.disabled and handle.activate('subject_pose_stop')and poses.pending and#events==1,'Stop callback must only queue')
assert(update()and events[2]=='emote_wave_done');state=0;assert(update());tick()
assert(handle.set('subject_pose',1));tick();assert(handle.activate('subject_pose_play'));assert(update());state=178;assert(update());tick()
-- A temporary graph-read failure must disable Play but retain owned Stop.
graph=false;for i=1,6 do tick()end
assert(controls.subject_pose_play.disabled and not controls.subject_pose_stop.disabled,'Read loss hid owned cleanup')
graph=true;for i=1,6 do tick()end
local before=#events;local releases=release_count
assert(controller.stop()and not photo.active and poses.pending and release_count==releases+1 and#events==before,'Photo exit dispatched instead of queueing cleanup')
assert(not controller.close(),'Controller closed while pose cleanup still owned')
assert(update()and events[#events]=='action_salute_exit');state=177;assert(update());state=0;assert(update())
assert(controller.close()and not poses.active and not poses.pending);DBFMCM=nil
print('Subject pose controls: real Core/controller/menu, verified catalog, paused Play gate, queue-only callbacks, render isolation, read-loss cleanup and Photo exit release passed')

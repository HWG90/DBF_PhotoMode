local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile(root..'vendor/core.lua');local Controller=dofile(root..'controller.lua')
local Options=dofile(root..'photo_options.lua');local Menu=dofile(root..'photo_menu.lua')
-- The sampled-pose service contract is mocked here; native sample/restore
-- correctness belongs to its backend fixtures. These checks exercise real UI
-- registration and controller ownership across queued updates and retries.
local phase='render';local keys={};local rate=1;local available=true;local draws=0
local bone='original';local writes=0;local release_count=0;local input_releases=0;local fail_restore=false
local photo={active=false};local queued;local poses={active=false,pending=false,status='Pause entire action to apply a pose'}
function poses.refresh()
 local ready=available and photo.active and rate==0
 return ready,poses.status,{salute=ready,wave=ready,taunt=ready}
end
function poses.queue(id)assert(photo.active and rate==0 and available);queued=id;poses.pending=true;return true end
function poses.release()
 release_count=release_count+1
 if poses.active then queued='reset';poses.pending=true;poses.status='Restoring original pose'
 else queued=nil;poses.pending=false end
 return true
end
poses.queue_stop=poses.release
function poses.flush()
 assert(phase=='update','Pose mutation escaped the owning update')
 if queued=='reset'then
  if fail_restore then return false,'Restore reader unavailable'end
  bone='original';writes=writes+1;poses.active=false;poses.pending=false;queued=nil;poses.status='Subject poses ready'
 elseif queued then
  bone=queued;writes=writes+1;poses.active=true;poses.pending=false;queued=nil;poses.status='Fixed pose held'
 end
 return true
end
local freeze={rate=function()return rate end,start=function(value)rate=value or 0;return true end,
 release=function()assert(not poses.active and not poses.pending,'Resumed simulation before pose restoration');rate=1;return true end,hold=function()return true end}
local api=Core.new(nil,function()end);api.is_open=function()return false end;api.close=function()return true end
api.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()return{}end,
 release=function()assert(not poses.active and not poses.pending,'Released input before pose restoration');input_releases=input_releases+1;return true end,
 set_focus=function()return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,
 menu_sample=function()return{x=0,y=0,click=false,dt=.016}end}
api.photo_resolution=function()return 1920,1080 end
api.create_photo_view=function()return{draw=function()draws=draws+1 end,release=function()end}end
DBFMCM=api
local controller=Controller.new(photo,{},function()return true end,function()end,freeze,Options,nil,Menu,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,poses)
local function tick()phase='render';controller.tick(.1)end
local function update()phase='update';local ok,why=poses.flush();phase='render';return ok,why end
local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
tick();local handle=api.mods.dbf_freecam.handle;local controls={}
for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do controls[control.id]=control end end
assert(controls.subject_pose.disabled and controls.subject_pose_play.disabled and controls.subject_pose_stop.disabled,'Pose controls enabled before Photo Mode')
assert(controls.subject_pose_play.label=='Apply pose'and controls.subject_pose_stop.label=='Reset pose','Emote playback labels remain')
assert(table.concat(Options.subject_poses,',')=='salute,wave,taunt')
press(80);assert(photo.active and rate==0);tick()
assert(not controls.subject_pose.disabled and not controls.subject_pose_play.disabled,'Paused pose application was blocked')
assert(handle.set('subject_pose',2)and poses.pending and writes==0,'Choosing a pose must queue application automatically')
tick();assert(writes==0 and poses.pending and draws>0,'Render consumed a pose mutation')
assert(update()and bone=='wave'and rate==0);tick()
assert(handle.activate('subject_pose_stop')and poses.pending and bone=='wave');assert(update()and bone=='original'and rate==0)
assert(handle.activate('subject_pose_play')and poses.pending);assert(update()and bone=='wave');tick()
available=false;tick();assert(controls.subject_pose_play.disabled and not controls.subject_pose_stop.disabled,'Read loss hid owned cleanup')
available=true;tick();local before=writes;local before_release=input_releases;local before_requests=release_count
assert(not controller.stop()and controller.pose_cleanup_pending()and photo.active and rate==0 and input_releases==before_release)
assert(poses.pending and release_count==before_requests+1 and writes==before,'Exit wrote bones or failed to queue restoration')
tick();tick();assert(release_count==before_requests+1 and writes==before and rate==0,'Waiting render retried native work or resumed the world')
fail_restore=true;assert(not update());tick()
assert(controller.pose_cleanup_pending()and photo.active and rate==0 and input_releases==before_release,'Failed cleanup released camera/time/input ownership')
assert(not controller.close()and api.mods.dbf_freecam,'Shutdown unregistered during pose cleanup')
fail_restore=false;assert(update()and bone=='original');tick()
assert(not controller.pose_cleanup_pending()and not photo.active and rate==1 and input_releases==before_release+1,'Acknowledged cleanup did not finish deferred exit')
-- Changing intent then exiting before the update cancels the queued Apply.
press(80);assert(photo.active and rate==0);tick();before=writes
assert(handle.set('subject_pose',3)and poses.pending);assert(controller.stop()and not photo.active and rate==1)
assert(update()and writes==before and bone=='original','Canceled pending Apply ran after exit')
-- Turning pause off and requesting slow motion use the same restoration gate.
press(80);assert(photo.active and rate==0);tick()
assert(handle.activate('subject_pose_play'));assert(update()and bone=='taunt');tick()
before_release=input_releases;before_requests=release_count
assert(handle.set('freeze_player',false)and rate==0 and poses.pending and controller.pose_cleanup_pending(),'Pause setting resumed before restoration')
tick();assert(controls.subject_pose_play.disabled and release_count==before_requests+1 and input_releases==before_release)
fail_restore=true;assert(not update());tick();assert(rate==0 and photo.active and controller.pose_cleanup_pending(),'Pause setting bypassed failed cleanup')
fail_restore=false;assert(update()and bone=='original');tick()
assert(rate==1 and photo.active and not controller.pose_cleanup_pending()and input_releases==before_release,'Pause off did not resume after restoration')
assert(controller.stop());assert(handle.set('freeze_player',true));press(80);assert(photo.active and rate==0);tick()
assert(handle.activate('subject_pose_play'));assert(update()and bone=='taunt');tick()
press(220);assert(rate==0 and not poses.pending and controller.slowmo_active,'Selecting slow motion bypassed Freeze or restored the held pose')
assert(controller._toggle_freeze_action()and rate==0 and poses.pending and controller.pose_cleanup_pending(),'Unfreeze resumed slow motion before restoration')
assert(update()and bone=='original');tick();assert(rate==.2 and photo.active and not controller.pose_cleanup_pending(),'Slow motion did not resume after restoration')
assert(controller.close());DBFMCM=nil
-- Catalog expansion retains stored indices and builds ordinary Core choices.
local function catalog(size)
 local entries={{id='salute',label='Salute'},{id='wave',label='Wave'},{id='taunt',label='Taunt'}}
 for index=4,size do entries[index]={id='emote_'..index,label='Emote '..index}end
 return entries
end
for _,size in ipairs({30,80})do
 local entries=catalog(size);assert(Options.set_subject_poses(entries));entries[size].label='Changed source'
 assert(#Options.subject_poses==size and table.concat(Options.subject_poses,',',1,3)=='salute,wave,taunt','Original pose indices moved')
 assert(Options.subject_pose_labels[size]=='Emote '..size,'Menu retained mutable source catalog entries')
 local choice
 for _,page in ipairs(Options.pages(function()end,function()end))do for _,control in ipairs(page.controls)do if control.id=='subject_pose'then choice=control end end end
 assert(choice.choices==Options.subject_pose_labels and#choice.choices==size,'Pose page still uses a fixed catalog')
 choice.disabled=false;local selected
 choice.on_change=function(value)selected=Options.subject_poses[value]end
 local large=Core.new(nil,function()end);local menu=large.register({id='pose_catalog',name='Poses',pages={{id='subject',name='Subject',controls={choice}}}})
 assert(menu.set('subject_pose',size)and selected=='emote_'..size,'Core could not select an expanded catalog entry')
end
local old_ids,old_labels=Options.subject_poses,Options.subject_pose_labels
local function rejects(entries)
 assert(not Options.set_subject_poses(entries),'Malformed pose catalog accepted')
 assert(Options.subject_poses==old_ids and Options.subject_pose_labels==old_labels,'Rejected catalog partially replaced menu mappings')
end
rejects(nil);rejects({});rejects(catalog(257))
local malformed=catalog(4);malformed[2]=nil;rejects(malformed)
malformed=catalog(4);malformed[4].id='wave';rejects(malformed)
malformed=catalog(4);malformed[4].id='not an id';rejects(malformed)
malformed=catalog(4);malformed[4].label='Wave';rejects(malformed)
malformed=catalog(4);malformed[4].label='\n';rejects(malformed)
malformed=catalog(4);malformed[4].label=string.rep('x',97);rejects(malformed)
malformed=catalog(4);malformed[1],malformed[2]=malformed[2],malformed[1];rejects(malformed)
malformed=catalog(4);malformed.extra={};rejects(malformed)
assert(Options.set_subject_poses(catalog(3))and#Options.subject_pose_labels==3)
print('Paused pose controls: real Core/controller/menu, queued Apply, paused availability, update-only mutation, retry ownership, deferred exit/pause-off/slow-motion release and pending-Apply cancellation passed')
print('Pose catalog: stable original indices, 30/80-entry Core menus, copied labels, bounded unique IDs/labels and atomic rejection passed')

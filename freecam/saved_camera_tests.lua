local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'saved_camera.lua');local options=dofile(root..'photo_options.lua');local controller=dofile(root..'controller.lua')
local photo={active=true,pos={10,0,2},view={yaw=1.2,pitch=.3},options={roll=25,fov=50}}
local world,epoch,player,point='mission',1,'diver',{0,0,2};local available=true
local function context()if available then return world,epoch,player,point end end
local saved=factory.new(photo,context,function()end)
assert(saved.save(60));photo.pos[1]=20;photo.view.yaw=3
local values={};local handle={set=function(k,v)values[k]=v;return true end}
photo.active=false;photo.pos=nil;photo.view=nil;assert(saved.hold(60))
assert(saved.restore(60,handle));assert(photo.pos[1]==10 and photo.view.yaw==1.2 and values.roll==25 and values.fov==50)
photo.pos[1]=99;assert(saved.restore(60,handle));assert(photo.pos[1]==10,'Restores must copy the immutable saved shot')
point={70,0,2};assert(saved.hold(60),'Boundary remains valid')
point={70.01,0,2};assert(not saved.hold(60));point={0,0,2};assert(not saved.restore(60,handle),'Leaving the radius must clear permanently')
photo.active=true;photo.pos={10,0,2};assert(saved.save(60));available=false;assert(not saved.hold(60));available=true;assert(saved.restore(60,handle),'Temporary camera discovery loss keeps the saved shot')
epoch=2;assert(not saved.hold(60));epoch=1;assert(not saved.restore(60,handle))
assert(saved.save(60));player='replacement';assert(not saved.hold(60),'Player replacement must invalidate the shot')
assert(saved.save(60));world='ship';assert(not saved.hold(60),'World replacement must invalidate the shot')
assert(not saved.save(5),'Reject a save already beyond the radius')
photo.active=false;assert(not saved.save(60),'Inactive save must not capture gameplay camera')

-- Lens settings can refuse or throw independently. A partial restore must be
-- reported through the return value, log and existing menu status, while the
-- immutable bookmark remains available for a later successful retry.
for _,failure in ipairs({{roll='refuse'},{fov='refuse'},{roll='throw'},{fov='throw'},{roll='throw',fov='refuse'}})do
 local camera={active=true,pos={1,2,3},view={yaw=.7,pitch=.2},options={roll=25,fov=50}}
 local messages,attempts={},{};local settings={roll=-10,fov=90,unrelated=123}
 local bookmark=factory.new(camera,function()return'mission',1,'local',{0,0,0}end,function(message)messages[#messages+1]=message end)
 local faults=failure
 local setter={set=function(id,value)
  attempts[#attempts+1]=id
  if faults[id]=='throw'then error(id..' setter unavailable')end
  if faults[id]=='refuse'then return false,id..' setting refused'end
  settings[id]=value;return true
 end}
 assert(bookmark.save(60));camera.pos={20,20,20};camera.view={yaw=2,pitch=0}
 local ok,why=bookmark.restore(60,setter)
 assert(ok==false and type(why)=='string'and why:find('restore incomplete',1,true),'A failed lens setting was reported as a successful camera restore')
 assert(#attempts==2 and attempts[1]=='roll'and attempts[2]=='fov','One refused/throwing lens setter prevented the independent setting from being attempted')
 for _,id in ipairs({'roll','fov'})do
  if failure[id]then
   assert(why:find(id,1,true)and bookmark.status(60):find(id,1,true),'Incomplete restore omitted the refused lens field')
  else assert(settings[id]==camera.options[id],'The accepted lens setting did not restore')end
 end
 assert(camera.pos[1]==1 and camera.view.yaw==.7 and settings.unrelated==123,'Lens failure changed unrelated settings or lost the restored camera position')
 assert(#messages==2 and messages[2]:find('restore incomplete',1,true)and not messages[2]:find('position restored',1,true),'A partial lens restore emitted the normal success log')
 assert(bookmark.hold(60)and bookmark.status(60):find('restore incomplete',1,true),'Lens failure discarded the valid bookmark or its visible retry status')
 camera.pos[1]=999;faults={}
 assert(bookmark.restore(60,setter)and camera.pos[1]==1 and settings.roll==25 and settings.fov==50,'A partial restore could not retry the original saved shot')
 assert(not bookmark.status(60):find('restore incomplete',1,true)and messages[#messages]=='Saved camera position restored','Successful retry did not clear its partial-restore report')
 faults={roll='refuse'};assert(not bookmark.restore(60,setter));assert(bookmark.save(60))
 assert(not bookmark.status(60):find('restore incomplete',1,true),'A new save retained an older restore failure')
 assert(not bookmark.restore(60,setter));bookmark.clear('manual')
 assert(bookmark.status(60)=='Saved camera cleared: manual','Clearing a bookmark retained an obsolete lens failure')
end
-- Real settings/input lifecycle: saved shot survives normal exit; Return to player bypasses it.
local core=dofile('src/core.lua').new(nil,function()end);local keys={};local owned=false
local input={down=function(k)return keys[k]or false end,focused=function()return true end,
 acquire=function()owned=true;return {}end,release=function()owned=false;return true end,
 sample=function()return {wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
core.camera_input=input;core.is_open=function()return false end;DBFMCM=core
local c=controller.new(photo,{},function()return true end,function()end,nil,options,nil,nil,nil,saved)
c.tick(.016);keys[80]=true;c.tick(.016);keys[80]=false;c.tick(.016)
assert(photo.active and owned);photo.pos={10,0,2};photo.view={yaw=.8,pitch=.2};photo.options={roll=20,fov=55}
local h=core.mods.dbf_freecam.handle;local status_control
for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id=='saved_camera_status'then status_control=control end end end
assert(status_control and not core.mods.dbf_freecam.controls.saved_camera_status,'Status must live on the registered page, outside the stored/action index')
assert(h.activate('save_camera'));c.tick(.016)
assert(status_control.label=='Saved camera: 10.0 / 60 m','A fresh save must update the live registered status')
point={15,0,2};c.tick(.016);assert(status_control.label=='Saved camera: 5.0 / 60 m','Player movement must refresh the displayed distance')
assert(h.set('saved_camera_radius',40));c.tick(.016);assert(status_control.label=='Saved camera: 5.0 / 40 m','Changing retention radius must refresh the displayed limit')
point={0,0,2};assert(h.set('saved_camera_radius',60));c.tick(.016)
assert(c.stop());assert(not photo.active and not owned);assert(saved.hold(60))
keys[80]=true;c.tick(.016);keys[80]=false;c.tick(.016)
assert(photo.active and photo.pos[1]==10 and photo.view.yaw==.8 and h.get('roll')==20 and h.get('fov')==55)
assert(h.activate('recenter'));c.tick(.11);assert(photo.active and not photo.pos,'Return to player must not restore the bookmark')
assert(status_control.label=='Saved camera cleared: returned to player','Clearing a bookmark must refresh its status')
assert(h.activate('recenter'));assert(c.stop());c.tick(.11);assert(not photo.active,'An explicit stop must cancel pending recenter activation')
assert(c.close());DBFMCM=nil
print('Saved camera: immutable shot, radius boundary/expiry, scene/player changes, target reacquisition, re-entry and Return to player passed')
print('Saved camera partial restore: refused/throwing roll and FOV, independent attempts, accurate return/log/status, preserved immutable bookmark and successful retry passed')

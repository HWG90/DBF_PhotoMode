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

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Options=dofile(root..'photo_options.lua')
local Subject=dofile(root..'subject.lua');local Director=dofile(root..'director.lua')
local photo={active=false};local player={local_owner=true,identity='local:1',position={0,0,1},yaw=0}
local part={identity='own:1',mesh_count=1};local mask=255;local writes=0;local available=true
local subject=Subject.new({resolve=function()if available then return{local_owner=true,identity='local:1',groups={hide_player={part},hide_armour={part},hide_weapons={}}}end;return nil,'Player unavailable'end,
 valid=function()return available end,read=function()return mask end,write=function(_,_,v)mask=v and 255 or 0;writes=writes+1 end})
local disk;local director=Director.new(photo,function()return player end,nil,nil,{load=function()return{}end,save=function(rows)disk=Director.encode(rows);return true end})
local api=Core.new(nil,function()end);local keys={};local leased=false
api.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()leased=true;return{}end,
 release=function()leased=false;return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
api.is_open=function()return false end;api.close=function()return true end;DBFMCM=api
local controller=Controller.new(photo,{},function()return true end,function()end,nil,Options,nil,nil,nil,nil,nil,nil,nil,subject,director)
controller.tick(.016);local handle=api.mods.dbf_freecam.handle;local controls,pages={},{}
for _,page in ipairs(api.mods.dbf_freecam.pages)do pages[page.id]=true;for _,control in ipairs(page.controls)do controls[control.id]=control end end
assert(pages.director and pages.subject and controls.hide_player.disabled and controls.director_save.disabled)
keys[80]=true;controller.tick(.016);keys[80]=false;controller.tick(.016);assert(photo.active and leased)
assert(subject.flush(.016));photo.pos={2,-3,4};photo.view={yaw=.2,pitch=.1};photo.options=Options.read(handle)
controller.tick(.1);assert(not controls.hide_player.disabled and controls.hide_weapons.disabled,'Only groups with verified live renderer parts may be enabled')
assert(handle.set('hide_player',true)and subject.pending and writes==0);assert(subject.flush(.016)and mask==0)
controller.tick(.1);assert(not controls.director_save.disabled);assert(handle.activate('director_save')and disk)
controller.tick(.1);assert(controls.director_slot.choices[1]:find('saved',1,true)and not controls.director_recall.disabled)
player.position={20,0,1};player.yaw=math.pi/2;photo.pos={100,100,100};assert(handle.activate('director_recall'))
assert(math.abs(photo.pos[1]-23)<1e-9 and math.abs(photo.pos[2]-2)<1e-9 and photo.pos[3]==4)
assert(controller.stop()and subject.pending and mask==0,'Closing Photo Mode must queue an owned restore')
assert(subject.flush(.016)and mask==255 and writes==2)
assert(controller.close());DBFMCM=nil
print('Director/Subject controls: real Core pages, verified group gates, queued setters, saved slot labels, relative recall and exit restoration passed')

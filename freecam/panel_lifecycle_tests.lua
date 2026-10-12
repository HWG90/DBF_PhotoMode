local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua');local options=dofile(root..'photo_options.lua');local panel=dofile(root..'photo_menu.lua');local controller=dofile(root..'controller.lua')
local keys={};local focused=true;local main_menu=false;local mode=0;local rate=1;local commands
local input={down=function(k)return keys[k]or false end,focused=function()return focused end,pause_allowed=function()return true end,
 acquire=function()mode=3;return {}end,release=function()mode=0;return true end,set_focus=function(v)mode=v and 1 or 3;return true end,
 sample=function()assert(mode==3);return {wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()assert(mode==1);return {click=false,wheel=0}end}
local api=core.new(nil,function()end);api.camera_input=input;api.is_open=function()return main_menu end;api.close=function()main_menu=false;return true end
api.photo_resolution=function()return 1920,1080 end;api.create_photo_view=function()return {draw=function(c)commands=c end,release=function()commands={}end}end
DBFMCM=api
local freeze={start=function(v)rate=v or 0;return true end,release=function()rate=1;return true end,hold=function()return true end,rate=function()return rate end}
local effects={parameters={},shader_status='Shader unavailable: fixture material',release=function()return true end}
local photo={};local c=controller.new(photo,{},function()return true end,function()end,freeze,options,effects,panel)
c.tick(.016);keys[80]=true;c.tick(.016);assert(photo.active and rate==0 and mode==3 and #commands>0);keys[80]=false
local status;for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id=='shader_status'then status=control end end end
assert(status and status.label==effects.shader_status,'Runtime status must update registered text controls, outside MCM stored-value index')
effects.shader_status='';c.tick(.016);assert(status.label=='')
keys[9]=true;c.tick(.016);assert(mode==1 and photo.input.dt==0 and rate==0);keys[9]=false
keys[13]=true;c.tick(.016);keys[13]=false;c.tick(.016);keys[80]=true;c.tick(.016);assert(photo.active and rate==0,'Numeric editing owns the photo-toggle shortcut');keys[80]=false
keys[27]=true;c.tick(.016);keys[27]=false;c.tick(.016);assert(mode==1 and photo.active,'Escape cancels numeric entry before leaving menu')
keys[72]=true;c.tick(.016);assert(mode==3 and #commands==0 and rate==0);keys[72]=false
keys[9]=true;c.tick(.016);assert(mode==1 and #commands>0);keys[9]=false
focused=false;c.tick(.016);assert(mode==0 and photo.active and rate==0)
focused=true;c.tick(.016);assert(mode==1 and photo.active and rate==0)
main_menu=true;c.tick(.016);assert(mode==0 and photo.active and rate==0)
main_menu=false;c.tick(.016);assert(mode==1)
assert(api.mods.dbf_freecam.handle.get('slowmo_key')==220)
keys[84]=true;c.tick(.016);assert(rate==0,'T must no longer be the default slow-motion key');keys[84]=false;c.tick(.016)
keys[220]=true;c.tick(.016);assert(rate==.2);keys[220]=false;c.tick(.016);keys[220]=true;c.tick(.016);assert(rate==0);keys[220]=false
keys[80]=true;c.tick(.016);assert(not photo.active and mode==0 and rate==1);assert(c.close());DBFMCM=nil
local runtime=dofile(root..'photo_runtime.lua')
local sr={Gui={resolution=function()return 1920,1080 end},World={create_screen_gui=function()return {}end,destroy_gui=function()end}}
local fx=runtime.new(sr,{new=function()return {apply=function()return .9 end,release=function()return true end}end}, {layout=function()return {}end,shaders={''}},
 {new=function()return {apply=function()error('Renderer flag readback mismatch')end,release=function()return true end}end},function()end)
assert(fx.apply(1,2,3,{0,1,0},{1,0,0},options.defaults,.016)==false);assert(fx.lens_status:find('camera and pause retained',1,true));assert(fx.release())
print('Photo panel: menu/camera focus, hide/show, focus-loss pause, MCM handoff, slow motion, exit restore and effect-error containment passed')

-- Hide the whole bindings/Controls page only when MCM owns configuration.
for _,standalone in ipairs({false,true})do
 local a=core.new(nil,function()end);a.camera_input=input;a.is_open=function()return false end;a.photo_standalone=standalone;a.create_photo_view=function()return {}end
 local visible;local factory={new=function()return {bind=function(_,pages)visible=pages end,close=function()end,editing_key=function()return false end}end}
 if standalone then DBFMCM=nil;DBF_PHOTO_STANDALONE_API=a else DBFMCM=a;DBF_PHOTO_STANDALONE_API=nil end
 keys={};local ctrl=controller.new({}, {},function()return true end,function()end,nil,options,nil,factory);ctrl.tick(.016)
 assert(visible and (#visible==(standalone and 5 or 4)));assert((visible[1].id=='camera')==standalone)
 assert(a.mods.dbf_freecam.name=='Photo Mode');assert(ctrl.close());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
end
print('Photo pages: Controls absent with MCM, retained standalone; internal name Photo Mode passed')

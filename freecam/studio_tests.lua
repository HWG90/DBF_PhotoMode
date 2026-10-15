local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local options=dofile(root..'photo_options.lua');local lens=dofile(root..'lens.lua');local composition=dofile(root..'composition.lua');local postfx=dofile(root..'postfx.lua')
local function near(a,b)assert(math.abs(a-b)<1e-6)end
local up=lens.up({0,1,0},{1,0,0},90);near(up[1],1);near(up[3],0)
local narrow=lens.depth(5,1.2,math.rad(50));local wide=lens.depth(5,16,math.rad(50));assert(narrow.near>wide.near and narrow.region<wide.region)
for index=2,6 do
 local mm=options.focal_presets[index];local degrees=assert(options.preset_fov(index));near(options.focal_length(math.rad(degrees)),mm)
end
assert(options.preset_fov(1)==nil and options.focal_length(0)==nil and options.focal_length(0/0)==nil and options.focal_length(math.pi)==nil)
local fov=.9;local rotation
local sr={Vector3=function(...)return {...}end,Quaternion={look=function(f,u)return {f=f,u=u}end},Camera={vertical_fov=function()return fov end,set_vertical_fov=function(_,v)fov=v end,set_local_rotation=function(_,_,v)rotation=v end}}
local camera=lens.new(sr);local o={fov=60,roll=90};camera.apply(1,2,{0,1,0},{1,0,0},o);near(fov,math.pi/3);near(rotation.u[1],1);assert(camera.release());near(fov,.9)
camera.apply(1,2,{0,1,0},{1,0,0},o);fov=1.1;assert(camera.release());near(fov,1.1)
local defaults={};for k,v in pairs(options.defaults)do defaults[k]=v end
assert(#composition.layout(1920,1080,defaults,0)==0)
for frame=1,5 do for logo=1,4 do defaults.frame=frame;defaults.logo=logo;defaults.logo_size=250;defaults.logo_x=0;defaults.logo_y=0;defaults.grid=4
 for _,r in ipairs(composition.layout(3840,2160,defaults,0))do assert(r.x>=0 and r.y>=0 and r.x+r.w<=3840.001 and r.y+r.h<=2160.001)end
end end
defaults.clean_view=true;defaults.frame=1;assert(#composition.layout(1920,1080,defaults,0)==0)
local fx=postfx.new({},lens);assert(not fx.apply(1,defaults,.9))
local values={dof=0,exposure=2};DBF_PHOTO_RENDER_PROFILE={world=1,parameters={dof=true,exposure=true},read=function(k)return values[k]end,write=function(k,v)values[k]=v end}
defaults.dof=true;defaults.exposure=-1;assert(fx.apply(1,defaults,.9));assert(values.dof==1 and values.exposure==-1);assert(fx.release());assert(values.dof==0 and values.exposure==2);DBF_PHOTO_RENDER_PROFILE=nil
-- Real MCM contract: editing holds the scene pause but hands keyboard/mouse to MCM.
local api=dofile('src/core.lua').new(nil,function()end);local held,menu,owned=false,false,false;local focused=true;local pauses,releases=0,0
local roll_key;local provider={down=function(k)return (k==80 and held)or k==roll_key end,focused=function()return focused end,acquire=function()owned=true;return {}end,release=function()owned=false;return true end,
 sample=function()return {dt=.016,wheel=0,forward=true,mouse_x=2,mouse_y=3}end,pause_allowed=function()return true end}
api.camera_input=provider;api.is_open=function()return menu end;api.close=function()menu=false;return true end;DBFMCM=api
local freeze={start=function()pauses=pauses+1;return true end,release=function()releases=releases+1;return true end,hold=function()return true end}
local photo={};local effect_state={fov=math.rad(60),release=function()return true end};local controller=dofile(root..'controller.lua').new(photo,{},function()return true end,function()end,freeze,options,effect_state)
controller.tick(.016);local h=api.mods.dbf_freecam.handle
for index=2,6 do
 assert(h.set('focal_preset',index));assert(math.abs(h.get('fov')-options.preset_fov(index))<.00051,'Preset FOV was quantized too coarsely')
 assert(math.abs(options.focal_length(math.rad(h.get('fov')))-options.focal_presets[index])<.01,'Preset does not use the same optical authority')
end
assert(h.set('fov',52.345));assert(h.get('focal_preset')==1,'Manual FOV did not invalidate preset metadata')
assert(h.set('roll_preset',3));near(h.get('roll'),90);assert(h.get('roll_preset')==3)
assert(h.set('roll',17));assert(h.get('roll_preset')==1,'Manual tilt did not invalidate shortcut metadata')
assert(h.set('roll_preset',4));near(h.get('roll'),-90);assert(h.set('roll_preset',2));near(h.get('roll'),0)
assert(h.set('fov',0));held=true;controller.tick(.016);assert(photo.active and pauses==1 and owned)
local focal_status;for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id=='focal_length_status'then focal_status=control end end end
assert(focal_status and focal_status.label=='Focal length: 20.8 mm (gameplay)','Gameplay FOV must use actual lens radians rather than zero metadata')
effect_state.fov=math.rad(40);controller.tick(.016);assert(focal_status.label=='Focal length: 33.0 mm (gameplay)','Focal length display did not follow actual lens FOV')
assert(h.set('focal_preset',3));effect_state.fov=math.rad(h.get('fov'));controller.tick(.016);assert(focal_status.label=='Focal length: 35.0 mm'and h.get('focal_preset')==3)
menu=true;local previous=releases;controller.tick(.016);assert(photo.active and not owned and releases==previous)
assert(h.set('roll',45));controller.tick(.016);assert(photo.options.roll==45)
assert(api.mods.dbf_freecam.controls.aperture.disabled);assert(not pcall(h.set,'aperture',2))
menu=false;controller.tick(.016);assert(photo.active and owned and pauses==1)
focused=false;local before=releases;controller.tick(.016);assert(photo.active and not owned and releases==before)
focused=true;controller.tick(.016);assert(photo.active and owned and pauses==1)
assert(api.mods.dbf_freecam.controls.roll_left_key.default==81 and api.mods.dbf_freecam.controls.roll_right_key.default==69)
roll_key=69;controller.tick(.016);near(photo.options.roll,45+.016*45)
roll_key=81;controller.tick(.016);near(photo.options.roll,45)
roll_key=nil;controller.tick(.016);near(h.get('roll'),45)
assert(h.set('lock_camera',true));controller.tick(.016);assert(not photo.input.forward and photo.input.mouse_x==0)
local bridge=assert(DBF_PHOTO_EDITOR_INPUT)
assert(bridge.acquire('Epic LUT') and photo.active and not owned)
controller.tick(.016);assert(photo.active and not owned and not photo.input.forward)
assert(not bridge.acquire('Another editor'))
assert(not bridge.release('Another editor'));controller.tick(.016);assert(not owned)
assert(bridge.release('Epic LUT'));controller.tick(.016);assert(photo.active and owned)
assert(controller.close());assert(not owned and not photo.active);DBFMCM=nil
print('Photo studio: lens math/restore, composition bounds, grading ownership, MCM edit/pause lifecycle and locked movement passed')
print('Lens metadata: 24/35/50/85/135 mm presets map the sole FOV setting, actual-radian gameplay readout, manual invalidation and 0/+90/-90 tilt shortcuts passed')

local catalog=dofile(root..'composition.lua');local pages=options.pages(function()end,function()end,catalog)
assert(#catalog.shader_names==41 and #catalog.filter_names==22)
for _,page in ipairs(pages)do for _,c in ipairs(page.controls)do
 if c.type=='choice'then assert(c.presentation=='dropdown')end
 if c.id=='shader_scale'then assert(c.min==.005 and c.max==16)end
 if c.id=='logo_size'then assert(c.min==.5)end
end end
for filter=1,22 do defaults.filter=filter;defaults.grain=100;defaults.grain_size=8;defaults.vignette_width=40;defaults.vignette=100
 for _,r in ipairs(catalog.layout(1920,1080,defaults,0))do assert(r.x>=0 and r.y>=0 and r.x+r.w<=1920.001 and r.y+r.h<=1080.001)end
end
print('Creative options: 22 filters, 40 shader overlays, dropdown metadata, fine scales and all filter bounds passed')

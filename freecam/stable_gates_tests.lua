-- Public release safety gates, exercised against the real MCM registration.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local options=dofile(root..'photo_options.lua');local catalog=dofile(root..'composition.lua')
local deferred={scene_effect=true,scene_steps=true}
for key in pairs(deferred)do assert(options.defaults[key]==nil,'Deferred scene setting leaked into defaults: '..key)end
local candidate={scene_shader=true,scene_strength=true,scene_depth_range=true,fog_distance=true,fog_density=true}
for _,page in ipairs(options.pages(function()end,function()end,catalog))do
 if page.id=='color'then assert(page.controls[1].id=='color_status','Color notice must precede disabled controls')end
 if page.id=='effects'then assert(page.controls[1].id=='scene_status','Effects notice must precede disabled controls')end
end
assert(options.defaults.scene_shader==1 and options.defaults.exposure==0 and options.defaults.contrast==100 and options.defaults.saturation==100)
for _,page in ipairs(options.pages(function()end,function()end,catalog))do
 for _,control in ipairs(page.controls)do
  assert(not deferred[control.id],'Deferred scene control leaked into menu: '..control.id)
  if candidate[control.id]then assert(control.disabled,'Scene candidate must default to disabled without a verified runtime')end
 end
end

local native_caps={dof=true,bloom=true,focus_distance=true,aperture=true,exposure=true,saturation=true,contrast=true}
local calls,owned,mode=0,false,3;local keys={};local editing=false;local panel
local input={down=function(key)return keys[key]or false end,focused=function()return true end,
 acquire=function()owned=true;return {}end,release=function()owned=false;return true end,
 sample=function()return {forward=true,wheel=0,mouse_x=4,mouse_y=5,dt=.016}end,
 menu_sample=function()return {click=false,wheel=0,dt=.016}end,set_focus=function(menu)mode=menu and 1 or 3;return true end}
local api=dofile('src/core.lua').new(nil,function()end)
api.camera_input=input;api.is_open=function()return false end;api.close=function()return true end
api.create_photo_view=function()return {}end;api.photo_resolution=function()return 1920,1080 end
DBFMCM=api;DBF_PHOTO_RENDER_PROFILE={parameters=native_caps}
local effects={parameters=native_caps,release=function()return true end}
local menu={new=function()
 panel={bind=function()end,close=function()end,dismiss=function()return true end,draw=function()end,tick=function()end,editing_key=function()return editing end}
 return panel
end}
local photo={};local controller=dofile(root..'controller.lua').new(photo,{},function()return true end,function()end,nil,options,effects,menu,catalog)
local function tick()controller.tick(.016)end
local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
tick();press(80);assert(photo.active and owned)
local mod=api.mods.dbf_freecam;local handle=mod.handle
assert(handle.get('lock_camera_key')==76,'L must be the default camera lock shortcut')
assert(mod.controls.focus_distance.disabled and mod.controls.aperture.disabled,'Synthetic capability reports must not enable deferred lens controls')
assert(not pcall(handle.set,'focus_distance',2)and not pcall(handle.set,'aperture',1.2),'Disabled lens edits must be rejected by the authoritative handle')
assert(not handle.get('lock_camera'));keys[76]=true;tick();assert(handle.get('lock_camera'))
assert(not photo.input.forward and photo.input.mouse_x==0 and photo.input.mouse_y==0,'Locked camera must reject movement and look')
tick();tick();assert(handle.get('lock_camera'),'Holding L must not toggle repeatedly')
keys[76]=false;tick();press(76);assert(not handle.get('lock_camera')and photo.input.forward)
-- Both key capture and numeric/text editing report through this editing guard.
editing=true;keys[76]=true;tick();assert(not handle.get('lock_camera'),'Typing/capture must not operate the camera lock shortcut')
editing=false;tick();assert(not handle.get('lock_camera'),'Finishing input while L is held must not create a new toggle edge')
keys[76]=false;tick();panel.bound_key=76;keys[76]=true;tick();assert(not handle.get('lock_camera'),'A newly captured L binding must suppress its held key')
keys[76]=false;tick();assert(panel.bound_key==nil);press(76);assert(handle.get('lock_camera'))
-- Only an explicitly enabled, ready candidate runtime may lift numeric gates.
DBF_PHOTO_RENDER_PROFILE={parameters={}}
effects.custom_dof_candidate=true;effects.custom_dof_ready=true;tick()
assert(not mod.controls.focus_distance.disabled and not mod.controls.aperture.disabled and not mod.controls.dof.disabled,'Ready candidate controls must follow runtime capabilities instead of the native profile')
handle.set('focus_distance',2);handle.set('aperture',1.2)
effects.custom_dof_ready=false;tick()
assert(mod.controls.focus_distance.disabled and mod.controls.aperture.disabled,'Losing candidate readiness must immediately close numeric gates')
assert(not pcall(handle.set,'focus_distance',3),'Unavailable candidate edits must be rejected')
assert(controller.close()and not owned);DBFMCM=nil;DBF_PHOTO_RENDER_PROFILE=nil

-- Even if an installed experimental asset remains available, release runtime
-- must not query or draw it, nor advertise its numeric lens capabilities.
local queries={};local gui_owner;local custom_seen
local sr={Application={main_world=function()return 10 end,worlds=function()return {10,20}end,
 can_get=function(_,name)queries[#queries+1]=name;return true end},
 World={create_screen_gui=function(owner)gui_owner=owner;return {}end,destroy_gui=function()end},Gui={resolution=function()return 1920,1080 end}}
local runtime=dofile(root..'photo_runtime.lua').new(sr,{new=function()return {apply=function()return .9 end,release=function()return true end}end},
 {shaders={''},layout=function()return {}end},{new=function()return {parameters=native_caps,
 apply=function(_,_,_,_,_,custom)custom_seen=custom;return true,'native flags' end,release=function()return true end}end},function()end)
local values={};for key,value in pairs(options.defaults)do values[key]=value end;values.scene_effect=8;values.dof=true
assert(runtime.apply(1,2,10,{0,1,0},{1,0,0},values,0))
assert(gui_owner==20,'Photo overlays must follow the proven UI world routing')
assert(custom_seen==false and runtime.custom_dof_ready==false and not runtime.parameters.focus_distance and not runtime.parameters.aperture)
assert(native_caps.focus_distance and native_caps.aperture,'The release capability mask must not mutate an external profile')
for _,name in ipairs(queries)do assert(not name:find('mods/dbf_photo/',1,true),'Experimental material queried: '..name)end
assert(runtime.release())
print('Stable release gates: no scene settings/assets, capability masks, L edge/lock behavior, input editing suppression and UI world routing passed')

-- This game emits DXGI_UNKNOWN for one verified HDR RGB10 back-buffer format.
-- Normalize only our captured header, with exact native surface evidence.
local backend_factory=dofile(root..'screenshot_backend.lua')
local function integer(value)local chars={};for i=1,4 do chars[i]=string.char(value%256);value=math.floor(value/256)end;return table.concat(chars)end
local function dds()
 local header='DDS '..integer(124)..integer(0x1007)..integer(2)..integer(2)..integer(8)..string.rep('\0',56)
 header=header:sub(1,76)..integer(32)..integer(4)..'DX10'..string.rep('\0',40)
 return header..integer(0)..integer(3)..integer(0)..integer(1)..integer(0)..string.rep('\255',16)
end
local original_open=io.open;local files={};local writes=0;local proof={format=16,kind=4,width=2,height=2,mips=1,array=1}
io.open=function(path,mode)
 if not files[path]then return end
 local cursor=0
 return {close=function()end,seek=function(_,origin,offset)
  if origin=='end'then cursor=#files[path]else cursor=offset or 0 end;return cursor
 end,read=function(_,count)return files[path]:sub(cursor+1,cursor+count)end,
 write=function(_,data)assert(mode=='r+b');files[path]=files[path]:sub(1,cursor)..data..files[path]:sub(cursor+#data+1);cursor=cursor+#data;writes=writes+1 end}
end
local screenshot=assert(backend_factory.new({Application={save_render_target=function(target,path)assert(target=='back_buffer');files[path]=dds()end}},function()return true,proof end))
local success,result=screenshot.capture('C:/Shots/hdr.dds');assert(success and result.format==24 and writes==1 and files[result.path]:sub(129,132)==integer(24))
for _,change in ipairs({{key='format',value=15},{key='kind',value=2},{key='width',value=3},{key='mips',value=2},{key='array',value=2}})do
 local previous=proof[change.key];proof[change.key]=change.value
 assert(not screenshot.capture('C:/Shots/rejected-'..change.key..'.dds'),'Unknown HDR normalization accepted mismatched native evidence')
 proof[change.key]=previous;assert(writes==1,'Rejected HDR metadata must not modify the capture header')
end
io.open=original_open
print('HDR screenshot release gate: verified RGB10 DXGI normalization, exact dimensions/kind/mips/array guards, rejected surfaces unchanged passed')

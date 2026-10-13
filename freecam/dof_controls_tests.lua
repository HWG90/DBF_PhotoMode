-- Exercise the exact review's private core, controller, menu and real overlay.
local root=assert(rawget(_G,'DBF_PHOTO_TEST_ROOT'))
local core=dofile(root..'vendor/core.lua');local options=dofile(root..'photo_options.lua')
local menu=dofile(root..'photo_menu.lua');local runtime_factory=dofile(root..'photo_runtime.lua')
local lens_math=dofile(root..'lens.lua');local postfx=dofile(root..'postfx.lua')
local overlay_factory=dofile(root..'dof_overlay.lua')
local guard_factory=dofile(root..'shader_template_guard.lua')
local keys,commands,uniforms={},nil,{};local primitives=0
local native={dof=1,bloom=0}
DBF_PHOTO_RENDER_PROFILE={world=10,parameters={dof=true,bloom=true},read=function(key)return native[key]end,write=function(key,value)native[key]=value end}
local function primitive()primitives=primitives+1;return primitives end
local function near(a,b)return math.abs(a-b)<1e-7 end
local sr={Vector2=function(...)return {...}end,Vector3=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end,
 Application={main_world=function()return 10 end,worlds=function()return {10,20}end,can_get=function()return true end},
 World={create_screen_gui=function(owner)assert(owner==20);return {}end,destroy_gui=function()end},
 Gui={resolution=function()return 1920,1080 end,material=function()return {}end,triangle=primitive,destroy_triangle=function()end},
 Material={set_scalar=function()end,set_vector4=function(_,key,value)uniforms[key]=value end,set_resource=function(_,name,value)assert(name=='diffuse_map'and value=='depth-target')end}}
local lens={depth=lens_math.depth,new=function()return {apply=function()return .9 end,release=function()return true end}end}
local composition={shaders={''},layout=function()return {}end}
local runtime=runtime_factory.new(sr,lens,composition,postfx,function()end,nil,nil,{new=function()
 return overlay_factory.new(sr,{available=function()return true end,get=function()return 'depth-target'end},true,guard_factory.new(sr,function()return true end))
end})
local api=core.new(nil,function()end);api.is_open=function()return false end;api.close=function()return true end
api.camera_input={down=function(key)return keys[key]or false end,focused=function()return true end,acquire=function()return {}end,release=function()return true end,
 sample=function()return {wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,set_focus=function()return true end,menu_sample=function()return {click=false,wheel=0,dt=.016}end}
api.photo_resolution=function()return 1920,1080 end
api.create_photo_view=function()return {draw=function(value)commands=value end,release=function()end}end
DBFMCM=api
local photo={};local controller=dofile(root..'controller.lua').new(photo,{},function()return true end,function()end,nil,options,runtime,menu)
controller.tick(.016);keys[80]=true;controller.tick(.016);keys[80]=false
assert(photo.active)
keys[9]=true;controller.tick(.016);keys[9]=false;controller.tick(.016)
keys[69]=true;controller.tick(.016);keys[69]=false;controller.tick(.016)
local function frame()
 controller.tick(.016)
 assert(runtime.apply(1,2,10,{0,1,0},{1,0,0},photo.options,.016))
 controller.tick(.016)
end
local handle=api.mods.dbf_freecam.handle
assert(handle.get('dof_mode')==1,'Native camera should be the default method')
handle.set('dof_mode',2);frame()
assert(handle.get('focus_distance')==5 and math.abs(handle.get('aperture')-5.6)<1e-7 and handle.get('dof')==false)
local controls=api.mods.dbf_freecam.controls
assert(controls.focus_distance.step==.01 and controls.focus_distance.fine_step==.001,'Focus must offer centimetre steps and millimetre fine adjustment')
for _,control in pairs(controls)do if control.type=='slider'then assert(control.commit_on_blur==true,'Photo numeric controls must opt into commit on leaving the field')end end
assert(not controls.focus_distance.disabled and not controls.aperture.disabled,'Registered off-state must allow lens edits')
local labels={};for _,command in ipairs(commands)do if command.control_id then labels[command.control_id]=true end end
assert(labels.dof and labels.focus_distance and labels.aperture,'Lens page must render DoF, focus and aperture together without scrolling')
handle.set('dof',true);handle.set('focus_distance',2);handle.set('aperture',1.2);frame()
assert(uniforms.scissor_rect[1]==2 and uniforms.scissor_rect[2]==1.2 and uniforms.scissor_rect[3]==.9 and native.dof==0)
assert(photo.options.focus_distance==2 and photo.options.aperture==1.2,'Settings read must supply actual stored values')
local before=primitives;handle.set('focus_distance',50);handle.set('aperture',22);frame()
assert(near(uniforms.scissor_rect[1],50)and near(uniforms.scissor_rect[2],22)and primitives>before,'Subsequent authoritative edits must update the shader draw')
handle.set('focus_distance',1.405);frame()
assert(near(handle.get('focus_distance'),1.405)and near(uniforms.scissor_rect[1],1.405),'Typed millimetre precision must survive authoritative normalization and reach DoF uniforms')
handle.set('dof_quality',2);handle.set('bokeh_shape',2);frame()
assert(uniforms.atlas_scissor[3]==6 and uniforms.atlas_scissor[4]==1,'Stored quality and aperture shape must reach the shader material')
assert(not pcall(handle.set,'aperture',0),'Native core must reject invalid f-stop values')
handle.set('dof',false);frame();assert(runtime.custom_dof_ready and native.dof==0)
assert(controller.close()and native.dof==1 and native.bloom==0,'Stopping must restore original native flags')
DBFMCM=nil;DBF_PHOTO_RENDER_PROFILE=nil
print('Candidate controls: actual private core settings -> controller options -> DoF uniforms; focus/aperture visible together; off-state editing, bounds and native restore passed')

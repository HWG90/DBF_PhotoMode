local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile(root..'vendor/core.lua');local Options=dofile(root..'photo_options.lua');local Menu=dofile(root..'photo_menu.lua');Menu.gizmo_factory=dofile(root..'photo_light_gizmos.lua')
local keys={};local mouse={x=960,y=810};local mode=0;local commands={};local queued={};local epoch=1;local samples=0;local capture=false
local provider={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()mode=3;return{}end,release=function()mode=0;return true end,set_focus=function(value)mode=value and 1 or 3;return true end,
 sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()return{x=mouse.x,y=mouse.y,click=keys[1]or false,dt=.016}end}
local values={enabled=true,kind='spot',intensity=3,color='#FFDDAA',range=8,cone=45,right=0,forward=1,up=0,follow_camera=false}
local rows={{id=17,index=1,position={0,10,5},selected=true,values=values}}
local saved;local presets={status='Five lighting slots',list=function()return{'Setup 1','Setup 2','Setup 3','Setup 4','Setup 5'}end,occupied=function()return saved~=nil end,
 save=function(slot,setup,target,frame)saved={slot=slot,setup=setup,target=target,frame=frame};return true end,
 recall=function(slot,target,frame)assert(saved and slot==saved.slot);return{version=1,definitions={},target=target,frame=frame}end,clear=function()saved=nil;return true end}
local lights={presets=presets,available=true,status='Ready',pending=false,revision=1,scene_context=function()return'world',epoch end,
 ready=function()return true,nil,{spot=true,range=true}end,count=function()return#rows end,selected=function()return values,1,#rows end,list=function()return rows end,
 queue=function(action,value)queued[#queued+1]={action=action,value=value};return true end,export_setup=function()return{version=1,definitions={{values=values}},selected=1}end,release=function()return true end}
local api=Core.new(nil,function()end);api.is_open=function()return false end;api.close=function()return true end;api.camera_input=provider;api.photo_resolution=function()return 1920,1080 end
api.create_photo_view=function()return{draw=function(c)commands=c end,release=function()commands={}end}end;DBFMCM=api
local effects={fov=math.pi/2,native_dof_candidate=true,native_dof_ready=true,parameters={focus_distance=true,aperture=true,dof=true},release=function()return true end}
local photo={};local sampler={sample=function()samples=samples+1;return 4 end,release=function()return true end}
local screenshots={active=function()return capture end,cancel=function()capture=false end,tick=function()return true end}
local controller=dofile(root..'controller.lua').new(photo,{},function()return true end,function()end,nil,Options,effects,Menu,nil,nil,screenshots,sampler,lights)
local function tick()controller.tick(.016)end
local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
tick();press(80);photo.light_context={world='world',position={0,0,0},right={1,0,0},forward={0,1,0},up={0,0,1}};tick()
local handle=api.mods.dbf_freecam.handle;local controls=api.mods.dbf_freecam.controls
assert(not controls.light_aim.disabled and not controls.light_apply_preset.disabled and not controls.light_setup_save.disabled)
assert(handle.activate('light_apply_preset'));local q=queued[#queued];assert(q.action=='preset'and q.value.name=='key_fill_rim'and q.value.target[2]==5)
handle.set('light_preset',3);handle.activate('light_apply_preset');assert(queued[#queued].value.name=='dramatic_side')
controller._remember_light_subject(.25,.25,4);handle.activate('light_aim');q=queued[#queued];assert(q.action=='aim'and math.abs(q.value.target[1]+32/9)<1e-7 and math.abs(q.value.target[3]-2)<1e-7,'Picked subject must retain its world-space target')
handle.activate('light_setup_save');assert(saved and saved.slot==1 and saved.frame.scene_epoch==1);tick();assert(not controls.light_setup_recall.disabled)
handle.activate('light_setup_recall');assert(queued[#queued].action=='import_setup');handle.activate('light_setup_clear');assert(not saved)
epoch=2;handle.activate('light_aim');q=queued[#queued];assert(q.value.target[1]==0 and q.value.target[2]==5,'Scene change reused the previous subject coordinates')
controller._remember_light_subject(.25,.25,4);handle.set('focus_distance',7);handle.activate('light_aim');assert(queued[#queued].value.target[1]==0 and queued[#queued].value.target[2]==7,'Manual focus did not reset subject target')
handle.set('focus_mode',2);tick();local before=#queued;press(1);press(1);assert(samples==0 and#queued>before,'Marker clicks reached autofocus instead of selection')
keys[1]=true;tick();mouse.x=1068;tick();q=queued[#queued];assert(q.action=='move'and q.value.id==17 and math.abs(q.value.position[1]-2)<1e-7,'Controller did not queue marker drag');keys[1]=false;tick()
capture=true;tick();for _,c in ipairs(commands)do assert(c.ui_role~='light_marker','Screenshot captured a light marker')end;capture=false;tick()
assert(controller.stop());assert(not controller._light_gizmos.active());assert(controller.close());DBFMCM=nil
print('Light tools UI: subject presets, cached/fallback target, same-world epoch invalidation, manual focus reset, saved setup actions, queued gizmo-before-focus input and screenshot hiding passed')

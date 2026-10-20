"""Generate a reversible photo-render validation bridge; idle until commanded."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'freecam'))
from build import compile_lua
source=''
for variable,filename in (('depth_factory','depth_resource.lua'),('registration_factory','shader_template_guard.lua'),('overlay_factory','dof_overlay.lua'),('capture_factory','screenshot_backend.lua')):
 source+='local '+variable+'=(function()\n'+(ROOT/'freecam'/filename).read_text()+'\nend)()\n'
for variable,filename in (('active_profile_factory','camera_profile_active.lua'),('native_trial_factory','native_profile_trial.lua'),('native_environment_factory','native_environment_trial.lua')):
 source+='local '+variable+'=(function()\n'+(ROOT/'dist/dof-investigation-20261011'/filename).read_text()+'\nend)()\n'
source+=r'''
local sr=assert(rawget(_G,'stingray'));local depth=depth_factory.new(sr);local overlay=overlay_factory.new(sr,depth,true,registration_factory.new(sr))
local state;local mode='off';local last;local pending;local frames=0;local last_status;local backend;local reported_handle;local reported_camera;local reported_command;local native_owner;local current_context;local request_serial=0;local native_observation='not sampled'
local numeric_trial=native_trial_factory.new(active_profile_factory,sr);local native_pair;local restore_check
local environment_trial=native_trial_factory.new(native_environment_factory,sr,{environment_id=1048582,camera_id=1048597})
local exposure_trial=native_trial_factory.new(native_environment_factory,sr,{environment_id=1048582,camera_id=1048597,exposure_trial=true})
local root='C:/Users/david/OneDrive/Documents/GitHub/DBF_PhotoMode/dist/dof-investigation-20261011/'
local function status(value)
 if value==last_status then return end;last_status=value
 local f=assert(io.open(root..'DOF-VALIDATION-STATUS.txt','wb'));f:write(value);f:close()
end
local function up(f,key)
 if type(f)~='function'then return end
 for i=1,80 do local name,value=debug.getupvalue(f,i);if not name then return end;if name==key then return value,i end end
end
local function retire_custom(original)
 if native_owner then return end
 local f=original
 for _=1,10 do
  local object,index=up(f,'dof')
  if object and type(object)=='table'and type(object.release)=='function'then
   local ok,why=object.release();assert(ok,why)
   assert(debug.setupvalue(f,index,nil)=='dof','DoF ownership changed')
   native_owner={f=f,index=index,object=object,baseline_native=sr.Application.render_setting('dof_enabled')};return
  end
  f=up(f,'original')or up(f,'previous');if not f then break end
 end
 error('Owned custom DoF cell unavailable')
end
local function restore_custom()
 if not native_owner then return end
 local name,value=debug.getupvalue(native_owner.f,native_owner.index)
 assert(name=='dof'and value==nil,'Custom DoF cell changed owner')
 assert(debug.setupvalue(native_owner.f,native_owner.index,native_owner.object)=='dof')
 native_owner=nil
end
local function finish_pair(reason)
 local pair=native_pair;local expected=native_owner and native_owner.baseline_native
 local trial=pair and pair.kind=='exposure'and exposure_trial or(pair and pair.kind=='environment'and environment_trial or numeric_trial)
 local ok,why=trial.release();assert(ok,why)
 restore_custom();native_pair=nil;pending=nil;mode='off'
 if pair then
  local r=trial.restoration;local rows={'result '..tostring(reason),'kind '..tostring(pair.kind),'utc_epoch '..os.time(),'native_expected '..tostring(expected),
   'same_entity '..tostring(r and r.same_entity),'scene_dof_restored '..tostring(r and r.scene_dof_restored),'focus_restored '..tostring(r and r.focus_restored)}
  if r and r.exposure_restored~=nil then rows[#rows+1]='exposure_restored '..tostring(r.exposure_restored)end
  if r and r.read_error then rows[#rows+1]='restore_read_error '..r.read_error end
  if r and r.after then rows[#rows+1]='focal_distance_after '..tostring(r.after.values.focal_distance);rows[#rows+1]='scene_dof_after '..tostring(r.after.values.scene_dof)end
  if r and r.native_driver_restoration then
   rows[#rows+1]='all_environment_fields_restored '..tostring(r.native_driver_restoration.all_restored)
   for i,environment in ipairs(r.native_driver_restoration.environments or{})do
    rows[#rows+1]='environment.'..i..'.address '..environment.address
    for key,field in pairs(environment.fields)do rows[#rows+1]='environment.'..i..'.'..key..'.baseline '..tostring(field.baseline);rows[#rows+1]='environment.'..i..'.'..key..'.after '..tostring(field.after);rows[#rows+1]='environment.'..i..'.'..key..'.restored '..tostring(field.restored)end
   end
  end
  local f=assert(io.open(root..pair.stem..'_restore.txt','wb'));f:write(table.concat(rows,'\n'),'\n');f:close()
  restore_check={stem=pair.stem,expected=expected,frames=0,properties_ack=r and r.same_entity and r.scene_dof_restored and r.focus_restored};status('Native pair '..tostring(reason)..'; owned cleanup complete, waiting for native flag acknowledgement')
 end
end
local function camera_pose(cam,unit,scene,forward,right,options)
 local p=sr.Camera.world_position(cam)
 return {cam=cam,unit=unit,world=scene,position={sr.Vector3.x(p),sr.Vector3.y(p),sr.Vector3.z(p)},
  forward={forward[1],forward[2],forward[3]},right={right[1],right[2],right[3]},fov=sr.Camera.vertical_fov(cam),roll=options.roll or 0}
end
local function find()
 local f=rawget(_G,'render')
 for _=1,10 do
  local apply=up(f,'apply');local photo=up(apply,'PHOTO');local controller=up(up(f,'bindings_step'),'DBF_FREECAM')
  local effects=controller and up(controller.tick,'effects')
  if photo and effects then return photo,effects,controller end
  f=up(f,'previous')or up(f,'original')
 end
end
return {name='Photo DoF reversible validation',on_enable=function()
 local util=require('jit.util');local methods={}
 for name,method in pairs(sr.Renderer or{})do if type(method)=='function'then local ok,info=pcall(util.funcinfo,method);if ok then methods[#methods+1]='Renderer.'..name..' '..tostring(info.addr)end end end
 for _,namespace in ipairs({'IdString32','IdString64','World','Unit','Entity','Component','Material'})do
  local object=sr[namespace]
  if type(object)=='function'then local ok,info=pcall(util.funcinfo,object);if ok then methods[#methods+1]=namespace..' '..tostring(info.addr)end
  elseif type(object)=='table'then for name,method in pairs(object)do if type(method)=='function'then local ok,info=pcall(util.funcinfo,method);if ok then methods[#methods+1]=namespace..'.'..tostring(name)..' '..tostring(info.addr)end end end end
 end
 table.sort(methods);local sdk=assert(io.open(root..'RENDERER-SDK.txt','wb'));sdk:write(table.concat(methods,'\n'));sdk:close()
 local f=assert(io.open(root..'DOF-VALIDATION-COMMAND.txt','wb'));f:write('off');f:close();last='off'
 status('Idle; waiting for photo render context')
end,
on_update=function(ctx)
 if state and state.photo.active and current_context then
  local ran,ok,value=pcall(native_environment_factory.observe_native,sr,current_context,{environment_id=1048582,camera_id=1048597})
  native_observation=ran and ok==true and 'positive packet observed'or tostring(ran and value or ok)
 end
 local file=io.open(root..'DOF-VALIDATION-COMMAND.txt','rb');local command=file and file:read('*a');if file then file:close()end
 if command and command~=last then
  local requested,name=command:match('^(%w+)%s*([%w_]*)')
  if not(requested=='off'or requested=='inspect'or requested=='baseline'or requested=='rawdepth'or requested=='colorcheck'or requested=='depth'or requested=='near'or requested=='far'or requested=='narrow'or requested=='nativeoff'or requested=='nativeon'or requested=='nativepair'or requested=='nativeenvpair'or requested=='exposurepair'or requested=='shadernear'or requested=='shaderfar'or requested=='shaderclosed'or requested=='shaderstandard'or requested=='shaderhex'or requested=='usertest')then return end
  if native_pair then finish_pair('cancelled')end
  if(requested=='nativepair'or requested=='nativeenvpair')and name==''then status('Native pair refused: a unique capture stem is required');return end
  last=command
  request_serial=request_serial+1
  mode=requested;pending=name~=''and name or nil;frames=0
  local consumed=assert(io.open(root..'DOF-VALIDATION-COMMAND.txt','wb'));consumed:write('off');consumed:close();last='off'
  if mode=='nativepair'or mode=='nativeenvpair'or mode=='exposurepair'then native_pair={stem=pending,phase=1,frames=0,kind=mode=='exposurepair'and'exposure'or(mode=='nativeenvpair'and'environment'or'component')};pending=nil end
  if mode=='off'or mode=='baseline'or mode=='rawdepth'or mode=='nativeoff'or mode=='nativeon'or mode=='nativepair'or mode=='nativeenvpair'then local ok,why=overlay.release();assert(ok,why)end
 end
 if state and mode=='usertest'then
  mode='off';pending=nil
  assert(state.photo.active,'Test controls require active Photo Mode')
  local handle=assert(up(state.controller.tick,'handle'),'Photo controls unavailable')
  for _,entry in ipairs({{'dof',true},{'dof_mode',2},{'dof_quality',2},{'bokeh_shape',1},{'focus_distance',.54},{'aperture',2}})do
   local ok,why=handle.set(entry[1],entry[2]);assert(ok~=false,tostring(why))
  end
  status('User test controls enabled: Shader preview, 64 samples, focus0.540m, f/2')
 end
 if state and mode=='inspect'and pending then
  local name=pending;pending=nil;mode='off'
  local rows={'utc_epoch '..os.time(),'photo_active '..tostring(state.photo.active),'native_dof '..tostring(sr.Application.render_setting('dof_enabled'))}
  for key,value in pairs(state.photo.options or{})do if key=='dof'or key=='dof_mode'or key=='focus_distance'or key=='aperture'then rows[#rows+1]=key..' '..tostring(value)end end
  local file=assert(io.open(root..name..'.txt','wb'));file:write(table.concat(rows,'\n'));file:close()
  backend=backend or assert(capture_factory.new(sr));local ran,ok,why=pcall(backend.capture,root..name..'.dds')
  status(ran and ok and 'Game inspection captured: '..name or 'Game inspection refused: '..tostring(ran and why or ok))
 end
 if state then return end
 local photo,effects,controller=find();if not photo or not effects then status('Waiting for Photo Mode render context');return end
 local original,release=effects.apply,effects.release
 local function wrapper(cam,unit,scene,forward,right,options,dt)
  local captured,context=pcall(native_environment_factory.capture_context,sr,scene,cam,{camera_id=1048597})
  current_context=captured and context or nil
  if not captured then native_observation=tostring(context)end
  local native_trial=mode=='nativeoff'or mode=='nativeon'or mode=='nativepair'or mode=='nativeenvpair'or mode=='exposurepair'
  local shader_trial=mode=='shadernear'or mode=='shaderfar'or mode=='shaderclosed'or mode=='shaderstandard'or mode=='shaderhex'
  local render_options=options
  if native_trial then
   assert(photo.active,'Native DoF comparison requires active Photo Mode')
   retire_custom(original);render_options={};for key,value in pairs(options)do render_options[key]=value end
   render_options.dof=mode~='nativeoff'
   if mode=='exposurepair'then assert(options.dof_mode==1,'Exposure control requires native mode');render_options=options end
   if native_pair then
    local focus=native_pair.kind=='exposure'and(native_pair.phase==1 and .25 or 4)or(native_pair.kind=='environment'and(native_pair.phase==1 and .44 or 15)or(native_pair.phase==1 and 1.4 or 12))
    local trial=native_pair.kind=='exposure'and exposure_trial or(native_pair.kind=='environment'and environment_trial or numeric_trial)
    local ok,value=pcall(trial.apply,scene,unit,cam,focus)
    if not ok then finish_pair('refused: '..tostring(value));render_options=options;native_trial=false
    else native_pair.snapshot=value;native_pair.focus=focus end
   end
  else restore_custom()end
  if shader_trial then
   assert(photo.active,'Shader comparison requires active Photo Mode')
   render_options={};for key,value in pairs(options)do render_options[key]=value end
   render_options.dof=true;render_options.dof_mode=2;render_options.focus_distance=mode=='shaderfar'and 15 or .54
   render_options.aperture=mode=='shaderclosed'and 22 or 2;render_options.dof_quality=mode=='shaderstandard'and 1 or 2
   render_options.bokeh_shape=mode=='shaderhex'and 2 or 1
  end
  if mode=='colorcheck'then render_options={};for key,value in pairs(options)do render_options[key]=value end;render_options.dof=false end
  local result=original(cam,unit,scene,forward,right,render_options,dt)
  if restore_check then
   restore_check.frames=restore_check.frames+1
   local actual=sr.Application.render_setting('dof_enabled')
   if actual==restore_check.expected or restore_check.frames>=120 then
    local f=assert(io.open(root..restore_check.stem..'_restore.txt','ab'));f:write('native_getter_after '..tostring(actual),'\nnative_flag_acknowledged '..tostring(actual==restore_check.expected),'\n');f:close()
    status(actual==restore_check.expected and restore_check.properties_ack and 'Native pair complete; component values and native flag restored' or 'Native pair cleanup complete; inspect restoration readbacks for differences')
    restore_check=nil
   end
  end
  if reported_camera~=cam or reported_command~=request_serial then
   local ffi=require('ffi');local util=require('jit.util')
   local function address(value)local ok,result=pcall(function()return tonumber(ffi.cast('uintptr_t',value))end);return ok and result or tostring(value)end
   local rows={'utc_epoch '..os.time(),'cam '..tostring(address(cam)),'unit '..tostring(unit),'unit_address '..tostring(address(unit)),'world '..tostring(address(scene)),
    'fov_radians '..tostring(sr.Camera.vertical_fov(cam)),'photo_active '..tostring(photo.active),'focus '..tostring(options.focus_distance),'aperture '..tostring(options.aperture),
    'validation_mode '..mode,'options.dof '..tostring(options.dof),'options.dof_mode '..tostring(options.dof_mode),
    'effects.custom_dof_candidate '..tostring(effects.custom_dof_candidate),'effects.custom_dof_ready '..tostring(effects.custom_dof_ready),
    'effects.lens_status '..tostring(effects.lens_status),'custom_retired_by_validation '..tostring(native_owner~=nil)}
   rows[#rows+1]='native_environment_observation '..native_observation
   for _,name in ipairs({'render_setting','set_render_setting'})do rows[#rows+1]='Application.'..name..' '..tostring(util.funcinfo(sr.Application[name]).addr)end
   local render=original;local custom
   for _=1,10 do custom=up(render,'dof');if custom then break end;render=up(render,'original')or up(render,'previous');if not render then break end end
   local custom_bound=type(custom)=='table'and up(custom.apply,'bound')or nil
   rows[#rows+1]='custom_dof_object_present '..tostring(type(custom)=='table')
   rows[#rows+1]='custom_dof_gui '..tostring(address(type(custom)=='table'and up(custom.apply,'gui')or nil))
   rows[#rows+1]='custom_dof_material '..tostring(address(type(custom_bound)=='table'and custom_bound.handle or nil))
   local position=sr.Camera.world_position(cam)
   rows[#rows+1]=string.format('camera_world_position %.8f %.8f %.8f',sr.Vector3.x(position),sr.Vector3.y(position),sr.Vector3.z(position))
   for _,key in ipairs({'focal_distance','scene_dof','aperture'})do rows[#rows+1]='Camera.has_data.'..key..' '..tostring(sr.Camera.has_data(cam,key))end
   for _,key in ipairs({'hdr_enabled','dof_enabled','bloom_enabled'})do local ok,value=pcall(sr.Application.render_setting,key);rows[#rows+1]='render_setting.'..key..' '..tostring(ok)..' '..tostring(value)end
   for _,name in ipairs({'camera','unit_component','data_component','world_position','alive'})do local method=sr.Unit[name];if type(method)=='function'then rows[#rows+1]='Unit.'..name..' '..tostring(util.funcinfo(method).addr)end end
   for name,method in pairs(sr.Camera)do if type(method)=='function'then local ok,info=pcall(util.funcinfo,method);if ok then rows[#rows+1]='Camera.'..name..' '..tostring(info.addr)end end end
   for name,method in pairs(sr.ShadingEnvironment or{})do if type(method)=='function'then local ok,info=pcall(util.funcinfo,method);if ok then rows[#rows+1]='ShadingEnvironment.'..name..' '..tostring(info.addr)end end end
   for name,method in pairs(sr.Renderer or{})do if type(method)=='function'then local ok,info=pcall(util.funcinfo,method);if ok then rows[#rows+1]='Renderer.'..name..' '..tostring(info.addr)end end end
   if type(sr.Application.render_world)=='function'then local ok,info=pcall(util.funcinfo,sr.Application.render_world);if ok then rows[#rows+1]='Application.render_world '..tostring(info.addr)end end
   for name,method in pairs(sr.World or{})do if type(method)=='function'and(name:find('shading')or name:find('environment')or name:find('render'))then local ok,info=pcall(util.funcinfo,method);if ok then rows[#rows+1]='World.'..name..' '..tostring(info.addr)end end end
   table.sort(rows);local f=assert(io.open(root..'ACTIVE-PHOTO-CAMERA.txt','wb'));f:write(table.concat(rows,'\n'));f:close();reported_camera=cam;reported_command=request_serial
  end
  if mode~='off'and mode~='baseline'and mode~='rawdepth'and mode~='colorcheck'and not native_trial and not shader_trial then
   local fov=sr.Camera.vertical_fov(cam)
   local preview={dof=true,focus_distance=mode=='far'and 50 or 2,aperture=mode=='narrow'and 22 or 1.2,depth_calibration=mode=='depth',validation_marker=true}
   local ok,why=overlay.apply(preview,fov);status(ok and 'Overlay submitted: '..mode or 'Overlay refused: '..tostring(why))
   if not ok then pending=nil;mode='off';ctx.log('DoF validation refused: '..tostring(why))end
   local bound=up(overlay.apply,'bound')
   if bound and bound.handle~=reported_handle then
    local ffi=require('ffi');local address=tonumber(ffi.cast('uintptr_t',bound.handle))
    local gui=up(overlay.apply,'gui');local owner=up(overlay.apply,'world');local util=require('jit.util')
    local f=assert(io.open(root..'LIVE-MATERIAL-HANDLE.txt','wb'));f:write(string.format('material 0x%x\ndepth 0x%x\ngui 0x%x\nworld 0x%x\ncreate_screen_gui 0x%x\n',address,tonumber(ffi.cast('uintptr_t',bound.resource)),tonumber(ffi.cast('uintptr_t',gui)),tonumber(ffi.cast('uintptr_t',owner)),util.funcinfo(sr.World.create_screen_gui).addr));f:close();reported_handle=bound.handle
   end
  end
  if native_pair then
   local pair=native_pair;local pose=camera_pose(cam,unit,scene,forward,right,options)
   local selected=pair.snapshot and pair.snapshot.selection
   if not pair.selection then pair.selection={index=selected.index,entity=selected.entity,instance=pair.snapshot.instance}end
   if selected.index~=pair.selection.index or selected.entity~=pair.selection.entity or pair.snapshot.instance~=pair.selection.instance then
    finish_pair('aborted: active native component changed between captures')
   elseif not native_trial_factory.same_pose(pair.pose or pose,pose)then
    if pair.phase==2 then finish_pair('aborted: camera position/orientation/FOV changed between captures')
    else pair.pose=pose;pair.frames=0;status('Native pair waiting for a stable full camera pose')end
   elseif pair.kind~='exposure'and sr.Application.render_setting('dof_enabled')~=true then pair.frames=0;status('Native pair waiting for native DoF ON acknowledgement')
   else
    pair.pose=pair.pose or pose
    pair.frames=pair.frames+1
    local dwell=pair.kind=='environment'and 120 or 20
    if pair.frames>=dwell then
     local name=pair.stem..(pair.phase==1 and '_near' or '_far');local snapshot=pair.snapshot
     local rows={'mode nativepair','kind '..pair.kind,'requested_focal_distance '..pair.focus,'focal_distance_readback '..snapshot.values.focal_distance,
      'scene_dof '..snapshot.values.scene_dof,'native_dof '..tostring(sr.Application.render_setting('dof_enabled')),
      'profile_index '..snapshot.selection.index,'entity '..snapshot.selection.entity,'instance '..snapshot.instance,
      'renderer_handle '..snapshot.renderer_handle,'utc_epoch '..os.time(),'fov '..pose.fov,'roll '..pose.roll,
      string.format('position %.8f %.8f %.8f',unpack(pose.position)),string.format('forward %.8f %.8f %.8f',unpack(pose.forward)),string.format('right %.8f %.8f %.8f',unpack(pose.right))}
     for key,value in pairs(snapshot.values)do rows[#rows+1]='component.'..key..' '..tostring(value)end
     for i,environment in ipairs(snapshot.environments or{})do
      rows[#rows+1]='environment.'..i..'.address '..environment.address;rows[#rows+1]='environment.'..i..'.id '..environment.id
      for key,value in pairs(environment.values)do rows[#rows+1]='environment.'..i..'.'..key..' '..tostring(value)end
     end
     local f=assert(io.open(root..name..'.txt','wb'));f:write(table.concat(rows,'\n'),'\n');f:close()
     backend=backend or assert(capture_factory.new(sr));local ok,why=backend.capture(root..name..'.dds')
     if not ok then finish_pair('capture refused: '..tostring(why))
     elseif pair.phase==1 then pair.phase=2;pair.frames=0;status('Native focus 1.4 captured; checking 12 with the same full pose')
     else finish_pair('captured both focus values with the same full pose')end
    end
   end
  end
  if pending then
   local acknowledged=shader_trial and effects.custom_dof_ready and sr.Application.render_setting('dof_enabled')==false or not shader_trial and(not native_trial or sr.Application.render_setting('dof_enabled')==(mode=='nativeon'))
   if acknowledged then frames=frames+1 else frames=0;status('Waiting for native DoF flag: '..mode)end
   if frames>=20 then
    backend=backend or assert(capture_factory.new(sr))
    local name=pending;pending=nil;local capture_mode=mode;mode='off';local ok,why
    local ran,error_message=pcall(function()
    if native_trial or shader_trial then
     local ffi=require('ffi');local position=sr.Camera.world_position(cam)
     local rows={'mode '..capture_mode,'native_dof '..tostring(sr.Application.render_setting('dof_enabled')),'cam '..tostring(tonumber(ffi.cast('uintptr_t',cam))),
      string.format('position %.8f %.8f %.8f',sr.Vector3.x(position),sr.Vector3.y(position),sr.Vector3.z(position)),'fov '..tostring(sr.Camera.vertical_fov(cam)),
      'focus '..tostring(render_options.focus_distance),'aperture '..tostring(render_options.aperture),'quality '..tostring(render_options.dof_quality),'shape '..tostring(render_options.bokeh_shape),'custom_ready '..tostring(effects.custom_dof_ready),'utc_epoch '..os.time(),
      string.format('forward %.8f %.8f %.8f',unpack(forward)),string.format('right %.8f %.8f %.8f',unpack(right)),'roll '..tostring(options.roll)}
     local f=assert(io.open(root..name..'.txt','wb'));f:write(table.concat(rows,'\n'));f:close()
    end
    if capture_mode=='colorcheck'then
     local guarded,reason=backend.ready();assert(guarded,reason)
     local path=root..name..'_hdr0.dds';local existing=io.open(path,'rb');assert(not existing,'HDR output already exists')
     sr.Application.save_render_target('hdr0',path)
     sr.Application.save_render_target('hdr1',root..name..'_hdr1.dds')
     sr.Application.save_render_target('hdr0_div4_fullres',root..name..'_display.dds')
     ok,why=backend.capture(root..name..'.dds');mode='off'
    elseif capture_mode=='rawdepth'then
     local available,reason=depth.available();assert(available,reason)
     local guarded,reason=backend.ready();assert(guarded,reason)
     local path=root..name..'.dds';local existing=io.open(path,'rb');assert(not existing,'Raw depth output already exists')
     ok,why=pcall(sr.Application.save_render_target,'linear_depth',path)
    else ok,why=backend.capture(root..name..'.dds')end
    end)
    if not ran then ok,why=false,tostring(error_message)end
    local cleaned,cleanup_reason=overlay.release();restore_custom()
    if not cleaned then ok,why=false,tostring(cleanup_reason)end
    status(ok and 'Game capture saved: '..name or 'Game capture refused: '..tostring(why))
   end
  end
  return result
 end
 local function closer(...)if native_pair then finish_pair('photo exit')end;local ok,why=numeric_trial.release();if not ok then return false,why end;ok,why=environment_trial.release();if not ok then return false,why end;ok,why=overlay.release();if not ok then return false,why end;return release(...)end
 effects.apply,effects.release=wrapper,closer;state={photo=photo,effects=effects,controller=controller,original=original,release=release,wrapper=wrapper,closer=closer}
 status(photo.active and 'Photo validation attached' or 'Attached; open Photo Mode to run validation')
end,on_disable=function()
 if native_pair then finish_pair('validation disabled')end
 local restored,why=numeric_trial.release();if not restored then return false,why end
 restored,why=environment_trial.release();if not restored then return false,why end
 restored,why=exposure_trial.release();if not restored then return false,why end
 local ok,why=overlay.release();if not ok then return false,why end
 restore_custom()
 if state and state.effects.apply==state.wrapper then state.effects.apply,state.effects.release=state.original,state.release end
 status('Validation removed; original photo rendering retained');return true
end}
'''
compile_lua(source.encode(),'photo-dof-reversible-validation')
out=ROOT/'dist/dof-investigation-20261011/photo_dof_validation.lua';out.write_text(source);print(out)

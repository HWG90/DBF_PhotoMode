-- Photo lens and owned screen overlays share the camera lifecycle.
local M={}
function M.new(sr,lens_factory,composition,postfx_factory,log,hud,profile_factory,dof_factory,scene_factory)
 local self={};local lens=lens_factory.new(sr);local postfx=postfx_factory.new(sr,lens_factory,profile_factory)
 local dof
 if dof_factory then
  local ok,value=pcall(dof_factory.new,sr)
  if ok and type(value)=='table'and type(value.apply)=='function'and type(value.release)=='function'and type(value.ready)=='function'then dof=value
  else log('Custom depth of field candidate unavailable: '..tostring(value))end
 end
 local scene_effect
 if scene_factory then
  local ok,value=pcall(scene_factory.new,sr)
  if ok and type(value)=='table'and type(value.ready)=='function'and type(value.apply)=='function'and type(value.release)=='function'and type(value.active)=='function'then scene_effect=value
  else log('Scene effect candidate unavailable: '..tostring(value))end
 end
 -- This flag identifies an explicitly constructed candidate, never visual proof.
 self.custom_dof_candidate=dof~=nil;self.custom_dof_ready=false;self.warming_up_scene=false
 local native_warmed,custom_warmed,scene_warmed=false,false,false
 local gui,world,camera_world;local ids={};local signature;local shader_name;local seconds=0;local failed_shaders={};local layout_key,layout_cache;local shader_handle
 local clock_source,last_clock
 local function gui_world(scene)
  if not(sr.Application and sr.Application.worlds and sr.Application.main_world)then return scene end
  local main=sr.Application.main_world()
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then return candidate end end
 end
 local function gui_world_present(owner)
  if not(sr.Application and type(sr.Application.worlds)=='function')then return nil,'Photo GUI world listing unavailable'end
  local ok,worlds=pcall(sr.Application.worlds)
  if not ok or type(worlds)~='table'then return nil,'Photo GUI world lifetime unavailable'end
  for _,candidate in pairs(worlds)do if owner==candidate then return true end end
  return false
 end
 local function advance(dt)
  local elapsed=math.max(0,math.min(.1,dt or 0))
  local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
  local source=api and api.camera_input and api.camera_input.now
  if type(source)=='function' then
   local ok,now=pcall(source)
   if ok and type(now)=='number'and now==now and math.abs(now)<math.huge then
    elapsed=clock_source==source and last_clock and math.max(0,math.min(.1,now-last_clock))or 0
    clock_source,last_clock=source,now
   else clock_source,last_clock=nil,nil end
  else clock_source,last_clock=nil,nil end
  seconds=seconds+elapsed
 end
 local function shader_mapping(handle,o)
  sr.Material.set_vector4(handle,'scissor_rect',sr.Vector4(4/o.shader_scale,0,0,seconds))
  sr.Material.set_vector4(handle,'atlas_scissor',sr.Vector4(0,4/o.shader_scale,0,o.shader_animate==false and 0 or 1))
 end
 local function clear()
  if not gui then return end
  for _,p in ipairs(ids)do sr.Gui['destroy_'..p.kind](gui,p.id)end
  ids={};signature=nil
 end
 function self.release()
  if scene_effect then local ran,done,why=pcall(scene_effect.release);if not ran or done~=true then return false,ran and why or tostring(done)end end
  local custom_ok,custom_reason=true,nil
  if dof then local ran,done,why=pcall(dof.release);custom_ok,custom_reason=ran and done==true,ran and why or tostring(done)end
  self.custom_dof_ready=false;self.native_dof_ready=false;self.warming_up_scene=false;self.fov=nil
  native_warmed,custom_warmed,scene_warmed=false,false,false
  if self.parameters then
   self.parameters.focus_distance,self.parameters.aperture=nil,nil
   if scene_effect then for _,key in ipairs({'exposure','saturation','contrast','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do self.parameters[key]=nil end end
  end
  local ok,why=lens.release();local restored,reason=postfx.release()
  if hud then local done,err=hud.release();if not done then restored,reason=false,err end end
  if gui then
   -- World retirement already owns its GUI teardown. Never pass that old
   -- world/GUI pair back into the native destructor; an unreadable world list
   -- is not retirement proof, so retain the handle for a later cleanup retry.
   local present,reason=gui_world_present(world)
   if present==nil then return false,reason end
   if present then local done,err=pcall(sr.World.destroy_gui,world,gui);if not done then return false,tostring(err)end end
  end
  gui,world,camera_world=nil,nil,nil;ids={};signature=nil;shader_name=nil;shader_handle=nil;layout_key=nil;layout_cache=nil
  clock_source,last_clock=nil,nil
  if not ok then return false,why end;if not custom_ok then return false,custom_reason end;return restored,reason
 end
 function self.apply(cam,unit,scene,forward,right,o,dt)
  local owner=gui_world(scene)
  if camera_world and(camera_world~=scene or world~=owner)then local ok,why=self.release();assert(ok,why)end
  camera_world=scene
  if hud then if o.hide_hud~=false then hud.hold()else local ok,why=hud.release();assert(ok,why)end end
  local fov=lens.apply(cam,unit,forward,right,o);self.fov=fov;advance(dt)
  local custom_active,custom_status=false,nil
  self.custom_dof_ready=false
  local shader_mode=o.dof_mode==2
  local combined=dof and dof.combined_scene_dof_candidate==true
  local combined_ready=false
  if combined then
   local ran,ready,why=pcall(dof.ready)
   if ran and ready==true then
    local applied,done,reason,shader_active=pcall(dof.apply,o,fov)
    combined_ready=applied and done==true
    custom_active=combined_ready and shader_active==true
    custom_status=applied and reason or tostring(done)
    if not combined_ready then pcall(dof.release)end
   else custom_status=ran and why or tostring(ready);pcall(dof.release)end
   self.custom_dof_ready=shader_mode and combined_ready
  elseif dof and shader_mode then
   local ran,ready,why
   if o.dof then
    ran,ready,why=pcall(dof.apply,o,fov)
    custom_active=ran and ready==true
   else
    local cleared,done,reason=pcall(dof.release)
    if cleared and done==true then ran,ready,why=pcall(dof.ready)
    else ran,ready,why=true,false,cleared and reason or tostring(done)end
   end
   self.custom_dof_ready=ran and ready==true;custom_status=ran and why or tostring(ready)
   if not ran then pcall(dof.release);log('Custom depth of field candidate refused: '..tostring(ready))end
  elseif dof then
   local ran,done,why=pcall(dof.release)
   assert(ran and done==true,ran and why or tostring(done))
  end
  local native_options=o
  if custom_active then
   native_options={};for key,value in pairs(o)do native_options[key]=value end
   native_options.dof=false -- Disable the native pass only after our pass draws.
  end
  local worked,supported,status=pcall(postfx.apply,scene,native_options,fov,unit,cam,custom_active)
  if not worked then
   log('Photo rendering adjustment refused: '..tostring(supported))
   postfx.release();supported=false;status='Rendering effect unavailable; camera and pause retained'
   self.parameters={}
  else self.parameters={};for key,value in pairs(postfx.parameters or {})do self.parameters[key]=value end end
  self.parameters.focus_distance,self.parameters.aperture=nil,nil
  self.native_dof_candidate=postfx.native_numeric_candidate==true
  self.native_dof_ready=worked and postfx.native_numeric_ready==true and not shader_mode
  if self.native_dof_ready then self.parameters.focus_distance,self.parameters.aperture=true,true end
  if self.custom_dof_ready then
   self.parameters.dof,self.parameters.focus_distance,self.parameters.aperture=true,true,true
   status='Shader preview: depth-aware focus and aperture'
  end
  supported=custom_active or supported
  local scene_active=false;self.scene_status=''
  if combined then
   for _,key in ipairs({'exposure','saturation','contrast','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do self.parameters[key]=combined_ready and true or nil end
   scene_active=combined_ready and dof.scene_active==true
   self.scene_status=combined_ready and 'Combined scene and DoF preview' or 'Scene compositor unavailable: '..tostring(custom_status)
  elseif scene_effect then
   for _,key in ipairs({'exposure','saturation','contrast','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do self.parameters[key]=nil end
   if shader_mode and o.dof then
    local ran,done,why=pcall(scene_effect.release);assert(ran and done==true,ran and why or tostring(done))
    for _,key in ipairs({'exposure','saturation','contrast','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do self.parameters[key]=nil end
    self.scene_status='Shader DoF Enabled. Scene Effects disabled'
   else
    local ran,ready,why=pcall(scene_effect.ready)
    if ran and ready==true then
     local applied,done,reason=pcall(scene_effect.apply,o)
     if applied and done==true then
      for _,key in ipairs({'exposure','saturation','contrast','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do self.parameters[key]=true end
      scene_active=scene_effect.active(o);self.scene_status='Scene preview: 960x540 color source'
     else
      pcall(scene_effect.release);self.scene_status='Scene effects unavailable: '..tostring(applied and reason or done)
     end
    else pcall(scene_effect.release);self.scene_status='Scene effects unavailable: '..tostring(ran and why or ready)end
   end
  end
  supported=scene_active or supported
  self.lens_status=status
  self.color_status='Warm/cool color tints ready; tonal grading unavailable'
  if self.parameters and self.parameters.exposure then self.color_status='Scene color grading profile available'end
  if o.dof==true and o.dof_mode==2 and not combined then self.color_status='Shader DoF Enabled. Scene Effects disabled'end
  if self.native_dof_ready then native_warmed=true end
  if self.custom_dof_ready then custom_warmed=true end
  if self.parameters.exposure then scene_warmed=true end
  local lens_waiting=shader_mode and dof~=nil and not custom_warmed and not self.custom_dof_ready or
   not shader_mode and self.native_dof_candidate and not native_warmed and not self.native_dof_ready
  local scene_waiting=(combined or scene_effect~=nil)and not scene_warmed and not self.parameters.exposure and
   not(shader_mode and o.dof and not combined)
  -- Initial scene resource loading is distinct from a later draw/resource
  -- failure. Keep the existing detailed status/error fields unchanged.
  self.warming_up_scene=(lens_waiting or scene_waiting)==true
  local w,h=sr.Gui.resolution();assert(type(w)=='number' and w>0 and type(h)=='number' and h>0,'Photo viewport unavailable')
  if not owner then self.lens_status='Photo UI world unavailable; camera retained';return false end
  if not gui then world=owner;gui=assert(sr.World.create_screen_gui(owner,'scale',1,1))end
  local layout_fields={tostring(w),tostring(h)}
  for _,key in ipairs({'filter','filter_strength','shader','shader_opacity','shader_scale','vignette','vignette_width','grain','grain_size','frame','grid','logo','logo_size','logo_x','logo_y','logo_opacity','logo_color','clean_view'})do
   layout_fields[#layout_fields+1]=key..'='..tostring(o[key])
  end
  table.sort(layout_fields)
  if (o.grain or 0)>0 then layout_fields[#layout_fields+1]='grain_frame='..math.floor(seconds*12)end
  local current_layout=table.concat(layout_fields,'|')
  if layout_key~=current_layout then layout_cache=composition.layout(w,h,o,seconds);layout_key=current_layout end
  local commands=layout_cache
  local shader=composition.shaders[o.shader or 1];local material
  self.shader_status=''
  if shader and shader~='' and o.shader_opacity>0 then
   material='mods/dbf_hud/materials/mapped_'..shader
   if failed_shaders[material]or not sr.Application.can_get('material',material)then material=nil;self.shader_status='Shader assets unavailable'
   end
  end
  local key=current_layout..'|'..(material or '')
  if key==signature then
   if shader_handle and material then
    local ok=pcall(shader_mapping,shader_handle,o)
    if not ok then failed_shaders[material]=true end
   end
   return supported
  end
  shader_handle=nil
  clear();shader_name=material
  for _,c in ipairs(commands)do
   local id;local kind=c.type=='triangle'and'triangle'or'rect';local color=sr.Color(math.floor(c.a*255),unpack(c.c))
   if kind=='triangle'then
    local p=c.points;id=sr.Gui.triangle(gui,sr.Vector3(p[1],0,p[2]),sr.Vector3(p[3],0,p[4]),sr.Vector3(p[5],0,p[6]),100,color)
   else id=sr.Gui.rect(gui,sr.Vector3(c.x,c.y,100),sr.Vector2(c.w,c.h),color)end
   ids[#ids+1]={kind=kind,id=id}
  end
  if material then
   -- Each photo GUI owns a mapped HUD shader material instance.
   -- Uniforms proven by the HUD material contract; failures disable this overlay.
   local ok,why=pcall(function()
    local handle=assert(sr.Gui.material(gui,material));shader_handle=handle
    sr.Material.set_scalar(handle,'scissor_mode',0)
    sr.Material.set_scalar(handle,'threshold_fade',0)
    shader_mapping(handle,o)
    sr.Material.set_vector4(handle,'clip_box',sr.Vector4(0,0,1,0))
    local rgb=composition.shader_colors and composition.shader_colors[shader]or {255,255,255}
    local id=assert(sr.Gui.bitmap(gui,material,sr.Vector3(0,0,90),sr.Vector2(w,h),sr.Color(math.floor(o.shader_opacity*2.55),unpack(rgb))))
    ids[#ids+1]={kind='bitmap',id=id}
   end)
   if not ok then failed_shaders[material]=true;self.shader_status='Shader unavailable; camera retained';log(tostring(why))end
  end
  signature=key;return supported
 end
 return self
end
return M

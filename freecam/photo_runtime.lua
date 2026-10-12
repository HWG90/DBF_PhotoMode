-- Photo lens and owned screen overlays share the camera lifecycle.
local M={}
function M.new(sr,lens_factory,composition,postfx_factory,log,hud,profile_factory)
 local self={};local lens=lens_factory.new(sr);local postfx=postfx_factory.new(sr,lens_factory,profile_factory)
 local gui,world,camera_world;local ids={};local signature;local shader_name;local seconds=0;local failed_shaders={};local layout_key,layout_cache;local shader_handle
 local clock_source,last_clock
 local function gui_world(scene)
  if not(sr.Application and sr.Application.worlds and sr.Application.main_world)then return scene end
  local main=sr.Application.main_world()
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then return candidate end end
 end
 local function advance(dt)
  local elapsed=math.max(0,math.min(.1,dt or 0))
  local api=rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
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
  for _,p in ipairs(ids)do sr.Gui[p.kind=='rect' and 'destroy_rect' or 'destroy_bitmap'](gui,p.id)end
  ids={};signature=nil
 end
 function self.release()
  local ok,why=lens.release();local restored,reason=postfx.release()
  if hud then local done,err=hud.release();if not done then restored,reason=false,err end end
  if gui then local done,err=pcall(sr.World.destroy_gui,world,gui);if not done then return false,tostring(err)end end
  gui,world,camera_world=nil,nil,nil;ids={};signature=nil;shader_name=nil;shader_handle=nil;layout_key=nil;layout_cache=nil
  clock_source,last_clock=nil,nil
  if not ok then return false,why end;return restored,reason
 end
 function self.apply(cam,unit,scene,forward,right,o,dt)
  local owner=gui_world(scene)
  if camera_world and(camera_world~=scene or world~=owner)then local ok,why=self.release();assert(ok,why)end
  camera_world=scene
  if hud then if o.hide_hud~=false then hud.hold()else local ok,why=hud.release();assert(ok,why)end end
  local fov=lens.apply(cam,unit,forward,right,o);advance(dt)
  self.custom_dof_ready=false
  local worked,supported,status=pcall(postfx.apply,scene,o,fov,unit,cam,self.custom_dof_ready)
  if not worked then
   log('Photo rendering adjustment refused: '..tostring(supported))
   postfx.release();supported=false;status='Rendering effect unavailable; camera and pause retained'
   self.parameters={}
  else self.parameters={};for key,value in pairs(postfx.parameters or {})do self.parameters[key]=value end end
  self.parameters.focus_distance,self.parameters.aperture=nil,nil
  self.scene_status=''
  self.lens_status=status
  self.color_status='Warm/cool color tints ready; tonal grading unavailable'
  if self.parameters and self.parameters.exposure then self.color_status='Scene color grading profile available'end
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
   local id=sr.Gui.rect(gui,sr.Vector3(c.x,c.y,100),sr.Vector2(c.w,c.h),sr.Color(math.floor(c.a*255),unpack(c.c)))
   ids[#ids+1]={kind='rect',id=id}
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

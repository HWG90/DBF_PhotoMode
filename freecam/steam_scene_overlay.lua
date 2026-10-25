-- Private combined candidate. output_target is native graded PQ in HDR/SDR;
-- color; GUI composition uses its actual UI white. Visual proof is still needed.
local M={}
M.shader='mods/dbf_photo/shaders/scene_dof_resolved_v2_76ff992884d03475'
M.material='mods/dbf_photo/materials/scene_dof_resolved_v2_76ff992884d03475'
M.sdr_shader='mods/dbf_photo/shaders/scene_dof_resolved_v2_da4d644cfee69b09'
M.sdr_white_nits=48 -- Exact SDR scene-copy parity on the qualified renderer build.
M.sdr_material='mods/dbf_photo/materials/scene_dof_resolved_v2_da4d644cfee69b09'
M.layer=88
M.combined_scene_dof_candidate=true
M.color_target='output_target'
M.color_target_hash=0xa68c78a4
M.color_encoding='pq-bt2020-resolved'
-- Read only the existing renderer map/cache. Calling Renderer.resource on a
-- missing key inserts a target, so this guard deliberately never invokes it.
local function number(value,fallback,low,high)
 if type(value)~='number'or value~=value or math.abs(value)==math.huge then value=fallback end
 return math.max(low,math.min(high,value))
end
function M.uniforms(o,fov,ui_white)
 o=o or {}
 local mode=math.floor(number(o.scene_shader,1,1,10))-1
 local strength=number(o.scene_strength,100,0,100)/100
 local exposure=number(o.exposure,0,-4,4)
 local contrast=number(o.contrast,100,50,200)/100
 local saturation=number(o.saturation,100,0,200)/100
 local scene=(mode>0 and strength>0)or exposure~=0 or contrast~=1 or saturation~=1
 local shader=o.dof==true and o.dof_mode==2
 return {
  active=scene or shader,scene_active=scene,shader_dof_active=shader,
  scissor={number(o.focus_distance,5,.1,200),number(o.aperture,5.6,1.2,22),number(fov,.9,.02,2.9),shader and 24*number(o.dof_strength,4,1,8)or 0},
  atlas={number(o.scene_depth_range,100,1,200),number(o.fog_density,50,0,100)/100+(o.depth_calibration==true and 1000 or 0),o.bokeh_shape==2 and 6 or 0,o.dof_quality==2 and 1 or 0},
  clip={exposure,contrast,saturation,number(ui_white,203,.01,10000)},
  mode=mode,strength=strength,fog_distance=number(o.fog_distance,25,.1,200),
 }
end
function M.active(options)return M.uniforms(options).active end
function M.new(sr,depth,allow_candidate,registration,verify_color)
 local self={combined_scene_dof_candidate=true,shader_dof_active=false,scene_active=false}
 local gui,world,signature,bound;local failed=false
 local color_guard,color_guard_error
 if verify_color then color_guard=verify_color
 else color_guard_error='Current color resource verifier required'end
 local function present(owner)
  local ok,worlds=pcall(sr.Application.worlds)
  if ok then for _,candidate in pairs(worlds or {})do if owner==candidate then return true end end end
  return false
 end
 function self.ready(options)
  self.color_binding_identity=nil
  self.ui_brightness=nil
  self.hdr_enabled=nil
  if allow_candidate~=true then return false,'Combined scene/DoF candidate is disabled'end
  if failed then return false,'Combined scene/DoF disabled after an error'end
  if not registration or type(registration.present)~='function'then return false,'Combined shader registration guard unavailable'end
  local ran,registered,why=pcall(registration.present)
  if not ran or registered~=true then return false,ran and why or tostring(registered)end
  local ok,available=pcall(function()
   return sr.Application.can_get('shader_library',M.shader)and sr.Application.can_get('material',M.material)
  end)
  if not ok or not available then return false,'Combined scene shader or material is not available'end
  if depth.available then local done,why=depth.available();if done~=true then return false,why end end
  if not color_guard then return false,color_guard_error or 'Combined color target verification unavailable'end
  local verified,exists,target=pcall(color_guard)
  if not verified or exists~=true then return false,verified and 'Resolved color target verification refused'or tostring(exists)end
  local w,h=sr.Gui.resolution()
  if type(target)~='table'or target.format~=19 or target.mips~=1 or target.array~=1 or
   type(w)~='number'or type(h)~='number'or w<=0 or h<=0 or w>16384 or h>16384 or
   target.width~=w or target.height~=h or not target.resource or not target.backing or not target.id then
   return false,'Resolved color target descriptor must be full-size RGBA16float'
  end
  if type(target.hdr_enabled)~='boolean'then return false,'Resolved color candidate requires a verified boolean hdr_enabled setting'end
  local white=target.ui_brightness
  if type(white)~='number'or white~=white or white<=0 or white>10000 then
   return false,'Renderer ui_brightness must be a finite positive number in nits'
  end
  self.material=M.material;self.sdr=false
  if target.hdr_enabled==false and options and options.dof==true and options.dof_mode==2 then
   local ok,present=pcall(function()return sr.Application.can_get('shader_library',M.sdr_shader)and sr.Application.can_get('material',M.sdr_material)end)
   if ok and present then
    local ran,registered,why=pcall(registration.present,0x49a73b4c)
    if not ran or registered~=true then return false,ran and why or tostring(registered)end
    self.material=M.sdr_material;self.sdr=true
   end
  end
  -- SDR uses the compositor's fixed cinema reference, not the HDR paper-white
  -- setting returned by Application.render_setting('ui_brightness'). Matched
  -- scene-copy captures establish 48 nits; HDR retains its verified setting.
  self.ui_brightness=target.hdr_enabled and white or M.sdr_white_nits
  self.hdr_enabled=target.hdr_enabled
  self.color_binding_identity=tostring(target.resource)..':'..tostring(target.backing)..':'..tostring(target.id)
  return true
 end
 function self.release()
  self.shader_dof_active,self.scene_active=false,false
  if gui and present(world)then
   local ok,why=pcall(sr.World.destroy_gui,world,gui)
   if not ok then return false,tostring(why)end
  end
  gui,world,signature,bound=nil,nil,nil,nil;self.color_binding_identity=nil;self.ui_brightness=nil;self.hdr_enabled=nil;return true
 end
 function self.apply(options,fov)
  -- The caller may suppress native DoF only if the returned third value is
  -- true. No native flag is written by this draw module.
  self.shader_dof_active,self.scene_active=false,false
  local uniforms=M.uniforms(options,fov)
  if not uniforms.active then local done,why=self.release();return done,why,false end
  local ready,reason=self.ready(options);if not ready then self.release();return false,reason,false end
  local material=self.material;local sdr=self.sdr
  local color_binding_identity=self.color_binding_identity
  local ui_brightness=self.ui_brightness
  uniforms.clip[4]=sdr and -ui_brightness or ui_brightness
  local hdr_enabled=self.hdr_enabled
  local target,reason=depth.get();if not target then self.release();return false,reason,false end
  local main=sr.Application.main_world();local owner
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then owner=candidate;break end end
  if not owner then self.release();return false,'Photo UI world unavailable',false end
  local w,h=sr.Gui.resolution()
  if not(w and h and w>0 and h>0)then self.release();return false,'Photo viewport unavailable',false end
  local key=tostring(owner)..'|'..w..'|'..h..'|'..material
  local ok,why=pcall(function()
   if signature~=key then
    local done,err=self.release();assert(done,err)
    world=owner;gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
    bound={handle=assert(sr.Gui.material(gui,material))};signature=key
   end
   if bound.resource~=target or bound.resource_identity~=depth.binding_identity then
    if depth.bind then local done,err=depth.bind(bound.handle,'diffuse_map',target);assert(done,err)
    else sr.Material.set_resource(bound.handle,'diffuse_map',target)end
    bound.resource=target;bound.resource_identity=depth.binding_identity
   end
   -- All names/offsets already belong to the native GUI material ABI.
   sr.Material.set_vector4(bound.handle,'scissor_rect',sr.Vector4(unpack(uniforms.scissor)))
   sr.Material.set_vector4(bound.handle,'atlas_scissor',sr.Vector4(unpack(uniforms.atlas)))
   sr.Material.set_vector4(bound.handle,'clip_box',sr.Vector4(unpack(uniforms.clip)))
   sr.Material.set_scalar(bound.handle,'scissor_mode',uniforms.mode)
   sr.Material.set_scalar(bound.handle,'threshold_fade',uniforms.strength)
   sr.Material.set_scalar(bound.handle,'desaturate',uniforms.fog_distance)
   local fields={uniforms.mode,uniforms.strength,uniforms.fog_distance,ui_brightness,hdr_enabled and 1 or 0}
   for _,values in ipairs({uniforms.scissor,uniforms.atlas,uniforms.clip})do
    for _,value in ipairs(values)do fields[#fields+1]=value end
   end
   fields[#fields+1]=tostring(target);fields[#fields+1]=tostring(depth.binding_identity);fields[#fields+1]=tostring(color_binding_identity)
   local draw_key=table.concat(fields,'|')
   if bound.draw_key~=draw_key then
    for _,id in ipairs(bound.ids or {})do sr.Gui.destroy_triangle(gui,id)end
    bound.ids={}
    local a,b,c,d=sr.Vector3(0,0,0),sr.Vector3(w,0,0),sr.Vector3(w,0,h),sr.Vector3(0,0,h)
    local color=sr.Color(255,255,255,255)
    local ua,ub,uc,ud=sr.Vector2(0,0),sr.Vector2(1,0),sr.Vector2(1,1),sr.Vector2(0,1)
    bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,b,c,M.layer,color,material,ua,ub,uc))
    bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,c,d,M.layer,color,material,ua,uc,ud))
    bound.draw_key=draw_key
   end
  end)
  if not ok then failed=true;self.release();return false,tostring(why),false end
  self.color_binding_identity=color_binding_identity
  self.ui_brightness=ui_brightness
  self.hdr_enabled=hdr_enabled
  self.shader_dof_active,self.scene_active=uniforms.shader_dof_active,uniforms.scene_active
  return true,'Combined resolved '..(hdr_enabled and 'HDR'or 'SDR')..' scene/DoF candidate; GUI highlights limited to UI white',self.shader_dof_active
 end
 return self
end
return M

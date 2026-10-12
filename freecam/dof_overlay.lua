-- Candidate-only depth overlay. Resource availability is not visual verification.
local M={}
function M.new(sr,depth,allow_candidate,registration)
 local self={};local gui,world,signature,bound;local failed=false
 local material='mods/dbf_photo/materials/dof_local_depth_v1'
 local shader='mods/dbf_photo/shaders/dof_local_depth_v1'
 local function present(owner)
  for _,candidate in pairs(sr.Application.worlds()or {})do if owner==candidate then return true end end
  return false
 end
 function self.ready()
  if allow_candidate~=true then return false,'Custom depth of field candidate is disabled'end
  if failed then return false,'Custom depth of field disabled after an error'end
  if registration then local present,why=registration.present();if not present then return false,why end end
  local ok,available=pcall(function()
   return sr.Application.can_get('shader_library',shader)and sr.Application.can_get('material',material)
  end)
  if not ok or not available then return false,'Depth shader or material is not available'end
  if depth.available then return depth.available()end
  return true
 end
 function self.release()
  if gui and present(world)then local ok,why=pcall(sr.World.destroy_gui,world,gui);if not ok then return false,tostring(why)end end
  gui,world,signature,bound=nil,nil,nil,nil;return true
 end
 function self.apply(options,fov)
  if allow_candidate~=true then return false,'Custom depth of field candidate is disabled'end
  if failed then return false,'Custom depth of field disabled after an error'end
  if not options.dof then local ok,why=self.release();return ok,why end
  local ready,reason=self.ready();if not ready then self.release();return false,reason end
  local target,reason=depth.get();if not target then self.release();return false,reason end
  local main=sr.Application.main_world();local owner
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then owner=candidate;break end end
  if not owner then self.release();return false,'Photo UI world unavailable'end
  local w,h=sr.Gui.resolution();if not(w and h and w>0 and h>0)then self.release();return false,'Photo viewport unavailable'end
  local key=tostring(owner)..'|'..w..'|'..h..'|'..tostring(options.validation_marker==true)
  local ok,why=pcall(function()
   if signature~=key then
    local done,err=self.release();assert(done,err)
    world=owner;gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
    local handle=assert(sr.Gui.material(gui,material))
    sr.Material.set_scalar(handle,'scissor_mode',0);sr.Material.set_scalar(handle,'threshold_fade',0)
    sr.Material.set_vector4(handle,'clip_box',sr.Vector4(0,0,1,0))
    if options.validation_marker then assert(sr.Gui.rect(gui,sr.Vector3(30,30,800),sr.Vector2(128,128),sr.Color(255,255,0,255)))end
    bound={handle=handle};signature=key
   end
   if bound.resource~=target or bound.resource_identity~=depth.binding_identity then
    if depth.bind then local done,why=depth.bind(bound.handle,'diffuse_map',target);assert(done,why)
    else sr.Material.set_resource(bound.handle,'diffuse_map',target)end
    bound.resource=target;bound.resource_identity=depth.binding_identity
   end
   local focus=math.max(.1,math.min(200,options.focus_distance or 5))
   local aperture=math.max(1.2,math.min(22,options.aperture or 5.6))
   sr.Material.set_vector4(bound.handle,'scissor_rect',sr.Vector4(focus,aperture,fov,32))
   local blades=options.bokeh_shape==2 and 6 or 0
   local quality=options.dof_quality==2 and 1 or 0
   sr.Material.set_vector4(bound.handle,'atlas_scissor',sr.Vector4(1,options.depth_calibration and 1 or 0,blades,quality))
   -- Submit only after resources/uniforms are bound. Native GUI triangles use XZ.
   local draw_key=table.concat({focus,aperture,fov,blades,quality,tostring(options.depth_calibration==true),tostring(target),tostring(depth.binding_identity)},'|')
   if bound.draw_key~=draw_key then
    for _,id in ipairs(bound.ids or {})do sr.Gui.destroy_triangle(gui,id)end
    local a,b,c,d=sr.Vector3(0,0,0),sr.Vector3(w,0,0),sr.Vector3(w,0,h),sr.Vector3(0,0,h)
    local color=sr.Color(255,255,255,255)
    local ua,ub,uc,ud=sr.Vector2(0,0),sr.Vector2(1,0),sr.Vector2(1,1),sr.Vector2(0,1)
    bound.ids={assert(sr.Gui.triangle(gui,a,b,c,88,color,material,ua,ub,uc)),assert(sr.Gui.triangle(gui,a,c,d,88,color,material,ua,uc,ud))}
    bound.draw_key=draw_key
   end
  end)
  if not ok then failed=true;self.release();return false,tostring(why)end
  return true,'Custom depth of field candidate active'
 end
 return self
end
return M

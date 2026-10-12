-- Photo-owned scene effects. This candidate samples the proven 960x540 display
-- source; neutral controls submit no carrier and preserve the original image.
local M={}
M.shader='mods/dbf_photo/shaders/scene_depth_color_v1'
M.material='mods/dbf_photo/materials/scene_depth_color_v1'
M.layer=87 -- Before custom DoF (88), decorative overlays (90), and guides (100).
local function number(value,fallback,low,high)
 if type(value)~='number'or value~=value or math.abs(value)==math.huge then value=fallback end
 return math.max(low,math.min(high,value))
end
function M.uniforms(o)
 local mode=math.floor(number(o.scene_shader,1,1,10))
 local strength=number(o.scene_strength,100,0,100)/100
 local exposure=number(o.exposure,0,-4,4)
 local contrast=number(o.contrast,100,50,200)/100
 local saturation=number(o.saturation,100,0,200)/100
 return {
  active=(mode>1 and strength>0)or exposure~=0 or contrast~=1 or saturation~=1,
  scissor={mode-1,strength,number(o.fog_distance,25,.1,200),number(o.fog_density,50,0,100)/100},
  atlas={exposure,contrast,saturation,number(o.scene_depth_range,100,1,200)},
 }
end
function M.new(sr,depth,allow_candidate,registration)
 local self={};local gui,world,signature,bound;local failed=false
 local function present(owner)
  local ok,worlds=pcall(sr.Application.worlds)
  if ok then for _,candidate in pairs(worlds or {})do if owner==candidate then return true end end end
  return false
 end
 function self.ready()
  if allow_candidate~=true then return false,'Scene effect candidate is disabled'end
  if failed then return false,'Scene effects disabled after an error'end
  if not registration or type(registration.present)~='function'then return false,'Scene shader registration guard unavailable'end
  local ran,registered,why=pcall(registration.present)
  if not ran or registered~=true then return false,ran and why or tostring(registered)end
  local ok,available=pcall(function()
   return sr.Application.can_get('shader_library',M.shader)and sr.Application.can_get('material',M.material)
  end)
  if not ok or not available then return false,'Scene shader or material is not available'end
  if depth.available then return depth.available()end
  return true
 end
 function self.release()
  if gui and present(world)then
   local ok,why=pcall(sr.World.destroy_gui,world,gui)
   if not ok then return false,tostring(why)end
  end
  gui,world,signature,bound=nil,nil,nil,nil;return true
 end
 function self.apply(options)
  local uniforms=M.uniforms(options)
  if not uniforms.active then return self.release()end
  local ready,reason=self.ready();if not ready then self.release();return false,reason end
  local target,reason=depth.get();if not target then self.release();return false,reason end
  local main=sr.Application.main_world();local owner
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then owner=candidate;break end end
  if not owner then self.release();return false,'Photo UI world unavailable'end
  local w,h=sr.Gui.resolution()
  if not(w and h and w>0 and h>0)then self.release();return false,'Photo viewport unavailable'end
  local key=tostring(owner)..'|'..w..'|'..h
  local ok,why=pcall(function()
   if signature~=key then
    local done,err=self.release();assert(done,err)
    world=owner;gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
    local handle=assert(sr.Gui.material(gui,M.material))
    sr.Material.set_scalar(handle,'scissor_mode',0);sr.Material.set_scalar(handle,'threshold_fade',0)
    sr.Material.set_vector4(handle,'clip_box',sr.Vector4(0,0,1,0))
    bound={handle=handle};signature=key
   end
   if bound.resource~=target or bound.resource_identity~=depth.binding_identity then
    if depth.bind then local done,err=depth.bind(bound.handle,'diffuse_map',target);assert(done,err)
    else sr.Material.set_resource(bound.handle,'diffuse_map',target)end
    bound.resource=target;bound.resource_identity=depth.binding_identity
   end
   sr.Material.set_vector4(bound.handle,'scissor_rect',sr.Vector4(unpack(uniforms.scissor)))
   sr.Material.set_vector4(bound.handle,'atlas_scissor',sr.Vector4(unpack(uniforms.atlas)))
   local draw_fields={};for _,v in ipairs(uniforms.scissor)do draw_fields[#draw_fields+1]=v end
   for _,v in ipairs(uniforms.atlas)do draw_fields[#draw_fields+1]=v end
   draw_fields[#draw_fields+1]=tostring(target);draw_fields[#draw_fields+1]=tostring(depth.binding_identity)
   local draw_key=table.concat(draw_fields,'|')
   if bound.draw_key~=draw_key then
    for _,id in ipairs(bound.ids or {})do sr.Gui.destroy_triangle(gui,id)end
    local a,b,c,d=sr.Vector3(0,0,0),sr.Vector3(w,0,0),sr.Vector3(w,0,h),sr.Vector3(0,0,h)
    local color=sr.Color(255,255,255,255)
    local ua,ub,uc,ud=sr.Vector2(0,0),sr.Vector2(1,0),sr.Vector2(1,1),sr.Vector2(0,1)
    bound.ids={assert(sr.Gui.triangle(gui,a,b,c,M.layer,color,M.material,ua,ub,uc)),assert(sr.Gui.triangle(gui,a,c,d,M.layer,color,M.material,ua,uc,ud))}
    bound.draw_key=draw_key
   end
  end)
  if not ok then failed=true;self.release();return false,tostring(why)end
  return true,'Scene effect preview: 960x540 display source'
 end
 return self
end
return M

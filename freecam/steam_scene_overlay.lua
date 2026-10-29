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
function M.paths(contract)
 if contract=='private-local-v1'then
  return 'mods/dbf_photo/shaders/windows_private_depth_8994dbbab90c07c5',
   'mods/dbf_photo/materials/windows_private_depth_8994dbbab90c07c5',
   'mods/dbf_photo/shaders/windows_private_depth_535eeb61c686fbab',
   'mods/dbf_photo/materials/windows_private_depth_535eeb61c686fbab'
 end
 assert(not contract,'Global-depth candidates withdrawn after Windows menu-open crashes')
 return M.shader,M.material,M.sdr_shader,M.sdr_material
end
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
-- The screen minus the menu's blurred backdrops, as {x0,y0,x1,y1} pieces. gui_blur draws the
-- game's blur_behind_ui image in an earlier UI pass than this grade, so a full-screen grade
-- hides it; the grade leaves those areas uncovered instead. No holes: one full-screen piece.
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
function M.pieces(w,h,holes)
 local cut={}
 for _,r in ipairs(type(holes)=='table'and holes or{})do
  if type(r)=='table'and finite(r.x)and finite(r.y)and finite(r.w)and finite(r.h)then
   local x0,y0,x1,y1=math.max(0,r.x),math.max(0,r.y),math.min(w,r.x+r.w),math.min(h,r.y+r.h)
   if x1>x0 and y1>y0 then cut[#cut+1]={x0,y0,x1,y1}end
  end
 end
 if #cut==0 then return{{0,0,w,h}}end
 local ys={0,h};for _,c in ipairs(cut)do ys[#ys+1]=c[2];ys[#ys+1]=c[4]end
 table.sort(ys)
 local pieces={}
 for i=1,#ys-1 do
  local ya,yb=ys[i],ys[i+1]
  if yb>ya then
   local spans={}
   for _,c in ipairs(cut)do if c[2]<=ya and c[4]>=yb then spans[#spans+1]={c[1],c[3]}end end
   table.sort(spans,function(a,b)return a[1]<b[1]end)
   local x=0
   for _,s in ipairs(spans)do if s[1]>x then pieces[#pieces+1]={x,ya,s[1],yb}end;x=math.max(x,s[2])end
   if x<w then pieces[#pieces+1]={x,ya,w,yb}end
  end
 end
 return pieces
end
function M.new(sr,depth,allow_candidate,registration,verify_color)
 local self={combined_scene_dof_candidate=true,shader_dof_active=false,scene_active=false}
 local shader_path,material_path,sdr_shader_path,sdr_material_path=M.paths(depth.binding_contract or depth.global_binding)
 local gui,world,signature,bound;local failed=false
 -- Registry/descriptor/color verification runs on any resolution, HDR or
 -- material change and at most once per second otherwise. The bound depth
 -- resource itself is still fetched and identity-checked every frame.
 local verified_key,verified_at
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
   return sr.Application.can_get('shader_library',shader_path)and sr.Application.can_get('material',material_path)
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
  self.material=material_path;self.sdr=false
  if target.hdr_enabled==false and options and options.dof==true and options.dof_mode==2 then
   local ok,present=pcall(function()return sr.Application.can_get('shader_library',sdr_shader_path)and sr.Application.can_get('material',sdr_material_path)end)
   if ok and present then
    local ran,registered,why=pcall(registration.present,0x49a73b4c)
    if not ran or registered~=true then return false,ran and why or tostring(registered)end
    self.material=sdr_material_path;self.sdr=true
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
 function self.rearm()failed=false;verified_key=nil end
 function self.release()
  self.shader_dof_active,self.scene_active=false,false;verified_key=nil
  if gui and present(world)then
   local ok,why=pcall(sr.World.destroy_gui,world,gui)
   if not ok or why==false then return false,not ok and tostring(why)or'Scene GUI retirement refused'end
  end
  gui,world,signature,bound=nil,nil,nil,nil;self.color_binding_identity=nil;self.ui_brightness=nil;self.hdr_enabled=nil;return true
 end
 -- holes: screen rectangles {x,y,w,h} the menu currently blurs (nil when it draws none).
 function self.apply(options,fov,holes)
  -- The caller may suppress native DoF only if the returned third value is
  -- true. No native flag is written by this draw module.
  self.shader_dof_active,self.scene_active=false,false
  local uniforms=M.uniforms(options,fov)
  if not uniforms.active then local done,why=self.release();return done,why,false end
  local w,h=sr.Gui.resolution()
  local pieces=M.pieces(w,h,holes)
  local read_hdr,hdr=pcall(sr.Application.render_setting,'hdr_enabled')
  local key=tostring(w)..'x'..tostring(h)..'|'..tostring(read_hdr and hdr)..'|'..tostring(options and options.dof==true and options.dof_mode==2)
  local clock=sr.Application.time_since_launch;local now=type(clock)=='function'and clock()or nil
  if key~=verified_key or not now or not verified_at or now<verified_at or now-verified_at>=1 then
   local ready,reason=self.ready(options);if not ready then self.release();return false,reason,false end
   verified_key,verified_at=key,now
  end
  local material=self.material;local sdr=self.sdr
  local color_binding_identity=self.color_binding_identity
  local ui_brightness=self.ui_brightness
  uniforms.clip[4]=sdr and -ui_brightness or ui_brightness
  local hdr_enabled=self.hdr_enabled
  local target,reason=depth.get();if not target then self.release();return false,reason,false end
  local main=sr.Application.main_world();local owner
  local scope=depth.render_world and depth.render_world()or'ui'
  assert(scope=='ui'or scope=='main','Unknown scene GUI world scope')
  for _,candidate in pairs(sr.Application.worlds()or {})do
   if(scope=='main'and candidate==main)or(scope=='ui'and candidate~=main)then owner=candidate;break end
  end
  if not owner then self.release();return false,'Photo '..scope..' world unavailable',false end
  if not(w and h and w>0 and h>0)then self.release();return false,'Photo viewport unavailable',false end
  local key=tostring(owner)..'|'..w..'|'..h..'|'..material
  local ok,why=pcall(function()
   if world~=owner or signature~=key then
    local done,err=self.release();assert(done,err)
    world=owner;gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
    bound={ids={}};signature=key
    if type(sr.Gui.create_material)=='function'then
     bound.handle=assert(sr.Gui.create_material(gui,material))
    else
     -- This game build lacks create_material. A retained primitive assigns
     -- the loaded material to our GUI before its handle may be queried.
     -- Keep it assigned until the final quad exists; configure that final
     -- material before returning to the native renderer.
     local a,b,c=sr.Vector3(0,0,0),sr.Vector3(w,0,0),sr.Vector3(w,0,h)
     bound.ids[1]=assert(sr.Gui.triangle(gui,a,b,c,M.layer,sr.Color(255,255,255,255),material,sr.Vector2(0,0),sr.Vector2(1,0),sr.Vector2(1,1)))
     bound.handle=assert(sr.Gui.material(gui,material))
     bound.late_binding=true
    end
   end
   if not bound.late_binding and(bound.resource~=target or bound.resource_identity~=depth.binding_identity)then
    if depth.bind then local done,err=depth.bind(bound.handle,'diffuse_map',target);assert(done,err)
    else sr.Material.set_resource(bound.handle,'diffuse_map',target)end
    bound.resource=target;bound.resource_identity=depth.binding_identity
   end
   local function write_parameters()
    -- All names/offsets already belong to the native GUI material ABI.
    sr.Material.set_vector4(bound.handle,'scissor_rect',sr.Vector4(unpack(uniforms.scissor)))
    sr.Material.set_vector4(bound.handle,'atlas_scissor',sr.Vector4(unpack(uniforms.atlas)))
    sr.Material.set_vector4(bound.handle,'clip_box',sr.Vector4(unpack(uniforms.clip)))
    sr.Material.set_scalar(bound.handle,'scissor_mode',uniforms.mode)
    sr.Material.set_scalar(bound.handle,'threshold_fade',uniforms.strength)
    sr.Material.set_scalar(bound.handle,'desaturate',uniforms.fog_distance)
   end
   if not bound.late_binding then write_parameters()end
   local fields={uniforms.mode,uniforms.strength,uniforms.fog_distance,ui_brightness,hdr_enabled and 1 or 0}
   for _,values in ipairs({uniforms.scissor,uniforms.atlas,uniforms.clip})do
    for _,value in ipairs(values)do fields[#fields+1]=value end
   end
   fields[#fields+1]=tostring(target);fields[#fields+1]=tostring(depth.binding_identity);fields[#fields+1]=tostring(color_binding_identity)
   for _,p in ipairs(pieces)do for i=1,4 do fields[#fields+1]=p[i]end end
   local draw_key=table.concat(fields,'|')
   if bound.draw_key~=draw_key then
    local previous=bound.ids
    if not bound.late_binding then for _,id in ipairs(previous)do sr.Gui.destroy_triangle(gui,id)end end
    bound.ids={}
    local color=sr.Color(255,255,255,255)
    for _,p in ipairs(pieces)do
     local a,b,c,d=sr.Vector3(p[1],0,p[2]),sr.Vector3(p[3],0,p[2]),sr.Vector3(p[3],0,p[4]),sr.Vector3(p[1],0,p[4])
     local ua,ub,uc,ud=sr.Vector2(p[1]/w,p[2]/h),sr.Vector2(p[3]/w,p[2]/h),sr.Vector2(p[3]/w,p[4]/h),sr.Vector2(p[1]/w,p[4]/h)
     bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,b,c,M.layer,color,material,ua,ub,uc))
     bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,c,d,M.layer,color,material,ua,uc,ud))
    end
    if bound.late_binding then
     -- Keep at least one assigned primitive alive throughout replacement.
     -- Bind the material that the final retained quad actually owns, after
     -- primitive creation/deletion can initialize its local texture slots.
     for _,id in ipairs(previous)do sr.Gui.destroy_triangle(gui,id)end
     bound.handle=assert(sr.Gui.material(gui,material))
     if depth.bind then local done,err=depth.bind(bound.handle,'diffuse_map',target);assert(done,err)
     else sr.Material.set_resource(bound.handle,'diffuse_map',target)end
     bound.resource=target;bound.resource_identity=depth.binding_identity
     write_parameters()
    end
    bound.draw_key=draw_key
   end
  end)
  if not ok then failed=true;self.release();return false,tostring(why),false end
  if depth.world_applied then depth.world_applied(scope,owner)end
  self.color_binding_identity=color_binding_identity
  self.ui_brightness=ui_brightness
  self.hdr_enabled=hdr_enabled
  self.shader_dof_active,self.scene_active=uniforms.shader_dof_active,uniforms.scene_active
  return true,'Combined resolved '..(hdr_enabled and 'HDR'or 'SDR')..' scene/DoF candidate; GUI highlights limited to UI white',self.shader_dof_active
 end
 return self
end
return M

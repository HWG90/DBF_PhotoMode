-- Private combined candidate. output_target is native graded PQ in HDR/SDR;
-- color; GUI composition uses its actual UI white. Visual proof is still needed.
local M={}
M.shader='mods/dbf_photo/shaders/scene_dof_resolved_v2_8a8fd1f00bd99bfa'
M.material='mods/dbf_photo/materials/scene_dof_resolved_v2_8a8fd1f00bd99bfa'
M.layer=88
M.combined_scene_dof_candidate=true
M.color_target='output_target'
M.color_target_hash=0xa68c78a4
M.color_encoding='pq-bt2020-resolved'
-- Read only the existing renderer map/cache. Calling Renderer.resource on a
-- missing key inserts a target, so this guard deliberately never invokes it.
local function native_color_guard(sr)
 local ffi=require('ffi');local util=require('jit.util')
 pcall(ffi.cdef,[[void *FSC_GetCurrentProcess(void) __asm__("GetCurrentProcess");void *FSC_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");int FSC_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local process=kernel.FSC_GetCurrentProcess()
 local base=tonumber(ffi.cast('uintptr_t',kernel.FSC_GetModuleHandleA(nil)))
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=4096*32,'Combined color target read bounds invalid')
  local buffer=ffi.new('uint8_t[?]',size);local count=ffi.new('size_t[1]')
  assert(kernel.FSC_ReadProcessMemory(process,ffi.cast('void *',address),buffer,size,count)~=0 and tonumber(count[0])==size,'Combined color target read failed')
  return ffi.string(buffer,size)
 end
 local function u32(data,offset)
  local value=ffi.new('uint32_t[1]');ffi.copy(value,data:sub(offset+1,offset+4),4);return tonumber(value[0])
 end
 local function pointer(data,offset)
  local value=ffi.new('uint64_t[1]');ffi.copy(value,data:sub(offset+1,offset+8),8);return tonumber(value[0])
 end
 local function ptr(address)return pointer(read(address,8),0)end
 return function()
  assert(sr.Renderer and type(sr.Renderer.resource)=='function','Renderer resource lookup unavailable')
  assert(util.funcinfo(sr.Renderer.resource).addr==base+0x417cd0,'Renderer resource binding changed')
  assert(read(base+0x417cd0,16)=='\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x40\x45\x33\xc0\x48\x8b\xd9','Renderer resource code changed')
  local renderer=ptr(ptr(base+0x23621a8)+0x338);local map=renderer+0x1600
  local count=u32(read(map,4),0);local active=u32(read(map+0x18,4),0);local buckets=u32(read(map+0x1c,4),0)
  assert(count>0 and count<=4096 and active>0 and active<=count and buckets>0 and buckets<=count,'Combined color target registry invalid')
  local records=read(ptr(map+8),count*32);local found,back_buffer
  for offset=0,#records-32,32 do
   if u32(records,offset+24)~=4294967294 then
    local hash=u32(records,offset)
    if hash==M.color_target_hash then assert(not found,'Combined color target ambiguous');found=pointer(records,offset+8)
    elseif hash==0x2b269c03 then assert(not back_buffer,'Back buffer target ambiguous');back_buffer=pointer(records,offset+8)end
   end
  end
  assert(found and found>=65536 and found<2^47,'Existing resolved output_target unavailable')
  assert(back_buffer and back_buffer>=65536 and back_buffer<2^47 and found~=back_buffer,'Resolved color must be separate from the back buffer')
  read(found,8)
  local backend=ptr(renderer+0x1168);if backend<65536 then backend=ptr(renderer+0x1138)end
  local cache=ptr(backend+0x468)+u32(read(backend+0x478,4),0)*40
  local textures=u32(read(cache,4),0);assert(textures>0 and textures<=4096,'Combined color texture cache invalid')
  local entries=read(ptr(cache+8),textures*24);local backing,back_buffer_backing
  for at=0,#entries-24,24 do
   if u32(entries,at+16)~=4294967294 then
    local key=pointer(entries,at)
    if key==found then assert(not backing,'Resolved color backing ambiguous');backing=pointer(entries,at+8)
    elseif key==back_buffer then assert(not back_buffer_backing,'Back buffer backing ambiguous');back_buffer_backing=pointer(entries,at+8)end
   end
  end
  assert(backing and backing>=65536 and backing<2^47,'Resolved color GPU backing unavailable')
  assert(back_buffer_backing and back_buffer_backing>=65536 and back_buffer_backing<2^47 and backing~=back_buffer_backing,'Resolved color cannot sample the back buffer backing')
  local descriptor=read(backing,36);local id=u32(descriptor,0)
  assert(id%16777216~=16777215,'Resolved color texture ID invalid')
  assert(id~=u32(read(back_buffer_backing,4),0),'Resolved color cannot alias the back buffer GPU texture')
  -- Same existing Lua getter/prefix verified by render_profile.lua. No setter,
  -- Renderer.resource invocation, target insertion or native renderer command.
  local getter=sr.Application and sr.Application.render_setting
  assert(type(getter)=='function','Renderer color settings getter unavailable')
  local address=util.funcinfo(getter).addr
  assert(address==base+0x3fa3d0,'Renderer color settings binding changed')
  assert(read(address,8)=='\x48\x8b\xd1\xe9\x38\xfe\xff\xff','Renderer color settings getter code changed')
  -- Getter body RVA3fa210 uses this global sorted Variant table. Verify its
  -- exact pointer-load instruction and both key types BEFORE any getter call.
  -- Native Variant type1 is float at +8; type4 is boolean at +8.
  assert(read(base+0x3fa262,7)=='\x4c\x8b\x35\x4f\x60\x61\x01','Renderer settings schema binding changed')
  local settings=ptr(base+0x1a102b8);local setting_count=u32(read(settings,4),0)
  assert(setting_count>0 and setting_count<=4096,'Renderer settings schema count invalid')
  local setting_records=read(ptr(settings+8),setting_count*24)
  local hdr_type,white_type
  for at=0,#setting_records-24,24 do
   local key=u32(setting_records,at+16)
   if key==0xbf7ef641 then assert(not hdr_type,'HDR setting schema ambiguous');hdr_type=u32(setting_records,at)
   elseif key==0x3f5fea89 then assert(not white_type,'UI white setting schema ambiguous');white_type=u32(setting_records,at)end
  end
  assert(hdr_type==4 and white_type==1,'Renderer color settings keys/types are not supported')
  local hdr_enabled=getter('hdr_enabled')
  local ui_brightness=getter('ui_brightness')
  return true,{resource=found,backing=backing,id=id,format=u32(descriptor,8),
   width=u32(descriptor,20),height=u32(descriptor,24),mips=u32(descriptor,28),array=u32(descriptor,32),
   hdr_enabled=hdr_enabled,ui_brightness=ui_brightness}
 end
end
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
  scissor={number(o.focus_distance,5,.1,200),number(o.aperture,5.6,1.2,22),number(fov,.9,.02,2.9),shader and 24 or 0},
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
 else local made,value=pcall(native_color_guard,sr);if made then color_guard=value else color_guard_error=tostring(value)end end
 local function present(owner)
  local ok,worlds=pcall(sr.Application.worlds)
  if ok then for _,candidate in pairs(worlds or {})do if owner==candidate then return true end end end
  return false
 end
 function self.ready()
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
  self.ui_brightness=white
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
  local ready,reason=self.ready();if not ready then self.release();return false,reason,false end
  local color_binding_identity=self.color_binding_identity
  local ui_brightness=self.ui_brightness
  uniforms.clip[4]=ui_brightness
  local hdr_enabled=self.hdr_enabled
  local target,reason=depth.get();if not target then self.release();return false,reason,false end
  local main=sr.Application.main_world();local owner
  for _,candidate in pairs(sr.Application.worlds()or {})do if candidate~=main then owner=candidate;break end end
  if not owner then self.release();return false,'Photo UI world unavailable',false end
  local w,h=sr.Gui.resolution()
  if not(w and h and w>0 and h>0)then self.release();return false,'Photo viewport unavailable',false end
  local key=tostring(owner)..'|'..w..'|'..h
  local ok,why=pcall(function()
   if signature~=key then
    local done,err=self.release();assert(done,err)
    world=owner;gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
    bound={handle=assert(sr.Gui.material(gui,M.material))};signature=key
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
    bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,b,c,M.layer,color,M.material,ua,ub,uc))
    bound.ids[#bound.ids+1]=assert(sr.Gui.triangle(gui,a,c,d,M.layer,color,M.material,ua,uc,ud))
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

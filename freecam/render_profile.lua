-- Guarded serialized renderer settings; commands apply asynchronously. No render_config calls.
local M={}
function M.new(sr,world,verify,unit,cam)
 local ffi=require('ffi');local util=require('jit.util')
 pcall(ffi.cdef,[[void *FCR_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FCR_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local buffer=ffi.new('uint8_t[8]');local got=ffi.new('size_t[1]')
 local function guard(f,bytes)
  local address=util.funcinfo(f).addr;if not address then return false end
  return kernel.FCR_ReadProcessMemory(kernel.FCR_GetCurrentProcess(),ffi.cast('void *',address),buffer,8,got)~=0 and tonumber(got[0])==8 and ffi.string(buffer,8)==bytes
 end
 local supported
 if verify then supported=verify(sr)else
  supported=guard(sr.Application.render_setting,'\x48\x8b\xd1\xe9\x38\xfe\xff\xff')and guard(sr.Application.set_render_setting,'\x48\x8b\xd1\xe9\x98\xfb\xff\xff')
 end
 if not supported then return end
 local mapping={dof='dof_enabled',bloom='bloom_enabled'};local self={world=world,unit=unit,cam=cam,parameters={}};local pending={};local frame=0
 for key,name in pairs(mapping)do local ok,value=pcall(sr.Application.render_setting,name);if ok and type(value)=='boolean'then self.parameters[key]=true end end
 local scene
 local function attach_scene()
  if scene or not M.camera_factory then return end
  local ok,value,why=pcall(M.camera_factory.new,sr,world,unit,cam)
  if ok and type(value)=='table'then
   scene=value;self.scene_reason=nil;for key,supported in pairs(scene.parameters or{})do self.parameters[key]=supported end
  else self.scene_reason=tostring(ok and why or value)end
 end
 function self.read(key)
  if not mapping[key]then assert(scene,'Native lens source unavailable');return scene.read(key)end
  local value=sr.Application.render_setting(mapping[key]);assert(type(value)=='boolean','Renderer flag changed type')
  local current=value and 1 or 0;local command=pending[key]
  if command and command.value==current then pending[key]=nil end
  return current
 end
 function self.write(key,value)
  if not mapping[key]then assert(scene,'Native lens source unavailable');return scene.write(key,value)end
  if pending[key]and pending[key].value==value then return end
  if not pending[key]and self.read(key)==value then return end
  sr.Application.set_render_setting(mapping[key],value~=0 and 'true'or 'false')
  pending[key]={value=value,frame=frame}
 end
 function self.restore(key,value)
  if mapping[key]then return self.write(key,value)end
  assert(scene,'Native lens source unavailable');return scene.restore(key,value)
 end
 function self.flush()if scene and scene.flush then scene.flush()end end
 function self.tick()
  frame=frame+1
  for key,command in pairs(pending)do local current=self.read(key)
   if current~=command.value and frame-command.frame>120 then error('Renderer command did not apply: '..key)end
  end
  if scene and scene.tick and scene.tick()==false then
   local done,why=scene.release();assert(done,why)
   for key in pairs(scene.parameters or{})do self.parameters[key]=nil end;scene=nil
  end
  attach_scene();self.native_numeric_candidate=scene and scene.native_numeric_candidate==true or
   (scene==nil and M.camera_factory~=nil and rawget(_G,'DBF_PHOTO_NATIVE_LENS_CANDIDATE')==true)
  self.native_numeric_ready=scene~=nil and self.native_numeric_candidate and(not scene.tick or scene.tick()==true)or false
 end
 function self.pending(key)if key then return pending[key]~=nil end;return next(pending)~=nil end
 attach_scene()

 return self
end
return M

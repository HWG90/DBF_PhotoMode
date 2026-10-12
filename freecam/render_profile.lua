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
 function self.read(key)
  local value=sr.Application.render_setting(assert(mapping[key]));assert(type(value)=='boolean','Renderer flag changed type')
  local current=value and 1 or 0;local command=pending[key]
  if command and command.value==current then pending[key]=nil end
  return current
 end
 function self.write(key,value)
  if pending[key]and pending[key].value==value then return end
  if not pending[key]and self.read(key)==value then return end
  -- The Boolean overload serializes the key slot, not the requested value, on this build.
  -- The string overload directly queues the intended SJSON literal.
  sr.Application.set_render_setting(assert(mapping[key]),value~=0 and 'true'or 'false')
  pending[key]={value=value,frame=frame}
 end
 function self.tick()
  frame=frame+1
  for key,command in pairs(pending)do
   local current=self.read(key)
   if current~=command.value and frame-command.frame>120 then error('Renderer command did not apply: '..key)end
  end
 end
 function self.pending(key)if key then return pending[key]~=nil end;return next(pending)~=nil end
 if M.camera_factory then
  local ok,scene=pcall(M.camera_factory.new,sr,world,unit,cam)
  if ok and scene then
   for key,value in pairs(scene.parameters)do self.parameters[key]=value end
   local flag_read,flag_write=self.read,self.write
   function self.read(key)if mapping[key]then return flag_read(key)end;return scene.read(key)end
   function self.write(key,value)if mapping[key]then return flag_write(key,value)end;return scene.write(key,value)end
   function self.restore(key,value)
    if mapping[key]then return flag_write(key,value)end;return scene.restore(key)
   end
   function self.flush()scene.flush()end
  else self.scene_reason=tostring(scene)end
 end
 return self
end
return M

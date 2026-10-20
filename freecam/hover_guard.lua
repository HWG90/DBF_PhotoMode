-- Keep the native movement guard armed until a resumed update has completed.
-- Native loading and hook installation are lazy and fail closed on build mismatch.
local M={}
local function load_library()
 local ffi=require('ffi')
 ffi.cdef[[
 typedef int (__stdcall *PhotoHoverProtectFn)(void*, size_t, unsigned long, unsigned long*);
 int PHG_VirtualProtect(void*, size_t, unsigned long, unsigned long*) __asm__("VirtualProtect");
 unsigned int PhotoHoverGuardInstall(void);
 unsigned int PhotoHoverGuardInstallWithProtection(PhotoHoverProtectFn);
 unsigned int PhotoHoverGuardArm(unsigned int enabled);
 unsigned long long PhotoHoverGuardSkipped(void);
 unsigned long long PhotoHoverGuardForwarded(void);
 unsigned int PhotoHoverGuardInstalled(void);
 unsigned int PhotoHoverGuardError(void);
 ]]
 local root=assert(rawget(_G,'DBF_PHOTO_PACKAGE_ROOT'),'Photo package path unavailable')
 local file=assert(io.open(root..'/hover-library.txt','rb'),'Hover guard manifest missing')
 local name=file:read('*a');file:close()
 name=assert(name:match('^(PhotoHoverGuard_%x+%.dll)%s*$'),'Invalid hover guard library name')
 local library=ffi.load(root..'/'..name)
 local kernel=ffi.load('kernel32')
 local virtual_protect=kernel.PHG_VirtualProtect
 local protect=function(address,size,requested,previous)
  return virtual_protect(address,size,requested,previous)
 end
 require('jit').off(protect,true)
 local callback=ffi.cast('PhotoHoverProtectFn',protect)
 local api={_library=library,_kernel=kernel,_callback=callback}
 -- The loader supplies the ordinary OS protection call synchronously; the
 -- native installer still owns the complete thread/patch transaction.
 api.PhotoHoverGuardInstall=function()return library.PhotoHoverGuardInstallWithProtection(callback)end
 require('jit').off(api.PhotoHoverGuardInstall,true)
 for _,key in ipairs({'PhotoHoverGuardArm','PhotoHoverGuardSkipped','PhotoHoverGuardForwarded','PhotoHoverGuardInstalled','PhotoHoverGuardError'})do
  api[key]=library[key]
 end
 return api
end
function M.new(loader)
 local self={armed=false,pending=false};local native
 local function failure(why)return false,'Hoverpack pause guard: '..tostring(why)end
 function self.prepare()
  local ok,why=pcall(function()
   native=native or(loader or load_library)()
   assert(native.PhotoHoverGuardInstall()~=0,'Unsupported flight code (error '..tostring(native.PhotoHoverGuardError())..')')
  end)
  if not ok then return failure(why)end
  return true
 end
 function self.acquire()
  local ready,reason=self.prepare();if not ready then return false,reason end
  local ok,why=pcall(function()assert(native.PhotoHoverGuardArm(1)~=0,'Unable to arm flight guard')end)
  if not ok then return failure(why)end
  self.armed=true;self.pending=false;return true
 end
 function self.release()
  -- Policy restoration alone does not prove the last zero-dt frame finished.
  if self.armed then self.pending=true end
  return true
 end
 function self.after_update(delta)
  if not self.pending or type(delta)~='number'or delta~=delta or delta<=0 or delta==math.huge then return true end
  local ok,why=pcall(function()assert(native.PhotoHoverGuardArm(0)~=0,'Unable to release flight guard')end)
  if not ok then return failure(why)end
  self.armed=false;self.pending=false;return true
 end
 function self.state()
  local value={armed=self.armed,pending=self.pending,installed=false,skipped=0,forwarded=0}
  if native then
   local ok,why=pcall(function()
    value.installed=native.PhotoHoverGuardInstalled()~=0
    value.skipped=tonumber(native.PhotoHoverGuardSkipped())
    value.forwarded=tonumber(native.PhotoHoverGuardForwarded())
    value.error=tonumber(native.PhotoHoverGuardError())
   end)
   if not ok then value.error=tostring(why)end
  end
  return value
 end
 self.close=self.release
 return self
end
return M

-- Hide the validated gameplay HUD container; overlays and MCM remain separate.
local M={}
function M.new()
 local ffi=require('ffi');local bit=require('bit')
 pcall(ffi.cdef,[[void *FCH_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");void *FCH_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FCH_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local base=tonumber(ffi.cast('uintptr_t',kernel.FCH_GetModuleHandleA('game.dll')))
 local process=kernel.FCH_GetCurrentProcess();local data=ffi.new('uint8_t[64]');local got=ffi.new('size_t[1]')
 local self={};local native_saved;local custom_saved
 local function read(address,n)
  assert(address>=65536 and address<2^47 and n<=64,'Invalid HUD read')
  assert(kernel.FCH_ReadProcessMemory(process,ffi.cast('void *',address),data,n,got)~=0 and tonumber(got[0])==n,'HUD unreadable')
  return ffi.string(data,n)
 end
 local function pointer(address)local p=ffi.new('uint64_t[1]');ffi.copy(p,read(address,8),8);return tonumber(p[0])end
 local function flag(address)local p=ffi.new('uint32_t[1]');ffi.copy(p,read(address,4),4);return bit.band(tonumber(p[0]),16)~=0 end
 local function identity()
  if base==0 then return end
  local root=pointer(base+0x346d538);local state=pointer(base+0x3326340)
  if root<65536 or state<65536 then return end
  local mode=ffi.new('uint32_t[1]');ffi.copy(mode,read(state+0xac21c,4),4)
  if tonumber(mode[0])~=4 or read(root+0x24e334,1)~='\1' then return end
  local widget=root+0x820
  assert(pointer(widget+0xf0)==root+0x258,'Gameplay HUD parent guard changed')
  assert(read(base+0x144cfb0,32)=='\x48\x83\xec\x28\x44\x8b\x01\x4c\x8b\xd1\x41\x8b\xc0\x45\x8b\xc8\x83\xe0\xef\x41\x83\xc9\x10\x84\xd2\x44\x0f\x44\xc8\x44\x89\x09','HUD visibility binding changed')
  return widget
 end
 local function set(widget,visible)
  ffi.cast('void (*)(uintptr_t, bool)',base+0x144cfb0)(widget,visible)
  assert(flag(widget)==visible,'HUD visibility readback mismatch')
 end
 function self.hold()
  local widget=identity()
  if native_saved and widget~=native_saved.widget then native_saved=nil end
  if widget then if not native_saved then native_saved={widget=widget,visible=flag(widget)}end;if flag(widget)then set(widget,false)end end
  local custom=rawget(_G,'DBFHUD')
  if custom_saved and custom~=custom_saved.hud then custom_saved=nil end
  if custom then if not custom_saved then custom_saved={hud=custom,hidden=custom.hidden,opacity=custom.opacity,photo_hidden=custom.photo_hidden}end;custom.hidden=true;custom.opacity=0;if custom.set_photo_hidden then custom.set_photo_hidden(true)end end
  return true
 end
 function self.release()
  local ok,why=pcall(function()
   if native_saved and identity()==native_saved.widget and not flag(native_saved.widget)then set(native_saved.widget,native_saved.visible)end
   if custom_saved and rawget(_G,'DBFHUD')==custom_saved.hud and custom_saved.hud.hidden==true then custom_saved.hud.hidden=custom_saved.hidden;custom_saved.hud.opacity=custom_saved.opacity;if custom_saved.hud.set_photo_hidden then custom_saved.hud.set_photo_hidden(custom_saved.photo_hidden)end end
  end)
  if not ok then return false,tostring(why)end;native_saved,custom_saved=nil,nil;return true
 end
 return self
end
return M

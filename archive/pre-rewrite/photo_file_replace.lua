-- Legacy LuaJIT filesystem adapter. The preset model itself stays portable.
local M={}
function M.replace(source,target)
 local ffi=require('ffi')
 if ffi.os~='Windows'then return os.rename(source,target)end
 local ok,done=pcall(function()
  pcall(ffi.cdef,[[int PLP_MoveFileExW(const wchar_t*,const wchar_t*,unsigned long) __asm__("MoveFileExW");
   int PLP_MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int) __asm__("MultiByteToWideChar");]])
  local k=ffi.load('kernel32')
  local function wide(s)
   local n=k.PLP_MultiByteToWideChar(65001,8,s,#s,nil,0);assert(n>0,'Invalid preset path')
   local v=ffi.new('wchar_t[?]',n+1)
   assert(k.PLP_MultiByteToWideChar(65001,8,s,#s,v,n)==n,'Preset path conversion failed');return v
  end
  return k.PLP_MoveFileExW(wide(source),wide(target),9)~=0
 end)
 if not ok or not done then return false,'Atomic lighting preset replacement failed'end
 return true
end
return M

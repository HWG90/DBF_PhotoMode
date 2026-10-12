-- Capture after clean frames; the controller temporarily overrides visibility.
local M={}
function M.new(backend,convert,folder,log)
 local self={};local pending;local sequence=0
 function self.active()return pending~=nil end
 function self.request()
  if pending then return false,'Screenshot already pending'end
  assert(backend and convert,'Screenshot backend unavailable')
  local stem
  repeat sequence=sequence+1;stem=folder..'/War Journalist-'..os.date('%Y%m%d-%H%M%S')..'-'..string.format('%03d',sequence);local f=io.open(stem..'.png','rb');if f then f:close()else break end until sequence>100000
  pending={stem=stem,frames=0};return true
 end
 function self.cancel()pending=nil end
 function self.tick()
  if not pending then return end
  pending.frames=pending.frames+1;if pending.frames<12 then return end
  local item=pending;local dds,png=item.stem..'.dds',item.stem..'.png'
  local ok,why=pcall(function()
   local saved,reason=backend.capture(dds);assert(saved,reason)
   self.metadata=type(reason)=='table'and reason or nil
   local converted,reason=convert(dds,png);assert(converted,reason)
   local f=assert(io.open(png,'rb'),'PNG was not written');local signature=f:read(8);f:close();assert(signature=='\137PNG\r\n\26\n','Screenshot is not a PNG')
  end)
  if ok then os.remove(dds)else self.raw_path=dds end;pending=nil
  if ok then self.last_path=png;self.status='Screenshot saved';if log then log('Screenshot saved: '..png)end
  else self.status='Screenshot failed: '..tostring(why);if log then log(self.status)end end
  return ok,self.status
 end
 return self
end
function M.native_converter(path,folder)
 local ffi=require('ffi')
 pcall(ffi.cdef,[[int MultiByteToWideChar(unsigned int,unsigned long,const char *,int,wchar_t *,int);int CreateDirectoryW(const wchar_t *,void *);unsigned long GetLastError(void);int PhotoDDSConvert(const wchar_t *,const wchar_t *);]])
 local kernel=ffi.load('kernel32');local native=ffi.load(path)
 local function wide(value)
  local n=kernel.MultiByteToWideChar(65001,8,value,-1,nil,0);assert(n>0,'Screenshot path invalid')
  local out=ffi.new('wchar_t[?]',n);assert(kernel.MultiByteToWideChar(65001,8,value,-1,out,n)==n,'Screenshot path conversion failed');return out
 end
 kernel.CreateDirectoryW(wide(folder),nil)
 return function(input,output)local result=native.PhotoDDSConvert(wide(input),wide(output));local error_code=kernel.GetLastError();return result==1,'PNG conversion failed ('..tonumber(error_code)..')'end
end
return M

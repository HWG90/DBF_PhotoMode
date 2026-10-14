-- Win32 client-area confinement for the current foreground game process.
-- No cursor warping, input hook, persistent worker, or engine namespace edits.
local M={}
local function valid(r)
 if type(r)~='table'then return false end
 for i=1,4 do local v=r[i];if type(v)~='number'or v~=math.floor(v)or v< -2147483648 or v>2147483647 then return false end end
 return r[1]<r[3]and r[2]<r[4]
end
local function copy(r)return{r[1],r[2],r[3],r[4]}end
local function equal(a,b)return valid(a)and valid(b)and a[1]==b[1]and a[2]==b[2]and a[3]==b[3]and a[4]==b[4]end
function M.new(api)
 if not api then
  local ffi=require('ffi');pcall(ffi.cdef,[[typedef struct {long left,top,right,bottom;} CCB_RECT;typedef struct {long x,y;} CCB_POINT;
   unsigned long CCB_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");void* CCB_GetForegroundWindow(void) __asm__("GetForegroundWindow");
   unsigned long CCB_GetWindowThreadProcessId(void*,unsigned long*) __asm__("GetWindowThreadProcessId");int CCB_IsWindow(void*) __asm__("IsWindow");
   int CCB_GetClientRect(void*,CCB_RECT*) __asm__("GetClientRect");int CCB_ClientToScreen(void*,CCB_POINT*) __asm__("ClientToScreen");
   int CCB_GetClipCursor(CCB_RECT*) __asm__("GetClipCursor");int CCB_ClipCursor(const CCB_RECT*) __asm__("ClipCursor");]])
  local user=ffi.load('user32');local kernel=ffi.load('kernel32');api={}
  local function hwnd(h)return ffi.cast('void*',h)end
  function api.current_pid()return tonumber(kernel.CCB_GetCurrentProcessId())end
  function api.foreground()return tonumber(ffi.cast('uintptr_t',user.CCB_GetForegroundWindow()))end
  function api.valid_window(h)return user.CCB_IsWindow(hwnd(h))~=0 end
  function api.pid(h)local pid=ffi.new('unsigned long[1]');assert(user.CCB_GetWindowThreadProcessId(hwnd(h),pid)~=0,'Window process lookup unavailable');return tonumber(pid[0])end
  function api.client(h)local r=ffi.new('CCB_RECT[1]');assert(user.CCB_GetClientRect(hwnd(h),r)~=0,'Game client bounds unavailable');return{tonumber(r[0].left),tonumber(r[0].top),tonumber(r[0].right),tonumber(r[0].bottom)}end
  function api.to_screen(h,x,y)local p=ffi.new('CCB_POINT[1]');p[0].x=x;p[0].y=y;assert(user.CCB_ClientToScreen(hwnd(h),p)~=0,'Game screen bounds unavailable');return tonumber(p[0].x),tonumber(p[0].y)end
  function api.get_clip()local r=ffi.new('CCB_RECT[1]');assert(user.CCB_GetClipCursor(r)~=0,'Cursor clip readback unavailable');return{tonumber(r[0].left),tonumber(r[0].top),tonumber(r[0].right),tonumber(r[0].bottom)}end
  function api.set_clip(value)
   local r;if value then r=ffi.new('CCB_RECT[1]');r[0].left=value[1];r[0].top=value[2];r[0].right=value[3];r[0].bottom=value[4]end
   assert(user.CCB_ClipCursor(r)~=0,'Cursor confinement refused');return true
  end
 end
 local pid=api.current_pid();assert(type(pid)=='number'and pid>0,'Game process identity unavailable')
 local self={}
 function self.valid_window(h)
  local ok,value=pcall(function()if not api.valid_window(h)then return false end;return api.pid(h)==pid end)
  if not ok then return nil,tostring(value)end;return value
 end
 function self.window()
  local ok,value,why=pcall(function()
   local h=api.foreground();if not h or h==0 then return nil,'focus_lost'end
   if not api.valid_window(h)then return nil,'window_retired'end
   if api.pid(h)~=pid then return nil,'focus_lost'end
   local c=api.client(h);assert(valid(c),'Game client rectangle invalid')
   local left,top=api.to_screen(h,c[1],c[2]);local right,bottom=api.to_screen(h,c[3],c[4]);local r={left,top,right,bottom}
   assert(valid(r),'Game screen rectangle invalid')
   return{window=h,pid=pid,rect=r}
  end)
  if not ok then return nil,'unavailable: '..tostring(value)end;return value,why
 end
 function self.clip()local r=api.get_clip();assert(valid(r),'Cursor clip rectangle invalid');return copy(r)end
 function self.write(target,expected,window)
  local committed=false
  local ok,value=pcall(function()
   assert(target==nil or valid(target),'Invalid cursor confinement target')
   if window then local current,why=self.window();assert(current and current.window==window and equal(current.rect,target),why or'Game window changed')end
   assert(equal(self.clip(),expected),'Cursor clip changed by another writer')
   assert(api.set_clip(target)==true,'Cursor confinement refused');committed=true
   local actual=self.clip();assert(target==nil or equal(actual,target),'Cursor confinement readback mismatch');return actual
  end)
  if not ok then return false,tostring(value),committed end
  return true,value,committed
 end
 return self
end
M.equal=equal;M.valid=valid
return M

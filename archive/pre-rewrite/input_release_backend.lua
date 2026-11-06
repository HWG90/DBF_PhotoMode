-- Photo-only release events. SendInput acceptance is not an engine-state reset:
-- the caller must read Keyboard/Mouse.button again on a later game update.
local M={}
local mouse={[1]={4,0},[2]={16,0},[4]={64,0},[5]={256,1},[6]={256,2}}
local names={backspace=8,tab=9,enter=13,return_key=13,shift=16,ctrl=17,control=17,alt=18,pause=19,capslock=20,escape=27,esc=27,space=32,pageup=33,pagedown=34,['end']=35,home=36,left=37,up=38,right=39,down=40,printscreen=44,insert=45,delete=46,leftwin=91,rightwin=92,apps=93,numlock=144,scrolllock=145,leftshift=160,rightshift=161,leftctrl=162,rightctrl=163,leftcontrol=162,rightcontrol=163,leftalt=164,rightalt=165,semicolon=186,equals=187,comma=188,minus=189,period=190,slash=191,grave=192,leftbracket=219,backslash=220,rightbracket=221,apostrophe=222}
local mouse_names={left=1,leftbutton=1,right=2,rightbutton=2,middle=4,middlebutton=4,x1=5,xbutton1=5,button4=5,x2=6,xbutton2=6,button5=6}
local function integer(v,lo,hi)return type(v)=='number'and v==math.floor(v)and v>=lo and v<=hi end
local function normal(name)return type(name)=='string'and name:lower():gsub('[%s_%-]','')or''end
local function vk(device,name)
 local n=normal(name);if device=='Mouse'then return mouse_names[n]end
 if #n==1 then local b=n:byte();if b>=97 and b<=122 then return b-32 elseif b>=48 and b<=57 then return b end end
 local f=n:match('^f(%d+)$');if f and integer(tonumber(f),1,24)then return 111+tonumber(f)end
 local d=n:match('^numpad(%d)$')or n:match('^num(%d)$');if d then return 96+tonumber(d)end
 if n=='return'then return 13 end;return names[n]
end
local function keys_sorted(keys)
 local out={};for k,value in pairs(keys)do assert(integer(k,1,254)and value==true,'Invalid cached input');if not((k==16 and(keys[160]or keys[161]))or(k==17 and(keys[162]or keys[163]))or(k==18 and(keys[164]or keys[165])))then out[#out+1]=k end end
 table.sort(out);return out
end
local function cdef(ffi)
 if not pcall(ffi.typeof,'IR_INPUT')then ffi.cdef[[
 typedef struct {long dx,dy;unsigned long mouseData,dwFlags,time;uintptr_t dwExtraInfo;} IR_MOUSEINPUT;
 typedef struct {unsigned short wVk,wScan;unsigned long dwFlags,time;uintptr_t dwExtraInfo;} IR_KEYBDINPUT;
 typedef struct {unsigned long uMsg;unsigned short wParamL,wParamH;} IR_HARDWAREINPUT;
 typedef struct {unsigned long type;union {IR_MOUSEINPUT mi;IR_KEYBDINPUT ki;IR_HARDWAREINPUT hi;};} IR_INPUT;
 typedef struct {long x,y;} IR_POINT;typedef struct {long left,top,right,bottom;} IR_RECT;
 unsigned long IR_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");unsigned long long IR_GetTickCount64(void) __asm__("GetTickCount64");
 void* IR_GetForegroundWindow(void) __asm__("GetForegroundWindow");unsigned long IR_GetWindowThreadProcessId(void*,unsigned long*) __asm__("GetWindowThreadProcessId");
 int IR_IsWindow(void*) __asm__("IsWindow");short IR_GetAsyncKeyState(int) __asm__("GetAsyncKeyState");
 unsigned int IR_MapVirtualKeyW(unsigned int,unsigned int) __asm__("MapVirtualKeyW");unsigned int IR_SendInput(unsigned int,IR_INPUT*,int) __asm__("SendInput");
 int IR_GetCursorPos(IR_POINT*) __asm__("GetCursorPos");int IR_GetClientRect(void*,IR_RECT*) __asm__("GetClientRect");int IR_ClientToScreen(void*,IR_POINT*) __asm__("ClientToScreen");
 ]]end
 pcall(ffi.cdef,[[void* IR_WindowFromPoint(IR_POINT) __asm__("WindowFromPoint");]])
end
-- Pure encoder also exercised by the fixture: all events are UP, never motion,
-- wheel, DOWN, or Unicode text. Scan codes preserve the physical key identity.
function M.encode(ffi,list,map)
 cdef(ffi);local out=ffi.new('IR_INPUT[?]',#list)
 for i,k in ipairs(list)do
  assert(integer(k,1,254),'Invalid release key');local m=mouse[k];local e=out[i-1]
  if m then e.type=0;e.mi.dwFlags=m[1];e.mi.mouseData=m[2]
  else
   e.type=1;e.ki.wVk=k;e.ki.dwFlags=2
   local scan=map and map(k)or 0;assert(integer(scan,0,65535),'Invalid scan code')
   local prefix=math.floor(scan/256)
   if scan>0 and(prefix==0 or prefix==224)then e.ki.wVk=0;e.ki.wScan=scan%256;e.ki.dwFlags=10+(prefix==224 and 1 or 0)end
  end
 end
 return out,ffi.sizeof('IR_INPUT')
end
local function win32()
 local ffi=require('ffi');cdef(ffi);local user=ffi.load('user32');local kernel=ffi.load('kernel32');local api={}
 local function h(value)return ffi.cast('void*',value)end
 function api.current_pid()return tonumber(kernel.IR_GetCurrentProcessId())end
 function api.now()return tonumber(kernel.IR_GetTickCount64())/1000 end
 function api.foreground()return tonumber(ffi.cast('uintptr_t',user.IR_GetForegroundWindow()))end
 function api.valid_window(value)return user.IR_IsWindow(h(value))~=0 end
 function api.pid(value)local pid=ffi.new('unsigned long[1]');assert(user.IR_GetWindowThreadProcessId(h(value),pid)~=0,'Input window lookup failed');return tonumber(pid[0])end
 function api.down(k)return user.IR_GetAsyncKeyState(k)<0 end
 function api.mouse_inside(value)
  local p=ffi.new('IR_POINT[1]');local r=ffi.new('IR_RECT[1]');local a=ffi.new('IR_POINT[1]');local b=ffi.new('IR_POINT[1]')
  assert(user.IR_GetCursorPos(p)~=0 and user.IR_GetClientRect(h(value),r)~=0,'Mouse destination read failed')
  a[0].x=r[0].left;a[0].y=r[0].top;b[0].x=r[0].right;b[0].y=r[0].bottom
  assert(user.IR_ClientToScreen(h(value),a)~=0 and user.IR_ClientToScreen(h(value),b)~=0,'Mouse destination bounds failed')
  if not(p[0].x>=a[0].x and p[0].x<b[0].x and p[0].y>=a[0].y and p[0].y<b[0].y)then return false end
  local target=user.IR_WindowFromPoint(p[0]);if target==nil then return false end
  local target_pid=ffi.new('unsigned long[1]');assert(user.IR_GetWindowThreadProcessId(target,target_pid)~=0,'Mouse destination identity failed')
  return tonumber(target_pid[0])==api.current_pid()
 end
 function api.send(list)local events,size=M.encode(ffi,list,function(k)return tonumber(user.IR_MapVirtualKeyW(k,4))end);return tonumber(user.IR_SendInput(#list,events,size))end
 return api
end
function M.new(sr,api)
 api=api or win32();local pid=api.current_pid();assert(integer(pid,1,4294967295),'Input process identity unavailable');local self={}
 function self.now()return api.now()end
 function self.owner()
  local ok,value,why=pcall(function()
   local h=api.foreground();if not h or h==0 then return nil,'focus_lost'end
   if not api.valid_window(h)then return nil,'window_retired'end
   if api.pid(h)~=pid then return nil,'focus_lost'end
   return{window=h,pid=pid}
  end)
  if not ok then return nil,'unavailable: '..tostring(value)end;return value,why
 end
 local function same(expected)local current,why=self.owner();return current and expected and current.window==expected.window and current.pid==expected.pid,why or'Game input window changed'end
 local function sdk_snapshot()
  local buttons={};local unavailable={};local mapped={}
  for _,device in ipairs({'Keyboard','Mouse'})do
   local d=sr and sr[device];local ok,result=pcall(function()
    assert(type(d)=='table'and type(d.num_buttons)=='function'and type(d.button)=='function'and type(d.button_name)=='function'and type(d.active)=='function','Button read API unavailable')
    assert(d.active()==true,'Device is inactive');local count=d.num_buttons();assert(integer(count,0,device=='Keyboard'and 512 or 32),'Invalid button count')
    local held={};for i=0,count-1 do local value=d.button(i);assert(type(value)=='number'and value==value,'Invalid button state');if value~=0 then local name=d.button_name(i);assert(type(name)=='string','Invalid button name');held[#held+1]={device=device,index=i,name=name};local key=vk(device,name);if key then mapped[key]=true end end end
    return held
   end)
   if ok then for _,entry in ipairs(result)do buttons[#buttons+1]=entry end else unavailable[#unavailable+1]=device..': '..tostring(result)end
  end
  local why;if #unavailable>0 then why=table.concat(unavailable,'; ')end;return buttons,mapped,why
 end
 function self.snapshot(expected)
  local owner,why=self.owner();if not owner then return nil,why end
  if expected and(owner.window~=expected.window or owner.pid~=expected.pid)then return nil,'window_retired'end
  local ok,value=pcall(function()
   local keys={};for k=1,254 do local down=api.down(k);assert(type(down)=='boolean','Physical input read unavailable');if down then keys[k]=true end end
   local buttons,mapped,unavailable=sdk_snapshot();for k in pairs(mapped)do keys[k]=true end
   assert(same(owner),'Game lost focus during input snapshot')
   return{owner=owner,keys=keys,buttons=buttons,unavailable=unavailable}
  end)
  if not ok then return nil,'unavailable: '..tostring(value)end;return value
 end
 function self.send(expected,keys)
  local accepted=0;local ok,why=pcall(function()
   local sorted=keys_sorted(keys);local groups={{},{}};for _,k in ipairs(sorted)do local group=mouse[k]and groups[2]or groups[1];group[#group+1]=k end
   -- Small batches permit a foreground/process check between batches. Mouse UP
   -- is additionally restricted to the game client, since its target is spatial.
   for _,list in ipairs(groups)do for first=1,#list,8 do
    local good,reason=same(expected);assert(good,reason);local batch={}
    for i=first,math.min(first+7,#list)do local k=list[i];if mouse[k]then assert(api.mouse_inside(expected.window)==true,'Mouse is outside game client')end;batch[#batch+1]=k end
    good,reason=same(expected);assert(good,reason)
    local sent=api.send(batch);assert(integer(sent,0,#batch),'Invalid release acceptance');accepted=accepted+sent;assert(sent==#batch,'Input release events were refused')
   end end
  end)
  if not ok then return false,tostring(why),accepted end;return true,nil,accepted
 end
 function self.verify(expected,buttons)
  local good,why=same(expected);if not good then return nil,why end
  local ok,value,reason=pcall(function()
   for _,device in ipairs({'Keyboard','Mouse'})do local d=sr and sr[device];assert(d and type(d.active)=='function'and d.active()==true,device..' is inactive')end
   local held={};for _,entry in pairs(buttons)do local d=sr[entry.device];assert(d.button_name(entry.index)==entry.name,'Input button identity changed');local v=d.button(entry.index);assert(type(v)=='number'and v==v,'Button state unavailable');if v~=0 then held[#held+1]=entry.device..'.'..entry.name end end
   assert(same(expected),'Game lost focus during button readback')
   return #held==0,#held>0 and table.concat(held,', ')or nil
  end)
  if not ok then return nil,tostring(value)end;return value,reason
 end
 return self
end
M.key_for=vk;M.keys_sorted=keys_sorted
return M

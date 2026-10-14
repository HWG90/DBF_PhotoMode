-- Private settings/input/rendering service. Does not publish or impersonate DBFMCM.
local M={}
function M.input(host,sr,available,parent)
 local ffi=require('ffi');local bit=require('bit')
 pcall(ffi.cdef,[[
  typedef struct {long x;long y;} SS_POINT;
  short SS_GetAsyncKeyState(int) __asm__("GetAsyncKeyState");void *SS_GetForegroundWindow(void) __asm__("GetForegroundWindow");
  int SS_GetCursorPos(SS_POINT *) __asm__("GetCursorPos");int SS_ScreenToClient(void *,SS_POINT *) __asm__("ScreenToClient");
  int SS_GetClientRect(void *,long *) __asm__("GetClientRect");unsigned long SS_GetWindowThreadProcessId(void *,unsigned long *) __asm__("GetWindowThreadProcessId");
  unsigned long SS_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
  int mcm_install(void *);int mcm_capture(int);int mcm_captured(void);void mcm_release(void);
  int mcm_wheel(void);int mcm_mouse_x(void);int mcm_mouse_y(void);double mcm_seconds(void);
 ]])
 if not pcall(ffi.typeof,'MCM_PHOTO_SESSION')then ffi.cdef[[
  typedef struct {int session_present,other_peers,joining_peers,connections;} MCM_PHOTO_SESSION;
  typedef void (*MCM_PHOTO_QUERY)(MCM_PHOTO_SESSION *);typedef int (*MCM_PHOTO_APPLY)(void);
  int mcm_photo_pause_allowed(MCM_PHOTO_QUERY);int mcm_photo_pause(MCM_PHOTO_QUERY,MCM_PHOTO_APPLY);
 ]]end
 local user=ffi.load('user32');local kernel=ffi.load('kernel32');local pid=kernel.SS_GetCurrentProcessId()
 local dll=assert(host.read('standalone-library.txt')):match('^(mcm_input_%x+%.dll)%s*$');assert(dll,'Standalone input manifest invalid')
 pcall(ffi.cdef,'int mcm_escape_passthrough(void);')
 local native=ffi.load(host.dir..'/'..dll)
 assert(native.mcm_escape_passthrough()==1,'Photo input Escape policy unavailable')
 pcall(ffi.cdef,'int mcm_load_menu_cursor(const char*);void *mcm_menu_cursor(void);')
 local cursor_ok,cursor_loaded=pcall(function()return native.mcm_load_menu_cursor(host.dir..'/assets/helldivers_cursor.cur')~=0 end)
 local capture=host.require('src/photo_input_capture.lua').new(sr.Window,parent)
 local input={};local hwnd;local point=ffi.new('SS_POINT[1]');local rect=ffi.new('long[4]');local owner=ffi.new('unsigned long[1]')
 function input.poll()
  hwnd=user.SS_GetForegroundWindow();user.SS_GetWindowThreadProcessId(hwnd,owner);if owner[0]~=pid then hwnd=nil end
 end
 function input.down(key)return hwnd~=nil and bit.band(tonumber(user.SS_GetAsyncKeyState(key)),0x8000)~=0 end
 function input.focused()return hwnd~=nil end;function input.window()return hwnd end
 function input.now()return tonumber(native.mcm_seconds())end
 function input.wheel()return tonumber(native.mcm_wheel())end
 function input.look()return tonumber(native.mcm_mouse_x()),tonumber(native.mcm_mouse_y())end
 function input.lock_aim()sr.Window.set_mouse_focus(false);return sr.Window.mouse_focus()==false end
 function input.menu_cursor(menu)
  sr.Window.set_mouse_focus(false);sr.Window.set_show_cursor(menu);sr.Window.set_clip_cursor(true)
  return sr.Window.mouse_focus()==false and sr.Window.show_cursor()==menu and sr.Window.clip_cursor()==true
 end
 function input.mouse()
  if not hwnd or user.SS_GetCursorPos(point)==0 or user.SS_ScreenToClient(hwnd,point)==0 or user.SS_GetClientRect(hwnd,rect)==0 then return end
  local w,h=sr.Gui.resolution();local cw,ch=tonumber(rect[2]),tonumber(rect[3]);if cw<=0 or ch<=0 then return end
  return tonumber(point[0].x)*w/cw,h-tonumber(point[0].y)*h/ch
 end
 local function count(t)assert(type(t)=='table');local n=0;for _ in pairs(t)do n=n+1 end;return n end
 input.photo_check=ffi.cast('MCM_PHOTO_QUERY',function(state)
  state.session_present=-1;state.other_peers=-1;state.joining_peers=-1;state.connections=-1
  pcall(function()
   local N,G=assert(sr.Network),assert(sr.GameSession);local session=N.game_session()
   if session then local peers=count(G.other_peers(session));local joining=count(G.synchronizing_peers(session));state.other_peers=peers;state.joining_peers=joining;state.session_present=1
   else state.connections=count(N.connections());state.session_present=0 end
  end)
 end)
 function input.photo_apply(apply)
  local reason;local callback=ffi.cast('MCM_PHOTO_APPLY',function()local ok,why=pcall(apply);if not ok then reason=tostring(why)end;return ok and 1 or 0 end)
  local ok,result=pcall(native.mcm_photo_pause,input.photo_check,callback);callback:free()
  return ok and result~=0,reason or 'Simulation control requires a verified solo session'
 end
 jit.off(input.photo_apply,true)
 local camera=host.require('src/vendor/camera_input.lua').new(native,capture,input,function()
  local loader=rawget(_G,'LiveLuaLoader');local status=loader and loader.input_status and loader.input_status()
  if status and(status.owner or status.active or status.pending_restore)then return false end
  if available then local ok,ready=pcall(available);return ok and ready==true end
  return true
 end)
 camera.native_escape_passthrough=true;camera.photo_input_owner='War Journalist'
 camera.cursor_graphic=cursor_ok and cursor_loaded and 'Helldivers'or 'Windows arrow'
 return camera
end
function M.shared(host,sr,mcm)
 assert(type(mcm)=='table'and type(mcm.is_open)=='function'and type(mcm.input_status)=='function','MCM input ownership reader unavailable')
 local facade=setmetatable({photo_standalone=false,photo_input_parent=mcm},{__index=mcm})
 local function parent()
  if rawget(_G,'DBFMCM')~=mcm then return nil,'MCM input provider changed'end
  local status=mcm.input_status()
  if type(status)~='table'or type(status.active)~='boolean'or type(status.pending_restore)~='boolean'then return nil,'MCM input ownership unavailable'end
  local open=mcm.is_open()
  if type(open)~='boolean'then return nil,'MCM menu ownership unavailable'end
  return open or status.owner~=nil or status.active or status.pending_restore
 end
 facade.camera_input=M.input(host,sr,function()return parent()==false end,parent)
 return facade
end
function M.new(host,sr)
 local ffi=require('ffi')
 local core=host.require('src/vendor/core.lua');local store=host.require('src/vendor/store.lua').new(assert(host.config_dir,'Photo settings directory unavailable'))
 local api=core.new(store,host.log);api.photo_standalone=true
 api.is_open=function()return false end;api.close=function()return true end
 api.camera_input=M.input(host,sr)
 api.photo_resolution=function()return sr.Gui.resolution()end
 local view_factory=host.require('src/vendor/view.lua')
 function api.create_photo_view()
  local view=view_factory.new(sr,nil,host.log)
  pcall(function()
   local runtime=host.require('src/vendor/bingus_runtime.lua');local memory=host.require('src/vendor/bingus_memory.lua').new(runtime)
   view.set_font_source(host.require('src/vendor/font.lua').new(memory,'game.dll',function(a)return ffi.cast('void *',a)end))
  end)
  return view
 end
 return api
end
return M

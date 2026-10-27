-- Private settings/input/rendering service. Does not publish or impersonate DBFMCM.
local M={}
local function inactive()return{open=false,active=false,pending_restore=false,available=true,claimed=false}end
local function normalized(value,label,open,inactive_fallback)
 if type(value)~='table'or type(value.active)~='boolean'or(value.owner~=nil and type(value.owner)~='string')then
  return nil,label..' input ownership unavailable'
 end
 local pending=value.pending_restore
 if pending==nil and inactive_fallback and value.active==false and value.owner==nil then
  local exact=true;for key in pairs(value)do if key~='active'then exact=false end end
  if exact then pending=false end
 end
 if type(pending)~='boolean'or type(open)~='boolean'then return nil,label..' input ownership unavailable'end
 local active=value.active;local owner=value.owner
 return{open=open,active=active,pending_restore=pending,owner=owner,claimed=active or pending or owner~=nil,
  available=not(open or active or pending or owner~=nil)}
end
function M.epic_status(front)
 if front==nil then return inactive()end
 if type(front)~='table'then return nil,'Epic LUT frontend ownership unavailable'end
 local called,value
 if type(front.input_status)=='function'then
  called,value=pcall(front.input_status)
 elseif front.input_status~=nil then return nil,'Epic LUT input ownership reader unavailable'
 elseif type(front.capture)=='table'and type(front.capture.status)=='function'then
  called,value=pcall(front.capture.status)
 else return nil,'Epic LUT input ownership reader unavailable'end
 if not called then return nil,'Epic LUT input ownership read failed: '..tostring(value)end
 local open;if type(value)=='table'then open=value.open end
 if open==nil and type(front.menu)=='table'then open=front.menu.visible end
 return normalized(value,'Epic LUT',open,false)
end
function M.external_status(globals)
 globals=globals or _G
 if type(globals)~='table'then return nil,'External input globals unavailable'end
 local result=inactive();result.owners={};result.providers={}
 local function include(value,label)
  result.open=result.open or value.open;result.active=result.active or value.active
  result.pending_restore=result.pending_restore or value.pending_restore
  if not value.available then result.available=false end
  if value.claimed then result.claimed=true;result.providers[label]=true;result.owners[#result.owners+1]=value.owner or label end
 end
 local loader=rawget(globals,'LiveLuaLoader')
 if loader~=nil then
  if type(loader)~='table'or type(loader.input_status)~='function'then return nil,'LLL input ownership reader unavailable'end
  local called,value=pcall(loader.input_status)
  if not called then return nil,'LLL input ownership read failed: '..tostring(value)end
  local open=false;if type(value)=='table'and value.open~=nil then open=value.open end
  local state,why=normalized(value,'LLL',open,true)
  if not state then return nil,why end;include(state,'LLL')
 end
 -- A private Photo service can predate MCM. Read the current public provider
 -- each time instead of relying only on the parent captured during startup.
 local mcm=rawget(globals,'DBFMCM')
 if mcm~=nil then
  if type(mcm)~='table'or type(mcm.input_status)~='function'or type(mcm.is_open)~='function'then return nil,'MCM input ownership reader unavailable'end
  local called,value=pcall(mcm.input_status);local opened,open=pcall(mcm.is_open)
  if not called or not opened then return nil,'MCM input ownership read failed'end
  local state,why=normalized(value,'MCM',open,true)
  if not state then return nil,why end;result.mcm=state;include(state,'MCM')
 end
 local packages=rawget(globals,'package')
 if type(packages)~='table'or type(packages.loaded)~='table'then return nil,'Epic LUT registry unavailable'end
 local epic,why=M.epic_status(rawget(packages.loaded,'dbf.epic_lut.frontend.v1'))
 if not epic then return nil,why end;include(epic,'Epic LUT')
 result.owner=result.owners[1]
 return result
end
-- The same ownership/recovery implementation is injectable for isolated tests;
-- production binds it to the real Camera service and this Photo helper only.
function M.ownership(available,parent,globals)
 local self={};globals=globals or _G
 function self.external_status()
  local state,why=M.external_status(globals);if not state then return nil,why end
  if parent then
   local called,active,reason=pcall(parent)
   if not called or type(active)~='boolean'then return nil,called and(reason or'Parent input ownership unavailable')or tostring(active)end
   if active then
    state.available=false
    local claimed=true
    if type(reason)=='table'then
     local detail,problem=normalized(reason,'Parent',reason.open,false)
     if not detail then return nil,problem end
     if state.mcm then
      for _,key in ipairs({'open','active','pending_restore','owner'})do
       if state.mcm[key]~=detail[key]then return nil,'MCM input ownership changed during observation'end
      end
     end
     claimed=detail.claimed;state.open=state.open or detail.open
    end
    if claimed then
     state.active=true;state.claimed=true
     if not state.providers.MCM then state.providers.MCM=true;state.owners[#state.owners+1]='MCM' end
     state.owner=state.owner or'MCM'
    end
   end
  end
  return state
 end
 function self.parent()
  local state,why=self.external_status();if not state then return nil,why end
  return not state.available,state.owner
 end
 function self.restore_parent()
  local state,why=self.external_status();if not state then return nil,why end
  return state.claimed,state.owner
 end
 function self.available()
  local active=self.parent();if active~=false then return false end
  if available then local called,value=pcall(available);return called and value==true end
  return true
 end
 function self.attach(camera,native,input)
  camera.external_status=self.external_status
  local function preflight()
   local external,reason=self.external_status();assert(external and external.available==true,reason or'An external editor owns input')
   local state=camera.status();assert(type(state)=='table','Photo input ownership unavailable')
   assert(state.active==false and state.owned==false and state.cleanup_pending==false,'Photo input lease must be released before recovery')
   assert(state.available==true,'Photo input recovery is blocked by another owner')
   assert(type(state.native_mode)=='number'and state.native_mode>=0 and state.native_mode<=3 and state.native_mode%1==0,'Photo native input state unavailable')
   input.poll();assert(state.focused==true and input.focused()==true,'Focus the game before input recovery')
   for _,name in ipairs({'native_menu_active','chat_active'})do
    assert(type(camera[name])=='function'and camera[name]()==false,'Close native menus and chat before input recovery')
   end
   assert(type(camera.native_menu_resume)=='function','Native menu cursor recovery unavailable')
  end
  function camera.recover_native()
   local called,done=pcall(function()
    preflight()
    native.mcm_release()
    assert(tonumber(native.mcm_captured())==0,'Photo native input release readback failed')
    assert(camera.native_menu_resume()==true,'Native menu cursor restoration is pending')
    preflight() -- A new editor/focus transition cannot grant recovery success.
    return true
   end)
   if not called then return false,tostring(done)end
   return done==true
  end
  return camera
 end
 return self
end
-- The engine's clip flag is insufficient with gameplay mouse focus disabled.
-- Use client coordinates translated to screen space, including negative monitors.
function M.cursor_clip(user,ffi,input)
 local rect=ffi.new('long[4]');local points=ffi.new('SS_POINT[2]')
 local self={focused=input.focused}
 function self.current()
  if user.SS_GetClipCursor(rect)==0 then return end
  return{tonumber(rect[0]),tonumber(rect[1]),tonumber(rect[2]),tonumber(rect[3])}
 end
 function self.client()
  local hwnd=input.window();if not hwnd or user.SS_GetClientRect(hwnd,rect)==0 then return end
  points[0].x=rect[0];points[0].y=rect[1];points[1].x=rect[2];points[1].y=rect[3]
  if user.SS_ClientToScreen(hwnd,points)==0 or user.SS_ClientToScreen(hwnd,points+1)==0 then return end
  return{tonumber(points[0].x),tonumber(points[0].y),tonumber(points[1].x),tonumber(points[1].y)}
 end
 function self.apply(bounds)
  if not bounds then return user.SS_ClipCursor(nil)~=0 end
  for i=0,3 do rect[i]=bounds[i+1]end
  return user.SS_ClipCursor(rect)~=0
 end
 return self
end
function M.input(host,sr,available,parent)
 local ownership=M.ownership(available,parent,_G)
 local ffi=require('ffi');local bit=require('bit')
 pcall(ffi.cdef,[[
  typedef struct {long x;long y;} SS_POINT;
  short SS_GetAsyncKeyState(int) __asm__("GetAsyncKeyState");void *SS_GetForegroundWindow(void) __asm__("GetForegroundWindow");
  int SS_GetCursorPos(SS_POINT *) __asm__("GetCursorPos");int SS_ScreenToClient(void *,SS_POINT *) __asm__("ScreenToClient");
  int SS_GetClientRect(void *,long *) __asm__("GetClientRect");unsigned long SS_GetWindowThreadProcessId(void *,unsigned long *) __asm__("GetWindowThreadProcessId");
  int SS_ClientToScreen(void *,SS_POINT *) __asm__("ClientToScreen");
  int SS_GetClipCursor(long *) __asm__("GetClipCursor");int SS_ClipCursor(const long *) __asm__("ClipCursor");
  unsigned int SS_GetDoubleClickTime(void) __asm__("GetDoubleClickTime");int SS_GetSystemMetrics(int) __asm__("GetSystemMetrics");
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
 pcall(ffi.cdef,[[
  typedef struct {double seconds;int x;int y;int button;int down;} MCM_CLICK_EVENT;
  int mcm_next_click(MCM_CLICK_EVENT *);int mcm_cursor_confinement(void);
 ]])
 local native_clip_ok,native_clip=pcall(function()return native.mcm_cursor_confinement()==1 end)
 local native_click_ok=pcall(function()return native.mcm_next_click end)
 pcall(ffi.cdef,'int mcm_load_menu_cursor(const char*);void *mcm_menu_cursor(void);')
 local cursor_ok,cursor_loaded=pcall(function()return native.mcm_load_menu_cursor(host.dir..'/assets/helldivers_cursor.cur')~=0 end)
 local input={};local hwnd;local point=ffi.new('SS_POINT[1]');local rect=ffi.new('long[4]');local owner=ffi.new('unsigned long[1]')
 function input.poll()
  hwnd=user.SS_GetForegroundWindow();user.SS_GetWindowThreadProcessId(hwnd,owner);if owner[0]~=pid then hwnd=nil end
 end
 function input.down(key)return hwnd~=nil and bit.band(tonumber(user.SS_GetAsyncKeyState(key)),0x8000)~=0 end
 function input.focused()return hwnd~=nil end;function input.window()return hwnd end
 local capture=host.require('src/photo_input_capture.lua').new(sr.Window,ownership.restore_parent,not(native_clip_ok and native_clip)and M.cursor_clip(user,ffi,input)or nil)
 function input.now()return tonumber(native.mcm_seconds())end
 pcall(ffi.cdef,'int mcm_gameplay_wheel(int);')
 function input.gameplay_wheel(enabled)return tonumber(native.mcm_gameplay_wheel(enabled and 1 or 0))end
 function input.wheel()return tonumber(native.mcm_wheel())end
 function input.look()return tonumber(native.mcm_mouse_x()),tonumber(native.mcm_mouse_y())end
 function input.double_click_limits(w,h)
  if not hwnd or user.SS_GetClientRect(hwnd,rect)==0 then return .5,8,8 end
  local cw,ch=tonumber(rect[2]-rect[0]),tonumber(rect[3]-rect[1]);if cw<=0 or ch<=0 then return .5,8,8 end
  if not w or not h then w,h=sr.Gui.resolution()end
  return tonumber(user.SS_GetDoubleClickTime())/1000,math.max(8,tonumber(user.SS_GetSystemMetrics(36))*w/cw/2),math.max(8,tonumber(user.SS_GetSystemMetrics(37))*h/ch/2)
 end
 if native_click_ok then
  local event=ffi.new('MCM_CLICK_EVENT[1]')
  function input.click_events()
   local events={};if not hwnd or user.SS_GetClientRect(hwnd,rect)==0 then return events end
   local cw,ch=tonumber(rect[2]-rect[0]),tonumber(rect[3]-rect[1]);if cw<=0 or ch<=0 then return events end
   local w,h=sr.Gui.resolution();local now=input.now()
   for _=1,64 do
    if native.mcm_next_click(event)==0 then break end
    events[#events+1]={age=math.max(0,now-tonumber(event[0].seconds)),x=tonumber(event[0].x)*w/cw,y=h-tonumber(event[0].y)*h/ch,button=tonumber(event[0].button),click=event[0].down~=0}
   end
   return events
  end
 end
 function input.lock_aim()sr.Window.set_mouse_focus(false);return sr.Window.mouse_focus()==false end
 function input.menu_cursor(menu)
  sr.Window.set_mouse_focus(false);sr.Window.set_show_cursor(menu);sr.Window.set_clip_cursor(true)
  if sr.Window.mouse_focus()~=false or sr.Window.show_cursor()~=menu or sr.Window.clip_cursor()~=true then return false end
  return capture.confine(not menu)
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
 local camera=host.require('src/vendor/camera_input.lua').new(native,capture,input,ownership.available)
 ownership.attach(camera,native,input)
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
  return open or status.owner~=nil or status.active or status.pending_restore,
   {open=open,active=status.active,pending_restore=status.pending_restore,owner=status.owner}
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

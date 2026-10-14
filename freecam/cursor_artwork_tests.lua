local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Standalone=dofile(root..'standalone.lua')
local mode=2;local writes=0;local refused=false;local bad_readback=false
local native={mcm_cursor_mode=function()return mode end,mcm_set_cursor_mode=function(value)
 writes=writes+1;if refused then return 0 end;if not bad_readback then mode=value end;return 1 end}
local artwork=Standalone.cursor_artwork(native)
assert(artwork(true)and mode==1 and writes==1,'New helper did not select visible Photo menu cursor')
assert(artwork(true)and writes==1,'Stable menu rewrites cursor policy each frame')
assert(artwork(false)and mode==2 and writes==2,'Camera focus did not return to hidden engine artwork')
assert(artwork(false)and writes==2)
assert(artwork(true));mode=2 -- Native release restores its normal policy.
assert(artwork(true)and mode==1,'Menu re-entry did not reassert Photo artwork after release')
mode=2;refused=true;assert(not artwork(true)and mode==2,'Refused policy was acknowledged');refused=false
bad_readback=true;assert(not artwork(true)and mode==2,'Bad cursor readback was acknowledged');bad_readback=false
mode=0;local before=writes;assert(not artwork(true)and writes==before,'Unknown helper state was overwritten')
local old=Standalone.cursor_artwork({});assert(old(true)and old(false),'Legacy helper without artwork API was rejected')
local absent=setmetatable({},{__index=function()error('Missing native symbol')end})
old=Standalone.cursor_artwork(absent);assert(old(true)and old(false),'Legacy FFI symbol lookup failed startup')
assert(not Standalone.cursor_artwork({mcm_cursor_mode=function()error('Read failed')end,mcm_set_cursor_mode=function()error('Unexpected write')end})(true),'Helper read failure was acknowledged')

-- Exercise the actual private input factory and camera/cursor lease together.
-- Only OS/DLL functions are mocked; capture, focus transitions and restoration
-- execute the production modules that load in the game.
local ffi=require('ffi');local previous_ffi=package.loaded.ffi
local function factory(legacy)
 local state={capture=0,artwork=2,focus=true,cursor=false,clip=true,sets=0}
 local api={mcm_install=function()return 1 end,mcm_capture=function(v)state.capture=v;return 1 end,
  mcm_captured=function()return state.capture end,mcm_release=function()state.capture=0;state.artwork=2 end,
  mcm_seconds=function()return 1 end,mcm_mouse_x=function()return 0 end,mcm_mouse_y=function()return 0 end,mcm_wheel=function()return 0 end,
  mcm_escape_passthrough=function()return 1 end}
 if not legacy then
  api.mcm_cursor_mode=function()return state.artwork end
  api.mcm_set_cursor_mode=function(v)state.sets=state.sets+1;if state.refuse then return 0 end;if not state.bad then state.artwork=v end;return 1 end
 end
 local user={SS_GetForegroundWindow=function()return ffi.cast('void*',101)end,
  SS_GetWindowThreadProcessId=function(_,out)out[0]=7;return 1 end,SS_GetAsyncKeyState=function()return 0 end,
  SS_GetCursorPos=function(out)out[0].x=10;out[0].y=10;return 1 end,SS_ScreenToClient=function()return 1 end,
  SS_GetClientRect=function(_,out)out[0]=0;out[1]=0;out[2]=1920;out[3]=1080;return 1 end}
 local kernel={SS_GetCurrentProcessId=function()return 7 end}
 package.loaded.ffi=setmetatable({load=function(name)if name=='user32'then return user elseif name=='kernel32'then return kernel else return api end end},{__index=ffi})
 local window={mouse_focus=function()return state.focus end,show_cursor=function()return state.cursor end,clip_cursor=function()return state.clip end,
  set_mouse_focus=function(v)if v then assert(state.artwork==2,'Native release did not precede engine restoration')end;state.focus=v end,
  set_show_cursor=function(v)state.cursor=v end,set_clip_cursor=function(v)state.clip=v end}
 local host={dir='test-photo',read=function()return'mcm_input_deadbeef.dll'end}
 host.require=function(name)
  if name=='src/cursor_capture.lua'then return{new=function()return{suspend=function()return true end,resume=function()return true end,tick=function()return true end,release=function()return true end,state=function()return{}end}end}end
  if name=='src/cursor_capture_backend.lua'then return{new=function()return{}end}end
  return dofile(root..name:gsub('^src/',''))
 end
 local camera=Standalone.input(host,{Window=window,Gui={resolution=function()return 1920,1080 end}})
 return camera,state
end
local called,problem=pcall(function()
 local camera,state=factory(false)
 assert(camera.acquire()and state.capture==3 and state.artwork==2 and not state.cursor and not state.focus)
 assert(camera.set_focus(true)and state.capture==1 and state.artwork==1 and state.cursor and not state.focus,'Actual Photo menu did not acquire visible artwork')
 local n=state.sets;assert(camera.menu_sample()and state.sets==n,'Actual menu sampling repeatedly wrote artwork')
 assert(camera.set_focus(false)and state.capture==3 and state.artwork==2 and not state.cursor)
 assert(camera.release()and state.capture==0 and state.artwork==2 and state.focus and not state.cursor)
 assert(camera.acquire()and camera.set_focus(true)and state.artwork==1)
 assert(camera.release()and state.artwork==2 and state.focus)
 assert(camera.acquire());state.refuse=true;assert(not camera.set_focus(true)and state.capture==0 and state.focus and not state.cursor,'Refused artwork did not restore the actual input lease')
 state.refuse=false;assert(camera.acquire());state.bad=true;assert(not camera.set_focus(true)and state.capture==0 and state.focus,'Bad artwork readback retained capture')
 camera,state=factory(true);assert(camera.acquire()and camera.set_focus(true)and state.capture==1 and state.cursor,'Actual legacy input factory stopped working')
 assert(camera.release()and state.capture==0 and state.focus)
end)
package.loaded.ffi=previous_ffi;assert(called,problem)
print('Photo cursor artwork: explicit new-helper menu/camera policy, stable writes, release/re-entry, refusal/readback/unknown state and legacy FFI fallback passed')

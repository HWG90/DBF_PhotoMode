-- The real Lua capture/service pair against a bounded native input double.
-- Sampling must report loss without releasing a pause-dependent input lease.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Capture=dofile(root..'photo_input_capture.lua')
local Camera=dofile(root..'vendor/camera_input.lua')
local function fixture()
 local f={focused=true,available=true,parent=false,mode=0,clock=1,releases=0,captures=0,window_writes=0,
  focus=true,cursor=false,clip=false,keys={}}
 local window={mouse_focus=function()return f.focus end,show_cursor=function()return f.cursor end,clip_cursor=function()return f.clip end}
 function window.set_mouse_focus(v)
  f.window_writes=f.window_writes+1
  if v and f.fail_restore then return false end
  if not(v and f.ignore_restore)then f.focus=v end
  return true
 end
 function window.set_show_cursor(v)f.window_writes=f.window_writes+1;f.cursor=v;return true end
 function window.set_clip_cursor(v)f.window_writes=f.window_writes+1;f.clip=v;return true end
 f.capture=Capture.new(window,function()return f.parent end)
 local native={mcm_captured=function()return f.focused and f.mode or 0 end,
  mcm_install=function(h)assert(h==7);return f.install_fail and 0 or 1 end,
  mcm_capture=function(mode)
   f.captures=f.captures+1
   if f.capture_fail then return 0 end
   f.mode=mode;return 1
  end,
  mcm_release=function()
   assert(not f.paused,'Sampling released pause-dependent native capture before controller restoration')
   f.releases=f.releases+1;if not f.native_release_fail then f.mode=0 end
  end}
 local input={poll=function()end,focused=function()return f.focused end,window=function()return 7 end,
  now=function()return f.clock end,down=function(key)return f.keys[key]==true end,
  wheel=function()return 0 end,look=function()return 3,-2 end,mouse=function()return 80,90 end}
 function input.lock_aim()return window.set_mouse_focus(false)and not f.focus end
 function input.menu_cursor(menu)
  if f.cursor_fail then return false end
  window.set_mouse_focus(false);window.set_show_cursor(menu);window.set_clip_cursor(true)
  return f.capture.confine(not menu)
 end
 f.camera=Camera.new(native,f.capture,input,function()return f.available and not f.parent end)
 return f
end
local function acquired(f,menu)
 local token=assert(f.camera.acquire());assert(f.capture.owns(token))
 if menu then assert(f.camera.set_focus(true))end
 return token
end
local function retained(f,message)
 local status=f.camera.status()
 assert(status.active and status.owned and f.capture.status().active,message)
 return status
end
local f=fixture();local token=acquired(f,true)
local writes,releases,captures=f.window_writes,f.releases,f.captures
local status=f.camera.status()
assert(status.ready and status.mode==1 and status.native_mode==1 and not status.cleanup_pending)
assert(f.window_writes==writes and f.releases==releases and f.captures==captures,'Input status mutated native capture or Window flags')
assert(not f.camera.acquire()and f.releases==releases and f.captures==captures,'A valid live lease was silently replaced')

-- Native WM_KILLFOCUS can clear capture between Lua polls, even if the next
-- sample already observes the game focused again. Leave cleanup to controller.
f.mode=0;f.paused=true
local sample,why=f.camera.menu_sample()
assert(not sample and type(why)=='string'and f.releases==releases,'Menu capture loss performed implicit native release')
status=retained(f,'Menu capture loss discarded its restoration token')
assert(not status.ready and status.native_mode==0 and not status.cleanup_pending)
assert(not f.camera.set_focus(false)and f.releases==releases and f.captures==captures,'A focus switch silently reacquired a lost pause-dependent capture')
f.paused=false;assert(f.camera.release()and not f.camera.status().active and f.focus and not f.cursor and not f.clip)
acquired(f,false);assert(f.camera.sample().mouse_x==3 and f.camera.sample().mouse_y==-2)
assert(f.camera.release())

-- Acquiring directly after confirmed native loss repairs the stale token
-- instead of getting stuck on "already acquired" forever.
f=fixture();local old=acquired(f,true);f.mode=0
local fresh=assert(f.camera.acquire())
assert(fresh~=old and f.capture.owns(fresh)and not f.capture.owns(old)and f.mode==3 and f.releases==1 and f.camera.status().ready)
assert(f.camera.release())

-- Both camera and menu sampling honor external input ownership/availability.
for _,menu in ipairs({false,true})do
 f=fixture();acquired(f,menu);f.available=false;f.paused=true
 if menu then sample,why=f.camera.menu_sample()else sample,why=f.camera.sample()end
 assert(not sample and type(why)=='string'and f.releases==0 and retained(f,'Unavailable input discarded its lease').ready==false)
 assert(not f.camera.set_focus(not menu)and f.releases==0)
 f.paused=false;assert(f.camera.release())
end
f=fixture();acquired(f,true);f.focused=false;f.paused=true
assert(not f.camera.menu_sample()and not f.camera.sample()and f.releases==0 and retained(f,'Focus loss discarded its lease').ready==false)
f.paused=false;assert(f.camera.release())

-- A failed Window restoration keeps a retryable token even though native
-- capture has already been released. acquire must retry cleanup before capture.
for _,failure in ipairs({'fail_restore','ignore_restore'})do
 f=fixture();old=acquired(f,true);f[failure]=true
 local ok,reason=f.camera.release();assert(not ok and type(reason)=='string')
 status=retained(f,'Failed Window restoration dropped its lease')
 assert(status.cleanup_pending and not status.ready and status.native_mode==0)
 captures=f.captures;assert(not f.camera.acquire()and f.captures==captures and f.camera.status().cleanup_pending,'Pending cleanup was skipped before recapture')
 f[failure]=false;fresh=assert(f.camera.acquire())
 assert(fresh~=old and f.camera.status().ready and not f.camera.status().cleanup_pending and f.mode==3)
 assert(f.camera.release()and f.focus and not f.cursor and not f.clip)
end

f=fixture();acquired(f);f.native_release_fail=true
assert(not f.camera.release()and f.camera.status().cleanup_pending and f.mode==3)
captures=f.captures;assert(not f.camera.acquire()and f.captures==captures,'Native release failure was bypassed by a new capture')
f.native_release_fail=false;assert(f.camera.acquire()and f.camera.status().ready and f.camera.release())

-- A partially successful acquire can alter Window flags before native capture
-- fails. Failed rollback must remain recoverable by a later acquire attempt.
f=fixture();f.capture_fail=true;f.fail_restore=true
local accepted,reason=f.camera.acquire();assert(not accepted and type(reason)=='string')
status=retained(f,'Partial acquire rollback lost restoration ownership')
assert(status.cleanup_pending and status.native_mode==0 and not status.ready)
f.capture_fail=false;f.fail_restore=false
assert(f.camera.acquire()and f.camera.status().ready and f.camera.release()and f.focus and not f.cursor and not f.clip)

-- Cursor/focus switching failures are reported without releasing. Native mode
-- may already have switched, making explicit controller cleanup essential.
f=fixture();acquired(f);f.cursor_fail=true;f.paused=true
sample,why=f.camera.sample();assert(not sample and type(why)=='string'and f.releases==0)
assert(retained(f,'Cursor sample failure discarded its lease').ready)
local switched,problem=f.camera.set_focus(true)
assert(not switched and type(problem)=='string'and f.releases==0 and f.mode==1)
status=retained(f,'Failed focus switch discarded its lease');assert(status.mode==3 and status.native_mode==1 and not status.ready)
f.paused=false;f.cursor_fail=false;assert(f.camera.release()and f.camera.acquire()and f.camera.set_focus(true))
f.cursor_fail=true;f.paused=true
sample,why=f.camera.menu_sample();assert(not sample and type(why)=='string'and f.releases==1)
retained(f,'Menu cursor failure discarded its lease');f.paused=false;f.cursor_fail=false;assert(f.camera.release())

-- Respect a newer foreign frontend. Once the old Lua token no longer owns the
-- capture lease, its cleanup must not release the frontend's native capture.
f=fixture();token=acquired(f,true);assert(f.capture.release(token));f.parent=true;f.mode=1
releases=f.releases;assert(not f.camera.status().owned and not f.camera.status().ready)
assert(not f.camera.acquire()and not f.camera.status().active and f.releases==releases and f.mode==1,'A retired local token released foreign native capture')
f=fixture();acquired(f,true);f.parent=true;writes=f.window_writes
assert(not f.camera.menu_sample()and f.releases==0 and f.camera.release())
assert(f.window_writes==writes and not f.camera.status().active,'Photo cleanup overwrote a newer frontend Window state')

print('Input lease recovery: read-only status, capture/focus/availability loss, no sampling-time release, retryable native/Window cleanup, partial acquire and focus failure, fresh reacquisition and foreign ownership passed')

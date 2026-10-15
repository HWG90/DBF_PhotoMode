local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Capture=dofile(root..'photo_input_capture.lua')
local function copy(v)if v then return{v[1],v[2],v[3],v[4]}end end
local function same(a,b)return a and b and table.concat(a,',')==table.concat(b,',')end
local desktop={-1920,0,2560,1440};local actual=copy(desktop);local client={-1800,120,-520,840}
local focus,cursor_flag,engine_clip=true,false,false;local focused=true;local parent=false
local writes,fail,ignore=0,false,false
local native={current=function()return copy(actual)end,client=function()return copy(client)end,
 focused=function()return focused end,apply=function(bounds)
  writes=writes+1;if fail then return false end
  if not ignore then actual=copy(bounds or desktop)end;return true
 end}
local window={mouse_focus=function()return focus end,show_cursor=function()return cursor_flag end,clip_cursor=function()return engine_clip end,
 set_mouse_focus=function(v)focus=v end,set_show_cursor=function(v)cursor_flag=v end,set_clip_cursor=function(v)engine_clip=v end}
local lease=Capture.new(window,function()return parent end,native)
local token=assert(lease.acquire('photo'))
assert(lease.confine(true)and same(actual,client),'Camera must confine to client area on a negative-coordinate monitor')
local before=writes;assert(lease.confine(true)and writes==before,'Unchanged camera frames must avoid redundant clipping calls')
actual=copy(desktop);assert(lease.confine(true)and same(actual,client),'Camera must recover when the engine drops its real Windows clip despite retaining its flag')
client={200,160,1800,1060};assert(lease.confine(true)and same(actual,client),'Confinement must track window moves/resizes')
assert(lease.confine(false)and same(actual,desktop),'Menu focus must release camera confinement')
assert(lease.confine(true));assert(lease.release(token)and same(actual,desktop),'Photo exit must restore the prior Windows clip')
actual={100,100,900,700};local prior=copy(actual);token=assert(lease.acquire('photo'));assert(lease.confine(true));assert(lease.release(token)and same(actual,prior),'Existing confinement must be restored exactly')
actual=copy(desktop);token=assert(lease.acquire('photo'));assert(lease.confine(true));focused=false
assert(not lease.confine(true),'Alt-Tab must never acquire or extend confinement')
assert(lease.release(token)and same(actual,desktop),'Focus loss must release the desktop instead of restoring a game clip')
focused=true;token=assert(lease.acquire('photo'));assert(lease.confine(true))
local foreign={10,20,110,220};actual=copy(foreign);before=writes
assert(lease.release(token)and writes==before and same(actual,foreign),'Release must not overwrite a later foreign clip')
actual=copy(desktop);token=assert(lease.acquire('photo'));fail=true
assert(not lease.confine(true));fail=false;assert(lease.confine(true));fail=true
assert(not lease.release(token)and lease.owns(token),'Failed release must retain ownership for retry')
fail=false;assert(lease.release(token)and same(actual,desktop))
token=assert(lease.acquire('photo'));ignore=true;assert(not lease.confine(true),'Accepted clip with wrong readback must fail')
ignore=false;assert(lease.release(token));actual=copy(desktop)
token=assert(lease.acquire('photo'));assert(lease.confine(true));parent=true;actual=copy(foreign);before=writes
assert(lease.release(token)and writes==before and same(actual,foreign),'A newer MCM owner must retain its confinement')

-- Exercise the real Win32 adapter's coordinate and RECT marshalling without
-- changing the desktop or installing an input callback.
local ffi=require('ffi');pcall(ffi.cdef,'typedef struct {long x;long y;} SS_POINT;')
local user={SS_GetClipCursor=function(r)for i=0,3 do r[i]=desktop[i+1]end;return 1 end,
 SS_GetClientRect=function(h,r)assert(h==7);r[0]=0;r[1]=0;r[2]=1280;r[3]=720;return 1 end,
 SS_ClientToScreen=function(h,p)assert(h==7);p[0].x=p[0].x-1800;p[0].y=p[0].y+120;return 1 end,
 SS_ClipCursor=function(r)if r then actual={tonumber(r[0]),tonumber(r[1]),tonumber(r[2]),tonumber(r[3])}else actual=copy(desktop)end;return 1 end}
local clip=dofile(root..'standalone.lua').cursor_clip(user,ffi,{focused=function()return true end,window=function()return 7 end})
assert(same(clip.current(),desktop)and same(clip.client(),{-1800,120,-520,840}))
assert(clip.apply(client)and same(actual,client));assert(clip.apply(nil)and same(actual,desktop))
print('Camera confinement: real client-area adapter, moves/resizes, menu/exit/Alt-Tab restoration, takeover, failures and retry passed')

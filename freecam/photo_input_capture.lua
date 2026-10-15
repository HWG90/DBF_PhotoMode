-- Photo-owned cursor lease. Native capture is released by camera_input first.
-- A newer external frontend owns its current Window flags; never restore over it.
local M={}
function M.new(window,parent,cursor)
 local self={};local lease
 local function equal(a,b)
  return a and b and a[1]==b[1]and a[2]==b[2]and a[3]==b[3]and a[4]==b[4]
 end
 local function restore_clip()
  if not cursor or not lease.clip_owned then return true end
  local current=cursor.current()
  if not current then return false,'Windows cursor bounds unavailable'end
  -- Another frontend may have changed confinement since our last frame.
  if not equal(current,lease.clip_owned)then lease.clip_owned=nil;return true end
  local saved=cursor.focused()and lease.clip_saved or nil
  if not cursor.apply(saved)then return false,'Windows cursor release failed'end
  local actual=cursor.current()
  if not actual or saved and not equal(actual,saved)then return false,'Windows cursor release readback failed'end
  lease.clip_owned=nil;return true
 end
 local function parent_active()
  if not parent then return false end
  local ok,active,why=pcall(parent)
  if not ok then return nil,tostring(active)end
  if type(active)~='boolean'then return nil,why or'External input ownership unavailable'end
  return active
 end
 function self.acquire(owner)
  if lease then return nil,'Photo input lease already owned'end
  local active,why=parent_active();if active~=false then return nil,why or'External input is already owned'end
  local called,saved=pcall(function()return{focus=window.mouse_focus(),cursor=window.show_cursor(),clip=window.clip_cursor()}end)
  if not called then return nil,tostring(saved)end
  for _,name in ipairs({'focus','cursor','clip'})do if type(saved[name])~='boolean'then return nil,'Photo cursor state unavailable'end end
  local bounds=cursor and cursor.current()
  if cursor and not bounds then return nil,'Windows cursor bounds unavailable'end
  local token={};lease={token=token,owner=owner,saved=saved,clip_saved=bounds};return token
 end
 function self.owns(token)return lease~=nil and lease.token==token end
 function self.confine(camera)
  if not lease then return false,'Photo input lease not owned'end
  if not cursor then return true end
  if not camera then return restore_clip()end
  if not cursor.focused()then return false,'Game window is not focused'end
  local bounds=cursor.client()
  if not bounds or bounds[3]<=bounds[1]or bounds[4]<=bounds[2]then return false,'Game client bounds unavailable'end
  local current=cursor.current()
  if not current then return false,'Windows cursor bounds unavailable'end
  if not equal(current,bounds)then
   if not cursor.apply(bounds)then return false,'Windows camera confinement failed'end
   -- Keep release ownership even if the following readback fails.
   lease.clip_owned=bounds
   if not equal(cursor.current(),bounds)then return false,'Windows camera confinement readback failed'end
  else lease.clip_owned=bounds end
  return true
 end
 function self.release(token)
  if not self.owns(token)then return false,'Photo input lease not owned'end
  local active,why=parent_active()
  if active==nil then return false,why end
  if active then lease=nil;return true end
  local saved=lease.saved
  local ok,problem=pcall(function()
   for _,entry in ipairs({{'set_mouse_focus','mouse_focus','focus'},{'set_show_cursor','show_cursor','cursor'},{'set_clip_cursor','clip_cursor','clip'}})do
    if window[entry[2]]()~=saved[entry[3]]then assert(window[entry[1]](saved[entry[3]])~=false,'Photo cursor restoration refused')end
    assert(window[entry[2]]()==saved[entry[3]],'Photo cursor restoration readback failed')
   end
   local restored,reason=restore_clip();assert(restored,reason)
  end)
  if not ok then return false,tostring(problem)end
  lease=nil;return true
 end
 function self.status()return{owner=lease and lease.owner,active=lease~=nil}end
 return self
end
return M

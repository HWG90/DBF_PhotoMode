-- Photo-owned cursor lease. Native capture is released by camera_input first.
-- A newer external frontend owns its current Window flags; never restore over it.
local M={}
function M.new(window,parent)
 local self={};local lease
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
  local token={};lease={token=token,owner=owner,saved=saved};return token
 end
 function self.owns(token)return lease~=nil and lease.token==token end
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
  end)
  if not ok then return false,tostring(problem)end
  lease=nil;return true
 end
 function self.status()return{owner=lease and lease.owner,active=lease~=nil}end
 return self
end
return M

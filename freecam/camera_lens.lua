-- Bind the unchanged photo lens implementation to a validated scene lifetime.
-- This factory is used only by the independent camera candidate.
local M={}
function M.new(original_factory,scene_reader)
 assert(type(original_factory)=='table'and type(original_factory.new)=='function','Photo lens factory unavailable')
 assert(type(scene_reader)=='function','Photo lens scene reader unavailable')
 local factory={}
 for name,value in pairs(original_factory)do factory[name]=value end
 local function scene()
  local ok,value=pcall(scene_reader)
  if not ok then return nil,tostring(value)end
  if type(value)~='table'or type(value.current)~='function'or type(value.owned)~='function'then return nil,'Photo lens scene validator unavailable'end
  return value
 end
 local function snapshot(frame)
  local value={};for name,item in pairs(frame)do value[name]=item end;return value
 end
 local function same(a,b)
  for _,name in ipairs({'world','unit','cam','player','player_identity','epoch'})do if a[name]~=b[name]then return false end end
  return true
 end
 function factory.new(sr)
  local impl=original_factory.new(sr);local saved
  assert(type(impl)=='table'and type(impl.apply)=='function'and type(impl.release)=='function','Photo lens implementation unavailable')
  local self={}
  function self.apply(cam,unit,...)
   local owner,why=scene();assert(owner,why)
   local read,frame,reason=pcall(owner.current)
   assert(read and type(frame)=='table',read and(reason or'Photo lens camera is not currently verified')or tostring(frame))
   assert(frame.cam==cam and frame.unit==unit,'Photo lens camera does not match the verified scene')
   local checked,owned,problem=pcall(owner.owned,frame)
   assert(checked and owned==true,checked and(problem or'Photo lens camera ownership is unavailable')or tostring(owned))
   if saved then assert(saved.owner==owner and same(saved.frame,frame),'Photo lens changed before its previous scene was released')
   else saved={owner=owner,frame=snapshot(frame)}end
   -- Save ownership before the real setter runs. A later rotation/setter error
   -- still needs a guarded cleanup of any FOV write already completed.
   return impl.apply(cam,unit,...)
  end
  function self.release()
   if not saved then return true end
   local owner,why=scene();if not owner then return false,why end
   if owner~=saved.owner then return false,'Photo lens scene owner changed before cleanup validation'end
   local checked,owned,problem=pcall(owner.owned,saved.frame)
   if not checked then return false,tostring(owned)end
   if owned==nil then return false,problem or'Photo lens cleanup awaits a verified camera lifetime'end
   if owned==false then
    -- The old native Camera may already be freed while its Unit is still alive.
    -- Discard its Lua implementation instead of asking it to inspect/restore
    -- the saved Camera. Constructing the original factory performs no writes.
    local made,next_impl=pcall(original_factory.new,sr)
    if not made then return false,tostring(next_impl)end
    if type(next_impl)~='table'or type(next_impl.apply)~='function'or type(next_impl.release)~='function'then return false,'Fresh photo lens implementation unavailable'end
    impl=next_impl;saved=nil;return true
   end
   if owned~=true then return false,'Invalid photo lens camera ownership acknowledgment'end
   local called,restored,reason=pcall(impl.release)
   if not called then return false,tostring(restored)end
   if restored~=true then return false,reason or'Photo lens restoration is pending'end
   saved=nil;return true
  end
  return setmetatable(self,{__index=function(_,name)return impl[name]end})
 end
 return factory
end
return M

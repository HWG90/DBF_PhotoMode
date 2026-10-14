-- One Photo session owns an OS rectangle lease. Tick after Core input/cursor
-- setters across camera/menu transitions; restore before final Core teardown.
local M={}
local function copy(r)return r and{r[1],r[2],r[3],r[4]}end
local function equal(a,b)return a and b and a[1]==b[1]and a[2]==b[2]and a[3]==b[3]and a[4]==b[4]end
function M.new(backend,log)
 local self={active=false,pending=false,status='Photo cursor is released'};local lease;local yielded=false;local suspended=false
 local function fail(why)self.status=tostring(why);return false,self.status end
 local function window()
  local ok,value,why=pcall(backend.window);if not ok then return nil,'unavailable: '..tostring(value)end;return value,why
 end
 local function clip()local ok,value=pcall(backend.clip);if not ok then return nil,tostring(value)end;return value end
 function self.release(reason)
  self.active=false
  if not lease then self.pending=false;return true end
  local current,why=clip();if not current then self.pending=true;return fail('Photo cursor release pending: '..tostring(why))end
  if lease.restoring and(lease.restore_target==nil or equal(current,lease.restore_target))then lease=nil;self.pending=false;self.status=reason or'Photo cursor restoration acknowledged';return true end
  if not equal(current,lease.owned)then lease=nil;self.pending=false;self.status='Changed cursor clip preserved';return true end
  local owner,why=window()
  if not owner and why~='focus_lost'and why~='window_retired'then self.pending=true;return fail('Photo cursor release pending: '..tostring(why))end
  -- A matching lease is ours to release. Never leave another application
  -- trapped in the game client area after focus loss or window retirement.
  local target=owner and owner.window==lease.window and copy(lease.prior)or nil
  local called,ok,value,committed=pcall(backend.write,target,current)
  if not called or ok~=true then
   if called and committed then lease.restoring=true;lease.restore_target=copy(target);self.pending=true;return fail('Photo cursor release readback pending: '..tostring(value))end
   self.pending=true;return fail('Photo cursor release pending: '..tostring(called and value or ok))
  end
  lease=nil;self.pending=false;self.status=reason or'Photo cursor is released';return true
 end
 function self.tick(active)
  if not active then yielded=false;suspended=false;return self.release('Photo cursor restored')end
  if suspended or yielded then return true end
  if lease and lease.restoring then return self.release('Photo cursor restoration retry')end
  local candidate,why=window()
  if not candidate then
   if why=='focus_lost'or why=='window_retired'then return self.release('Photo cursor released on focus loss')end
   return fail('Photo cursor unavailable: '..tostring(why))
  end
  if lease and lease.window~=candidate.window then local ok,why=self.release('Photo window changed');if not ok then return false,why end end
  local current,why=clip();if not current then return fail('Photo cursor unavailable: '..tostring(why))end
  if lease and not equal(current,lease.owned)then
   if equal(current,candidate.rect)then lease.owned=copy(current) -- Core resize/focus transition to the same client area.
   else lease=nil;self.active=false;self.pending=false;yielded=true;return fail('Photo cursor yielded to another clip writer')end
  end
  if not lease then lease={window=candidate.window,prior=copy(current),owned=copy(current),claimed=false}end
  if not equal(current,candidate.rect)or not lease.claimed then
   local called,ok,value,committed=pcall(backend.write,candidate.rect,current,candidate.window)
   if called and committed then lease.owned=copy(candidate.rect);lease.claimed=true end
   if not called or ok~=true then
    self.active=false;self.pending=lease.claimed
    if not lease.claimed then lease=nil end
    return fail('Photo cursor capture failed: '..tostring(called and value or ok))
   end
   lease.owned=copy(value);lease.claimed=true
  end
  self.active=true;self.pending=false;self.status='Photo cursor confined to game client';return true
 end
 -- Core/input handoff protocol: suspend before a known clip-owner transition,
 -- then explicitly resume after it. A foreign writer is never fought per frame.
 function self.suspend()local ok,why=self.release('Photo cursor handoff');if ok then suspended=true end;return ok,why end
 function self.resume()suspended=false;yielded=false;return true end
 function self.state()return{active=self.active,pending=self.pending,yielded=yielded,suspended=suspended,window=lease and lease.window,prior=lease and copy(lease.prior),owned=lease and copy(lease.owned)}end
 self.close=self.release;self.clear=self.release
 return self
end
return M

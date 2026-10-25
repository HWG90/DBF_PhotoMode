-- Lifecycle adapter around the recovered data-only controller.
local M={}
function M.new(backend,controller,clock,now)
 local guard=controller.new(backend);local self={};local opened=false;local started,first_epoch,zero_at,held_epoch
 local function close_clock()
  local state=guard.status()
  if not state.owned and state.phase=='idle'then clock.close();opened=false;started,first_epoch=nil,nil end
 end
 function self.owned()return guard.status().owned end
 function self.pending()return guard.pending end
 function self.status()return guard.status()end
 function self.prepare()
  if not opened then assert(clock.open());opened=true;started=now();clock.mark();first_epoch=select(1,clock.sample())end
  local state=guard.status()
  if state.phase=='releasing'then
   local ok,why=guard.after_update();if not ok then return false,why,true end
   close_clock();return false,'Waiting for previous hover restoration',true
  end
  if not state.owned then clock.mark()end
  local ok,why=guard.prepare()
  if not ok then return false,why,false end
  local snapshot,reason=backend.snapshot();if not snapshot then return false,reason,false end
  -- Keyboard capture may precede the native jump activation queued last frame.
  -- Give every equipped Hover Pack a completed positive update before zero.
  if snapshot.hover and(snapshot.epoch<=first_epoch or snapshot.dt<=0)then
   if now()-started>5 then guard.release();return false,'Hover preparation timed out',false end
   return false,'Waiting for hover controls to settle',true
  end
  -- Re-read preparation after the positive update: queued hover activation may
  -- now need its own neutralizing override and one further completed update.
  ok,why=guard.prepare();if not ok then return false,why,false end
  ok,why=guard.ready()
  if not ok then
   if now()-started>5 then guard.release();return false,why,false end
   return false,why,true
  end
  ok,why=guard.acquire();if ok then zero_at=nil;held_epoch=nil end;return ok,why,false
 end
 function self.release()
  zero_at,held_epoch=nil,nil
  if opened then clock.mark()end
  local ok,why=guard.release();close_clock();return ok,why
 end
 function self.cleanup()
  local ok,why=guard.after_update();if ok then close_clock()end;return ok,why
 end
 function self.hold()
  local ok,why=guard.hold();if not ok then return false,why end
  local stamp=now();zero_at=zero_at or stamp
  if stamp-zero_at>=.5 then
   local epoch,reason=clock.sample();if not epoch then return false,reason end
   if held_epoch and epoch~=held_epoch then return false,'Gameplay world advanced despite hover pause'end
   held_epoch=epoch
  end
  return true
 end
 function self.dispose()
  local ok,why=self.release();if not ok then return false,why end
  ok,why=self.cleanup();if ok and not self.owned()then clock.close();opened=false end
  return ok,why
 end
 return self
end
return M

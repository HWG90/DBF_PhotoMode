-- Explicit opt-in factory; non-FFI builds never import the native backend.
local M={}
function M.new(factory,now,log)
 local self={};local controller;local reason=factory and'Choose Passive or Dummy to enable'or'AI requires an FFI build';local due=0;local last_error;local available=factory~=nil
 function self.select(index)
  local mode=({'normal','passive','dummy'})[index];if not mode then return false,'Unknown AI mode'end
  if mode=='normal'and not controller then return true end
  if not controller then
   if not factory then return false,reason end
   local ok,value=pcall(factory);if not ok or not value then reason=tostring(value);available=false;return false,reason end
   controller=value
  end
  if mode~='normal'then
   local ok,ready,why=pcall(controller.ready);available=ok and ready==true
   if not available then reason=tostring(ok and why or ready);return false,reason end
  end
  return controller.queue(mode)
 end
 function self.tick()
  if not controller then return true end
  local ok,value,why=pcall(controller.flush,true)
  if not ok or value==false then reason=tostring(ok and why or value);if reason~=last_error then last_error=reason;log('Enemy behavior: '..reason)end else last_error=nil end
  if now()>=due then due=now()+.5;local called,ready,why=pcall(controller.ready);available=called and ready==true;if not available then reason=tostring(called and why or ready)end end
  return ok and value~=false,reason
 end
 function self.state()
  return{available=available,mode=controller and controller.mode or'normal',pending=controller and controller.pending or false,
   status=controller and controller.status or reason,reason=reason}
 end
 function self.faction()if controller and controller.faction then return controller.faction()end end
 function self.dispose()
  if not controller then return true end
  controller.queue('normal');local ok,why=controller.flush(false)
  if not ok or controller.pending or controller.count()>0 then return false,why or'AI restoration pending'end
  return true
 end
 return self
end
return M

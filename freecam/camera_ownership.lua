-- Photo's local camera lease. Other mods' globals, callbacks and bindings are
-- outside this service; scene/input cleanup remains with the owning controller.
local M={}
function M.new()
 local self={available=true,held=false,count=0}
 function self.refresh()
  if self.disabled then return false,self.reason end
  return true
 end
 function self.acquire()
  local ready,why=self.refresh();if not ready then return false,why end
  self.held=true;return true
 end
 function self.release()
  self.held=false;return true
 end
 function self.dispose()
  if self.held then return false,'Release the Photo camera before stopping its owner'end
  self.disabled=true;self.available=false;self.reason='Photo camera owner stopped'
  return true
 end
 return self
end
return M

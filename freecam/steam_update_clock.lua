-- Completed world-clock observations around the real game update callback.
-- UI ticks never manufacture an epoch. Retained foreign chains become inert.
local M={}
function M.new(sr,identity)
 local A,W=sr.Application,sr.World;local self={};local world,key,last,epoch,dt,why
 local previous,wrapper,switch
 local function poll(clear_idle)
  if not switch or not switch.active then return end
  local ok,value=pcall(function()
   local current=assert(A.main_world(),'World unavailable')
   assert(identity(current)==key,'World clock owner changed')
   local v=W.time(current);assert(type(v)=='number'and v==v and v>=0 and v<1e12,'World clock invalid');return v
  end)
  if not ok then why=tostring(value);dt=0;return end
  if last and value<last then why='World clock moved backwards';dt=0;return end
  why=nil;local change=last and value-last or 0;last=value
  if change>0 then dt=change;epoch=epoch+1 elseif clear_idle then dt=0 end
 end
 function self.open()
  if switch and switch.active then return self.sample()~=nil end
  assert(type(W.time)=='function','Completed world clock unavailable')
  world=assert(A.main_world(),'World unavailable');key=identity(world);last=nil;epoch=0;dt=0;why=nil
  previous=assert(rawget(_G,'update'),'Game update callback unavailable');local saved=previous
  switch={active=true};local owned_switch=switch
  local function after(...)if owned_switch.active then poll(true)end;return ...end
  wrapper=function(...)if owned_switch.active then poll(false)end;return after(saved(...))end
  rawset(_G,'update',wrapper);poll(false)
  if why then local reason=why;self.close();error(reason)end;return true
 end
 function self.mark()poll(false);return self.sample()end
 function self.sample()
  if not switch or not switch.active then return nil,'Completed world clock is closed'end
  if why then return nil,why end
  return epoch,dt
 end
 function self.close()
  if switch then switch.active=false end
  if wrapper and rawget(_G,'update')==wrapper then rawset(_G,'update',previous)end
  previous,wrapper,switch,world,key,last=nil,nil,nil,nil,nil,nil;return true
 end
 return self
end
return M

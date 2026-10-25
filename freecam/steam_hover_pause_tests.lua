local Clock=dofile('freecam/steam_update_clock.lua')
local Controller=dofile('freecam/hover_pause.lua')
local Hover=dofile('freecam/steam_hover_pause.lua')
local function fixture(before)
 local f={time=0,now=0,value=6,active=true,z=1,world={},writes={},action=nil,reads=0}
 local sr={Application={main_world=function()return f.world end},World={time=function(w)assert(w==f.world);f.reads=f.reads+1;return f.time end}}
 f.native=function(dt,...)
  local function engine()f.time=f.time+dt;if dt>0 and f.value==0 then f.z=0 end end
  if before then engine()end;if f.action then f.action()end;if not before then engine()end
  return nil,'saved',nil,...
 end
 update=f.native
 f.clock=Clock.new(sr,function(v)return v end)
 local backend={snapshot=function(expected)
  local e,dt=f.clock.sample();assert(e,dt)
  return{identity='world:pack',generation=1,epoch=e,dt=dt,value=f.value,active=f.active,hover=true,action=0,control={x=0,y=0,z=f.z}}
 end,input_supported=function()return true end,
 set=function(s,v)assert(v==0 and s.value==f.value);f.value=v;f.writes[#f.writes+1]=v;return true end,
 restore=function(s,v)assert(s.value==0 and f.value==0);f.value=v;f.writes[#f.writes+1]=v;return true end}
 f.guard=Hover.new(backend,Controller,f.clock,function()return f.now end)
 function f.step(dt)f.now=f.now+.016;local a,b,c,d=update(dt,'slot');assert(a==nil and b=='saved'and c==nil and d=='slot','Update returns changed')end
 return f
end
for _,before in ipairs({false,true})do
 local f=fixture(before);local ready,pending
 f.action=function()local why;ready,why,pending=f.guard.prepare()end
 f.step(.016);assert(not ready and pending and f.value==0,'A Lua tick or prior engine update qualified a new override')
 for i=1,4 do if ready then break end;f.step(.016)end
 assert(ready and f.guard.owned()and f.guard.status().phase=='armed')
 f.action=nil;local epoch=f.clock.sample();local reads=f.reads
 for i=1,100 do f.clock.sample()end
 assert(f.clock.sample()==epoch and f.reads==reads,'UI samples fabricated completed engine updates')
 f.action=function()assert(f.guard.hold())end;f.step(0);assert(f.value==0)
 local released=false
 f.action=function()if not released then assert(f.guard.release());released=true end;assert(not f.guard.cleanup(),'Restore consumed an update completed before release')end
 f.step(0);assert(f.value==0 and f.guard.owned())
 f.action=nil;f.step(.016);assert(f.guard.cleanup()and f.value==6 and not f.guard.owned())
 assert(update==f.native,'Owned update hook did not retire')
end
-- Foreign chains retain their exact function and an inert forwarding observer.
do
 local f=fixture(false);f.guard.prepare();local owned=update
 local outer=function(...)return owned(...)end;update=outer
 f.guard.release();f.step(.016);assert(f.guard.cleanup());assert(update==outer)
 local reads=f.reads;update(.016);assert(f.reads==reads,'Retired observer kept reading native state')
end
-- A completed update whose clock change happened BEFORE the write cannot qualify it.
do
 local f=fixture(true);assert(f.clock.open());f.action=function()local ok,_,pending=f.guard.prepare();assert(not ok and pending)end
 f.step(.016);local epoch=f.clock.sample();assert(epoch==1)
 f.action=nil
 local ok,_,pending=f.guard.prepare();assert(not ok and pending,'Already observed world-clock change counted twice')
 assert(f.guard.release());f.step(.016);assert(f.guard.cleanup())
end
print('Hover lifecycle: real world-clock epochs, both update orders, no UI qualification, neutralization, deferred restoration, hook/return ownership passed')
-- A setter receipt is not enough if the gameplay clock continues advancing.
do
 local f=fixture(false);f.guard.prepare();f.step(.016);assert(f.guard.prepare())
 local refused=false
 for i=1,45 do f.step(.016);local ok,why=f.guard.hold();if not ok then assert(why:find('advanced despite'));refused=true;break end end
 assert(refused,'An advancing world clock was accepted as a stable zero pause')
 assert(f.guard.release());f.step(.016);assert(f.guard.cleanup()and f.value==6)
end
print('Hover pause world-clock verification: damped acquisition grace, then strict stationary gameplay clock passed')

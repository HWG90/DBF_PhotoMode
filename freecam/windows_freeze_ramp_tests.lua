local Runtime=dofile('freecam/steam_runtime.lua')
local function fixture(target)
 local f={time=0,writes={},rate=1,prepares=0,cleanups=0,queries=0,world={},session={}}
 local function native(key,value)
  assert(key=='external_multiplier');f.writes[#f.writes+1]=value;f.rate=value
  if f.refuse then return false end
 end
 f.native=native
 f.sr={Application={main_world=function()return f.world end,set_time_step_policy=native},
  Network={game_session=function()return f.session end},GameSession={peers=function()return{'local'}end}}
 f.policy=Runtime.time_policy(f.sr,function()return math.floor(f.time)end,function()
  f.cleanups=f.cleanups+1;if f.cleanup then return f.cleanup()end;return true
 end,function()
  f.prepares=f.prepares+1;if f.prepare then return f.prepare()end;return true
 end,function()f.queries=f.queries+1;return target or 0 end,nil,function()return f.time end)
 function f.at(t)f.time=t;return f.policy.tick()end
 return f
end
for _,target in ipairs({0,1e-14})do
 local f=fixture(target);local p=f.policy
 assert(p.set_smooth_freeze==nil,'Smooth Freeze has been removed')
 assert(p.freeze()and f.rate==target and #f.writes==1,'Freeze immediately uses its selected endpoint')
 local writes=#f.writes
 for i=1,12 do assert(f.at(i*.05))end
 assert(#f.writes==writes,'No timed descent or extra time writes')
 assert(p.resume()and f.rate==1,'Resume restores normal time')
end
print('Immediate Freeze and retained hoverpack endpoint passed')

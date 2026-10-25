local M=dofile('freecam/steam_runtime.lua')
local now,rate,world,session,reads=0,1,{}, {},0
local peers={'local'};local writes={};local fail_restore=false;local native_calls=0
local function native(key,value)
 assert(key=='external_multiplier')
 native_calls=native_calls+1
 if fail_restore and value==1 then return false end
 rate=value;writes[#writes+1]=value
end
local sr={Application={set_time_step_policy=native,main_world=function()reads=reads+1;return world end},
 Network={game_session=function()reads=reads+1;return session end},
 GameSession={peers=function(s)assert(s==session);reads=reads+1;return peers end}}
local p=M.time_policy(sr,function()return now end)
for i=1,100 do assert(p.tick())end;assert(reads==0 and #writes==0,'Unfrozen policy must be idle')
assert(p.freeze()and rate==0 and p.frozen,'Freeze must be true zero')
local before=reads
for i=1,100 do assert(p.tick())end;assert(reads==before and #writes==1,'No repeated writes or peer checks within one second')
now=1;assert(p.tick());assert(reads==before+3)
fail_restore=true;assert(not p.release()and rate==0 and p.frozen,'Retain restoration ownership after refusal')
before=native_calls;for i=1,100 do assert(not p.release())end
assert(native_calls==before,'Failed restoration must not hammer native setter each frame')
fail_restore=false;now=2;assert(p.release()and rate==1 and not p.frozen and sr.Application.set_time_step_policy==native)
assert(p.freeze());fail_restore=true
assert(sr.Application.set_time_step_policy('external_multiplier',1)==false)
assert(p.frozen and rate==0,'Refused foreign write must retain pause ownership')
fail_restore=false;assert(p.release()and rate==1,'Cleanup must thaw after a refused foreign write')
assert(p.freeze());local owned=sr.Application.set_time_step_policy
sr.Application.set_time_step_policy('external_multiplier',.3)
assert(rate==.3 and not p.frozen);before=#writes;assert(p.release()and #writes==before,'Never overwrite observed foreign time')
assert(p.freeze());peers={local_peer=true,remote_peer=true};now=3;assert(p.tick()and rate==1 and not p.frozen,'Keyed peer inventory must thaw')
assert(not p.freeze()and rate==1,'Refuse multiplayer freeze')
peers={'local'};assert(p.freeze());world={};now=4;assert(p.tick()and rate==1,'World replacement must thaw')
assert(p.freeze());local wrapper=sr.Application.set_time_step_policy
local outer=function(...)return wrapper(...)end;sr.Application.set_time_step_policy=outer
assert(not p.release()and rate==0,'Binding replacement must not silently claim restoration')
outer('external_multiplier',1);assert(not p.frozen);assert(p.release())
assert(sr.Application.set_time_step_policy==outer,'Preserve foreign wrapper')
before=#writes;owned('external_multiplier',.5);assert(#writes==before+1,'Retired wrapper delegates without stale ownership')
-- Slow Motion owns the same setter as Freeze and survives ordinary Resume.
sr.Application.set_time_step_policy=native;now=5
p=M.time_policy(sr,function()return now end)
assert(p.set_slowmo(true,.2)and rate==.2 and p.slowmo_active and p.owned)
local shared=sr.Application.set_time_step_policy
assert(p.freeze()and rate==0 and sr.Application.set_time_step_policy==shared,'Reuse one owner for Slow Motion and Freeze')
before=#writes
assert(p.set_slowmo(true,.4));assert(p.set_slowmo(false,.6));assert(p.set_slowmo(true,.3))
assert(#writes==before and rate==0,'Frozen slow-motion edits must not unpause or write time')
assert(p.resume()and rate==.3 and p.slowmo_active and not p.frozen)
before=#writes;assert(p.set_slowmo(true,.3));for i=1,100 do assert(p.tick())end
assert(#writes==before,'Unchanged slow motion must never rewrite the time policy')
assert(p.set_slowmo(true,.5)and rate==.5,'Active slider edits apply immediately')
assert(p.release()and rate==1 and not p.owned and not p.slowmo_active)
assert(p.set_slowmo(true,.3));peers={'local','remote'}
assert(not p.freeze()and rate==1 and not p.owned,'Explicit Freeze must revalidate an existing slow-motion owner immediately')
peers={'local'}
before=#writes;assert(p.set_slowmo(false,.8)and #writes==before,'Disabled slider edits stay idle')
assert(p.set_slowmo(true,.2));sr.Application.set_time_step_policy('external_multiplier',.7)
assert(not p.owned and not p.slowmo_active and rate==.7)
before=#writes;assert(p.release()and #writes==before,'Do not restore over a foreign positive rate')
assert(p.set_slowmo(true,.2));fail_restore=true
assert(sr.Application.set_time_step_policy('external_multiplier',1)==false and p.owned and p.slowmo_active)
assert(not p.release()and p.pending_restore);before=native_calls
for i=1,100 do assert(not p.tick())end
assert(native_calls==before,'Failed full cleanup remains bounded while slow motion owns time')
fail_restore=false;now=6;assert(p.tick()and rate==1 and not p.owned)
assert(p.set_slowmo(true,.4));peers={'local','remote'};now=7
assert(p.tick()and rate==1 and not p.owned,'Slow motion must retire on multiplayer transition too')
peers={'local'}
print('Steam simulation: true zero, idle state, bounded solo checks, exact 1x policy, restoration retry and foreign ownership passed')

-- Refuse unsafe/unknown equipment before ownership or a zero setter call.
do
 local native_writes=0;local allowed=false;local broken=false
 local native=function(_,v)native_writes=native_writes+1;assert(v>=0)end
 local s={Application={set_time_step_policy=native,main_world=function()return{}end},
 Network={game_session=function()return{}end},GameSession={peers=function()return{'local'}end}}
 local t=M.time_policy(s,function()return 0 end,nil,function()
  if broken then error('Unreadable backpack')end
  return allowed,'Hover Pack pause is being repaired'
 end)
 local ok,why=t.freeze();assert(not ok and why:find('Hover Pack')and native_writes==0 and not t.owned and not t.frozen)
 broken=true;ok,why=t.freeze();assert(not ok and why:find('Unreadable backpack')and native_writes==0 and s.Application.set_time_step_policy==native)
 broken=false;allowed=true;assert(t.freeze()and native_writes==1 and t.owns_zero())
 assert(t.release()and native_writes==2 and not t.frozen)
end
print('Pause equipment gate: unsafe/unknown reads refuse before zero or ownership; safe equipment still freezes/restores passed')

local Backend=dofile('freecam/windows_hover_freeze.lua')
local Runtime=dofile('freecam/steam_runtime.lua')
local world,pack={},{};local units={};local reads,writes,now,rate=0,{},0,1
local function native(key,value)assert(key=='external_multiplier');rate=value;writes[#writes+1]=value end
local sr={Application={main_world=function()return world end,set_time_step_policy=native},
 IdString64={from_hex=function(s)assert(s=='5ec80f4f1cdb66cf');return s end},
 World={units_by_resource=function(w,id)assert(w==world);reads=reads+1;return units end},
 Unit={alive=function(u)return u==pack end,world=function(u)assert(u==pack);return world end},
 Network={game_session=function()return 'solo'end},GameSession={peers=function()return{'local'}end}}
local choose=Backend.new(sr)
local cleanup,prepares=0,0
local p=Runtime.time_policy(sr,function()return now end,function()cleanup=cleanup+1;return true end,
 function()prepares=prepares+1;return true end,choose)
for i=1,100 do assert(p.tick())end;assert(reads==0 and #writes==0)
assert(p.freeze()and rate==0 and p.owns_zero()and prepares==1)
assert(p.resume()and rate==1)
units={pack};assert(p.freeze()and rate==1e-14 and p.frozen and not p.owns_zero())
assert(prepares==1,'Positive fallback must not prepare exact-zero skeleton writes')
local scans,changes=reads,#writes
for i=1,100 do assert(p.freeze());assert(p.tick())end
assert(reads==scans and #writes==changes,'Latched Freeze must remain idle')
assert(sr.Application.set_time_step_policy('external_multiplier',1)==nil)
assert(rate==1e-14 and p.frozen and not p.owns_zero(),'Foreign-write hold must preserve fallback instead of reasserting zero')
assert(p.set_slowmo(true,.3)and rate==1e-14)
assert(p.resume()and rate==.3 and not p.frozen)
assert(p.freeze()and rate==1e-14);assert(p.release()and rate==1)
units={};assert(p.freeze()and rate==0 and p.owns_zero(),'Recheck equipment on the next explicit Freeze')
assert(p.release())
local refused=Runtime.time_policy(sr,function()return now end,function()return false,'pose cleanup pending'end,nil,function()return 1e-14 end)
changes=#writes;assert(not refused.freeze()and #writes==changes,'Do not advance time before pose cleanup acknowledges')
local unavailable=Runtime.time_policy(sr,function()return now end,nil,nil,function()return nil,'inventory unavailable'end)
assert(not unavailable.freeze()and #writes==changes,'Unavailable inventory must not submit zero')
local invalid=Runtime.time_policy(sr,function()return now end,nil,nil,function()return .0001 end)
assert(not invalid.freeze()and #writes==changes,'Only the explicitly authorized fallback rate is accepted')
-- Manual button can temporarily use 1e-11 and return to the captured base.
units={};local samples=0
local manual=Runtime.time_policy(sr,function()return now end,function()return true end,function()return true end,choose,
 function(value,index)assert(value==1e-11 and index>=1 and index<=3);samples=samples+1 end)
assert(manual.set_near_zero(true)and rate==1)
assert(manual.freeze()and rate==1e-11 and not manual.owns_zero())
for i=1,100 do assert(manual.tick())end;assert(samples==3,'Only three deployed delta samples per tiny-rate write')
assert(manual.set_near_zero(false)and rate==0 and manual.owns_zero())
assert(manual.set_near_zero(true)and rate==1e-11 and not manual.owns_zero())
assert(manual.resume()and rate==1)
assert(manual.set_near_zero(false));units={pack}
assert(manual.freeze()and rate==1e-14)
assert(manual.set_near_zero(true)and rate==1e-11)
assert(manual.set_near_zero(false)and rate==1e-14 and not manual.owns_zero(),'Button off must preserve automatic hover fallback')
assert(manual.release()and rate==1)
-- A cleanup callback may synchronously yield to another time writer.
local reentrant
reentrant=Runtime.time_policy(sr,function()return now end,function()
 if reentrant.frozen then sr.Application.set_time_step_policy('external_multiplier',.7);sr.Application.set_time_step_policy('external_multiplier',.7)end
 return true
end,nil,function()return 0 end)
assert(reentrant.freeze()and rate==0)
local accepted=reentrant.set_near_zero(true)
assert(not accepted and rate==.7 and not reentrant.owned,'Cleanup takeover must not be reacquired by a near-zero edit')
assert(reentrant.release())
-- Runtime wiring: opening and refreezing uses the same policy, including close.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps)deps.engine_time_only=true;deps.freeze_rate=function()return 1e-14 end end)
f.open();assert(f.rate==1e-14 and f.runtime.handle.get('freeze_player'))
assert(f.runtime.handle.set('freeze_player',false)and f.rate==1)
assert(f.runtime.toggle_slowmo()and f.rate==.2)
assert(f.runtime.handle.set('freeze_player',true)and f.rate==1e-14)
assert(f.runtime.handle.set('freeze_player',false)and f.rate==.2)
assert(f.runtime.handle.set('freeze_player',true)and f.rate==1e-14)
assert(f.runtime.close(true)and f.rate==1);f.finish()
print('Hover tiny-rate fallback: detection, idle, exact-zero separation, ownership, cleanup, slow motion and runtime transitions passed')

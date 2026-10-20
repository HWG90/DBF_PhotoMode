local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Guard=dofile(root..'hover_guard.lua')
local Simulation=dofile(root..'simulation.lua')
local events={};local mode=0;local install_ok=1;local arm_ok=1;local rate=1;local clock=10;local fail_restore=false
local native={}
function native.PhotoHoverGuardInstall()events[#events+1]='install';return install_ok end
function native.PhotoHoverGuardArm(v)events[#events+1]='arm:'..v;if arm_ok~=0 then mode=v end;return arm_ok end
function native.PhotoHoverGuardInstalled()return install_ok end
function native.PhotoHoverGuardError()return 17 end
function native.PhotoHoverGuardSkipped()return 12 end
function native.PhotoHoverGuardForwarded()return 40 end
local guard=Guard.new(function()return native end)
local sr={World={time=function()return clock end,delta_time=function()return rate==0 and 0 or .016 end},Network={game_session=function()return 1 end},GameSession={other_peers=function()return{}end,synchronizing_peers=function()return{}end}}
local backend={snapshot=function()return{value=rate}end,value=function()return rate end,now=function()return clock end,
 set=function(_,v)events[#events+1]='rate:'..v;if fail_restore and v>0 then error('restore failed')end;rate=v end}
local pause=Simulation.new(sr,function()return 1,2,true end,backend,guard)
assert(pause.start()and rate==0 and mode==1)
assert(table.concat(events,',')=='install,arm:1,rate:0','Guard must arm before the world reaches zero')
assert(pause.release()and rate==1 and mode==1 and guard.pending,'Restoring multiplier must retain guard until a resumed update finishes')
guard.after_update(0);guard.after_update(0/0);guard.after_update(math.huge);assert(mode==1 and guard.pending)
guard.after_update(.016);assert(mode==0 and not guard.pending)
assert(pause.start()and mode==1);fail_restore=true;assert(not pause.release()and mode==1 and not guard.pending)
fail_restore=false;assert(pause.release());assert(pause.start()and mode==1 and not guard.pending,'Re-entering pause cancels queued disarm')
guard.after_update(.016);assert(mode==1,'An update cannot disarm a newly reacquired pause')
assert(pause.start(.2)and rate==.2 and mode==1 and guard.pending);guard.after_update(.016);assert(mode==0)
assert(pause.release());install_ok=0;rate=1;local count=#events
assert(not pause.start()and rate==1 and not pause.paused(),'Failed native guard must not apply zero time')
assert(#events==count+1)
install_ok=1;assert(pause.start());assert(pause.release());arm_ok=0
assert(not guard.after_update(.016)and mode==1 and guard.pending,'Disarm failure must retain retry state')
arm_ok=1;assert(guard.after_update(.016)and mode==0)
local s=guard.state();assert(s.installed and s.skipped==12 and s.forwarded==40)
print('Hover guard: arm-before-zero, resume-frame drain, ownership retry and unsupported-build refusal passed')

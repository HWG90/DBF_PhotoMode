local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local make=dofile(root..'simulation.lua')
local multiplier=1.25;local now=0;local world_time=100;local dt=0
local unit,world={},{};local current=unit;local peers,joining={},{};local fail_restore=false
local sr={World={time=function()return world_time end,delta_time=function()return dt end},
 Network={game_session=function()return {}end},GameSession={other_peers=function()return peers end,synchronizing_peers=function()return joining end}}
local backend={snapshot=function()return {value=multiplier,owner=1}end,value=function()return multiplier end,
 set=function(_,v)if fail_restore and v~=0 then error('restore failed')end;multiplier=v end,now=function()return now end}
local pause=make.new(sr,function()return current,world,true end,backend)
assert(pause.start());assert(multiplier==0);now=0.2;assert(pause.hold());assert(pause.release());assert(multiplier==1.25)
peers={'remote'};assert(pause.start()==false);assert(multiplier==1.25)
peers={};assert(pause.start());joining={'joining'};assert(pause.hold()==false);assert(multiplier==1.25)
joining={};assert(pause.start());current={};assert(pause.hold()==false);assert(multiplier==1.25)
current=unit;assert(pause.start());fail_restore=true;assert(pause.release()==false);assert(pause.paused());fail_restore=false;assert(pause.release())
assert(pause.start());multiplier=0.5;assert(pause.hold()==false);assert(multiplier==0.5)
multiplier=1;assert(pause.start());now=now+0.51;assert(pause.hold());world_time=world_time+0.01
assert(pause.hold()==false);assert(multiplier==1)
assert(pause.start());now=now+0.51;dt=0.01;assert(pause.hold());now=now+.1
assert(pause.hold()and pause.paused(),'A stale completed-frame delta must not reject a stationary world clock');assert(pause.release());assert(multiplier==1)

-- Zero policy readback precedes the final damped gameplay updates. Transient
-- clock progress is allowed only during the bounded acquisition interval.
multiplier=1.25;world_time=200;now=10;dt=.016
assert(pause.start())
for _,time in ipairs({10.15,10.2,10.25,10.35,10.49})do
 now=time;world_time=world_time+.002;dt=dt*.5
 assert(pause.hold()and multiplier==0,'A settling simulation step retired a newly acquired pause')
end
now=10.5;assert(pause.hold(),'The first settled clock sample establishes the stationary baseline')
now=10.6;dt=.005;assert(pause.hold(),'A stale nonzero delta must not override a stable settled clock')
now=10.7;world_time=world_time+.01;dt=0
assert(not pause.hold()and multiplier==1.25,'Actual clock advancement after settling must fail even when delta_time reports zero')

-- Unknown/nonfinite clocks fail closed, including the initial acquisition.
for _,bad in ipairs({0/0,math.huge,-math.huge,'unavailable'})do
 world_time=bad;assert(not pause.start()and multiplier==1.25,'Invalid acquisition clock was accepted')
 world_time=300;now=20;assert(pause.start());now=20.5;assert(pause.hold())
 world_time=bad;assert(not pause.hold()and multiplier==1.25,'Invalid held world clock did not restore the prior rate')
end
world_time=nil;assert(not pause.start()and multiplier==1.25)
world_time=300;now=20;assert(pause.start());now=20.5;assert(pause.hold());world_time=nil
assert(not pause.hold()and multiplier==1.25,'An unavailable settled clock retained zero time')
world_time=300
for _,bad in ipairs({0/0,math.huge,-math.huge,'unavailable'})do
 now=bad;assert(not pause.start()and multiplier==1.25,'Invalid real-time acquisition clock was accepted')
 now=20;assert(pause.start());now=bad
 assert(not pause.hold()and multiplier==1.25,'Invalid real-time clock did not restore the prior rate')
end

-- A new freeze after positive time gets its own settling interval/baseline.
now=30;world_time=500;assert(pause.start());now=30.5;assert(pause.hold())
assert(pause.start(.3));world_time=501;now=30.7;assert(pause.hold());assert(pause.start(0))
now=31;world_time=501.02;assert(pause.hold(),'Re-freezing reused the previous stationary clock baseline')
now=31.21;world_time=501.03;assert(pause.hold());now=31.3;assert(pause.hold())
world_time=world_time+.01;assert(not pause.hold()and multiplier==1.25,'Re-freezing stopped verifying actual clock advancement')
print('Simulation pause: exact multiplier restore, solo/join gates, owner loss, retry and ineffective-pause detection passed')
print('Pause acquisition: bounded damped-step settling, stable-clock verification despite stale delta, finite/available clocks and independent re-freeze baselines passed')

dt=0;world_time=150;multiplier=1.25
assert(pause.start(.2));assert(multiplier==.2 and not pause.paused());world_time=151;now=now+.5;assert(pause.hold())
assert(pause.start(0));assert(multiplier==0 and pause.paused());assert(pause.start(.3));assert(multiplier==.3)
assert(pause.release());assert(multiplier==1.25)
peers={'other'};assert(not pause.start(.2));assert(multiplier==1.25);peers={}
assert(pause.start(.2));joining={'join'};assert(not pause.hold());assert(multiplier==1.25);joining={}
print('Prototype slow motion: pause/rate transitions preserve original speed, world advances, multiplayer/join denied')

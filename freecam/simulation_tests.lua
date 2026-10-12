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
multiplier=1;assert(pause.start());now=now+0.2;assert(pause.hold());world_time=world_time+0.01
assert(pause.hold()==false);assert(multiplier==1)
assert(pause.start());now=now+0.2;dt=0.01;assert(pause.hold()==false);assert(multiplier==1)
print('Simulation pause: exact multiplier restore, solo/join gates, owner loss, retry and ineffective-pause detection passed')

dt=0;world_time=150;multiplier=1.25
assert(pause.start(.2));assert(multiplier==.2 and not pause.paused());world_time=151;now=now+.5;assert(pause.hold())
assert(pause.start(0));assert(multiplier==0 and pause.paused());assert(pause.start(.3));assert(multiplier==.3)
assert(pause.release());assert(multiplier==1.25)
peers={'other'};assert(not pause.start(.2));assert(multiplier==1.25);peers={}
assert(pause.start(.2));joining={'join'};assert(not pause.hold());assert(multiplier==1.25);joining={}
print('Prototype slow motion: pause/rate transitions preserve original speed, world advances, multiplayer/join denied')

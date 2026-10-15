local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Cinema=dofile(root..'cinema_camera.lua')
local photo={active=true,pos={1,2,3},view={yaw=.7,pitch=.2},options={fov=0,roll=17}}
local context={world='mission',epoch=1,player='local:1',gameplay_input=true}
local mode=Cinema.new(photo,function()return context end)
assert(mode.state=='off'and not mode.prepare(.9),'A new runtime must not resume Cinema automatically')
assert(mode.place()and mode.prepare(.9))
photo.pos[1]=99;photo.view.yaw=2;photo.options.roll=80
assert(mode.commit()and mode.state=='perform'and photo.cinema_state=='perform')
assert(photo.pos[1]==1 and photo.view.yaw==.7 and photo.options.roll==17 and math.abs(photo.options.fov-math.deg(.9))<1e-8,'Capture must copy the actual rendered pose and lens')
local shot=mode.snapshot();shot.pos[1]=100;shot.identity.player='other'
for i=1,100 do
 photo.pos={i*100,0,0};photo.view={yaw=4,pitch=-.5};photo.input={mouse_x=1000,forward=true};photo.options.fov=12;photo.options.roll=-30
 assert(mode.hold()and photo.pos[1]==1 and photo.view.yaw==.7 and photo.input.mouse_x==0 and not photo.input.forward,'Avatar/input changes must not move the shot')
end
assert(mode.gameplay_input_ready());context.gameplay_input=false;assert(not mode.gameplay_input_ready())
assert(mode.hold(),'Native menu cursor changes must not retire camera ownership')
assert(mode.reposition()and mode.state=='place'and photo.pos[1]==1 and not mode.snapshot())
photo.options.fov=65;assert(mode.prepare(nil));context.epoch=2;assert(not mode.commit()and mode.state=='place','Scene changes during handoff must refuse activation')
assert(mode.prepare(nil)and mode.commit());context.player='respawned';assert(not mode.hold(),'Respawn must not retain a stale subject')
assert(mode.stop()and mode.state=='off'and not mode.snapshot());mode.place()
photo.pos[1]=0/0;assert(not mode.prepare(.9),'Invalid vectors must never reach camera setters')
photo.pos[1]=1;photo.view.pitch=0/0;assert(not mode.prepare(.9));photo.view.pitch=.2
assert(not mode.prepare(0)and not mode.prepare(math.pi),'Invalid lenses must not be captured')
context=nil;assert(not mode.prepare(.9),'Unknown player/scene identity must refuse activation')
print('Cinema numeric shot: startup off, copied actual pose/lens, static hold, native-menu identity, reposition, scene/respawn invalidation and finite validation passed')

-- Playback uses wall time, including while world simulation is frozen. Calls
-- from both update and render at one timestamp must not advance it twice.
local now=100
local identity={world='mission-a',epoch=4,player='local:7',gameplay_input=true}
local p={active=true,pos={0,0,0},view={yaw=math.rad(179),pitch=0},options={fov=50,roll=0}}
local path=Cinema.new(p,function()return identity end,function()return now end)
local function near(a,b)return math.abs(a-b)<1e-7 end
local function record(x,yaw,fov,duration,transition,roll,pitch)
 p.pos={x,0,0};p.view={yaw=yaw or 0,pitch=pitch or 0};p.options={fov=fov or 50,roll=roll or 0}
 return path.path_add(nil,duration,transition)
end
assert(path.place()and not path.path_prepare(),'A path without points must not acquire Cinema ownership')
assert(record(0,math.rad(179),50,2,'smooth'))
assert(not path.path_prepare(),'A single point is a static shot, not a playable camera path')
assert(not path.path_set_duration(1,0)and not path.path_set_duration(1,61)and not path.path_set_duration(1,0/0))
assert(not path.path_set_transition(1,'unvalidated')and not path.path_set_duration(99,2))
assert(record(10,math.rad(-179),90,3,'smooth'))
local saved=path.path_points();saved[1].pos[1]=999;saved[1].duration=60
assert(path.path_prepare());p.pos={500,500,500};p.options.fov=12
assert(path.commit()and path.state=='perform'and path.path_playing and p.pos[1]==0 and p.options.fov==50)
assert(path.path_snapshot().count==2 and path.path_snapshot().duration==2)
now=101;assert(path.hold())
assert(near(p.pos[1],5)and near(p.options.fov,70),'A smooth segment must interpolate recorded composition and FOV')
assert(math.cos(p.view.yaw)<-.999999 and math.abs(math.sin(p.view.yaw))<1e-7,'Rotation must take the short route across 180 degrees')
local middle=p.pos[1];assert(path.hold()and p.pos[1]==middle,'A second hold at the same timestamp must not double-advance playback')
local info=path.path_snapshot();assert(info.playing and info.index==1 and near(info.elapsed,1)and near(info.fraction,.5))
now=100.5;assert(path.hold()and near(path.path_snapshot().elapsed,1));now=101
assert(path.hold()and near(path.path_snapshot().elapsed,1),'A backwards clock reading must neither rewind nor count the recovered time twice')
now=102;assert(path.hold()and p.pos[1]==10 and near(p.options.fov,90)and not path.path_playing and path.state=='perform','Completion must hold the final camera while keeping avatar control')
now=200;assert(path.hold()and p.pos[1]==10,'Completed paths must not restart or loop')

-- Cuts hold the outgoing frame until its duration expires, then jump with
-- rotation and lens together. Multiple segments consume one shared timeline.
assert(path.reposition()and path.path_clear())
assert(record(0,.1,40,2,'cut')and record(10,.5,60,3,'cut')and record(20,.9,80,1,'smooth'))
assert(path.path_prepare()and path.commit());now=201.999
assert(path.hold()and p.pos[1]==0 and p.view.yaw==.1 and p.options.fov==40)
now=202;assert(path.hold()and p.pos[1]==10 and p.view.yaw==.5 and p.options.fov==60,'A cut must switch exactly at the recorded segment boundary')
now=204.999;assert(path.hold()and p.pos[1]==10)
now=205;assert(path.hold()and p.pos[1]==20 and not path.path_playing,'The last cut must land on the final point')

assert(path.reposition()and path.path_clear())
assert(record(0,0,50,4,'smooth',179)and record(10,0,70,4,'smooth',-179))
assert(path.path_prepare()and path.commit());now=207;assert(path.hold())
assert(math.abs(p.options.roll)>179.9,'Roll must also interpolate around its short arc')
assert(path.path_stop());local paused=p.pos[1];now=300
assert(path.hold()and p.pos[1]==paused and not path.path_playing and path.state=='perform','Stopping playback holds the current composition without taking avatar input')
assert(path.reposition()and path.path_snapshot().count==2 and not path.path_playing,'Repositioning must end playback but keep the editable recorded path')
assert(path.path_remove()and path.path_snapshot().count==1 and path.path_remove(1)and not path.path_remove())
for i=1,32 do assert(record(i,0,50,.1,'cut'))end
assert(not record(33,0,50,.1,'cut')and path.path_snapshot().count==32,'Runtime path storage must remain bounded')
assert(path.path_prepare()and path.commit());now=100000
assert(path.hold()and p.pos[1]==32 and not path.path_playing,'A large real-time jump must finish a bounded path without replaying old frames')

assert(path.reposition()and path.path_prepare());identity.player='respawned'
assert(not path.commit()and path.state=='place'and not path.path_playing,'A respawn during handoff must refuse the whole path')
assert(not path.path_prepare()and not record(0),'Old camera points must never migrate into a new player generation')
assert(path.path_clear()and record(1,0,50,2,'smooth')and record(2,0,50,2,'smooth'))
assert(path.path_prepare()and path.commit());identity.epoch=5
local before=p.pos[1]
assert(not path.hold()and path.state=='off'and p.cinema_state=='off'and not path.path_playing and path.path_snapshot().count==0,'Scene loss must retire all playback state before the next camera write')
assert(p.pos[1]==before and path.hold(),'Retired playback must not write stale world positions')

assert(path.place()and record(1,0,50,2,'smooth')and record(2,0,50,2,'smooth'))
assert(path.path_prepare()and path.cancel()and not path.commit(),'Cancelling a handoff must not start its queued path later')
assert(path.path_prepare()and path.path_clear()and not path.commit(),'Clearing a queued path must not leave its first point armed as a static shot')
assert(record(1,0,50,2,'smooth')and record(2,0,50,2,'smooth'))
assert(path.path_prepare());now=0/0
assert(not path.commit()and not path.path_playing and path.state=='place','An invalid real-time clock must refuse playback before acquiring perform ownership')
print('Cinema camera path: bounded copied points, wall-time playback, shortest quaternion arcs, curve/FOV interpolation, timed cuts, completion/stop, and scene/player retirement passed')

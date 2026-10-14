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

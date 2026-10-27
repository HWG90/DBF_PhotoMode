local s,c,modules,addon,_,bindings=chef_fixture()
assert(addon.capabilities.keyboard_freecam and addon.capabilities.free_mouse_camera)
assert(addon.update==nil and next(s.counts)==nil,'Closed controls perform no native reads')
local controls=assert(modules['wj.chef.controls'].new(c,bindings))
assert(s.specs['wj.chef.clutch'].button=='left alt' and s.specs['wj.chef.forward'].trigger=='hold')
for _=1,1000 do assert(controls.sample(true)==nil) end
assert(next(s.counts)==nil,'Idle controls only ask for the clutch')
s.keys['wj.chef.clutch']=true;s.keys['wj.chef.forward']=true;s.keys['wj.chef.right']=true
local first=assert(controls.sample(true));assert(first.dt==0 and first.dx==0 and first.y==1 and first.x==1)
s.now=s.now+.02;s.dx=5;s.dy=-3
local input=assert(controls.sample(true));assert(input==first and input.dx==5 and input.dy==-3)
assert(math.abs(input.dt-.02)<1e-8 and c.time()==0,'Movement clock must run through freeze')
local queries=s.counts['Mouse.axis_index'];local mouse_reads=s.counts['Mouse.axis']
s.menu=true;s.now=s.now+10
assert(controls.sample(true)==nil and s.counts['Mouse.axis']==mouse_reads,'Menu suppresses mouse as well as keys')
s.menu=false;assert(controls.sample(true).dt==0 and input.dx==0,'No jump on menu handoff')
s.focused=false;assert(controls.sample(true)==nil)
s.focused=true;s.now=s.now+10;assert(controls.sample(true).dt==0)
s.now=s.now+1;assert(controls.sample(false).dt==.1,'Clamp resumed or stalled frames')
assert(s.counts['Mouse.axis_index']==queries,'Resolve the delta axis once')
controls.sample(true);s.skip='Mouse.axis'
local sample,why=controls.sample(true);assert(not sample and why=='skipped')
s.skip=nil;s.dx=0/0
sample,why=controls.sample(true);assert(not sample and why=='Invalid mouse delta')
s.dx=5000;assert(not controls.sample(true));s.dx=0
assert(controls.sample(true).dx==0)
s.keys['wj.chef.clutch']=false;assert(controls.sample(false)==nil)

local motion=modules['wj.chef.motion']
local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local camera=motion.new(frame)
local opts={move_speed=3,turn_speed=60,mouse_sensitivity=.12}
local v=camera.view()
local zero={dt=.1,x=0,y=0,z=0,yaw=0,pitch=0,roll=0,zoom=0,dx=0,dy=0,fast=false}
for _=1,1000 do assert(not camera.step(zero,opts) and camera.view()==v) end
zero.x,zero.y=1,1
assert(camera.step(zero,opts))
local distance=math.sqrt((v.position[1]-1)^2+(v.position[2]-2)^2+(v.position[3]-3)^2)
assert(math.abs(distance-.3)<1e-9,'Diagonal motion must have the same speed')
zero.fast=true
local old=v.position[1];camera.step(zero,opts);assert(math.abs(v.position[1]-old-.3*4/math.sqrt(2))<1e-9)
zero.x,zero.y,zero.yaw,zero.pitch,zero.roll=0,0,1,1,1
for _=1,20000 do assert(camera.step(zero,opts)) end
local nf,nr,nu,dot=0,0,0,0
for i=1,3 do nf=nf+v.forward[i]^2;nr=nr+v.right[i]^2;nu=nu+v.up[i]^2;dot=dot+v.forward[i]*v.up[i] end
assert(math.abs(nf-1)<1e-9 and math.abs(nr-1)<1e-9 and math.abs(nu-1)<1e-9 and math.abs(dot)<1e-9)
zero.yaw,zero.pitch,zero.roll,zero.zoom=0,0,0,-1
for _=1,1000 do camera.step(zero,opts) end
assert(math.abs(v.fov-math.rad(5))<1e-9 and not camera.step(zero,opts))
zero.zoom=1;for _=1,1000 do camera.step(zero,opts) end
assert(math.abs(v.fov-math.rad(120))<1e-9 and not camera.step(zero,opts))
local edits={right=0,forward=1,up=0,yaw=0,pitch=0,roll=0,fov=60}
camera.adjust(edits);assert(math.abs(v.fov-math.pi/3)<1e-9)
local x=v.position[1];camera.adjust(edits);assert(x==v.position[1],'Reapplying unchanged manual edits must not move')
edits.fov=0;camera.adjust(edits);assert(v.fov==1)

-- Integration of real controls, motion and time policy through the runtime.
-- Camera API correctness is exercised separately by camera_tests.lua.
local state,host,mods,unused_addon,unused_shared,control_bindings=chef_fixture()
local captured,applied,held=frame,0,0
local runtime=mods['wj.chef.runtime'].new(host,{
    camera={new=function() return {
        begin=function() return true end,valid=function() return true end,step=function() return true end,
        frame=function() return frame end,
        apply=function(p,f,u,fov) captured={position={unpack(p)},forward=f,up=u,fov=fov};applied=applied+1;return true end,
        maintain=function() held=held+1;return true end,close=function() return true end,
    } end},
    controls=mods['wj.chef.controls'],bindings=control_bindings,
    motion=mods['wj.chef.motion'],simulation=mods['wj.chef.simulation'],composition=mods['wj.composition'],
})
host.set('camera',true);runtime.update()
assert(runtime.status()=='active' and applied==0)
host.set('freeze',true);runtime.update();assert(state.rate==0)
state.keys['wj.chef.clutch']=true;state.keys['wj.chef.forward']=true
runtime.update();local previous=applied
state.now=state.now+.1;runtime.update()
assert(applied==previous+1 and captured.position[1]>frame.position[1] and state.rate==0,
    'Camera controls must continue while simulation is frozen')
state.menu=true;previous=applied;state.now=state.now+.1;runtime.update()
assert(applied==previous,'Menu input must never move the photo camera')
state.menu=false;runtime.update();assert(applied==previous,'No motion on the clutch rearm frame')
host.set('camera',false)
assert(runtime.status()=='closed' and runtime.update==nil and state.rate==1,'Closing camera must thaw and go idle')
assert(runtime.shutdown())
print('chef controls: menu/focus clutch, unscaled motion, raw delta, limits and long-take stability passed')

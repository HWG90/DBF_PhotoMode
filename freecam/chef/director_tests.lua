local s,c,m,unused,unused_shared,bindings=chef_fixture()
local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local held,writes,view=0,0,nil
local runtime=m['wj.chef.runtime'].new(c,{
    camera={new=function() return {begin=function() return true end,valid=function() return s.focused end,
        step=function() return true end,frame=function() return frame end,
        apply=function(p,f,u,fov) writes=writes+1;view={position={unpack(p)},forward={unpack(f)},up={unpack(u)},fov=fov};return true end,
        maintain=function() held=held+1;return true end,close=function() return true end} end},
    controls=m['wj.chef.controls'],bindings=bindings,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=m['wj.composition'],shots=m['wj.chef.shots'],path=m['wj.steam_path'],
})
local function action(id) c.set(id,true);runtime.update() end
c.set('camera',true);runtime.update()
c.set('slow_motion',true);c.set('slow_rate',.25);c.set('freeze',true);runtime.update();assert(s.rate==0)
action('cinema_begin');assert(runtime.cinema_active() and s.rate==.25 and not s.values.freeze)
s.keys['wj.chef.clutch']=true;s.keys['wj.chef.forward']=true
local before=writes;s.now=s.now+.1;runtime.update();assert(writes==before and held>0,'Cinema never consumes movement')
action('cinema_reposition');assert(not runtime.cinema_active() and s.rate==0 and s.values.freeze)
s.keys={};c.set('path_duration',1);action('path_record');c.set('forward',10);action('path_record')
action('cinema_path');assert(runtime.cinema_active() and s.rate==.25 and view.position[1]==1)
s.now=s.now+.5;runtime.update();assert(math.abs(view.position[1]-6)<1e-8)
action('cinema_reposition');assert(s.rate==0 and not runtime.cinema_active())
c.set('path_point',1);c.set('path_duration',2);action('path_edit');action('path_recall');assert(view.position[1]==1)
action('path_remove_selected');assert(runtime.shot_status()==1)
action('lens_apply');assert(math.abs(view.fov-2*math.atan(12/50))<1e-8)
action('camera_portrait');assert(math.abs(view.up[2]-1)<1e-8)
action('camera_level');assert(math.abs(view.up[3]-1)<1e-8)
action('camera_recenter');assert(view.position[1]==1 and view.fov==1)
c.set('lock_camera',true);s.keys['wj.chef.clutch']=true;s.keys['wj.chef.forward']=true
before=writes;s.now=s.now+.1;runtime.update();assert(writes==before)
c.set('lock_camera',false);s.keys={};action('cinema_begin')
s.session=newproxy();runtime.update();assert(runtime.status()=='closed' and s.rate==1 and not runtime.cinema_active())
assert(runtime.shutdown())

-- Commands are press bindings, gated by the clutch and Chef's own menu.
assert(s.specs['wj.chef.freeze'].trigger=='press' and s.specs['wj.chef.light_drag'].button=='middle')
local controls=m['wj.chef.controls'].new(c,bindings)
s.keys={['wj.chef.freeze']=true};assert(controls.command()==nil)
s.keys['wj.chef.clutch']=true;s.menu=true;assert(controls.command()==nil)
s.menu=false;assert(controls.command()=='freeze');s.keys={}

-- Smoothing is bounded, uses the unscaled input clock, and stops immediately
-- on a clutch/menu handoff instead of drifting or accumulating deferred input.
local motion=m['wj.chef.motion'].new(frame)
local input={dt=.01,x=0,y=1,z=0,yaw=0,pitch=0,roll=0,zoom=1,dx=0,dy=0,fast=false}
local opts={move_speed=3,turn_speed=60,mouse_sensitivity=.12,camera_smoothing=true,smoothing_strength=100}
motion.step(input,opts)
assert(motion.view().position[1]>1 and motion.view().position[1]<1.03)
for _=1,100 do motion.step(input,opts) end
local pos,fov=motion.view().position[1],motion.view().fov
for _=1,100 do assert(not motion.step(nil,opts)) end
assert(motion.view().position[1]==pos and motion.view().fov==fov)
input.dt=0;input.dx=999;assert(not motion.step(input,opts))
input.dx=0;input.dt=.01;input.y=0;input.zoom=0;assert(not motion.step(input,opts))
assert(m['wj.chef.shots'].valid(motion.view()))
print('chef director: Cinema time restoration, frozen paths, segment editing, lens/tilt, lock and smoothing handoff passed')

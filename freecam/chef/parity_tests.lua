-- WJ 1.3.0 workflows adapted to Chef's own menu/input services.
local s,c,m,unused,shared,bindings=chef_fixture()
local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local text_count,last_grid,last_logo,wheel_reads=0,nil,nil,0
local composition=m['wj.composition'];local layout=composition.layout_static
composition.layout_static=function(w,h,v) last_grid,last_logo=v.grid,v.logo;return layout(w,h,v) end
function c.screen() return 1920,1080 end
function c.color(...) return {...} end
function c.rect() end
function c.triangle() return true end
function c.text() text_count=text_count+1 end
function c.wheel() wheel_reads=wheel_reads+1;return s.wheel or 0 end
local runtime=m['wj.chef.runtime'].new(c,{
    camera={new=function() return {begin=function() return true end,valid=function() return s.focused end,
        step=function() return true end,frame=function() return frame end,apply=function() return true end,
        maintain=function() return true end,close=function() return true end} end},
    controls=m['wj.chef.controls'],bindings=bindings,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=composition,shots=m['wj.chef.shots'],path=m['wj.steam_path'],
})
local function tick() s.now=s.now+.02;assert(runtime.update);runtime.update() end
assert(runtime.update==nil and next(s.counts)==nil)
c.set('global_shortcuts',true);tick()
for _=1,1000 do tick() end
assert(next(s.counts)==nil,'Opt-in idle shortcuts read bindings only, no engine scans or time reads')
assert(s.specs['wj.chef.global_slow'].button=='backslash')
s.keys['wj.chef.global_camera']=true;s.menu=true;tick();assert(runtime.status()=='closed')
s.menu=false;tick();s.keys={};tick();assert(runtime.status()=='active')
s.keys={['wj.chef.clutch']=true};tick();assert(wheel_reads==0,'Discard input on clutch rearm')
s.wheel=1;tick();assert(math.abs(s.values.move_speed-3.6)<1e-8 and wheel_reads==1)
s.keys={};s.wheel=8;tick();assert(wheel_reads==1)
s.menu=true;s.keys={['wj.chef.clutch']=true};tick();assert(wheel_reads==1);s.menu=false;s.keys={}
c.set('overlay',true);c.set('grid',2);c.set('logo',3);c.set('show_legend',true)
runtime.render();assert(last_grid==2 and last_logo==3 and text_count==1)
c.set('capture_view',true);runtime.render()
assert(last_grid==1 and last_logo==3 and text_count==1,'External capture view removes WJ annotations but keeps photo artwork')
c.set('capture_view',false);runtime.render();assert(last_grid==2 and text_count==2)
c.set('keep_slow_on_close',true);c.set('slow_rate',.3)
s.keys={['wj.chef.global_slow']=true};tick();s.keys={};assert(math.abs(s.rate-.3)<1e-8)
c.set('freeze',true);tick();assert(s.rate==0)
s.keys={['wj.chef.global_camera']=true};tick();s.keys={}
assert(runtime.status()=='closed' and math.abs(s.rate-.3)<1e-8 and not s.values.freeze)
s.keys={['wj.chef.global_slow']=true};s.menu=true;tick();assert(s.values.slow_motion)
s.menu=false;tick();s.keys={};assert(s.rate==1 and not s.values.slow_motion)
s.focused=false;s.keys={['wj.chef.global_camera']=true};tick();assert(runtime.status()=='closed')
s.focused=true;s.keys={};tick();c.set('global_shortcuts',false);assert(runtime.update==nil)
c.set('slow_motion',true);tick();s.focused=false;tick();assert(s.rate==1 and runtime.update==nil)
assert(runtime.shutdown())

local rolled={position={1,2,3},forward={1,0,0},right={0,0,1},up={0,1,0},fov=1}
local motion=m['wj.chef.motion'].new(rolled)
local input={dt=.1,x=0,y=0,z=1,yaw=0,pitch=0,roll=0,zoom=0,dx=0,dy=0,fast=false}
motion.step(input,{move_speed=3,turn_speed=60,mouse_sensitivity=.1,vertical_world=true})
assert(motion.view().position[2]==2 and math.abs(motion.view().position[3]-3.3)<1e-8)
print('chef 1.3 parity: opt-in global shortcuts, bounded idle work, wheel speed, clean external view and slow-motion close passed')

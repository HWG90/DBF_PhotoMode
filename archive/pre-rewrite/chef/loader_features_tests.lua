-- Chef 1.4.0 services (mouse hold, players event, joining, capture) are used
-- only when the loader has them; 1.2.3-1.3.1 keep the earlier paths exactly.
local function count(list,needle)
    local n=0;for _,line in ipairs(list) do if line:find(needle,1,true) then n=n+1 end end;return n
end

-- Probe: nothing from an older loader, and a capability without its helper is not used.
local old_s,old_c,old_m,old_addon=chef_fixture()
local F=old_m['wj.chef.loader_features']
local f=F.probe(old_c)
assert(not f.mouse_hold and not f.players_event and not f.joining and not f.menu_state and not f.capture)
assert(old_s.values.capture_dds==nil and not old_addon.capabilities.mouse_hold,'No 1.4 rows on an older loader')
assert(count(old_s.logs,'mouse hold=no, players event=no, joining=no, capture call=no')==1)
local s,c,m,addon,_,bindings=chef_fixture(nil,'1.4.0')
f=F.probe(c)
assert(f.mouse_hold and f.players_event and f.joining and f.menu_state and f.capture)
assert(addon.capabilities.mouse_hold and addon.capabilities.players_event and s.values.capture_dds==false)
local hold=c.hold_mouse;c.hold_mouse=nil;assert(not F.probe(c).mouse_hold);c.hold_mouse=hold
assert(#s.holds==0 and s.delta_reads==0 and s.joining_reads==0 and s.captures==0 and s.events.players==nil,
    'Starting the addon asks the loader for nothing')

-- Mouse look holds the loader's mouse only while the clutch is held.
local controls=assert(m['wj.chef.controls'].new(c,bindings,f))
for _=1,100 do assert(controls.sample(true)==nil) end
assert(#s.holds==0 and s.delta_reads==0,'Clutch up: no hold and no reads')
s.keys['wj.chef.clutch']=true
local first=assert(controls.sample(true))
assert(s.held and #s.holds==1 and first.dx==0 and first.dy==0,'First held frame starts the count')
assert(s.counts['Mouse.axis']==nil and s.counts['Mouse.axis_index']==nil,'Held mouse never reads the shared axis')
s.now=s.now+.02;s.mdx,s.mdy=4,-2
local input=assert(controls.sample(true));assert(input.dx==4 and input.dy==-2 and controls.mouse_held())
for _=1,500 do s.now=s.now+.02;assert(controls.sample(true)) end
assert(#s.holds==1,'One hold for one clutch press')
local keyboard=assert(controls.sample(false))
assert(keyboard.dx==0 and not s.held and s.holds[#s.holds]==false,'Mouse look off lets go')
s.mdx=9;assert(controls.sample(true).dx==0 and s.held,'Hold again; never reuse a stale delta')
s.now=s.now+.02;assert(controls.sample(true).dx==9)
s.keys['wj.chef.clutch']=false;assert(controls.sample(true)==nil and not s.held,'Clutch release lets go')
s.keys['wj.chef.clutch']=true;controls.sample(true);assert(s.held)
s.menu=true;assert(controls.sample(true)==nil and not s.held,'Chef menu handoff lets go')
s.menu=false;controls.sample(true);s.now=s.now+.02;s.mdx=0/0
local sample,why=controls.sample(true)
assert(not sample and why=='Invalid mouse delta' and not s.held,'Invalid deltas are refused and release the hold')
s.mdx=5000;controls.sample(true);s.now=s.now+.02;assert(not controls.sample(true) and not s.held)
s.mdx=0
-- A refused hold falls back to the shared axis (the game camera may turn too), logs once and backs off.
controls.reset();s.hold_refuse="the mouse can't be held: the game gave no dead zone for it"
local holds=#s.holds
assert(controls.sample(true) and not s.held and s.counts['Mouse.axis']==1)
for _=1,10 do s.now=s.now+.02;assert(controls.sample(true)) end
assert(#s.holds==holds+1 and count(s.logs,'mouse hold unavailable')==1,'A refused hold is not asked every frame')
s.now=s.now+2;controls.sample(true)
assert(#s.holds==holds+2 and count(s.logs,'mouse hold unavailable')==1,'Asks again later; logs a reason once')
s.hold_refuse=nil;s.now=s.now+2;controls.sample(true);assert(s.held)
controls.reset();assert(not s.held)
local throwing=c.hold_mouse;c.hold_mouse=function() error('hold exploded') end
s.now=s.now+2;assert(controls.sample(true) and not s.held,'A throwing hold falls back to the shared axis')
c.hold_mouse=throwing;controls.reset()

-- Runtime: camera close and shutdown always give the mouse back.
local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local applied=0
local runtime=m['wj.chef.runtime'].new(c,{
    camera={new=function() return {begin=function() return true end,valid=function() return true end,
        step=function() return true end,frame=function() return frame end,
        apply=function() applied=applied+1;return true end,maintain=function() return true end,
        close=function() return true end} end},
    controls=m['wj.chef.controls'],bindings=bindings,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=m['wj.composition'],loader_features=F,
})
c.set('mouse_look',true);s.keys={}
c.set('camera',true);runtime.update();assert(runtime.status()=='active' and not s.held)
s.keys={['wj.chef.clutch']=true};s.now=s.now+.02;runtime.update();assert(s.held)
s.mdx=12;s.now=s.now+.02;local before=applied;runtime.update()
assert(applied==before+1,'Held mouse deltas turn the photo camera')
c.set('camera',false);assert(runtime.status()=='closed' and not s.held,'Closing the camera lets the mouse go')
c.set('camera',true);runtime.update();s.now=s.now+.02;runtime.update();assert(s.held)
runtime.shutdown();assert(not s.held,'Stopping the addon lets the mouse go')

-- Time: the players event and chef.joining end solo time at once, and only while time is owned.
local ts,tc,tm=chef_fixture(nil,'1.4.0')
local tf=tm['wj.chef.loader_features'].probe(tc)
local sim=tm['wj.chef.simulation'].new(tc,tf)
for _=1,100 do assert(sim.tick()) end
assert(ts.events.players==nil and ts.joining_reads==0,'No player checks while time is unmodified')
assert(sim.set(true,false,.2) and ts.rate==0 and type(ts.events.players)=='function' and ts.joining_reads==1)
for _=1,1000 do assert(sim.tick()) end
assert(ts.joining_reads==1,'Joining is checked with the bounded solo check, not every frame')
ts.now=ts.now+.25;assert(sim.tick() and ts.joining_reads==2)
ts.events.players(1,0,1);assert(sim.tick() and ts.rate==0 and sim.owned,'A solo count keeps time')
ts.events.players(1,1,1)
local ok,reason=sim.tick()
assert(ok and reason=='Time controls ended: a player is joining' and ts.rate==1 and not sim.owned)
assert(ts.events.players==nil,'The listener ends with the lease')
ts.joining=1;assert(not sim.set(true,false,.2) and ts.rate==1 and not sim.owned,'Never take time while a player joins')
ts.joining=0;assert(sim.set(false,true,.5) and ts.rate==.5)
ts.events.players(2,0,1);assert(sim.tick() and ts.rate==1 and not sim.owned)
assert(sim.set(true,false,.2));ts.events.players(2,0,1)
local writes=#ts.writes;assert(not sim.set(true,true,.3) and ts.rate==1 and not sim.owned,'Edits after a join are refused')
assert(#ts.writes==writes+1 and ts.events.players==nil)
assert(sim.set(true,false,.2));ts.generation=ts.generation+1
assert(sim.tick() and not sim.owned and ts.events.players==nil,'World change also ends the listener')
assert(sim.set(true,false,.2));ts.refuse=true;ts.events.players(2,0,1)
assert(not sim.tick() and sim.pending and ts.rate==0,'A refused thaw stays pending')
ts.refuse=false;ts.now=ts.now+1;assert(sim.tick() and ts.rate==1 and not sim.owned and ts.events.players==nil)
local unsubscribe_on=tc.on;tc.on=function() error('no events today') end
assert(sim.set(true,false,.2) and sim.owned and count(ts.logs,'players event unavailable, polling only')==1)
tc.on=unsubscribe_on;assert(sim.release(true))
-- The older path (no features) never touches events or joining.
local os_,oc,om=chef_fixture()
local old_sim=om['wj.chef.simulation'].new(oc)
assert(old_sim.set(true,false,.2) and os_.events.players==nil and old_sim.release(true))

-- Capture: one request, taken after the Chef menu closes; refusals are reported and not retried.
-- A fresh packaged addon: the runtimes above took over the first fixture's option callbacks.
s,c,m,addon=chef_fixture(nil,'1.4.0')
local function tick(seconds)
    s.now=s.now+(seconds or 0)
    if addon.update then addon.update() end
end
s.menu=true;s.notices={}
c.set('capture_dds',true);assert(s.values.capture_dds==false,'Action rows reset')
tick();assert(s.captures==0 and s.notices[#s.notices]=='Screenshot waits for the Chef menu to close')
for _=1,100 do tick(.02) end
assert(s.captures==0,'Never photograph the Chef menu')
s.menu=false;tick();tick(.1);assert(s.captures==0,'Let the menu leave the screen first')
tick(.2);assert(s.captures==1 and s.notices[#s.notices]:find('goose_war_journalist_capture_01.dds',1,true))
assert(addon.update==nil,'Idle again after the screenshot')
c.set('capture_dds',true);tick();s.menu=true;tick(.3);assert(s.captures==1,'Menu reopened during the delay')
s.menu=false;tick();tick(.3);assert(s.captures==2)
s.capture_refuse='not available to this mod'
c.set('capture_dds',true);tick();tick(.3)
assert(s.captures==3 and s.notices[#s.notices]=='Screenshot not saved: not available to this mod')
for _=1,100 do tick(.1) end
assert(s.captures==3 and addon.update==nil,'A refusal is not retried')
s.capture_refuse=nil;s.menu=true
c.set('capture_dds',true);tick();c.set('capture_dds',true);tick()
assert(s.notices[#s.notices]=='A screenshot is already waiting')
addon.shutdown();s.menu=false
for _=1,10 do tick(.3) end
assert(s.captures==3,'Stopping cancels a waiting screenshot')
print('chef 1.4 services: guarded probe, loader mouse hold, players/joining time guard and menu-safe capture passed')

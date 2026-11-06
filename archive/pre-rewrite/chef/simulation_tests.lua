local s,c,modules,addon,shared=chef_fixture()
local factory=modules['wj.chef.simulation']
local sim=factory.new(c)
for _=1,1000 do assert(sim.tick()) end
assert(next(s.counts)==nil and #s.writes==0,'Unmodified time must be idle')
assert(sim.set(false,true,.2) and s.rate==.2 and sim.owned)
assert(sim.set(true,true,.2) and s.rate==0 and sim.frozen)
local writes=#s.writes
assert(sim.set(true,true,.4) and sim.set(true,false,.6) and sim.set(true,true,.3))
assert(#s.writes==writes and s.rate==0,'Frozen speed edits must not unpause or rewrite')
assert(sim.set(false,true,.3) and s.rate==.3)
local reads=s.counts['GameSession.peers'];writes=#s.writes
for _=1,1000 do assert(sim.tick()) end
assert(s.counts['GameSession.peers']==reads and #s.writes==writes)
s.now=s.now+.25;assert(sim.tick() and s.counts['GameSession.peers']==reads+1)
assert(sim.set(false,true,.3) and #s.writes==writes)
assert(sim.set(true,true,.3));s.peers={local_peer=true,joining_peer=true}
s.now=s.now+.25;assert(sim.tick() and s.rate==1 and not sim.owned,'Visible joining peer must thaw')
assert(not sim.set(true,false,.2) and s.rate==1)
s.peers={};assert(not sim.set(true,false,.2))
s.peers={local_peer=true};assert(sim.set(true,false,.2));s.focused=false
assert(sim.tick() and s.rate==1 and not sim.owned,'Focus loss must resume')
s.focused=true;assert(sim.set(true,false,.2));s.world={};s.generation=s.generation+1
assert(sim.tick() and s.rate==1)
assert(sim.set(false,true,.4));s.session=newproxy();s.now=s.now+.25
assert(sim.tick() and s.rate==1)
assert(sim.set(true,false,.2));s.refuse=true
assert(not sim.release(true) and sim.pending and sim.owned)
writes=#s.writes
for _=1,1000 do assert(not sim.tick()) end
assert(#s.writes==writes,'Failed restore must not hammer the setter')
s.now=s.now+1;assert(not sim.tick() and #s.writes==writes+1)
s.refuse=false;assert(sim.set(false,false,.2) and not sim.owned and s.rate==1)
s.skip='Application.set_time_step_policy'
assert(not sim.set(true,false,.2) and sim.pending and sim.owned,'Guarded nil/reason cannot report success')
s.skip=nil;assert(sim.release(true) and not sim.owned)
assert(sim.set(true,false,.2))
local replacement={owner='cooperating replacement'};shared['dbf.war_journalist.time_owner']=replacement
writes=#s.writes;assert(sim.tick() and not sim.owned and #s.writes==writes)
assert(shared['dbf.war_journalist.time_owner']==replacement,'Never clear another time owner')
assert(not sim.set(true,false,.2) and #s.writes==writes)
shared['dbf.war_journalist.time_owner']=nil;s.rate=1
assert(sim.set(true,false,.2));s.skip='Network.game_session';s.now=s.now+.25
assert(sim.tick() and s.rate==1 and not sim.owned,'Refused peer check must thaw')
s.skip=nil;assert(sim.set(true,false,.2));s.skip='Application.time_since_launch';s.refuse=true
assert(not sim.tick() and sim.pending)
writes=#s.writes;for _=1,100 do assert(not sim.tick()) end
assert(#s.writes==writes,'Broken clock must not defeat restore backoff')
s.refuse=false;assert(sim.release(true) and s.rate==1);s.skip=nil
assert(not sim.set(true,false,0/0) and not sim.set(true,false,0) and not sim.set(true,false,2))

-- Actual runtime: time-only changes schedule work; successful cleanup removes it.
c.set('slow_motion',true);c.set('slow_rate',.4);assert(addon.update)
writes=#s.writes;addon.update();assert(s.rate==.4 and #s.writes==writes+1)
c.set('freeze',true);addon.update();assert(s.rate==0)
c.set('slow_rate',.5);writes=#s.writes;addon.update();assert(s.rate==0 and #s.writes==writes)
c.set('freeze',false);addon.update();assert(s.rate==.5)
c.set('slow_motion',false);addon.update();assert(s.rate==1 and addon.update==nil)
c.set('freeze',true);addon.update();s.events.world(2,false)
assert(s.rate==1 and s.values.freeze==false and addon.update==nil)
c.set('freeze',true);addon.update();assert(addon.shutdown() and s.rate==1 and addon.update==nil)
assert(not s.events.world)
print('chef simulation: solo guard, frozen slow-motion edits, lease handoff, bounded cleanup and runtime shutdown passed')

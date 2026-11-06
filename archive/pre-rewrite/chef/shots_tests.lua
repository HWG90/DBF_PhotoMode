local s,c,mods,addon,shared,bindings=chef_fixture()
local factory=mods['wj.chef.shots']
local loads,saves,data,save_error=0,0,nil,false
function c.load_table(name) assert(name=='camera_presets_v1');loads=loads+1;return data,data and nil or 'none saved' end
function c.save_table(name,value)
    assert(name=='camera_presets_v1');saves=saves+1
    if save_error then return false,'disk full' end
    data=value;return true
end
local function view(x)
    return {position={x or 1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
end
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' ~= '..tostring(b)) end
local function same(a,b)
    for _,key in ipairs({'position','forward','right','up'}) do for i=1,3 do near(a[key][i],b[key][i]) end end
    near(a.fov,b.fov)
end
local shots=factory.new(c,mods['wj.steam_path'])
for _=1,1000 do assert(not shots.sample() and shots.count()==0 and not shots.playing()) end
assert(loads==0 and saves==0 and next(s.counts)==nil,'No idle clocks or save reads')
assert(not shots.record(view(),1,1) and not shots.preset('save',1,view()))
shots.begin(view());assert(not shots.play())
local original=view(5)
assert(shots.bookmark('save',1,original));original.position[1]=999
local mark=assert(shots.bookmark('recall',1));near(mark.position[1],5)
mark.position[1]=888;near(shots.bookmark('recall',1).position[1],5)
assert(shots.record(view(),1,1));assert(shots.record(view(11),1,1));assert(shots.play())
local frame=assert(shots.sample());same(frame,view())
s.now=s.now+.5;assert(shots.sample()==frame);near(frame.position[1],6)
assert(c.time()==0 and shots.playing(),'Playback uses unscaled wall time')
s.now=s.now+.5;same(shots.sample(),view(11));assert(not shots.playing())
local clocks=s.counts['Application.time_since_launch']
for _=1,1000 do assert(shots.sample()==nil) end
assert(s.counts['Application.time_since_launch']==clocks)
shots.clear()
local rolled=mods['wj.chef.motion'].new(view())
rolled.adjust({right=0,forward=0,up=0,yaw=35,pitch=60,roll=120,fov=70})
assert(shots.record(rolled.view(),.1,2));assert(shots.record(view(21),1,1));assert(shots.play())
same(shots.sample(),rolled.view());s.now=s.now+.05;same(shots.sample(),rolled.view())
s.now=s.now+.06;same(shots.sample(),view(21))
shots.clear()
for _=1,32 do assert(shots.record(view(),1,1)) end
assert(not shots.record(view(),1,1) and shots.count()==32)
assert(shots.remove() and shots.count()==31)
assert(shots.play());s.now=s.now-1
local result,why=shots.sample();assert(not result and why=='Camera path clock changed' and not shots.playing())
s.skip='Application.time_since_launch';assert(not pcall(shots.play));s.skip=nil

-- Full orientation, translation and lens are saved in the opening camera's
-- coordinate frame, never a guessed player frame or a native handle.
shots.begin(view());assert(shots.preset('save',2,rolled.view()))
rolled.view().position[1],rolled.view().position[2],rolled.view().position[3]=6,-1,5
assert(shots.preset('save',2,rolled.view()))
assert(loads==1 and saves==2 and data.version==1 and factory.valid(data.slots[2]))
same(shots.preset('recall',2),rolled.view())
local second=view(101);second.forward={0,1,0};second.right={1,0,0}
shots.reset();shots.begin(second)
assert(not shots.bookmark('recall',1),'Bookmarks must not leak between camera sessions')
local shifted=assert(shots.preset('recall',2));assert(factory.valid(shifted))
near(shifted.position[1],second.position[1]+3);near(shifted.position[2],second.position[2]+5)
near(shifted.position[3],second.position[3]+2)
local saved=shifted.position[1];shifted.position[1]=999
near(shots.preset('recall',2).position[1],saved)
local fresh=factory.new(c,mods['wj.steam_path']);fresh.begin(second)
same(fresh.preset('recall',2),shots.preset('recall',2));assert(loads==2)
save_error=true
assert(not shots.preset('save',2,view(200)))
near(shots.preset('recall',2).position[1],saved)
save_error=false;assert(shots.preset('clear',2));assert(not shots.preset('recall',2))
assert(not shots.preset('save',6,view()) and not shots.preset('save',1,{fov=1}))
local bad=view();bad.right={0,1,0};assert(not factory.valid(bad))
bad=view();bad.position[3]=0/0;assert(not factory.valid(bad))
for _,corrupt in ipairs({{version=2,slots={}},{version=1,slots={[6]=view()}},{version=1,slots={[1]=bad}}}) do
    data=corrupt;local broken=factory.new(c,mods['wj.steam_path']);broken.begin(view())
    local before=saves;assert(not broken.preset('save',1,view()) and saves==before,'Never overwrite corrupt saves')
end
function c.load_table() return nil,'decode failed' end
local broken=factory.new(c,mods['wj.steam_path']);broken.begin(view())
assert(not broken.preset('save',1,view()))

-- Integrate queued actions, freeze, manual takeover and lifecycle cleanup.
local st,host,m,unused,unused_shared,keys=chef_fixture()
local applied,captured=0,nil
local runtime=m['wj.chef.runtime'].new(host,{
    camera={new=function() return {
        begin=function() return true end,valid=function() return st.focused end,step=function() return true end,
        frame=function() return view() end,
        apply=function(p,f,u,fov) applied=applied+1;captured={p[1],p[2],p[3]};return true end,
        maintain=function() return true end,close=function() return true end,
    } end},
    controls=m['wj.chef.controls'],bindings=keys,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=m['wj.composition'],shots=m['wj.chef.shots'],path=m['wj.steam_path'],
})
host.set('path_record',true);assert(st.values.path_record==false and runtime.update)
runtime.update();assert(runtime.update==nil and runtime.shot_status()==0)
host.set('camera',true);runtime.update();host.set('path_duration',1)
host.set('path_record',true);runtime.update()
host.set('forward',10);host.set('path_record',true);runtime.update()
assert(runtime.shot_status()==2 and captured[1]==11,'Pending edits precede recording')
host.set('freeze',true);host.set('path_play',true);runtime.update();near(captured[1],1)
st.now=st.now+.5;runtime.update();near(captured[1],6);assert(st.rate==0)
st.keys['wj.chef.clutch']=true;runtime.update()
local count,playing=runtime.shot_status();assert(count==2 and not playing,'Clutch takes over without a position jump')
near(captured[1],6);st.keys['wj.chef.clutch']=false
host.set('bookmark_save',true);runtime.update()
host.set('forward',11);runtime.update();near(captured[1],7)
host.set('bookmark_recall',true);runtime.update();near(captured[1],6)
host.set('path_play',true);runtime.update();st.focused=false;runtime.update()
assert(runtime.status()=='closed' and runtime.shot_status()==0 and st.rate==1 and runtime.update==nil)
assert(runtime.shutdown())
print('chef shots: paths, copied bookmarks, validated relative saves, manual takeover and frozen playback passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Simulation=dofile(root..'simulation.lua');local Options=dofile(root..'photo_options.lua')
local Cinema=dofile(root..'cinema_camera.lua')
local function fixture(hover,cinema_enabled)
    local f={keys={},rate=1.25,epoch=10,world_time=20,clock=1,focused=true,allowed=true,unit=1,world=2,logs={},writes={}}
    local api=Core.new(nil,function()end);api.is_open=function()return false end
    api.photo_resolution=function()return 1920,1080 end;api.create_photo_view=function()return{}end
    api.camera_input={down=function(k)return f.keys[k]or false end,focused=function()return f.focused end,
        pause_allowed=function()return f.allowed end,acquire=function()f.owned=true;return{}end,
        release=function()f.owned=false;return true end,sample=function()return{dt=.016,wheel=0,mouse_x=0,mouse_y=0}end}
    local sr={Network={game_session=function()return 1 end},GameSession={other_peers=function()return f.peers or{}end,synchronizing_peers=function()return{}end},
        World={time=function()return f.world_time end,delta_time=function()return f.rate==0 and 0 or .016*f.rate end}}
    local backend={snapshot=function()return{value=f.rate}end,value=function()return f.rate end,now=function()return f.clock end,
        set=function(_,rate)assert(not f.reject_zero or rate~=0,'zero denied');f.rate=rate;f.writes[#f.writes+1]=rate end}
    local guard
    if hover then
        guard={prepare=function()f.prepared_epoch=f.epoch;f.guard_owned=true;return true end,
            ready=function()return f.epoch>(f.prepared_epoch or f.epoch),'Waiting for positive gameplay update'end,
            acquire=function()assert(f.epoch>f.prepared_epoch,'Hover freeze skipped completed update');return true end,
            release=function()f.guard_owned=false;return true end,hold=function()return true end,
            status=function()return{owned=f.guard_owned}end}
    end
    f.freeze=Simulation.new(sr,function()return f.unit,f.world,true end,backend,guard)
    local factory={new=function(_,actions)
        f.actions=actions
        return{bind=function()end,draw=function()end,tick=function()end,close=function()return true end,
            editing_key=function()return false end,editing_text=function()return false end}
    end}
    f.photo={};DBFMCM=api
    if cinema_enabled then f.cinema=Cinema.new(f.photo,function()return{world=f.world,epoch=1,player=f.unit,gameplay_input=true}end,function()return f.clock end)end
    f.controller=Controller.new(f.photo,{},function()return true end,function(message)f.logs[#f.logs+1]=message end,f.freeze,Options,nil,factory,nil,nil,nil,nil,nil,nil,nil,nil,function()return f.epoch end,nil,nil,nil,f.cinema)
    function f.tick()f.clock=f.clock+.016;f.controller.tick(.016)end
    function f.update()f.epoch=f.epoch+1;if f.rate>0 then f.world_time=f.world_time+.016*f.rate end;f.tick()end
    function f.press(key)f.keys[key]=true;f.tick();f.keys[key]=false;f.tick()end
    f.tick();f.handle=api.mods.dbf_freecam.handle
    return f
end
local function near(a,b)assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b))end
local f=fixture();local h=f.handle
assert(h.set('slowmo_speed',.35));f.press(220);near(f.rate,.35);assert(f.controller.slowmo_active)
f.press(80);assert(f.photo.active and f.freeze.paused()and f.controller.slowmo_active,'Photo entry discarded active slow motion');near(h.get('slowmo_speed'),.35)
local frozen,enabled,rate=f.actions.freeze_state();assert(frozen and enabled and rate==0)
local selected,can_slow=f.actions.slowmo_state();assert(selected and can_slow,'Slow-motion selection disappeared while frozen')
assert(f.actions.freeze());near(f.rate,.35);assert(not h.get('freeze_player')and f.controller.slowmo_active,'Unfreeze did not resume the active rate')
assert(f.actions.freeze());near(f.rate,0);assert(h.set('slowmo_speed',.55));near(f.rate,0)
assert(f.actions.freeze());near(f.rate,.55);near(h.get('slowmo_speed'),.55)
assert(f.actions.freeze());f.press(80);near(f.rate,.55);assert(not f.photo.active and f.controller.slowmo_active,'Photo exit discarded active slow motion')
f.press(80);assert(f.photo.active and f.freeze.paused());assert(f.actions.freeze());near(f.rate,.55)
f.press(220);near(f.rate,1.25);assert(not f.controller.slowmo_active,'Disabling slow motion did not restore the original gameplay rate');near(h.get('slowmo_speed'),.55)
assert(f.actions.freeze());assert(f.actions.slowmo());near(f.rate,0);assert(f.controller.slowmo_active,'Slow-motion toggle bypassed an active freeze')
assert(f.actions.freeze());near(f.rate,.55);assert(h.set('slowmo_speed',.4));near(f.rate,.4,'Active slider edit did not update simulation')
assert(f.controller.close());near(f.rate,1.25)

-- Standard speed is restored exactly, and actual state wins over stale settings.
f=fixture();h=f.handle;f.press(80);near(f.rate,0);assert(f.actions.freeze());near(f.rate,1.25)
assert(h.set('freeze_player',true));near(f.rate,0);assert(f.freeze.release());near(f.rate,1.25)
frozen,enabled=f.actions.freeze_state();assert(not frozen and enabled and h.get('freeze_player'),'Footer confused saved checkbox with actual pause')
assert(f.actions.freeze());near(f.rate,0);assert(f.controller.close());near(f.rate,1.25)

-- Hover preparation runs at the chosen positive rate, waits for an engine
-- update, and does not clear the underlying policy during entry or refreeze.
f=fixture(true);h=f.handle;assert(h.set('slowmo_speed',.25));f.press(220);near(f.rate,.25)
f.press(80);assert(f.controller.entry_pending()and f.controller.slowmo_active and not f.photo.active);near(f.rate,.25)
f.update();assert(f.photo.active and f.freeze.paused());assert(f.actions.freeze());near(f.rate,.25)
assert(f.actions.freeze()and f.controller._freeze_action_pending);near(f.rate,.25)
f.tick();near(f.rate,.25);assert(f.controller._freeze_action_pending,'Lua tick was mistaken for a completed engine update')
f.update();near(f.rate,0);assert(not f.controller._freeze_action_pending)
f.press(80);near(f.rate,.25);assert(f.controller.slowmo_active and h.get('slowmo_speed')==.25)
assert(f.controller.close());near(f.rate,1.25)

-- Availability cannot offer a zero timestep in multiplayer or while a
-- camera/pose/hover ownership transition is pending.
f=fixture();f.press(80);f.allowed=false;frozen,enabled=f.actions.freeze_state();assert(frozen and not enabled and not f.actions.freeze());near(f.rate,0)
selected,can_slow=f.actions.slowmo_state();assert(not can_slow and not f.actions.slowmo(),'Multiplayer offered a simulation-rate write')
f.allowed=true;f.controller._pose_time_pending={};frozen,enabled=f.actions.freeze_state();assert(not enabled);f.controller._pose_time_pending=nil
f.freeze.cleanup_pending=function()return true end;frozen,enabled=f.actions.freeze_state();assert(not enabled)
f.freeze.cleanup_pending=function()return false end;f.controller._cinema={state='perform',stop=function()end,cancel=function()end};frozen,enabled=f.actions.freeze_state();assert(not enabled)
f.controller._cinema=nil;assert(f.controller.close());near(f.rate,1.25)

-- A refused zero write fails closed to the original policy, retaining the
-- chosen speed for the next explicit request rather than retrying ownership.
f=fixture();assert(f.handle.set('freeze_player',false));f.press(220);f.press(80);f.reject_zero=true
assert(not f.actions.freeze()and not f.freeze.paused());near(f.rate,1.25);assert(not f.controller.slowmo_active and f.handle.get('slowmo_speed')==.2)
f.reject_zero=false;assert(f.controller.close());near(f.rate,1.25)

-- Action shots only lift Freeze. Keep the active slow-motion ownership and
-- original baseline across gameplay handoff, repositioning and Photo exit.
f=fixture(false,true);h=f.handle
assert(h.set('slowmo_speed',.3));f.press(220);near(f.rate,.3)
f.press(80);near(f.rate,0);assert(h.set('slowmo_speed',.45));near(f.rate,0)
assert(h.set('fov',60));f.photo.pos={1,2,3};f.photo.view={yaw=.2,pitch=.1};f.tick()
local writes_before=#f.writes
assert(h.activate('cinema_begin'));f.tick()
near(f.rate,.45);assert(f.cinema.state=='perform'and not f.owned and f.controller.slowmo_active and h.get('slowmo_speed')==.45 and not h.get('freeze_player'),'Static action shot discarded the cached slow-motion resume policy')
for i=writes_before+1,#f.writes do near(f.writes[i],.45)end
for i=1,10 do f.update();near(f.rate,.45)end
f.press(80);near(f.rate,.45);assert(f.cinema.state=='place'and f.owned and f.controller.slowmo_active,'Repositioning changed the action-shot timescale')
writes_before=#f.writes;assert(h.activate('cinema_begin'));f.tick();near(f.rate,.45)
assert(#f.writes==writes_before and not f.owned and f.controller.slowmo_active,'An already-unpaused slow-motion action shot rewrote its timescale')
f.press(80);near(f.rate,.45)
assert(f.controller.stop());near(f.rate,.45);assert(f.controller.slowmo_active and h.get('slowmo_speed')==.45,'Photo exit discarded the slow-motion selection')
assert(f.controller.close());near(f.rate,1.25)

-- The path uses exactly the same resume policy, including a qualified hover
-- pause. Playback's camera clock advances independently of the retained rate.
f=fixture(true,true);h=f.handle
assert(h.set('slowmo_speed',.25));f.press(220);f.press(80);f.update();near(f.rate,0)
assert(h.set('slowmo_speed',.6)and h.set('fov',70));f.photo.pos={0,0,0};f.photo.view={yaw=0,pitch=0};f.tick()
assert(h.activate('path_add')and h.set('path_duration',1));f.photo.pos={10,0,0};assert(h.activate('path_add'));f.tick()
writes_before=#f.writes;assert(h.activate('path_play'));f.tick()
near(f.rate,.6);assert(f.cinema.path_playing and not f.owned and not f.guard_owned and f.controller.slowmo_active,'Camera path did not resume its selected slow rate after hover restoration')
for i=writes_before+1,#f.writes do near(f.writes[i],.6)end
f.clock=f.clock+.5;f.tick();near(f.rate,.6);assert(f.photo.pos[1]>0 and f.photo.pos[1]<10,'Slow simulation time incorrectly drove camera-path playback')
f.press(80);near(f.rate,.6);assert(f.cinema.state=='place'and not f.cinema.path_playing and f.owned)
writes_before=#f.writes;assert(h.activate('path_play'));f.tick();near(f.rate,.6)
assert(#f.writes==writes_before and f.cinema.path_playing and not f.owned,'An already-unpaused camera path rewrote its timescale')
f.press(80);near(f.rate,.6)
assert(f.controller.stop());near(f.rate,.6);assert(f.controller.slowmo_active,'Path exit cleared the active slow-motion policy');near(h.get('slowmo_speed'),.6)
assert(f.controller.close());near(f.rate,1.25)

-- Without Slow Motion selected, unpausing keeps the pre-Photo gameplay rate.
f=fixture(false,true);h=f.handle;f.press(80);near(f.rate,0)
assert(h.set('fov',60));f.photo.pos={1,2,3};f.photo.view={yaw=0,pitch=0};f.tick()
assert(h.activate('cinema_begin'));f.tick();near(f.rate,1.25)
assert(not f.controller.slowmo_active and f.cinema.state=='perform'and not f.owned,'A plain action shot invented a slow-motion policy')
assert(f.controller.close());near(f.rate,1.25)
DBFMCM=nil
print('Simulation controls: retained active rates, freeze/resume and Photo transitions, frozen edits, original-speed restore, hover update qualification, footer actual-state and solo/ownership gates passed')
print('Cinema timescale: static/path shots only unfreeze, retained selected slow rate and cache across handoff/reposition/exit, qualified hover restoration, wall-time path playback and exact original-speed restore passed')

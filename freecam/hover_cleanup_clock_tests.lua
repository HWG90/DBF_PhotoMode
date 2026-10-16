-- Exercise the actual generated completed-update bridge with the real guard.
local root=assert(DBF_PHOTO_TEST_ROOT)
local Guard=dofile(root..'hover_pause.lua')
local body=assert(INDEPENDENT_RUNTIME_SOURCE:match('H%.dbf_input_after_update=function%(%.%.%.%)\n(.-)\nend\nH%.dbf_input_before_update='))
local function fixture()
 local state={value=6,epoch=10,dt=.016,delta=.016,world='world',reads=0,updates=0}
 local backend={snapshot=function()return{identity='pack',generation=1,active=true,hover=true,value=state.value,epoch=state.epoch,dt=state.dt,control={x=0,y=0,z=0},action=0}end,
 input_supported=function()return true end,
 set=function(_,v)state.value=v;return true end,restore=function(_,v)state.value=v;return true end,
 after_update=function(dt)state.epoch=state.epoch+1;state.dt=dt;state.updates=state.updates+1 end}
 local guard=Guard.new(backend)
 local env={H={dbf_input_epoch=0,dbf_hover_pause=guard,dbf_hover_pause_backend=backend},target=nil,PHOTO={active=false},
 DBF_PLAYER_FREEZE={rate=function()return 1 end},
 sr={Application={main_world=function()state.reads=state.reads+1;return state.world end},World={delta_time=function()return state.delta end}},
 world_alive=function(w)return w=='world'end,try=function(fn,...)if fn then return fn(...)end end}
 setmetatable(env,{__index=_G})
 local callback=assert(loadstring('return function(...)\n'..body..'\nend'))();setfenv(callback,env)
 assert(guard.prepare()and state.value==0);backend.after_update(.016);assert(guard.acquire());assert(guard.release()and guard.pending)
 return state,guard,env,callback
end
local s,g,e,callback=fixture()
local before=s.updates;assert(callback('kept',nil,7)=='kept')
assert(s.updates==before+1 and s.value==6 and not g.pending,'Camera idle stranded the hover override')
local reads=s.reads;before=s.updates;callback();assert(s.reads==reads and s.updates==before,'Clean idle reintroduced background polling')
s,g,e,callback=fixture();s.delta=0;callback();assert(g.pending and s.value==0,'Zero-delta update restored hover unsafely')
s.delta=.016;callback();assert(s.value==6 and not g.pending,'Positive update failed to complete deferred restoration')
s,g,e,callback=fixture();s.world=nil;callback();assert(g.pending and s.value==0,'Missing main world manufactured progress')
s.world='foreign';callback();assert(g.pending and s.value==0,'Unverified world manufactured progress')
s.world='world';callback();assert(s.value==6 and not g.pending)
s,g,e,callback=fixture();e.target={world='retired'};callback();assert(s.updates==2 and not g.pending,'Retired camera target blocked cleanup clock')
print('Generated hover cleanup clock: idle target removal, positive-step restoration, zero/unknown-world refusal and clean idle no-polling passed')

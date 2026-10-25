local ready,ticks,flushes,clears,frames=0,0,0,0,0
local available,clear_ok,flush_ok=true,true,true
local rows={};local calls={};local scene
local level_set={{}};local generations={}
local manager={pending=false,revision=0,status='ready'}
function manager.ready()ready=ready+1;return available,'asset unavailable'end
function manager.tick(w,f)assert(w=='world'and f.position);generations[#generations+1]=select(2,manager.scene_context());ticks=ticks+1;return true end
function manager.list()return rows end
function manager.follows_camera()return rows[1]and rows[1].values.follow_camera or false end
function manager.flush(w,f)
 assert(w=='world'and f.position);flushes=flushes+1;manager.pending=false
 if not flush_ok then return false,'write refused'end
 return true
end
function manager.queue(a,v)calls[#calls+1]={a,v};manager.pending=true;return true end
function manager.clear()clears=clears+1;if not clear_ok then return false,'destroy refused'end;rows={};return true end
function manager.release(reason)assert(reason=='photo mode exited','Closing must retain definitions');return manager.clear()end
function manager.selected()return rows[1]and rows[1].values or nil,1,#rows end
function manager.export_setup()return{definitions={},selected=1}end
local light=dofile('freecam/steam_lighting.lua').new({World={levels=function()return level_set end},Light={set_falloff_end=function()end}},
 {new=function(native)assert(type(native.Light.set_falloff_end)=='function');return manager end},function()end)
local frame=function()frames=frames+1;return{position={0,0,0}}end
for i=1,100 do assert(light.tick(frame))end
assert(frames==0 and ready==0 and ticks==0,'Closed lighting must not read native state')
available=false;assert(not light.open('world',1,frame()));assert(not light.action('create'));assert(light.close());assert(clears==0)
available=true;assert(light.open('world',2,frame()));local baseline=frames
for i=1,100 do assert(light.tick(frame))end
assert(frames==baseline and ticks==1 and ready==2 and flushes==0,'Static lighting must remain idle')
assert(light.change('light_intensity',8));assert(calls[#calls][2].intensity==8)
local basis={position={1,2,3},forward={0,1,0},right={1,0,0},up={0,0,1}}
assert(light.subject('aim',basis,5));assert(calls[#calls][1]=='aim'and calls[#calls][2].target[2]==7)
assert(light.subject('preset',basis,5,'portrait'));assert(calls[#calls][2].name=='portrait')
assert(not light.subject('preset',basis,0/0,'portrait'))
local saved=false;local slots={
 save=function(slot,setup,target,f)assert(slot==2 and setup.definitions and target[2]==7 and f==basis);saved=true;return true end,
 recall=function(slot,target,f)assert(slot==2 and target[2]==7 and f==basis);return{definitions={},selected=1}end,
 clear=function(slot)assert(slot==2);return true end}
assert(light.setup('save',slots,2,basis,5)and saved)
assert(light.setup('recall',slots,2,basis,5));assert(calls[#calls][1]=='import_setup')
assert(light.setup('clear',slots,2,basis,5))
rows={{values={follow_camera=true}}};assert(light.tick(frame));assert(flushes==1)
assert(light.tick(frame));assert(flushes==2,'Following lights need current camera updates')
assert(not light.change('light_follow_player',true),'Never infer player identity from camera')
assert(light.change('light_range',8));assert(calls[#calls][1]=='update'and calls[#calls][2].range==8,'Range control must reach the owned-light manager')
flush_ok=false;assert(not light.tick(frame));local failed=flushes
for i=1,100 do assert(light.tick(frame))end
assert(flushes==failed,'A failed native write must not loop without an explicit retry')
flush_ok=true;assert(light.action('update',{enabled=false}));assert(light.tick(frame));assert(flushes==failed+1)
clear_ok=false;assert(not light.close());assert(clears==1)
assert(not pcall(light.open,'world',3,frame()),'Cannot replace a session whose cleanup is pending')
clear_ok=true;assert(light.close());local ended=frames
for i=1,100 do assert(light.tick(frame))end
assert(frames==ended and clears==2,'Cleanup retry must retain ownership until success')
local generation=generations[#generations]
assert(light.open('world',3,frame()));assert(generations[#generations]==generation,'Camera reopen must retain the same scene generation')
assert(light.close());level_set={{}}
assert(light.open('world',4,frame()));assert(generations[#generations]~=generation,'Replaced levels must retire retained lighting')
assert(light.close())
print('Steam lighting: capability gate, zero static work, current camera follow, explicit write retry and cleanup ownership passed')

-- Following the player is admitted only with an explicit verified provider.
local player_reads=0
local player_light=dofile('freecam/steam_lighting.lua').new({World={levels=function()return level_set end}},
 {new=function()return manager end},function()end,function()player_reads=player_reads+1;return{world='world',position={1,2,3}}end)
assert(player_light.open('world',5,frame()))
assert(player_light.change('light_follow_player',true))
assert(calls[#calls][1]=='set_follow_player'and calls[#calls][2]==true)
manager.follow_player=true;rows={};assert(player_light.tick(frame));local before=flushes
assert(player_light.tick(frame));assert(flushes==before+1,'Player following must keep the update path active without camera-following lights')
assert(type(manager.player_context)=='function'and manager.player_context().position[1]==1 and player_reads==1)
manager.follow_player=false;manager.pending=false;assert(player_light.tick(frame));before=flushes
assert(player_light.tick(frame)and flushes==before,'Stationary non-following lights must return to zero-work idle')
assert(player_light.close())

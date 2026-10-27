local M=dofile('freecam/windows_camera_signals.lua')
do
 local keyboard={button_name=function(id)return id end};local events={};local deliveries,queues=0,0
 local sr={Keyboard=keyboard,InputEventType={BUTTON_PRESSED=1,BUTTON_RELEASED=2},
  Input={event_queue=function()queues=queues+1;return events end}}
 local s=M.new(sr,function()error('Unarmed diagnostics emitted a keyboard sample')end,nil,false,function(name,pressed)
  assert(name=='a'and pressed);deliveries=deliveries+1
 end)
 for _=1,120 do s.tick(false)end;assert(queues==0)
 events={{sender=keyboard,type=1,id='a'}};for _=1,40 do s.tick(true)end
 assert(deliveries==40,'Opt-in movement events outlive the separate diagnostic budget')
 events={{sender=keyboard,type=1,id='w'}};s.tick(true);assert(deliveries==40,'Unrelated keys do not trigger movement trials')
 s.release();s.tick(true);assert(deliveries==40)
end
local lines={};local queues,reads=0,0;local events={};local mouse={button_name=function(id)return id==1 and'right'or'middle'end}
local calls=0;local original=function(...)calls=calls+1;assert(select('#',...)==2);return nil,'tail',nil end
local sr={Gui={set_visible=original},Mouse=mouse,InputEventType={BUTTON_PRESSED=1,BUTTON_RELEASED=2},Input={event_queue=function()queues=queues+1;return events end}}
local p=M.new(sr,function(s)lines[#lines+1]=s end);local gui={}
local result={n=select('#',sr.Gui.set_visible(gui,false)),sr.Gui.set_visible(gui,false)}
assert(result.n==3 and result[1]==nil and result[2]=='tail'and #lines==1 and calls==2,'Observer preserves return arity and only logs changed values')
for _=1,120 do p.tick(false)end;assert(queues==0,'Inactive observer performs no event reads')
events={{sender=mouse,type=1,id=2}};p.tick(true)
assert(lines[#lines]:find('mouse=middle action=pressed',1,true))
local frame={position={0,0,2},forward={1,0,0},fov=1};local head={head={0,0,2}}
local before=#lines;for _=1,120 do p.observe(frame,head)end;assert(#lines==before+3,'Camera samples stop after three frames')
p.release();assert(sr.Gui.set_visible==original);p.tick(true);assert(queues==1)
local q=M.new(sr,function()end);local foreign=function()end;sr.Gui.set_visible=foreign;q.release();assert(sr.Gui.set_visible==foreign,'Preserve a later writer')
print('Camera signals: passive visibility callback, input events only while active, bounded camera observations and foreign-wrapper preservation passed')

local forwarded=0;local hooked=M.new(sr,function()end,function()forwarded=forwarded+1 end)
for i=1,40 do hooked.tick(true)end
assert(forwarded==40,'ADS event delivery must outlive the diagnostic log budget')
hooked.release();hooked.tick(true);assert(forwarded==40)

-- Selected rig observations use only existing events and stop after three samples.
do
 local messages,poses,states,ads={},{},0,0
 local owner,world={},{};local keyboard={button_name=function()return 's'end}
 local test={Mouse=mouse,Keyboard=keyboard,InputEventType=sr.InputEventType,Input=sr.Input,
  Application={main_world=function()return world end},Unit={
   alive=function(u)return u==owner end,world=function()return world end,
   has_node=function(_,name)return name=='weapon_aim'or name=='aim_weapon'end,
   node=function(_,name)return name=='weapon_aim'and 86 or 34 end,
   world_pose=function(_,node)poses[#poses+1]=node;return {}end,
   has_animation_state_machine=function()return true end,
   animation_get_state=function()states=states+1;local a={'idle',nil,'aim'};for i=4,31 do a[i]=i end;return unpack(a,1,31)end},
  Matrix4x4={to_elements=function()return 1,0,0,0,1,0,0,0,1,10,20,30 end}}
 local trace=M.new(test,function(s)messages[#messages+1]=s end,function()ads=ads+1 end,true)
 events={{sender=keyboard,type=1,id=83}};trace.tick(true)
 local selected={head={0,0,2},root_handle=owner,world=world}
 for i=1,100 do trace.observe(frame,selected)end
 assert(#poses==3 and poses[1]==1 and poses[2]==86 and poses[3]==34 and states==1,'Exactly one selected rig node per sample, one animation read per event')
 assert(ads==0,'Movement diagnostics must not change ADS handoff')
 assert(table.concat(messages,'\n'):find('idle|nil|aim',1,true),'Animation layers preserve nil positions')
 assert(table.concat(messages,'\n'):find('values=31',1,true),'Supported 31-value animation snapshot is not rejected')
 test.Unit.animation_get_state=function()local a={};for i=1,80 do a[i]=i end;return unpack(a)end
 trace.tick(true);for i=1,3 do trace.observe(frame,selected)end
 assert(#poses==6,'Oversized optional animation snapshot does not stop known-node capture')
 test.Unit.animation_get_state=function()error('graph retired')end
 trace.tick(true);for i=1,3 do trace.observe(frame,selected)end
 assert(#poses==9,'Optional animation read failure does not stop known-node capture')
 keyboard.button_name=function(id)return id==65 and'a'or'd'end
 for _,key in ipairs({65,68})do events={{sender=keyboard,type=1,id=key}};trace.tick(true);for i=1,3 do trace.observe(frame,selected)end end
 assert(#poses==15 and ads==0,'A/D produce bounded pose observations without changing ADS')
 events={{sender=mouse,type=1,id=2}};trace.tick(true);assert(ads==1)
 selected.world={};trace.observe(frame,selected);local count=#poses
 selected.world=world;trace.observe(frame,selected);assert(#poses==count,'Retired owner disables diagnostic reads for the generation')
 trace.release();trace.tick(true);trace.observe(frame,selected);assert(#poses==count)
 local quiet=M.new(test,function()end,nil,false)
 events={{sender=mouse,type=1,id=2}};quiet.tick(true);quiet.observe(frame,selected)
 assert(#poses==count,'Release configuration does not inspect bones or animation')
 quiet.release()
end

do
 local owner,world={},{};local queries,gets,finds=0,0,0;local lines={};local value=0
 local U={alive=function(u)return u==owner end,world=function()return world end,has_animation_state_machine=function()return true end}
 local test={Unit=U,Application={main_world=function()return world end},Matrix4x4={to_elements=function()return 1,0,0,0,1,0,0,0,1,2,3,4 end}}
 for _,kind in ipairs({'variable','constraint_target'})do
  U['animation_has_'..kind]=function(_,name)queries=queries+1;return name=='focused'end
  U['animation_find_'..kind]=function(_,name)finds=finds+1;assert(name=='focused');return 3 end
  U['animation_get_'..kind]=function(_,index)gets=gets+1;assert(index==3);return value end
 end
 local sample=M.parameters(test,function(s)lines[#lines+1]=s end);local h={root_handle=owner,world=world}
 for i=1,20 do local before=queries;sample(h);assert(queries-before==1,'At most one existence query per bounded sample')end
 assert(finds==1 and gets==1,'Absent parameters never invoke indexed getters')
 value=1;sample(h);assert(gets==2 and lines[#lines]:find('value=1',1,true),'Discovered parameter is freshly read at a later input event')
 local before=queries;sample({root_handle={},world=world});sample(h);assert(queries==before,'Subject change retires the parameter reader')
 local complete=0;for _,s in ipairs(lines)do if s:find('discovery complete',1,true)then complete=complete+1 end end;assert(complete==1)
 for _,kind in ipairs({'variable','constraint_target'})do U['animation_has_'..kind]=function()queries=queries+1;return false end end
 sample=M.parameters(test,function()end);for i=1,20 do sample(h)end;before=queries
 for i=1,120 do sample(h)end;assert(queries==before,'No matches stays idle after bounded discovery')
 U.animation_has_constraint_target=function(_,name)return name=='aim_weapon'end
 U.animation_find_constraint_target=function()return 0 end
 U.animation_get_constraint_target=function()return {}end
 lines={};sample=M.parameters(test,function(s)lines[#lines+1]=s end);sample(h)
 assert(lines[1]:find('constraint=aim_weapon matrix=',1,true),'Constraint index zero is valid and copied immediately')
 U.animation_find_constraint_target=function()return -1 end
 U.animation_get_constraint_target=function()error('invalid index getter must not run')end
 lines={};sample=M.parameters(test,function(s)lines[#lines+1]=s end);sample(h)
 assert(lines[1]:find('Parameter index refused',1,true),'Invalid lookup stops before an indexed native read')
end

-- Read-only native-function environment inventory does not invoke or replace callbacks.
do
 local inventory=dofile('freecam/windows_api_inventory.lua');local messages={};local calls=0
 local env={HUDManager={visible=function()calls=calls+1 end}};local fn=setfenv(function()calls=calls+1 end,env)
 local tables,keys,hits=inventory.hud_environment({},function(s)messages[#messages+1]=s end,{Gui={set_visible=fn},Application={main_world=fn},Unit={camera=fn}})
 assert(hits==2 and calls==0 and getfenv(fn)==env,'Environment inventory must only inspect names, with shared tables scanned once')
end

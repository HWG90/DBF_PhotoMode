assert(_VERSION=='Lua 5.1')
local Probe=dofile('freecam/windows_freeze_physics_probe.lua')
local function fixture()
 local f={reads=0,disables=0,enables=0,alive=true,enabled=true,angle=0,epoch=1,logs={},count=107,mode='position_and_rotation'}
 f.unit=newproxy();f.world=newproxy();f.session=newproxy();f.current_world=f.world;f.current_session=f.session
 local temporaries={}
 local function temp(value)local u=newproxy();temporaries[u]={value=value,epoch=f.epoch};return u end
 local function value(u)local r=assert(temporaries[u]);assert(r.epoch==f.epoch,'Scratch value escaped callback');return r.value end
 local function read(u)assert(u==f.unit);f.reads=f.reads+1 end
 local U={alive=function(u)read(u);return f.alive end,world=function(u)read(u);return f.world end,
  num_scene_graph_items=function(u)read(u);return f.count end,
  resource_name=function(u)read(u);return temp(f.wrong_resource and'other'or'4d1c334d294dfa97')end,
  animation_bone_mode=function(u)read(u);return f.mode end,
  local_rotation=function(u,index)read(u);assert(index==1);local a=math.rad(f.angle)/2;return temp({0,0,math.sin(a),math.cos(a)})end,
  disable_physics=function(u)read(u);f.disables=f.disables+1;f.enabled=false;if f.disable_throw then error('Disable changed then threw')end end,
  enable_physics=function(u)read(u);f.enables=f.enables+1;if f.enable_throw then error('Enable failed')end;f.enabled=true end}
 local sr={Unit=U,Application={main_world=function()return f.current_world end},Network={game_session=function()return f.current_session end},
  IdString64={from_hex=temp,equal=function(a,b)return value(a)==value(b)end},Quaternion={to_elements=function(q)return unpack(value(q))end}}
 f.probe=Probe.new(sr,function(s)f.logs[#f.logs+1]=s end,function()return 0 end)
 f.frame={explicit_subject=true,root_handle=f.unit,world=f.world}
 function f.start(t)return f.probe.start(f.frame,t or 0)end
 function f.tick(t,enabled)f.epoch=f.epoch+1;return f.probe.tick(enabled~=false,t)end
 function f.disable()assert(f.start());f.angle=30;assert(f.tick(.25));assert(f.disables==1 and not f.enabled)end
 return f
end
do
 local f=fixture();for i=1,100 do assert(f.tick(i,false))end;assert(f.reads==0)
 assert(f.start());local reads=f.reads;for i=1,24 do assert(f.tick(i*.01))end;assert(f.reads==reads)
 f.angle=30;assert(f.tick(.25));assert(f.disables==1)
 assert(f.tick(.75));assert(f.tick(2.25));assert(f.tick(4.25));local reads=f.reads
 for i=1,199 do assert(f.tick(4.25+i*.01))end;assert(f.reads==reads,'No native polling between scheduled samples')
 assert(f.tick(6.25)and f.enabled and f.enables==1 and not f.probe.active())
 local reads=f.reads;for i=1,100 do f.tick(7+i)end;assert(f.reads==reads and f.disables==1 and f.enables==1)
 assert(f.start(20));f.angle=60;f.tick(20.25);assert(f.tick(20.3,false));assert(f.enables==2 and not f.start(30),'Two explicit off/on trials maximum')
end
do
 local f=fixture();assert(f.start());assert(f.tick(.25)and not f.probe.active()and f.disables==0,'Static root never authorizes the experiment')
 assert(f.start(10));f.angle=40;assert(f.tick(12)and f.disables==0,'An expired precheck never disables later')
 assert(f.start(20));f.angle=80;assert(f.tick(20.25)and f.disables==1,'Rejected and expired prechecks do not consume off/on attempts')
 assert(f.probe.release('test finished'))
end
for _,failure in ipairs({'dead','world','session'})do
 local f=fixture();f.disable()
 if failure=='dead'then f.alive=false elseif failure=='world'then f.current_world=newproxy()else f.current_session=newproxy()end
 assert(f.probe.release(failure)and f.enables==0 and not f.probe.active(),'Retired identities are not written')
end
do
 local f=fixture();f.disable_throw=true;assert(f.start());f.angle=30;assert(f.tick(.25))
 assert(f.disables==1 and f.enables==1 and f.enabled and not f.probe.active(),'A partially applied disable retains enable responsibility')
end
do
 local f=fixture();f.disable();f.enable_throw=true
 assert(not f.tick(6.25)and f.probe.active());local reads=f.reads
 for i=1,100 do assert(not f.tick(7+i))end
 assert(f.reads==reads and f.enables==1,'Failed cleanup never retries native calls each frame')
 for i=1,100 do assert(not f.probe.release('automatic close'))end
 assert(f.reads==reads and f.enables==1,'Lifecycle cleanup must also stay idle after refusal')
 f.enable_throw=nil;assert(not f.probe.release('automatic close'),'Changed backend alone does not retry')
 assert(f.probe.release('explicit retry',true)and f.enabled and f.enables==2)
end
do
 local f=fixture();f.mode='ignore';assert(not f.start()and f.disables==0)
 f.mode='position_and_rotation';f.wrong_resource=true;assert(not f.start()and f.disables==0)
end
print('Freeze physics probe: explicit rotating target, bounded off/on, no idle native work, scratch lifetime, partial failures and retired identity passed')

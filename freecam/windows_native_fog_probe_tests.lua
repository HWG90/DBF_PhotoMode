local M=dofile('freecam/windows_native_fog_probe.lua')
local mapping='core/stingray_renderer/shading_environment_components/fog'
local function fixture(count)
 local f={time=0,cpu=0,reads=0,scans=0,logs={},world=newproxy(),manager=newproxy(),entities={},data={},vectors={}}
 for i=1,count or 1 do local e=newproxy();f.entities[i]=e;f.data[e]={alive=true,ids={7,-9},mapping=mapping}end
 function f.vec(a,b,c)local v=newproxy();f.vectors[v]={a,b,c};return v end
 f.enabled=true;f.parameters=f.vec(100,0,.04);f.color=f.vec(.1,.2,.3)
 local function read()f.reads=f.reads+1 end
 f.api={instances=function(m,e)read();assert(m==f.manager);return unpack(f.data[e].ids)end,
  get_property=function(m,e,id,path)
   read();assert(m==f.manager and f.data[e].alive);assert(id==7 or id==-9);assert(type(path)=='table'and #path==1)
   local key=path[1]
   if key=='shading_environment_mapping'then return id==-9 and f.data[e].mapping or 'different' end
   assert(id==-9 and f.data[e].mapping==mapping,'Never read fog fields on another schema')
   if key=='fog_enabled'then return f.enabled end
   if key=='fog_parameters'then return f.parameters elseif key=='fog_color'or key=='near_ground_fog_color'then return f.color end
   return 1
  end,set_property=function()error('Probe must never write')end}
 local sr={Application={main_world=function()read();return f.world end},
  World={entities=function(w)read();assert(w==f.world);f.scans=f.scans+1;return f.entities end},
  EntityManager={render_data_component=function(w)read();assert(w==f.world);return f.manager end,alive=function(e)read();return f.data[e].alive end},
  RenderDataComponent=f.api,Vector3={x=function(v)read();return f.vectors[v][1]end,y=function(v)read();return f.vectors[v][2]end,z=function(v)read();return f.vectors[v][3]end}}
 f.probe=M.new(sr,function()return f.time end,function()f.cpu=f.cpu+(f.cost or .00001);return f.cpu end,function(s)f.logs[#f.logs+1]=s end)
 function f.tick(active,n)for i=1,n or 1 do f.time=f.time+.016;f.probe.tick(active)end end
 return f
end
local f=fixture(2);f.tick(false,100);assert(f.reads==0 and f.scans==0)
f.tick(true);assert(#f.probe.profiles==1,'One profile maximum per update')
f.tick(true,5);assert(f.probe.done and f.probe.complete and #f.probe.profiles==2 and f.scans==1)
assert(f.probe.profiles[1].values.fog_parameters[3]==.04)
assert(f.probe.profiles[1].values.fog_enabled==true)
local off=fixture();off.enabled=false;off.tick(true,5);assert(off.probe.complete and off.probe.profiles[1].values.fog_enabled==false)
local wrong=fixture();wrong.enabled=1;wrong.tick(true,5);assert(wrong.probe.done and not wrong.probe.complete and wrong.probe.reason:find('expected boolean',1,true))
f.vectors[f.parameters][3]=8;assert(f.probe.profiles[1].values.fog_parameters[3]==.04,'Retain numeric copies, not Vector3 userdata')
local before=f.reads;f.tick(true,200);f.tick(false);f.tick(true);assert(f.reads==before,'Done stays completely idle across reopen')
local shape=fixture();shape.parameters={1,2,3};shape.tick(true,5)
assert(shape.probe.done and not shape.probe.complete and #shape.probe.profiles==0 and shape.probe.reason:find('expected Vector3',1,true))
before=shape.reads;shape.tick(true,100);assert(shape.reads==before,'Unsupported return shape disables once')
local world=fixture(2);world.tick(true);world.world=newproxy();world.tick(true)
assert(world.probe.done and not world.probe.complete and world.probe.reason=='World changed'and world.scans==1)
local close=fixture(2);close.tick(true);close.tick(false);assert(close.probe.done and not close.probe.complete)
local membership=fixture();membership.cost=.0008
membership.data[membership.entities[1]].ids={7,-9,7,-9,7,-9,7,-9}
membership.tick(true);membership.data[membership.entities[1]].ids={-9};membership.tick(true)
assert(membership.probe.done and not membership.probe.complete and membership.probe.reason:find('membership changed',1,true))
local retired=fixture();retired.cost=.0008;retired.data[retired.entities[1]].ids={7,-9,7,-9}
retired.tick(true);retired.data[retired.entities[1]].alive=false;retired.tick(true)
assert(retired.probe.done and not retired.probe.complete and retired.probe.reason:find('retired',1,true))
local limit=fixture(17);limit.tick(true,30);assert(limit.probe.done and not limit.probe.complete and #limit.probe.profiles==16)
local empty=fixture(0);empty.tick(true);assert(empty.probe.done and empty.probe.complete and #empty.probe.profiles==0)
local malformed=fixture();malformed.api.instances=function()return{named=4}end;malformed.tick(true)
assert(malformed.probe.done and not malformed.probe.complete and malformed.probe.reason:find('Invalid fog instance list',1,true))
local timeout=fixture(2);timeout.tick(true);timeout.time=11;timeout.tick(true)
assert(timeout.probe.done and not timeout.probe.complete and timeout.probe.reason=='Ten-second budget')
local fault=fixture();fault.cost=0/0;assert(pcall(fault.tick,true));assert(fault.probe.done and not fault.probe.complete)
local release=fixture();release.probe.release();release.tick(true);assert(release.reads==0 and release.probe.done)
print('Native fog probe: exact schema, scalar/Vector3 shapes, copied values, one profile/update, membership/world retirement, bounds, failure latch and idle completion passed; no writes or live qualification')

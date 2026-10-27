local M=dofile('freecam/windows_freeze_observer.lua')
local function fixture(animation_source)
 local f={time=0,meter=0,reads=0,scans=0,priority_calls=0,priority={},logs={},world=newproxy(),units={},data={}}
 local function read()f.reads=f.reads+1 end
 function f.unit(x,animated)
  local u=newproxy();f.units[#f.units+1]=u;f.data[u]={alive=true,world=f.world,x=x,animated=animated~=false,q={0,0,0,1},bone={0,0,0,1}};return u
 end
 local U={alive=function(u)read();return f.data[u].alive end,world=function(u)read();return f.data[u].world end,
  num_scene_graph_items=function(u)read();assert(f.data[u].alive);return f.data[u].count or 3 end,
  has_animation_state_machine=function(u)read();return f.data[u].animated end,
  has_animation_blender=function(u)read();return true end,
  resource_name=function(u)read();return f.data[u].resource or tostring(f.data[u].x)end,
  has_node=function(u,n)read();return n=='hips'end,node=function()read();return 2 end,
  world_position=function(u)read();assert(f.data[u].alive);return{f.data[u].x,0,0}end,
  world_rotation=function(u,i)read();assert(f.data[u].alive);return i>1 and f.data[u].worldbone or f.data[u].q end,
  local_position=function(u)read();assert(f.data[u].alive);return{0,0,0}end,
  local_rotation=function(u)read();assert(f.data[u].alive);return f.data[u].bone end}
 U.animation_root_mode=function(u)read();return f.data[u].root_mode or 'delta_rotation'end
 U.animation_bone_mode=function(u)read();return f.data[u].bone_mode or 'transform'end
 local sr={Application={main_world=function()read();return f.world end},Unit=U,
  IdString64={from_hex=function(hex)assert(hex=='4d1c334d294dfa97');return hex end},
  World={units_by_resource=function(w,id)assert(w==f.world);f.priority_calls=f.priority_calls+1;return f.priority end,units=function(w)assert(w==f.world);f.scans=f.scans+1;local list={};for i,u in ipairs(f.units)do list[i]=u end;return list end},
  Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  Quaternion={to_elements=function(q)return unpack(q)end}}
 f.sr=sr
 f.observer=M.new(sr,function()return f.time end,function()f.meter=f.meter+.00001;return f.meter end,function(s)f.logs[#f.logs+1]=s end,animation_source)
 function f.step(frozen,n,dt)for i=1,n or 1 do f.time=f.time+(dt or .01);f.observer.tick(frozen,{0,0,0})end end
 function f.text()return table.concat(f.logs,'\n')end
 return f
end
local f=fixture();local root=f.unit(1);local bone=f.unit(2,false)
f.step(false,100);assert(f.reads==0 and f.scans==0,'No engine calls before an explicit Freeze')
f.step(true,6);f.data[root].q={0,0,math.sqrt(.5),math.sqrt(.5)};f.data[bone].bone={0,math.sqrt(.5),0,math.sqrt(.5)}
f.step(true,200,.02)
assert(f.scans==1 and f.text():find('complete units=2',1,true))
assert(f.text():find('root=delta_rotation bone=transform',1,true),'Record the actual exposed modes alongside root/bone motion')
assert(f.text():find('root_deg=90.000 bone_local_m=0.000000 bone_local_deg=0.000',1,true),'Whole-unit rotation is distinct from bone-local motion')
assert(f.text():find('root_deg=0.000 bone_local_m=0.000000 bone_local_deg=90.000',1,true),'Blender-only subjects remain observable')
local reads=f.reads;f.step(true,200);assert(f.reads==reads,'Completed frozen state performs no engine reads')
f.step(false);f.step(true,6);f.data[root].alive=false;f.step(true,200,.02)
assert(not f.text():find('disabled',1,true),'Retired units must be recorded without crashing the observer')
f.observer.release();reads=f.reads;f.step(false);f.step(true,100);assert(f.reads==reads,'Disposal drops all pending reads')
local g=fixture();for i=1,100 do g.unit(i/10)end
g.step(true);assert(g.priority_calls==1);g.world=newproxy();g.step(true,20)
assert(g.text():find('world changed',1,true)and g.scans==0 and g.priority_calls==1,'A frozen world transition cancels; it never scans a successor world')
local h=fixture();h.unit(1)
for i=1,18 do h.step(true);h.step(false)end
assert(h.priority_calls==16,'Aborted episodes cannot exhaust four completed captures but have a separate sixteen-attempt bound')
local bounded=fixture();for i=1,16420 do bounded.unit(100)end
bounded.step(true,800,.005)
assert(bounded.text():find('scanned=16384 truncated=true',1,true),'Large scenes have an explicit scan bound')
local priority=fixture();for i=1,4200 do priority.unit(100)end
local body=priority.unit(1);priority.priority={body};priority.step(true,3)
priority.data[body].worldbone={0,0,math.sqrt(.5),math.sqrt(.5)}
priority.step(true,50,.05)
assert(priority.text():find('lane=helldiver resource=1',1,true),'Helldiver captured before broad scenery scan')
assert(priority.text():find('root_deg=0.000 bone_local_m=0.000000 bone_local_deg=0.000 bone_world_m=0.000000 bone_world_deg=90.000',1,true),'Inherited world-bone motion is observable even with unchanged root/local samples')
assert(priority.text():find('Helldiver samples finished',1,true))
do
 local f=fixture();local body=f.unit(1);local row=f.data[body]
 row.resource='4d1c334d294dfa97';row.count=107;row.root_mode='ignore';f.priority={body}
 local calls=0;local epoch=0;local scratch={}
 local function matrix(x,rotating)
  local c,s=rotating and 0 or 1,rotating and 1 or 0
  local u=newproxy();scratch[u]={epoch=epoch,numbers={c,s,0,rotating and -1 or 0,c,0,0,0,1,x,0,0}};return u
 end
 -- Install through the fixture's captured engine tables, with callback-lifetime
 -- scratch values so copied matrices can be checked after later frames.
 f.sr.Matrix4x4={to_elements=function(u)local v=assert(scratch[u]);assert(v.epoch==epoch,'Root source scratch escaped callback');return unpack(v.numbers)end}
 f.sr.Unit.world_pose=function(u,i)assert(u==body and i==1);return matrix(1)end
 f.sr.Unit.animation_wanted_root_pose=function(u)assert(u==body);calls=calls+1;return matrix(f.wanted or 1)end
 f.sr.Unit.delta_pose=function(u,i)assert(u==body and i==1);return matrix(0,f.rotating)end
 f.sr.World.delta_time=function(w)assert(w==f.world);return 0 end
 local step=f.step
 function f.step(frozen,n,dt)for i=1,n or 1 do epoch=epoch+1;step(frozen,1,dt)end end
 f.step(true,4);assert(calls==1);f.wanted=2;f.step(true,200,.02)
 assert(calls==3,'Root-source getters run only at baseline and two existing capture samples')
 assert(f.text():find('sample=0 world_dt=0 actual=1,0,0,0,1,0,0,0,1,1,0,0 wanted=1,0,0,0,1,0,0,0,1,1,0,0',1,true))
 assert(f.text():find('wanted=1,0,0,0,1,0,0,0,1,2,0,0 delta=1,0,0,0,1,0,0,0,1,0,0,0',1,true),'Wanted motion is logged even when actual root does not move')
 local reads=f.reads;f.step(true,200);assert(f.reads==reads and calls==3,'Finished source capture stays idle')
 f.rotating=true;f.step(false);f.step(true,200,.02)
 local _,bursts=f.text():gsub('Freeze root burst: episode=2 row=1 frame=','')
 assert(bursts==8 and calls==14,'A rotating delta adds exactly eight root samples once per episode')
 local reads=f.reads;f.step(true,200);assert(f.reads==reads and calls==14,'Root burst never becomes continuous sampling')
 local unavailable=fixture();local u=unavailable.unit(1);local d=unavailable.data[u]
 d.resource='4d1c334d294dfa97';d.count=107;d.root_mode='ignore';unavailable.priority={u}
 unavailable.step(true,4);d.q={0,0,math.sqrt(.5),math.sqrt(.5)};unavailable.step(true,200,.02)
 assert(unavailable.text():find(' unavailable=',1,true)and unavailable.text():find('root_deg=90.000',1,true),'Unavailable optional root getters do not discard established drift evidence')
 assert(not unavailable.text():find('Freeze observer disabled:',1,true))
end
print('Freeze observer: bounded root/bone/source capture, copied matrices, optional API failure, idle silence, retired units and world cancellation passed')
do
 local ticks,reads=0,0
 local matrix={1,0,0,0,1,0,0,0,1,0,0,0}
 local factory={new=function(sr,world,rows)
  assert(#rows==1 and rows[1].count==107)
  local reader={done=false}
  reader.tick=function()ticks=ticks+1;if ticks==2 then reader.done=true end end
  reader.read=function(unit)assert(reader.done and unit==rows[1].unit);reads=reads+1;return matrix end
  return reader
 end}
 local f=fixture(factory);local body=f.unit(1);local row=f.data[body]
 row.count=107;row.resource='4d1c334d294dfa97';row.root_mode='ignore';f.priority={body}
 f.sr.Matrix4x4={to_elements=function(m)return unpack(m)end}
 f.sr.Unit.world_pose=function()return matrix end;f.sr.Unit.delta_pose=function()return matrix end
 f.sr.Unit.animation_wanted_root_pose=function()return matrix end;f.sr.World.delta_time=function()return 0 end
 f.step(true,200,.02)
 assert(ticks==2 and reads==3,'Observer waits for complete entity discovery before the three animation samples')
 assert(f.text():find(' animation_delta=1,0,0,0,1,0,0,0,1,0,0,0',1,true))
 local before=f.reads;f.step(true,100);assert(f.reads==before and reads==3,'Mapped animation source stays idle after capture')
end

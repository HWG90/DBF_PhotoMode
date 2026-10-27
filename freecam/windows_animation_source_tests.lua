local M=dofile('freecam/windows_animation_source.lua')
local function fixture(count)
 local f={world=newproxy(),unit=newproxy(),unit_provider=newproxy(),blender_provider=newproxy(),entities={},data={},reads=0,delta_reads=0,meter=0,epoch=0,logs={}}
 f.current_world=f.world
 for i=1,count or 12 do local e=newproxy();f.entities[i*3]=e;f.data[e]={alive=true,unit=i==1 and f.unit or newproxy(),ids={-140308449}}end
 local function read()f.reads=f.reads+1 end
 local scratch={}
 local sr={Application={main_world=function()read();return f.current_world end},World={entities=function(w)read();assert(w==f.world);return f.entities end},
  Unit={alive=function(u)read();assert(u==f.unit);return not f.dead end,world=function()read();return f.world end},
  EntityManager={unit_component=function(w)read();assert(w==f.world);return f.unit_provider end,
   animation_blender_component=function(w)read();assert(w==f.world);return f.blender_provider end,
   alive=function(e)read();return f.data[e].alive end},
  UnitComponent={instances=function(m,e)read();assert(m==f.unit_provider);return 42 end,
   unit=function(m,e)read();assert(m==f.unit_provider);return f.data[e].unit end},
  AnimationBlenderComponent={instances=function(m,e)read();assert(m==f.blender_provider);return unpack(f.data[e].ids)end,
   delta_transform=function(m,e)read();assert(m==f.blender_provider and f.data[e].unit==f.unit);f.delta_reads=f.delta_reads+1
    local u=newproxy();scratch[u]=f.epoch;return u end},
  Matrix4x4={to_elements=function(u)assert(scratch[u]==f.epoch,'Animation matrix scratch escaped callback');return 1,0,0,0,1,0,0,0,1,0,0,0 end}}
 f.sr=sr
 function f.start()f.reader=M.new(sr,f.world,{{unit=f.unit,count=107,resource='4d1c334d294dfa97'}},function(s)f.logs[#f.logs+1]=s end,function()f.meter=f.meter+.000001;return f.meter end)end
 function f.step(n)for i=1,n or 1 do f.epoch=f.epoch+1;f.reader.tick()end end
 return f
end
do
 local f=fixture();f.start();f.step();assert(not f.reader.done and f.delta_reads==0,'Discovery stays bounded and does not read animation without a complete mapping')
 f.step(10);assert(f.reader.done and f.reader.complete)
 local values=f.reader.read(f.unit);assert(#values==12 and values[1]==1 and f.delta_reads==1)
 local reads=f.reads;f.step(100);assert(f.reads==reads,'Completed discovery performs no native work')
 f.epoch=f.epoch+1;assert(values[1]==1 and f.reader.read(f.unit)[1]==1,'Only copied numbers survive callbacks')
 f.data[f.entities[3]].ids={7};assert(not pcall(f.reader.read,f.unit)and f.delta_reads==2,'Changed component token refuses before reading a replacement')
end
do
 local f=fixture();f.data[f.entities[6]].unit=f.unit;f.start();f.step(10)
 assert(f.reader.read(f.unit)==nil and f.delta_reads==0,'Ambiguous unit-to-entity mappings do not authorize the getter')
end
do
 local f=fixture();f.data[f.entities[3]].ids={};f.start();f.step(10)
 assert(f.reader.read(f.unit)==nil and f.delta_reads==0,'A linked unit without an entity animation component is not interchangeable with one')
end
do
 local f=fixture(4097);f.start();f.step(600)
 assert(f.reader.done and not f.reader.complete and f.reader.read(f.unit)==nil and f.delta_reads==0,'An incomplete bounded inventory cannot claim unique ownership')
end
for _,fault in ipairs({'world','entity','unit','mapping'})do
 local f=fixture();f.start();f.step(10)
 if fault=='world'then f.current_world=newproxy()elseif fault=='entity'then f.data[f.entities[3]].alive=false
 elseif fault=='unit'then f.dead=true else f.data[f.entities[3]].unit=newproxy()end
 assert(not pcall(f.reader.read,f.unit)and f.delta_reads==0,'Retired mapping must not reach the animation getter')
end
do
 local f=fixture();f.sr.AnimationBlenderComponent.delta_transform=nil;f.start()
 assert(f.reader.done and not f.reader.complete and f.reader.read(f.unit)==nil)
 local reads=f.reads;f.step(100);assert(f.reads==reads,'Unavailable API is terminal for this capture, not retried')
end
print('Animation source: bounded sparse entity lookup, complete unique mapping, component/lifetime guards, copied matrices, no setters and idle silence passed')

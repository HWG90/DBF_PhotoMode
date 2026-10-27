local M=dofile('freecam/windows_freeze_root_hold.lua')
local function clone(t)local v={};for i,n in ipairs(t)do v[i]=n end;return v end
local function fixture(options)
 local f={world=newproxy(),units={},priority={},data={},time=0,cpu=0,reads=0,writes=0,scans=0,logs={},epoch=0,updates={}}
 local function id(hex)return setmetatable({hex=hex,epoch=f.epoch},{__tostring=function(v)return '[IdString64 0x'..v.hex..']'end})end
 function f.unit(x,priority,camera,light)
  local u=newproxy();f.units[#f.units+1]=u
  f.data[u]={world=f.world,alive=true,count=107,resource=priority and '4d1c334d294dfa97'or string.format('%016x',#f.units),camera=camera and 1 or 0,light=light and 1 or 0,
   pose={1,0,0,0,1,0,0,0,1,x,0,0},x=x}
  if priority then f.priority[#f.priority+1]=u end;return u
 end
 local function read()f.reads=f.reads+1 end
 local function data(u)read();return assert(f.data[u])end
 local U={alive=function(u)return data(u).alive end,world=function(u)return data(u).world end,
  num_scene_graph_items=function(u)return data(u).count end,num_cameras=function(u)return data(u).camera end,
  num_lights=function(u)return data(u).light end,resource_name=function(u)return id(data(u).resource)end,
  has_node=function(u,name)if options and options.pelvis_only and name=='hips'then return true end;return data(u).cape==true and (name=='cape1'or name=='cape2'or name=='cape3')end,
  node=function(u,name)assert(name=='hips');return 10 end,scene_graph_parent=function(u,i)assert(i==10);return 8 end,
  world_position=function(u)return{data(u).x,0,0}end,local_pose=function(u,i)assert(i==1 or options and options.pelvis_only and i==10);return clone(i==10 and data(u).hips or data(u).pose)end,
  local_position=function(u)return{data(u).pose[10],0,0}end,local_rotation=function(u)return{0,0,data(u).pose[2],data(u).pose[1]}end,
  set_local_pose=function(u,i,v)
   assert((i==1 or options and options.pelvis_only and i==10)and data(u).alive and data(u).camera==0 and (data(u).light==0 or data(u).resource=='4d1c334d294dfa97'))
   f.writes=f.writes+1;if i==10 then data(u).hips=clone(v)else data(u).pose=clone(v)end;if f.fail then error('setter changed then threw')end
  end}
 U.teleport_local_pose=function(u,i,v)f.teleports=(f.teleports or 0)+1;return U.set_local_pose(u,i,v)end
 local sr={Application={main_world=function()read();return f.world end},Unit=U,
  World={units_by_resource=function(w)assert(w==f.world);f.scans=f.scans+1;return f.priority end,
   units=function(w)assert(w==f.world);f.scans=f.scans+1;return f.units end,
   update_unit=function(w,u)assert(w==f.world and data(u).alive);f.updates[#f.updates+1]=u;if f.rewrite then data(u).pose[10]=999 end end},
  IdString64={from_hex=function(h)return id(h)end,equal=function(a,b)return a.epoch==f.epoch and b.epoch==f.epoch and a.hex==b.hex end},
  Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  Quaternion={to_elements=function(q)return unpack(q)end},
  Matrix4x4={to_elements=function(m)return unpack(m)end,from_elements=function(...)return{...}end}}
 f.sr=sr
 f.hold=M.new(sr,function()return f.time end,function()f.cpu=f.cpu+.00001;return f.cpu end,function(s)f.logs[#f.logs+1]=s end,nil,options)
 function f.step(enabled,n)for i=1,n or 1 do f.time=f.time+.016;f.epoch=f.epoch+1;f.hold.tick(enabled,{0,0,0});f.hold.render(enabled)end end
 return f
end
local f=fixture();local player=f.unit(2,true);local other=f.unit(3);local camera=f.unit(1,false,true);local light=f.unit(1,false,false,true)
do
 local baseline=fixture({observe_once=true});local body=baseline.unit(2,true);local other=baseline.unit(3)
 assert(baseline.hold.prepare());baseline.step(true,10)
 baseline.data[body].pose[10]=25;baseline.data[body].pose[1]=-1;baseline.data[other].pose[10]=30
 baseline.step(true,100)
 assert(baseline.writes==0 and #baseline.updates==0 and baseline.scans==2,'Isolation Freeze must perform no root/pose/scene writes or nearby scan')
 assert(baseline.data[body].pose[10]==25 and baseline.data[other].pose[10]==30,'Observe native root movement without clamping')
 assert(baseline.hold.release());baseline.step(true,10);baseline.data[body].pose[10]=90;baseline.hold.render(true)
 assert(baseline.writes==1 and baseline.data[body].pose[10]==25,'Only the first Freeze is isolated; ordinary hold returns next time')
end
do
 local tele=fixture({use_teleport=true});local body=tele.unit(2,true)
 tele.sr.Unit.teleport_local_pose=function()error('Rejected teleport API must never be called')end
 tele.step(true,20);tele.data[body].pose[10]=9;tele.hold.render(true)
 assert(not tele.teleports,'Rejected teleport experiment must remain disabled even with legacy options')
end
do
 local pre=fixture();local body=pre.unit(2,true);local cape=pre.unit(3);pre.data[cape].cape=true;pre.data[cape].count=50
 assert(pre.hold.prepare()and pre.writes==0 and #pre.updates==0,'Pre-zero capture reads only')
 pre.data[body].pose[10]=99;pre.data[body].pose[1]=-1;pre.data[body].pose[5]=-1
 pre.data[cape].pose[10]=77
 pre.step(true,10)
 assert(pre.data[body].pose[10]==2 and pre.data[body].pose[1]==1 and pre.data[body].pose[5]==1,'First zero-time displacement cannot become the held target')
 assert(pre.data[cape].pose[10]==77,'Pre-zero root acquisition never captures or restores capes')
 assert(pre.hold.release());pre.data[body].pose[10]=44;pre.step(true,10)
 assert(pre.data[body].pose[10]==44,'Released pre-zero baseline never leaks into the next Freeze')
 local stale=fixture();local u=stale.unit(1,true);assert(stale.hold.prepare());stale.time=2;stale.data[u].pose[10]=9;stale.step(true,10)
 assert(stale.data[u].pose[10]==9,'Expired pre-zero sample cannot rewind a later Freeze')
end
f.step(false,100);assert(f.reads==0 and f.scans==0 and f.writes==0)
f.step(true,10);assert(f.scans==2 and f.writes==0,'No writes to unchanged roots')
local base=clone(f.data[player].pose);f.data[player].pose[1]=0;f.data[player].pose[2]=1;f.data[player].pose[10]=7
f.data[other].pose[10]=8;f.data[camera].pose[10]=12;f.data[light].pose[10]=13
f.hold.render(true);assert(f.writes==2 and f.data[player].pose[1]==base[1]and f.data[player].pose[10]==2 and f.data[other].pose[10]==3)
assert(f.data[camera].pose[10]==12 and f.data[light].pose[10]==13,'Camera/light transforms never frozen')
f.step(true,100);assert(f.scans==2 and f.writes==2,'Steady roots cause no repeated writes/discovery')
assert(f.hold.release());f.data[player].pose[10]=30;f.hold.render(false);assert(f.data[player].pose[10]==30 and f.writes==2,'Release never rewinds a resumed pose')
local reads=f.reads;f.step(false,100);assert(f.reads==reads,'Closed state has no engine calls')
f.step(true,10);f.data[player].alive=false;f.data[other].count=3;local writes=f.writes;f.step(true);assert(f.writes==writes,'Dead/replaced graphs cannot be written')
local world=fixture();local u=world.unit(1,true);world.step(true,5);world.world=newproxy();world.data[u].pose[10]=5;world.step(true,50)
assert(world.writes==0 and world.scans==2,'World retirement stops without scanning/writing successor')
local fail=fixture();u=fail.unit(1,true);fail.step(true,5);fail.fail=true;fail.data[u].pose[10]=2;fail.step(true);writes=fail.writes;fail.step(true,100)
assert(writes==1 and fail.writes==1,'Mutate-then-throw latches; no repeated calls or restore rewind')
local update=fixture();u=update.unit(1,false);update.step(true,5);update.rewrite=true;update.data[u].pose[10]=2;update.step(true)
assert(table.concat(update.logs,'\n'):find('readback differs after scene update',1,true),'Verification includes final scene update')
local bound=fixture();local priority=bound.unit(40,true);for i=1,100 do bound.unit(i/100)end
bound.step(true,10);for unit,d in pairs(bound.data)do d.pose[10]=99 end;bound.hold.render(true)
assert(bound.writes==32 and bound.data[priority].pose[10]==40,'32-root cap preserves priority Helldiver')
local lit=fixture();local actor=lit.unit(2,true,false,true);local cam=lit.unit(1,true,true,true);local lamp=lit.unit(1,false,false,true)
lit.step(true,10);lit.data[actor].pose[10]=9;lit.data[cam].pose[10]=8;lit.data[lamp].pose[10]=7;lit.hold.render(true)
assert(lit.writes==1 and lit.data[actor].pose[10]==2 and lit.data[cam].pose[10]==8 and lit.data[lamp].pose[10]==7,'Character lights do not exclude the body; camera and standalone light remain untouched')
local cloth=fixture();local body=cloth.unit(2,true);local cape=cloth.unit(3);cloth.data[cape].cape=true;cloth.data[cape].count=50
cloth.step(true,10);assert(#cloth.updates==0)
cloth.data[body].pose[10]=10;cloth.data[cape].pose[10]=999;cloth.hold.render(true)
assert(cloth.writes==1 and #cloth.updates==0 and cloth.data[cape].pose[10]==999,'Root correction cannot force either body or cape scene evaluation')
cloth.step(true,20);assert(#cloth.updates==0 and cloth.data[cape].pose[10]==999,'Native garment changes remain untouched')
cloth.data[cape].alive=false;cloth.data[body].pose[10]=10;cloth.hold.render(true);assert(#cloth.updates==0,'No forced body evaluation on a subsequent correction')
cloth.hold.release();cloth.hold.render(false);assert(#cloth.updates==0,'No cape refresh on release')
local flip=fixture();local selected=flip.unit(2,true);local garment=flip.unit(3);flip.data[garment].cape=true;flip.data[garment].count=50
flip.step(true,10)
local U=flip.sr.Unit;local old_has=U.has_node;local old_position=U.world_position
U.has_node=function(u,n)return u==selected and n=='chest'or old_has(u,n)end
U.node=function(u,n)assert(u==selected and n=='chest');return 29 end
U.world_pose=function(u,n)assert(n==1);return clone(flip.data[u].pose)end
U.world_position=function(u,n)
 if n==29 then local m=flip.data[u].pose;return{m[10]+m[7]*1.5,m[11]+m[8]*1.5,m[12]+m[9]*1.5}end
 return old_position(u,n)
end
local frame={explicit_subject=true,world=flip.world,root_handle=selected}
local baseline=clone(flip.data[selected].pose);local cape_baseline=clone(flip.data[garment].pose)
assert(not flip.hold.flip_body({world=flip.world,root_handle=selected}),'No implicit subject')
assert(flip.hold.flip_body(frame));assert(flip.writes==0,'Button only queues the held target')
flip.hold.render(true)
local m=flip.data[selected].pose
assert(m[1]==1 and m[5]==-1 and m[9]==-1 and m[10]==2 and m[12]==3,'Proper half-turn, not a reflection; chest pivot is fixed')
assert(U.world_position(selected,29)[3]==1.5 and flip.writes==1 and #flip.updates==0,'Only body root is written; no forced body or cape scene refresh')
for i=1,12 do assert(flip.data[garment].pose[i]==cape_baseline[i],'Garment transform unchanged')end
assert(flip.hold.flip_body(frame));flip.hold.render(true)
for i=1,12 do assert(flip.data[selected].pose[i]==baseline[i],'Undo restores the original held target')end
assert(flip.hold.flip_body(frame));flip.hold.render(true);local count=flip.writes
flip.hold.release();assert(not flip.hold.flip_body(frame));assert(flip.writes==count,'Resume/dispose never rewinds a live body')
print('Freeze root candidate: idle silence, bounded roots, restoration, body-only pivot flip/undo and no-rewind release passed; visual effect unverified')

do
 local p=fixture({pelvis_only=true});local body=p.unit(2,true);local prop=p.unit(3)
 p.data[body].hips=clone(p.data[body].pose)
 assert(p.hold.prepare());p.step(true,3)
 p.data[body].pose[10]=80;p.data[body].hips[10]=7;p.data[prop].pose[10]=90
 p.hold.render(true)
 assert(p.writes==1 and p.data[body].hips[10]==2,'Only the captured hips transform is held')
 assert(p.data[body].pose[10]==80 and p.data[prop].pose[10]==90,'Root and other units remain untouched')
 assert(#p.updates==0 and not p.teleports,'No forced scene update or teleport')
 local writes=p.writes;p.hold.render(true);assert(p.writes==writes,'Unchanged pelvis performs no writes')
 assert(p.hold.release());p.hold.render(false);assert(p.writes==writes,'Resume never rewinds the pelvis')
end
print('Pelvis-only trial: qualified hips, root untouched, changed-only setter, no scene refresh and no resume rewind passed')

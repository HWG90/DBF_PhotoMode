assert(_VERSION=='Lua 5.1')
local M=dofile('freecam/windows_freeze_cape.lua')
local function copy(a)local b={};for i,v in ipairs(a)do b[i]=v end;return b end
local function identity()return{1,0,0,0,1,0,0,0,1,0,0,0}end
local function multiply(a,b)
 local c={}
 for row=0,2 do for col=1,3 do local v=0
  for k=0,2 do v=v+a[row*3+k+1]*b[k*3+col]end;c[row*3+col]=v
 end end
 for col=1,3 do c[9+col]=b[9+col];for k=0,2 do c[9+col]=c[9+col]+a[10+k]*b[k*3+col]end end
 return c
end
local function inverse(a)
 local b=identity();for row=0,2 do for col=1,3 do b[row*3+col]=a[(col-1)*3+row+1]end end
 for col=1,3 do b[9+col]=0;for k=0,2 do b[9+col]=b[9+col]-a[10+k]*b[k*3+col]end end;return b
end
local function close(a,b)for i=1,12 do assert(math.abs(a[i]-b[i])<1e-5,'Matrix differs: '..i)end end
local function rotate(angle,x,y,z)
 local c,s=math.cos(angle),math.sin(angle);return{c,s,0,-s,c,0,0,0,1,x,y,z}
end
local function fixture(options)
 local f={epoch=1,writes={},updates=0,alive=true,resource='ea846ef460cc5ba0',values={},parents={[23]=22,[43]=42,[49]=42,[50]=42}}
 local body,cape,world=newproxy(),newproxy(),newproxy();f.body=body;f.cape=cape
 f.frame={explicit_subject=true,root_handle=body,world=world,identity='selected'}
 f.meshes={newproxy(),newproxy(),newproxy(),newproxy()};local mesh_nodes={23,43,49,50}
 local names={cape1=21,cape2=22,cape3=24};f.names=names
 f.anchor=rotate(.43,13,-7,2)
 for i=1,50 do f.values[i]=identity()end
 f.values[1]=rotate(-.71,11,2,-3);f.values[42]=rotate(.27,.4,-.3,1)
 for _,n in ipairs({43,49,50})do f.values[n]=inverse(f.values[42])end
 local temps={}
 local function temp(v)local h=newproxy();temps[h]={epoch=f.epoch,value=copy(v)};return h end
 local function value(h)local t=assert(temps[h]);assert(t.epoch==f.epoch,'Scratch matrix retained across callbacks');return t.value end
 local function world_pose(u,n)
  f.reads=(f.reads or 0)+1
  if u==body then if n==1 then return identity()end;assert(n==35);return copy(f.anchor)end
  if n==1 then return copy(f.values[n])end
  local parent=f.parents[n]or 1
  return multiply(f.values[n],world_pose(cape,parent))
 end
 local U={alive=function(u)return u==body or f.alive end,world=function()return world end,
  resource_name=function()return f.resource end,num_scene_graph_items=function(u)return u==body and 107 or 50 end,
  num_meshes=function()return 4 end,mesh=function(u,i)return f.meshes[i]end,
  has_node=function(u,name)return u==body and name=='cape1'or u==cape and names[name]~=nil end,
  node=function(u,name)return u==body and 35 or names[name]end,
  scene_graph_parent=function(u,n)
   assert(u==cape);if f.parents[n]then return f.parents[n]end
   if n==1 or n==21 or n==22 or n==24 then return nil end;return 1
  end,
  world_pose=function(u,n)return temp(world_pose(u,n))end,
  local_pose=function(u,n)assert(u==cape);return temp(f.values[n])end,
  set_local_pose=function(u,n,v)
   assert(u==cape and(n==43 or n==49 or n==50),'Wrote body, root or cloth node')
   f.writes[#f.writes+1]=n;f.values[n]=copy(value(v))
   if f.fail==n then f.fail=nil;error('Setter failed after mutation')end
  end}
 local X={from_elements=function(...)return temp({...})end,to_elements=function(v)return unpack(value(v))end,
  multiply=function(a,b)return temp(multiply(value(a),value(b)))end,inverse=function(a)return temp(inverse(value(a)))end}
 f.current_world=world;f.session=newproxy()
 local sr={Unit=U,Application={main_world=function()return f.current_world end},Network={game_session=function()return f.session end},World={update_unit=function(w,u)assert(w==world and u==cape);f.updates=f.updates+1 end},
  Matrix4x4=X,IdString64={equal=function(a,b)return a==b end,from_hex=function(h)return h end},
  Mesh={visibility=function()return true end,
   world_pose=function(h)for i,m in ipairs(f.meshes)do if m==h then return temp(world_pose(cape,mesh_nodes[i]))end end;error('Stale Mesh')end,
   node=function(h)for i,m in ipairs(f.meshes)do if m==h then return mesh_nodes[i]end end;error('Stale Mesh')end}}
 f.solver=M.new(sr,function(frame,group)
  assert(frame==f.frame and group=='cape');if f.ambiguous then error('Ambiguous')end
  return{{unit=cape,world=world}}
 end,options)
 f.world_pose=world_pose;f.original={};for _,n in ipairs({43,49,50})do f.original[n]=copy(f.values[n])end
 return f
end
do
 local logs={};local f=fixture({trace_only=true,log=function(s)logs[#logs+1]=s end})
 local r=f.solver.capture(f.frame);assert(r.trace_remaining==8 and #logs>0)
 f.epoch=2;f.anchor=rotate(2,4,5,6)
 assert(f.solver.apply(r,f.frame)==0 and #f.writes==0,'Read-only trace never changes garment')
 for i=1,8 do f.epoch=f.epoch+1;f.solver.trace(r,'sample'..i)end
 assert(r.trace_remaining==0)
 local reads,n=f.reads,#logs
 for i=1,100 do f.solver.trace(r,'finished')end
 assert(f.reads==reads and #logs==n,'Completed trace has zero native reads or logging')
 assert(f.solver.release(r)and #f.writes==0)
 local second=f.solver.capture(f.frame);assert(second.trace_remaining==8)
 local n=#logs;local third=f.solver.capture(f.frame)
 assert(not third.trace_remaining and #logs==n,'At most two captures per enabled diagnostic')
end
do
 local f=fixture({flip_shoulder_right=true})
 local original=f.world_pose(f.cape,43);local pivot=copy(f.anchor)
 local r=f.solver.capture(f.frame);f.epoch=2
 assert(f.solver.apply(r,f.frame)==3)
 local rotation={1,0,0,0,-1,0,0,0,-1,0,0,0}
 local expected=multiply(multiply(multiply(original,inverse(pivot)),rotation),pivot)
 for _,n in ipairs({43,49,50})do close(f.world_pose(f.cape,n),expected)end
 -- Check geometric points independently of the placement formula: shoulder
 -- position stays fixed, right stays right, and forward/up reverse.
 local function point(p,m)local out={}
  for col=1,3 do out[col]=m[9+col];for row=0,2 do out[col]=out[col]+p[row+1]*m[row*3+col]end end;return out
 end
 local delta=multiply(inverse(original),f.world_pose(f.cape,43))
 for _,p in ipairs({{0,0,0},{1,0,0},{0,1,0},{0,0,1}})do
  local actual=point(point(p,pivot),delta);local wanted=point({p[1],-p[2],-p[3]},pivot)
  for i=1,3 do assert(math.abs(actual[i]-wanted[i])<1e-5,'Shoulder axis or pivot moved')end
 end
 assert(f.solver.apply(r,f.frame)==0,'The half turn does not accumulate on repeated apply')
 assert(f.solver.release(r));for n,v in pairs(f.original)do close(f.values[n],v)end
end
do
 local f=fixture();local original_anchor=copy(f.anchor);local original_world=f.world_pose(f.cape,43)
 local r=f.solver.capture(f.frame);assert(#r.meshes==3 and #f.writes==0)
 f.epoch=2;f.anchor=rotate(-1.2,-3,6,4)
 assert(f.solver.apply(r,f.frame)==3)
 local expected=multiply(multiply(original_world,inverse(original_anchor)),f.anchor)
 for _,n in ipairs({43,49,50})do close(f.world_pose(f.cape,n),expected)end
 for i=3,103 do f.epoch=i;assert(f.solver.apply(r,f.frame)==0)end
 assert(#f.writes==3 and f.updates==1,'Unchanged placement must not write or refresh')
 assert(f.solver.release(r));for n,v in pairs(f.original)do close(f.values[n],v)end
 assert(#f.writes==6 and f.updates==2)
 assert(f.solver.release(r)and #f.writes==6,'Repeated cleanup is idle')
end
do
 local f=fixture();local r=f.solver.capture(f.frame);f.epoch=2;f.anchor=rotate(2,4,3,2);f.fail=49
 assert(not pcall(f.solver.apply,r,f.frame));assert(f.solver.release(r))
 for n,v in pairs(f.original)do close(f.values[n],v)end
end
do
 local f=fixture();local r=f.solver.capture(f.frame);f.anchor=rotate(2,1,2,3);f.solver.apply(r,f.frame)
 local foreign=rotate(.1,4,3,2);f.values[43]=foreign
 assert(f.solver.release(r));close(f.values[43],foreign)
end
do
 local f=fixture();local r=f.solver.capture(f.frame);f.meshes[2]=newproxy()
 assert(f.solver.apply(r,f.frame)==0 and r.retired and #f.writes==0)
 assert(f.solver.release(r)and #f.writes==0)
end
do
 local f=fixture();local r=f.solver.capture(f.frame);f.alive=false
 assert(f.solver.release(r)and #f.writes==0,'Never touch retired garment')
end
do
 local f=fixture();local r=f.solver.capture(f.frame);f.anchor=rotate(2,1,2,3);f.solver.apply(r,f.frame)
 f.session=newproxy();local writes=#f.writes
 assert(f.solver.release(r)and #f.writes==writes,'No restoration writes into a retired session')
end
do
 local f=fixture();f.ambiguous=true;assert(not pcall(f.solver.capture,f.frame)and #f.writes==0)
 local f=fixture();f.parents[42]=43;assert(not pcall(f.solver.capture,f.frame)and #f.writes==0,'Reject hierarchy cycle')
 local f=fixture();local r=f.solver.capture(f.frame);f.parents[43]=2
 assert(not pcall(f.solver.apply,r,f.frame)and #f.writes==0,'Reject changed topology')
end
print('windows_freeze_cape_tests: passed')

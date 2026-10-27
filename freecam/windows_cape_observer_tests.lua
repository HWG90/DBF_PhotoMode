local M=dofile('freecam/windows_cape_observer.lua')
local world={};local calls=0;local logs={};local units={}
local function read(u)calls=calls+1;return units[u]end
local function values(x)return{1,0,0,0,1,0,0,0,1,x,0,0}end
local U={alive=function(u)return read(u).alive end,world=function(u)return read(u).world end,
 num_scene_graph_items=function(u)return read(u).count end,
 has_node=function(u,n)return read(u).names[n]~=nil end,node=function(u,n)return read(u).names[n]end,
 scene_graph_parent=function(u,n)read(u);return n==1 and nil or 1 end,
 local_pose=function(u,n)read(u);return values(n)end,world_pose=function(u,n)return values(n+read(u).x)end,
 num_meshes=function(u)return read(u).meshes end,mesh=function(u,i)return{unit=u,index=i}end}
local sr={Unit=U,Matrix4x4={to_elements=function(m)return unpack(m)end},Mesh={node=function(m)return m.index+4 end}}
local function row(cape)
 local u=newproxy();units[u]={alive=true,world=world,count=cape and 50 or 107,names={cape1=2,cape2=3,cape3=4},meshes=4,x=10}
 return{unit=u,count=units[u].count,resource=cape and'ea846ef460cc5ba0'or'4d1c334d294dfa97',cape=cape,helldiver=not cape}
end
local observer=M.new(sr,function(s)logs[#logs+1]=s end);local body=row(false);local cape=row(true)
assert(observer.before({},world)==nil and calls==0)
local pair=assert(observer.before({body,cape},world));units[body.unit].x=20;units[cape.unit].x=20
observer.after(pair,true)
assert(pair.before.cape.world_root[10]==11,'Before snapshot retains numeric copies across change')
local text=table.concat(logs,'\n');assert(text:find('phase=before role=cape',1,true)and text:find('phase=after role=cape',1,true)and text:find('mesh=4 node=8',1,true))
assert(text:find('root_local=1,0,0,0,1,0,0,0,1,1,0,0',1,true),'Correct local versus world label')
local before=calls;for i=1,100 do assert(observer.before({body,cape},world)==nil)end;assert(calls==before,'No repeat reads of inspected garment')
local retired=row(true);pair=assert(observer.before({body,retired},world));units[retired.unit].alive=false;observer.after(pair,true)
assert(logs[#logs]:find('unit retired',1,true))
local too_many=row(true);units[too_many.unit].meshes=9;assert(observer.before({body,too_many},world)==nil)
assert(logs[#logs]:find('mesh budget',1,true))
local fourth=row(true);assert(observer.before({body,fourth},world));before=calls
assert(observer.before({body,row(true)},world)==nil and calls==before,'Four-pair process bound')
print('Cape observer: read-only paired scalar snapshots, local/world labels, bounded meshes, one garment read, lifetime checks and four-pair process limit passed')

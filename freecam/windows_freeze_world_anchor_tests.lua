local M=dofile('freecam/windows_freeze_root_hold.lua')
local function clone(a)local b={};for i,v in ipairs(a)do b[i]=v end;return b end
local function mul(a,b)
 local c={};for r=0,2 do for col=1,3 do c[r*3+col]=0;for k=1,3 do c[r*3+col]=c[r*3+col]+a[r*3+k]*b[(k-1)*3+col]end end end
 for col=1,3 do c[9+col]=b[9+col];for k=1,3 do c[9+col]=c[9+col]+a[9+k]*b[(k-1)*3+col]end end;return c
end
local function inv(a)
 local b={a[1],a[4],a[7],a[2],a[5],a[8],a[3],a[6],a[9],0,0,0}
 for col=1,3 do for k=1,3 do b[9+col]=b[9+col]-a[9+k]*b[(k-1)*3+col]end end;return b
end
local function pose(angle,x,y,z)local c,s=math.cos(angle),math.sin(angle);return{c,s,0,-s,c,0,0,0,1,x,y,z}end
local function close(a,b)for i=1,12 do assert(math.abs(a[i]-b[i])<1e-5,'World anchor drift at '..i)end end
local world,unit=newproxy(),newproxy();local time=0;local reads,writes,scans=0,0,0
local parent=pose(.7,17,-4,3);local body={1,0,0,0,0,1,0,-1,0,.2,.5,1};local wanted=mul(body,parent)
local alive=true;local parent_node=5;local logs={}
local U={alive=function()return alive end,world=function()return world end,num_scene_graph_items=function()return 107 end,
 num_cameras=function()return 0 end,num_lights=function()return 0 end,resource_name=function()return '0x4d1c334d294dfa97'end,
 has_node=function(_,name)return name=='boss'end,node=function()return 8 end,scene_graph_parent=function()return parent_node end,
 world_position=function(_,i)assert(i==1);return{0,0,0}end,
 world_pose=function(_,i)reads=reads+1;assert(i==5 or i==8);return i==5 and clone(parent)or mul(body,parent)end,
 local_pose=function(_,i)assert(i==8,'Root/cape getter forbidden');return clone(body)end,
 set_local_pose=function(_,i,p)assert(i==8,'Root/cape setter forbidden');writes=writes+1;body=clone(p)end,
 teleport_local_pose=function()error('Teleport forbidden')end}
local sr={Application={main_world=function()return world end},Unit=U,
 World={units_by_resource=function()scans=scans+1;return{unit}end,units=function()error('Nearby scan forbidden')end,update_unit=function()error('Forced update forbidden')end},
 IdString64={from_hex=function(s)return '0x'..s end,equal=function(a,b)return a==b end},Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
 Matrix4x4={from_elements=function(...)return{...}end,to_elements=function(a)return unpack(a)end,multiply=mul,inverse=inv}}
local cpu=0;local hold=M.new(sr,function()return time end,function()cpu=cpu+.00001;return cpu end,function(s)logs[#logs+1]=s end,nil,{world_anchor=true})
assert(hold.prepare());assert(hold.tick(true,{0,0,0}));assert(hold.render(true));assert(writes==0,'Initial world anchor remains unchanged')
for i=1,50 do
 parent=pose(i*.21,17+i*.07,-4+i*.03,3);assert(hold.render(true));close(mul(body,parent),wanted)
end
assert(writes==50 and scans==2,'One changed anchor write per render; no repeated discovery')
local n=writes;for i=1,50 do assert(hold.render(true))end;assert(writes==n,'Unchanged world anchor stays idle')
parent_node=1;assert(hold.render(true));assert(writes==n,'Topology replacement retires before writing')
assert(hold.release());assert(hold.render(false));assert(writes==n,'Release never rewinds')
parent_node=5;assert(hold.prepare());assert(hold.tick(true,{0,0,0}));parent={0,0,0,0,0,0,0,0,0,0,0,0}
assert(not hold.render(true));assert(writes==n,'Singular parent refuses before any setter')
assert(hold.release());local old=reads;assert(hold.tick(false,{0,0,0}));assert(hold.render(false));assert(reads==old,'Closed state has no getters')
print('Body world anchor: noncommuting rotation/translation, rotating parent compensation, root/cape exclusion, idle, topology/singular refusal and no resume rewind passed')

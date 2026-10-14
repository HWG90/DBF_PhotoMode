local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'subject_poses.lua')
local data=dofile(root..'assets/subject_pose_frames.lua')
local function copy(a)local b={};for k,v in pairs(a)do b[k]=type(v)=='table'and copy(v)or v end;return b end
local function identity()return{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}end
local function multiply(a,b)
 local c={};for row=0,3 do for col=0,3 do local v=0;for k=0,3 do v=v+a[row*4+k+1]*b[k*4+col+1]end;c[row*4+col+1]=v end end;return c
end
local function inverse(a)
 local b=identity();for row=0,2 do for col=0,2 do b[row*4+col+1]=a[col*4+row+1]end end
 for col=0,2 do b[13+col]=-(a[13]*b[1+col]+a[14]*b[5+col]+a[15]*b[9+col])end;return b
end
local function matrix(q,p)
 local x,y,z=q.axis[1],q.axis[2],q.axis[3];local c,s=math.cos(q.angle),math.sin(q.angle);local k=1-c
 return{x*x*k+c,x*y*k+z*s,x*z*k-y*s,0,
  x*y*k-z*s,y*y*k+c,y*z*k+x*s,0,
  x*z*k+y*s,y*z*k-x*s,z*z*k+c,0,p[1],p[2],p[3],1}
end
local function transform(point,m)
 return{point[1]*m[1]+point[2]*m[5]+point[3]*m[9]+m[13],
  point[1]*m[2]+point[2]*m[6]+point[3]*m[10]+m[14],
  point[1]*m[3]+point[2]*m[7]+point[3]*m[11]+m[15]}
end
local function close(a,b,message)
 assert(#a==#b,message);for i=1,#a do assert(math.abs(a[i]-b[i])<1e-6,message..' at '..i..': '..a[i]..' / '..b[i])end
end
local function fixture(options)
 options=options or{}
 local t={phase='menu',paused=true,root_live=true,cape_live=true,attached=true,writes={},cape_writes=0,world_time=0,updates=0}
 local body,cape,world,unrelated={},{},{},{}
 local body_values,cape_values={},{};local names={};local parents={}
 for i,n in ipairs(data.rig.nodes)do body_values[i]=identity();names[n.name or false]=i;parents[i]=n.parent end
 -- A rotated/translated world root and nontrivial local body/cape anchors
 -- expose multiplication-order mistakes hidden by translation-only mocks.
 body_values[1]=matrix({axis={0,0,1},angle=.67},{13,-9,4})
 body_values[8]=matrix({axis={1,0,0},angle=-.31},{.4,-.8,1.2})
 local anchor=assert(names.cape1);body_values[anchor]=matrix({axis={0,1,0},angle=.43},{.15,-.25,.7})
 for i=1,50 do cape_values[i]=identity()end
 local cape_names={cape1=35,cape2=36,cape3=37,g_shock_trooper_cape_simple=43,g_shock_trooper_cape=49,g_shock_trooper_cape_simple_partial=50}
 local placements={43,49,50};local cape_parents={[43]=42,[49]=42,[50]=42}
 if options.variant then
  -- Read-only live variant: all old mesh names absent; its externally linked
  -- cape bones have no local parent. The cloth mesh remains separate at 23.
  cape_names={cape1=21,cape2=22,cape3=24};placements={48,49,50}
  cape_parents={[23]=22,[48]=42,[49]=42,[50]=42}
 end
 if options.unsupported then cape_names.cape2=nil end
 if options.duplicate_bone then cape_names.cape3=cape_names.cape2 end
 if options.bad_bone then cape_names.cape2=51 end
 local mesh_nodes={23,placements[1],placements[2],placements[3]};local meshes={{},{},{},{}}
 cape_values[1]=copy(body_values[1]);cape_values[23]=matrix({axis={0,0,1},angle=.12},{.6,0,.2})
 cape_values[42]=matrix({axis={0,1,0},angle=-.29},{-.3,.2,.1})
 for _,node in ipairs(placements)do cape_values[node]=inverse(cape_values[42])end
 local original_body,original_cape=copy(body_values),copy(cape_values)
 local part={ref=22,native=220,handle=cape,world_native=99,mesh_count=4,meshes={1,2,3,4},mesh_objects=meshes,owner_key='owner'}
 local unrelated_part={ref=23,native=230,handle=unrelated,world_native=99,mesh_count=4,owner_key='owner'}
 local frame={local_owner=true,identity='body:1',owner_key='owner',root_ref=11,root_handle=body,native=110,world=world,world_native=99,component={}}
 if options.foreign_world then part.world_native=100 end
 if options.foreign_owner then part.owner_key='previous-owner'end
 local function world_pose(u,i,depth)
  assert((depth or 0)<128,'Fixture hierarchy cycle')
  if u==cape and i==cape_names.cape1 then return world_pose(body,anchor)end
  local values=u==body and body_values or cape_values;local parent=u==body and parents[i]or(cape_parents[i]or(i==1 and 0 or 1))
  return parent and parent>0 and multiply(values[i],world_pose(u,parent,(depth or 0)+1))or copy(values[i])
 end
 local U={};local mode='position_and_rotation'
 function U.num_scene_graph_items(u)return u==body and 107 or 50 end
 function U.scene_graph_parent(u,i)
  if u==cape and t.parent_changed==i then return 2 end
  if u==cape and options.variant and(i==21 or i==22 or i==24)then return nil end
  return u==body and parents[i]or(cape_parents[i]or(i==1 and 0 or 1))
 end
 function U.has_node(u,name)
  local mapping=u==body and names or u==cape and cape_names
  return type(mapping)=='table'and mapping[name]~=nil
 end
 function U.node(u,name)
  if u==cape and t.changed_bone==name then return cape_names[name]+1 end
  return assert(u==body and names[name]or u==cape and cape_names[name])
 end
 function U.local_pose(u,i)assert(u==body and t.root_live or u==cape and t.cape_live);return copy((u==body and body_values or cape_values)[i])end
 function U.world_pose(u,i)assert(u==body and t.root_live or u==cape and t.cape_live);return world_pose(u,i)end
 function U.set_local_pose(u,i,v)
  assert(t.phase=='update','Pose/cape write escaped owning update')
  assert(u==body and t.root_live or u==cape and t.cape_live,'Stale Unit write')
  if u==cape then
   t.cape_writes=t.cape_writes+1
   if t.fail_node==i then error('Cape setter transient failure')end
  end
  t.writes[#t.writes+1]={unit=u,node=i};(u==body and body_values or cape_values)[i]=copy(v)
 end
 function U.animation_bone_mode(u)assert(u==body);return mode end
 function U.set_animation_bone_mode(u,v)assert(t.phase=='update'and u==body and t.root_live);mode=v end
 function U.has_mesh(u,name)return u==cape and not options.variant and cape_names[name]~=nil end
 function U.mesh(u,index)
  assert(u==cape and t.cape_live)
  if type(index)=='string'then for i,node in ipairs(mesh_nodes)do if node==cape_names[index]then return meshes[i]end end;return nil end
  return meshes[index]
 end
 function U.num_meshes(u)assert(u==cape);return 4 end
 local Mesh={node=function(mesh)for i,value in ipairs(meshes)do if mesh==value then return t.changed_mesh_node==i and 50 or mesh_nodes[i]end end;error('Retired mesh')end}
 local B={}
 function B.pose_frame()return frame end
 function B.pose_valid(f,owner)if t.owner_unknown then return nil,'Transient root ownership'end;return t.root_live and f==frame end
 function B.resolve()
  if options.no_resolve then error('Unsupported attachment reader')end
  local parts=options.unrelated and{part,unrelated_part}or{part}
  return{local_owner=true,groups={hide_player=parts,hide_armour=parts},parts=parts}
 end
 function B.valid(p,index)
  assert(p==part or options.unrelated and p==unrelated_part)
  if p==unrelated_part then return true end
  if t.cape_unknown then return nil,'Transient cape ownership'end
  if not t.cape_live then return false end
  if index and t.retired_mesh==index then return false end
  return true
 end
 function B.owned(p)return p==part and t.attached or options.unrelated and p==unrelated_part end
 local X={multiply=multiply,inverse=inverse,from_quaternion_position=matrix,to_elements=function(v)return unpack(v)end,
  right=function(v)return{v[1],v[2],v[3]}end,forward=function(v)return{v[5],v[6],v[7]}end,
  up=function(v)return{v[9],v[10],v[11]}end,translation=function(v)return{v[13],v[14],v[15]}end}
 local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  {__call=function(_,x,y,z)return{x,y,z}end})
 if options.missing_api then X.right=nil end
 if options.no_mesh_names then U.has_mesh=nil end
 local E={Unit=U,Mesh=Mesh,Matrix4x4=X,Vector3=V,
  Quaternion={axis_angle=function(axis,angle)return{axis=axis,angle=angle}end},
  Matrix4x4Box=function(v)local saved=copy(v);return{unbox=function()return copy(saved)end}end,
  World={update_unit=function(w,u)assert(t.phase=='update'and w==world);t.updates=t.updates+1 end}}
 local api=M.new(E,B,function()return t.paused end,nil,data)
 t.api=api;t.body=body;t.cape=cape;t.values=cape_values;t.original=original_cape;t.original_body=original_body
 t.mesh_nodes=mesh_nodes;t.placements=placements;t.meshes=meshes;t.anchor=anchor;t.body_values=body_values;t.world_pose=world_pose;t.part=part;t.frame=frame
 function t.select(id)
  t.phase='menu';assert(api.refresh(.5));local before=#t.writes;assert(api.queue(id)and#t.writes==before)
  t.phase='update';return api.flush()
 end
 function t.reset()
  t.phase='menu';local before=#t.writes;assert(api.release()and#t.writes==before);t.phase='update';t.restoring=true
  local ok=api.flush();t.restoring=false;return ok
 end
 return t
end

local full_body
for _,entry in ipairs(data.catalog)do if data.poses[entry.id].full_body then full_body=entry.id;break end end
assert(full_body,'Actual catalog contains no full-body pose for the cape trial')
local function restored(t)
 for i=1,50 do close(t.values[i],t.original[i],'Original cape placement was not restored')end
 if t.root_live then for i=1,107 do close(t.body_values[i],t.original_body[i],'Original body pose was not restored')end end
end
local function relative_points(t)
 local reference={};local shoulder=inverse(t.world_pose(t.body,t.anchor))
 for _,node in ipairs(t.placements)do
  local m=t.world_pose(t.cape,node);reference[node]={}
  for _,point in ipairs({{0,0,0},{.3,-.2,.7},{-.4,.6,.1}})do
   reference[node][#reference[node]+1]={point=point,relative=transform(transform(point,m),shoulder)}
  end
 end
 return reference
end
local function attached(t,reference)
 local shoulder=inverse(t.world_pose(t.body,t.anchor))
 for node,points in pairs(reference)do for _,point in ipairs(points)do
  close(transform(transform(point.point,t.world_pose(t.cape,node)),shoulder),point.relative,'Cape moved relative to its posed shoulder')
 end end
 close(t.values[23],t.original[23],'Non-cape mesh placement changed')
 assert(t.world_time==0,'Cape following advanced simulation time')
end

do
 local t=fixture();local reference=relative_points(t)
 assert(t.select(full_body)and t.api.active and t.cape_writes>0,'Supported cape did not follow a full-body pose')
 attached(t,reference)
 assert(t.select('wave'));attached(t,reference)
 -- An engine pass may rewrite the mesh placement; the owned after-update
 -- must reassert the same original shoulder attachment, not recapture it.
 t.values[49]=identity();t.phase='update';assert(t.api.after_update());attached(t,reference)
 assert(t.reset()and not t.api.active and not t.api.pending);restored(t)
end
do
 local t=fixture({variant=true,unrelated=true,no_mesh_names=true});local reference=relative_points(t)
 assert(t.select(full_body)and t.api.active and t.cape_writes>0,'Renamed cape mesh class did not follow a full-body pose')
 attached(t,reference)
 for _,write in ipairs(t.writes)do if write.unit==t.cape then
  assert(write.node==48 or write.node==49 or write.node==50,'Variant wrote a cloth bone or unrelated placement')
 end end
 assert(t.select('wave'));attached(t,reference)
 t.values[49]=identity();t.phase='update';assert(t.api.after_update());attached(t,reference)
 assert(t.reset()and not t.api.active and not t.api.pending);restored(t)
end
for _,options in ipairs({{unsupported=true},{duplicate_bone=true},{bad_bone=true},{missing_api=true},{no_resolve=true},{foreign_world=true},{foreign_owner=true}})do
 local t=fixture(options);assert(t.select(full_body)and t.api.active,'Unsupported cape disabled body poses')
 assert(t.cape_writes==0,'Unsupported cape received placement writes');assert(t.reset());restored(t)
end
do
 local t=fixture({variant=true});assert(t.select(full_body));t.changed_bone='cape2';local before=t.cape_writes
 t.phase='update';assert(not t.api.after_update()and t.api.pending,'Changed cape bone mapping retained follow writes')
 assert(t.cape_writes==before,'Changed cape bone mapping received writes')
 assert(not t.reset()and t.api.active and t.api.pending,'Changed cape bone mapping discarded restoration')
 t.changed_bone=nil;assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));local count=t.cape_writes;t.cape_unknown=true
 assert(not t.reset()and t.api.active and t.api.pending,'Unknown cape ownership discarded restoration')
 assert(t.cape_writes==count,'Unreadable cape received restoration writes')
 t.cape_unknown=false;assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.fail_node=49
 assert(not t.reset()and t.api.active and t.api.pending,'Partial cape restoration discarded the lease')
 close(t.values[43],t.original[43],'Independent cape restoration did not make progress')
 t.fail_node=nil;assert(t.reset());restored(t)
end
do
 local t=fixture();t.fail_node=49;assert(not t.select(full_body)and t.api.active and t.api.pending,'Partial cape apply lost restoration')
 t.fail_node=nil;assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));local count=t.cape_writes;t.cape_live=false
 assert(t.reset()and not t.api.active and not t.api.pending,'Retired cape prevented body restoration')
 assert(t.cape_writes==count,'Retired cape received restoration writes')
end
do
 local t=fixture();assert(t.select(full_body));t.retired_mesh=3;local retired=copy(t.values[49])
 assert(t.reset(),'Retired cape mesh prevented restoring independent placements')
 close(t.values[49],retired,'Retired mesh node received a stale restore')
 for _,node in ipairs({43,50})do close(t.values[node],t.original[node],'Live cape mesh did not restore')end
end
do
 local t=fixture();assert(t.select(full_body));t.parent_changed=49;local before=copy(t.values[49])
 assert(not t.reset()and t.api.active and t.api.pending,'Changed hierarchy discarded cape cleanup')
 close(t.values[49],before,'Restore wrote into a changed placement hierarchy')
 t.parent_changed=nil;assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.changed_mesh_node=3;local before=copy(t.values[49])
 assert(not t.reset()and t.api.active and t.api.pending,'Changed mesh-node mapping discarded restoration')
 close(t.values[49],before,'Restore wrote through a changed mesh-node mapping')
 t.changed_mesh_node=nil;assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.attached=false;t.phase='update'
 assert(not t.api.after_update()and t.api.pending,'Detached cape retained active follow writes')
 assert(t.reset());restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.root_live=false;t.phase='update'
 assert(t.api.flush()and not t.api.active and not t.api.pending,'Retired body left its still-live cape posed')
 restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.root_live=false;t.cape_unknown=true;t.phase='update';local before=t.cape_writes
 assert(not t.api.flush()and t.api.active and t.api.pending,'Body retirement discarded unreadable cape cleanup')
 assert(t.cape_writes==before,'Unknown cape received writes after body retirement')
 t.cape_unknown=false;assert(t.api.flush()and not t.api.active and not t.api.pending);restored(t)
end
do
 local t=fixture();assert(t.select(full_body));t.paused=false;t.phase='update'
 assert(t.api.flush()and not t.api.active,'Resuming time retained cape placement');restored(t)
end
print('Cape poses: renamed mesh/external bone variant, rotated world/shoulder attachment, switch/hold/reset, unsupported fallback, partial/read failures, hierarchy/attachment guards, mesh/body retirement and unpause restoration passed')

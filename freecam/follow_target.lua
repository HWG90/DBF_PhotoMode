-- Read-only camera targets. Never pass these handles to posing or visibility code.
local M={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e8 end
local function point(sr,v)
 local p={sr.Vector3.x(v),sr.Vector3.y(v),sr.Vector3.z(v)}
 assert(finite(p[1]) and finite(p[2]) and finite(p[3]),'Invalid camera target position')
 return p
end
local function distance(a,b)
 return (a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2
end
function M.target(sr,unit,node)
 local U=sr.Unit
 local world=sr.Application.main_world()
 local session=sr.Network.game_session()
 assert(session and world and U.alive(unit) and U.world(unit)==world,'Camera target unavailable')
 local resource=U.resource_name(unit)
 local function frame()
  assert(session==sr.Network.game_session() and world==sr.Application.main_world() and U.alive(unit)
   and U.world(unit)==world and sr.IdString64.equal(resource,U.resource_name(unit)),'Camera target changed')
  local count=U.num_scene_graph_items(unit)
  local index=node
  if not index then
   assert(U.has_node(unit,'head'),'Picked Helldiver has no head')
   index=U.node(unit,'head')
  end
  assert(finite(index) and index%1==0 and index>=1 and index<=count,'Camera target node unavailable')
  local pose=U.world_pose(unit,index)
  local forward=point(sr,sr.Matrix4x4.forward(pose))
  local head=point(sr,U.world_position(unit,index))
  local basis=node and {point(sr,sr.Matrix4x4.right(pose)),forward,point(sr,sr.Matrix4x4.up(pose))}
  return {basis=basis,position=node and head or point(sr,U.world_position(unit,1)),head=head,identity=unit,
   yaw=math.atan2(forward[2],forward[1]),pitch=math.atan2(forward[3],math.sqrt(forward[1]^2+forward[2]^2))}
 end
 frame()
 return frame
end
-- Explicit pin pick: search near the visible surface for a scene node, once per click.
function M.surface(sr,camera,x,y,w,h,depth)
 assert(finite(depth) and depth>0,'Pin needs depth at the clicked surface')
 local tangent=math.tan(camera.fov/2)
 local sx=(2*x/w-1)*tangent*w/h
 local sy=(2*y/h-1)*tangent
 local hit={}
 for i=1,3 do hit[i]=camera.pos[i]+depth*(camera.forward[i]+sx*camera.right[i]+sy*camera.up[i])end
 local U=sr.Unit
 local best,node,nearest=nil,nil,2.25
 local world=sr.Application.main_world()
 local scanned,reads=0,0
 for _,unit in pairs(sr.World.units(world))do
  scanned=scanned+1
  assert(scanned<=16384,'Too many units for a pin pick')
  if type(unit)=='userdata' and U.alive(unit) and U.world(unit)==world then
   local count=U.num_scene_graph_items(unit)
   if count>=1 and count<=512 and distance(point(sr,U.world_position(unit,1)),hit)<=144 then
    for i=1,count do
     reads=reads+1
     assert(reads<=8192,'Too many nearby nodes. Move closer and pick again')
     local d=distance(point(sr,U.world_position(unit,i)),hit)
     if d<nearest then best,node,nearest=unit,i,d end
    end
   end
  end
 end
 assert(best,'No attachment point near that surface')
 return M.target(sr,best,node),node
end
return M

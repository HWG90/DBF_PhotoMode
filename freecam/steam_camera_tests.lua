local factory=dofile('freecam/steam_camera.lua')
local function vector(x,y,z)return{x=x,y=y,z=z}end
local V=setmetatable({x=function(v)return v.x end,y=function(v)return v.y end,z=function(v)return v.z end},{__call=function(_,...)return vector(...)end})
local function yaw(q)return 2*math.atan2(q[3],q[4])end
local function rotation_z(angle)return{0,0,math.sin(angle/2),math.cos(angle/2)}end
local function pose(angle,p)return{angle=angle,position=vector(p.x,p.y,p.z)}end
-- Planar rigid transforms follow the native row-vector multiplication order.
-- The parented camera below computes its world pose separately by forward kinematics.
local M4={
 translation=function(p)return p.position or p end,
 rotation=function(p)return rotation_z(p.angle)end,
 from_quaternion_position=function(q,p)return pose(yaw(q),p)end,
 forward=function(p)return vector(math.cos(p.angle),math.sin(p.angle),0)end,
 right=function(p)return vector(math.sin(p.angle),-math.cos(p.angle),0)end,
 up=function()return vector(0,0,1)end}
function M4.multiply(a,b)
 local c,s=math.cos(b.angle),math.sin(b.angle)
 return pose(a.angle+b.angle,vector(a.position.x*c-a.position.y*s+b.position.x,
  a.position.x*s+a.position.y*c+b.position.y,a.position.z+b.position.z))
end
function M4.inverse(p)
 local c,s=math.cos(p.angle),math.sin(p.angle)
 return pose(-p.angle,vector(-p.position.x*c-p.position.y*s,p.position.x*s-p.position.y*c,-p.position.z))
end
local Q={to_elements=function(q)return unpack(q)end,from_elements=function(...)return{...}end,
 look=function(forward,up)
  assert(math.abs(up.x)<1e-8 and math.abs(up.y)<1e-8 and math.abs(up.z-1)<1e-8)
  return rotation_z(math.atan2(forward.y,forward.x))
 end}
local function near(a,b,label)assert(math.abs(a-b)<1e-6,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b))end
local world,unit,camera={},{},{}
local position=vector(1,2,3)
local alive=true;local scans,reads,writes=0,0,0
local sr={Vector3=V,Matrix4x4=M4,
 Application={main_world=function()reads=reads+1;return world end},
 World={debug_camera_pose=function()return vector(1,2,3)end,units=function()scans=scans+1;return{unit}end,
 update_unit=function(w,u)assert(w==world and u==unit)end,
 unit_by_id=function()error('Dynamic cameras must not use level ID lookup')end},
 Unit={alive=function(u)assert(u==unit);return alive end,num_cameras=function()return 1 end,
 camera=function(u,index)assert(u==unit and index==1);return camera end,
 id=function()error('Dynamic camera IDs may be nil')end},
 Camera={world_position=function(c)assert(c==camera);return position end,
 local_position=function(c,u)assert(c==camera and u==unit,'Parent required');return position end,
 set_local_position=function(c,u,p)assert(c==camera and u==unit and p,'Camera write ABI requires parent');writes=writes+1;position=p end}}
local c=factory.new(sr)
assert(c.close() and reads==0 and scans==0 and writes==0)
assert(c.open() and scans==1)
for i=1,100 do assert(c.write({2,3,4}));assert(c.position()[1]==2)end
assert(scans==1,'Active camera must not rescan world units')
assert(c.close() and position.x==1 and writes==101)
assert(c.open());assert(c.write({5,6,7}));position=vector(9,9,9)
assert(c.close() and position.x==9,'Do not overwrite another owner during cleanup')
position=vector(1,2,3);assert(c.open());assert(c.write({5,6,7}));alive=false
local before=writes;assert(c.close() and writes==before,'Do not write a retired unit')
alive=true;position=vector(1,2,3);assert(c.open());assert(c.write({5,6,7}));world={}
before=writes;assert(c.close() and writes==before,'Do not touch a previous world')
position=vector(1,2,3);assert(c.open());assert(c.write({5,6,7}));camera={}
before=writes;assert(c.close() and writes==before,'Do not restore a replacement camera component')
position=vector(1,2,3);assert(c.open());assert(c.write({5,6,7}))
local set=sr.Camera.set_local_position
sr.Camera.set_local_position=function()return false end
assert(c.close()==false and c.active(),'A refused restore must keep its cleanup lease')
sr.Camera.set_local_position=set
assert(c.close())
position=vector(1,2,3);assert(c.open());assert(c.write({5,6,7}))
local update=sr.World.update_unit
sr.World.update_unit=function()return false end
assert(c.close()==false and c.active(),'Keep cleanup lease until scene update succeeds')
sr.World.update_unit=update
assert(c.close())
local rotation={0,0,.70710678,.70710678};local fov=1
sr.Quaternion=Q
sr.Camera.world_pose=function(c)assert(c==camera);return pose(yaw(rotation),position)end
sr.Camera.local_pose=function(c,u)assert(c==camera and(u==nil or u==unit));return pose(yaw(rotation),position)end
sr.Camera.local_rotation=function(c,u)assert(c==camera and u==unit);return rotation end
sr.Camera.set_local_rotation=function(c,u,q)assert(c==camera and u==unit);rotation=q end
sr.Camera.vertical_fov=function(c)assert(c==camera);return fov end
sr.Camera.set_vertical_fov=function(c,value)assert(c==camera);fov=value end
position=vector(1,2,3);assert(c.open());near(c.frame().forward[2],1,'Initial world orientation')
assert(c.write_view({2,3,4},{1,0,0},{0,0,1},.8))
assert(fov==.8 and rotation[4]==1)
assert(c.close()and fov==1 and math.abs(rotation[4]-.70710678)<1e-7)
assert(c.open());assert(c.write_view({2,3,4},{1,0,0},{0,0,1},.8))
fov=1.2;rotation={0,0,1,0}
assert(c.close()and fov==1.2 and rotation[3]==1,'Preserve external lens/rotation changes')

do
 local scene,owner,component={},{},{}
 local parent={x=10,y=20,z=5,angle=math.pi/2}
 local local_position=vector(2,3,4);local local_rotation=rotation_z(math.pi/6);local lens=1.1
 local native_writes,updates,discoveries=0,0,0
 -- Independent FK: transform the camera node by its actual translated/rotated parent.
 -- Expected positions below are fixed numeric examples, not the adapter's inverse formula.
 local function world_pose()
  local c,s=math.cos(parent.angle),math.sin(parent.angle)
  return pose(parent.angle+yaw(local_rotation),vector(parent.x+c*local_position.x-s*local_position.y,
   parent.y+s*local_position.x+c*local_position.y,parent.z+local_position.z))
 end
 local published=world_pose();local rendered_override
 local native={Vector3=V,Matrix4x4=M4,Quaternion=Q,
  Application={main_world=function()return scene end},
  World={debug_camera_pose=function(w)assert(w==scene);return rendered_override or published end,
   units=function(w)assert(w==scene);discoveries=discoveries+1;return{owner}end,
   update_unit=function(w,u)assert(w==scene and u==owner);updates=updates+1;published=world_pose()end},
  Unit={alive=function(u)assert(u==owner);return true end,num_cameras=function()return 1 end,
   camera=function(u,index)assert(u==owner and index==1);return component end},
  Camera={world_position=function(cam)assert(cam==component);return world_pose().position end,
   world_pose=function(cam)assert(cam==component);return world_pose()end,
   local_pose=function(cam,u)assert(cam==component and(u==nil or u==owner));return pose(yaw(local_rotation),local_position)end,
   local_position=function(cam,u)assert(cam==component and u==owner);return local_position end,
   local_rotation=function(cam,u)assert(cam==component and u==owner);return local_rotation end,
   vertical_fov=function(cam)assert(cam==component);return lens end,
   set_local_position=function(cam,u,p)assert(cam==component and u==owner);native_writes=native_writes+1;local_position=p end,
   set_local_rotation=function(cam,u,q)assert(cam==component and u==owner);native_writes=native_writes+1;local_rotation=q end,
   set_vertical_fov=function(cam,value)assert(cam==component);native_writes=native_writes+1;lens=value end}}
 local camera=factory.new(native);assert(camera.open())
 local frame=assert(camera.frame())
 near(frame.position[1],7,'Frame world X');near(frame.position[2],22,'Frame world Y');near(frame.position[3],9,'Frame world Z')
 near(frame.forward[1],-.5,'Frame world forward X');near(frame.forward[2],math.sqrt(3)/2,'Frame world forward Y')
 local diagnostic_position=camera.position();near(diagnostic_position[1],2,'Diagnostic position stays local')
 assert(camera.write_view({13,24,11},{1,0,0},{0,0,1},.7))
 near(local_position.x,4,'Converted local X');near(local_position.y,-3,'Converted local Y');near(local_position.z,6,'Converted local Z')
 near(math.sin(yaw(local_rotation)),-1,'Converted local orientation')
 local actual=world_pose();near(actual.position.x,13,'Published world X');near(actual.position.y,24,'Published world Y');near(actual.position.z,11,'Published world Z')
 near(M4.forward(actual).x,1,'Published world forward X');near(M4.forward(actual).y,0,'Published world forward Y')
 -- Parent movement between updates must not move the requested world composition.
 parent.x,parent.y,parent.z,parent.angle=-5,8,2,math.pi
 assert(camera.write_view({13,24,11},{1,0,0},{0,0,1},.7,true))
 near(local_position.x,-18,'Moved-parent local X');near(local_position.y,-16,'Moved-parent local Y');near(local_position.z,9,'Moved-parent local Z')
 actual=world_pose();near(actual.position.x,13,'Held world X');near(actual.position.y,24,'Held world Y');near(actual.position.z,11,'Held world Z')
 near(M4.forward(actual).x,1,'Held world forward X');near(M4.forward(actual).y,0,'Held world forward Y')
 -- Gameplay may update and publish this same held component before our render override.
 -- Accept its current world pose as well as the previous frame's published shot.
 local_position=vector(-17,-15,9);local_rotation=rotation_z(-math.pi+.2);published=world_pose()
 assert(camera.write_view({13,24,11},{1,0,0},{0,0,1},.7,true),
  'A newly published pose from the still-owned camera must not look like camera replacement')
 actual=world_pose();near(actual.position.x,13,'Pre-override publication world X');near(actual.position.y,24,'Pre-override publication world Y')
 near(actual.position.z,11,'Pre-override publication world Z');near(M4.forward(actual).x,1,'Pre-override publication forward X')
 near(M4.forward(actual).y,0,'Pre-override publication forward Y')
 assert(discoveries==1,'World conversion must not rediscover camera units')
 -- A different rendered camera in the same live world must be rejected before any setter/update.
 rendered_override=pose(.8,vector(100,200,300))
 local writes_before,updates_before=native_writes,updates
 local accepted,why=camera.write_view({14,25,12},{1,0,0},{0,0,1},.8,true)
 assert(accepted==false and why and native_writes==writes_before and updates==updates_before,
  'Rendered-camera replacement must refuse the complete world write without native side effects')
 assert(camera.close())
 near(local_position.x,2,'Owned local position restore X');near(local_position.y,3,'Owned local position restore Y');near(local_position.z,4,'Owned local position restore Z')
 near(yaw(local_rotation),math.pi/6,'Owned local rotation restore');near(lens,1.1,'Owned lens restore')
 -- Cleanup still compares local values and preserves a later foreign writer.
 rendered_override=nil;published=world_pose();assert(camera.open())
 assert(camera.write_view({13,24,11},{1,0,0},{0,0,1},.7))
 local_position=vector(8,9,10);local_rotation=rotation_z(.4);lens=1.3
 assert(camera.close())
 near(local_position.x,8,'Foreign local position');near(yaw(local_rotation),.4,'Foreign local rotation');near(lens,1.3,'Foreign lens')
end
print('Steam camera: parent ABI, no level IDs, explicit discovery, idle work and owned cleanup passed')

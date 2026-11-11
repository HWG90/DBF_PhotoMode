-- Natural limits table against the pose bank it was read from, in actual Lua 5.1.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local E=dofile('freecam/pose_editor.lua');local bank=dofile('freecam/assets/steam_subject_poses.lua');local limits=dofile('freecam/assets/pose_limits.lua')
assert(limits.version==1 and limits.poses==#bank.catalog and type(limits.nodes)=='table')
-- Every bone the editor offers has a limit, except the Cape and the gear sockets.
local expected,count=0,0
for _,group in ipairs(E.GROUPS)do for _,bone in ipairs(group.bones)do
 local limit=limits.nodes[bone.node]
 if group.id=='cape'or group.id=='gear'then assert(limit==nil,group.label..' is left free: '..bone.label)
 else
  expected=expected+1
  assert(type(limit)=='table',group.label..' / '..bone.label..' has no limit')
  local n=0;for i=1,4 do assert(type(limit.r[i])=='number');n=n+limit.r[i]^2 end;assert(math.abs(n-1)<1e-5,'Rest rotation is a unit quaternion')
  for _,axis in ipairs({'t','y','z'})do
   local range=limit[axis];assert(#range==2 and range[1]<range[2]and range[1]>=-180 and range[2]<=180,'Range shape')
   assert(range[1]<=0 and range[2]>=0,'The rest rotation is inside its own ranges')
   assert(range[2]-range[1]>=4,'A range is never narrower than the margin on both sides')
  end
 end
end end
for _ in pairs(limits.nodes)do count=count+1 end;assert(count==expected and count>50,'No limit for a bone the editor does not offer')
-- Every pose the game ships is natural: the limiter changes none of them.
for index,item in ipairs(bank.catalog)do
 local pose=assert(bank.decode(item.id))
 for node,limit in pairs(limits.nodes)do
  local _,changed=E.limit_rotation(limit,pose.nodes[node].q)
  assert(not changed,item.id..' is outside the limits at node '..node)
 end
end
-- Knees are hinges that bend one way; twist bones only twist; the armour pads do not turn.
local function width(range)return range[2]-range[1]end
for _,node in ipairs({13,18})do local knee=limits.nodes[node]
 assert(width(knee.t)<6 and width(knee.y)<6 and width(knee.z)>120,'A knee bends about one axis only')
 -- From a straight leg (the straightest pose in the bank), backwards is held to the margin.
 local straight;for _,item in ipairs(bank.catalog)do local q=bank.decode(item.id).nodes[node].q;local _,_,z=E.swing_twist(E.quat_multiply({-knee.r[1],-knee.r[2],-knee.r[3],knee.r[4]},q));if not straight or z>straight.z then straight={q=q,z=z}end end
 local back=E.compose(straight.q,40,0,0);local held,changed=E.limit_rotation(knee,back,straight.q);assert(changed,'A knee bent backwards is stopped')
 local _,_,z=E.swing_twist(E.quat_multiply({-knee.r[1],-knee.r[2],-knee.r[3],knee.r[4]},held));assert(z-straight.z<=8.01,'...within the margin past straight')
 local _,free=E.limit_rotation(knee,E.compose(straight.q,-90,0,0),straight.q);assert(not free,'...and bends forwards freely')
 local _,side=E.limit_rotation(knee,E.compose(straight.q,-45,25,0),straight.q);assert(side,'A knee does not bend sideways')
end
for _,node in ipairs({46,65,69,71})do local twist=limits.nodes[node];assert(width(twist.t)>100 and width(twist.y)<6 and width(twist.z)<6,'A twist bone only twists')end
for _,node in ipairs({44,67})do local pad=limits.nodes[node];assert(width(pad.t)<6 and width(pad.y)<6 and width(pad.z)<6,'Shoulder armour stays put')end
print('Pose limits: coverage, every bank pose inside, hinge knees, twist bones and fixed armour pads passed')

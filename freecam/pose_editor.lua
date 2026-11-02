-- Pure pose editor: bone groups, quaternion maths and composed frames.
-- No engine access. Frames are the subject controller's numeric nodes
-- (p, q xyzw, s, optional canonical pose); the editor changes only q.
local M={BONE_FRAME_SIDE='right'}
-- Carry sockets the game re-places every frame; the controller skips them for edits.
M.GAME_OWNED={[23]='attach_samplepouch',[24]='attach_intelpad',[25]='target_designator',[28]='sling',[31]='support_mg',[32]='support'}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function fingers(side,first)
 -- first = node of thumb segment 1 for the thumb, then each finger's own first node.
 local out={}
 for _,finger in ipairs(first)do for segment=1,3 do out[#out+1]={node=finger.node+segment-1,label=finger.label..' '..segment}end end
 return out
end
M.GROUPS={
 {id='body',label='Body',bones={{node=8,label='Body root'},{node=10,label='Hips'},{node=22,label='Spine 1'},{node=27,label='Spine 2'},{node=29,label='Chest'},{node=90,label='Neck'},{node=91,label='Head'}}},
 {id='left_arm',label='Left arm',bones={{node=43,label='Clavicle'},{node=45,label='Shoulder'},{node=47,label='Elbow'},{node=48,label='Hand'},{node=46,label='Shoulder twist'},{node=65,label='Hand twist'},{node=44,label='Shoulder armour'}}},
 {id='right_arm',label='Right arm',bones={{node=66,label='Clavicle'},{node=68,label='Shoulder'},{node=70,label='Elbow'},{node=72,label='Hand'},{node=69,label='Shoulder twist'},{node=71,label='Hand twist'},{node=67,label='Shoulder armour'}}},
 {id='left_leg',label='Left leg',bones={{node=17,label='Thigh'},{node=18,label='Knee'},{node=19,label='Foot'},{node=20,label='Ball'},{node=21,label='Toe'}}},
 {id='right_leg',label='Right leg',bones={{node=11,label='Thigh'},{node=13,label='Knee'},{node=14,label='Foot'},{node=15,label='Ball'},{node=16,label='Toe'}}},
 {id='left_hand',label='Left hand',bones=fingers('l',{{node=62,label='Thumb'},{node=59,label='Index'},{node=56,label='Middle'},{node=53,label='Ring'},{node=50,label='Pinky'}})},
 {id='right_hand',label='Right hand',bones=fingers('r',{{node=87,label='Thumb'},{node=82,label='Index'},{node=79,label='Middle'},{node=76,label='Ring'},{node=73,label='Pinky'}})},
 {id='cape',label='Cape',bones={}},
 {id='gear',label='Aim and gear',bones={{node=9,label='Aim'},{node=92,label='Head aim'},{node=33,label='Weapon mount'},{node=34,label='Weapon aim'},{node=86,label='Hand aim'},{node=49,label='Left hand mount'},{node=85,label='Right hand mount'},{node=12,label='Pistol'},{node=30,label='Backpack'},{node=26,label='Knife'}}},
}
for i=1,8 do M.GROUPS[8].bones[i]={node=34+i,label='Cape '..i}end
M.rig_names={[8]='boss',[9]='boss_aim',[10]='hips',[11]='r_thigh',[12]='pistol',[13]='r_knee',[14]='r_foot',[15]='r_ball',[16]='r_toe',
 [17]='l_thigh',[18]='l_knee',[19]='l_foot',[20]='l_ball',[21]='l_toe',[22]='spine1',[23]='attach_samplepouch',[24]='attach_intelpad',
 [25]='target_designator',[26]='attach_knife',[27]='spine2',[28]='sling',[29]='chest',[30]='backpack',[31]='support_mg',[32]='support',
 [33]='attach_weapon',[34]='aim_weapon',[43]='l_clavicle',[44]='l_shoulderarmour',[45]='l_shoulder',[46]='l_shoulder_twist',[47]='l_elbow',
 [48]='l_hand',[49]='attach_hand_l',[65]='l_hand_twist',[66]='r_clavicle',[67]='r_shoulderarmour',[68]='r_shoulder',[69]='r_shoulder_twist',
 [70]='r_elbow',[71]='r_hand_twist',[72]='r_hand',[85]='attach_hand_r',[86]='weapon_aim',[90]='neck',[91]='head',[92]='head_aim'}
for i=1,8 do M.rig_names[34+i]='cape'..i end
for _,f in ipairs({{62,'l_thumb'},{59,'l_index'},{56,'l_middle'},{53,'l_ring'},{50,'l_pinky'},{87,'r_thumb'},{82,'r_index'},{79,'r_middle'},{76,'r_ring'},{73,'r_pinky'}})do
 for s=1,3 do M.rig_names[f[1]+s-1]=f[2]..'_finger'..s end
end
function M.quat_multiply(a,b)
 local ax,ay,az,aw,bx,by,bz,bw=a[1],a[2],a[3],a[4],b[1],b[2],b[3],b[4]
 return{aw*bx+ax*bw+ay*bz-az*by,aw*by-ax*bz+ay*bw+az*bx,aw*bz+ax*by-ay*bx+az*bw,aw*bw-ax*bx-ay*by-az*bz}
end
function M.quat_normalize(q)
 local n=math.sqrt(q[1]*q[1]+q[2]*q[2]+q[3]*q[3]+q[4]*q[4])
 if n<1e-12 then return{0,0,0,1}end
 return{q[1]/n,q[2]/n,q[3]/n,q[4]/n}
end
function M.quat_axis_angle(x,y,z,degrees)
 local n=math.sqrt(x*x+y*y+z*z);if n<1e-12 then return{0,0,0,1}end
 local half=math.rad(degrees)/2;local s=math.sin(half)/n
 return{x*s,y*s,z*s,math.cos(half)}
end
-- Rotate a vector by a unit quaternion (xyzw): rotate = q v q*, rotate_inverse = q* v q.
local function conjugate(q)return{-q[1],-q[2],-q[3],q[4]}end
function M.rotate(q,v)
 local p=M.quat_multiply(M.quat_multiply(q,{v[1],v[2],v[3],0}),conjugate(q));return{p[1],p[2],p[3]}
end
function M.rotate_inverse(q,v)
 local p=M.quat_multiply(M.quat_multiply(conjugate(q),{v[1],v[2],v[3],0}),q);return{p[1],p[2],p[3]}
end
-- Bend about local Z, Swing about local Y, Twist about local X, applied in
-- the bone's own frame: the delta sits on BONE_FRAME_SIDE of the base.
function M.compose(base_q,bend,swing,twist)
 local delta=M.quat_multiply(M.quat_multiply(M.quat_axis_angle(0,0,1,bend),M.quat_axis_angle(0,1,0,swing)),M.quat_axis_angle(1,0,0,twist))
 if M.BONE_FRAME_SIDE=='right'then return M.quat_normalize(M.quat_multiply(base_q,delta))end
 return M.quat_normalize(M.quat_multiply(delta,base_q))
end
-- The inverse of compose for a unit delta (xyzw): Bend, Swing, Twist in degrees. Swing is
-- asin-bounded; at Swing +-90 Twist folds into Bend and the rotation itself is kept.
function M.decompose(q)
 local x,y,z,w=q[1],q[2],q[3],q[4]
 local m11,m21,m31=1-2*(y*y+z*z),2*(x*y+z*w),2*(x*z-y*w)
 local m12,m22=2*(x*y-z*w),1-2*(x*x+z*z)
 local m32,m33=2*(y*z+x*w),1-2*(x*x+y*y)
 local s=math.max(-1,math.min(1,-m31))
 local bend,twist
 if math.abs(s)>1-1e-12 then bend,twist=math.atan2(-m12,m22),0 else bend,twist=math.atan2(m21,m11),math.atan2(m32,m33)end
 return math.deg(bend),math.deg(math.asin(s)),math.deg(twist)
end
-- Angles for a parent bone so that its child points at a world target, bone length kept:
-- base_q is the parent's base rotation (in its own parent's frame), grand_q that parent's
-- world rotation (identity for a root), parent_q the parent's current world rotation,
-- parent_p/child_p/target world positions. The turn is the smallest one from the bone's
-- direction to the target's; the result replaces the parent's three angles.
function M.aim(base_q,grand_q,parent_q,parent_p,child_p,target)
 local d={child_p[1]-parent_p[1],child_p[2]-parent_p[2],child_p[3]-parent_p[3]}
 local t={target[1]-parent_p[1],target[2]-parent_p[2],target[3]-parent_p[3]}
 local dl,tl=math.sqrt(d[1]*d[1]+d[2]*d[2]+d[3]*d[3]),math.sqrt(t[1]*t[1]+t[2]*t[2]+t[3]*t[3])
 if not(dl>1e-6)then return nil,'Bone too short'end
 if not(tl>1e-6)then return nil,'Target at the joint'end
 for i=1,3 do d[i]=d[i]/dl;t[i]=t[i]/tl end
 local dot=d[1]*t[1]+d[2]*t[2]+d[3]*t[3]
 local turn
 if dot<-1+1e-9 then
  -- Antiparallel: a half turn about any axis across the bone.
  local ax={-d[2],d[1],0};if math.abs(ax[1])+math.abs(ax[2])<1e-6 then ax={0,-d[3],d[2]}end
  turn=M.quat_axis_angle(ax[1],ax[2],ax[3],180)
 else
  turn=M.quat_normalize({d[2]*t[3]-d[3]*t[2],d[3]*t[1]-d[1]*t[3],d[1]*t[2]-d[2]*t[1],1+dot})
 end
 -- turn * parent_q = grand_q * base_q * delta
 local delta=M.quat_multiply(conjugate(base_q),M.quat_multiply(conjugate(grand_q),M.quat_multiply(turn,parent_q)))
 return M.decompose(M.quat_normalize(delta))
end
local AXES={bend=1,swing=2,twist=3}
-- A loaded 'X edits' pose is the base named X: the suffix never stacks.
local function base_name(text)return(tostring(text):match('^(.-) edits$'))or tostring(text)end
local function clamp(v)return math.max(-180,math.min(180,v))end
local function clamp_metres(v)return math.max(-1,math.min(1,v))end
function M.new()
 local self={};local base,label;local angles={};local offsets={};local selected=70;local dirty=false
 local function copy3(v)return{v[1],v[2],v[3]}end
 function self.rebase(frame,text)
  assert(type(frame)=='table'and type(frame.nodes)=='table','Pose base frame required')
  for i=8,92 do assert(type(frame.nodes[i])=='table'and type(frame.nodes[i].q)=='table','Pose base node missing: '..i)end
  base,label=frame,tostring(text or'Pose');angles={};offsets={};dirty=false
 end
 function self.clear()base,label=nil,nil;angles={};offsets={};dirty=false end
 -- A base taken when editing has already started: angles survive.
 function self.adopt(frame,text)
  local kept,kept_offsets=angles,offsets;self.rebase(frame,text);angles,offsets=kept,kept_offsets;dirty=true
 end
 function self.touch()dirty=true end
 function self.has_base()return base~=nil end
 function self.base_rotation(node)local n=base and base.nodes[node];return n and n.q or nil end
 function self.base_label()return label end
 function self.select(node)
  if not M.rig_names[node]then return false,'Unknown bone'end
  selected=node;return true
 end
 function self.selected()return selected end
 function self.angles(node)local a=angles[node];if not a then return 0,0,0 end;return a[1],a[2],a[3]end
 function self.set_angle(node,axis,degrees)
  if not M.rig_names[node]then return false,'Unknown bone'end
  local index=AXES[axis];if not index then return false,'Unknown axis'end
  if not finite(degrees)then return false,'Angle must be a number'end
  local value=clamp(degrees);local a=angles[node]or{0,0,0}
  if a[index]==value then return true end
  a[index]=value
  if a[1]==0 and a[2]==0 and a[3]==0 then angles[node]=nil else angles[node]=a end
  dirty=true;return true
 end
 -- Offsets move a bone in its parent's frame (metres, clamped to one metre).
 function self.offset(node)local o=offsets[node];if not o then return 0,0,0 end;return o[1],o[2],o[3]end
 function self.nudge_offset(node,dx,dy,dz)
  if not M.rig_names[node]then return false,'Unknown bone'end
  if not(finite(dx)and finite(dy)and finite(dz))then return false,'Offset must be a number'end
  local o=offsets[node]or{0,0,0}
  local n={clamp_metres(o[1]+dx),clamp_metres(o[2]+dy),clamp_metres(o[3]+dz)}
  if n[1]==o[1]and n[2]==o[2]and n[3]==o[3]then return true end
  if n[1]==0 and n[2]==0 and n[3]==0 then offsets[node]=nil else offsets[node]=n end
  dirty=true;return true
 end
 function self.reset_bone(node)angles[node]=nil;offsets[node]=nil;dirty=true end
 function self.reset_all()angles={};offsets={};dirty=true end
 function self.edited()return next(angles)~=nil or next(offsets)~=nil end
 function self.dirty()return dirty end
 -- keep_dirty: a copy for saving, which must not count as an apply.
 function self.compose_frame(keep_dirty)
  if not base then return nil,'No base pose'end
  local nodes={}
  for i=8,92 do
   local source=base.nodes[i];local a=angles[i];local o=offsets[i]
   if a or o then
    local p=copy3(source.p);if o then p[1]=p[1]+o[1];p[2]=p[2]+o[2];p[3]=p[3]+o[3]end
    nodes[i]={p=p,q=a and M.compose(source.q,a[1],a[2],a[3])or{source.q[1],source.q[2],source.q[3],source.q[4]},s=copy3(source.s)}
   else nodes[i]=source end
  end
  if not keep_dirty then dirty=false end
  return{full_body=true,nodes=nodes,label=self.edited()and base_name(label)..' edits'or label}
 end
 function self.status(group_label,bone_label)
  local where=tostring(group_label)..' / '..tostring(bone_label)
  if not base then return'Freeze Action, then move a slider  |  '..where end
  local b,s,t=self.angles(selected);local ox,oy,oz=self.offset(selected)
  local text=(self.edited()and base_name(label)..' edits'or label)..'  |  '..where..string.format('  Bend %d  Swing %d  Twist %d',b,s,t)
  if ox~=0 or oy~=0 or oz~=0 then text=text..string.format('  Move %d/%d/%d cm',math.floor(ox*100+.5),math.floor(oy*100+.5),math.floor(oz*100+.5))end
  return text
 end
 return self
end
return M

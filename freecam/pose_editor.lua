-- Pure pose editor: bone groups, quaternion maths and composed frames.
-- No engine access. Frames are the subject controller's numeric nodes
-- (p, q xyzw, s, optional canonical pose); the editor changes only q.
local M={BONE_FRAME_SIDE='right'}
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
 {id='gear',label='Aim and gear',bones={{node=9,label='Aim'},{node=92,label='Head aim'},{node=33,label='Weapon mount'},{node=34,label='Weapon aim'},{node=86,label='Hand aim'},{node=49,label='Left hand mount'},{node=85,label='Right hand mount'},{node=12,label='Pistol'},{node=30,label='Backpack'},{node=28,label='Sling'},{node=32,label='Support'},{node=31,label='Support MG'},{node=23,label='Pouch'},{node=24,label='Intel pad'},{node=25,label='Designator'},{node=26,label='Knife'}}},
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
-- Bend about local Z, Swing about local Y, Twist about local X, applied in
-- the bone's own frame: the delta sits on BONE_FRAME_SIDE of the base.
function M.compose(base_q,bend,swing,twist)
 local delta=M.quat_multiply(M.quat_multiply(M.quat_axis_angle(0,0,1,bend),M.quat_axis_angle(0,1,0,swing)),M.quat_axis_angle(1,0,0,twist))
 if M.BONE_FRAME_SIDE=='right'then return M.quat_normalize(M.quat_multiply(base_q,delta))end
 return M.quat_normalize(M.quat_multiply(delta,base_q))
end
local AXES={bend=1,swing=2,twist=3}
local function clamp(v)return math.max(-180,math.min(180,v))end
function M.new()
 local self={};local base,label;local angles={};local selected=70;local dirty=false
 local function copy3(v)return{v[1],v[2],v[3]}end
 function self.rebase(frame,text)
  assert(type(frame)=='table'and type(frame.nodes)=='table','Pose base frame required')
  for i=8,92 do assert(type(frame.nodes[i])=='table'and type(frame.nodes[i].q)=='table','Pose base node missing: '..i)end
  base,label=frame,tostring(text or'Pose');angles={};dirty=false
 end
 function self.clear()base,label=nil,nil;angles={};dirty=false end
 -- A base taken when editing has already started: angles survive.
 function self.adopt(frame,text)
  local kept=angles;self.rebase(frame,text);angles=kept;dirty=true
 end
 function self.touch()dirty=true end
 function self.has_base()return base~=nil end
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
 function self.reset_bone(node)angles[node]=nil;dirty=true end
 function self.reset_all()angles={};dirty=true end
 function self.edited()return next(angles)~=nil end
 function self.dirty()return dirty end
 -- keep_dirty: a copy for saving, which must not count as an apply.
 function self.compose_frame(keep_dirty)
  if not base then return nil,'No base pose'end
  local nodes={}
  for i=8,92 do
   local source=base.nodes[i];local a=angles[i]
   if a then nodes[i]={p=copy3(source.p),q=M.compose(source.q,a[1],a[2],a[3]),s=copy3(source.s)}
   else nodes[i]=source end
  end
  if not keep_dirty then dirty=false end
  return{full_body=true,nodes=nodes,label=self.edited()and label..' edits'or label}
 end
 function self.status(group_label,bone_label)
  local where=tostring(group_label)..' / '..tostring(bone_label)
  if not base then return'Freeze Action, then move a slider  |  '..where end
  local b,s,t=self.angles(selected)
  return(self.edited()and label..' edits'or label)..'  |  '..where..string.format('  Bend %d  Swing %d  Twist %d',b,s,t)
 end
 return self
end
return M

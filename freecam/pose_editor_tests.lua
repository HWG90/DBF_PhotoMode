-- Pure pose editor contracts in actual Lua 5.1: bone groups, quaternion maths, composed frames.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local E=dofile('freecam/pose_editor.lua');local bank=dofile('freecam/assets/steam_subject_poses.lua')
-- Group coverage: every node 8..92 exactly once, names match the rig.
local seen={};for _,g in ipairs(E.GROUPS)do for _,b in ipairs(g.bones)do
 assert(not seen[b.node],'Node listed twice: '..b.node);seen[b.node]=true
 assert(bank.rig.nodes[b.node].name==E.rig_names[b.node],'Rig name mismatch at '..b.node)end end
for i=8,92 do assert(seen[i]or E.GAME_OWNED[i],'Node not grouped: '..i);assert(not(seen[i]and E.GAME_OWNED[i]),'Game-owned node offered: '..i)end
for node,name in pairs(E.GAME_OWNED)do assert(bank.rig.nodes[node].name==name,'Game-owned name mismatch at '..node)end
assert(#E.GROUPS==9 and E.GROUPS[1].id=='body'and E.GROUPS[9].id=='gear')
-- Quaternion maths against known values.
local function near(a,b)for i=1,4 do if math.abs(a[i]-b[i])>1e-9 then return false end end;return true end
assert(near(E.quat_axis_angle(0,0,1,90),{0,0,math.sin(math.rad(45)),math.cos(math.rad(45))}))
assert(near(E.quat_multiply({0,0,0,1},{.1,.2,.3,.9}),{.1,.2,.3,.9}),'Identity is neutral')
assert(near(E.quat_normalize({0,0,0,2}),{0,0,0,1}))
-- Composition order pinned: Bend 90 on identity about Z; Twist 90 about X.
assert(near(E.compose({0,0,0,1},90,0,0),E.quat_axis_angle(0,0,1,90)))
assert(near(E.compose({0,0,0,1},0,0,90),E.quat_axis_angle(1,0,0,90)))
local b=E.quat_axis_angle(0,1,0,30)
assert(near(E.compose(b,45,0,0),E.quat_multiply(b,E.quat_axis_angle(0,0,1,45))),'Delta on the bone side')
assert(E.compose({0,0,0,1},0,0,0)[4]==1 and E.BONE_FRAME_SIDE=='right')
-- Editor lifecycle.
local function node(x)return{p={x,0,0},q={0,0,0,1},s={1,1,1},pose={1,0,0,0,1,0,0,0,1,x,0,0}}end
local frame={nodes={}};for i=8,92 do frame.nodes[i]=node(i)end
local e=E.new();assert(not e.has_base()and not e.dirty())
e.rebase(frame,'Salute');assert(e.has_base()and e.base_label()=='Salute'and not e.edited())
assert(e.select(70)and e.selected()==70)
assert(e.set_angle(70,'bend',45)and e.dirty()and e.edited())
assert(select(2,e.set_angle(70,'bend',0/0))=='Angle must be a number')
assert(select(2,e.set_angle(5,'bend',1))=='Unknown bone')
e.set_angle(70,'twist',400);local _,_,t=e.angles(70);assert(t==180,'Clamped')
local out=e.compose_frame();assert(out.full_body==true and not e.dirty())
assert(out.nodes[8]==frame.nodes[8]and out.nodes[47]==frame.nodes[47],'Unchanged bones pass the base table through')
assert(out.nodes[70]~=frame.nodes[70]and out.nodes[70].pose==nil and near(out.nodes[70].q,E.compose({0,0,0,1},45,0,180)))
assert(out.nodes[70].p[1]==70 and out.nodes[70].s[1]==1,'Position and scale untouched')
e.reset_bone(70);assert(not e.edited()and e.dirty());e.set_angle(48,'swing',10);e.reset_all();assert(not e.edited())
e.set_angle(48,'swing',10);e.rebase(frame,'Wave');assert(not e.edited()and e.base_label()=='Wave','Rebase clears angles')
e.clear();assert(not e.has_base()and e.selected()==70,'Clear keeps the selection')
assert(e.status('Right arm','Elbow'):find('Right arm / Elbow',1,true))
e.set_angle(70,'bend',5);e.adopt(frame,'Snapshot');assert(e.has_base()and e.edited()and e.base_label()=='Snapshot','Adopt keeps angles')
e.compose_frame();assert(not e.dirty());e.touch();assert(e.dirty(),'Touch re-arms an apply')
assert(e.compose_frame().label=='Snapshot edits','Composed frames carry their label')
e.touch();assert(e.compose_frame(true).label=='Snapshot edits'and e.dirty(),'A copy for saving keeps the dirty flag')
e.rebase(frame,'Snapshot edits');e.set_angle(70,'bend',5);assert(e.compose_frame().label=='Snapshot edits','No double edits suffix')
assert(e.status('Right arm','Elbow'):find('^Snapshot edits  |'),e.status('Right arm','Elbow'))
-- Offsets: a bone can be moved in its parent's frame; composed p = base p + offset.
do
 local e2=E.new();e2.rebase(frame,'Salute')
 assert(e2.nudge_offset(70,.1,0,-.02)and e2.edited()and e2.dirty())
 local ox,oy,oz=e2.offset(70);assert(ox==.1 and oy==0 and oz==-.02)
 local out=e2.compose_frame();assert(out.nodes[70].p[1]==70.1 and out.nodes[70].p[3]==-.02 and out.nodes[70].q[4]==1,'Offset moves p and leaves q')
 assert(out.nodes[8]==frame.nodes[8],'Other bones pass through')
 e2.nudge_offset(70,5,0,0);ox=e2.offset(70);assert(ox==1,'Offsets clamp to one metre')
 assert(select(2,e2.nudge_offset(70,0/0,0,0))=='Offset must be a number')
 assert(e2.status('Right arm','Elbow'):find('Move 100/0/-2 cm',1,true),e2.status('Right arm','Elbow'))
 e2.reset_bone(70);assert(not e2.edited());local a,b,c=e2.offset(70);assert(a==0 and b==0 and c==0,'Reset bone clears the offset')
 e2.nudge_offset(48,0,.3,0);e2.reset_all();assert(not e2.edited())
end
-- Bend/Swing/Twist back from a delta: the inverse of compose, exact away from Swing +-90.
do
 local function wrap(a)return(a+180)%360-180 end
 for _,angles in ipairs({{30,0,0},{0,40,0},{0,0,50},{30,40,50},{-120,60,-170},{170,-85,20},{45,89.9,-45}})do
  local q=E.compose({0,0,0,1},angles[1],angles[2],angles[3]);local b,s,t=E.decompose(q)
  assert(math.abs(wrap(b-angles[1]))<1e-6 and math.abs(s-angles[2])<1e-6 and math.abs(wrap(t-angles[3]))<1e-6,'Roundtrip '..table.concat(angles,'/')..' gave '..b..'/'..s..'/'..t)
 end
 -- At the gimbal (Swing +-90) the rotation is reproduced with Twist folded into Bend.
 for _,angles in ipairs({{30,90,20},{-40,-90,70}})do
  local q=E.compose({0,0,0,1},angles[1],angles[2],angles[3]);local b,s,t=E.decompose(q);local back=E.compose({0,0,0,1},b,s,t)
  assert(math.abs(back[1]*q[1]+back[2]*q[2]+back[3]*q[3]+back[4]*q[4])>1-1e-9 and t==0,'Gimbal case reproduces the rotation')
 end
end
-- Aim: angles for a parent bone so that its child points at a world target (the bone keeps its length).
do
 local I={0,0,0,1}
 local b,s,t=E.aim(I,I,I,{0,0,0},{1,0,0},{0,2,0})
 assert(math.abs(b-90)<1e-9 and math.abs(s)<1e-9 and math.abs(t)<1e-9,'Child on +X aimed at +Y is Bend 90')
 b,s,t=E.aim(I,I,I,{0,0,0},{1,0,0},{0,0,3});assert(math.abs(s+90)<1e-9,'Aimed at +Z is Swing -90')
 -- General case: rotated grandparent, edited parent, base off identity. The composed parent
 -- rotation must send the bone (in the parent's frame) onto the target direction, length kept.
 local grand=E.quat_axis_angle(1,2,3,70);local base=E.quat_axis_angle(0,1,0,25)
 local parent_world=E.quat_multiply(grand,E.compose(base,15,-20,35))
 local parent_p={1,2,3};local bone={0,.4,0}
 local child_p;do local w=E.rotate(parent_world,bone);child_p={parent_p[1]+w[1],parent_p[2]+w[2],parent_p[3]+w[3]}end
 local target={1.3,2.2,2.6}
 b,s,t=E.aim(base,grand,parent_world,parent_p,child_p,target)
 local w=E.rotate(E.quat_multiply(grand,E.compose(base,b,s,t)),bone)
 local d={target[1]-parent_p[1],target[2]-parent_p[2],target[3]-parent_p[3]};local n=math.sqrt(d[1]^2+d[2]^2+d[3]^2);local l=math.sqrt(w[1]^2+w[2]^2+w[3]^2)
 for i=1,3 do assert(math.abs(w[i]/l-d[i]/n)<1e-9,'Child direction follows the target')end
 assert(math.abs(l-.4)<1e-9,'Bone length kept')
 -- Degenerate inputs are refused, never NaN; an antiparallel target is a finite half turn.
 assert(select(2,E.aim(I,I,I,{0,0,0},{0,0,0},{1,0,0}))=='Bone too short')
 assert(select(2,E.aim(I,I,I,{0,0,0},{1,0,0},{0,0,0}))=='Target at the joint')
 b,s,t=E.aim(I,I,I,{0,0,0},{1,0,0},{-1,0,0});w=E.rotate(E.compose(I,b,s,t),{1,0,0});assert(math.abs(w[1]+1)<1e-9,'Half turn')
end
-- All-Bones mode finds a clicked bone's group: the first group that lists the node.
do
 local g,b=E.locate(70);assert(E.GROUPS[g].id=='right_arm'and E.GROUPS[g].bones[b].label=='Elbow')
 g,b=E.locate(18);assert(E.GROUPS[g].id=='left_leg'and E.GROUPS[g].bones[b].node==18)
 g,b=E.locate(38);assert(E.GROUPS[g].id=='cape'and b==4)
 for gi,group in ipairs(E.GROUPS)do for bi,bone in ipairs(group.bones)do
  local g2,b2=E.locate(bone.node);assert(g2 and E.GROUPS[g2].bones[b2].node==bone.node and(g2<gi or g2==gi and b2<=bi),'Every listed bone is found')
 end end
 assert(E.locate(1)==nil and E.locate(nil)==nil and E.locate('70')==nil,'A node no group lists is not found')
end
-- Natural limits. A bone's rotation is read as a twist about its own X and a swing about Y and
-- Z from a rest rotation; a limit is a range for each, in degrees.
do
 local abs=math.abs
 local function same(a,b)local d=abs(a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]);return abs(d-1)<1e-9 end
 for _,c in ipairs({{0,0,0},{40,0,0},{0,30,0},{0,0,-50},{25,-35,60},{-120,80,-20}})do
  local t,y,z=E.swing_twist(E.from_swing_twist(c[1],c[2],c[3]))
  assert(abs(t-c[1])<1e-9 and abs(y-c[2])<1e-9 and abs(z-c[3])<1e-9,'Swing and twist round trip')
 end
 assert(same(E.from_swing_twist(90,0,0),E.quat_axis_angle(1,0,0,90)),'Twist turns about X')
 assert(same(E.from_swing_twist(0,90,0),E.quat_axis_angle(0,1,0,90))and same(E.from_swing_twist(0,0,90),E.quat_axis_angle(0,0,1,90)),'Swing turns about Y and Z')
 local t,y,z=E.swing_twist({0,0,0,-1});assert(t==0 and y==0 and z==0,'Either sign of a quaternion is the same rotation')
 -- A knee: bends about Z one way only.
 local knee={r={0,0,0,1},t={-5,5},y={-5,5},z={-140,5}}
 local function bend(d)return E.quat_axis_angle(0,0,1,d)end
 local q,changed=E.limit_rotation(knee,bend(-90));assert(not changed and same(q,bend(-90)),'A natural bend passes')
 q,changed=E.limit_rotation(knee,bend(-170));assert(changed and same(q,bend(-140)),'Too far stops at the range')
 q,changed=E.limit_rotation(knee,bend(40));assert(changed and same(q,bend(5)),'Backwards stops just past straight')
 q,changed=E.limit_rotation(knee,E.quat_axis_angle(0,1,0,30));assert(changed and same(q,E.quat_axis_angle(0,1,0,5)),'Sideways stops')
 q,changed=E.limit_rotation(knee,E.quat_axis_angle(1,0,0,-60));assert(changed and same(q,E.quat_axis_angle(1,0,0,-5)),'Twist stops')
 q,changed=E.limit_rotation(knee,bend(5));assert(not changed,'The limit itself is inside')
 q,changed=E.limit_rotation(knee,bend(-140));assert(not changed)
 -- A rest rotation: the ranges are measured from it.
 local rest=E.quat_axis_angle(0,1,0,90);local turned={r=rest,t={-5,5},y={-5,5},z={-140,5}}
 q,changed=E.limit_rotation(turned,E.quat_multiply(rest,bend(-90)));assert(not changed)
 q,changed=E.limit_rotation(turned,E.quat_multiply(rest,bend(30)));assert(changed and same(q,E.quat_multiply(rest,bend(5))))
 q,changed=E.limit_rotation(turned,bend(-90));assert(changed,'The same turn from another rest is outside')
 -- A bone already outside its range stays; it only cannot move further out.
 q,changed=E.limit_rotation(knee,bend(50),bend(60));assert(not changed,'Moving back in is free')
 q,changed=E.limit_rotation(knee,bend(80),bend(60));assert(changed and same(q,bend(60)),'No further out than it was')
 q,changed=E.limit_rotation(knee,bend(-20),bend(60));assert(not changed)
 q,changed=E.limit_rotation(knee,E.quat_multiply(bend(60),E.quat_axis_angle(1,0,0,30)),bend(60));assert(changed,'Outside on one axis frees no other')
end
do -- the editor holds what the limits allow, and its angles say where the bone stopped
 local abs=math.abs
 local nodes={};for i=8,92 do nodes[i]={p={0,0,0},q={0,0,0,1},s={1,1,1}}end
 local knee={r={0,0,0,1},t={-5,5},y={-5,5},z={-140,5}}
 local e=E.new();e.rebase({nodes=nodes},'Test');assert(not e.limited())
 e.set_limits({[13]=knee});assert(e.limited())
 local ok,stopped=e.set_angle(13,'bend',-90);assert(ok and not stopped);local b,s,t=e.angles(13);assert(b==-90 and s==0 and t==0)
 ok,stopped=e.set_angle(13,'bend',60);assert(ok and stopped==true,'The editor says when a bone stopped')
 b,s,t=e.angles(13);assert(abs(b-5)<1e-6 and abs(s)<1e-6 and abs(t)<1e-6,'Bend stopped at 5, got '..b)
 ok,stopped=e.set_angle(13,'swing',40);assert(ok and stopped);b,s,t=e.angles(13);assert(abs(s-5)<.3,'Swing stopped near 5, got '..s)
 ok,stopped=e.set_angle(70,'bend',170);assert(ok and not stopped and e.angles(70)==170,'A bone without limits is free')
 local frame=e.compose_frame();local got=E.limit_rotation(knee,frame.nodes[13].q);assert(select(2,E.limit_rotation(knee,frame.nodes[13].q))==false,'The composed pose is inside the limits')
 -- All three angles at once: one check, not three.
 e.reset_bone(13);ok,stopped=e.set_angles(13,-100,0,0);assert(ok and not stopped and e.angles(13)==-100)
 ok,stopped=e.set_angles(13,-100,1,-1);assert(ok and not stopped);b,s,t=e.angles(13);assert(b==-100 and s==1 and t==-1,'Inside the ranges the angles are kept exactly')
 assert(e.set_angles(13,0/0,0,0)==false and e.set_angles(999,0,0,0)==false,'Bad input is refused')
 -- Off: free again. On again with a bone outside: it stays, and only cannot go further.
 e.set_limits(nil);ok,stopped=e.set_angles(13,60,0,0);assert(ok and not stopped and e.angles(13)==60)
 e.set_limits({[13]=knee});assert(e.angles(13)==60,'Switching limits on moves nothing')
 ok,stopped=e.set_angle(13,'bend',70);assert(stopped and abs(e.angles(13)-60)<1e-6,'No further out')
 ok,stopped=e.set_angle(13,'bend',30);assert(not stopped and e.angles(13)==30,'Back in is free')
 ok,stopped=e.set_angle(13,'bend',60);assert(stopped and abs(e.angles(13)-30)<1e-6,'...and the way out closes behind it')
 -- A base pose outside the range: no jump on the first touch.
 local bent={};for i=8,92 do bent[i]=nodes[i]end;bent[13]={p={0,0,0},q=E.quat_axis_angle(0,0,1,50),s={1,1,1}}
 local e2=E.new();e2.set_limits({[13]=knee});e2.rebase({nodes=bent},'Bent')
 ok,stopped=e2.set_angle(13,'bend',10);assert(stopped and abs(e2.angles(13))<1e-6,'Cannot bend further backwards')
 ok,stopped=e2.set_angle(13,'bend',-30);assert(not stopped and e2.angles(13)==-30,'Can straighten')
 -- Angles set before a base exists are limited when the base arrives.
 local e3=E.new();e3.set_limits({[13]=knee});ok,stopped=e3.set_angle(13,'bend',60);assert(ok and not stopped and e3.angles(13)==60)
 e3.adopt({nodes=nodes},'Snapshot');assert(abs(e3.angles(13)-5)<1e-6,'Adopting a base applies the limits')
end
print('Pose editor: groups, quaternion maths, pinned composition, pass-through and lifecycle passed')

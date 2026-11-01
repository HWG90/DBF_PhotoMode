-- Pure pose editor contracts in actual Lua 5.1: bone groups, quaternion maths, composed frames.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local E=dofile('freecam/pose_editor.lua');local bank=dofile('freecam/assets/steam_subject_poses.lua')
-- Group coverage: every node 8..92 exactly once, names match the rig.
local seen={};for _,g in ipairs(E.GROUPS)do for _,b in ipairs(g.bones)do
 assert(not seen[b.node],'Node listed twice: '..b.node);seen[b.node]=true
 assert(bank.rig.nodes[b.node].name==E.rig_names[b.node],'Rig name mismatch at '..b.node)end end
for i=8,92 do assert(seen[i],'Node not grouped: '..i)end
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
print('Pose editor: groups, quaternion maths, pinned composition, pass-through and lifecycle passed')

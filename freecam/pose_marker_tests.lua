-- Bone marker contracts in actual Lua 5.1: numeric projection only, no engine calls.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local G=dofile('freecam/photo_light_gizmos.lua');local Marker=dofile('freecam/pose_marker.lua')
local frame={position={0,0,0},forward={0,1,0},right={1,0,0},up={0,0,1}}
local m=Marker.new(G.project)
assert(not m.visible())
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,5,0},parent={0,5,-.3}}},70,true);assert(m.visible(),'A bone in front of the camera is visible')
local cmds={};m.draw(cmds)
local ring,dot;for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then ring=c elseif c.ui_role=='bone_parent'then dot=c end end
assert(ring and dot,'Ring at the bone, dot at the parent')
assert(math.abs(ring.x+ring.w/2-960)<1 and math.abs(ring.y+ring.h/2-540)<1,'Ring is centred on the projected bone')
assert(dot.y+dot.h/2<ring.y+ring.h/2 and dot.w<ring.w,'Parent dot sits toward the parent and is smaller')
assert(ring.type=='rect'and ring.layer==330)
m.update(nil,nil,nil,1920,1080,nil,nil,false);assert(not m.visible());cmds={};m.draw(cmds);assert(#cmds==0,'Hidden marker draws nothing')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,-5,0},parent={0,-5,-.3}}},70,true);assert(not m.visible(),'Behind the camera is not visible')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,5,0}}},70,true);assert(m.visible());cmds={};m.draw(cmds)
local parents=0;for _,c in ipairs(cmds)do if c.ui_role=='bone_parent'then parents=parents+1 end end;assert(parents==0,'No parent, no dot')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0/0,5,0}}},70,true);assert(not m.visible(),'A non-finite position hides the marker')
-- Several rings (one per bone in the group): click selects, the selected ring is white,
-- the others yellow, and gestures follow Gadget Kit's First Person editor:
-- L drag moves in the screen plane, R drag bends/swings, M drag twists, wheel is depth, Shift fine.
do
 local values={bone_bend=10,bone_swing=0,bone_twist=0};local preview;local commits,cancels=0,0;local selected_calls={};local moves={}
 local d=Marker.new(G.project,{get=function(id)return preview and preview[id]~=nil and preview[id]or values[id]end,
  adjust=function(v,commit)if v then preview=preview or{};for k,n in pairs(v)do preview[k]=n end else if commit and preview then commits=commits+1;for k,n in pairs(preview)do values[k]=n end elseif not commit then cancels=cancels+1 end;preview=nil end;return true end,
  select=function(node)selected_calls[#selected_calls+1]=node;return true end,
  move=function(delta)moves[#moves+1]=delta;return true end})
 local keys={};local function down(k)return keys[k]or false end
 local items={{node=68,position={-1,5,0}},{node=70,position={0,5,0},parent={0,5,-.3}},{node=72,position={1,5,0}}}
 d.update(frame,math.rad(60),1920,1080,items,70,true);assert(d.visible())
 local cmds={};d.draw(cmds);local rings={};local dots=0
 for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then rings[#rings+1]=c elseif c.ui_role=='bone_parent'then dots=dots+1 end end
 assert(#rings==3 and dots==1,'One ring per bone, a parent dot only for the selected')
 local white,yellow=0,0;for _,r in ipairs(rings)do if r.c[1]==255 and r.c[2]==255 and r.c[3]==255 then white=white+1;assert(r.bone==70)else yellow=yellow+1 end end
 assert(white==1 and yellow==2,'Selected white, others yellow')
 local x72;for _,r in ipairs(rings)do if r.bone==72 then x72=r.x+r.w/2 end end
 assert(d.tick({x=x72,y=540,click=true},down,nil,false)==true and selected_calls[1]==72,'Click on an unselected ring selects it')
 d.tick({x=x72,y=540,click=false},down,nil,false)
 -- L drag on the selected ring: move in the screen plane, metres per screen width.
 assert(d.tick({x=960,y=540,click=true},down,nil,false)==true and #selected_calls==1,'Press on the selected ring starts a move, no reselect')
 d.tick({x=960+192,y=540,click=true},down,nil,false)
 assert(#moves==1 and math.abs(moves[1][1]-.1)<1e-9 and math.abs(moves[1][2])<1e-9 and math.abs(moves[1][3])<1e-9,'192 px of 1920 is 0.1 m along camera right')
 d.tick({x=960+192,y=540+108,click=true},down,nil,false)
 assert(#moves==2 and math.abs(moves[2][3]+.06)<1e-9,'108 px of 1080 down is 0.06 m down along camera up')
 d.tick({x=960+192,y=540+108,click=false},down,nil,false)
 -- Wheel: depth along camera forward, 1 cm per notch.
 assert(d.tick({x=960,y=540,click=false,wheel=120},down,nil,false)==true and math.abs(moves[3][2]-.01)<1e-9,'Wheel moves 1 cm along forward')
 -- R drag: Bend with x (120 degrees per width), Swing with y (90 per height); release commits once.
 keys[2]=true;assert(d.tick({x=960,y=540,click=false},down,nil,false)==true)
 d.tick({x=960+192,y=540+108,click=false},down,nil,false)
 assert(math.abs(preview.bone_bend-(10-12))<1e-9 and math.abs(preview.bone_swing-(-9))<1e-9,'R drag maps like yaw/pitch')
 keys[2]=false;d.tick({x=960+192,y=540+108,click=false},down,nil,false);assert(commits==1 and values.bone_bend==-2)
 -- M drag: Twist with x (180 degrees per width).
 keys[4]=true;assert(d.tick({x=960,y=540,click=false},down,nil,false)==true);d.tick({x=960+192,y=540,click=false},down,nil,false)
 assert(math.abs(preview.bone_twist-18)<1e-9,'M drag twists');keys[4]=false;d.tick({x=960+192,y=540,click=false},down,nil,false);assert(commits==2)
 -- Shift: fine.
 keys[16]=true;keys[2]=true;d.tick({x=960,y=540,click=false},down,nil,false);d.tick({x=960+192,y=540,click=false},down,nil,false)
 assert(math.abs(preview.bone_bend-(-2-1.2))<1e-9,'Shift is a tenth');keys[2]=false;keys[16]=false;d.tick({x=960+192,y=540,click=false},down,nil,false)
 assert(d.tick({x=400,y=200,click=true},down,nil,false)==false,'Away from every ring: not captured')
 d.tick({x=400,y=200,click=false},down,nil,false)
 assert(d.tick({x=960,y=540,click=true},down,nil,false)==true);d.cancel();assert(cancels==1 and preview==nil)
 d.update(frame,math.rad(60),1920,1080,items,70,true)
 assert(d.tick({x=960,y=540,click=true},down,function()return true end,false)==false,'A blocked pointer never grabs a ring')
 assert(d.tick({x=960,y=540,click=true},down,nil,true)==false,'A modal menu never grabs a ring')
 d.update(nil,nil,nil,1920,1080,nil,nil,false);assert(not d.visible());cmds={};d.draw(cmds);assert(#cmds==0)
end
print('Pose marker: projection, rings per bone, select, move/rotate/twist/depth gestures, fine, blocked and hidden cases passed')

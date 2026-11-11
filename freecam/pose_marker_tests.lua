-- Bone marker contracts in actual Lua 5.1: numeric projection only, no engine calls.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local G=dofile('freecam/photo_light_gizmos.lua');local Marker=dofile('freecam/pose_marker.lua')
local frame={position={0,0,0},forward={0,1,0},right={1,0,0},up={0,0,1}}
local m=Marker.new(G.project)
assert(not m.visible())
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,5,0},parent={0,5,-.3}}},70,true);assert(m.visible(),'A bone in front of the camera is visible')
local cmds={};m.draw(cmds)
local ring,dot,lines;lines={};for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then ring=c elseif c.ui_role=='bone_parent'then dot=c elseif c.ui_role=='bone_line'then lines[#lines+1]=c end end
assert(ring and dot,'Ring at the bone, dot at the parent')
assert(#lines==2 and lines[1].type=='triangle'and #lines[1].points==6 and lines[1].layer<ring.layer,'The bone is a line of two triangles from the parent, under the rings')
for _,l in ipairs(lines)do for i=1,6,2 do assert(math.abs(l.points[i]-960)<3,'Line stays on the bone column')end;assert(math.min(l.points[2],l.points[4],l.points[6])<540-2 and math.max(l.points[2],l.points[4],l.points[6])>=540-2,'Line spans parent to ring')end
assert(math.abs(ring.x+ring.w/2-960)<1 and math.abs(ring.y+ring.h/2-540)<1,'Ring is centred on the projected bone')
assert(dot.y+dot.h/2<ring.y+ring.h/2 and dot.w<ring.w,'Parent dot sits toward the parent and is smaller')
assert(ring.type=='rect'and ring.layer==330)
m.update(nil,nil,nil,1920,1080,nil,nil,false);assert(not m.visible());cmds={};m.draw(cmds);assert(#cmds==0,'Hidden marker draws nothing')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,-5,0},parent={0,-5,-.3}}},70,true);assert(not m.visible(),'Behind the camera is not visible')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0,5,0}}},70,true);assert(m.visible());cmds={};m.draw(cmds)
local parents=0;for _,c in ipairs(cmds)do if c.ui_role=='bone_parent'or c.ui_role=='bone_line'then parents=parents+1 end end;assert(parents==0,'No parent, no dot and no line')
m.update(frame,math.rad(60),1920,1080,{{node=70,position={0/0,5,0}}},70,true);assert(not m.visible(),'A non-finite position hides the marker')
-- Several rings (one per bone in the group): click selects, the selected ring is white,
-- the others yellow, and gestures follow Gadget Kit's First Person editor:
-- L drag aims the bone at the pointer (its parent rotates), R drag bends/swings, M drag twists, wheel is depth, Shift fine.
do
 local values={bone_bend=10,bone_swing=0,bone_twist=0};local preview;local commits,cancels=0,0;local selected_calls={};local aims={}
 local d=Marker.new(G.project,{get=function(id)return preview and preview[id]~=nil and preview[id]or values[id]end,
  adjust=function(v,commit)if v then preview=preview or{};for k,n in pairs(v)do preview[k]=n end else if commit and preview then commits=commits+1;for k,n in pairs(preview)do values[k]=n end elseif not commit then cancels=cancels+1 end;preview=nil end;return true end,
  select=function(node)selected_calls[#selected_calls+1]=node;return true end,
  aim=function(node,point)aims[#aims+1]={node=node,point=point};return true end})
 local keys={};local function down(k)return keys[k]or false end
 local items={{node=68,position={-1,5,0},parent={-1,5,-.3}},{node=70,position={0,5,0},parent={-1,5,0}},{node=72,position={1,5,0},parent={0,5,0}}}
 d.update(frame,math.rad(60),1920,1080,items,70,true);assert(d.visible())
 local cmds={};d.draw(cmds);local rings={};local dots,lines=0,0
 for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then rings[#rings+1]=c elseif c.ui_role=='bone_parent'then dots=dots+1 elseif c.ui_role=='bone_line'then lines=lines+1 end end
 assert(#rings==3 and dots==1 and lines==6,'One ring and one line per bone, a parent dot only for the selected')
 local white,yellow=0,0;for _,r in ipairs(rings)do if r.c[1]==255 and r.c[2]==255 and r.c[3]==255 then white=white+1;assert(r.bone==70)else yellow=yellow+1 end end
 assert(white==1 and yellow==2,'Selected white, others yellow')
 local x72;for _,r in ipairs(rings)do if r.bone==72 then x72=r.x+r.w/2 end end
 assert(d.tick({x=x72,y=540,click=true},down,nil,false)==true and selected_calls[1]==72,'Click on an unselected ring selects it')
 d.tick({x=x72,y=540,click=false},down,nil,false)
 -- L drag on the selected ring: aim the bone at the pointer, unprojected at the ring's depth (menu space grows upward).
 local function near3(a,b)return math.abs(a[1]-b[1])<1e-9 and math.abs(a[2]-b[2])<1e-9 and math.abs(a[3]-b[3])<1e-9 end
 assert(d.tick({x=960,y=540,click=true},down,nil,false)==true and #selected_calls==1,'Press on the selected ring starts an aim, no reselect')
 d.tick({x=960+192,y=540,click=true},down,nil,false)
 assert(#aims==1 and aims[1].node==70 and near3(aims[1].point,G.target(frame,math.rad(60),1920,1080,1152/1920,1-540/1080,5)),'192 px right aims at the pointer, 5 m deep, along camera right')
 d.tick({x=960+192,y=540+108,click=true},down,nil,false)
 assert(#aims==2 and near3(aims[2].point,G.target(frame,math.rad(60),1920,1080,1152/1920,1-648/1080,5))and aims[2].point[3]>.5,'108 px up the screen aims up along camera up')
 d.tick({x=960+192,y=540+108,click=false},down,nil,false)
 -- Wheel: push the bone deeper along camera forward, 1 cm per notch, still an aim.
 assert(d.tick({x=960,y=540,click=false,wheel=120},down,nil,false)==true and #aims==3 and aims[3].node==70 and near3(aims[3].point,{0,5.01,0}),'Wheel aims 1 cm deeper')
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
print('Pose marker: projection, rings and bone lines, select, aim/rotate/twist/depth gestures, fine, blocked and hidden cases passed')
-- All-Bones overview: every bone of every group gets a small ring, nothing is selected and
-- nothing drags. The group under the pointer lights up; a left click on a ring selects it
-- (the runtime opens its group). In a group, a left click away from the rings asks for the
-- overview again.
do
 local picked,away={},0;local all=true
 local o=Marker.new(G.project,{select=function(node)picked[#picked+1]=node;return true end,away=function()away=away+1 end,
  get=function()return 0 end,adjust=function(v)assert(not(v and all),'No drag in the overview')end,aim=function()assert(not all,'No aim in the overview');return true end})
 local keys={};local function down(k)return keys[k]or false end
 local items={{node=68,group=3,position={-1,5,0},parent={-1,5,-.3}},{node=70,group=3,position={0,5,0},parent={-1,5,0}},{node=17,group=4,position={1,5,0},parent={0,5,0}}}
 local function show(overview,selected)all=overview;o.update(frame,math.rad(60),1920,1080,items,selected,true,overview)end
 local function rings()
  local cmds={};o.draw(cmds);local out,dots={},0
  for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then out[c.bone]=c elseif c.ui_role=='bone_parent'then dots=dots+1 end end
  return out,dots
 end
 local function white(c)return c.c[1]==255 and c.c[2]==255 and c.c[3]==255 end
 show(true,nil);assert(o.visible(),'The overview needs no selected bone')
 local r,dots=rings();assert(r[68]and r[70]and r[17]and dots==0,'One ring per bone, no parent dot')
 for _,ring in pairs(r)do assert(ring.w<18 and not white(ring),'Overview rings are smaller and yellow until hovered')end
 local x70,x17=r[70].x+r[70].w/2,r[17].x+r[17].w/2
 -- Hover: the whole group under the pointer turns white; it survives the next update.
 assert(o.tick({x=x70,y=540,click=false},down,nil,false)==false,'Hovering captures nothing')
 show(true,nil);r=rings();assert(white(r[68])and white(r[70])and not white(r[17]),'The hovered bone lights its whole group')
 o.tick({x=x17,y=540,click=false},down,nil,false);show(true,nil);r=rings();assert(white(r[17])and not white(r[70]),'Hover follows the pointer')
 o.tick({x=x17,y=540,click=false},down,function()return true end,false);show(true,nil);r=rings();assert(not white(r[17]),'No hover under the menu')
 o.tick({x=400,y=200,click=false},down,nil,false);show(true,nil);r=rings();assert(not white(r[17])and not white(r[70]),'No hover away from the rings')
 -- No gestures: right and middle presses and the wheel do nothing on an overview ring.
 keys[2]=true;assert(o.tick({x=x70,y=540,click=false},down,nil,false)==false);o.tick({x=x70+50,y=560,click=false},down,nil,false);keys[2]=false
 o.tick({x=x70,y=540,click=false},down,nil,false)
 keys[4]=true;assert(o.tick({x=x70,y=540,click=false},down,nil,false)==false);keys[4]=false;o.tick({x=x70,y=540,click=false},down,nil,false)
 assert(o.tick({x=x70,y=540,click=false,wheel=120},down,nil,false)==false and not o.active(),'No wheel, no gesture')
 -- Left click: select, once per press, and never start a drag.
 assert(o.tick({x=x70,y=540,click=true},down,nil,false)==true and #picked==1 and picked[1]==70,'A click on an overview ring selects that bone')
 assert(o.tick({x=x70+40,y=540,click=true},down,nil,false)==false and #picked==1 and not o.active(),'Holding selects once and drags nothing')
 o.tick({x=x70,y=540,click=false},down,nil,false)
 assert(o.tick({x=400,y=200,click=true},down,nil,false)==false and away==0,'All bones are already shown: away asks for nothing')
 o.tick({x=400,y=200,click=false},down,nil,false)
 -- In a group: the old rings, and a left click away from them asks for the overview once.
 show(false,70);r,dots=rings();assert(r[70].w>=18 and white(r[70])and not white(r[68])and dots==1,'A group shows full rings and its selected bone')
 assert(o.tick({x=400,y=200,click=true},down,nil,false)==false and away==1,'A left click away from the rings asks for all bones')
 o.tick({x=410,y=200,click=true},down,nil,false);assert(away==1,'Once per press')
 o.tick({x=400,y=200,click=false},down,nil,false)
 assert(o.tick({x=400,y=200,click=true},down,function()return true end,false)==false and away==1,'A click on the menu is not away')
 o.tick({x=400,y=200,click=false},down,nil,false)
 keys[2]=true;o.tick({x=400,y=200,click=false},down,nil,false);keys[2]=false;o.tick({x=400,y=200,click=false},down,nil,false);assert(away==1,'Only the left button')
 assert(o.tick({x=400,y=200,click=true},down,nil,true)==false and away==1,'A modal menu is not away')
 o.tick({x=400,y=200,click=false},down,nil,false)
 -- Releasing a drag away from the rings is not a click away.
 show(false,70);assert(o.tick({x=x70,y=540,click=true},down,nil,false)==true)
 o.tick({x=400,y=200,click=true},down,nil,false);o.tick({x=400,y=200,click=false},down,nil,false);assert(away==1,'A drag that ends off the rings is not away')
end
print('Pose marker overview: small rings, group hover, click selects, no gestures; click away in a group asks for all bones passed')

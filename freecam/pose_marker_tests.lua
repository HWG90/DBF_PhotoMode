-- Bone marker contracts in actual Lua 5.1: numeric projection only, no engine calls.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local G=dofile('freecam/photo_light_gizmos.lua');local Marker=dofile('freecam/pose_marker.lua')
local frame={position={0,0,0},forward={0,1,0},right={1,0,0},up={0,0,1}}
local m=Marker.new(G.project)
assert(not m.visible())
m.update(frame,math.rad(60),1920,1080,{0,5,0},{0,5,-.3},true);assert(m.visible(),'A bone in front of the camera is visible')
local cmds={};m.draw(cmds)
local ring,dot;for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then ring=c elseif c.ui_role=='bone_parent'then dot=c end end
assert(ring and dot,'Ring at the bone, dot at the parent')
assert(math.abs(ring.x+ring.w/2-960)<1 and math.abs(ring.y+ring.h/2-540)<1,'Ring is centred on the projected bone')
assert(dot.y+dot.h/2<ring.y+ring.h/2 and dot.w<ring.w,'Parent dot sits toward the parent and is smaller')
assert(ring.type=='rect'and ring.layer==330)
m.update(nil,nil,nil,1920,1080,nil,nil,false);assert(not m.visible());cmds={};m.draw(cmds);assert(#cmds==0,'Hidden marker draws nothing')
m.update(frame,math.rad(60),1920,1080,{0,-5,0},{0,-5,-.3},true);assert(not m.visible(),'Behind the camera is not visible')
m.update(frame,math.rad(60),1920,1080,{0,5,0},nil,true);assert(m.visible());cmds={};m.draw(cmds)
local parents=0;for _,c in ipairs(cmds)do if c.ui_role=='bone_parent'then parents=parents+1 end end;assert(parents==0,'No parent, no dot')
m.update(frame,math.rad(60),1920,1080,{0/0,5,0},nil,true);assert(not m.visible(),'A non-finite position hides the marker')
-- Dragging the ring: absolute values through get/adjust, like the menu's drag handle.
do
 local values={bone_bend=10,bone_swing=0,bone_twist=0};local preview;local commits,cancels=0,0
 local d=Marker.new(G.project,{get=function(id)return preview and preview[id]~=nil and preview[id]or values[id]end,
  adjust=function(v,commit)if v then preview=preview or{};for k,n in pairs(v)do preview[k]=n end else if commit and preview then commits=commits+1;for k,n in pairs(preview)do values[k]=n end elseif not commit then cancels=cancels+1 end;preview=nil end;return true end})
 local keys={};local function down(k)return keys[k]or false end
 d.update(frame,math.rad(60),1920,1080,{0,5,0},nil,true)
 assert(d.tick({x=960,y=540,click=true},down,nil,false)==true,'Press on the ring captures')
 assert(d.tick({x=970,y=560,click=true},down,nil,false)==true and preview.bone_bend==12 and preview.bone_swing==4,'0.2 degrees per pixel at 1080p')
 keys[16]=true;d.tick({x=980,y=560,click=true},down,nil,false);assert(math.abs(preview.bone_bend-12.2)<1e-9,'Shift is fine');keys[16]=false
 assert(d.tick({x=980,y=560,click=false},down,nil,false)==true and commits==1 and values.bone_bend>12,'Release commits once')
 assert(d.tick({x=960,y=540,click=false,wheel=120},down,nil,false)==true and values.bone_twist==1 and commits==2,'Wheel over the ring twists and commits')
 assert(d.tick({x=960,y=540,click=false,wheel=-120},down,nil,false)==true and values.bone_twist==0)
 assert(d.tick({x=1200,y=540,click=true},down,nil,false)==false,'Away from the ring: not captured')
 d.tick({x=1200,y=540,click=false},down,nil,false)
 assert(d.tick({x=960,y=540,click=true},down,nil,false)==true);d.cancel();assert(cancels==1 and preview==nil,'Cancel discards the preview')
 d.update(frame,math.rad(60),1920,1080,{0,5,0},nil,true)
 assert(d.tick({x=960,y=540,click=true},down,function()return true end,false)==false,'A blocked pointer never grabs the ring')
 assert(d.tick({x=960,y=540,click=true},down,nil,true)==false,'A modal menu never grabs the ring')
end
print('Pose marker: projection, ring and parent dot, hidden, behind-camera and non-finite cases passed')

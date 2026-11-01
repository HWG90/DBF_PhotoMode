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
print('Pose marker: projection, ring and parent dot, hidden, behind-camera and non-finite cases passed')

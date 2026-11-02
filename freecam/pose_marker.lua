-- Bone markers: one ring per bone of the selected group, projected with the light
-- gizmos' numeric camera projection, and a line from each ring to its parent (the
-- bone). The selected ring and its bone are white, the others yellow; a dot marks
-- the selected bone's parent. Click selects. Gestures follow Gadget Kit's First
-- Person editor: L drag aims the bone at the pointer (its parent joint turns, the
-- length is kept), R drag bends and swings the bone itself, M drag twists, the
-- wheel pushes the bone deeper, Shift is fine. Display and input only: hooks carry
-- every change (get/adjust as the menu drag handle, select, aim). Menu space grows
-- upward, like the projection.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vec(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
M.SELECTED={255,255,255};M.UNSELECTED={244,202,53}
M.DEPTH_PER_NOTCH=.01;M.LINE_HALF_WIDTH=1.5
M.BEND_PER_WIDTH=120;M.SWING_PER_HEIGHT=90;M.TWIST_PER_WIDTH=180
local RADIUS=9
local function clamp(v)return math.max(-180,math.min(180,math.floor(v*100+.5)/100))end
function M.new(project,hooks)
 assert(type(project)=='function','Marker projection required')
 hooks=hooks or{}
 local get,adjust,select_bone,aim=hooks.get,hooks.adjust,hooks.select,hooks.aim
 local self={};local rings,selected_ring,dot,cam={},nil,nil,nil;local visible=false;local width,height=1920,1080
 local gesture;local held={};local armed=true
 function self.update(frame,fov,w,h,items,selected,shown)
  rings,selected_ring,dot,cam={},nil,nil,nil;visible=false
  if finite(w)and w>0 then width=w end;if finite(h)and h>0 then height=h end
  if shown~=true or type(items)~='table'then return end
  for _,item in ipairs(items)do
   if type(item)=='table'and vec(item.position)then
    local x,y,depth=project(frame,fov,w,h,item.position)
    if x then
     local ring={node=item.node,x=x,y=y,depth=depth,position=item.position,selected=item.node==selected}
     rings[#rings+1]=ring
     if vec(item.parent)then local px,py=project(frame,fov,w,h,item.parent);if px then ring.px,ring.py=px,py end end
     if ring.selected then
      selected_ring=ring
      if ring.px then dot={x=ring.px,y=ring.py}end
     end
    end
   end
  end
  visible=#rings>0 and(selected==nil or selected_ring~=nil)
  if not visible then rings,selected_ring,dot={},nil,nil;return end
  cam={right=frame.right,up=frame.up,forward=frame.forward,position=frame.position,fov=fov}
 end
 -- The world point under a menu position at a given depth: the inverse of project().
 local function at_depth(x,y,depth)
  local scale=height/(2*depth*math.tan(cam.fov/2));local rx,uy=(x-width/2)/scale,(y-height/2)/scale
  local out={};for i=1,3 do out[i]=cam.position[i]+cam.forward[i]*depth+cam.right[i]*rx+cam.up[i]*uy end
  return out
 end
 function self.visible()return visible end
 function self.active()return gesture~=nil end
 local function finish(commit)
  if gesture and adjust then adjust(nil,commit)end
  gesture=nil
 end
 function self.cancel()finish(false);held={};armed=false end
 local function hit(input,block)
  if block and block(input.x,input.y)then return nil end
  local best
  for _,ring in ipairs(rings)do
   if math.abs(input.x-ring.x)<=RADIUS+3 and math.abs(input.y-ring.y)<=RADIUS+3 then
    if not best or(ring.selected and not best.selected)or(ring.selected==best.selected and ring.depth<best.depth)then best=ring end
   end
  end
  return best
 end
 local function value(id,delta)
  local current=get and get(id)or 0;if not finite(current)then current=0 end
  return clamp(current+delta),current
 end
 local function along(ax,k,bx,j)return{ax[1]*k+(bx and bx[1]*j or 0),ax[2]*k+(bx and bx[2]*j or 0),ax[3]*k+(bx and bx[3]*j or 0)}end
 function self.tick(input,down,block,modal)
  if not visible or modal or not input or not(finite(input.x)and finite(input.y))then self.cancel();return false end
  local left=input.click==true
  local right=input.right_click;if right==nil then right=down~=nil and down(2)==true end
  local middle=down~=nil and down(4)==true
  local pressed={left=left and not held.left,right=right and not held.right,middle=middle and not held.middle}
  held={left=left,right=right,middle=middle}
  local fine=down and down(16)and .1 or 1
  if not(left or right or middle)then
   local captured=gesture~=nil
   if gesture then finish(true)end
   armed=true
   if input.wheel and input.wheel~=0 and aim and selected_ring and hit(input,block)==selected_ring then
    aim(selected_ring.node,along(cam.forward,input.wheel/120*M.DEPTH_PER_NOTCH*fine,selected_ring.position,1));return true
   end
   return captured
  end
  if gesture then
   local dx,dy=input.x-gesture.x,input.y-gesture.y;gesture.x,gesture.y=input.x,input.y
   if dx==0 and dy==0 then return true end
   if gesture.kind=='aim'then
    if selected_ring then aim(selected_ring.node,at_depth(input.x,input.y,selected_ring.depth))end
   else
    local values={}
    if gesture.kind=='rotate'then
     local b,cb=value('bone_bend',-dx/width*M.BEND_PER_WIDTH*fine);if b~=cb then values.bone_bend=b end
     local s,cs=value('bone_swing',-dy/height*M.SWING_PER_HEIGHT*fine);if s~=cs then values.bone_swing=s end
    else
     local t,ct=value('bone_twist',dx/width*M.TWIST_PER_WIDTH*fine);if t~=ct then values.bone_twist=t end
    end
    if next(values)then adjust(values)end
   end
   return true
  end
  if not armed or not(pressed.left or pressed.right or pressed.middle)then return false end
  local ring=hit(input,block);if not ring then return false end
  if not ring.selected then if select_bone then select_bone(ring.node)end;return true end
  local kind=pressed.left and'aim'or pressed.right and'rotate'or'twist'
  if kind=='aim'and not aim then return true end
  if kind~='aim'and not(adjust and get)then return true end
  gesture={kind=kind,x=input.x,y=input.y};return true
 end
 function self.draw(commands)
  if not visible then return end
  local r=RADIUS
  local function rect(x,y,ww,hh,c,role,node)commands[#commands+1]={type='rect',x=x,y=y,w=ww,h=hh,c=c,a=1,layer=330,ui_role=role,bone=node}end
  -- The bone: a thin quad (two triangles) from the parent to the ring, under the rings.
  local function line(x1,y1,x2,y2,c,node)
   local dx,dy=x2-x1,y2-y1;local len=math.sqrt(dx*dx+dy*dy);if len<1 then return end
   local nx,ny=-dy/len*M.LINE_HALF_WIDTH,dx/len*M.LINE_HALF_WIDTH
   commands[#commands+1]={type='triangle',points={x1+nx,y1+ny,x1-nx,y1-ny,x2-nx,y2-ny},c=c,a=.9,layer=329,ui_role='bone_line',bone=node}
   commands[#commands+1]={type='triangle',points={x1+nx,y1+ny,x2-nx,y2-ny,x2+nx,y2+ny},c=c,a=.9,layer=329,ui_role='bone_line',bone=node}
  end
  for _,ring in ipairs(rings)do
   if ring.px then line(ring.px,ring.py,ring.x,ring.y,ring.selected and M.SELECTED or M.UNSELECTED,ring.node)end
  end
  for _,ring in ipairs(rings)do
   local colour=ring.selected and M.SELECTED or M.UNSELECTED
   rect(ring.x-r-2,ring.y-r-2,r*2+4,r*2+4,colour,'bone_marker',ring.node)
   rect(ring.x-r,ring.y-r,r*2,r*2,{16,18,20},'bone_marker_inner',ring.node)
   rect(ring.x-2,ring.y-2,4,4,colour,'bone_marker_centre',ring.node)
  end
  if dot then rect(dot.x-3,dot.y-3,6,6,{230,232,234},'bone_parent')end
 end
 return self
end
return M

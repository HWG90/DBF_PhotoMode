-- Bone marker: a ring at the selected bone and a dot at its parent, projected
-- with the light gizmos' numeric camera projection. Display only, no engine calls.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vec(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
-- Dragging the ring maps to absolute slider values through hooks.get/hooks.adjust,
-- the same contract as the menu's drag handle: adjust(values) previews,
-- adjust(nil,true) commits once on release, adjust(nil,false) discards.
M.DEGREES_PER_PIXEL=.2
local RADIUS=9
local function clamp(v)return math.max(-180,math.min(180,math.floor(v*100+.5)/100))end
function M.new(project,hooks)
 assert(type(project)=='function','Marker projection required')
 local self={};local ring,dot;local visible=false;local height=1080
 local drag;local held=false;local armed=true
 local get=hooks and hooks.get;local adjust=hooks and hooks.adjust
 function self.update(frame,fov,w,h,bone,parent,shown)
  ring,dot=nil,nil;visible=false;if finite(h)and h>0 then height=h end
  if shown~=true or not vec(bone)then return end
  local x,y,depth=project(frame,fov,w,h,bone)
  if not x then return end
  ring={x=x,y=y,depth=depth};visible=true
  if vec(parent)then local px,py=project(frame,fov,w,h,parent);if px then dot={x=px,y=py}end end
 end
 function self.visible()return visible end
 function self.active()return drag~=nil end
 function self.cancel()
  if drag and adjust then adjust(nil,false)end
  drag=nil;held=false;armed=false
 end
 local function over(input,block)
  if not ring then return false end
  if block and block(input.x,input.y)then return false end
  return math.abs(input.x-ring.x)<=RADIUS+3 and math.abs(input.y-ring.y)<=RADIUS+3
 end
 local function value(id,delta)
  local current=get and get(id)or 0;if not finite(current)then current=0 end
  return clamp(current+delta),current
 end
 function self.tick(input,down,block,modal)
  if not adjust or not get then return false end
  if not visible or modal or not input or not(finite(input.x)and finite(input.y))then self.cancel();return false end
  local click=input.click==true;local pressed=click and not held;held=click
  local fine=down and down(16)and .1 or 1
  if not click then
   local captured=drag~=nil
   if drag then drag=nil;adjust(nil,true)end
   armed=true
   if input.wheel and input.wheel~=0 and over(input,block)then
    local v,current=value('bone_twist',(input.wheel>0 and 1 or -1)*fine)
    if v~=current then adjust({bone_twist=v})end
    adjust(nil,true);return true
   end
   return captured
  end
  if not armed then return false end
  if drag then
   local dx,dy=input.x-drag.x,input.y-drag.y;drag.x,drag.y=input.x,input.y
   if dx~=0 or dy~=0 then
    local k=M.DEGREES_PER_PIXEL*fine*1080/height;local values={}
    local b,cb=value('bone_bend',dx*k);if b~=cb then values.bone_bend=b end
    local s,cs=value('bone_swing',dy*k);if s~=cs then values.bone_swing=s end
    if next(values)then adjust(values)end
   end
   return true
  end
  if not pressed or not over(input,block)then return false end
  drag={x=input.x,y=input.y};return true
 end
 function self.draw(commands)
  if not visible or not ring then return end
  local r=9
  local function rect(x,y,ww,hh,c,role)commands[#commands+1]={type='rect',x=x,y=y,w=ww,h=hh,c=c,a=1,layer=330,ui_role=role}end
  rect(ring.x-r-2,ring.y-r-2,r*2+4,r*2+4,{244,202,53},'bone_marker')
  rect(ring.x-r,ring.y-r,r*2,r*2,{16,18,20},'bone_marker_inner')
  rect(ring.x-2,ring.y-2,4,4,{244,202,53},'bone_marker_centre')
  if dot then rect(dot.x-3,dot.y-3,6,6,{230,232,234},'bone_parent')end
 end
 return self
end
return M

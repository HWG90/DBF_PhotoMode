-- Bone marker: a ring at the selected bone and a dot at its parent, projected
-- with the light gizmos' numeric camera projection. Display only, no engine calls.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vec(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
function M.new(project)
 assert(type(project)=='function','Marker projection required')
 local self={};local ring,dot;local visible=false
 function self.update(frame,fov,w,h,bone,parent,shown)
  ring,dot=nil,nil;visible=false
  if shown~=true or not vec(bone)then return end
  local x,y,depth=project(frame,fov,w,h,bone)
  if not x then return end
  ring={x=x,y=y,depth=depth};visible=true
  if vec(parent)then local px,py=project(frame,fov,w,h,parent);if px then dot={x=px,y=py}end end
 end
 function self.visible()return visible end
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

-- Numeric camera projection and queued light dragging. No engine/native calls.
local M={}
local marker_fields={'id','index','x','y','color','selected','enabled'}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vec(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
local function copy(v)return{v[1],v[2],v[3]}end
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function camera(f,fov,w,h)
 if type(f)~='table'or not(vec(f.position)and vec(f.forward)and vec(f.right)and vec(f.up))or not(finite(fov)and fov>.001 and fov<math.pi-.001 and finite(w)and finite(h)and w>0 and h>0)then return false end
 for _,v in ipairs({f.forward,f.right,f.up})do if math.abs(dot(v,v)-1)>.02 then return false end end
 return math.abs(dot(f.forward,f.right))<.02 and math.abs(dot(f.forward,f.up))<.02 and math.abs(dot(f.right,f.up))<.02
end
function M.target(frame,fov,w,h,u,v,depth)
 if not camera(frame,fov,w,h)or not(finite(u)and finite(v)and u>=0 and u<=1 and v>=0 and v<=1 and finite(depth)and depth>.05)then return nil end
 local vertical=math.tan(fov/2)*depth;local x=(u*2-1)*vertical*w/h;local y=(1-v*2)*vertical;local out={}
 for i=1,3 do out[i]=frame.position[i]+frame.forward[i]*depth+frame.right[i]*x+frame.up[i]*y end
 return out
end
function M.project(frame,fov,w,h,position)
 if not camera(frame,fov,w,h)or not vec(position)then return nil end
 local delta={position[1]-frame.position[1],position[2]-frame.position[2],position[3]-frame.position[3]};local depth=dot(delta,frame.forward)
 if depth<=.05 then return nil end
 local scale=h/(2*depth*math.tan(fov/2));return w/2+dot(delta,frame.right)*scale,h/2+dot(delta,frame.up)*scale,depth
end
function M.new(queue)
 local self={revision=0};local rows={};local frame,fov,w,h;local drag;local held=false;local armed=false;local visible=false
 function self.cancel()drag=nil;held=false;armed=false end
 function self.active()return drag~=nil end
 function self.update(items,context,angle,width,height,shown)
  local previous=rows;local was_visible=visible
  visible=shown==true and camera(context,angle,width,height);rows={}
  if not visible then if was_visible then self.revision=self.revision+1 end;self.cancel();return end
  if frame and(frame.world~=context.world or frame.scene_epoch~=context.scene_epoch)then self.cancel()end
  frame={position=copy(context.position),forward=copy(context.forward),right=copy(context.right),up=copy(context.up),world=context.world,scene_epoch=context.scene_epoch};fov,w,h=angle,width,height
  local found=false
  for _,item in ipairs(items or{})do
   local position=drag and drag.id==item.id and drag.position or item.position
   local x,y,depth=M.project(frame,fov,w,h,position)
   if x and finite(item.id)and finite(item.index)then
    local row={id=item.id,index=item.index,x=x,y=y,depth=depth,position=copy(position),color=item.color or item.values and item.values.color or'#FFFFFF',selected=item.selected,enabled=item.enabled~=false and(not item.values or item.values.enabled~=false)}
    rows[#rows+1]=row;if drag and drag.id==item.id then found=true end
   end
  end
  if drag and not found then self.cancel()end
  local changed=not was_visible or #previous~=#rows
  if not changed then for index,row in ipairs(rows)do
   local old=previous[index]
   for _,key in ipairs(marker_fields)do
    if row[key]~=old[key]then changed=true;break end
   end
   if changed then break end
  end end
  if changed then self.revision=self.revision+1 end
 end
 local function radius()return math.max(10,math.min(20,h/72))end
 local function excluded(block,x,y,r)
  return x-r<0 or y-r<0 or x+r>w or y+r>h or block and(block(x,y)or block(x-r,y-r)or block(x+r,y+r)or block(x-r,y+r)or block(x+r,y-r))
 end
 function self.hit(x,y,block,modal)
  if not visible or modal or not(finite(x)and finite(y))then return false end
  if drag then return true end
  local r=radius()+3
  for _,row in ipairs(rows)do if not excluded(block,row.x,row.y,r)and math.abs(x-row.x)<=r and math.abs(y-row.y)<=r then return true end end
  return false
 end
 function self.draw(commands,block,modal)
  if not visible or modal then return end
  local r=radius()
  for _,row in ipairs(rows)do if not excluded(block,row.x,row.y,r+3)then
   local color=row.color;local c={tonumber(color:sub(2,3),16)or 255,tonumber(color:sub(4,5),16)or 255,tonumber(color:sub(6,7),16)or 255};local border=row.selected and{244,202,53}or{230,232,234}
   local function rect(x,y,ww,hh,col,role)commands[#commands+1]={type='rect',x=x,y=y,w=ww,h=hh,c=col,a=row.enabled and 1 or .55,layer=330,ui_role=role,light_id=row.id}end
   rect(row.x-r-2,row.y-r-2,r*2+4,r*2+4,border,'light_marker')
   rect(row.x-r,row.y-r,r*2,r*2,{16,18,20})
   rect(row.x-r+2,row.y-r+2,4,r*2-4,c,'light_marker_color')
   commands[#commands+1]={type='text',text=tostring(row.index),x=row.x-r*.2,y=row.y-r*.55,size=r*1.3,c={255,255,255},a=1,layer=331,light_id=row.id,ui_role='light_marker_number'}
  end end
 end
 function self.tick(input,down,block,modal)
  if not visible or modal or not input or not(finite(input.x)and finite(input.y))then self.cancel();return false end
  local click=input.click==true;local pressed=click and not held;held=click
  if not click then local captured=drag~=nil;drag=nil;armed=true;return captured end
  if not armed then return false end
  if drag then
   local dx,dy=input.x-drag.x,input.y-drag.y;drag.x,drag.y=input.x,input.y
   if block and block(input.x,input.y)then return true end
   local speed=down and down(16)and .1 or 1;local scale=2*drag.depth*math.tan(drag.fov/2)/drag.h*speed
   if dx~=0 or dy~=0 then
    local position={};for i=1,3 do position[i]=drag.position[i]+(drag.frame.right[i]*dx+drag.frame.up[i]*dy)*scale end
    local ok=queue('move',{id=drag.id,position=position});if ok~=false then drag.position=position end
   end
   return true
  end
  if not pressed then return false end
  local closest;local r=radius()+3
  for _,row in ipairs(rows)do if not excluded(block,row.x,row.y,r)and math.abs(input.x-row.x)<=r and math.abs(input.y-row.y)<=r and(not closest or row.depth<closest.depth)then closest=row end end
  if not closest then return false end
  if queue('select',closest.index)==false then return true end
  for _,row in ipairs(rows)do row.selected=row.id==closest.id end
  self.revision=self.revision+1
  drag={id=closest.id,position=copy(closest.position),depth=closest.depth,x=input.x,y=input.y,frame=frame,fov=fov,h=h}
  return true
 end
 return self
end
return M

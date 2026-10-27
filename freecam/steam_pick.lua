-- One-shot scene subject picking for an explicit double-click. No ticks or
-- caches: every unit handle is fetched in the call and dropped before the
-- caller's frame ends. Each transform read follows Unit.alive and a nonzero
-- scene-graph count, since the transform getters do not check either.
local M={}
local helldiver='4d1c334d294dfa97'
-- Feet, waist and head height above the root, so tall and short rigs both hit.
local heights={0,.9,1.8}
-- Named body joints from the same stock 107-node rig used by the pose bank.
-- Read on explicit picks only; never retain engine vectors or unit handles.
local body_nodes={'hips','chest','head','l_shoulder','l_elbow','l_hand','r_shoulder','r_elbow','r_hand',
 'l_thigh','l_knee','l_foot','r_thigh','r_knee','r_foot'}
local body_segments={{1,2,.35},{2,3,.25},{2,4,.25},{4,5,.18},{5,6,.18},{2,7,.25},{7,8,.18},{8,9,.18},
 {1,10,.25},{10,11,.22},{11,12,.18},{1,13,.25},{13,14,.22},{14,15,.18}}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function segment_distance2(point,a,b)
 local ax,ay,az=b[1]-a[1],b[2]-a[2],b[3]-a[3]
 local length=ax*ax+ay*ay+az*az
 local t=length>0 and math.max(0,math.min(1,((point[1]-a[1])*ax+(point[2]-a[2])*ay+(point[3]-a[3])*az)/length))or 0
 return(point[1]-a[1]-t*ax)^2+(point[2]-a[2]-t*ay)^2+(point[3]-a[3]-t*az)^2
end
function M.new(sr)
 local A,W,U,I,V=sr.Application,sr.World,sr.Unit,sr.IdString64,sr.Vector3
 local self={}
 local function usable()
  return type(A)=='table'and type(W)=='table'and type(U)=='table'and type(V)=='table'and
   type(W.units)=='function'and type(U.alive)=='function'and type(U.num_scene_graph_items)=='function'and
   type(U.has_animation_state_machine)=='function'and type(U.world_position)=='function'and
   type(V.x)=='function'and type(V.y)=='function'and type(V.z)=='function'
 end
 local function is_helldiver(unit,id)
  if not id or type(U.resource_name)~='function'or type(I.equal)~='function'then return false end
  local ok,same=pcall(function()return I.equal(U.resource_name(unit),id)end)
  return ok and same==true
 end
 local function label(unit,hd)
  if hd then return'Helldiver'end
  if type(U.debug_name)=='function'then
   local ok,name=pcall(U.debug_name,unit)
   -- Shipping builds return '#ID[hash]' for most units; that is no label.
   if ok and type(name)=='string'and #name>0 and #name<=64 and not name:find('%c')and not name:find('^#ID%[')then return name end
  end
  return'Character'
 end
 -- camera={pos,forward,up,fov}; x,y are GUI pixels with a bottom-left origin.
 function self.pick(camera,x,y,width,height,radius,surface_depth,audit)
  if not usable()then return nil,'Scene picking unavailable'end
  if not(width and height and width>0 and height>0)then return nil,'Photo viewport unavailable'end
  local world=A.main_world();if not world then return nil,'Main world unavailable'end
  local units=W.units(world);if type(units)~='table'then return nil,'World units unavailable'end
  local p,f,u=camera.pos,camera.forward,camera.up
  local r={f[2]*u[3]-f[3]*u[2],f[3]*u[1]-f[1]*u[3],f[1]*u[2]-f[2]*u[1]}
  local tangent=math.tan(camera.fov/2);local aspect=width/height
  local id=I and type(I.from_hex)=='function'and select(2,pcall(I.from_hex,helldiver))or nil
  local surface
  if surface_depth~=nil then
   if type(surface_depth)~='number'or surface_depth~=surface_depth or surface_depth<=0 or surface_depth>=10000 then return nil,'No visible surface under the pointer'end
   local sx,sy=(x/width*2-1)*tangent*aspect,(y/height*2-1)*tangent
   surface={};for i=1,3 do surface[i]=p[i]+surface_depth*(f[i]+r[i]*sx+u[i]*sy)end
  end
  if audit then audit.surface=surface;audit.candidates=0;audit.hits={};audit.rigs={} end
  local best,best_score,best_depth,best_body
  for _,unit in pairs(units)do if type(unit)=='userdata'then
   local ok,score,depth,center,geometry=pcall(function()
    if U.alive(unit)~=true then return end
    local items=U.num_scene_graph_items(unit)
    if type(items)~='number'or items<2 then return end
    local hd=surface and items==107 and is_helldiver(unit,id)
    local trace
    if audit and hd and #audit.rigs<8 then trace={reason='animation',ratio=-1};audit.rigs[#audit.rigs+1]=trace end
    if U.has_animation_state_machine(unit)~=true then return end
    local root=U.world_position(unit,1)
    local x0,y0,z0=V.x(root),V.y(root),V.z(root)
    if hd and type(U.has_node)=='function'and type(U.node)=='function'then
     if trace then trace.reason='joint-read' end
     local points={}
     for i,name in ipairs(body_nodes)do
      if U.has_node(unit,name)~=true then return end
      local index=U.node(unit,name)
      if not(finite(index)and index==math.floor(index)and index>=1 and index<=items)then return end
      local position=U.world_position(unit,index)
      local point={V.x(position),V.y(position),V.z(position)}
      if not(finite(point[1])and finite(point[2])and finite(point[3]))then return end
      points[i]=point
     end
     local nearest
     for _,segment in ipairs(body_segments)do
      local d2=segment_distance2(surface,points[segment[1]],points[segment[2]])
      if trace then local ratio=math.sqrt(d2)/segment[3];if trace.ratio<0 or ratio<trace.ratio then trace.ratio=ratio end end
      if d2<=segment[3]^2 and(not nearest or d2<nearest)then nearest=d2 end
     end
     if trace then trace.reason=nearest and'hit'or'outside-body' end
     if nearest then return math.sqrt(nearest)/surface_depth/tangent*height/2,surface_depth,points[1],'body-joints' end
     return -- Valid depth outside the current body must not select its old upright proxy.
    end
    -- Reject projected characters behind the clicked surface. This is a
    -- conservative character capsule, not an exact skinned-mesh raycast.
    if surface then
     local dz=surface[3]-math.max(z0,math.min(z0+heights[3],surface[3]))
     if (surface[1]-x0)^2+(surface[2]-y0)^2+dz^2>.8^2 then return end
    end
    local nearest,depth,previous
    for _,h in ipairs(heights)do
     local dx,dy,dz=x0-p[1],y0-p[2],z0+h-p[3]
     local z=dx*f[1]+dy*f[2]+dz*f[3]
     if z>.3 then
      local sx=width/2+(dx*r[1]+dy*r[2]+dz*r[3])/z/(tangent*aspect)*width/2
      local sy=height/2+(dx*u[1]+dy*u[2]+dz*u[3])/z/tangent*height/2
      local d=math.sqrt((sx-x)^2+(sy-y)^2)
      if not nearest or d<nearest then nearest,depth=d,z end
      if previous then
       local ax,ay=sx-previous[1],sy-previous[2];local length=ax*ax+ay*ay
       local t=length>0 and math.max(0,math.min(1,((x-previous[1])*ax+(y-previous[2])*ay)/length))or 0
       local segment=math.sqrt((previous[1]+t*ax-x)^2+(previous[2]+t*ay-y)^2)
       if segment<nearest then nearest,depth=segment,previous[3]+t*(z-previous[3])end
      end
      previous={sx,sy,z}
     else previous=nil
     end
    end
    local reach=surface and math.max(radius,.35/surface_depth/tangent*height/2)or radius
    if nearest and nearest<=reach then return nearest,depth,{x0,y0,z0+heights[2]},audit and'upright-capsule'or nil end
   end)
   if audit and ok and score then
    audit.candidates=audit.candidates+1
    if #audit.hits<16 then
     local resource='unknown'
     if type(U.resource_name)=='function'then
      local named,name=pcall(function()return tostring(U.resource_name(unit))end)
      if named then resource=name:sub(1,96):gsub('%c','?')end
     end
     audit.hits[#audit.hits+1]={resource=resource,geometry=geometry,score=score,depth=depth}
    end
   end
   -- A depth-qualified body intersection is more specific than an upright
   -- proxy. Attached animated render units can project closer to the cursor
   -- than their actual subject; do not let that proxy steal a real body hit.
   -- Occluded bodies still fail the surface/joint test above.
   local body=geometry=='body-joints'
   if ok and score and(not best_score or body and not best_body or body==best_body and
    (score<best_score-4 or math.abs(score-best_score)<=4 and depth<best_depth))then
    best,best_score,best_depth,best_body={unit=unit,center=center},score,depth,body
    if audit then audit.geometry=geometry;audit.center=center;audit.score=score end
   end
  end end
  if not best then return nil,'No character under the pointer'end
  best.helldiver=is_helldiver(best.unit,id);best.label=label(best.unit,best.helldiver)
  if audit and type(U.resource_name)=='function'then
   local ok,name=pcall(function()return tostring(U.resource_name(best.unit))end)
   if ok then audit.resource=name:sub(1,96):gsub('%c','?')end
  end
  local c=best.center
  best.distance=surface_depth or math.sqrt((c[1]-p[1])^2+(c[2]-p[2])^2+(c[3]-p[3])^2)
  return best
 end
 return self
end
return M

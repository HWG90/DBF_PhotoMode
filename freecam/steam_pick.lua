-- One-shot scene subject picking for an explicit double-click. No ticks or
-- caches: every unit handle is fetched in the call and dropped before the
-- caller's frame ends. Each transform read follows Unit.alive and a nonzero
-- scene-graph count, since the transform getters do not check either.
local M={}
local helldiver='4d1c334d294dfa97'
-- Feet, waist and head height above the root, so tall and short rigs both hit.
local heights={0,.9,1.6}
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
 function self.pick(camera,x,y,width,height,radius)
  if not usable()then return nil,'Scene picking unavailable'end
  if not(width and height and width>0 and height>0)then return nil,'Photo viewport unavailable'end
  local world=A.main_world();if not world then return nil,'Main world unavailable'end
  local units=W.units(world);if type(units)~='table'then return nil,'World units unavailable'end
  local p,f,u=camera.pos,camera.forward,camera.up
  local r={f[2]*u[3]-f[3]*u[2],f[3]*u[1]-f[1]*u[3],f[1]*u[2]-f[2]*u[1]}
  local tangent=math.tan(camera.fov/2);local aspect=width/height
  local best,best_score,best_depth
  for _,unit in pairs(units)do if type(unit)=='userdata'then
   local ok,score,depth,center=pcall(function()
    if U.alive(unit)~=true then return end
    local items=U.num_scene_graph_items(unit)
    if type(items)~='number'or items<2 then return end
    if U.has_animation_state_machine(unit)~=true then return end
    local root=U.world_position(unit,1)
    local x0,y0,z0=V.x(root),V.y(root),V.z(root)
    local nearest,depth
    for _,h in ipairs(heights)do
     local dx,dy,dz=x0-p[1],y0-p[2],z0+h-p[3]
     local z=dx*f[1]+dy*f[2]+dz*f[3]
     if z>.3 then
      local sx=width/2+(dx*r[1]+dy*r[2]+dz*r[3])/z/(tangent*aspect)*width/2
      local sy=height/2+(dx*u[1]+dy*u[2]+dz*u[3])/z/tangent*height/2
      local d=math.sqrt((sx-x)^2+(sy-y)^2)
      if not nearest or d<nearest then nearest,depth=d,z end
     end
    end
    if nearest and nearest<=radius then return nearest,depth,{x0,y0,z0+heights[2]}end
   end)
   if ok and score and(not best_score or score<best_score-4 or math.abs(score-best_score)<=4 and depth<best_depth)then
    best,best_score,best_depth={unit=unit,center=center},score,depth
   end
  end end
  if not best then return nil,'No character under the pointer'end
  local id=I and type(I.from_hex)=='function'and select(2,pcall(I.from_hex,helldiver))or nil
  best.helldiver=is_helldiver(best.unit,id);best.label=label(best.unit,best.helldiver)
  local c=best.center
  best.distance=math.sqrt((c[1]-p[1])^2+(c[2]-p[2])^2+(c[3]-p[3])^2)
  return best
 end
 return self
end
return M

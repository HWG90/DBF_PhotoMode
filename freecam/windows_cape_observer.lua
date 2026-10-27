-- Private, read-only paired snapshots around the existing root correction.
-- Four pairs per process, one garment and at most four bodies per pair.
-- Matching positions are evidence to inspect, not attachment ownership.
local M={}
function M.new(sr,log)
 local U,B=sr.Unit,sr.Matrix4x4
 local remaining=4;local serial=0;local seen=setmetatable({},{__mode='k'})
 local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
 local function pose(u,node,world)
  local values={B.to_elements((world and U.world_pose or U.local_pose)(u,node))}
  assert(#values==12,'Cape matrix shape');for _,n in ipairs(values)do assert(finite(n),'Cape matrix invalid')end
  return values
 end
 local function valid(r,w)
  return U.alive(r.unit)==true and U.world(r.unit)==w and U.num_scene_graph_items(r.unit)==r.count
 end
 local function snapshot(r,w,mesh)
  assert(valid(r,w),'Cape observer unit retired')
  local out={resource=r.resource,nodes=r.count,root=pose(r.unit,1,false),world_root=pose(r.unit,1,true)}
  out.bones={}
  for _,name in ipairs({'cape1','cape2','cape3'})do
   if U.has_node(r.unit,name)==true then
    local node=U.node(r.unit,name);assert(finite(node)and node%1==0 and node>=1 and node<=r.count,'Cape node bounds')
    out.bones[#out.bones+1]={name=name,node=node,parent=U.scene_graph_parent(r.unit,node),local_pose=pose(r.unit,node,false),world_pose=pose(r.unit,node,true)}
   end
  end
  if mesh then
   local count=U.num_meshes(r.unit);assert(finite(count)and count%1==0 and count>=1 and count<=8,'Cape mesh budget exceeded')
   out.meshes={}
   for index=1,count do
    local handle=U.mesh(r.unit,index);assert(handle~=nil,'Cape mesh missing')
    local node=sr.Mesh.node(handle);assert(finite(node)and node%1==0 and node>=1 and node<=r.count,'Cape mesh node bounds')
    local parent=U.scene_graph_parent(r.unit,node)
    local visible='getter unavailable'
    if type(sr.Mesh.visibility)=='function'then
     local ok,value=pcall(sr.Mesh.visibility,handle)
     visible=ok and type(value)=='boolean'and tostring(value)or'read unavailable'
    end
    out.meshes[#out.meshes+1]={index=index,node=node,parent=parent,visible=visible,local_pose=pose(r.unit,node,false),world_pose=pose(r.unit,node,true)}
   end
  end
  return out
 end
 local function numbers(t)local s={};for i,n in ipairs(t)do s[i]=string.format('%.7g',n)end;return table.concat(s,',')end
 local function emit(id,phase,role,s)
  local prefix='Cape snapshot: pair='..id..' phase='..phase..' role='..role..' resource='..s.resource
  log(prefix..' nodes='..s.nodes..' root_local='..numbers(s.root)..' root_world='..numbers(s.world_root))
  for _,b in ipairs(s.bones)do log(prefix..' bone='..b.name..' node='..b.node..' parent='..tostring(b.parent)..' local='..numbers(b.local_pose)..' world='..numbers(b.world_pose))end
  for _,b in ipairs(s.meshes or{})do log(prefix..' mesh='..b.index..' node='..b.node..' parent='..tostring(b.parent)..' visible='..b.visible..' local='..numbers(b.local_pose)..' world='..numbers(b.world_pose))end
 end
 local self={}
 function self.before(rows,world)
  if remaining==0 then return end
  local cape,bodies
  bodies={}
  for _,r in ipairs(rows)do
   if r.helldiver and #bodies<4 then bodies[#bodies+1]=r end
   if r.cape and not seen[r.unit]and not cape then cape=r end
  end
  if not cape or #bodies==0 then return end
  seen[cape.unit]=true;remaining=remaining-1;serial=serial+1
  local ok,pair=pcall(function()
   local result={id=serial,world=world,cape=cape,bodies=bodies,before={cape=snapshot(cape,world,true),bodies={}}}
   for _,r in ipairs(bodies)do result.before.bodies[#result.before.bodies+1]=snapshot(r,world,false)end
   return result
  end)
  if not ok then log('Cape snapshot unavailable: '..tostring(pair));return end
  return pair
 end
 function self.after(pair,changed)
  if not pair then return end
  local ok,why=pcall(function()
   local after={cape=snapshot(pair.cape,pair.world,true),bodies={}}
   for _,r in ipairs(pair.bodies)do after.bodies[#after.bodies+1]=snapshot(r,pair.world,false)end
   for _,phase in ipairs({'before','after'})do
    local s=phase=='before'and pair.before or after
    emit(pair.id,phase,'cape',s.cape)
    for i,b in ipairs(s.bodies)do emit(pair.id,phase,'body'..i,b)end
   end
   log('Cape snapshot complete: pair='..pair.id..' body_changed='..tostring(changed)..'; read-only; ownership unverified')
  end)
  if not ok then log('Cape snapshot unavailable: '..tostring(why))end
 end
 return self
end
return M

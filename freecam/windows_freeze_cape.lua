-- Selected-outfit placement lease, using the authored-pose shoulder solver.
-- No cloth-bone, simulation, root, time, or input writes. Discover once per
-- Freeze; only replay placement after a body update or a scheduled readback.
local M={}
local function close(a,b)
 for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then return false end end;return true
end
function M.new(sr,associate,options)
 local U,W,X,H,I=sr.Unit,sr.World,sr.Matrix4x4,sr.Mesh,sr.IdString64
 local trace_count=0
 local function save(value)
  local t={X.to_elements(value)};assert(#t==12,'Cape matrix shape changed')
  for _,n in ipairs(t)do assert(type(n)=='number'and n==n and math.abs(n)<1e8,'Cape matrix invalid')end
  return t
 end
 local function load(t)return X.from_elements(unpack(t))end
 local function local_pose(u,n)return save(U.local_pose(u,n))end
 local function world_pose(u,n)return save(U.world_pose(u,n))end
 local function node(n,count)return type(n)=='number'and n%1==0 and n>=1 and n<=count end
 local function valid(r)
  if sr.Application.main_world()~=r.world or sr.Network.game_session()~=r.session then return false end
  if U.alive(r.unit)==false then return false end
  assert(U.alive(r.unit)==true and U.world(r.unit)==r.world,'Cape world changed')
  assert(I.equal(U.resource_name(r.unit),r.resource)==true,'Cape resource changed')
  assert(U.num_scene_graph_items(r.unit)==r.count and U.num_meshes(r.unit)==#r.handles,'Cape layout changed')
  for i,h in ipairs(r.handles)do if U.mesh(r.unit,i)~=h then return false end end
  for name,n in pairs(r.bones)do assert(U.has_node(r.unit,name)and U.node(r.unit,name)==n,'Cape bone mapping changed')end
  for _,m in ipairs(r.meshes)do
   assert(H.node(r.handles[m.index])==m.node and U.scene_graph_parent(r.unit,m.node)==m.parent,'Cape placement mapping changed')
  end
  return true
 end
 local self={}
 function self.trace(r,phase)
  if not r.trace_remaining or r.trace_remaining<=0 then return end
  r.trace_remaining=r.trace_remaining-1
  local ok,why=pcall(function()
   assert(valid(r),'Cape trace garment retired')
   assert(U.alive(r.body)==true and U.world(r.body)==r.world,'Cape trace body retired')
   local prefix='Cape attachment trace: lease='..r.trace_id..' phase='..phase
   local function emit(role,values)
    local out={};for i,n in ipairs(values)do out[i]=string.format('%.9g',n)end
    options.log(prefix..' role='..role..' matrix='..table.concat(out,','))
   end
   emit('body_root',world_pose(r.body,1));emit('garment_root',world_pose(r.unit,1))
   for _,name in ipairs({'chest','cape1','cape2'})do
    for _,item in ipairs({{'body',r.body},{'garment',r.unit}})do
     if U.has_node(item[2],name)then emit(item[1]..'_'..name,world_pose(item[2],U.node(item[2],name)))end
    end
   end
   for i,h in ipairs(r.handles)do
    local n=H.node(h)
    options.log(prefix..' mesh='..i..' node='..n..' parent='..tostring(U.scene_graph_parent(r.unit,n))..' visible='..tostring(H.visibility(h)))
    emit('mesh'..i..'_node_world',world_pose(r.unit,n))
    -- The documented Mesh getter reads the render object's placement, rather
    -- than assuming its scene-graph node is the final render transform.
    emit('mesh'..i..'_render_world',save(H.world_pose(h)))
   end
  end)
  if not ok then
   r.trace_remaining=0
   pcall(options.log,'Cape attachment trace stopped: '..tostring(why))
  end
 end
 function self.capture(frame)
  local rows=associate(frame,'cape');assert(#rows==1,'Unique cape unavailable')
  local row=rows[1];local u=row.unit
  assert(U.has_node(frame.root_handle,'cape1'),'Body shoulder unavailable')
  local anchor=U.node(frame.root_handle,'cape1')
  assert(node(anchor,U.num_scene_graph_items(frame.root_handle)),'Body shoulder invalid')
  local inverse=save(X.inverse(U.world_pose(frame.root_handle,anchor)))
  local r={unit=u,world=frame.world,body=frame.root_handle,identity=frame.identity,anchor=anchor,
   resource=U.resource_name(u),session=sr.Network.game_session(),count=U.num_scene_graph_items(u),bones={},meshes={},handles={},writes=0,
   flip=options and options.flip_shoulder_right==true}
  assert(node(r.count,512),'Cape graph bounds changed')
  local bones={}
  for i=1,64 do local name='cape'..i
   if U.has_node(u,name)then local n=U.node(u,name)
    assert(node(n,r.count)and not bones[n],'Cape bone mapping invalid');r.bones[name]=n;bones[n]=true
   end
  end
  assert(r.bones.cape1,'Cape shoulder unavailable')
  local function follows_cloth(n)
   local seen={}
   for _=1,r.count do
    if bones[n]then return true end
    assert(not seen[n],'Cape hierarchy cycle');seen[n]=true
    local parent=U.scene_graph_parent(u,n)
    if parent==nil or parent==0 then return false end
    assert(node(parent,r.count)and parent~=n,'Cape hierarchy invalid');n=parent
   end
   error('Cape hierarchy exceeds bound')
  end
  local count=U.num_meshes(u);assert(count==4,'Cape mesh bounds changed')
  local root=world_pose(u,1);local seen={}
  for i=1,count do
   local h=U.mesh(u,i);assert(h,'Cape mesh missing');r.handles[i]=h
   local n=H.node(h);assert(node(n,r.count),'Cape mesh node invalid')
   local parent=U.scene_graph_parent(u,n)
   if n>1 and not follows_cloth(n)and not seen[n]and node(parent,r.count)and parent~=n then
    local pose=world_pose(u,n)
    if close(pose,root)then
     local bind=save(X.multiply(load(pose),load(inverse)))
     if r.flip then
      -- Proper half turn, captured once. The zero translation keeps the
      -- shoulder pivot fixed; this never mirrors or scales the garment.
      bind=save(X.multiply(load(bind),X.from_elements(1,0,0,0,-1,0,0,0,-1,0,0,0)))
     end
     seen[n]=true;r.meshes[#r.meshes+1]={index=i,node=n,parent=parent,original=local_pose(u,n),
      bind=bind}
    end
   end
  end
  assert(#r.meshes>0 and valid(r),'Cape placement unavailable')
  if options and type(options.log)=='function'and trace_count<2 then
   trace_count=trace_count+1;r.trace_id=trace_count;r.trace_remaining=9
   self.trace(r,'capture_before_zero')
  end
  return r
 end
 function self.apply(r,frame)
  if options and options.trace_only then return 0 end
  if r.retired then return 0 end
  if not valid(r)then r.retired=true;return 0 end
  assert(frame and frame.identity==r.identity and frame.root_handle==r.body and frame.world==r.world,'Cape subject changed')
  assert(U.alive(r.body)==true and U.world(r.body)==r.world and U.node(r.body,'cape1')==r.anchor,'Cape body retired')
  local anchor=world_pose(r.body,r.anchor);local writes=0
  for _,m in ipairs(r.meshes)do
   local parent=world_pose(r.unit,m.parent)
   local desired=save(X.multiply(X.multiply(load(m.bind),load(anchor)),X.inverse(load(parent))))
   if not close(local_pose(r.unit,m.node),desired)then
    m.changed=true;m.last=desired -- Own cleanup even if the setter mutates then throws.
    assert(U.set_local_pose(r.unit,m.node,load(desired))~=false,'Cape placement refused')
    writes=writes+1;r.writes=r.writes+1
   end
  end
  if writes>0 then assert(W.update_unit(r.world,r.unit)~=false,'Cape placement refresh refused')end
  return writes
 end
 function self.release(r)
  if r.retired or not valid(r)then r.retired=true;return true end
  local changed={};local wrote=false
  for _,m in ipairs(r.meshes)do if m.changed then
   -- Do not overwrite a replacement animation/pose owner's placement.
   if close(local_pose(r.unit,m.node),m.last)then
    assert(U.set_local_pose(r.unit,m.node,load(m.original))~=false,'Cape restoration refused');wrote=true
   end
   changed[#changed+1]=m
  end end
  if wrote then assert(W.update_unit(r.world,r.unit)~=false,'Cape restoration refresh refused')end
  for _,m in ipairs(changed)do m.changed=nil end
  return true
 end
 return self
end
return M

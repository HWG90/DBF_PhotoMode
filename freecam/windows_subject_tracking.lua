-- Photographic selection only; does not claim local-player ownership.
local M={}
-- Diagnostic only: world = local * parent implies parent = inverse(local) * world.
-- A derived match never grants a visibility lease or changes any transform.
function M.root_parent_pose(sr,unit)
 local U,B=sr.Unit,sr.Matrix4x4
 if not(U and B and type(U.local_pose)=='function'and type(B.inverse)=='function'and type(B.multiply)=='function'and type(B.from_elements)=='function')then return nil,'root transform APIs unavailable'end
 local function save(p)
  local a={B.to_elements(p)};assert(#a==12,'Root parent matrix shape changed')
  for _,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Root parent matrix invalid')end
  return a
 end
 local ok,value=pcall(function()
  assert(U.alive(unit)==true and U.num_scene_graph_items(unit)>=1,'Root parent subject retired')
  local local_pose=save(U.local_pose(unit,1));local world_pose=save(U.world_pose(unit,1))
  local a=local_pose
  local det=a[1]*(a[5]*a[9]-a[6]*a[8])-a[2]*(a[4]*a[9]-a[6]*a[7])+a[3]*(a[4]*a[8]-a[5]*a[7])
  assert(math.abs(det)>.0001,'Root parent local transform is singular')
  local parent=save(B.multiply(B.inverse(B.from_elements(unpack(local_pose))),B.from_elements(unpack(world_pose))))
  local rebuilt=save(B.multiply(B.from_elements(unpack(local_pose)),B.from_elements(unpack(parent))))
  for i=1,12 do assert(math.abs(rebuilt[i]-world_pose[i])<.001,'Root parent recomposition differs')end
  return parent
 end)
 if not ok then return nil,tostring(value)end
 return value
end
-- Private, read-only outfit discovery. Matching bones are evidence, not an
-- attachment lease: this never calls a visibility or transform setter.
-- Read-only attachment evidence. Exact transform coincidence is a candidate,
-- not an ownership lease. Check eight nodes per chunk; keep both poses in the same callback.
function M.attachment_matches(sr,owner,unit,first_node,expected_count)
 local U,B=sr.Unit,sr.Matrix4x4
 local function pose(u,n)
  local a={B.to_elements(U.world_pose(u,n))};assert(#a==12,'Attachment pose shape changed')
  for _,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Attachment pose invalid')end
  return a
 end
 local count=U.num_scene_graph_items(unit)
 assert(type(count)=='number'and count%1==0 and count>=1 and count<=1024,'Attachment graph exceeds bound')
 if expected_count then assert(count==expected_count,'Attachment graph changed during scan')end
 first_node=first_node or 1
 assert(first_node%1==0 and first_node>=1 and first_node<=count,'Attachment cursor invalid')
 local first,body=pose(unit,1),pose(owner,1);local distance=0
 for i=10,12 do distance=distance+(first[i]-body[i])^2 end
 if distance>9 then return {},nil,0,count end
 local derived
 -- A finite known weapon set, once at the start of an explicit node scan.
 if first_node==1 and type(U.resource_name)=='function'then
  local resource=tostring(U.resource_name(unit)):lower()
  for _,known in ipairs({'968211c0033dce64','27ee1ed8f6fb6356','416d053372c4e433','a8cffb316f0b5c5f'})do
   if resource:find(known,1,true)then derived=M.root_parent_pose(sr,unit);break end
  end
 end
 local anchors={}
 for _,name in ipairs({'attach_weapon','attach_hand_r','attach_hand_l','weapon_aim','backpack','sling','pistol','support','support_mg','attach_samplepouch','attach_intelpad','attach_knife'})do
  if U.has_node(owner,name)then anchors[#anchors+1]={name=name,pose=pose(owner,U.node(owner,name))}end
 end
 local matches={}
 local last_node=math.min(count,first_node+7)
 for node=first_node,last_node do
  local candidate=node==1 and first or pose(unit,node)
  for _,anchor in ipairs(anchors)do
   local equal=true
   for i=1,12 do if math.abs(candidate[i]-anchor.pose[i])>1e-4 then equal=false;break end end
   if equal then matches[#matches+1]=node..':'..anchor.name end
  end
 end
 local parent_matches={}
 if derived then for _,anchor in ipairs(anchors)do
  local equal=true;for i=1,12 do if math.abs(derived[i]-anchor.pose[i])>1e-4 then equal=false;break end end
  if equal then parent_matches[#parent_matches+1]=anchor.name end
 end end
 return matches,last_node<count and last_node+1 or nil,last_node-first_node+1,count,parent_matches
end
function M.inventory(sr,log,clock)
 local U,W,B=sr.Unit,sr.World,sr.Matrix4x4
 local names={'head','chest','spine1','hips','l_hand','r_hand','cape1','backpack','attach_weapon'}
 local state,used;local self={};clock=clock or os.clock
 local function matrix(unit,node)
  local values={B.to_elements(U.world_pose(unit,node))}
  assert(#values==12,'Outfit matrix shape changed')
  for _,n in ipairs(values)do assert(type(n)=='number'and n==n and math.abs(n)<1e8,'Outfit matrix invalid')end
  return values
 end
 local function finish(reason)
  self.result={reason=reason,visited=state.cursor-1,total=state.total or 0,candidates=state.found,attachments=state.attachments,attachment_nodes=state.attachment_nodes,nested=state.nested_hits,nested_nodes=state.nested_nodes,max_step_ms=state.max_ms}
  log(string.format('Outfit discovery: %s; units=%d/%d candidates=%d attachments=%d attachment_nodes=%d nested=%d nested_nodes=%d max_step_ms=%.3f; writes=0; ownership unverified',
   reason,self.result.visited,self.result.total,state.found,state.attachments,state.attachment_nodes,state.nested_hits,state.nested_nodes,state.max_ms))
  state=nil
 end
 function self.request(frame)
  if used or not frame or not frame.explicit_subject then return false end
  used=true;state={owner=frame.root_handle,world=frame.world,identity=frame.identity,cursor=1,found=0,attachments=0,attachment_nodes=0,max_ms=0,
   nearby={},parents={},direct={},nested_hits=0,nested_nodes=0}
  return true
 end
 local function attachment_chunk(unit,count)
  local pending=state.pending
  local resource=tostring(U.resource_name(unit))
  if pending then assert(resource==pending.resource and count==pending.meshes,'Attachment resource changed during scan')end
  local hits,next_node,spent,total,parent_matches=M.attachment_matches(sr,state.owner,unit,pending and pending.node,pending and pending.total)
  if parent_matches and #parent_matches>0 then
   log('Attachment derived-parent candidate: resource='..resource..' meshes='..count..' nodes='..total..' matching='..table.concat(parent_matches,',')..'; inverse local-root times world-root; read-only hypothesis; writes=0')
  end
  state.attachment_nodes=state.attachment_nodes+spent
  assert(state.attachment_nodes<=4096,'Attachment node budget exceeded')
  local matches=pending and pending.matches or{}
  for _,hit in ipairs(hits)do if #matches<32 then matches[#matches+1]=hit end end
  if next_node then
   state.pending={unit=unit,resource=resource,meshes=count,node=next_node,total=total,matches=matches}
  else
   state.pending=nil
   if spent>0 or pending then
    assert(#state.nearby<128,'Nearby attachment candidate budget exceeded')
    state.nearby[#state.nearby+1]={unit=unit,resource=resource,meshes=count,nodes=total}
   end
   if #matches>0 then
    state.attachments=state.attachments+1
    assert(state.attachments<=16,'Attachment candidate budget exceeded')
    log('Attachment candidate: resource='..resource..' meshes='..count..' nodes='..total..' matching='..table.concat(matches,',')..'; writes=0; ownership unverified')
    state.direct[unit]=true
    -- Only a root matched to a named body anchor may be a second-pass parent.
    -- Store handles and scalar identity, never scratch matrices/IdString64s.
    local anchors={}
    for _,hit in ipairs(matches)do local name=hit:match('^1:(.+)$');if name then anchors[#anchors+1]=name end end
    if #anchors>0 then state.parents[#state.parents+1]={unit=unit,resource=resource,meshes=count,nodes=total,anchors=anchors}end
   end
  end
 end
 local function equal(a,b)
  for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then return false end end
  return true
 end
 local function validate(row)
  assert(U.alive(row.unit)and U.world(row.unit)==state.world,'Nested attachment retired')
  assert(tostring(U.resource_name(row.unit))==row.resource and U.num_meshes(row.unit)==row.meshes and U.num_scene_graph_items(row.unit)==row.nodes,'Nested attachment identity changed')
 end
 local function nested_chunk()
  local p=state.nested
  local candidate,parent=state.nearby[p.candidate],state.parents[p.parent]
  if not candidate or not parent then state.nested_done=true;return end
  if state.direct[candidate.unit]then p.candidate=p.candidate+1;return end
  validate(candidate);validate(parent)
  local root=matrix(parent.unit,1);local attached=false
  if parent.body then
   -- Investigate missing holster links only for already observed equipment
   -- resources; do not multiply every nearby prop by the entire body graph.
   for _,resource in ipairs({'968211c0033dce64','27ee1ed8f6fb6356','416d053372c4e433','e60ae045e0090f4c','a8cffb316f0b5c5f'})do
    if candidate.resource:lower():find(resource,1,true)then attached=true;break end
   end
  else
   for _,name in ipairs(parent.anchors)do
    if U.has_node(state.owner,name)and equal(root,matrix(state.owner,U.node(state.owner,name)))then attached=true;break end
   end
  end
  -- A dropped/swapped weapon is no longer evidence about this subject.
  local hits={};local last=math.min(parent.nodes,p.node+7)
  if attached then
   local child=matrix(candidate.unit,1)
   for node=p.node,last do
    state.nested_nodes=state.nested_nodes+1
    assert(state.nested_nodes<=8192,'Nested attachment node budget exceeded')
    if equal(child,node==1 and root or matrix(parent.unit,node))then hits[#hits+1]=node end
   end
   if #hits>0 then
    state.nested_hits=state.nested_hits+1;assert(state.nested_hits<=128,'Nested attachment match budget exceeded')
    log('Nested attachment candidate: resource='..candidate.resource..' meshes='..candidate.meshes..' nodes='..candidate.nodes..' parent='..parent.resource..' parent_nodes='..table.concat(hits,',')..'; root full-matrix match; writes=0; ownership unverified')
   end
  end
  if attached and last<parent.nodes then p.node=last+1;return end
  p.node=1;p.parent=p.parent+1
  if p.parent>#state.parents then p.parent=1;p.candidate=p.candidate+1 end
 end
 function self.release()if state then finish('cancelled at Photo Mode close')end end
 function self.tick(frame)
  if not state then return end
  local started=clock()
  local ok,why=pcall(function()
   assert(frame and frame.root_handle==state.owner and frame.world==state.world and frame.identity==state.identity,'Selected subject changed')
   assert(sr.Application.main_world()==state.world and U.alive(state.owner)and U.world(state.owner)==state.world,'Selected subject retired')
   if not state.units then
    state.units=W.units(state.world)
    assert(type(state.units)=='table'and #state.units<=16384,'Outfit world inventory exceeds bound')
    state.total=#state.units;state.nodes={}
    for _,name in ipairs(names)do if U.has_node(state.owner,name)then state.nodes[name]=U.node(state.owner,name)end end
    return -- Measure the snapshot separately; never add scanning to this frame.
   end
   if state.nested then
    local chunks=0
    while not state.nested_done and chunks<4 and clock()-started<.002 do nested_chunk();chunks=chunks+1 end
    return
   end
   local processed=0
   while (state.pending or state.cursor<=state.total)and processed<24 and clock()-started<.002 do
    if state.pending then
     local u=state.pending.unit;assert(U.alive(u)and U.world(u)==state.world,'Attachment candidate retired')
     attachment_chunk(u,U.num_meshes(u));processed=processed+1
    else
    local unit=state.units[state.cursor];state.cursor=state.cursor+1;processed=processed+1
    if unit~=state.owner and U.alive(unit)and U.world(unit)==state.world then
     local count=U.num_meshes(unit)
     if type(count)=='number'and count%1==0 and count>0 and count<=128 then
      local matched={};local present={}
      for _,name in ipairs(names)do
       if state.nodes[name]and U.has_node(unit,name)then
        present[#present+1]=name
        -- Compare both live poses in the same callback, never across frames.
        local a,b=matrix(state.owner,state.nodes[name]),matrix(unit,U.node(unit,name));local equal=true
        for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then equal=false;break end end
        if equal then matched[#matched+1]=name end
       end
      end
      if #matched==0 and type(U.num_scene_graph_items)=='function'then
       attachment_chunk(unit,count)
      end
      if #matched>0 then
       state.found=state.found+1
       assert(state.found<=32,'Outfit candidate budget exceeded')
       local resource=tostring(U.resource_name(unit))
       log('Outfit candidate: resource='..resource..' meshes='..count..' matching='..table.concat(matched,',')..' present='..table.concat(present,','))
       for i=1,math.min(count,16)do
        local mesh=U.mesh(unit,i)
        log('Outfit candidate mesh: resource='..resource..' index='..i..' node='..tostring(sr.Mesh.node(mesh))..' visible='..tostring(sr.Mesh.visibility(mesh)))
       end
      end
     end
    end
    end
   end
  end)
  local elapsed=(clock()-started)*1000;state.max_ms=math.max(state.max_ms,elapsed)
  if not ok then finish('stopped: '..tostring(why))
  elseif elapsed>8 then finish('stopped at read budget')
  elseif state.nested_done then finish('complete')
  elseif state.total and state.cursor>state.total and not state.pending and not state.nested then
   if type(U.num_scene_graph_items)=='function'then
    local resource=tostring(U.resource_name(state.owner))
    if resource:lower():find('4d1c334d294dfa97',1,true)and U.num_scene_graph_items(state.owner)==107 then
     state.parents[#state.parents+1]={unit=state.owner,resource=resource,meshes=U.num_meshes(state.owner),nodes=107,body=true}
    end
   end
   local unmatched=false;for _,row in ipairs(state.nearby)do if not state.direct[row.unit]then unmatched=true;break end end
   if #state.parents>0 and unmatched then
    state.nested={candidate=1,parent=1,node=1}
    log('Nested attachment discovery: nearby='..#state.nearby..' parents='..#state.parents..'; bounded second pass; writes=0')
   else finish('complete')end
  end
 end
 return self
end
function M.inspect(frame,sr,log)
 local U,Mesh=sr and sr.Unit,sr and sr.Mesh
 if not(U and Mesh and type(U.num_meshes)=='function'and type(U.mesh)=='function')then return end
 local unit=frame.root_handle
 assert(U.alive(unit)==true and U.world(unit)==frame.world,'Selected mesh inventory owner retired')
 local count=U.num_meshes(unit)
 assert(type(count)=='number'and count%1==0 and count>=0 and count<=64,'Selected mesh inventory budget exceeded')
 log('Handycam mesh inventory: selected root meshes='..count..'; attachment ownership not inferred')
 for index=1,count do
  local mesh=U.mesh(unit,index);local fields={'mesh='..index}
  for _,name in ipairs({'node','visibility','num_materials'})do
   if type(Mesh[name])=='function'then
    local ok,value=pcall(Mesh[name],mesh)
    fields[#fields+1]=name..'='..(ok and tostring(value):sub(1,128)or'unavailable')
   end
  end
  log('Handycam mesh inventory: '..table.concat(fields,' '))
 end
 assert(U.alive(unit)==true and U.world(unit)==frame.world,'Selected mesh inventory owner changed')
end
function M.new(selected,sr,log,diagnostics)
 local self={selection_only=true}
 local observed={};local observations=0
 local inventory=diagnostics and sr and log and M.inventory(sr,log)
 local inventory_requested=false;local inventory_attempts=0
 function self.request_inventory(explicit)
  -- A later explicit full-hide action can capture a new equipped/holstered
  -- state. Never rearm from routine subject sync or while a scan is running.
  if explicit==true and not inventory and inventory_attempts<4 and diagnostics and sr and log then
   inventory=M.inventory(sr,log);inventory_requested=false
  end
  if not inventory or inventory_requested then return end
  local ok,frame=pcall(selected)
  if ok and frame then inventory_requested=inventory.request(frame);if inventory_requested then inventory_attempts=inventory_attempts+1 end end
 end
 function self.tick()
  if not inventory or not inventory_requested then return end
  local ok,frame=pcall(selected)
  if not ok then frame=nil end
  inventory.tick(frame)
  if inventory.result then inventory=nil end -- Finished state stays idle.
 end
 function self.release()if inventory then inventory.release();inventory=nil end end
 function self.head_frame()
  local frame,why=selected();assert(type(frame)=='table',why or'Select a Helldiver in Subject')
  assert(frame.explicit_subject==true and frame.identity and frame.root_handle and frame.world,'Selected tracking identity unavailable')
  for _,name in ipairs({'position','head'})do
   local v=frame[name];assert(type(v)=='table','Selected tracking position missing')
   for i=1,3 do assert(type(v[i])=='number'and v[i]==v[i]and math.abs(v[i])<1e8,'Selected tracking position invalid')end
  end
  -- Bounded to four distinct explicit targets per runtime, on shot entry/read.
  -- No world scan, material change, visibility setter or idle refresh.
  if sr and log and not observed[frame.identity]and observations<4 then
   observed[frame.identity]=true;observations=observations+1
   local ok,why=pcall(M.inspect,frame,sr,log)
   if not ok then log('Handycam mesh inventory unavailable: '..tostring(why))end
  end
  return frame
 end
 self.frame=self.head_frame
 return self
end
return M

-- Private current-outfit candidate. Bone correspondence associates photographic
-- subjects; it is not a local-player authority claim. Current outfit grouping visually verified.
local M={}
local models={
 {group='torso',resource='98ef4e039e963bdb',bones={'chest','spine1'},names={-1507809972,1834168505,1254990207,281914907,-912447649}},
 {group='torso',resource='d2a2e2bc4fa5be21',bones={'head','chest','spine1'},names={-1507809972,-2146726238,1969322454,1910610386,-333112902,531958952}},
 {group='helmet',resource='544ed679357b6cb7',bones={'head','chest','spine1'},names={-2146726238,1417423069,-486531110,1988273415,1447930109}},
 {group='cape',resource='ea846ef460cc5ba0',bones={'head','chest','cape1'},names={-13682950,523982579,-308352159,-925021909}}}
-- Additional current-outfit resources observed with the selected body's full
-- joint matrices; full hiding is a private candidate until visually accepted.
for _,item in ipairs({
 {'a5710e9464a26f48',5,{'chest','spine1','l_hand'}},
 {'6a589144bb3f838f',5,{'chest','spine1','r_hand'}},
 {'a70972419680b0b2',5,{'spine1','hips'}},
 {'3bae7995707e30fb',5,{'chest','spine1'}},
 {'619253c08af8dfdf',5,{'chest','spine1'}},
 {'abf65fc9fc79fa96',5,{'hips'}},
 {'c80b17cf0adc14a8',5,{'chest','spine1'}},
 {'b0552d54fcd2a0d3',5,{'hips'}},
 {'86b26185ad78f9e8',6,{'hips'}},
 {'ad4f0063842dbb63',5,{'hips'}},
 {'312c88caefdf6f9c',5,{'chest','spine1','r_hand'}},
 {'1ab1fdccc59f05da',5,{'chest','spine1','l_hand'}},
 {'e17025ba1d43acd3',6,{'spine1','hips'}}})do
 models[#models+1]={group='body',resource=item[1],count=item[2],bones=item[3]}
end
for _,item in ipairs({
 {'968211c0033dce64',9,{'attach_hand_r','attach_weapon','sling'}},
 {'416d053372c4e433',9,{'pistol','attach_hand_r'}},
 {'a9936cbe561e8180',6,{'attach_samplepouch'}},
 {'1c8764d62e12925a',10,{'attach_intelpad'}},
 -- Current mission capture: node 1 exactly matches the selected body's
 -- backpack/support anchor. Preserve the same unique-match and mesh leases.
 {'e60ae045e0090f4c',21,{'backpack'}},
 {'a8cffb316f0b5c5f',9,{'support','support_mg','attach_hand_r'}}})do
 models[#models+1]={group='equipment',resource=item[1],count=item[2],anchors=item[3],optional=true}
end
-- Repeated read-only captures on 2026-10-26: selected hand -> 40-node
-- weapon -> separate scope/magazine units. These are outfit-specific links,
-- not an equipment ownership claim based on distance or resource alone.
models[#models+1]={group='equipment',resource='27ee1ed8f6fb6356',count=10,graph=40,
 anchors={'attach_hand_r'},optional=true}
for _,item in ipairs({{'309f7e645a8d2b56',4,14,{19}},
 {'cebd25f8778bfdee',5,14,{17}}, {'b1bc2b7252ccbc03',5,12,{28,29}}})do
 models[#models+1]={group='equipment',resource=item[1],count=item[2],nodes=item[3],
  parent='27ee1ed8f6fb6356',parent_nodes=40,parent_anchors=item[4],optional=true}
end
-- Live read-only capture: these separate units attach to the current pistol's
-- internal nodes, rather than directly to a body anchor. Qualify both links.
for _,item in ipairs({{'e53e4b0c20563d21',1,5,24},{'78829731a0563576',4,13,15},
 {'f9df21c8e52cac95',4,13,12,'968211c0033dce64',43},
 {'7be1e04a7738e673',4,18,14,'968211c0033dce64',43},
 {'5c1e075cba68340b',4,12,15,'968211c0033dce64',43}})do
 models[#models+1]={group='equipment',resource=item[1],count=item[2],nodes=item[3],
  parent=item[5]or'416d053372c4e433',parent_nodes=item[6]or 32,parent_node=item[4],optional=true}
end
-- Current holstered render variant (01:20 read-only capture): local root
-- parent matches selected sling node 28, while its world root is offset.
models[#models+1]={group='equipment',resource='b80951732a5f58f4',count=10,graph=40,
 anchors={'attach_hand_r','sling','attach_weapon'},local_bind=true,optional=true}
local weapon_nodes={};for i=1,40 do weapon_nodes[i]=i end
for _,item in ipairs({{'309f7e645a8d2b56',4,14},{'66781fc94b2db0e0',5,13},{'244d6938e49be6b9',4,18}})do
 models[#models+1]={group='equipment',resource=item[1],count=item[2],nodes=item[3],parent='b80951732a5f58f4',parent_nodes=40,parent_anchors=weapon_nodes,local_bind=true,optional=true}
end
-- Any outfit: the render units bound to the selected skeleton (every probed bone the unit
-- shares with it sits on the same world matrix, which only an attached unit can), grouped
-- by the bones they carry. A cape carries cape1; arm and leg pieces a hand or the hips
-- (the body, kept in POV); a helmet the head; a torso piece the chest or spine.
M.probes={'head','chest','spine1','hips','l_hand','r_hand','cape1'}
-- A resource name as its 16 hex digits, for the log.
function M.short(name)
 local text=tostring(name);return text:match('#ID%[(%x+)%]')or text
end
-- Bones a piece carries do not say where its geometry is. Live 2026-10-29: a helmet and two
-- torso shells carried the same head, neck and shoulder bones. Their LOD meshes' bounds, in the
-- body root's frame, did not overlap: helmet centred 1.74 m up (+-0.14), shells 1.28 m (0.84 to
-- 1.72). Measured where the bones are ambiguous: a piece with the head, or one on the whole rig.
local head_up=1.58 -- Above: a helmet. Below: a torso piece reaching the neck.
local chest_up=1.05 -- A whole-rig piece centred below this is a whole suit (kept with the body).
local function whole(has)return has.chest and has.l_hand and has.r_hand and has.hips end
function M.ambiguous(has)return not has.cape1 and(whole(has)or has.head and not(has.l_hand or has.r_hand))end
-- The piece's geometry centre in the body root's frame (right, forward, up), from the bounds most
-- of its meshes share (its LODs); a proxy mesh with other bounds is outvoted. nil if unreadable.
function M.geometry(sr,unit,meshes,root)
 local H,V,B=sr.Mesh,sr.Vector3,sr.Matrix4x4
 if not(H and V and type(H.bounding_volume_components)=='function'and type(H.world_pose)=='function')then return nil end
 local ok,result=pcall(function()
  local found={}
  for i=1,math.min(meshes,8)do
   local m=sr.Unit.mesh(unit,i);local lo,hi=H.bounding_volume_components(m)
   local l={V.x(lo),V.y(lo),V.z(lo)};local h={V.x(hi),V.y(hi),V.z(hi)}
   local p={B.to_elements(H.world_pose(m))};assert(#p==12,'Mesh pose shape changed')
   local c={(l[1]+h[1])/2,(l[2]+h[2])/2,(l[3]+h[3])/2};local w={}
   for k=1,3 do w[k]=p[9+k]+c[1]*p[k]+c[2]*p[3+k]+c[3]*p[6+k]-root[9+k]end
   local b={};for a=0,2 do b[a+1]=w[1]*root[a*3+1]+w[2]*root[a*3+2]+w[3]*root[a*3+3]end
   for _,v in ipairs(b)do assert(v==v and math.abs(v)<100,'Mesh bounds invalid')end
   found[#found+1]=b
  end
  local best,votes
  for _,a in ipairs(found)do
   local n=0;for _,b in ipairs(found)do if math.abs(a[1]-b[1])<.02 and math.abs(a[2]-b[2])<.02 and math.abs(a[3]-b[3])<.02 then n=n+1 end end
   if not votes or n>votes then best,votes=a,n end
  end
  return best and{right=best[1],forward=best[2],up=best[3]}
 end)
 return ok and result or nil
end
function M.classify(has,geometry)
 if has.cape1 then return'cape'end
 -- Some armours author their chest shells on the whole rig: both arms, the legs and the head
 -- (live 2026-10-29: three such pieces and no chest-only piece, so Hide Torso hid nothing).
 if whole(has)then return geometry and geometry.up<chest_up and'body'or'torso'end
 -- One arm, or the hips without the chest: arm, leg and waist pieces. A chest piece that
 -- reaches the hips is still a torso shell.
 if has.l_hand or has.r_hand or has.hips and not has.chest then return'body'end
 if has.head then return geometry and geometry.up<head_up and'torso'or'helmet'end
 if has.chest or has.spine1 then return'torso'end
end
function M.association(sr,log,clock)
 local U,W,B=sr.Unit,sr.World,sr.Matrix4x4
 clock=clock or os.clock
 local described={}
 local function discover(frame,group,pose)
  assert(type(W.units)=='function','POV hiding is not available for this outfit')
  local started=clock()
  local units=W.units(frame.world);assert(type(units)=='table','POV outfit discovery unavailable')
  local result,scanned,bound,seen={},0,0,{}
  for key,unit in pairs(units)do
   scanned=scanned+1
   assert(type(key)=='number'and key%1==0 and key>=1 and scanned<=16384,'POV outfit discovery exceeds bound')
   if unit~=frame.root_handle and U.alive(unit)and U.world(unit)==frame.world then
    local meshes=U.num_meshes(unit)
    if type(meshes)=='number'and meshes%1==0 and meshes>0 and meshes<=128 then
     local has,named,matched={},0,0
     for _,name in ipairs(M.probes)do if U.has_node(unit,name)then
      has[name]=true
      if U.has_node(frame.root_handle,name)then
       named=named+1
       local a,b=pose(unit,U.node(unit,name)),pose(frame.root_handle,U.node(frame.root_handle,name));local same=true
       for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then same=false;break end end
       if same then matched=matched+1 end
      end
     end end
     if matched>0 and matched==named then
      bound=bound+1
      local flags={};for _,name in ipairs(M.probes)do if has[name]then flags[#flags+1]=name end end
      local geometry=M.ambiguous(has)and M.geometry(sr,unit,meshes,pose(frame.root_handle,1))or nil
      local class=M.classify(has,geometry)
      local short=M.short(U.resource_name(unit))
      seen[#seen+1]=short..'['..table.concat(flags,'+')..(geometry and string.format('@%.2f',geometry.up)or'')..']'
      -- Every skeleton bone the piece carries, once per resource: evidence for classifying
      -- pieces the probes cannot tell apart (an armour collar and a helmet both carry the head).
      if log and type(frame.rig_nodes)=='table'and not described[short]then
       described[short]=true;local carried={}
       for _,node in ipairs(frame.rig_nodes)do
        if type(node.name)=='string'and U.has_node(unit,node.name)then carried[#carried+1]=node.name end
       end
       log('POV outfit piece: '..short..' meshes='..meshes..' class='..tostring(class)..' bones='..table.concat(carried,'+'))
       -- Where each mesh's bounds sit in the body's frame (right, forward, up from the root), and
       -- their half sizes: evidence for a geometric torso/helmet rule. Read-only.
       local ok,why=pcall(function()
        local H,V=sr.Mesh,sr.Vector3;local r=pose(frame.root_handle,1);local parts={}
        for i=1,math.min(meshes,8)do
         local m=U.mesh(unit,i);local lo,hi=H.bounding_volume_components(m)
         local l={V.x(lo),V.y(lo),V.z(lo)};local h={V.x(hi),V.y(hi),V.z(hi)}
         local p={B.to_elements(H.world_pose(m))};assert(#p==12,'Mesh pose shape changed')
         local c={(l[1]+h[1])/2,(l[2]+h[2])/2,(l[3]+h[3])/2};local w={}
         for k=1,3 do w[k]=p[9+k]+c[1]*p[k]+c[2]*p[3+k]+c[3]*p[6+k]-r[9+k]end
         local b={};for a=0,2 do b[a+1]=w[1]*r[a*3+1]+w[2]*r[a*3+2]+w[3]*r[a*3+3]end
         parts[#parts+1]=string.format('m%d=%s c=%.2f,%.2f,%.2f h=%.2f,%.2f,%.2f',i,tostring(H.name(m)),b[1],b[2],b[3],
          (h[1]-l[1])/2,(h[2]-l[2])/2,(h[3]-l[3])/2)
        end
        return table.concat(parts,' ')
       end)
       log('POV outfit piece geometry: '..short..' '..tostring(why)..(ok and''or' (unavailable)'))
      end
      if class==group then
       assert(#result<32,'POV outfit discovery exceeds bound')
       local indices={};for index=1,meshes do indices[index]=index end
       result[#result+1]={unit=unit,world=frame.world,resource=tostring(U.resource_name(unit)),indices=indices}
      end
     end
    end
   end
  end
  if log then
   local names={};for _,row in ipairs(result)do names[#names+1]=M.short(row.resource)..'x'..#row.indices end
   log(string.format('POV outfit discovery: %s=%d of %d bound units (%s); bound: %s; scanned=%d ms=%.3f',group,#result,bound,table.concat(names,','),table.concat(seen,' '),scanned,(clock()-started)*1000))
  end
  -- No unit bound at all: the outfit was caught mid-update (the frame a freeze releases the
  -- skeleton). The caller retries on later frames instead of hiding nothing.
  result.unsettled=bound==0
  return result
 end
 local function read_pose(u,node)
  local p={B.to_elements(U.world_pose(u,node))};assert(#p==12,'POV pose shape changed')
  for _,v in ipairs(p)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'POV pose invalid')end
  return p
 end
 local function inventory(value)
  assert(type(value)=='table','POV outfit lookup unavailable')
  local result={};local count=0
  -- Native inventories can have holes. ipairs would silently omit later units,
  -- including a second matching owner that must make the association ambiguous.
  for key,unit in pairs(value)do
   count=count+1
   assert(count<=16,'POV outfit lookup exceeds bound')
   assert(type(key)=='number'and key>=1 and key<math.huge and key%1==0,'POV outfit inventory key invalid')
   result[count]=unit
  end
  return result
 end
 local function rows(frame,group)
  assert(frame and frame.explicit_subject and frame.root_handle and frame.world and frame.identity,'Select a Helldiver first')
  assert(U.alive(frame.root_handle)and U.world(frame.root_handle)==frame.world,'POV subject retired')
  -- Scalar copies are shared only within this uninterrupted association plan.
  -- No cache survives a transition, subject change or callback boundary.
  local poses={}
  local function pose(unit,node)
   local nodes=poses[unit]
   if not nodes then nodes={};poses[unit]=nodes end
   if not nodes[node]then nodes[node]=read_pose(unit,node)end
   return nodes[node]
  end
  local function parent_pose(unit)
   if not(type(U.local_pose)=='function'and type(B.inverse)=='function'and type(B.multiply)=='function'and type(B.from_elements)=='function')then return nil end
   local a={B.to_elements(U.local_pose(unit,1))};assert(#a==12,'Equipment local pose shape changed')
   for _,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Equipment local pose invalid')end
   local det=a[1]*(a[5]*a[9]-a[6]*a[8])-a[2]*(a[4]*a[9]-a[6]*a[7])+a[3]*(a[4]*a[8]-a[5]*a[7]);assert(math.abs(det)>.0001,'Equipment local pose singular')
   local p={B.to_elements(B.multiply(B.inverse(B.from_elements(unpack(a))),B.from_elements(unpack(pose(unit,1)))))}
   assert(#p==12,'Equipment parent shape changed');for _,v in ipairs(p)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Equipment parent invalid')end
   return p
  end
  local result={};local parents={}
  for _,model in ipairs(models)do if model.group==group then
   local candidates=inventory(W.units_by_resource(frame.world,sr.IdString64.from_hex(model.resource)))
   local found,slots,seen_match={},{},{}
   for _,unit in ipairs(candidates)do
    if unit~=frame.root_handle and U.alive(unit)and U.world(unit)==frame.world then
     local matches=true;local matched_nodes
     if model.parent then
      matches=false
      local parent=parents[model.parent]
      if parent then
       assert(U.num_scene_graph_items(parent)==model.parent_nodes,'POV equipment parent graph changed')
       assert(U.num_scene_graph_items(unit)==model.nodes,'POV accessory graph changed')
       local a=pose(unit,1);local derived=model.local_bind and parent_pose(unit);matches=false;matched_nodes={}
       for _,node in ipairs(model.parent_anchors or{model.parent_node})do
        local b=pose(parent,node);local same=true
        for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then same=false;break end end
        if not same and derived then same=true;for i=1,12 do if math.abs(derived[i]-b[i])>1e-4 then same=false;break end end end
        if same then matches=true;matched_nodes[#matched_nodes+1]=node end
       end
      end
     elseif model.anchors then
      matches=false
      local a=pose(unit,1);local derived=model.local_bind and parent_pose(unit)
      for _,name in ipairs(model.anchors)do if U.has_node(frame.root_handle,name)then
       local b=pose(frame.root_handle,U.node(frame.root_handle,name));local equal=true
       for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then equal=false;break end end
       if not equal and derived then equal=true;for i=1,12 do if math.abs(derived[i]-b[i])>1e-4 then equal=false;break end end end
       if equal then matches=true;break end
      end end
     else
      for _,name in ipairs(model.bones)do
       if not U.has_node(unit,name)or not U.has_node(frame.root_handle,name)then matches=false;break end
       local a,b=pose(unit,U.node(unit,name)),pose(frame.root_handle,U.node(frame.root_handle,name))
       for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then matches=false;break end end
       if not matches then break end
      end
     end
     if matches then
      if model.parent_anchors then
       assert(not seen_match[unit],'POV accessory inventory contains a duplicate')
       for _,node in ipairs(matched_nodes)do
        assert(not slots[node]or slots[node]==unit,'POV accessory slot association is ambiguous')
        slots[node]=unit
       end
      else assert(#found==0,'POV outfit association is ambiguous')end
      seen_match[unit]=true;found[#found+1]=unit
     end
    end
   end
   -- Another outfit than the one this catalog was verified with: discover it instead.
   if #found==0 and not model.optional then return discover(frame,group,pose)end
   for _,found in ipairs(found)do
    if model.graph then assert(U.num_scene_graph_items(found)==model.graph,'POV equipment graph changed')end
    local count=model.count or #model.names
    assert(U.num_meshes(found)==count,'POV outfit mesh layout changed')
    local indices={}
    for index=1,count do
     if model.names then assert(sr.Mesh.name(U.mesh(found,index))==model.names[index],'POV outfit mesh identity changed')end
     indices[index]=index
    end
    result[#result+1]={unit=found,world=frame.world,resource=tostring(U.resource_name(found)),indices=indices}
    if model.anchors then parents[model.resource]=found end
   end
  end end
  return result
 end
 return rows
end
-- Discover whole render units from the selected skeleton, including resources
-- absent from the outfit catalog. Snapshot once per explicit Full Hide; process
-- at most 16 units / 2 ms per callback, then stay idle. Never hide by proximity.
function M.skeleton_scan(sr,frame,parents,clock,log,weapons_only)
 local U,W,B=sr.Unit,sr.World,sr.Matrix4x4
 local state={world=frame.world,root=frame.root_handle,identity=frame.identity,rig=frame.rig_nodes,
  parents=parents or{},rows={},new_rows={},seen={},missed={},max_ms=0,round=1};local self={}
 clock=clock or os.clock
 local function pose(unit,node)
  local a={B.to_elements(U.world_pose(unit,node))};assert(#a==12,'Full hide pose shape changed')
  for _,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Full hide pose invalid')end
  return a
 end
 local function same(a,b)for i=1,12 do if math.abs(a[i]-b[i])>1e-4 then return false end end;return true end
 function self.take_rows()local rows=state.new_rows;state.new_rows={};return rows end
 function self.tick(current)
  if self.done then return self.rows end
  local started=clock();local s=state
  assert(current and current.identity==s.identity and current.root_handle==s.root and current.world==s.world,'Full hide selection changed')
  assert(U.alive(s.root)and U.world(s.root)==s.world,'Full hide subject retired')
  if not s.units then
   local units=W.units(s.world);assert(type(units)=='table','Full hide inventory unavailable')
   s.units={};local seen={}
   for key,unit in pairs(units)do
    assert(type(key)=='number'and key%1==0 and key>=1 and #s.units<16384,'Full hide inventory exceeds bound')
    if not seen[unit]then seen[unit]=true;s.units[#s.units+1]=unit end
   end
   s.cursor=1;s.seen[s.root]=true
   for _,row in ipairs(s.parents)do s.seen[row.unit]=true end
   return nil
  end
  -- All matrices below are scalar copies local to this callback. Getter scratch
  -- objects cannot outlive a frame; moving subjects therefore use current poses.
  local anchors={};local body=pose(s.root,1)
  for index,node in ipairs(s.rig)do if index>5 then
   anchors[#anchors+1]={name=node.name,pose=pose(s.root,index)}
  end end
  assert(#anchors>0,'Full hide skeleton unavailable')
  local function parent(row)
   assert(U.alive(row.unit)and U.world(row.unit)==s.world and tostring(U.resource_name(row.unit))==row.resource,'Full hide attachment retired')
   local count=U.num_scene_graph_items(row.unit)
   assert(type(count)=='number'and count%1==0 and count>=1 and count<=256,'Full hide attachment graph changed')
   for node=1,count do
    local a=pose(row.unit,node);local distance=0
    for i=10,12 do distance=distance+(a[i]-body[i])^2 end
    if distance<36 then anchors[#anchors+1]={pose=a}end
   end
  end
  for _,row in ipairs(s.parents)do parent(row)end
  for _,row in ipairs(s.rows)do if row.parent_candidate then parent(row)end end
  assert(#anchors<=4096,'Full hide anchor budget exceeded')
  local work=0
  while s.cursor<=#s.units and work<16 and clock()-started<.002 do
   local unit=s.units[s.cursor];s.cursor=s.cursor+1;work=work+1
   if not s.seen[unit]and U.alive(unit)and U.world(unit)==s.world then
    local count=U.num_meshes(unit)
    assert(type(count)=='number'and count%1==0 and count>=0 and count<=128,'Full hide mesh count changed')
    if count>0 then
     local matches,names,root_match=0,0,false;local root=pose(unit,1)
     for _,a in ipairs(anchors)do
      if same(root,a.pose)then root_match=true end
      if a.name and U.has_node(unit,a.name)then
       names=names+1;if same(pose(unit,U.node(unit,a.name)),a.pose)then matches=matches+1 end
      end
     end
     -- A holster can apply an authored offset to the weapon root. Recover
     -- its parent frame from local * parent = world before comparing every
     -- selected bone. Do not move the unit or assume it still uses the hand.
     local bind_match,derived_pose=false,nil
     if not root_match and type(U.local_pose)=='function'and type(B.inverse)=='function'and type(B.multiply)=='function'and type(B.from_elements)=='function'then
      local ok,derived=pcall(function()
       local a={B.to_elements(U.local_pose(unit,1))};assert(#a==12,'Weapon local pose shape changed')
       for _,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Weapon local pose invalid')end
       local det=a[1]*(a[5]*a[9]-a[6]*a[8])-a[2]*(a[4]*a[9]-a[6]*a[7])+a[3]*(a[4]*a[8]-a[5]*a[7])
       assert(math.abs(det)>.0001,'Weapon local pose singular')
       local result={B.to_elements(B.multiply(B.inverse(B.from_elements(unpack(a))),B.from_elements(unpack(root))))}
       assert(#result==12,'Weapon parent pose shape changed')
       for _,v in ipairs(result)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Weapon parent pose invalid')end
       return result
      end)
      if ok then derived_pose=derived;for _,a in ipairs(anchors)do if same(derived,a.pose)then bind_match=true;break end end end
     end
     if (not weapons_only or names<2)and(root_match or bind_match or matches>=2 and matches==names)then
      assert(#s.rows<48,'Full hide additional-unit budget exceeded')
      local indices={};for i=1,count do indices[i]=i end
      local row={unit=unit,world=s.world,resource=tostring(U.resource_name(unit)),indices=indices,parent_candidate=(root_match or bind_match)and names<2}
      s.rows[#s.rows+1]=row;s.new_rows[#s.new_rows+1]=row;s.seen[unit]=true;s.added=true
      if log then log('Full hide skeleton match: resource='..row.resource..' meshes='..count..' bones='..matches..' root='..tostring(root_match)..' local_bind='..tostring(bind_match))end
     elseif weapons_only and log and names<2 then
      -- Evidence for weapons left visible: a meshed unit within 3 m that no anchor matched,
      -- with how far its root (and holster-derived parent) is from the closest anchor.
      local d2=(root[10]-body[10])^2+(root[11]-body[11])^2+(root[12]-body[12])^2
      local resource=M.short(U.resource_name(unit))
      if d2<9 and not s.missed[resource]then
       s.missed[resource]=true
       local function nearest(p)
        if not p then return'none'end
        local best,label=math.huge,'?'
        for _,a in ipairs(anchors)do
         local e=0;for i=1,12 do e=math.max(e,math.abs(p[i]-a.pose[i]))end
         if e<best then best,label=e,a.name or'attachment'end
        end
        return string.format('%.4f@%s',best,label)
       end
       log(string.format('Weapon scan near miss: resource=%s meshes=%d graph=%s distance_m=%.2f root=%s bind=%s bones=%d',resource,count,
        tostring(U.num_scene_graph_items(unit)),math.sqrt(d2),nearest(root),nearest(derived_pose),names))
      end
     end
    end
   end
  end
  local elapsed=(clock()-started)*1000;s.max_ms=math.max(s.max_ms,elapsed)
  if s.cursor>#s.units then
   -- Newly found weapons can own separate scopes, magazines and other units.
   -- Reuse the same inventory, bounded to four nesting levels; no new snapshot.
   if s.added and s.round<4 then s.round=s.round+1;s.cursor=1;s.added=false
   else
    self.done=true;self.rows=s.rows
    if log then log('Full hide skeleton inventory: units='..#s.units..' additional_units='..#s.rows..' rounds='..s.round..' max_step_ms='..string.format('%.3f',s.max_ms))end
    return s.rows
   end
  end
 end
 return self
end
function M.new(sr,selected,lease_factory,log,clock)
 local U,W,B=sr.Unit,sr.World,sr.Matrix4x4;local groups={'helmet','torso','cape','body','equipment'};local pov_groups={'helmet','torso','cape'};local leases={}
 for _,group in ipairs(groups)do leases[group]=lease_factory.new(sr)end
 local desired,dirty,owners,unsettled={},{},{},{};local requested={};local full=false;local scan;local equipment_settle=0;local extra=lease_factory.new(sr)
 local self={status='Helmet, torso and cape hiding off',max_apply_ms=0};clock=clock or os.clock
 local function count_owned()local n=extra.count();for _,group in ipairs(groups)do n=n+leases[group].count()end;return n end
 local function report(started,ok,why)
  local elapsed=(clock()-started)*1000;self.max_apply_ms=math.max(self.max_apply_ms,elapsed)
  if log then log('POV visibility: '..self.status..'; transition_ms='..string.format('%.3f',elapsed)..'; owned_meshes='..count_owned()..'; max_equipment_render_ms='..string.format('%.3f',self.max_maintain_ms or 0))end
  return ok,why
 end
 local rows=M.association(sr,log,clock)
 function self.queue(group,value)
  -- Boolean form retained for internal all-group callers.
  if type(group)=='boolean'then for _,name in ipairs(pov_groups)do self.queue(name,group)end;return end
  assert(leases[group]and type(value)=='boolean','POV visibility expects a group and Boolean')
  requested[group]=value
  local effective=value or full
  if (desired[group]==true)~=effective then desired[group]=effective;dirty[group]=true end
 end
 function self.queue_weapons(value)
  if requested.equipment~=value then equipment_settle=value and 4 or 0 end
  self.queue('equipment',value)
 end
 function self.queue_player(value)
  assert(type(value)=='boolean','Full hiding expects a Boolean')
  if full~=value then scan=nil;equipment_settle=value and 4 or 0 end
  full=value
  for _,group in ipairs(groups)do
   local effective=full or requested[group]==true
   if (desired[group]==true)~=effective then desired[group]=effective;dirty[group]=true end
  end
 end
 function self.selection_changed()
  if not(desired.helmet or desired.torso or desired.cape or desired.equipment)then return end
  local ok,frame=pcall(selected)
  for _,group in ipairs(groups)do
   if desired[group]and(not ok or not frame or frame.identity~=owners[group])then dirty[group]=true end
  end
 end
 function self.release()
  desired,dirty,requested={},{},{};full=false;scan=nil
  local count=count_owned()
  local started=count>0 and clock();local success,reason=extra.release()
  for _,group in ipairs(groups)do
   local ok,why=leases[group].release()
   if ok then owners[group]=nil else success=false;reason=why end
  end
  self.status=success and'Helmet, torso and cape hiding off'or('POV restoration pending: '..tostring(reason))
  if started then return report(started,success,reason)end
  return success,reason
 end
 function self.reassert()
  local started=clock()
  local ok,why=pcall(function()
   local frame=selected()
   local accepted,reason=extra.reassert();assert(accepted,reason)
   for _,group in ipairs(groups)do if desired[group]then
    assert(frame and frame.identity==owners[group],'POV subject changed during ADS transition')
    local accepted,reason=leases[group].reassert();assert(accepted,reason)
   end end
  end)
  return report(started,ok,why)
 end
 -- The stock equipment renderer may restore visibility after update. Keep
 -- only acquired equipment meshes hidden at the existing after-game callback;
 -- no discovery, transforms or unconditional setters run here.
 function self.maintain()
  if not(desired.equipment or full)then return true end
  local started=clock()
  if equipment_settle>0 then
   equipment_settle=equipment_settle-1
   local called,plan=pcall(rows,selected(),'equipment')
   if not called then return false,plan end
   local accepted,why=leases.equipment.append(plan);if not accepted then return false,why end
  end
  local ok,why=leases.equipment.reassert()
  if ok then ok,why=extra.reassert()end
  local elapsed=(clock()-started)*1000
  self.max_maintain_ms=math.max(self.max_maintain_ms or 0,elapsed)
  return ok,why
 end
 function self.flush()
  if not next(dirty)then
   if not scan then return true end
   local ok,result=pcall(scan.tick,selected())
   if not ok then scan=nil;self.status='Full hide discovery: '..tostring(result);if log then log(self.status)end;return false,self.status end
   local new_rows=scan.take_rows()
   if #new_rows>0 then
    local hidden,why=extra.append(new_rows)
    if log then log('Full hide additional meshes: '..extra.count()..'; accepted='..tostring(hidden)..'; '..tostring(why))end
    if not hidden then scan=nil;return false,why end
   end
   if result then scan=nil end
   return true
  end
  local started=clock()
  local ok,reason=pcall(function()
   local restored,issue=extra.release();assert(restored,issue);scan=nil
   local plans,identities={},{}
   for _,group in ipairs(groups)do if dirty[group]and desired[group]then
    local frame=selected();plans[group]=rows(frame,group);identities[group]=frame.identity
   end end
   if (full or requested.equipment)and type(W.units)=='function'then
    local frame=selected()
    if frame and type(frame.rig_nodes)=='table'then
     local parents={}
     for _,row in ipairs(plans.equipment or{})do parents[#parents+1]=row end
     scan=M.skeleton_scan(sr,frame,parents,clock,log,not full)
    end
   end
   for _,group in ipairs(groups)do if dirty[group]then
    dirty[group]=nil
    local restored,why=leases[group].release();assert(restored,why);owners[group]=nil
    if desired[group]then
     local hidden,issue=leases[group].hide(plans[group]);assert(hidden,issue);owners[group]=identities[group]
     if plans[group].unsettled and(unsettled[group]or 0)<60 then unsettled[group]=(unsettled[group]or 0)+1;dirty[group]=true
     else
      if plans[group].unsettled and log then log('POV outfit discovery: '..group..' found no attached pieces in 60 frames')end
      unsettled[group]=nil
     end
    end
   end end
  end)
  if not ok then
   local restored,why=self.release()
   self.status=tostring(reason)..(restored and''or'; '..tostring(why))
   return report(started,false,self.status)
  end
  local active={};for _,group in ipairs(groups)do if desired[group]then active[#active+1]=group end end
  self.status=#active==0 and'Helmet, torso and cape hiding off'or('Hidden: '..table.concat(active,', '))
  return report(started,true)
 end
 return self
end
return M

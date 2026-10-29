-- SOURCE ONLY: selected photographic subjects, never authoritative local avatars.
-- new(sr, policy) returns nil unless an explicit current-session writer receipt
-- authorizes synchronous Unit local-pose/mode/update and exact12-scalar matrix roundtrip.
-- Export presence and the qualified read-only probes do not authorize writes.
-- preview(sr, policy) is unqualified and requires per-mutation authorization;
-- a separate finite driver owns selection, true-zero, focus, budget and cleanup.
-- No ticks, polling, Math boxes, Unit IDs, engine hooks or automatic arming.
local M={}
function M.choose_tracking(nearby)
 table.sort(nearby,function(a,b)return a.distance<b.distance end)
 if nearby[1]and nearby[1].distance<=6 and(not nearby[2]or nearby[2].distance-nearby[1].distance>=.75)then
  return nearby[1].target,string.format('nearest head %.2f m from gameplay camera',nearby[1].distance)
 end
end
local resource='4d1c334d294dfa97'
local function pack(...)return{n=select('#',...),...}end
-- Diagnostics keep exact slot counts/scalars, never unexpected Math/ID userdata.
-- The synchronous failure return still forwards the original native error.
local function receipt(values)
 local out={n=values.n,types={}}
 for i=1,values.n do local value=values[i];local kind=type(value);out.types[i]=kind
  if kind=='number'or kind=='string'or kind=='boolean'then out[i]=value end
 end
 return out
end
local function check(ok,why)if not ok then error(why,0)end end
local function finite(value)return type(value)=='number'and value==value and math.abs(value)<1e8 end
local function vector(value,n)
 check(type(value)=='table','Numeric subject component unavailable')
 local result={};for i=1,n do check(finite(value[i]),'Invalid numeric subject component');result[i]=value[i]end;return result
end
local function pose_vector(value)
 check(type(value)=='table'and getmetatable(value)==nil,'Numeric matrix pose unavailable')
 local count=0;for key in pairs(value)do
  count=count+1;check(count<=12 and type(key)=='number'and key%1==0 and key>=1 and key<=12,'Matrix pose must be dense12')
 end
 check(count==12,'Matrix pose must contain12 scalars');return vector(value,12)
end
local function sign(q)
 local negative=q[4]<0
 if q[4]==0 then for i=1,3 do if q[i]~=0 then negative=q[i]<0;break end end end
 if negative then for i=1,4 do q[i]=-q[i]end end
 return q
end
local function copy(value,anchor)
 check(type(value)=='table','Numeric subject node unavailable')
 local out={p=vector(value.p,3),q=vector(value.q,4),s=vector(value.s,3)}
 if not anchor then sign(out.q)end
 local norm=0;for i=1,4 do norm=norm+out.q[i]^2 end
 check(math.abs(norm-1)<.002,'Subject quaternion is not normalized')
 if not anchor then for i=1,3 do check(math.abs(out.s[i]-1)<.002,'Subject scale is not unit scale')end end
 if value.pose~=nil then out.pose=pose_vector(value.pose)end
 return out
end
local function equal(a,b)
 if type(a.pose)~='table'or type(b.pose)~='table'then return false end
 for i=1,12 do if a.pose[i]~=b.pose[i]then return false end end;return true
end
local function pose_mismatch(index,expected_mode,before,target,observed)
 local out={index=index,mode=expected_mode,before=vector(before.pose,12),target=vector(target.pose,12),
  observed=vector(observed.pose,12),delta={},max_abs_delta=0}
 for i=1,12 do local delta=observed.pose[i]-target.pose[i];out.delta[i]=delta
  out.max_abs_delta=math.max(out.max_abs_delta,math.abs(delta))
  if delta~=0 and not out.first_scalar then out.first_scalar=i end
 end
 return out
end
local function mode(value)return type(value)=='string'and #value>0 and #value<=128 and not value:find('[%z\1-\31\127]')end
local function factory(sr,policy,preview)
 local qualified=type(policy)=='table'and policy.qualified==true and policy.contract=='unit-pose-sync-v1'and
  type(policy.qualification)=='string'and #policy.qualification>0 and #policy.qualification<=128
 local trial=type(policy)=='table'and policy.contract=='unit-pose-preview-v1'and type(policy.authorize)=='function'and
  type(policy.trial_id)=='string'and #policy.trial_id>0 and #policy.trial_id<=128 and not policy.trial_id:find('[%z\1-\31\127]')
 if type(policy)~='table'or type(policy.session)~='userdata'or(preview and not trial)or(not preview and not qualified)then
  return nil,'Selected-subject native writes are not qualified for this session'
 end
 if type(sr)~='table'then return nil,'Engine namespace unavailable'end
 local A,W,U,I,V,Q,N,B=sr.Application,sr.World,sr.Unit,sr.IdString64,sr.Vector3,sr.Quaternion,sr.Network,sr.Matrix4x4
 local namespaces={Application=A,World=W,Unit=U,IdString64=I,Vector3=V,Quaternion=Q,Network=N,Matrix4x4=B}
 local bindings={}
 for _,group in ipairs({{A,'main_world'},{W,'units_by_resource','update_unit'},
  {U,'alive','world','resource_name','num_scene_graph_items','animation_bone_mode','scene_graph_parent','has_node','node',
   'local_pose','set_local_pose','set_animation_bone_mode'},
  {I,'from_hex','equal'},{V,'x','y','z'},{Q,'from_elements','to_elements'},{N,'game_session'},
  {B,'from_elements','to_elements','from_quaternion_position','set_scale','translation','rotation','scale'}})do
  if type(group[1])~='table'then return nil,'Required native namespace unavailable'end
  for i=2,#group do
   local fn=rawget(group[1],group[i]);if type(fn)~='function'then return nil,'Required native export unavailable: '..group[i]end
   bindings[#bindings+1]={group[1],group[i],fn}
  end
 end
 local vector_meta=getmetatable(V);local vector_call=type(vector_meta)=='table'and rawget(vector_meta,'__call')
 if type(vector_call)~='function'then return nil,'Qualified Vector3 constructor unavailable'end
 local session=policy.session;local authorizer=preview and policy.authorize;local records={};local generation=0;local retired_tag={}
 local pending=0
 local status={qualified=not preview,preview=preview,qualification=not preview and policy.qualification or nil,
  trial_id=preview and policy.trial_id or nil,capability='explicit_photographic_subject',player_authority=false,pending=0,pose_scalars=12,contract=preview and'unit-pose-preview-v1'or'unit-pose-sync-v1'}
 local self={version=1}
 local function ready()
  for name,value in pairs(namespaces)do check(rawget(sr,name)==value,'Native namespace binding changed')end
  check(getmetatable(V)==vector_meta and rawget(vector_meta,'__call')==vector_call,'Vector3 constructor binding changed')
  for _,entry in ipairs(bindings)do check(rawget(entry[1],entry[2])==entry[3],'Native function binding changed: '..entry[2])end
 end
 local function authorize(operation,target)
  if not preview then return end
  local values=pack(pcall(authorizer,operation,target))
  check(values[1]and values[2]==true,values[1]and(values[3]or'Preview mutation is not authorized')or values[2])
 end
 local function one(values,kind,label)
  check(values.n==1 and type(values[1])==kind,label..' return shape changed');return values[1]
 end
 local function num(fn,...)
  local value=one(pack(fn(...)),'number','Numeric native getter');check(finite(value),'Nonfinite native number');return value
 end
 local function xyz(value)
  check(type(value)=='userdata','Vector3 getter returned a non-userdata')
  return{num(V.x,value),num(V.y,value),num(V.z,value)}
 end
 local function quaternion(value,anchor)
  check(type(value)=='userdata','Quaternion getter returned a non-userdata')
  local values=pack(Q.to_elements(value));check(values.n==4,'Quaternion scalar return count changed')
  local out=vector(values,4);return anchor and out or sign(out)
 end
 local function matrix_values(matrix)
  check(type(matrix)=='userdata','Matrix getter returned a non-userdata')
  local values=pack(B.to_elements(matrix));check(values.n==12,'Matrix scalar return count changed')
  return vector(values,12)
 end
 local function matrix_from(values)
  values=pose_vector(values)
  local matrix=one(pack(B.from_elements(unpack(values))),'userdata','Matrix4x4.from_elements')
  local actual=matrix_values(matrix)
  for i=1,12 do check(actual[i]==values[i],'Raw matrix constructor changed numeric pose')end
  return matrix
 end
 local function matrix_node(matrix,anchor)
  local pose=matrix_values(matrix)
  return copy({p=xyz(one(pack(B.translation(matrix)),'userdata','Matrix4x4.translation')),
   q=quaternion(one(pack(B.rotation(matrix)),'userdata','Matrix4x4.rotation'),anchor),
   s=xyz(one(pack(B.scale(matrix)),'userdata','Matrix4x4.scale')),pose=pose},anchor)
 end
 local function read_node(unit,index,anchor)
  return matrix_node(one(pack(U.local_pose(unit,index)),'userdata','Unit.local_pose'),anchor)
 end
 local function math_node(value)
  value=copy(value)
  if value.pose then return matrix_node(matrix_from(value.pose))end
  local rotation=one(pack(Q.from_elements(unpack(value.q))),'userdata','Quaternion.from_elements')
  local position=V(unpack(value.p));check(type(position)=='userdata','Vector3 constructor returned invalid userdata')
  local matrix=one(pack(B.from_quaternion_position(rotation,position)),'userdata','Matrix4x4.from_quaternion_position')
  local scale=V(unpack(value.s));check(type(scale)=='userdata','Vector3 constructor returned invalid userdata')
  check(pack(B.set_scale(matrix,scale)).n==0,'Matrix4x4.set_scale return shape changed')
  return matrix_node(matrix)
 end
 local function rig_copy(rig)
  check(type(rig)=='table'and rig.resource==resource and rig.node_count==107 and type(rig.nodes)=='table','Unsupported subject rig')
  local result={}
  for i=1,107 do local node=rig.nodes[i]
   check(type(node)=='table'and type(node.parent)=='number'and node.parent%1==0 and node.parent>=0 and node.parent<i,'Invalid authored subject parent')
   check(node.name==nil or type(node.name)=='string'and #node.name>0 and #node.name<=128,'Invalid authored subject name')
   result[i]={parent=node.parent,name=node.name}
  end
  return result
 end
 local function record(target,rig)
  ready();local r=records[target]
  check(r and getmetatable(target)==nil and target.identity==r.identity and target.resource==resource and target.node_count==107 and
   target.label==r.label and rig==r.rig and rig.resource==resource and rig.node_count==107,'Private selected-subject identity unavailable')
  if r.retired then error({tag=retired_tag,reason='Selected subject retired'},0)end
  return r
 end
 local function drop(r)
  if not r.retired then
   for _,entry in pairs(r.nodes)do if entry.attempt then pending=pending-1 end end
   if r.mode and r.mode.attempt then pending=pending-1 end
   r.nodes={};r.mode=nil;r.scene_dirty=false;r.refresh_expected=nil;r.refresh_nodes={};r.retired=true;status.pending=pending
  end
 end
 local function retire(r,why)drop(r);error({tag=retired_tag,reason=why},0)end
 local function lifetime(r)
  check(not r.retired,'Selected subject is retired')
  if one(pack(N.game_session()),'userdata','Game session')~=session then retire(r,'Qualified session changed')end
  if one(pack(A.main_world()),'userdata','Main world')~=r.world then retire(r,'Selected-subject world retired')end
  if not one(pack(U.alive(r.unit)),'boolean','Unit.alive')then retire(r,'Selected subject retired')end
  check(one(pack(U.world(r.unit)),'userdata','Unit.world')==r.world,'Selected subject moved to another world')
  local expected=one(pack(I.from_hex(resource)),'userdata','IdString64.from_hex')
  local actual=one(pack(U.resource_name(r.unit)),'userdata','Unit.resource_name')
  check(one(pack(I.equal(actual,expected)),'boolean','IdString64.equal'),'Selected subject resource changed')
  check(num(U.num_scene_graph_items,r.unit)==107,'Selected subject node count changed')
 end
 local function topology(r,index)
  check(type(index)=='number'and index%1==0 and index>=1 and index<=107,'Subject node outside rig')
  local node=r.topology[index];local values=pack(U.scene_graph_parent(r.unit,index))
  -- Current root1 is qualified to return zero values; other nodes return one integer.
  check((node.parent==0 and(values.n==0 or values.n==1 and(values[1]==nil or values[1]==0)))or
   (values.n==1 and type(values[1])=='number'and values[1]==node.parent),'Subject parent topology changed')
  if node.name then
   check(one(pack(U.has_node(r.unit,node.name)),'boolean','Unit.has_node'),'Subject node name missing')
   check(num(U.node,r.unit,node.name)==index,'Subject node-name index changed')
  end
 end
 local function current(r,index,expected_mode)
  ready();lifetime(r);if index then topology(r,index)end
  local value=one(pack(U.animation_bone_mode(r.unit)),'string','Unit.animation_bone_mode')
  check(mode(value),'Unsupported subject bone mode')
  if expected_mode then check(value==expected_mode,'Subject bone mode changed')end
  return value,index and read_node(r.unit,index)or nil
 end
 local function result(fn,...)
  local values=pack(pcall(fn,...))
  if not values[1]then
   local why=values[2];if type(why)=='table'and why.tag==retired_tag then return nil,why.reason end
   return nil,why
  end
  return unpack(values,2,values.n)
 end
 local function begin_attempt(entry,before,target,expected_mode)
  if not entry.attempt then pending=pending+1 end
  entry.attempt={before=copy(before),target=copy(target),mode=expected_mode}
  status.pending=pending;return entry.attempt
 end
 local function clear_attempt(entry)
  if entry.attempt then entry.attempt=nil;pending=pending-1;status.pending=pending end
 end
 local function known(entry,value)
  local attempt=entry.attempt
  return attempt and(equal(value,attempt.before)or equal(value,attempt.target)or attempt.approved and equal(value,attempt.approved))
 end
 local function acknowledged_mode(r,before,value)
  for _,entry in pairs(r.nodes)do
   if entry.attempt and entry.attempt.mode==before then entry.attempt.mode=value end
  end
 end
 -- Reuse the maintained local-avatar cape attachment solver. Discovery of
 -- photographic subjects grants no ownership of another player's attachments.
 local cape_reader=policy.cape_reader
 local selected_cape=policy.selected_cape
 local cape=type(policy.cape_factory)=='function'and cape_reader and policy.cape_factory(sr,cape_reader,function(frame,owned)
  local valid,why=cape_reader.pose_valid(frame,owned);check(valid==true,why or'Cape body owner unavailable')
 end)or nil
 local function capture_cape(r)
  if r.cape_capture_done then return end
  if selected_cape then
   r.cape_capture_done=true
   local frame={explicit_subject=true,identity=r.identity,root_handle=r.unit,world=r.world}
   local ok,lease=pcall(selected_cape.capture,frame)
   status.cape=ok and #lease.meshes or tostring(lease)
   if ok then r.cape={frame=frame,selected=lease}end
   if type(policy.log)=='function'then pcall(policy.log,'Authored pose cape capture: '..tostring(status.cape))end
   return
  end
  if not cape then return end
  r.cape_capture_done=true
  local ok,frame=pcall(cape_reader.pose_frame)
  if not ok or frame.root_handle~=r.unit or frame.world~=r.world then status.cape='No proven local cape owner';return end
  local records=cape.capture(frame)
  status.cape=records and #records or 'Cape topology unavailable'
  if records and #records>0 then r.cape={frame=frame,capes=records}end
 end
 local function restore_cape(r)
  if r.cape then
   if r.cape.selected then check(selected_cape.release(r.cape.selected),'Selected cape restoration refused')
   else cape.restore(r.cape)end
   r.cape=nil
  end
  r.cape_capture_done=nil
 end
 local function apply_cape(r)
  if r.cape.selected then
   local writes=selected_cape.apply(r.cape.selected,r.cape.frame)
   if type(policy.log)=='function'then pcall(policy.log,'Authored pose cape placement: writes='..writes)end
  else cape.apply(r.cape)end
 end
 function self.maintain(target,rig)
  return result(function()
   local r=record(target,rig)
   -- Selected Windows placement is applied by the body commit event. It needs
   -- no extra per-frame lookup or rewrite while the authored pose is unchanged.
   if not r.cape or r.cape.selected then return true end
   current(r,nil,'ignore')
   local valid,why=cape_reader.pose_valid(r.cape.frame,true);check(valid==true,why or'Cape owner changed')
   cape.apply(r.cape);return true
  end)
 end
 function self.session_current()
  return result(function()ready();return one(pack(N.game_session()),'userdata','Game session')==session end)
 end
 function self.discover(wanted,limit,rig,point)
  return result(function()
   local began=type(policy.measure)=='function'and policy.measure()
   ready();check(wanted==resource and limit==4,'Bounded exact-resource subject discovery required')
   for _,r in pairs(records)do check(not next(r.nodes)and not r.mode and not r.scene_dirty and not r.cape,'Retire owned subjects before refreshing')end
   check(one(pack(N.game_session()),'userdata','Game session')==session,'Qualified session changed')
   local topology_copy=rig_copy(rig);local world=one(pack(A.main_world()),'userdata','Main world')
   local id=one(pack(I.from_hex(resource)),'userdata','IdString64.from_hex')
   local units=one(pack(W.units_by_resource(world,id)),'table','World.units_by_resource')
   -- Four is the menu capacity, not a limit on live bodies/corpses in a mission.
   -- Refresh is explicit: inspect one exact-resource inventory, retain only the
   -- nearest four, and validate their complete rig before exposing any target.
   if point~=nil then point=vector(point,3);check(type(U.world_position)=='function','Subject position getter unavailable')end
   local candidates,seen={},{};local key;local scanned=0
   for index=1,129 do
    local unit;key,unit=next(units,key);if key==nil then break end
    check(index<=128,'Subject inventory exceeds the 128-unit discovery budget')
    scanned=index
    check(finite(key)and key%1==0 and key>=1 and type(unit)=='userdata','Subject inventory entry shape changed')
    if not seen[unit]then
     seen[unit]=true
     if one(pack(U.alive(unit)),'boolean','Unit.alive')and U.world(unit)==world and U.num_scene_graph_items(unit)==107 then
      local distance=0
      if point then local p=xyz(one(pack(U.world_position(unit,1)),'userdata','Unit.world_position'))
       for j=1,3 do distance=distance+(p[j]-point[j])^2 end
      end
      local at=#candidates+1
      for j,row in ipairs(candidates)do if distance<row.distance or distance==row.distance and key<row.key then at=j;break end end
      if at<=limit then table.insert(candidates,at,{unit=unit,distance=distance,key=key});if #candidates>limit then table.remove(candidates)end end
     end
    end
   end
   check(generation<4294967295,'Subject discovery generation exhausted');local next_generation=generation+1
   local found,next_records={},{}
   for i,row in ipairs(candidates)do
    local unit=row.unit
    local identity='photographic-subject-'..next_generation..'-'..i;local label='Photographic subject '..i
    local target={identity=identity,label=label,resource=resource,node_count=107}
    local r={identity=identity,label=label,unit=unit,world=world,rig=rig,topology=topology_copy,nodes={},refresh_nodes={}}
    lifetime(r);for node=1,107 do topology(r,node)end
    found[i]=target;next_records[target]=r
   end
   generation=next_generation;records=next_records
   if began and type(policy.log)=='function'then pcall(policy.log,string.format('Subject discovery: scanned=%d listed=%d elapsed_ms=%.3f',scanned,#found,(policy.measure()-began)*1000))end
   return found
  end)
 end
 -- Read-only helpers for automatic and scene (double-click) selection. They
 -- use handles from the current discovery and the full lifetime guard, which
 -- proves the 107-node scene graph before any transform getter runs.
 function self.locate(unit)
  for target,r in pairs(records)do if not r.retired and r.unit==unit then return target end end
 end
 -- Read-only camera association for photographic tracking, not gameplay authority.
 -- Prefer a unique authored camera-anchor match. Otherwise use a clearly
 -- closest head near the gameplay camera; never call this local-player proof.
 function self.camera_target(camera_unit,rig,view_position)
  return result(function()
   check(U.alive(camera_unit)==true and U.num_cameras(camera_unit)==1,'Camera unit unavailable')
   local world=U.world(camera_unit);local camera_pose=matrix_values(U.world_pose(camera_unit,1))
   local found;local nearby={}
   if view_position~=nil then view_position=vector(view_position,3)end
   for target,r in pairs(records)do
    if not r.retired and r.world==world then
     record(target,rig);lifetime(r);topology(r,7)
     local anchor=matrix_values(U.world_pose(r.unit,7));local same=true
     for i=1,12 do if math.abs(anchor[i]-camera_pose[i])>.0001 then same=false;break end end
     if same then check(not found,'Camera anchor is ambiguous');found=target end
     if view_position and U.has_node(r.unit,'head')==true then
      local node=U.node(r.unit,'head');check(finite(node)and node%1==0 and node>=1 and node<=107,'Head bounds changed')
      local p=xyz(U.world_position(r.unit,node));local d=0
      for i=1,3 do d=d+(p[i]-view_position[i])^2 end
      nearby[#nearby+1]={target=target,distance=math.sqrt(d)}
     end
    end
   end
   if found then return found,'unique camera-anchor match'end
   return M.choose_tracking(nearby)
  end)
 end
 function self.position(target,rig)
  return result(function()
   local r=record(target,rig);lifetime(r)
   local getter=rawget(U,'world_position');check(type(getter)=='function','Unit.world_position unavailable')
   return xyz(one(pack(getter(r.unit,1)),'userdata','Unit.world_position'))
  end)
 end
 -- A selected photographic subject is not an authoritative local-player ID.
 function self.tracking_frame(target,rig)
  return result(function()
   local r=record(target,rig);lifetime(r)
   check(U.has_node(r.unit,'head')==true,'Selected subject head unavailable')
   local head=U.node(r.unit,'head');check(finite(head)and head%1==0 and head>=1 and head<=107,'Selected head bounds')
   local pose=U.world_pose(r.unit,1);local forward=xyz(B.forward(pose))
   local frame={explicit_subject=true,identity=r.identity,root_handle=r.unit,world=r.world,rig_nodes=rig.nodes,
    position=xyz(U.world_position(r.unit,1)),head=xyz(U.world_position(r.unit,head)),
    yaw=math.atan2(forward[2],forward[1])}
   lifetime(r);return frame
  end)
 end
 -- Saved shots anchor on a bone's full position and orientation, so a camera on the face
 -- stays on the face as the Helldiver turns: the root and a few stable bones, world space,
 -- as position p and axes x, y, z. Read-only.
 function self.anchor_frame(target,rig)
  return result(function()
   local r=record(target,rig);lifetime(r)
   local function bone(index)
    local m=matrix_values(one(pack(U.world_pose(r.unit,index)),'userdata','Unit.world_pose'))
    return{p={m[10],m[11],m[12]},x={m[1],m[2],m[3]},y={m[4],m[5],m[6]},z={m[7],m[8],m[9]}}
   end
   local bones={root=bone(1)}
   for _,name in ipairs({'hips','chest','head'})do
    if U.has_node(r.unit,name)==true then
     local index=U.node(r.unit,name);check(finite(index)and index%1==0 and index>=1 and index<=107,'Anchor bone bounds')
     bones[name]=bone(index)
    end
   end
   local forward=bones.root.y
   local frame={identity=r.identity,position=bones.root.p,yaw=math.atan2(forward[2],forward[1]),bones=bones}
   lifetime(r);return frame
  end)
 end
 function self.valid(target,rig)
  local ok,why=pcall(function()local r=record(target,rig);if r.retired then error({tag=retired_tag,reason='Selected subject retired'},0)end;lifetime(r)end)
  if ok then return true end
  if type(why)=='table'and why.tag==retired_tag then
   local r=records[target];local restored,issue=pcall(restore_cape,r)
   if not restored then return nil,issue end
   return false,why.reason
  end
  return nil,why
 end
 function self.canonical_node(target,rig,value)
  return result(function()record(target,rig);return math_node(value)end)
 end
 function self.snapshot(target,rig)
  return result(function()
   local r=record(target,rig);local actual_mode=current(r)
   for i=1,107 do topology(r,i)end
   local nodes={};for i=8,92 do nodes[i]=read_node(r.unit,i)end
   if r.mode and r.mode.attempt and actual_mode==r.mode.attempt.target then
    acknowledged_mode(r,r.mode.attempt.before,actual_mode)
   end
   if r.refresh_expected then
    check(actual_mode==r.refresh_expected.mode,'Failed scene refresh has unknown mode outcome: '..actual_mode..', expected '..r.refresh_expected.mode)
    for i,value in pairs(r.refresh_expected.nodes)do check(equal(nodes[i],value),'Failed scene refresh has unknown node outcome: node '..i..', mode '..actual_mode)end
    r.refresh_expected=nil
   end
   r.captured=true
   return{identity=r.identity,resource=resource,node_count=107,mode=actual_mode,nodes=nodes}
  end)
 end
 if preview then function self.snapshot_anchors(target,rig)
  return result(function()
   local r=record(target,rig);local actual_mode=current(r)
   for i=1,107 do topology(r,i)end
   local nodes={}
   -- New anchor indices are read-only and not part of the prior 85-body-node
   -- live getter proof. Preserve actual scale and quaternion sign, without math
   -- constructor conversion; the finite driver must refuse an unexpected read.
   for i=1,107 do if i<8 or i>92 then nodes[i]=read_node(r.unit,i,true)end end
   return{identity=r.identity,resource=resource,node_count=107,mode=actual_mode,nodes=nodes}
  end)
 end end
 function self.set_node(target,rig,index,expected,value,expected_mode)
  local ok,why=result(function()
   local r=record(target,rig);check(r.captured,'Capture a coherent baseline before writing');check(index>=8 and index<=92 and index%1==0,'Subject write outside body')
   check(mode(expected_mode),'Expected mode unavailable');expected,value=copy(expected),copy(value)
   check(expected.pose and value.pose,'Raw numeric matrix ownership is required')
   matrix_from(expected.pose)
   local _,actual=current(r,index,expected_mode);check(equal(actual,expected),'Subject matrix compare-write refused')
   local entry=r.nodes[index]
   if entry and entry.attempt then check(known(entry,actual),'Unresolved matrix attempt requires explicit ownership proof')end
   if equal(expected,value)then return true end
   entry=entry or{base=copy(expected),value=copy(expected)}
   authorize(equal(value,entry.base)and'restore_node.pose'or'set_node.pose',target)
   if preview then record(target,rig);local _,authorized=current(r,index,expected_mode);check(equal(authorized,expected),'Subject matrix changed during authorization')end
   capture_cape(r)
   local temporary=matrix_from(value.pose)
   matrix_node(temporary) -- Validate actual target PQS without rebuilding its quaternion.
   r.nodes[index]=entry;begin_attempt(entry,expected,value,expected_mode);r.scene_dirty=true
   local called=pack(pcall(U.set_local_pose,r.unit,index,temporary));status.last_result=receipt(called)
   check(called[1]and called[2]~=false,called[1]and(called[3]or'Subject pose setter refused')or called[2])
   local _,after=current(r,index,expected_mode)
   if not equal(after,value)then
    if not status.pose_readback_mismatch then status.pose_readback_mismatch=pose_mismatch(index,expected_mode,expected,value,after)end
    error('Subject pose readback differs from exact numeric target',0)
   end
   clear_attempt(entry);entry.value=copy(value);r.refresh_nodes[index]=copy(value)
   if equal(value,entry.base)then r.nodes[index]=nil end
   return true
  end)
  if ok~=true then return false,why end;return true
 end
 function self.resolve_node(target,rig,index,before,desired,observed,expected_mode)
  local ok,why=result(function()
   local r=record(target,rig);local entry=r.nodes[index];local attempt=entry and entry.attempt
   check(attempt and index>=8 and index<=92,'No matching matrix attempt ledger')
   before,desired,observed=copy(before),copy(desired),copy(observed)
   check(before.pose and desired.pose and observed.pose,'Raw matrix recovery representation is required')
   check(equal(before,attempt.before)and equal(desired,attempt.target)and expected_mode==attempt.mode,'Matrix attempt identity mismatch')
   local _,actual=current(r,index,expected_mode);check(equal(actual,observed),'Matrix recovery snapshot changed')
   check(equal(actual,attempt.before)or equal(actual,attempt.target),'Matrix outcome is not an exact attempted endpoint')
   attempt.approved=copy(actual);return true
  end)
  if ok~=true then return false,why end;return true
 end
 function self.set_mode(target,rig,expected,value)
  local ok,why=result(function()
   local r=record(target,rig);check(r.captured and mode(expected)and mode(value),'Capture a coherent mode baseline first')
   current(r,nil,expected);local entry=r.mode
   if entry and entry.attempt then check(expected==entry.attempt.before or expected==entry.attempt.target,'Unresolved subject mode write')end
   if expected==value then return true end
   authorize(entry and value==entry.base and'restore_mode'or'set_mode',target)
   if preview then record(target,rig);current(r,nil,expected)end
   capture_cape(r)
   entry=entry or{base=expected,value=expected};r.mode=entry
   if not entry.attempt then pending=pending+1 end
   entry.attempt={before=expected,target=value};status.pending=pending;r.scene_dirty=true
   local called=pack(pcall(U.set_animation_bone_mode,r.unit,value));status.last_result=receipt(called)
   check(called[1]and called[2]~=false,called[1]and(called[3]or'Subject mode setter refused')or called[2])
   local actual=current(r);check(actual==value,'Subject mode readback differs from submitted value')
   acknowledged_mode(r,expected,value);clear_attempt(entry);entry.value=value;if value==entry.base then r.mode=nil end
   return true
  end)
  if ok~=true then return false,why end;return true
 end
 function self.commit(target,rig)
  local ok,why=result(function()
   local r=record(target,rig);if not r.scene_dirty then return true end
   local actual_mode=current(r);local expected_nodes={}
   if r.mode then local entry=r.mode
    if entry.attempt then
     check(actual_mode==entry.attempt.before or actual_mode==entry.attempt.target,'Mode cleanup remains unknown')
     if actual_mode==entry.attempt.target then acknowledged_mode(r,entry.attempt.before,actual_mode)end
     clear_attempt(entry);entry.value=actual_mode
    end
    if actual_mode==entry.base or actual_mode~=entry.value then r.mode=nil end
   end
   for index,entry in pairs(r.nodes)do
    topology(r,index);local actual=read_node(r.unit,index)
    if entry.attempt then check(known(entry,actual),'Node cleanup remains unknown: node '..index);clear_attempt(entry);entry.value=copy(actual)end
    if equal(actual,entry.base)or not equal(actual,entry.value)then r.nodes[index]=nil end
    expected_nodes[index]=copy(actual)
   end
   -- Retain restored baselines through commit too: scene evaluation must not
   -- silently change a node whose local setters have just restored it.
   for index in pairs(r.refresh_nodes)do if not expected_nodes[index]then topology(r,index);expected_nodes[index]=read_node(r.unit,index)end end
   authorize('commit',target)
   if preview then
    record(target,rig);current(r,nil,actual_mode)
    for index,expected in pairs(expected_nodes)do topology(r,index);check(equal(read_node(r.unit,index),expected),'Subject changed during preview authorization')end
   end
   r.refresh_expected={mode=actual_mode,nodes=expected_nodes}
   local called=pack(pcall(W.update_unit,r.world,r.unit));status.last_commit=receipt(called)
   check(called[1]and called[2]~=false,called[1]and(called[3]or'Subject scene refresh refused')or called[2])
   current(r,nil,actual_mode)
   for index,expected in pairs(expected_nodes)do topology(r,index);check(equal(read_node(r.unit,index),expected),'Subject changed during scene refresh: node '..index..', mode '..actual_mode)end
   if r.cape then
    if next(r.nodes)or r.mode then apply_cape(r)else restore_cape(r)end
   elseif not next(r.nodes)and not r.mode then r.cape_capture_done=nil end
   r.refresh_expected=nil;r.refresh_nodes={};r.scene_dirty=false;return true
  end)
  if ok~=true then return false,why end;return true
 end
 function self.status()return status end
 return self
end
function M.new(sr,policy)return factory(sr,policy,false)end
function M.preview(sr,policy)return factory(sr,policy,true)end
return M

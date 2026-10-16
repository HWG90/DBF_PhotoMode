-- Fixed authored poses. No gameplay events, animation graph swaps or time steps.
-- Writes/restoration run only from the owning update hook; menu callbacks queue.
local M={catalog={{id='salute',label='Salute'},{id='wave',label='Wave'},{id='taunt',label='Taunt'}}}
function M.native(sr,subject,data)
 local U,X,V,Q=sr.Unit,sr.Matrix4x4,sr.Vector3,sr.Quaternion
 assert(subject and subject.pose_frame and subject.pose_valid,'Fixed pose ownership reader unavailable')
 assert(data and data.version==1 and data.rig.node_count==107,'Fixed pose data unavailable')
 for _,name in ipairs({'num_scene_graph_items','scene_graph_parent','has_node','node','local_pose','set_local_pose','animation_bone_mode','set_animation_bone_mode'})do
  assert(type(U[name])=='function','Fixed pose API unavailable: '..name)
 end
 assert(sr.Matrix4x4Box and sr.World and type(sr.World.update_unit)=='function','Fixed pose transform API unavailable')
 local adapter={};local compiled={}
 function adapter.frame()
  local frame=subject.pose_frame()
  assert(frame.local_owner and frame.root_handle and frame.identity,'Local subject pose ownership required')
  assert(U.num_scene_graph_items(frame.root_handle)==107,'Subject skeleton changed')
  return frame
 end
 function adapter.valid(frame,owned)return subject.pose_valid(frame,owned)end
 local function checked(frame,owned)
  local valid,why=adapter.valid(frame,owned);assert(valid==true,why or'Subject pose owner retired')
 end
 -- Cloth keeps its simulated shape while world time is stopped. Its separate
 -- mesh-placement nodes must follow the posed shoulder anchor as well as the
 -- skeleton. Discover the owned cape rig from its live topology; an unsupported garment
 -- never prevents a body pose or authorizes guessed node-number writes.
 local cape_api=sr.Mesh and type(sr.Mesh.node)=='function'
 for _,name in ipairs({'resolve','valid','owned'})do cape_api=cape_api and type(subject[name])=='function'end
 for _,name in ipairs({'mesh','num_meshes','world_pose'})do cape_api=cape_api and type(U[name])=='function'end
 for _,name in ipairs({'multiply','inverse','right','forward','up','translation'})do cape_api=cape_api and type(X[name])=='function'end
 for _,name in ipairs({'x','y','z'})do cape_api=cape_api and type(V[name])=='function'end
 local function same_pose(a,b)
  for _,axis in ipairs({'right','forward','up','translation'})do
   local left,right=X[axis](a),X[axis](b)
   for _,field in ipairs({'x','y','z'})do
    local x,y=V[field](left),V[field](right)
    if type(x)~='number'or type(y)~='number'or x~=x or y~=y or math.abs(x)==math.huge or math.abs(y)==math.huge or math.abs(x-y)>1e-4 then return false end
   end
  end
  return true
 end
 local function cape_part(record,owned)
  local valid,why=subject.valid(record.part)
  if valid==false then return false end
  assert(valid==true,why or'Cape ownership read unavailable')
  assert(U.num_scene_graph_items(record.part.handle)==record.node_count,'Cape skeleton changed')
  for name,node in pairs(record.cape_nodes)do
   assert(U.has_node(record.part.handle,name)and U.node(record.part.handle,name)==node,'Cape bone mapping changed')
  end
  if owned then assert(subject.owned(record.part),'Cape attachment ownership changed')end
  return true
 end
 local function cape_mesh(record,mesh)
  local valid,why=subject.valid(record.part,mesh.index)
  if valid==false then return false end
  assert(valid==true,why or'Cape mesh ownership read unavailable')
  -- Do not dereference a saved Mesh until the backend has found that exact
  -- object in this still-live, generation-checked Unit's mesh array.
  assert(sr.Mesh.node(mesh.handle)==mesh.node,'Cape mesh node mapping changed')
  assert(U.scene_graph_parent(record.part.handle,mesh.node)==mesh.parent,'Cape placement parent changed')
  return true
 end
 local function capture_capes(frame)
  if not cape_api then return nil end
  local ok,result=pcall(function()
   checked(frame,true)
   assert(U.has_node(frame.root_handle,'cape1'),'Subject cape anchor unavailable')
   local anchor=U.node(frame.root_handle,'cape1')
   assert(type(anchor)=='number'and anchor%1==0 and anchor>=1 and anchor<=U.num_scene_graph_items(frame.root_handle),'Subject cape anchor unsupported')
   local inverse=sr.Matrix4x4Box(X.inverse(U.world_pose(frame.root_handle,anchor)))
   local scene=subject.resolve();local records,seen={},{}
   assert(scene.local_owner and scene.groups and scene.groups.hide_player,'Cape subject lookup unavailable')
   for _,part in ipairs(scene.groups.hide_player)do
    if part.ref~=frame.root_ref and not seen[part.ref]then
     seen[part.ref]=true
     local found,record=pcall(function()
      assert(subject.valid(part)==true and subject.owned(part),'Cape source unavailable')
      assert(part.world_native==frame.world_native and part.owner_key==frame.owner_key,'Cape subject world or owner differs')
      local unit=part.handle
      local node_count=U.num_scene_graph_items(unit)
      assert(type(node_count)=='number'and node_count%1==0 and node_count>=2 and node_count<=512,'Cape skeleton bounds changed')
      -- Armor variants rename their cape meshes and may externally link the
      -- cloth bones (no local parent). Identify the bounded named cape rig,
      -- then discover its separate placement nodes from actual Mesh handles.
      local cape_nodes,bones={},{}
      assert(U.has_node(unit,'cape1'),'Cape anchor mapping unavailable')
      for n=1,64 do local name='cape'..n
       if U.has_node(unit,name)then
        local node=U.node(unit,name)
        assert(type(node)=='number'and node%1==0 and node>=1 and node<=node_count and not bones[node],'Unsupported cape bone mapping')
        cape_nodes[name]=node;bones[node]=true
       end
      end
      -- Mesh nodes already beneath a cloth bone inherit its movement. Never
      -- apply the shoulder delta to them a second time. Walk only bounded,
      -- validated local parents; external links terminate the walk.
      local function follows_cloth(node)
       local seen={}
       for _=1,node_count do
        if bones[node]then return true end
        assert(not seen[node],'Cape hierarchy cycle');seen[node]=true
        local parent=U.scene_graph_parent(unit,node)
        if parent==nil or parent==0 then return false end
        assert(type(parent)=='number'and parent%1==0 and parent>=1 and parent<=node_count and parent~=node,'Cape hierarchy changed')
        node=parent
       end
       error('Cape hierarchy depth changed')
      end
      local count=U.num_meshes(unit);assert(count==part.mesh_count and count>=1 and count<=128,'Cape mesh bounds changed')
      local r={part=part,node_count=node_count,cape_nodes=cape_nodes,anchor=anchor,world=frame.world,meshes={},changed={}}
      local root=sr.Matrix4x4Box(U.world_pose(unit,1));local nodes={}
      for index=1,count do
       assert(subject.valid(part,index)==true,'Cape mesh retired during capture')
       local handle=U.mesh(unit,index);local node=sr.Mesh.node(handle)
       assert(type(node)=='number'and node%1==0 and node>=1 and node<=node_count,'Cape mesh node bounds changed')
       local parent=U.scene_graph_parent(unit,node)
       if node>1 and not follows_cloth(node)and not nodes[node]and type(parent)=='number'and parent%1==0 and parent>=1 and parent<=node_count and parent~=node then
        local pose=sr.Matrix4x4Box(U.world_pose(unit,node))
        if same_pose(pose:unbox(),root:unbox())then
         nodes[node]=true
         r.meshes[#r.meshes+1]={index=index,handle=handle,node=node,parent=parent,
          original=sr.Matrix4x4Box(U.local_pose(unit,node)),
          bind=sr.Matrix4x4Box(X.multiply(pose:unbox(),inverse:unbox()))}
        end
       end
      end
      assert(#r.meshes>0 and cape_part(r,true),'Cape placement nodes unavailable')
      for _,mesh in ipairs(r.meshes)do assert(cape_mesh(r,mesh),'Cape mesh retired during capture')end
      return r
     end)
     if found then records[#records+1]=record end
    end
   end
   checked(frame,true);return records
  end)
  -- No cape writes have happened yet: missing/unsupported cape readers can
  -- safely skip this optional feature without retaining a mutation lease.
  return ok and result or nil
 end
 local function apply_capes(lease)
  for _,record in ipairs(lease.capes or{})do
   if not record.retired then
    if not cape_part(record,true)then record.retired=true;record.changed={}
    else
     assert(U.has_node(lease.frame.root_handle,'cape1')and U.node(lease.frame.root_handle,'cape1')==record.anchor,'Subject cape anchor changed')
     local anchor=sr.Matrix4x4Box(U.world_pose(lease.frame.root_handle,record.anchor));local wrote=false
     for _,mesh in ipairs(record.meshes)do
      if not mesh.retired then
       if not cape_mesh(record,mesh)then mesh.retired=true;record.changed[mesh.node]=nil
       else
        local parent=U.world_pose(record.part.handle,mesh.parent)
        local desired=X.multiply(X.multiply(mesh.bind:unbox(),anchor:unbox()),X.inverse(parent))
        record.changed[mesh.node]=true -- Own restoration before a partial setter failure.
        U.set_local_pose(record.part.handle,mesh.node,desired);wrote=true
       end
      end
     end
     if wrote then sr.World.update_unit(record.world,record.part.handle)end
    end
   end
  end
 end
 local function restore_capes(lease)
  local failure
  for _,record in ipairs(lease.capes or{})do
   if next(record.changed)then
    local ok,why=pcall(function()
     if not cape_part(record,false)then record.changed={};record.retired=true;return end
     local done,wrote={},false;local problem
     for _,mesh in ipairs(record.meshes)do
      if record.changed[mesh.node]then
       local restored,reason=pcall(function()
        if cape_mesh(record,mesh)then U.set_local_pose(record.part.handle,mesh.node,mesh.original:unbox());wrote=true end
        done[mesh.node]=true
       end)
       if not restored then problem=problem or tostring(reason)end
      end
     end
     if wrote then sr.World.update_unit(record.world,record.part.handle)end
     for node in pairs(done)do record.changed[node]=nil end
     assert(not problem,problem)
    end)
    if not ok then failure=failure or tostring(why)end
   end
  end
  assert(not failure,failure)
 end
 function adapter.capture(frame)
  checked(frame,true)
  local unit=frame.root_handle
  for i,spec in ipairs(data.rig.nodes)do
   assert((U.scene_graph_parent(unit,i)or 0)==spec.parent,'Subject pose hierarchy changed')
   if spec.name then assert(U.has_node(unit,spec.name)and U.node(unit,spec.name)==i,'Subject pose bone mapping changed')end
  end
  local lease={frame=frame,original={},mode=U.animation_bone_mode(unit)}
  assert(type(lease.mode)=='string','Subject bone transfer mode unavailable')
  -- Preserve world placement/root (1..7), collision nodes and unnamed
  -- gameplay attachments. Body-root 8 is needed for poses such as push-ups.
  for i=8,92 do lease.original[i]=sr.Matrix4x4Box(U.local_pose(unit,i))end
  lease.capes=capture_capes(frame)
  return lease
 end
 local function poses(id)
  if compiled[id]then return compiled[id]end
  local source=assert(data.poses[id],'Unknown subject pose');local out={}
  for i=8,92 do
   local pose=source.nodes[i];local q=pose.q;local sign=q[4]<0 and-1 or 1
   local w=math.max(-1,math.min(1,q[4]*sign));local sine=math.sqrt(math.max(0,1-w*w));local axis=V(1,0,0)
   if sine>1e-7 then axis=V(q[1]*sign/sine,q[2]*sign/sine,q[3]*sign/sine)end
   for k=1,3 do assert(math.abs(pose.s[k]-1)<.002,'Unsupported subject bone scale')end
   out[i]=sr.Matrix4x4Box(X.from_quaternion_position(Q.axis_angle(axis,2*math.acos(w)),V(unpack(pose.p))))
  end
  compiled[id]=out;return out
 end
 function adapter.prepare(id)poses(id)end
 function adapter.apply(lease,id)
  local values=poses(id);checked(lease.frame,true)
  U.set_animation_bone_mode(lease.frame.root_handle,'ignore')
  for i=8,92 do
   local value=i==8 and not data.poses[id].full_body and lease.original[i]or values[i]
   U.set_local_pose(lease.frame.root_handle,i,value:unbox())
  end
  sr.World.update_unit(lease.frame.world,lease.frame.root_handle)
  apply_capes(lease)
 end
 function adapter.restore(lease)
  -- Cloth externally references the body shoulder. Restore/evaluate that
  -- owner first, then refresh cape placement and its cached render pose.
  -- With frozen time there may be no subsequent physics step to repair it.
  local body,reason=pcall(function()
   checked(lease.frame,false)
   for i=8,92 do U.set_local_pose(lease.frame.root_handle,i,lease.original[i]:unbox())end
   U.set_animation_bone_mode(lease.frame.root_handle,lease.mode)
   sr.World.update_unit(lease.frame.world,lease.frame.root_handle)
  end)
  local capes,why=pcall(restore_capes,lease)
  assert(capes,why);assert(body,reason)
 end
 function adapter.restore_retired(lease)restore_capes(lease)end
 return adapter
end
function M.new(sr,subject,is_paused,log,data,adapter)
 log=log or function()end
 local catalog=data and data.catalog or M.catalog
 local self={available=false,pending=false,active=false,status='Fixed poses are waiting for a local player',capabilities={},catalog=catalog}
 local labels={};for _,item in ipairs(catalog)do
  assert(type(item.id)=='string'and type(item.label)=='string'and not labels[item.id],'Invalid fixed pose catalog')
  assert(not data or data.poses[item.id],'Fixed pose catalog has no sampled frame')
  labels[item.id]=item.label
 end
 local owned,request,last;local elapsed=.5;local last_paused,last_clock;local refresh_calls=0
 -- Keep only a catalog ID across Photo Mode sessions. Captures and native
 -- subject handles belong to the current held pose and are restored on exit.
 local remembered,resume_pending,pause_seen
 local function backend()
  if not adapter then adapter=M.native(sr,subject,data)end
  return adapter
 end
 local function paused()
  assert(type(is_paused)=='function','Subject pose pause reader unavailable')
  local value=is_paused();assert(type(value)=='boolean','Subject pose pause state unavailable');return value
 end
 local function closed()
  resume_pending=false;last=nil;self.available=false
  if next(self.capabilities)then self.capabilities={}end
  -- The controller stops refreshing poses while Photo Mode is closed. The
  -- next paused refresh must rediscover this session's current subject.
  pause_seen=false;last_paused=nil;last_clock=nil;elapsed=.5;refresh_calls=0
 end
 local function remembered_status()
  return remembered and(labels[remembered]..' remembered - pause Photo Mode to reapply')or nil
 end
 local function idle(message)
  owned=nil;request=nil;self.active=false;self.pending=false
  self.status=remembered_status()or message or self.status
 end
 local function restore()
  if not owned then idle('Original pose restored');return true end
  local valid,why=backend().valid(owned.frame,false)
  if valid==false then
   if backend().restore_retired then backend().restore_retired(owned)end
   idle('Previous subject retired');return true
  end
  assert(valid==true,why or'Subject restoration ownership unavailable')
  backend().restore(owned);idle('Original pose restored');return true
 end
 local function resume()
  if resume_pending and remembered and last and self.available and not owned and not request then
   request={id=remembered,identity=last.identity};self.pending=true;resume_pending=false
   self.status=labels[remembered]..' remembered - reapplying to the current subject'
  end
 end
 function self.refresh(dt,now)
  -- Simulation delta is zero exactly when fixed poses are usable. Read pause
  -- transitions immediately and use the input clock for periodic owner retries.
  local pause_ok,pause_value=pcall(paused)
  if not pause_ok then
   self.available=false;self.capabilities={};last=nil;last_paused=nil;elapsed=.5
   self.status=tostring(pause_value);return self.available,self.status,self.capabilities
  end
  if pause_value~=pause_seen then
   -- An unreadable renderer may delay the first fresh frame. Leave this
   -- single request armed until discovery succeeds, without changing time.
   resume_pending=pause_value and pause_seen==false and remembered~=nil or false
   pause_seen=pause_value
  end
  local has_clock=type(now)=='number'and now==now and math.abs(now)<math.huge
  local rollback=has_clock and last_clock and now<last_clock
  local delta=has_clock and last_clock and(now-last_clock)or tonumber(dt)or 0
  if delta~=delta then delta=0 end
  last_clock=has_clock and now or nil
  elapsed=elapsed+math.max(0,math.min(.5,delta));refresh_calls=refresh_calls+1
  -- Older input providers may lack a clock. Bounded render-call retries still
  -- recover an unavailable subject while paused, without changing world time.
  if last_paused==pause_value and not rollback and elapsed<.5 and(has_clock or refresh_calls<30)then
   resume()
   return self.available,self.status,self.capabilities
  end
  elapsed=0;refresh_calls=0;last_paused=pause_value
  local ok,why=pcall(function()
   -- The closed/unpaused service must not retain a cached Unit or World.
   last=pause_value and backend().frame()or nil;self.available=pause_value;self.capabilities={}
   for id in pairs(labels)do self.capabilities[id]=self.available end
   if not self.available then self.status=remembered_status()or'Pause entire action to hold a fixed pose'
   elseif not owned and not request then self.status=remembered_status()or'Fixed poses ready; the scene stays paused'end
   resume()
  end)
  if not ok then self.available=false;self.capabilities={};last=nil;self.status=tostring(why)end
  return self.available,self.status,self.capabilities
 end
 function self.queue(id)
  if not labels[id]then return false,'Unknown subject pose'end
  if not last or not self.available or not self.capabilities[id]then return false,self.status end
  remembered=id;resume_pending=false
  request={id=id,identity=last.identity};self.pending=true;return true
 end
 function self.queue_stop()
  remembered=nil;resume_pending=false
  if not owned then idle('Original pose restored');return true end
  request={stop=true};self.pending=true;return true
 end
 function self.release()
  closed()
  if not owned then idle('Original pose restored');return true end
  request={stop=true};self.pending=true;return true
 end
 local function run(after)
  if owned then
   local valid,why=backend().valid(owned.frame,false)
   if valid==false then return restore()end
   assert(valid==true,why or'Subject pose ownership unavailable')
  end
  if request and request.stop then return restore()end
  if owned and not paused()then
   last=nil;self.available=false;self.capabilities={}
   return restore()
  end
  if request and not after then
   assert(paused(),'Pause entire action to hold a fixed pose')
   local frame=backend().frame();assert(frame.identity==request.identity,'Subject changed before pose request')
   local id=request.id
   if owned and owned.frame.identity~=frame.identity then restore()end
   backend().prepare(id)
   if not owned then owned=backend().capture(frame);self.active=true end
   owned.id=id;request=nil;self.pending=false
  end
  if owned then
   local valid,why=backend().valid(owned.frame,true)
   if valid==false then return restore()end
   assert(valid==true,why or'Subject pose ownership unavailable')
   backend().apply(owned,owned.id);self.status=labels[owned.id]..' held - scene paused'
  end
  return true
 end
 local function step(after)
  if not owned and not request then
   -- A retired owner may finish cleanup before controller.stop(), which
   -- then has no active lease to release. Observe only the boolean here:
   -- closed update hooks must never discover Units or write native poses.
   local ok,value=pcall(paused)
   if ok and value==false then closed();self.status=remembered_status()or self.status
   elseif not ok then self.available=false;self.capabilities={};last=nil;last_paused=nil;elapsed=.5 end
   return true
  end
  local ok,result=pcall(run,after)
  if not ok then
   -- A failed apply is not an invitation to repeatedly capture/apply the
   -- same pose. Restoration still retries; reopening or selection rearms it.
   resume_pending=false
   self.available=false;self.capabilities={};last=nil
   request=owned and{stop=true}or nil;self.pending=owned~=nil;self.active=owned~=nil
   local message='Fixed pose unavailable: '..tostring(result)
   if self.status~=message then log(message)end;self.status=message
   return false,message
  end
  return result
 end
 function self.flush()return step(false)end
 function self.after_update()return step(true)end
 function self.current()return owned and owned.id or nil end
 function self.remembered()return remembered end
 return self
end
return M

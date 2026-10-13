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
 function adapter.capture(frame)
  checked(frame,true)
  local unit=frame.root_handle
  for i,spec in ipairs(data.rig.nodes)do
   assert((U.scene_graph_parent(unit,i)or 0)==spec.parent,'Subject pose hierarchy changed')
   if spec.name then assert(U.has_node(unit,spec.name)and U.node(unit,spec.name)==i,'Subject pose bone mapping changed')end
  end
  local lease={frame=frame,original={},mode=U.animation_bone_mode(unit)}
  assert(type(lease.mode)=='string','Subject bone transfer mode unavailable')
  -- Preserve world placement/root/boss (1..8), collision nodes and unnamed
  -- gameplay attachments. Child equipment inherits the posed skeleton.
  for i=9,92 do lease.original[i]=sr.Matrix4x4Box(U.local_pose(unit,i))end
  return lease
 end
 local function poses(id)
  if compiled[id]then return compiled[id]end
  local source=assert(data.poses[id],'Unknown subject pose');local out={}
  for i=9,92 do
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
  for i=9,92 do U.set_local_pose(lease.frame.root_handle,i,values[i]:unbox())end
  sr.World.update_unit(lease.frame.world,lease.frame.root_handle)
 end
 function adapter.restore(lease)
  checked(lease.frame,false)
  for i=9,92 do U.set_local_pose(lease.frame.root_handle,i,lease.original[i]:unbox())end
  U.set_animation_bone_mode(lease.frame.root_handle,lease.mode)
  sr.World.update_unit(lease.frame.world,lease.frame.root_handle)
 end
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
 local owned,request,last;local elapsed=.5
 local function backend()
  if not adapter then adapter=M.native(sr,subject,data)end
  return adapter
 end
 local function paused()
  assert(type(is_paused)=='function','Subject pose pause reader unavailable')
  local value=is_paused();assert(type(value)=='boolean','Subject pose pause state unavailable');return value
 end
 local function idle(message)
  owned=nil;request=nil;self.active=false;self.pending=false
  if message then self.status=message end
 end
 local function restore()
  if not owned then idle('Original pose restored');return true end
  local valid,why=backend().valid(owned.frame,false)
  if valid==false then idle('Previous subject retired');return true end
  assert(valid==true,why or'Subject restoration ownership unavailable')
  backend().restore(owned);idle('Original pose restored');return true
 end
 function self.refresh(dt)
  elapsed=elapsed+math.max(0,math.min(.5,tonumber(dt)or 0))
  if elapsed<.5 then return self.available,self.status,self.capabilities end
  elapsed=0
  local ok,why=pcall(function()
   last=backend().frame();self.available=paused();self.capabilities={}
   for id in pairs(labels)do self.capabilities[id]=self.available end
   if not self.available then self.status='Pause entire action to hold a fixed pose'
   elseif not owned and not request then self.status='Fixed poses ready; the scene stays paused'end
  end)
  if not ok then self.available=false;self.capabilities={};last=nil;self.status=tostring(why)end
  return self.available,self.status,self.capabilities
 end
 function self.queue(id)
  if not labels[id]then return false,'Unknown subject pose'end
  if not last or not self.available or not self.capabilities[id]then return false,self.status end
  request={id=id,identity=last.identity};self.pending=true;return true
 end
 function self.queue_stop()
  if not owned then idle('Original pose restored');return true end
  request={stop=true};self.pending=true;return true
 end
 function self.release()return self.queue_stop()end
 local function run(after)
  if owned then
   local valid,why=backend().valid(owned.frame,false)
   if valid==false then idle('Previous subject retired');return true end
   assert(valid==true,why or'Subject pose ownership unavailable')
  end
  if request and request.stop or owned and not paused()then return restore()end
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
  if not owned and not request then return true end
  local ok,result=pcall(run,after)
  if not ok then
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
 return self
end
return M

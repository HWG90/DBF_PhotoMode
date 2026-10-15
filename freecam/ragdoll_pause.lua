-- Hold only the observed local ragdoll render pose while gameplay time is zero.
-- Releasing returns bone transfer ownership; it never rewinds world transforms.
local M={}
function M.native(sr,subject)
 local U,W=sr.Unit,sr.World
 assert(subject and type(subject.ragdoll_frame)=='function'and type(subject.pose_valid)=='function','Ragdoll ownership reader unavailable')
 for _,name in ipairs({'num_scene_graph_items','local_pose','set_local_pose','animation_bone_mode','set_animation_bone_mode'})do
  assert(U and type(U[name])=='function','Ragdoll pose API unavailable: '..name)
 end
 assert(sr.Matrix4x4Box and W and type(W.update_unit)=='function','Ragdoll transform API unavailable')
 local adapter={}
 function adapter.frame()
  local frame=subject.ragdoll_frame()
  assert(type(frame)=='table'and frame.local_owner and frame.root_handle and frame.world and frame.identity,'Local ragdoll subject unavailable')
  assert(type(frame.ragdoll_active)=='boolean','Ragdoll state unavailable')
  return frame
 end
 function adapter.valid(frame,owned)return subject.pose_valid(frame,owned)end
 local function checked(frame,owned)
  local valid,why=adapter.valid(frame,owned);assert(valid==true,why or'Ragdoll subject retired')
  assert(U.num_scene_graph_items(frame.root_handle)==107,'Ragdoll skeleton changed')
 end
 local function mode(frame,owned)
  checked(frame,owned);local value=U.animation_bone_mode(frame.root_handle)
  assert(type(value)=='string','Ragdoll bone mode unavailable');return value
 end
 function adapter.capture(frame)
  assert(frame.ragdoll_active==true,'Local player is not ragdolled')
  local lease={frame=frame,mode=mode(frame,true),poses={},mode_owned=false}
  assert(lease.mode~='ignore','Ragdoll bone transfer is owned by another pose')
  -- These bounded native batches run on the owning Lua update without a
  -- yield. Validate both boundaries instead of repeating native ownership
  -- discovery for each bone in the same uninterrupted call.
  for index=1,107 do
   local box=sr.Matrix4x4Box(U.local_pose(frame.root_handle,index))
   assert(box and type(box.unbox)=='function','Ragdoll pose capture unavailable')
   lease.poses[index]=box
  end
  assert(mode(frame,true)==lease.mode,'Ragdoll bone mode changed during capture')
  return lease
 end
 function adapter.apply(lease)
  local frame=lease.frame;local current=mode(frame,true)
  if not lease.mode_owned then
   assert(current==lease.mode,'Ragdoll bone mode ownership changed')
   -- Retain cleanup responsibility even when a setter mutates then throws.
   lease.mode_owned=true
   checked(frame,true)
   assert(U.set_animation_bone_mode(frame.root_handle,'ignore')~=false,'Ragdoll bone mode write refused')
  end
  assert(mode(frame,true)=='ignore','Ragdoll bone transfer ownership lost')
  for index=1,107 do
   assert(U.set_local_pose(frame.root_handle,index,lease.poses[index]:unbox())~=false,'Ragdoll pose write refused')
  end
  assert(mode(frame,true)=='ignore','Ragdoll bone transfer ownership lost')
  assert(W.update_unit(frame.world,frame.root_handle)~=false,'Ragdoll render update refused')
 end
 function adapter.restore(lease)
  if not lease.mode_owned then return true end
  -- A different current mode belongs to its current writer. In particular,
  -- never force ignore again merely to complete an old restoration.
  if mode(lease.frame,false)~='ignore'then return true end
  checked(lease.frame,false)
  assert(U.set_animation_bone_mode(lease.frame.root_handle,lease.mode)~=false,'Ragdoll bone mode restoration refused')
  assert(mode(lease.frame,false)~='ignore','Ragdoll bone mode restoration did not apply')
  return true
 end
 return adapter
end
function M.new(backend,log)
 assert(type(backend)=='table','Ragdoll pause backend unavailable');log=log or function()end
 local self={active=false,pending=false,status='Ragdoll pose hold idle'};local lease;local last_error
 local function clear(message)
  lease=nil;self.active=false;self.pending=false;self.status=message or'Ragdoll pose hold idle';last_error=nil
 end
 local function failure(message)
  self.status=tostring(message);self.active=lease~=nil;self.pending=lease~=nil
  if last_error~=self.status then last_error=self.status;pcall(log,'Ragdoll pose hold: '..self.status)end
  return false,self.status
 end
 local function valid(frame,owned)
  local called,result,why=pcall(backend.valid,frame,owned)
  if not called then return nil,tostring(result)end
  if result~=true and result~=false then return nil,why or'Ragdoll subject ownership unavailable'end
  return result,why
 end
 function self.release()
  if not lease then clear();return true end
  local alive,why=valid(lease.frame,false)
  if alive==false then clear('Previous ragdoll subject retired');return true end
  if alive~=true then return failure(why)end
  local called,result,reason=pcall(backend.restore,lease)
  if not called or result==false then return failure(called and reason or result)end
  clear('Ragdoll bone transfer restored');return true
 end
 function self.flush(enabled,fixed_pose_busy)
  if enabled~=true or fixed_pose_busy==true then return self.release()end
  if self.pending then return self.release()end
  if lease then
   local owned,why=valid(lease.frame,true)
   if owned==false then return self.release()end
   if owned~=true then return failure(why)end
  end
  local called,frame=pcall(backend.frame)
  if not called then return failure(frame)end
  if type(frame)~='table'or type(frame.ragdoll_active)~='boolean'then return failure('Ragdoll state unavailable')end
  if lease and frame.identity~=lease.frame.identity then return self.release()end
  if not frame.ragdoll_active then
   if lease then return self.release()end
   clear('Local player is not ragdolled');return true
  end
  if not lease then
   local alive,why=valid(frame,true)
   if alive~=true then return failure(why or'Ragdoll subject retired')end
   local captured,value=pcall(backend.capture,frame)
   if not captured then return failure(value)end
   if type(value)~='table'or value.frame~=frame then return failure('Ragdoll pose capture unavailable')end
   lease=value;self.active=true
  end
  local applied,result,why=pcall(backend.apply,lease)
  if not applied or result==false then
   local problem=applied and why or result
   local restored,reason=self.release()
   if not restored then problem=tostring(problem)..'; cleanup: '..tostring(reason)end
   return failure(problem)
  end
  self.active=true;self.pending=false;self.status='Ragdoll pose held';last_error=nil;return true
 end
 return self
end
return M

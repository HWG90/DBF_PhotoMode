-- Own only the default culling context, qualified on Windows build 26088801.
-- Callers supply associated live render units. This module does not discover
-- players, infer attachment ownership or turn a Boolean into a full pass mask.
local M={}
function M.new(sr)
 local U,Mesh=sr.Unit,sr.Mesh;local owned={};local self={}
 local function locate(record)
  local u=record.unit
  if not U.alive(u)or U.world(u)~=record.world or tostring(U.resource_name(u))~=record.resource then return nil end
  local count=U.num_meshes(u)
  assert(type(count)=='number'and count%1==0 and count>=0 and count<=128,'Visibility mesh count changed')
  if record.index<=count and U.mesh(u,record.index)==record.mesh then return record.index end
  local found
  for i=1,count do if U.mesh(u,i)==record.mesh then assert(not found,'Visibility mesh identity ambiguous');found=i end end
  return found
 end
 function self.release()
  local pending={};local reason
  for _,record in ipairs(owned)do
   local ok,why=pcall(function()
    local index=locate(record);if not index then return end
    local current=Mesh.visibility(record.mesh)
    assert(type(current)=='boolean','Visibility readback unavailable')
    if current~=false then return end -- Preserve a later visibility writer.
    U.set_mesh_visibility(record.unit,index,true,'default')
    assert(Mesh.visibility(record.mesh)==true,'Visibility restoration not acknowledged')
   end)
   if not ok then pending[#pending+1]=record;reason=tostring(why)end
  end
  owned=pending
  return #owned==0,reason
 end
 local function acquire(rows,append)
  assert(type(rows)=='table'and #rows<=64,'Visibility unit budget exceeded')
  if #owned>0 and not append then return false,'Restore the previous visibility selection first'end
  local plan,seen={},{}
  for _,record in ipairs(owned)do seen[record.mesh]=true end
  local ok,why=pcall(function()
   -- Validate the whole request before the first write.
   for _,row in ipairs(rows)do
    local u=row.unit
    assert(U.alive(u)and U.world(u)==row.world and tostring(U.resource_name(u))==row.resource,'Visibility unit identity changed')
    local count=U.num_meshes(u)
    assert(type(count)=='number'and count%1==0 and count>=0 and count<=128,'Visibility mesh budget exceeded')
    assert(type(row.indices)=='table'and #row.indices<=128,'Visibility mesh selection invalid')
    for _,index in ipairs(row.indices)do
     assert(type(index)=='number'and index%1==0 and index>=1 and index<=count,'Visibility mesh index invalid')
     local mesh=U.mesh(u,index);assert(mesh~=nil,'Visibility mesh missing')
     if not seen[mesh]then
      seen[mesh]=true;assert(#plan+#owned<512,'Visibility total budget exceeded')
      local before=Mesh.visibility(mesh);assert(type(before)=='boolean','Visibility baseline unavailable')
      plan[#plan+1]={unit=u,world=row.world,resource=row.resource,index=index,mesh=mesh,before=before}
     end
    end
   end
   for _,record in ipairs(plan)do
    if record.before then
     local index=assert(locate(record),'Visibility mesh retired before write')
     assert(Mesh.visibility(record.mesh)==true,'Visibility changed before write')
     owned[#owned+1]=record -- Retain restoration even if a setter throws after writing.
     U.set_mesh_visibility(record.unit,index,false,'default')
     assert(Mesh.visibility(record.mesh)==false,'Visibility hide not acknowledged')
    end
   end
  end)
  if not ok then
   local restored,reason=self.release()
   return false,tostring(why)..(restored and''or'; restore pending: '..tostring(reason))
  end
  return true
 end
 function self.hide(rows)return acquire(rows,false)end
 function self.append(rows)return acquire(rows,true)end
 -- Enforcement is also used by the owned after-game equipment renderer.
 -- User-requested enforcement, called only on explicit ADS transitions.
 -- Revalidate retained identities; never discover or acquire new mesh ownership.
 function self.reassert()
  local ok,why=pcall(function()
   local plan={}
   for _,record in ipairs(owned)do
    local index=assert(locate(record),'POV mesh retired during ADS transition')
    local visible=Mesh.visibility(record.mesh);assert(type(visible)=='boolean','POV visibility unavailable')
    if visible then plan[#plan+1]={record=record,index=index}end
   end
   for _,item in ipairs(plan)do
    U.set_mesh_visibility(item.record.unit,item.index,false,'default')
    assert(Mesh.visibility(item.record.mesh)==false,'POV enforcement not acknowledged')
   end
  end)
  return ok,why
 end
 function self.count()return #owned end
 return self
end
return M

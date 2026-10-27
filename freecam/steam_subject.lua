-- Source-only selected photographic-subject controller. No engine binding is
-- implied: the first argument is a qualified adapter, never a player resolver.
-- Adapter v1: discover(resource,limit,rig), valid(target,rig), snapshot(target,rig),
-- set_node(target,rig,index,expected,value,expected_mode),
-- set_mode(target,rig,expected,value), commit(target,rig).
-- Optional canonical_node(target,rig,value) returns numeric PQS in the exact
-- representation the qualified setters/getters roundtrip. It runs only for
-- selected authored target nodes, before baseline capture or any mutation.
-- Originals are already getter-canonical; non-fullbody root8 is never converted.
-- Optional node.pose is a copied dense 12-scalar affine matrix. When present on
-- both nodes it is the exact ownership representation; PQS remains mandatory
-- numeric presentation data. Mixed matrix/PQS frames never authorize writes.
-- Optional resolve_node(target,rig,index,before,value,current,expected_mode)
-- is read-only: explicit true proves an intermediate current node belongs to
-- the adapter's precise component-attempt ledger. False/nil/throw stays blocked.
-- Only explicit recover uses it; exact before/target paths never need it.
-- valid returns true / false (definitively retired) / nil (unknown).
-- snapshot must capture one coherent numeric frame in the current callback,
-- including identity/resource/node_count/mode and nodes 8..92. Every mutation
-- must freshly guard lifetime/rig and expected state. Mutations are synchronous,
-- never queued; only explicit true acknowledges complete application. A false or
-- throw can partially apply. Adapter arguments must not be modified or retained
-- as native Math/ID temporaries. A later native adapter requires ABI proof.
local M={}
local resource='4d1c334d294dfa97'
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function copy_vector(value,count)
 assert(type(value)=='table','Numeric subject vector unavailable')
 local result={};for i=1,count do assert(finite(value[i]),'Non-finite subject component');result[i]=value[i]end
 return result
end
local function copy_node(value)
 assert(type(value)=='table','Numeric subject node unavailable')
 local result={p=copy_vector(value.p,3),q=copy_vector(value.q,4),s=copy_vector(value.s,3)}
 if value.pose~=nil then
  assert(type(value.pose)=='table'and getmetatable(value.pose)==nil,'Numeric subject matrix unavailable')
  local count=0;for key in pairs(value.pose)do
   assert(type(key)=='number'and key>=1 and key<=12 and key==math.floor(key),'Invalid subject matrix index')
   count=count+1
  end
  assert(count==12,'Subject matrix must have exactly 12 components')
  result.pose=copy_vector(value.pose,12)
 end
 return result
end
local function same_node(a,b)
 if a.pose or b.pose then
  if not a.pose or not b.pose then return false end
  for i=1,12 do if a.pose[i]~=b.pose[i]then return false end end
  return true
 end
 for i=1,3 do if a.p[i]~=b.p[i]or a.s[i]~=b.s[i]then return false end end
 for i=1,4 do if a.q[i]~=b.q[i]then return false end end
 return true
end
local function copy_frame(value,identity)
 assert(type(value)=='table'and value.identity==identity and value.resource==resource and value.node_count==107,
  'Subject snapshot identity/rig unavailable')
 assert(type(value.mode)=='string'and #value.mode>0 and #value.mode<=128,'Subject bone mode unavailable')
 assert(type(value.nodes)=='table','Subject snapshot nodes unavailable')
 local result={mode=value.mode,nodes={}}
 for i=8,92 do
  result.nodes[i]=copy_node(value.nodes[i])
  local matrix=result.nodes[i].pose~=nil
  if i==8 then result.matrix=matrix else assert(result.matrix==matrix,'Mixed subject snapshot representations')end
 end
 return result
end
function M.new(adapter,bank,is_frozen)
 assert(type(bank)=='table'and bank.version==1 and type(bank.rig)=='table'and
  bank.rig.resource==resource and bank.rig.node_count==107 and type(bank.rig.nodes)=='table'and
  type(bank.catalog)=='table'and type(bank.decode)=='function','Unsupported subject pose bank')
 for i=1,107 do assert(type(bank.rig.nodes[i])=='table','Incomplete subject rig')end
 local labels={};for _,item in ipairs(bank.catalog)do
  assert(type(item.id)=='string'and type(item.label)=='string'and not labels[item.id],'Invalid subject pose catalog')
  labels[item.id]=item.label
 end
 local supported=type(adapter)=='table'and adapter.version==1 and type(is_frozen)=='function'
 for _,name in ipairs({'discover','valid','snapshot','set_node','set_mode','commit'})do
  supported=supported and type(adapter[name])=='function'
 end
 supported=supported and(adapter.canonical_node==nil or type(adapter.canonical_node)=='function')
 supported=supported and(adapter.resolve_node==nil or type(adapter.resolve_node)=='function')
 local self={catalog=bank.catalog};local targets,choices={},{};local selected,lease,pose,closing,blocked
 local status={available=supported==true,capability='explicit_photographic_subject',player_authority=false,
  state=supported and'unselected'or'unsupported',pending=false,message=supported and'Select a photographic subject'or'Subject adapter is not qualified'}
 local function state(name,message,detail)
  status.state,status.message,status.detail=name,message,detail
  blocked=name=='pending';status.selected=selected and selected.identity or nil;status.pose=pose;status.pending=blocked
 end
 local function pending(message,detail)state('pending',message,detail);return false,message end
 local function finish(retired,foreign)
  lease=nil;pose=nil
  if retired or closing then selected=nil;targets,choices={},{}end
  closing=false
  status.restored=not retired and not foreign
  state(retired and'retired'or foreign and'foreign'or selected and'selected'or'unselected',
   retired and'Selected subject retired; original pose was not restored'or
   foreign and'Foreign subject state preserved'or'Original subject pose restored')
  return true,status.message
 end
 local function snapshot()
  local called,valid,why=pcall(adapter.valid,selected,bank.rig)
  if not called then return nil,valid end
  if valid==false then return false,'Selected subject retired'end
  if valid~=true then return nil,why or'Subject lifetime is unknown'end
  local ok,frame,issue=pcall(adapter.snapshot,selected,bank.rig)
  if not ok then return nil,frame end
  if not frame then return nil,issue or'Subject snapshot unavailable'end
  local copied,result=pcall(copy_frame,frame,selected.identity)
  if not copied then return nil,result end
  return result
 end
 local function prepare(id)
  local decoded,frame,why=pcall(bank.decode,id)
  if not decoded or type(frame)~='table'or type(frame.full_body)~='boolean'or type(frame.nodes)~='table'then
   return nil,'Subject pose decode failed',decoded and why or frame
  end
  local copied,nodes=pcall(function()
   local result={};for i=8,92 do result[i]=copy_node(frame.nodes[i])end;return result
  end)
  if not copied then return nil,'Subject pose is not numeric',nodes end
  if adapter.canonical_node then for i=frame.full_body and 8 or 9,92 do
   local called,value,issue=pcall(adapter.canonical_node,selected,bank.rig,nodes[i])
   if not called or not value then return nil,'Subject target canonicalization failed',called and issue or value end
   local valid,result=pcall(copy_node,value)
   if not valid then return nil,'Subject target canonicalization is not numeric',result end
   nodes[i]=result
  end end
  return{full_body=frame.full_body,nodes=nodes}
 end
 local function write_node(index,current,value,mode)
  local record=lease.nodes[index]or{value=current};lease.nodes[index]=record
  record.attempt={before=current,target=value};lease.commit_pending=true
  local called,done,why=pcall(adapter.set_node,selected,bank.rig,index,current,value,mode)
  if not called or done~=true then return pending('Subject node write needs explicit recovery',called and why or done)end
  record.value,record.attempt=value,nil
  if same_node(value,lease.original.nodes[index])then lease.nodes[index]=nil end
  return true
 end
 local function write_mode(current,value)
  local record=lease.mode or{value=current};lease.mode=record
  record.attempt={before=current,target=value};lease.commit_pending=true
  local called,done,why=pcall(adapter.set_mode,selected,bank.rig,current,value)
  if not called or done~=true then return pending('Subject mode write needs explicit recovery',called and why or done)end
  record.value,record.attempt=value,nil
  if value==lease.original.mode then lease.mode=nil end
  return true
 end
 local function commit()
  if not lease.commit_pending then return true end
  local called,done,why=pcall(adapter.commit,selected,bank.rig)
  if not called or done~=true then return pending('Subject scene refresh needs explicit recovery',called and why or done)end
  lease.commit_pending=false;lease.mode_commit_pending=nil;return true
 end
 local function restore(resolve_partials,mode_only)
  pose=nil
  if not lease then
   if closing then selected=nil;targets,choices={},{};closing=false end
   if not supported then state('unsupported','Subject adapter is not qualified');return true end
   state(selected and'selected'or'unselected','No subject pose is held');return true
  end
  if mode_only then lease.mode_cleanup_attempted=true end
  local current,why=snapshot()
  if current==false then return finish(true)end
  if not current then return pending('Subject restoration ownership is unknown',why)end
  local foreign=lease.foreign==true;local unknown,detail
  local compatible=current.matrix==lease.original.matrix
  if not compatible then unknown=true;detail='Subject snapshot representation changed'end
  -- Resolve uncertain body setters before restoring body state. A value between
  -- its before/target states could be our partial write; never call it foreign.
  for i=8,92 do local record=lease.nodes[i]
   if record and compatible then
    local value=current.nodes[i]
    if record.attempt then
     if same_node(value,record.attempt.target)then record.value=value;record.attempt=nil
     elseif same_node(value,record.attempt.before)then record.value=value;record.attempt=nil
     elseif resolve_partials and adapter.resolve_node then
      local called,resolved,why=pcall(adapter.resolve_node,selected,bank.rig,i,
       copy_node(record.attempt.before),copy_node(record.attempt.target),copy_node(value),current.mode)
      if called and resolved==true then record.value=value;record.attempt=nil
      else unknown=true;detail=called and why or resolved end
     else unknown=true end
    elseif not same_node(value,record.value)then lease.nodes[i]=nil;foreign=true end
   end
  end
  local mode=lease.mode
  if mode then
   if mode.attempt then
    if current.mode==mode.attempt.target or current.mode==mode.attempt.before then mode.value=current.mode;mode.attempt=nil
    else unknown=true end
   elseif current.mode~=mode.value then lease.mode=nil;foreign=true end
  end
  lease.foreign=foreign
  if unknown or mode_only then
   -- Body uncertainty does not confer ownership of its intermediate values.
   -- A separately proven mode lease can still be retired, so exiting never
   -- leaves a known-owned 'ignore' merely because a body component is unknown.
   if lease.mode and not lease.mode.attempt then
    lease.mode_cleanup_attempted=true
    if current.mode==lease.original.mode then lease.mode=nil
    else
     lease.mode_commit_pending=true
     if not write_mode(current.mode,lease.original.mode)then return false,status.message end
     current.mode=lease.original.mode
    end
   end
   if lease.mode_commit_pending then
    if current.mode==lease.original.mode then
     if not commit()then return false,status.message end
    elseif not lease.mode then
     -- A foreign successor mode owns subsequent evaluation. Do not refresh it.
     lease.mode_commit_pending=nil;lease.foreign=true
    end
   end
   return pending(unknown and'A partial subject write is unresolved'or'Subject body cleanup needs explicit recovery',detail)
  end
  for i=8,92 do if lease.nodes[i]then
   if same_node(current.nodes[i],lease.original.nodes[i])then lease.nodes[i]=nil
   elseif not write_node(i,current.nodes[i],lease.original.nodes[i],current.mode)then
    -- One bounded, fresh mode-only pass follows a failed body restoration.
    -- It never retries the body setter or resolves uncertain node ownership.
    if lease.mode then return restore(false,true)end
    return false,status.message
   end
  end end
  if lease.mode then
   lease.mode_cleanup_attempted=true
   if current.mode==lease.original.mode then lease.mode=nil
   elseif not write_mode(current.mode,lease.original.mode)then return false,status.message end
  end
  if not commit()then return false,status.message end
  return finish(false,foreign)
 end
 function self.session_current()
  if type(adapter.session_current)~='function'then return true end
  local called,current,why=pcall(adapter.session_current)
  if not called then return nil,tostring(current)end
  return current,why
 end
 function self.refresh(point)
  if not supported then return false,status.message end
  if lease then return false,'Reset the held pose before refreshing subjects'end
  selected=nil;pose=nil;targets,choices={},{}
  local called,found,why=pcall(adapter.discover,resource,4,bank.rig,point)
  if not called or type(found)~='table'or #found>4 then
   state('unselected','Subject discovery unavailable',called and why or found);return false,status.message
  end
  local next_targets,next_choices={},{}
  for i,candidate in ipairs(found)do
   if type(candidate)~='table'or type(candidate.identity)~='string'or #candidate.identity==0 or #candidate.identity>128 or
    candidate.resource~=resource or candidate.node_count~=107 or next_targets[candidate.identity]or
    type(candidate.label)~='string'or #candidate.label>128 then
    state('unselected','Subject discovery returned an invalid candidate');return false,status.message
   end
   next_targets[candidate.identity]=candidate;next_choices[i]={id=candidate.identity,label=candidate.label}
  end
  targets,choices=next_targets,next_choices;state('unselected','Choose a photographic subject explicitly')
  return true,choices
 end
 local explicit_selection=false
 function self.select(id,automatic)
  if not supported then return false,status.message end
  if lease then return false,'Reset the held pose before changing subjects'end
  local candidate=targets[id];if not candidate then return false,'Refresh and explicitly select a listed subject'end
  local called,valid,why=pcall(adapter.valid,candidate,bank.rig)
  if not called or valid~=true then
   selected=nil;state(valid==false and'retired'or'unselected','Selected subject is not available',called and why or valid)
   return false,status.message
  end
  selected=candidate;explicit_selection=not automatic;pose=nil;closing=false;state('selected','Photographic subject selected');return true
 end
 function self.tracking_frame()
  if not selected or not explicit_selection then return nil,'Select your Helldiver explicitly in Subject first'end
  if type(adapter.tracking_frame)~='function'then return nil,'Selected-subject tracking unavailable'end
  return adapter.tracking_frame(selected,bank.rig)
 end
 function self.select_camera(unit,point)
  if lease or type(adapter.camera_target)~='function'then return false end
  local called,target,basis=pcall(adapter.camera_target,unit,bank.rig,point)
  if not called or not target then return false end
  for id,candidate in pairs(targets)do if candidate==target then local ok,why=self.select(id);return ok,ok and basis or why end end
  return false
 end
 -- Automatic choice: the listed subject nearest a world point (the camera).
 function self.select_nearest(point)
  if lease then return false,'Reset the held pose before changing subjects'end
  if type(adapter.position)~='function'then return choices[1]and self.select(choices[1].id,true)or false,'No subject listed'end
  local best,best_distance
  for _,choice in ipairs(choices)do
   local called,p=pcall(adapter.position,targets[choice.id],bank.rig)
   if called and type(p)=='table'then
    local d=(p[1]-point[1])^2+(p[2]-point[2])^2+(p[3]-point[3])^2
    if not best_distance or d<best_distance then best,best_distance=choice.id,d end
   end
  end
  if not best then return false,'No listed subject is available'end
  return self.select(best,true)
 end
 -- Scene choice: the listed subject that owns a picked engine unit handle.
 function self.select_unit(unit)
  if type(adapter.locate)~='function'then return false,'Subject picking unavailable'end
  local target=adapter.locate(unit)
  if not target then return false,'Picked character is not a listed subject'end
  return self.select(target.identity)
 end
 -- Private diagnostic: freeze animation transfer without writing any pose.
 -- It uses the same restoration ledger as authored poses, including partial
 -- mode setters, but never rewinds a root, body node, or cloth transform.
 function self.hold_bone_transfer()
  if not supported or not selected or not explicit_selection then return false,'Select a photographic subject first'end
  if lease or blocked then return false,'Release the current pose before testing bone transfer'end
  local frozen,value=pcall(is_frozen)
  if not frozen or value~=true then return false,'True-zero Freeze Action is required'end
  local current,why=snapshot()
  if not current then return false,why or'Subject snapshot unavailable'end
  if current.mode=='ignore'then return false,'Bone transfer is already held by another owner'end
  lease={identity=selected.identity,original=current,nodes={},commit_pending=false}
  if not write_mode(current.mode,'ignore')then return false,status.message end
  if not commit()then return false,status.message end
  pose='freeze-bone-trial';state('posed','Testing frozen bone transfer');return true
 end
 function self.apply(id)
  if not supported then return false,status.message end
  if blocked then return false,'Recover the pending subject cleanup first'end
  if not selected then return false,'Select a photographic subject first'end
  if not labels[id]then return false,'Unknown subject pose'end
  local frozen,value=pcall(is_frozen)
  if not frozen or value~=true then return false,'True-zero Freeze Action is required'end
  local prepared
  if not(lease and pose==id)then
   local why,detail;prepared,why,detail=prepare(id)
   if not prepared then state(lease and'posed'or'selected',why,detail);return false,status.message end
  end
  local current,why=snapshot()
  if current==false then finish(true);return false,status.message end
  if not current then
   if lease then return pending('Subject ownership is unknown',why)end
   state('selected','Subject snapshot unavailable',why);return false,status.message
  end
  if lease then
   if current.matrix~=lease.original.matrix then return pending('Subject snapshot representation changed; recover without guessing ownership')end
   local expected_mode=lease.mode and lease.mode.value or lease.original.mode
   if current.mode~=expected_mode then lease.foreign=true;return pending('Subject mode changed; recover without overwriting it')end
   for i=8,92 do
    local expected=lease.nodes[i]and lease.nodes[i].value or lease.original.nodes[i]
    if not same_node(current.nodes[i],expected)then lease.foreign=true;return pending('Subject body changed; recover without overwriting it')end
   end
   if pose==id then return true end
  end
  local nodes=prepared.nodes
  if not prepared.full_body then nodes[8]=lease and lease.original.nodes[8]or current.nodes[8]end
  -- Check every target before acquiring a lease or changing animation mode.
  -- Canonicalization may introduce matrices; preserved root8 uses its baseline.
  for i=8,92 do if(nodes[i].pose~=nil)~=current.matrix then
   state(lease and'posed'or'selected','Subject target representation does not match its snapshot')
   return false,status.message
  end end
  if not lease then lease={original=current,nodes={},commit_pending=false}end
  pose=nil
  if current.mode~='ignore'and not write_mode(current.mode,'ignore')then return false,status.message end
  for i=8,92 do if not same_node(current.nodes[i],nodes[i])then
   if not write_node(i,current.nodes[i],nodes[i],'ignore')then return false,status.message end
  end end
  if not commit()then return false,status.message end
  pose=id;status.restored=false;state('posed',labels[id]..' held on the selected subject');return true
 end
 function self.reset()
  closing=false;pose=nil
  if blocked then
   if lease and lease.mode and not lease.mode_cleanup_attempted then return restore(false,true)end
   status.pose=nil;return false,status.message
  end
  return restore()
 end
 function self.recover()return restore(true)end
 function self.close()
  closing=true;pose=nil
  if blocked then
   if lease and lease.mode and not lease.mode_cleanup_attempted then return restore(false,true)end
   status.pose=nil;return false,status.message
  end
  return restore()
 end
 function self.maintain()
  if not lease or not pose or blocked or type(adapter.maintain)~='function'then return true end
  local frozen,value=pcall(is_frozen)
  if not frozen or value~=true then return self.reset()end
  local called,ok,why=pcall(adapter.maintain,selected,bank.rig)
  if not called or ok~=true then return pending('Cape alignment needs explicit recovery',called and why or ok)end
  return true
 end
 function self.resume()return self.reset()end
 function self.invalidate()closing=true;return restore()end
 function self.choices()return choices end
 function self.status()return status end
 return self
end
return M

-- Private selected-character experiment: replay one coherent skeleton, never
-- separately captured accessory/cape roots. Exact-zero owner gates every pass.
-- Only copied scalars survive callbacks. Cleanup restores bone transfer, never
-- rewinds a pose or advances simulation. No discovery or work outside the trial.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-freeze-pose-probe.request';local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='freeze-pose-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function equal(a,b)for i=1,12 do if a[i]~=b[i]then return false end end;return true end
function M.new(sr,log,measure,options)
 local cape=options and options.cape
 local continuous=options and options.continuous==true
 local claim_transfer=not continuous or options and options.claim_transfer==true
 local exclude_cape=options and options.exclude_cape==true
 local U,W,A,N,I,B=sr.Unit,sr.World,sr.Application,sr.Network,sr.IdString64,sr.Matrix4x4
 local bindings={}
 for _,name in ipairs({'alive','world','resource_name','num_scene_graph_items','local_pose','set_local_pose','animation_bone_mode','set_animation_bone_mode'})do
  assert(type(U[name])=='function','Pose trial API unavailable: '..name);bindings[name]=U[name]
 end
 if exclude_cape then for _,name in ipairs({'has_node','node'})do
  assert(type(U[name])=='function','Cape exclusion API unavailable: '..name);bindings[name]=U[name]
 end end
 local update=W.update_unit;assert(type(update)=='function','Pose trial scene refresh unavailable')
 local self={};local work;local attempts=0;local pending
 local function emit(s)pcall(log,(continuous and'Freeze skeleton hold: 'or'Freeze pose probe: ')..s)end
 local function clock()local n=measure();assert(finite(n)and n>=0,'Pose trial clock unavailable');return n end
 local function valid(w)
  assert(sr.Unit==U and sr.World==W and W.update_unit==update,'Pose trial binding changed')
  for name,fn in pairs(bindings)do assert(U[name]==fn,'Pose trial binding changed: '..name)end
  if N.game_session()~=w.session or A.main_world()~=w.world then return false end
  local alive=U.alive(w.unit);if alive==false then return false end
  assert(alive==true and U.world(w.unit)==w.world,'Pose trial unit world unavailable')
  assert(U.num_scene_graph_items(w.unit)==107,'Pose trial rig changed')
  assert(I.equal(U.resource_name(w.unit),I.from_hex('4d1c334d294dfa97'))==true,'Pose trial resource changed')
  return true
 end
 local function matrix(w,index)
  local value={B.to_elements(U.local_pose(w.unit,index))};assert(#value==12,'Pose trial matrix shape changed')
  for i=1,12 do assert(finite(value[i]),'Pose trial matrix invalid')end;return value
 end
 function self.active()return work~=nil end
 -- A body frozen mid-stride: the game's own animation keeps putting its original mode back.
 -- Take it back, and on the first time pause the body's animation state machine until
 -- release, so the game stops fighting the hold (taking it back every frame flickered and
 -- left the arms in a weird pose, live 2026-10-29). Marked before the call: a setter may act
 -- and then throw.
 local function take_back(w,counter)
  assert(U.set_animation_bone_mode(w.unit,'ignore')~=false,'Pose trial bone mode refused')
  if not w.machine_paused and type(U.disable_animation_state_machine)=='function'and type(U.enable_animation_state_machine)=='function'and
   type(U.has_animation_state_machine)=='function'and U.has_animation_state_machine(w.unit)==true then
   w.machine_paused=true;U.disable_animation_state_machine(w.unit)
   emit('animation paused on the frozen body until Resume (the game kept taking it back)')
  elseif not w.reclaims and not w.update_reclaims then emit('bone mode taken back from the game\'s own animation (body frozen while moving)')end
  w[counter]=(w[counter]or 0)+1
 end
 function self.release(why,retry)
  if not work then return true end
  if pending and retry~=true then return false,pending end
  local w=work
  local ok,result=pcall(function()
   if w.cape then w.cape_writes=w.cape.writes;assert(cape.release(w.cape),'Cape restoration unavailable');w.cape=nil end
   if not w.issued then return 'no mode override' end
   if not valid(w)then w.machine_paused=nil;return 'subject retired' end
   -- The paused animation runs again before the original mode returns.
   if w.machine_paused then U.enable_animation_state_machine(w.unit);w.machine_paused=nil end
   local current=U.animation_bone_mode(w.unit)
   assert(type(current)=='string','Pose trial cleanup mode unavailable')
   if current=='ignore'then
    assert(U.set_animation_bone_mode(w.unit,w.mode)~=false,'Pose trial mode restoration refused')
    assert(U.animation_bone_mode(w.unit)==w.mode,'Pose trial mode restoration unconfirmed')
    return 'bone mode restored'
   end
   return current==w.mode and 'original mode already restored'or 'foreign mode preserved'
  end)
  if not ok then pending=tostring(result);emit('cleanup pending: '..pending);return false,pending end
  if w.cape_writes then emit('cape placement restored; writes='..w.cape_writes)end
  emit(string.format('released: %s; reason=%s renders=%d writes=%d max_step_ms=%.3f; takebacks update=%d render=%d; no pose rewind',result,tostring(why),w.renders,w.writes,w.max_ms,w.update_reclaims or 0,w.reclaims or 0))
  work=nil;pending=nil;return true
 end
 function self.start(subject,now)
  if work or not continuous and attempts>=2 then return false,'Skeleton trial busy or exhausted'end
  local ok,value=pcall(function()
   assert(type(subject)=='table'and type(subject.tracking_frame)=='function','Select a Helldiver first')
   assert(finite(now),'Pose trial clock unavailable')
   local began=clock();local f=assert(subject.tracking_frame())
   assert(f.explicit_subject==true and type(f.identity)=='string'and type(f.root_handle)=='userdata'and type(f.world)=='userdata','Selected subject unavailable')
   local w={unit=f.root_handle,world=f.world,session=N.game_session(),identity=f.identity,subject=subject,
    poses={},indices={},started=now,deadline=continuous and math.huge or now+6,renders=0,writes=0,max_ms=0,samples=0,next_at=now}
   assert(type(w.session)=='userdata'and valid(w),'Pose trial subject retired')
   w.mode=U.animation_bone_mode(w.unit)
   assert(w.mode=='position_and_rotation','Release the held pose before testing the skeleton')
   if exclude_cape then for i=1,8 do
    local name='cape'..i
    assert(U.has_node(w.unit,name)==true and U.node(w.unit,name)==34+i,'Cape exclusion rig changed')
   end end
   for index=1,107 do if not(exclude_cape and index>=35 and index<=42)then
    w.indices[#w.indices+1]=index;w.poses[index]=matrix(w,index)
   end end
   assert(valid(w)and U.animation_bone_mode(w.unit)==w.mode,'Pose trial capture changed')
   if cape then
    local captured,record=pcall(cape.capture,f)
    if captured then w.cape=record;emit('cape placement captured; nodes='..#record.meshes..'; authored-pose solver; shoulder_right_flip='..tostring(record.flip==true)..'; cloth simulation untouched')
    else emit('cape placement unavailable: '..tostring(record))end
   end
   w.max_ms=(clock()-began)*1000;assert(w.max_ms<=8,'Pose capture exceeded eight millisecond budget')
   return w
  end)
  if not ok then return false,tostring(value)end
  attempts=attempts+1;work=value
  emit(string.format('captured selected skeleton; nodes=%d; cape_bones=%s; %s; capture_ms=%.3f; separate cape/accessory root writes=0; awaiting owned render',#work.indices,exclude_cape and'excluded'or'included',(continuous and'before zero; until Resume'or'six seconds')..'; claim_transfer='..tostring(claim_transfer==true),work.max_ms))
  return true
 end
 if continuous then function self.prepare(subject,now)
  local ok,why=self.release('new Freeze preparation');if not ok then return false,why end
  -- Missing photographic selection is not proof that no character is moving.
  -- Preserve ordinary Freeze, but do not invent a body or claim it was held.
  if not subject or type(subject.tracking_frame)~='function'then emit('no selected character; no skeleton acquired');return true end
  local called,frame=pcall(subject.tracking_frame)
  if not called or not frame then emit('selected character unavailable; no skeleton acquired');return true end
  return self.start(subject,now)
 end end
 function self.tick(enabled,now)
  if not work then return true end
  if pending then return false,pending end
  if not enabled or not finite(now)or now<work.started or now>=work.deadline then return self.release('trial ended')end
  -- The game resets the body's mode during its update; taking it back only at render showed
  -- one animated frame. Take it back here too, before the body is drawn. A foreign owner is
  -- left for render to report.
  local w=work
  if claim_transfer and w.issued then
   local called,problem=pcall(function()
    if not valid(w)then return end
    if U.animation_bone_mode(w.unit)==w.mode then
     take_back(w,'update_reclaims')
    end
   end)
   if not called and not w.update_fault then w.update_fault=true;emit('update takeback failed: '..tostring(problem))end
  end
  return true
 end
 function self.render(enabled,now)
  local ok,why=self.tick(enabled,now);if not ok or not work then return ok,why end
  local w=work
  local called,problem=pcall(function()
   local began=clock();assert(valid(w),'Pose trial subject retired')
   local frame=assert(w.subject.tracking_frame())
   assert(frame.explicit_subject==true and frame.identity==w.identity and frame.root_handle==w.unit and frame.world==w.world,'Pose trial selection changed')
   local mode=U.animation_bone_mode(w.unit)
   if not claim_transfer then
    assert(mode==w.mode,'Freeze skeleton bone mode changed')
   elseif not w.issued then
    assert(mode==w.mode,'Pose trial bone mode changed before acquisition')
    w.issued=true -- A setter may mutate then throw: retain cleanup responsibility.
    assert(U.set_animation_bone_mode(w.unit,'ignore')~=false,'Pose trial bone mode refused')
   elseif mode~='ignore'then
    -- A body frozen mid-stride: the game's own animation puts its original mode back.
    -- Freeze holds this body until Resume, so take it back; any other mode is a foreign
    -- owner (ragdoll and the like) and is left alone.
    assert(mode==w.mode,'Pose trial bone transfer ownership lost to '..tostring(mode))
    take_back(w,'reclaims')
   end
   local expected_mode=claim_transfer and'ignore'or w.mode
   assert(U.animation_bone_mode(w.unit)==expected_mode,'Pose trial bone transfer unconfirmed')
   local trace=w.cape and cape.trace and now>=w.next_at
   if trace then cape.trace(w.cape,'sample'..(w.samples+1)..'_before_body')end
   local changed=0;local root_changed=false;local changed_indices=now>=w.next_at and{}or nil
   -- With the animation paused, the game still places the root (bone 1) every frame where
   -- the moving body got to; writing the captured root back jittered (flicker). The root is
   -- the game's; the other bones stay held relative to it.
   if w.machine_paused then w.poses[1]=matrix(w,1)end
   for _,index in ipairs(w.indices)do
    if not equal(matrix(w,index),w.poses[index])then
     local desired=B.from_elements(unpack(w.poses[index]))
     assert(U.set_local_pose(w.unit,index,desired)~=false,'Pose trial node write refused')
     changed=changed+1;w.writes=w.writes+1;root_changed=root_changed or index==1
     if changed_indices then changed_indices[#changed_indices+1]=index end
    end
   end
   if changed>0 then assert(update(w.world,w.unit)~=false,'Pose trial scene refresh refused')end
   if trace then cape.trace(w.cape,'sample'..(w.samples+1)..'_after_body')end
   if w.cape and(changed>0 or now>=w.next_at)then cape.apply(w.cape,frame)end
   assert(valid(w)and U.animation_bone_mode(w.unit)==expected_mode,'Pose trial ownership changed during replay')
   if now>=w.next_at then
    local mismatches,detail=0,{}
    for _,index in ipairs(w.indices)do
     local now_pose,held=matrix(w,index),w.poses[index]
     if not equal(now_pose,held)then
      mismatches=mismatches+1
      -- Which bone, and by how much: largest element difference and translation shift.
      local worst,shift=0,0
      for i=1,12 do worst=math.max(worst,math.abs(now_pose[i]-held[i]))end
      for i=10,12 do shift=shift+(now_pose[i]-held[i])^2 end
      if #detail<8 then detail[#detail+1]=string.format('%d:%.3g/%.3gm',index,worst,math.sqrt(shift))end
     end
    end
    w.samples=w.samples+1;w.next_at=w.samples==1 and now+.5 or w.samples==2 and w.started+2 or w.samples==3 and w.started+4 or math.huge
    emit(string.format('sample=%d changed_nodes=%d root_changed=%s mismatches=%d indices=%s; cape_bones=%s; cape_placement_writes=%d',w.samples,changed,tostring(root_changed),mismatches,table.concat(changed_indices,','),exclude_cape and'excluded'or'included',w.cape and w.cape.writes or 0))
    assert(mismatches==0,'Pose trial readback mismatch: '..table.concat(detail,' '))
   end
   w.renders=w.renders+1;w.max_ms=math.max(w.max_ms,(clock()-began)*1000)
   assert(w.max_ms<=8,'Pose replay exceeded eight millisecond budget')
  end)
  if not called then
   emit('stopped: '..tostring(problem))
   local released,reason=self.release('render stopped')
   return false,released and tostring(problem)or reason
  end
  return true
 end
 return self
end
return M

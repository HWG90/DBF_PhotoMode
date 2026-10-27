-- Private Windows candidate: hold observed Unit root poses only while Photo
-- Mode owns zero time. Uses existing render lifecycle, never native hooks.
-- Physics can replace roots between updates: compare once per render, write
-- only changed roots. No rediscovery after the bounded activation scan.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-freeze-root-hold.request';local f=io.open(path,'rb');if not f then return false end
 local text=f:read(64);f:close()
 return text=='freeze-root-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
function M.consume_flip(folder,pid)
 local path=folder..'/wj-freeze-body-flip.request';local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='body-flip-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
function M.consume_observe(folder,pid)
 local path=folder..'/wj-freeze-root-observe.request';local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='root-observe-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
function M.new(sr,now,measure,log,cape_observer,options)
 local A,W,U,I,V,B,Q=sr.Application,sr.World,sr.Unit,sr.IdString64,sr.Vector3,sr.Matrix4x4,sr.Quaternion
 local self={};local state;local disabled=false;local prepared
 local pelvis_only=options and options.pelvis_only==true
 local world_anchor=options and options.world_anchor==true
 local bone_only=pelvis_only or world_anchor
 local held_node=world_anchor and 8 or pelvis_only and 10 or 1
 local held_name=world_anchor and 'boss'or'hips'
 local held_parent=world_anchor and 5 or 8
 local function topology(unit)return U.has_node(unit,held_name)==true and U.node(unit,held_name)==held_node and U.scene_graph_parent(unit,held_node)==held_parent end
 local observe_next=options and options.observe_once==true
 local function matrix(unit,node,world)
  local p={B.to_elements(world and U.world_pose(unit,node or 1)or U.local_pose(unit,node or 1))};assert(#p==12,'Root matrix shape changed')
  for i=1,12 do assert(finite(p[i]),'Root matrix invalid')end;return p
 end
 local function equal(a,b,tolerance)for i=1,12 do if math.abs(a[i]-b[i])>(tolerance or 0)then return false end end;return true end
 local function root_values(unit)
  local p=U.local_position(unit,1);local q={Q.to_elements(U.local_rotation(unit,1))}
  local result={V.x(p),V.y(p),V.z(p),unpack(q)}
  assert(#result==7,'Root scalar getter shape changed');for _,v in ipairs(result)do assert(finite(v),'Root scalar getter invalid')end
  return result
 end
 local function clock()local n=measure();assert(finite(n)and n>=0,'Root hold clock unavailable');return n end
 local function retire(reason)
  if state then log(string.format('Freeze root hold: released roots=%d writes=%d renders=%d retired=%d cape_updates=%d max_scan_ms=%.3f max_hold_ms=%.3f reason=%s; no pose rewind',#state.rows,state.writes,state.renders,state.retired,state.cape_updates,state.scan_ms,state.hold_ms,reason))end
  state=nil
 end
 local function valid(r)
  if U.alive(r.unit)~=true then return false,'dead'end
  if U.world(r.unit)~=state.world then return false,'world'end
  if U.num_scene_graph_items(r.unit)~=r.count then return false,'graph'end
  if U.num_cameras(r.unit)~=0 then return false,'camera'end
  if bone_only and not topology(r.unit)then return false,'held bone topology'end
  if not r.helldiver and U.num_lights(r.unit)~=0 then return false,'light'end
  -- IdString64 values, like matrices, may be backed by frame scratch storage.
  -- Retain the numeric identity as hex text; rebuild both IDs for this check.
  local expected=I.from_hex(r.resource)
  if I.equal(U.resource_name(r.unit),expected)~=true then return false,'resource'end
  return true
 end
 -- Read the final positive-time roots before submitting exact zero. Capturing
 -- after the first zero-time update can otherwise save an already displaced
 -- physics/animation result as the supposedly frozen target.
 function self.prepare()
  prepared=nil
  local ok,why=pcall(function()
   local began=clock();local world=assert(A.main_world(),'Root preparation world unavailable')
   local units=W.units_by_resource(world,I.from_hex('4d1c334d294dfa97'))
   assert(type(units)=='table','Root preparation inventory unavailable')
   local rows={};local captured,scanned=0,0;local truncated=false
   for _,unit in pairs(units)do
    if scanned>=128 or captured>=32 or clock()-began>=.002 then truncated=true;break end
    scanned=scanned+1
    if type(unit)=='userdata'and U.alive(unit)==true and U.world(unit)==world and U.num_scene_graph_items(unit)==107
     and U.num_cameras(unit)==0 and I.equal(U.resource_name(unit),I.from_hex('4d1c334d294dfa97'))==true then
     if not bone_only or topology(unit)then
      rows[unit]={pose=matrix(unit,held_node,world_anchor),scalars=not bone_only and root_values(unit)or nil};captured=captured+1
     end
    end
   end
   assert(A.main_world()==world,'Root preparation world changed')
   prepared={world=world,at=now(),rows=rows}
   log(string.format('Freeze root preparation: captured=%d scanned=%d truncated=%s before_zero=true max_ms=%.3f; reads only',captured,scanned,tostring(truncated),(clock()-began)*1000))
  end)
  if not ok then prepared=nil;return false,tostring(why)end
  return true
 end
 local function candidate(unit,priority)
  if type(unit)~='userdata'or state.seen[unit]or U.alive(unit)~=true or U.world(unit)~=state.world then return end
  local cameras,lights,count=U.num_cameras(unit),U.num_lights(unit),U.num_scene_graph_items(unit)
  local resource=tostring(U.resource_name(unit)):match('0x(%x+)')
  assert(resource and #resource==16,'Unit resource hex unavailable')
  resource=resource:lower()
  local helldiver=count==107 and resource=='4d1c334d294dfa97'
  if bone_only and not helldiver then return end
  if bone_only and not topology(unit)then return end
  if priority then log('Freeze root eligibility: resource='..tostring(resource)..' nodes='..tostring(count)..' cameras='..tostring(cameras)..' lights='..tostring(lights)..' helldiver='..tostring(helldiver))end
  -- A known character may contain lights; that alone does not make it a
  -- standalone light. All camera units and other light-bearing units stay out.
  if cameras~=0 or (lights~=0 and not helldiver)then return end
  if not(finite(count)and count>=2 and count<=512)then return end
  -- A garment is not an independently frozen gameplay root. Leave its native
  -- cloth/attachment graph completely alone, including its root and refresh.
  if not helldiver and type(U.has_node)=='function'and U.has_node(unit,'cape1')==true
   and U.has_node(unit,'cape2')==true and U.has_node(unit,'cape3')==true then return end
  local p=U.world_position(unit,1);local x,y,z=V.x(p),V.y(p),V.z(p)
  assert(finite(x)and finite(y)and finite(z),'Root position invalid')
  local d=(x-state.point[1])^2+(y-state.point[2])^2+(z-state.point[3])^2;if d>2500 then return end
  local rows=state.rows;local at=#rows+1
  for i,r in ipairs(rows)do if priority and not r.priority or priority==r.priority and d<r.distance then at=i;break end end
  if at>32 then return end
  local row={unit=unit,count=count,resource=resource,distance=d,priority=priority,helldiver=helldiver,node=held_node,pose=matrix(unit,held_node,world_anchor)}
  local baseline=helldiver and state.prepared and state.prepared[unit]
  if baseline then
   local drift=0;for i=1,12 do drift=math.max(drift,math.abs(row.pose[i]-baseline.pose[i]))end
   row.pose=baseline.pose;row.pre_zero=true
   log(string.format('Freeze root baseline: before_zero=true initial_component_drift=%.9g target_position=%.9g,%.9g,%.9g',drift,row.pose[10],row.pose[11],row.pose[12]))
  end
  if priority and not bone_only then
   row.scalars=baseline and baseline.scalars or root_values(unit);row.check_at=now()+.5;row.checks=0
   log('Freeze root hold: captured priority resource='..tostring(resource)..' distance_m='..math.sqrt(d))
  end
  table.insert(rows,at,row);state.seen[unit]=true
  if row.helldiver then state.cape_probe_dirty=true end
  if #rows>32 then local old=table.remove(rows);state.seen[old.unit]=nil end
 end
 local function scan(point)
  local began=clock()
  if not state then
   local world=assert(A.main_world(),'Root world unavailable')
   state={world=world,point={point[1],point[2],point[3]},rows={},seen={},scanned=0,key=nil,
    lane='helldiver',writes=0,renders=0,retired=0,cape_updates=0,scan_ms=0,hold_ms=0,started=now(),observe=observe_next}
   observe_next=false
   if state.observe then log('Freeze root isolation: this Freeze is read-only; body/root/cape setters=0; next Freeze restores root holding')end
   if prepared and prepared.world==world and state.started>=prepared.at and state.started-prepared.at<=1 then state.prepared=prepared.rows end
   prepared=nil
   state.units=W.units_by_resource(world,I.from_hex('4d1c334d294dfa97'))
   assert(type(state.units)=='table','Helldiver root inventory unavailable')
   log('Freeze root hold: acquiring; Helldivers first; at most 32 nearby roots; cameras and non-character lights excluded; no bone-mode or physics changes')
  end
  if A.main_world()~=state.world then retire('world changed');disabled=true;return end
  if not state.units then return end
  local n=0
  while n<64 and clock()-began<.002 do
   local key,unit=next(state.units,state.key);state.key=key
   local limit=state.lane=='helldiver'and 128 or 16384
   if key==nil or state.scanned>=limit then
    if state.lane=='helldiver'then
     if state.observe or bone_only then state.units=nil;break end
     state.units=W.units(state.world);assert(type(state.units)=='table','Nearby root inventory unavailable')
     state.lane='nearby';state.key=nil;state.scanned=0;break
    end
    log('Freeze root hold: inventory finished roots='..#state.rows..' scanned='..state.scanned..' truncated='..tostring(key~=nil))
    state.units=nil;break
   end
   state.scanned=state.scanned+1;n=n+1
   candidate(unit,state.lane=='helldiver')
  end
  state.scan_ms=math.max(state.scan_ms,(clock()-began)*1000)
  if state.units and now()-state.started>10 then state.units=nil;log('Freeze root hold: ten-second discovery budget; retaining only captured roots')end
 end
 function self.tick(enabled,point)
  if not enabled then retire('Freeze released or pose ownership yielded');disabled=false;return true end
  if disabled then return true end
  -- Closed/steady discovery stays idle. The render pass validates held handles.
  if state and not state.units then return true end
  local ok,why=pcall(scan,point)
  if not ok then retire('discovery failed');disabled=true;log('Freeze root hold disabled: '..tostring(why));return false,tostring(why)end
  return true
 end
 function self.render(enabled)
  if not enabled then retire('Render no longer owns Freeze');return true end
  if not state or disabled then return true end
  local ok,why=pcall(function()
   local began=clock()
   state.renders=state.renders+1
   if state.renders==1 then log('Freeze root hold: first render roots='..#state.rows)end
   if A.main_world()~=state.world then retire('world changed');disabled=true;return end
   local cape_pair
   if cape_observer and state.cape_probe_dirty then
    state.cape_probe_dirty=false;cape_pair=cape_observer.before(state.rows,state.world)
   end
   local body_changed=false
   for i=#state.rows,1,-1 do
    local r=state.rows[i]
    local alive,reason=valid(r)
    if not alive then
     state.retired=state.retired+1
     if r.priority or state.retired<=3 then log('Freeze root hold: retired resource='..r.resource..' reason='..reason)end
     state.seen[r.unit]=nil;table.remove(state.rows,i)
    else
     local current=matrix(r.unit,r.node,world_anchor)
     if r.check_at and now()>=r.check_at then
      local values=root_values(r.unit);local drift=0
      for j=1,7 do drift=math.max(drift,math.abs(values[j]-r.scalars[j]))end
      log('Freeze root getter check: resource='..tostring(r.resource)..' scalar_drift='..drift..' matrix_changed='..tostring(not equal(current,r.pose)))
      r.checks=r.checks+1;r.check_at=r.checks<2 and now()+1 or nil
     end
     if not state.observe and not equal(current,r.pose,world_anchor and .0001 or 0)then
      local desired=B.from_elements(unpack(r.pose))
      if world_anchor then
       -- Keep the body anchor fixed in world space without writing its root.
       -- Stingray composes local * parent; derive local against THIS parent.
       local parent=matrix(r.unit,held_parent,true)
       local det=parent[1]*(parent[5]*parent[9]-parent[6]*parent[8])-parent[2]*(parent[4]*parent[9]-parent[6]*parent[7])+parent[3]*(parent[4]*parent[8]-parent[5]*parent[7])
       assert(math.abs(det)>.0001,'Body anchor parent is singular')
       desired=B.multiply(B.from_elements(unpack(r.pose)),B.inverse(B.from_elements(unpack(parent))))
      end
      local expected={B.to_elements(desired)};assert(#expected==12,'Held local pose shape changed')
      for _,value in ipairs(expected)do assert(finite(value),'Held local pose invalid')end
      assert(U.set_local_pose(r.unit,r.node or 1,desired)~=false,'Held node setter refused')
      -- Do not force another Helldiver scene-graph evaluation at zero time.
      -- Its native pose/cloth transfers run in the normal world lifecycle.
      if not r.helldiver then assert(W.update_unit(state.world,r.unit)~=false,'Root render update refused')end
      assert(equal(matrix(r.unit,r.node),expected),r.helldiver and'Root pose readback differs after setter'or'Root pose readback differs after scene update')
      state.writes=state.writes+1
      body_changed=body_changed or r.helldiver and not r.unflipped
      if not r.reported then r.reported=true;log('Freeze root hold: correcting resource='..tostring(r.resource)..' nodes='..r.count..'; held_node='..tostring(r.node or 1)..'; world_anchor='..tostring(world_anchor==true)..'; pelvis_only='..tostring(pelvis_only==true)..'; teleport=false'..'; forced_scene_update='..tostring(not r.helldiver)..'; visual acceptance pending')end
     end
    end
   end
   if cape_observer then cape_observer.after(cape_pair,body_changed)end
   state.hold_ms=math.max(state.hold_ms,(clock()-began)*1000)
  end)
  if not ok then retire('render hold failed');disabled=true;log('Freeze root hold disabled: '..tostring(why));return false,tostring(why)end
  return true
 end
 -- Explicit private test. Change only the selected body's held root target;
 -- no cape/bone setters, relinks, negative scale, physics or time changes.
 -- A half-turn around the root's right axis keeps the chest pivot fixed.
 function self.flip_body(frame)
  if not state or disabled or type(frame)~='table'or frame.explicit_subject~=true or frame.world~=state.world then
   return false,'Select the frozen Helldiver explicitly first'
  end
  if bone_only then return false,'Body flip unavailable during bone-only trial'end
  local row
  for _,r in ipairs(state.rows)do if r.unit==frame.root_handle and r.helldiver then row=r;break end end
  if not row then return false,'Selected body is not held by Freeze'end
  local ok,why=pcall(function()
   assert(valid(row),'Selected body changed')
   if row.unflipped then
    row.pose=row.unflipped;row.unflipped=nil
    log('Freeze body flip: undo queued; body root only');return
   end
   local current=matrix(row.unit);local world={B.to_elements(U.world_pose(row.unit,1))}
   for i=1,12 do assert(finite(world[i])and math.abs(current[i]-world[i])<1e-4,'Body root must be unparented')end
   assert(U.has_node(row.unit,'chest')==true,'Chest pivot unavailable')
   local node=U.node(row.unit,'chest');assert(node==29,'Chest pivot rig changed')
   local p=U.world_position(row.unit,node);local delta={V.x(p)-current[10],V.y(p)-current[11],V.z(p)-current[12]}
   for _,v in ipairs(delta)do assert(finite(v),'Chest pivot invalid')end
   -- Verify an orthonormal basis before using its transpose as the inverse.
   for a=0,2 do for b=0,2 do
    local dot=0;for k=1,3 do dot=dot+current[a*3+k]*current[b*3+k]end
    assert(math.abs(dot-(a==b and 1 or 0))<.001,'Body root basis is not rigid')
   end end
   local local_y,local_z=0,0
   for k=1,3 do local_y=local_y+delta[k]*current[k+3];local_z=local_z+delta[k]*current[k+6]end
   local desired={unpack(row.pose)}
   for k=1,3 do
    desired[k+9]=row.pose[k+9]+2*(row.pose[k+3]*local_y+row.pose[k+6]*local_z)
    desired[k+3]=-row.pose[k+3];desired[k+6]=-row.pose[k+6]
   end
   for _,v in ipairs(desired)do assert(finite(v),'Flipped root invalid')end
   row.unflipped=row.pose;row.pose=desired
   log('Freeze body flip: 180-degree pitch around chest queued; body root only; cape writes=0; visual test')
  end)
  return ok,ok and'Body flip toggled; press again to undo, Resume ends the test'or tostring(why)
 end
 function self.release()prepared=nil;retire('explicit release');disabled=false;return true end
 return self
end
return M

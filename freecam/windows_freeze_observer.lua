-- Explicit, read-only development capture. One scan per Freeze transition,
-- Helldivers first, then a bounded nearby multi-node scan. Four completed
-- captures / sixteen attempts maximum. Never changes time or poses.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-freeze-observer.request'
 local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='freeze-state-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function delta(a,b)
 local p=0;for i=1,3 do p=p+(a.p[i]-b.p[i])^2 end
 local dot=0;for i=1,4 do dot=dot+a.q[i]*b.q[i]end
 return math.sqrt(p),math.deg(2*math.acos(math.min(1,math.abs(dot))))
end
function M.new(sr,now,measure,log,animation_source)
 local A,W,U,V,Q=sr.Application,sr.World,sr.Unit,sr.Vector3,sr.Quaternion
 local self={};local previous=false;local episode=0;local completed=0;local work;local stopped=false
 local function stamp()local n=measure();assert(finite(n)and n>=0,'Observer clock unavailable');return n end
 local function valid(unit,world)return U.alive(unit)==true and U.world(unit)==world end
 local function root_source(row)
  assert(valid(row.unit,work.world)and U.num_scene_graph_items(row.unit)==107,'Root source subject retired')
  assert(tostring(U.resource_name(row.unit))==row.resource,'Root source identity changed')
  assert(U.animation_root_mode(row.unit)=='ignore','Root source mode changed')
  local function matrix(value)
   local numbers={sr.Matrix4x4.to_elements(value)};assert(#numbers==12,'Root source matrix shape changed')
   for i=1,12 do assert(finite(numbers[i]),'Root source matrix invalid')end
   return numbers
  end
  local actual=matrix(U.world_pose(row.unit,1))
  local wanted=matrix(U.animation_wanted_root_pose(row.unit))
  local movement=matrix(U.delta_pose(row.unit,1))
  local dt=W.delta_time(work.world);assert(finite(dt),'World delta unavailable')
  local source={actual=actual,wanted=wanted,movement=movement,dt=dt}
  if work.animation_map then
   local ok,values,why=pcall(work.animation_map.read,row.unit)
   if ok and values then source.animation=values else source.animation_error=tostring(ok and why or values):sub(1,160):gsub('%c',' ')end
  end
  return source
 end
 local function source_log(prefix,source)
  local function csv(numbers)local fields={};for i=1,#numbers do fields[i]=string.format('%.9g',numbers[i])end;return table.concat(fields,',')end
  log(prefix..' world_dt='..string.format('%.9g',source.dt)..' actual='..csv(source.actual)..' wanted='..csv(source.wanted)..' delta='..csv(source.movement)..
   (source.animation and' animation_delta='..csv(source.animation)or source.animation_error and' animation_unavailable='..source.animation_error or''))
 end
 local function pose(unit,index,local_space)
  local p=(local_space and U.local_position or U.world_position)(unit,index)
  local q=(local_space and U.local_rotation or U.world_rotation)(unit,index)
  local values={Q.to_elements(q)};assert(#values==4,'Quaternion shape changed')
  local xyz={V.x(p),V.y(p),V.z(p)};local norm=0
  for i=1,3 do assert(finite(xyz[i]),'Position invalid')end
  for i=1,4 do assert(finite(values[i]),'Rotation invalid');norm=norm+values[i]^2 end
  assert(math.abs(norm-1)<.01,'Rotation not normalized')
  norm=math.sqrt(norm);for i=1,4 do values[i]=values[i]/norm end
  return{p=xyz,q=values}
 end
 local function frame(row)
  assert(valid(row.unit,work.world),'Unit retired')
  local count=U.num_scene_graph_items(row.unit);assert(count==row.count,'Unit graph changed')
  local result={root=pose(row.unit,1,false),bones={},world_bones={}};local indices={}
  -- Read only at the three existing capture samples, never continuously.
  -- Actor/PhysicsWorld are absent in the current Windows Lua environment.
  if type(U.has_animation_blender)=='function'and U.has_animation_blender(row.unit)==true then
   for _,kind in ipairs({'root','bone'})do
    local getter=U['animation_'..kind..'_mode']
    if type(getter)=='function'then
     local ok,value=pcall(getter,row.unit)
     result[kind..'_mode']=ok and(type(value)=='string'or type(value)=='number')and tostring(value):sub(1,64)or'unavailable'
    end
   end
  end
  -- Only the qualified Helldiver lane reads animation-requested root motion.
  -- Copy matrices immediately; native scratch objects never survive callbacks.
  if work.lane=='helldiver'and row.count==107 and row.resource:find('4d1c334d294dfa97',1,true)and result.root_mode=='ignore'then
   local ok,source=pcall(root_source,row)
   if ok then result.root_source=source else result.root_source_error=tostring(source):sub(1,160):gsub('%c',' ')end
  end
  -- Include the ancestor chain: spinning can occur above hips while hips-local
  -- rotation remains unchanged. World samples also expose inherited movement.
  for i=1,math.min(count,12)do indices[i]=true end
  for _,name in ipairs({'hips','head'})do
   if U.has_node(row.unit,name)==true then
    local i=U.node(row.unit,name);assert(finite(i)and i%1==0 and i>=1 and i<=count,'Node index invalid');indices[i]=true
   end
  end
  for i in pairs(indices)do result.bones[i]=pose(row.unit,i,true);result.world_bones[i]=pose(row.unit,i,false)end
  return result
 end
 local function cancel(reason)
  if work then log('Freeze observer: episode='..episode..' stopped='..reason);work=nil end
 end
 local function start(world,point)
  local began=stamp()
  episode=episode+1
  local units=W.units_by_resource(world,sr.IdString64.from_hex('4d1c334d294dfa97'));assert(type(units)=='table','Helldiver unit list unavailable')
  work={world=world,point={point[1],point[2],point[3]},units=units,key=nil,scanned=0,rows={},phase='scan',
   max_ms=(stamp()-began)*1000,errors=0,started=now(),truncated=false,lane='helldiver',lane_scanned=0,seen={},total_units=0}
  log('Freeze observer: episode='..episode..' started; read-only; Helldivers first then nearest 64 multi-node units within 50 m; wide scan limit 16384')
 end
 local function step()
  local began=stamp();local processed=0
  if work.phase=='animation_map'then
   work.animation_map.tick()
   if work.animation_map.done then work.phase='baseline';work.index=1 end
   work.max_ms=math.max(work.max_ms,(stamp()-(work.tick_started or began))*1000)
   return
  end
  if work.root_burst then
   local burst=work.root_burst;burst.index=burst.index+1
   local ok,source=pcall(root_source,burst.row)
   if ok and source.dt==0 then
    source_log('Freeze root burst: episode='..episode..' row='..burst.row.id..' frame='..burst.index..' at='..string.format('%.6f',now()),source)
   else
    log('Freeze root burst: stopped='..(ok and'nonzero world delta'or tostring(source):sub(1,160)));work.root_burst=nil
   end
   if burst.index>=8 then work.root_burst=nil end
   work.max_ms=math.max(work.max_ms,(stamp()-(work.tick_started or began))*1000)
   return -- One qualified root per update; no world scan or bone loop here.
  end
  if work.phase=='scan'then
   while processed<64 and stamp()-began<.002 do
    local key,unit=next(work.units,work.key);work.key=key
    if key==nil or work.lane_scanned>=(work.lane=='helldiver'and 128 or 16384)then
     work.truncated=work.truncated or key~=nil;work.units=nil;work.phase='baseline';work.index=1
     if work.lane=='helldiver'and animation_source then
      work.animation_map=animation_source.new(sr,work.world,work.rows,log,measure)
      work.phase='animation_map'
     end
     break
    end
    processed=processed+1;work.scanned=work.scanned+1;work.lane_scanned=work.lane_scanned+1
    local ok,row=pcall(function()
     if type(unit)~='userdata'or work.seen[unit]or not valid(unit,work.world)then return end
     local count=U.num_scene_graph_items(unit)
     if not(finite(count)and count>=2 and count<=512)then return end
     local p=U.world_position(unit,1);local x,y,z=V.x(p),V.y(p),V.z(p)
     if not(finite(x)and finite(y)and finite(z))then return end
     local d=(x-work.point[1])^2+(y-work.point[2])^2+(z-work.point[3])^2
     if d>2500 then return end
     return{unit=unit,count=count,distance=d,resource=tostring(U.resource_name(unit)):sub(1,96):gsub('%c','?')}
    end)
    if not ok then work.errors=work.errors+1 elseif row then
     local rows=work.rows;local at=#rows+1
     for i,other in ipairs(rows)do if row.distance<other.distance then at=i;break end end
     if at<=64 then table.insert(rows,at,row);if #rows>64 then table.remove(rows)end end
    end
   end
  else
   if work.phase=='wait'then
    if now()<work.next_at then return end
    work.phase='sample';work.index=1
   end
   while work.index<=#work.rows and processed<2 and stamp()-began<.002 do
    local row=work.rows[work.index];work.index=work.index+1;processed=processed+1
    local ok,value=pcall(frame,row)
    if not ok then work.errors=work.errors+1
    elseif work.phase=='baseline'then
     row.before=value;work.seen[row.unit]=true;work.total_units=work.total_units+1;row.id=work.total_units
     local samples=0;for _ in pairs(value.bones)do samples=samples+1 end
     log(string.format('Freeze unit: episode=%d row=%d lane=%s resource=%s nodes=%d sampled_nodes=%d distance_m=%.3f',episode,row.id,work.lane,row.resource,row.count,samples,math.sqrt(row.distance)))
     log('Freeze modes: episode='..episode..' row='..row.id..' root='..tostring(value.root_mode)..' bone='..tostring(value.bone_mode)..'; read-only baseline')
    elseif row.before then
     local p,r=delta(row.before.root,value.root);local bp,br,wp,wr=0,0,0,0
     for name,bone in pairs(value.bones)do if row.before.bones[name]then
      local x,y=delta(row.before.bones[name],bone);bp=math.max(bp,x);br=math.max(br,y)
     end end
     for i,bone in pairs(value.world_bones)do if row.before.world_bones[i]then
      local x,y=delta(row.before.world_bones[i],bone);wp=math.max(wp,x);wr=math.max(wr,y)
     end end
     if p>.001 or r>.1 or bp>.001 or br>.1 or wp>.001 or wr>.1 then
      log(string.format('Freeze drift: episode=%d sample=%d resource=%s root_m=%.6f root_deg=%.3f bone_local_m=%.6f bone_local_deg=%.3f bone_world_m=%.6f bone_world_deg=%.3f row=%d lane=%s',episode,work.sample,row.resource,p,r,bp,br,wp,wr,row.id,work.lane))
      log('Freeze modes: episode='..episode..' sample='..work.sample..' row='..row.id..' root='..tostring(row.before.root_mode)..'->'..tostring(value.root_mode)..' bone='..tostring(row.before.bone_mode)..'->'..tostring(value.bone_mode)..'; read-only drift')
     end
    end
    if ok and(value.root_source or value.root_source_error)then
     local prefix='Freeze root source: episode='..episode..' row='..tostring(row.id)..' sample='..(work.phase=='baseline'and 0 or work.sample)
     if value.root_source then
      local source=value.root_source
      source_log(prefix,source)
      local d=source.movement
      if not work.root_burst_done and source.dt==0 and d[1]+d[5]+d[9]<2.99 then
       work.root_burst_done=true;work.root_burst={row=row,index=0}
      end
     else log(prefix..' unavailable='..value.root_source_error)end
    end
   end
   if work.index>#work.rows then
    if #work.rows==0 then work.phase='complete'
    elseif work.phase=='baseline'then work.sample=1;work.next_at=now()+.5;work.phase='wait'
    elseif work.sample==1 then work.sample=2;work.next_at=now()+1;work.phase='wait'
    else work.phase='complete'end
   end
  end
  work.max_ms=math.max(work.max_ms,(stamp()-(work.tick_started or began))*1000)
  if work.phase=='complete'and work.lane=='helldiver'then
   local begin=stamp();local units=W.units(work.world);assert(type(units)=='table','World unit list unavailable')
   work.max_ms=math.max(work.max_ms,(stamp()-(work.tick_started or begin))*1000)
   log('Freeze observer: episode='..episode..' Helldiver samples finished; continuing bounded nearby-unit scan')
   work.units=units;work.key=nil;work.rows={};work.lane='nearby';work.lane_scanned=0;work.phase='scan'
  elseif work.phase=='complete'then
   log(string.format('Freeze observer: episode=%d complete units=%d scanned=%d truncated=%s errors=%d max_step_ms=%.3f elapsed=%.3f; idle until next Freeze transition',episode,work.total_units,work.scanned,tostring(work.truncated),work.errors,work.max_ms,now()-work.started))
   work=nil;completed=completed+1;if completed>=4 or episode>=16 then stopped=true end
  end
 end
 function self.tick(frozen,point)
  if stopped then return end
  local edge=frozen and not previous;previous=frozen==true
  if not frozen then cancel('Freeze released');return end
  if not work and not edge then return end
  if edge and(episode>=16 or completed>=4)then stopped=true;return end
  local ok,why=pcall(function()
   local tick_started=stamp();local world=A.main_world()
   if work and world~=work.world then cancel('world changed');return end
   if edge then assert(world and point,'Camera/world unavailable');start(world,point)end
   if work then
    work.tick_started=tick_started
    if now()-work.started>15 then cancel('fifteen-second budget');if episode>=16 then stopped=true end;return end
    step()
   end
  end)
  if not ok then cancel(tostring(why));stopped=true;log('Freeze observer disabled: '..tostring(why))end
 end
 function self.release()work=nil;stopped=true end
 return self
end
return M

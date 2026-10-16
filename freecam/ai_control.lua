-- Director behavior suppression. Enemy brains, physics and damage still run.
local M={modes={'normal','passive','dummy'},maximum=1024,interval=.05,batch=16}
local bit=require('bit')
local APPLY_FIELDS={'still','target','alert','detector','hostiles'}
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
function M.new(backend,log)
 local self={mode='normal',status='Enemy behavior: Normal',available=false,pending=false,affected=0,solo_reset=0};local requested;local context;local held={};local detectors={};local cursor=0;local next_refresh=0;local round=0;local detector_round=0
 local held_dirty,detector_dirty=true,true
 local tracked,affected,errors=0,0,0
 local function tally(h,sign)
  if h then tracked=tracked+sign;if h.applied then affected=affected+sign end;if h.error then errors=errors+sign end end
 end
 local function replace(e,h)tally(held[e],-1);held[e]=h;tally(h,1);held_dirty=true end
 local held_ids,detector_ids={},{};local displayed={}
 local function ordered(records,ids,dirty)
  if not dirty then return ids end
  ids={};for id in pairs(records)do ids[#ids+1]=id end;table.sort(ids);return ids
 end
 local function reset_records()
  tracked,affected,errors=0,0,0;held={};detectors={};held_ids={};detector_ids={};held_dirty=false;detector_dirty=false;round=0;detector_round=0
 end
 local function fail(why)self.status=tostring(why);return false,self.status end
 local function get_context(cleanup)
  local ok,value,why,policy=pcall(cleanup and(backend.restore_context or backend.context)or backend.context)
  if not ok then return nil,tostring(value),'transient_context'end
  if value~=nil and type(value)~='table'then return nil,'Solo session context unavailable','unknown_session'end
  if value and not cleanup and(value.solo~=true or value.player_count~=1)then return nil,'Enemy behavior requires a verified solo player count','unknown_session'end
  return value,why,policy
 end
 function self.ready()
  local value,why=get_context();self.available=value~=nil
  return self.available,why,{normal=true,passive=self.available,dummy=self.available}
 end
 function self.faction()
  if type(backend.faction)~='function'then return end
  local ok,value=pcall(backend.faction);if ok then return value end
 end
 local function observe(e)local ok,r,why=pcall(backend.observe,context,e);if not ok then return nil,tostring(r)end;return r,why end
 local function post_write(done,verified,record,key,value)
  if done~=true or type(verified)~='table'or verified.entity~=record.entity or verified.identity~=record.identity or type(verified.fields)~='table'then return end
  local before=record.fields[key];local after=verified.fields[key]
  if before and type(after)=='table'and after.token==before.token and after.address==before.address and
      after.owner==before.owner and after.owner_identity==before.owner_identity and after.value==value then return verified end
 end
 local function detector_record(lease)
  local ok,r,why=pcall(backend.observe_detector or backend.observe,context,lease.entity)
  if not ok then return nil,tostring(r)end
  if not r then return nil,why end
  local field=r.fields.detector
  if r.identity~=lease.identity or(field and field.token~=lease.token)then return nil,'retired'end
  if not field then return nil,'Enemy detector unavailable'end
  return r
 end
 local function restore_detector(lease)
  if not lease.owned then return true end
  local r,why=detector_record(lease);if not r then return why=='retired',why end
  local field=r.fields.detector
  if field.value~=lease.applied or field.value==lease.baseline then return true end
  local ok,done,err=pcall(backend.restore or backend.write,context,r,'detector',lease.baseline,field.value)
  if not ok or done==false then return false,tostring(ok and err or done)end
  return true
 end
 local function reassert_movement(e,h)
  local lease=h.leases.still
  if self.mode~='dummy'or not(lease and lease.owned and backend.observe_restore)then return end
  local called,r=pcall(backend.observe_restore,context,e)
  if not called or not r or r.identity~=h.identity then return end
  local field=r.fields and r.fields.still
  if not field or field.token~=lease.token then return end
  local value=bit.bor(field.value,0x80)%4294967296
  if value~=field.value then
   -- Only renew our existing movement lease. Detector/target failures do not
   -- justify touching a different component or acquiring a new ownership record.
   pcall(backend.write,context,r,'still',value,field.value)
  end
 end
 local function restore(e,h)
  local function own_record()
   local ok,r,why=pcall(backend.observe_restore or backend.observe,context,e)
   if not ok then return nil,tostring(r)end;return r,why
  end
  local r,why=own_record();if not r then if why=='retired'then return true end;return false,why end
  if r.identity~=h.identity then return true end
  for key,lease in pairs(h.leases)do
   local field=r.fields[key]
   if lease.owned and field and field.token==lease.token then
    local current=key=='still'and bit.band(field.value,0x80)or field.value
    if current==lease.applied then
     local value=key=='still'and bit.bor(bit.band(field.value,bit.bnot(0x80)),lease.baseline)%4294967296 or lease.baseline
     if value~=field.value then
      local ok,done,err,committed,verified=pcall(backend.restore or backend.write,context,r,key,value,field.value)
      if not ok or done==false then return false,tostring(ok and err or done)end
      local fresh=post_write(done,verified,r,key,value);local why
      if not fresh then fresh,why=own_record()end;if not fresh then return why=='retired',why end
      if fresh.identity~=h.identity then return true end;r=fresh
     end
    end
   end
   h.leases[key]=nil
  end
  return true
 end
 local function release_all(reason)
  if next(held)==nil and next(detectors)==nil then context=nil;self.affected=0;self.status=reason or'Enemy behavior: Normal';return true end
  local current,why=get_context(true)
  if not current then return fail('Enemy cleanup waiting for authority: '..tostring(why))end
  if context and current.identity~=context.identity then reset_records();context=nil;self.affected=0;self.status='Enemy scene retired';return true end
  context=current
  local pending_error
  for e,h in pairs(held)do local ok,err=restore(e,h);if ok then replace(e,nil) else pending_error=err end end
  for key,lease in pairs(detectors)do local ok,err=restore_detector(lease);if ok then detectors[key]=nil;detector_dirty=true else pending_error=err end end
  if next(held)or next(detectors)then return fail('Enemy cleanup pending: '..tostring(pending_error))end
  reset_records();context=nil;self.affected=0;self.status=reason or'Enemy behavior: Normal';return true
 end
 function self.release(reason)
  requested=nil;self.pending=false;self.mode='normal';return release_all(reason)
 end
 function self.queue(mode)
  if mode~='normal'and mode~='passive'and mode~='dummy'then return fail('Choose Normal, Passive, or Dummy')end
  requested=mode;self.pending=true;return true
 end
 local function apply(e,h,r)
  local problems;local function problem(why)if not problems then problems={}end;problems[#problems+1]=tostring(why)end
  if self.mode=='passive'and h.leases.still then
   local old=h.leases.still;local field=r.fields.still;local restored=true
   if old.owned and not field then restored=false;problem('Movement restoration waiting for its component')end
   if old.owned and field and old.token==field.token and bit.band(field.value,0x80)==old.applied then
    local value=bit.bor(bit.band(field.value,bit.bnot(0x80)),old.baseline)%4294967296
    if value~=field.value then
     local ok,done,why,committed,verified=pcall(backend.write,context,r,'still',value,field.value)
     if not ok or done==false then restored=false;problem(ok and why or done)end
     local fresh=ok and post_write(done,verified,r,'still',value);local why
     if not fresh then fresh,why=observe(e)end;if not fresh or fresh.identity~=h.identity then return false,why or'Enemy changed after movement restore'end;r=fresh
    end
   end
   if restored then h.leases.still=nil end
  end
  -- Apply independent local fields first. A detector fault must not leave a
  -- verified live enemy moving toward its old target.
  for _,key in ipairs(APPLY_FIELDS)do local value=0;if key=='target'then value=r.invalid elseif key=='still'then value=self.mode=='dummy'and 0x80 or nil end;local field=value~=nil and r.fields[key]
   if field then
    local persistent=key=='still'
    local current=key=='still'and bit.band(field.value,0x80)or field.value
    local lease=h.leases[key]
    if key=='detector'then
     local owner,identity=field.owner or e,field.owner_identity or r.identity
     local token=identity..':'..tostring(field.token)
     lease=detectors[token]
     if not lease then lease={entity=owner,identity=identity,token=field.token,baseline=current,applied=value,owned=false};detectors[token]=lease;detector_dirty=true end
    end
    if persistent and(not lease or lease.token~=field.token)then lease={token=field.token,baseline=current,applied=value,owned=false};h.leases[key]=lease end
    local full=key=='still'and bit.bor(field.value,0x80)%4294967296 or value
    if full~=field.value then
     local ok,done,why,committed,verified=pcall(backend.write,context,r,key,full,field.value)
     if lease and(ok and(done==true or committed==true))then lease.owned=true end
     if not ok or done==false then problem(ok and why or done)end
     local fresh=ok and post_write(done,verified,r,key,full);local why
     if not fresh then fresh,why=observe(e)end;if not fresh or fresh.identity~=h.identity then return false,why or'Enemy changed after behavior edit'end;r=fresh
    end
   end
  end
  if r.partial_issue then problem(r.partial_issue)end
  return problems==nil,problems and table.concat(problems,'; ')or nil
 end
 -- The Director selection belongs to the session, not the menu lifetime.
 -- Keep discovery running while Photo Mode is closed; explicit Normal/release
 -- restores owned fields, and a retired scene never reuses old leases.
 function self.flush(active)
  -- Discovery can be throttled; holding already discovered enemies cannot.
  -- The game can share targets and clear movement flags between updates.
  local now=backend.now();local discover=now>=next_refresh or self.pending
  if discover then next_refresh=now+M.interval end
  if requested then self.mode=requested;requested=nil;self.pending=false end
  if self.mode=='normal'then return release_all()end
  local current,why,policy=get_context()
  if not current then
   self.available=false
   if policy=='not_solo'or policy=='unknown_session'then
    requested=nil;self.mode='normal';self.pending=false;self.solo_reset=self.solo_reset+1
    return release_all('Enemy behavior reset to Normal: '..tostring(why))
   end
   return fail('Enemy behavior unavailable: '..tostring(why))
  end
  self.available=true
  if context and current.identity~=context.identity then reset_records();cursor=0;discover=true;self.discovery_error=nil end
  context=current
  local limited=false
  if discover then
   local ran,entities,new_cursor,scan_issue=pcall(backend.scan,context,cursor,256)
   if not ran or type(entities)~='table'or type(new_cursor)~='number'or scan_issue~=nil then
    self.discovery_error=tostring(scan_issue or entities)
   else
    self.discovery_error=nil;cursor=new_cursor
    for _,e in ipairs(entities)do if not held[e]then
     if tracked<M.maximum then replace(e,{leases={}}) else limited=true end
    end end
   end
   -- Enumeration failure delays new arrivals only. Every known enemy still
   -- revalidates its scene, authority and component identity before a write.
  end
  held_ids=ordered(held,held_ids,held_dirty);held_dirty=false;local ids=held_ids
  if#ids>0 then
   for i=1,math.min(M.batch,#ids)do
    local index=((round+i-1)%#ids)+1;local e=ids[index];local h=held[e];tally(h,-1);local r,err=observe(e)
    if not r then
     -- Unusable, untouched records must not crowd out new live enemies. The
     -- rolling discovery scan can retry them without retaining a cleanup lease.
     if err=='retired'or next(h.leases)==nil then held[e]=nil;held_dirty=true else h.error=err;h.applied=false;reassert_movement(e,h)end
    else
     if h.identity~=r.identity then h={identity=r.identity,leases={}};held[e]=h end
     local ok,why=apply(e,h,r);h.error=not ok and why or nil;h.applied=ok
    end
    tally(held[e],1)
   end
   round=(round+M.batch)%#ids
  end
  -- Detector leases outlive borrowers, but not their actual owner's lifetime.
  -- Sweep a bounded slice so deaths/replacements cannot accumulate forever.
  if discover then
   detector_ids=ordered(detectors,detector_ids,detector_dirty);detector_dirty=false
   if#detector_ids>0 then
    for i=1,math.min(M.batch,#detector_ids)do
     local key=detector_ids[((detector_round+i-1)%#detector_ids)+1]
     local r,why=detector_record(detectors[key]);if not r and why=='retired'then detectors[key]=nil;detector_dirty=true end
    end
    detector_round=(detector_round+M.batch)%#detector_ids
   end
  end
  self.affected=affected
  if displayed.mode~=self.mode or displayed.affected~=self.affected or displayed.errors~=errors or displayed.limited~=limited or displayed.discovery~=self.discovery_error or displayed.text~=self.status then
   self.status=string.format('Enemy behavior: %s (%d affected%s%s%s)',self.mode=='dummy'and'Dummy'or'Passive',self.affected,errors>0 and(', '..errors..' unavailable')or'',limited and', tracking capacity reached'or'',self.discovery_error and', discovery retry pending'or'')
   displayed.mode,displayed.affected,displayed.errors,displayed.limited,displayed.discovery,displayed.text=self.mode,self.affected,errors,limited,self.discovery_error,self.status
  end
  return true
 end
 function self.count()return count(held)+count(detectors)end
 self.close=self.release;self.clear=self.release
 return self
end
return M

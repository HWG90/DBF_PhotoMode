-- Explicit one-shot development diagnostic. No virtual input. Only the fixed
-- native-override-v1 mode enables the separately owned/restorable lens test.
-- The fixed marker is consumed at startup; no file polling or executable commands.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-native-dof-selftest.request'
 local f=io.open(path,'rb');if not f then return false end
 local token=f:read(64);f:close()
 if token=='selection-depth-v1\n' then
  if os.rename(path,path..'.claimed.'..tostring(pid))~=true then return false end
  return 'selection-depth-v1'
 end
 if token~='native-dof-v1\n'and token~='private-depth-v1\n'and token~='native-dof-entity-v1\n'and token~='native-dof-owner-v1\n'and token~='native-dof-override-v1\n'and token~='local-depth-control-v1\n'and token~='local-texture-control-v1\n'and token~='local-world-control-v1\n'then return false end
 if os.rename(path,path..'.claimed.'..tostring(pid))~=true then return false end
 return token=='local-world-control-v1\n'and'local-world-control-v1'or token=='local-texture-control-v1\n'and'local-texture-control-v1'or token=='local-depth-control-v1\n'and'local-depth-control-v1'or token=='private-depth-v1\n'and'private-depth-v1'or token=='native-dof-entity-v1\n'and'entity-getter-v1'or token=='native-dof-owner-v1\n'and'entity-owner-v1'or token=='native-dof-override-v1\n'and'native-override-v1'or true
end
function M.new(sr,log,mode,readiness_factory)
 assert(mode==nil or mode==true or mode=='selection-depth-v1'or mode=='private-depth-v1'or mode=='entity-getter-v1'or mode=='entity-owner-v1'or mode=='native-override-v1'or mode=='local-depth-control-v1'or mode=='local-texture-control-v1'or mode=='local-world-control-v1','Unknown self-test')
 local selection=mode=='selection-depth-v1'
 local points={{.5,.5},{.5,.65},{.5,.35},{.35,.5},{.65,.5},{.5,.5}}
 local point_index,point_deadline=1,nil
 local world_control=mode=='local-world-control-v1'
 local texture_control=mode=='local-texture-control-v1'
 local local_control=mode=='local-depth-control-v1'or texture_control or world_control
 local private=mode=='private-depth-v1'or local_control
 local sink=log
 log=function(message)sink(private and message:gsub('Native DoF self%-test','Depth shader self-test')or message)end
 local started=sr.Application.time_since_launch()
 local next_at,attempts,phase,deadline=started+60,0,'waiting',nil
 local readiness,readiness_world
 local self={}
 if local_control then self.local_binding_probe={source=world_control and 'linear_depth' or texture_control and 'atlas-string' or 'output_target',gui_world='ui'}end
 function self.store(factory)
  return{new=function(folder)
   local store=factory.new(folder)
   return{load=function(id)
    local values=store.load(id)
    if id=='dbf_freecam'then
     values.dof=true;values.dof_mode=1;values.focus_mode=1
     values.scene_shader=1;values.freeze_player=false
     if selection then values.dof=false;values.freeze_player=true end
     if private then
      values.dof=false;values.dof_mode=2;values.scene_shader=7;values.scene_strength=100
      values.scene_depth_range=local_control and not world_control and 1 or 10;values.focus_distance=.7;values.aperture=1.2
      values.exposure=0;values.contrast=100;values.saturation=100;values.depth_calibration=false
     end
     values.hide_player=false;values.hide_armour=false;values.hide_weapons=false;values.hide_cape=false
     if mode=='native-override-v1'then values.focus_distance=.7;values.aperture=1.2 end
    end
    return values
   end,save=function(id,values)
    if id=='dbf_freecam'then return true end
    return store.save(id,values)
   end}
  end}
 end
 function self.abort(runtime,reason)
  if phase=='closing'or phase=='stopped'then return end
  log('Native DoF self-test: closing; '..tostring(reason))
  phase='closing';deadline=sr.Application.time_since_launch()+30;next_at=0
  if readiness then readiness.release();readiness=nil end
  runtime.close(true)
 end
 function self.tick(runtime)
  if phase=='stopped'then return false end
  local now=sr.Application.time_since_launch()
  if phase=='closing'then
   if now>=deadline then phase='stopped';log('Native DoF self-test: cleanup unconfirmed; normal ownership recovery retained');return false end
   -- Entry disposal can still refuse after close. Retry no faster than once
   -- a second within the existing cleanup deadline, never once per frame.
   if runtime.state=='closed'and now>=next_at then
    if next_at==0 then log('Native DoF self-test: closed; restoring normal runtime from saved settings')end
    next_at=now+1;return true
   end
   return false
  end
  if phase=='waiting'then
   -- A network-session userdata also exists during the intro movie. For the
   -- association test, require actual readable lens profiles before taking
   -- input/camera ownership. Advance the existing bounded reader across frames.
   if not runtime.active and readiness then
    if now-started>=180 then self.abort(runtime,'lens readiness deadline reached');return false end
    local world=sr.Application.main_world()
    if world~=readiness_world then readiness.release();readiness=nil;next_at=now+10;return false end
    readiness.tick({},1,{world=world,generation=0})
    if not readiness.done then return false end
    local found=readiness.profile_count>0
    readiness.release();readiness=nil
    if not found then next_at=now+10;return false end
    if sr.Window and type(sr.Window.has_focus)=='function'and not sr.Window.has_focus()then next_at=now+10;return false end
    local ok,why=runtime.open()
    log('Native DoF self-test: lens-qualified open accepted='..tostring(ok)..' '..tostring(why))
    if ok then phase='on';deadline=now+(world_control and 10 or 40) else next_at=now+10 end
    return false
   end
   if runtime.active then
    if private then
     for key,value in pairs({dof=false,dof_mode=2,scene_shader=7,scene_strength=100,scene_depth_range=local_control and not world_control and 1 or 10})do assert(runtime.handle.set(key,value))end
    else
     if runtime.handle.get('dof_mode')~=1 then assert(runtime.handle.set('dof_mode',1))end
     if not selection and not runtime.handle.get('dof')then assert(runtime.handle.set('dof',true))end
    end
    phase='on';deadline=now+(world_control and 10 or 40)
    log('Native DoF self-test: Photo Mode already open; continuing test from this session')
    return false
   end
   if now<next_at then return false end
   if now-started>=180 or attempts>=12 then self.abort(runtime,'no qualifying session within startup limit');return false end
   attempts=attempts+1;next_at=now+10
   if not sr.Application.main_world()or type(sr.Network.game_session())~='userdata'then return false end
   if sr.Window and type(sr.Window.has_focus)=='function'and not sr.Window.has_focus()then return false end
   if readiness_factory then
    readiness_world=sr.Application.main_world();readiness=readiness_factory()
    return false
   end
   local ok,why=runtime.open()
   log('Native DoF self-test: open attempt '..attempts..' accepted='..tostring(ok)..' '..tostring(why))
   if ok then phase='on';deadline=now+(world_control and 10 or 40) end
   return false
  end
  if not runtime.active then self.abort(runtime,'Photo Mode closed before test completion');return false end
  if now<deadline then return false end
  if selection then
   if phase=='selection_complete'then self.abort(runtime,'selection sequence complete; visual accuracy and timings require review');return false end
   if not point_deadline then point_deadline=now+5 end
   local point=points[point_index]
   local result,why,info=runtime.selection_probe(point[1],point[2])
   if not result and info and info.pending and now<point_deadline then
    deadline=math.min(point_deadline,math.max(now+.1,info.retry_at or now+.5));return false
   end
   if result then
    log(string.format('Selection depth test: point=%d x=%.3f y=%.3f depth=%.3f selected=%s readback_ms=%.3f sample_ms=%.3f pick_ms=%.3f label=%s',
     point_index,point[1],point[2],result.depth,tostring(result.selected),result.readback_ms,result.sample_ms,result.pick_ms,result.label))
    local audit=result.audit
    if audit then
     local function xyz(p)return p and string.format('%.4f,%.4f,%.4f',p[1],p[2],p[3])or'unavailable'end
     log(string.format('Selection geometry: point=%d candidates=%d kind=%s resource=%s surface=%s center=%s score=%.3f',
      point_index,audit.candidates or 0,audit.geometry or'none',audit.resource or'unknown',xyz(audit.surface),xyz(audit.center),audit.score or -1))
     for i,hit in ipairs(audit.hits or{})do
      log(string.format('Selection candidate: point=%d candidate=%d kind=%s resource=%s depth=%.3f score=%.3f',
       point_index,i,hit.geometry or'none',hit.resource,hit.depth,hit.score))
     end
     for i,rig in ipairs(audit.rigs or{})do
      log(string.format('Selection body: point=%d rig=%d reason=%s radius_ratio=%.3f',point_index,i,rig.reason,rig.ratio))
     end
    end
   else log('Selection depth test: point='..point_index..' unavailable='..tostring(why))end
   -- Retain each result, including the last, while the external window
   -- capture completes. No further scene reads happen during this interval.
   point_index=point_index+1;point_deadline=nil;deadline=now+8
   if point_index>#points then phase='selection_complete'end
   return false
  end
  if local_control then
   if phase=='on'then
    self.local_binding_probe.source=world_control and 'linear_depth' or texture_control and 'atlas-id' or 'linear_depth'
    if world_control then self.local_binding_probe.gui_world='main';log('Local world probe: switching to main')end
    assert(runtime.handle.set('scene_depth_range',texture_control and 1 or 10));phase='depth';deadline=now+(world_control and 10 or 30)
    log('Local resource probe: switching to '..self.local_binding_probe.source)
   elseif phase=='depth'then
    self.local_binding_probe.source=world_control and 'linear_depth' or texture_control and 'depth-id' or 'output_target'
    if world_control then self.local_binding_probe.gui_world='ui';log('Local world probe: switching to ui')end
    assert(runtime.handle.set('scene_depth_range',(texture_control or world_control) and 10 or 1));phase='color_again';deadline=now+(world_control and 10 or 30)
    log('Local resource probe: switching to '..self.local_binding_probe.source)
   else self.abort(runtime,'local resource sequence complete; visual verification required')end
   return false
  end
  if mode=='native-override-v1'then
   if phase=='on'then
    assert(runtime.handle.set('focus_distance',20));phase='far';deadline=now+30
    log('Native DoF self-test: native focus 20 m, f/1.2; capture window 30 seconds')
   elseif phase=='far'then
    assert(runtime.handle.set('aperture',22));phase='aperture';deadline=now+30
    log('Native DoF self-test: native focus 20 m, f/22; capture window 30 seconds')
   else self.abort(runtime,'native focus/aperture sequence complete; visual verification required')end
   return false
  end
  if private then
   if phase=='on'then
    for key,value in pairs({scene_shader=1,dof=true,focus_distance=.7,aperture=1.2})do assert(runtime.handle.set(key,value))end
    phase='near';deadline=now+30;log('Native DoF self-test: shader focus 0.7 m, f/1.2; capture window 30 seconds')
   elseif phase=='near'then
    assert(runtime.handle.set('focus_distance',20));phase='far';deadline=now+30
    log('Native DoF self-test: shader focus 20 m, f/1.2; capture window 30 seconds')
   elseif phase=='far'then
    assert(runtime.handle.set('aperture',22));phase='aperture';deadline=now+30
    log('Native DoF self-test: shader focus 20 m, f/22; capture window 30 seconds')
   else self.abort(runtime,'depth/focus/aperture sequence complete; visual verification required')end
   return false
  end
  if phase=='on'then
   assert(runtime.handle.set('dof',false));phase='off';deadline=now+30
   log('Native DoF self-test: native DoF OFF; capture window 30 seconds')
  elseif phase=='off'then
   assert(runtime.handle.set('dof',true));phase='on_again';deadline=now+30
   log('Native DoF self-test: native DoF ON; capture window 30 seconds')
  else self.abort(runtime,'ON/OFF/ON sequence complete; no numeric controller claimed')end
  return false
 end
 log('Native DoF self-test: armed once; 60-second startup delay, 180-second session limit; settings remain on disk unchanged')
 return self
end
return M

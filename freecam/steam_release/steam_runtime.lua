-- Modular Lua 5.1 controller. Native-dependent features remain capability
-- gated while their backends are ported; never execute old-build addresses.
local M={}
-- True-zero pause and slow motion use the documented engine policy setter.
-- Resume is an explicit 1x policy, not an invented native-state snapshot.
-- A foreign Lua multiplier write revokes ownership; it is never overwritten.
function M.time_policy(sr,clock)
 local A,G,N=sr.Application,sr.GameSession,sr.Network
 local self={frozen=false,slowmo_active=false,rate=.2,owned=false,revision=0,reason=nil}
 local original,wrapper,world,session,last_check
 local acquire
 local retry_at,retry_binding,retry_reason,retry_value
 local function solo()
  local current=N.game_session();if not current then return nil,'Solo session unavailable'end
  local peers=G.peers(current)
  if type(peers)~='table'then return nil,'Solo peer inventory unavailable'end
  local count=0;for _ in pairs(peers)do count=count+1;if count>1 then return nil,'Freeze Action is solo only'end end
  if type(G.synchronizing_peers)=='function'then
   local joining=G.synchronizing_peers(current)
   if type(joining)~='table'or next(joining)~=nil then return nil,'Freeze ended: a player is joining'end
  end
  return current
 end
 local function detach()
  if wrapper and A.set_time_step_policy==wrapper then A.set_time_step_policy=original end
  wrapper=nil;original=nil;world=nil;session=nil
  retry_at,retry_binding,retry_reason,retry_value=nil,nil,nil,nil
 end
 local function restore(value)
  local now=clock();local binding=A.set_time_step_policy
  if retry_at and now<retry_at and binding==retry_binding and value==retry_value then return false,retry_reason end
  local function pending(why)
   retry_at,retry_binding,retry_reason,retry_value=now+1,binding,why,value;return false,why
  end
  if binding~=wrapper then return pending('Time-policy binding changed; restoration is pending')end
  local called,result=pcall(original,'external_multiplier',value)
  if not called or result==false then return pending('Time restoration failed: '..tostring(result))end
  retry_at,retry_binding,retry_reason,retry_value=nil,nil,nil,nil;return true
 end
 function self.release()
  if self.owned then local ok,why=restore(1);if not ok then self.pending_restore=true;return false,why end end
  local changed=self.owned or self.frozen or self.slowmo_active
  self.owned,self.frozen,self.slowmo_active,self.pending_restore=false,false,false,false
  if changed then self.revision=self.revision+1 end
  detach();return true
 end
 function self.resume()
  if self.pending_restore then return self.release()end
  if not self.frozen then return true end
  if self.slowmo_active then
   local ok,why=acquire();if not ok then return false,why end
  end
  local ok,why=restore(self.slowmo_active and self.rate or 1);if not ok then return false,why end
  self.frozen=false;self.revision=self.revision+1
  if not self.slowmo_active then self.owned=false;detach()end
  return true
 end
 acquire=function()
  if self.pending_restore then return false,'Time restoration is pending'end
  if self.owned and A.set_time_step_policy~=wrapper then return false,'Time-policy binding changed'end
  local called,current,why=pcall(solo)
  if not called or not current then
   local reason=called and why or tostring(current)
   if self.owned then local ok,restore_why=self.release();if not ok then return false,restore_why end end
   return false,reason
  end
  local current_world=A.main_world();if not current_world then return false,'Main world unavailable'end
  if self.owned then
   if current~=session or current_world~=world then
    local ok,why=self.release();return false,ok and'Time modifier ended: session or world changed'or why
   end
   return true
  end
  original=A.set_time_step_policy
  if type(original)~='function'then return false,'Time-policy API unavailable'end
  local saved=original;local owned
  owned=function(...)
   local args={...};local result={saved(...)}
   if wrapper==owned and result[1]~=false then
    for _,arg in ipairs(args)do if arg=='external_multiplier'then
     self.owned,self.frozen,self.slowmo_active,self.pending_restore=false,false,false,false
     self.reason='Another time modifier took control';self.revision=self.revision+1
     -- Keep other mods' wrappers intact; retained callbacks remain inert.
     detach();break
    end end
   end
   return unpack(result)
  end
  wrapper=owned;A.set_time_step_policy=owned
  world,session=current_world,current
  -- Mark ownership before a write so a throwing setter still requires cleanup.
  self.owned=true;self.reason=nil;last_check=clock();return true
 end
 local function write(value,label)
  local ok,result=pcall(original,'external_multiplier',value)
  if not ok or result==false then
   local restored,reason=self.release()
   return false,restored and(label..' failed: '..tostring(result))or reason
  end
  return true
 end
 function self.freeze()
  if self.frozen then return true end
  local ok,why=acquire();if not ok then return false,why end
  self.frozen=true
  ok,why=write(0,'Freeze Action');if not ok then return false,why end
  self.revision=self.revision+1;return true
 end
 function self.set_slowmo(enabled,rate)
  if type(enabled)~='boolean'or type(rate)~='number'or rate~=rate or rate<.05 or rate>1 then
   return false,'Invalid slow-motion setting'
  end
  if self.pending_restore then return false,'Time restoration is pending'end
  if self.slowmo_active==enabled and self.rate==rate then return true end
  if not self.frozen and(enabled or self.owned)then
   local ok,why=acquire();if not ok then return false,why end
   ok,why=write(enabled and rate or 1,'Slow motion');if not ok then return false,why end
  end
  self.slowmo_active,self.rate=enabled,rate;self.revision=self.revision+1
  if not self.frozen and not enabled then self.owned=false;detach()end
  return true
 end
 function self.tick()
  if self.pending_restore then return self.release()end
  if not self.owned then return true end
  local now=clock()
  if now>=last_check and now-last_check<1 then return true end
  last_check=now
  -- No join notification exists in this API. At most one small peer read per
  -- wall second while modifying time; unmodified state performs zero reads.
  local ok,current=pcall(solo)
  if not ok or current~=session or A.main_world()~=world or
   (sr.Window and sr.Window.has_focus and sr.Window.has_focus()~=true)then
   local restored,why=self.release();self.reason='Time modifier ended: session or world changed'
   return restored,why
  end
  return true
 end
 return self
end
-- Native global Bloom is qualified independently of numeric lens/scene effects.
-- Reads occur on explicit entry/change/cleanup or a bounded asynchronous ack;
-- a settled or blocked policy never reads the native setting or clock. The Lua
-- observer cannot detect native ABA; fresh pre-change/restore value comparison
-- is the boundary for native writers.
function M.bloom_policy(sr)
 local A=sr and sr.Application
 if type(A)~='table'or type(A.render_setting)~='function'or type(A.set_render_setting)~='function'or
  type(A.time_since_launch)~='function'then return nil end
 local self={state='closed',revision=0,reason=nil,failures={}}
 local getter,prior,wrapper,baseline,observed,owned,desired,inflight
 local active,closing,written,restore_attempted,foreign,foreign_unknown=false,false,false,false,false,false
 local next_poll,deadline,last_clock
 local function pack(...)return{n=select('#',...),...}end
 local function finite(n)return type(n)=='number'and n==n and n>=0 and n<math.huge end
 local function state(value,reason)
  if self.state~=value or self.reason~=reason then self.state,self.reason=value,reason;self.revision=self.revision+1 end
 end
 local function failure(name,result,message)
  self.failures[name]=result;state('blocked',message);return false,message
 end
 local function now(value)
  if value==nil then
   local result=pack(pcall(A.time_since_launch))
   if not result[1]then failure('clock',result,'Bloom clock failed; cleanup is pending');return nil end
   value=result[2]
  end
  if not finite(value)or last_clock and value<last_clock then
   failure('clock',{n=1,value},'Bloom clock changed; cleanup is pending');return nil
  end
  last_clock=value;return value
 end
 local function read()
  local result=pack(pcall(getter,'bloom_enabled'))
  if not result[1]or result.n~=2 or type(result[2])~='boolean'then
   failure('getter',result,'Bloom getter failed or changed type; cleanup is pending');return nil
  end
  return result[2]
 end
 local function detach(final_state,message)
  if wrapper and A.set_render_setting==wrapper then
   local result=pack(pcall(function()A.set_render_setting=prior end))
   if not result[1]or A.set_render_setting==wrapper then
    return failure('observer_restore',result,'Bloom observer restoration is pending')
   end
  end
  wrapper=nil;prior=nil;inflight=nil;active=false;written=false;closing=false
  state(final_state,message);return true
 end
 local function check_foreign()
  if wrapper and(foreign or A.set_render_setting~=wrapper)then
   return detach(closing and'closed'or'foreign','Bloom handed to another Lua writer; its value is preserved')
  end
 end
 local function submit(value,kind,time)
  local stamp=now(time);if not stamp then return false,self.reason end
  -- Mark attempted ownership before calling: false/throw may partially apply.
  written=true;inflight={value=value,kind=kind};next_poll,deadline=stamp+.1,stamp+2
  -- An apply back to the baseline is already the single baseline submission.
  -- A failed attempt must not authorize a duplicate cleanup setter.
  restore_attempted=kind=='restore'or value==baseline
  local result=pack(pcall(prior,'bloom_enabled',value and'true'or'false'))
  if not result[1]or result[2]==false then
   return failure(kind,result,'Bloom '..kind..' failed; partial application is unknown')
  end
  state('awaiting',kind=='restore'and'Restoring original Bloom'or'Applying selected Bloom');return true
 end
 local cleanup
 cleanup=function(value,time)
  if not written then return detach('closed','Bloom released without changing the native setting')end
  if foreign_unknown then return false,'Failed foreign Bloom submission; native ownership remains unknown'end
  if value==baseline then
   -- An unacknowledged opposite submission can still be queued behind this
   -- old baseline. A submitted baseline itself cannot later undo cleanup.
   if inflight and inflight.value~=baseline and observed~=inflight.value then
    return failure('unacknowledged',{n=1,value},'Bloom submission remains unacknowledged; cleanup is unknown')
   end
   return detach('closed','Original Bloom value restored')
  end
  if value~=owned and(not inflight or value~=inflight.value)then
   return detach('foreign','Bloom changed outside Photo Mode; its value is preserved')
  end
  if restore_attempted then return failure('unacknowledged_restore',{n=1,value},'Bloom restore remains unacknowledged; no repeated setter')end
  local ok,why=submit(baseline,'restore',time)
  return false,ok and'Awaiting original Bloom acknowledgement'or why
 end
 function self.open(value)
  if self.state~='closed'then return false,'Previous Bloom ownership is not retired'end
  if type(value)~='boolean'then return false,'Bloom selection must be boolean'end
  getter=A.render_setting
  baseline=read();if baseline==nil then return false,self.reason end
  observed,owned,desired=baseline,baseline,value
  active,closing,written,restore_attempted,foreign,foreign_unknown=true,false,false,false,false,false
  inflight,next_poll,deadline,last_clock=nil,nil,nil,nil;self.failures={}
  prior=A.set_render_setting
  if type(prior)~='function'then active=false;state('blocked','Bloom setter unavailable');return false,self.reason end
  local saved=prior
  local owned_wrapper
  owned_wrapper=function(...)
   if wrapper~=owned_wrapper or not active and not written or(...)~='bloom_enabled'then return saved(...)end
   local result=pack(pcall(saved,...))
   if not result[1]or result[2]==false then
    if written then foreign_unknown=true;failure('foreign',result,'Failed foreign Bloom write; ownership remains unknown')
    else foreign=true end
   else foreign=true end
   if not result[1]then error(result[2],0)end
   return unpack(result,2,result.n)
  end
  wrapper=owned_wrapper
  local installed=pack(pcall(function()A.set_render_setting=wrapper end))
  if not installed[1]or A.set_render_setting~=wrapper then
   active=false;return failure('observer_install',installed,'Bloom observer unavailable')
  end
  state('active','Bloom matches the selected value')
  if value~=baseline then return submit(value,'apply')end
  return true
 end
 function self.request(value)
  if type(value)~='boolean'then return false,'Bloom selection must be boolean'end
  if check_foreign()~=nil then return false,self.reason end
  if not active or closing or self.state=='blocked'then return false,self.reason or'Bloom is not active'end
  if desired==value then return true end
  desired=value;self.revision=self.revision+1
  if inflight then return true end -- Coalesce without another native submission.
  local current=read();if current==nil then return false,self.reason end
  if current~=observed then
   detach('foreign','Bloom changed outside Photo Mode; its value is preserved');return false,self.reason
  end
  if current==value then return true end
  return submit(value,'apply')
 end
 function self.tick(time)
  if check_foreign()~=nil then return self.state~='blocked',self.reason end
  if self.state~='awaiting'then return self.state~='blocked',self.reason end
  local stamp=now(time);if not stamp then return false,self.reason end
  if stamp>deadline then return failure('timeout',{n=1,inflight.value},'Bloom acknowledgement timed out; cleanup is unknown')end
  if stamp<next_poll then return true end
  next_poll=stamp+.1
  local current=read();if current==nil then return false,self.reason end
  if current==inflight.value then
   observed,owned=current,current;inflight=nil;next_poll,deadline=nil,nil
   if closing then return cleanup(current,stamp)end
   state('active','Selected Bloom value acknowledged')
   if desired~=current then return submit(desired,'apply',stamp)end
  elseif stamp>=deadline then return failure('timeout',{n=1,current},'Bloom acknowledgement timed out; cleanup is unknown')end
  return true
 end
 function self.close(explicit)
  closing=true;active=false
  if check_foreign()~=nil then return self.state~='blocked',self.reason end
  if self.state=='closed'then return true end
  if self.state=='foreign'then return detach('closed','Foreign Bloom value preserved')end
  if self.state=='awaiting'then return false,'Awaiting bounded Bloom acknowledgement'end
  if self.state=='blocked'and explicit~=true then return false,self.reason end
  if not written then return detach('closed','Bloom released without native changes')end
  if foreign_unknown then return false,'Failed foreign Bloom submission; native ownership remains unknown'end
  local stamp=now();if not stamp then return false,self.reason end
  if next_poll and stamp<next_poll then return false,'Awaiting Bloom cleanup read interval'end
  next_poll=stamp+.1
  local current=read();if current==nil then return false,self.reason end
  return cleanup(current,stamp)
 end
 function self.waiting()return self.state=='awaiting'end
 function self.status()
  if self.state=='active'then return'Bloom: '..(observed and'ON'or'OFF')..' (native). Exposure, contrast and saturation are not ported.'end
  return'Bloom: '..tostring(self.reason or self.state)..'. Exposure, contrast and saturation are not ported.'
 end
 return self
end
local function copy(v)return{v[1],v[2],v[3]}end
function M.new(host,sr,deps,service)
 local self={active=false,state='closed',mode='menu',reason=nil}
 local camera=deps.camera.new(sr);local input=deps.input.new(sr,service)
 local simulation=sr.Network and sr.GameSession and M.time_policy(sr,os.time)
 local bloom=M.bloom_policy(sr);local bloom_revision
 -- The loader owns transport and the external worker. No capture service means
 -- the existing controls stay gated, with no new closed/idle work.
 local capture_backend=deps.capture_backend
 local capture=deps.capture and capture_backend and deps.capture.new(capture_backend,sr.Application.time_since_launch)
 local capture_frame,capture_completed_frame,capture_sequence=0,0,0
 local capture_world,capture_generation,capture_scene
 local capture_context={}
 local lighting=deps.lighting and deps.lighting.new(sr,deps.lights,host.log)
 local presets=deps.light_presets and deps.light_presets.new(host.config_dir..'/lighting-presets.ini')
 local core=deps.core.new(deps.store.new(host.config_dir),host.log)
 local view=deps.view.new(sr,nil,host.log);local overlay=deps.view.new(sr,true,host.log)
 local handle,menu,prior,wrapper,photo,initial,options,options_revision
 local light_sync=false;local light_revision
 local light_frame
 local refresh_setups
 local sample_sequence=0;local edges={};local controls={};local texts={};local last_time
 local overlay_commands,overlay_revision,overlay_width,overlay_height,overlay_capture
 local grain_view,grain_commands,grain_phase,grain_width,grain_height,grain_amount,grain_size,grain_frame
 local lens_fov,lens_gameplay,lens_text
 local pending_cleanup=false;local full_cleanup=false;local disposed=false;local base_cleanup_done=false;local full_time_released=false
 local close_persisted=false;local close_persist_reason
 local freeze_sync=false;local simulation_revision
 local shot
 local path=deps.path and deps.path.new();local path_output={};local path_sync=false
 local sync_path
 local decorative,decorative_active,decorative_opt_in,decorative_finalizing
 local decorative_status,decorative_button
 local function shader_status(message)
  if message~=decorative_status then
   decorative_status=message
   if texts.shader_status then texts.shader_status.label=message end
  end
 end
 local function close_decorative(dispose)
  if not decorative then return true end
  decorative_finalizing=decorative_finalizing or dispose==true
  local called,ok,why=pcall(decorative_finalizing and decorative.dispose or decorative.close)
  if not called or ok==false then return false,tostring(called and(why or'Decorative overlay cleanup pending')or ok)end
  decorative_active=false
  if decorative_finalizing then decorative=nil;decorative_finalizing=nil end
  return true
 end
 local function toggle_decorative()
  if not deps.decorative_overlay then return false,'Decorative overlay adapter unavailable'end
  if decorative_opt_in then
   decorative_opt_in=false
   local ok,why=close_decorative(false)
   if not ok then self.close(true);return false,why end
   shader_status('Decorative overlay preview disabled')
  else
   decorative_opt_in=true
   shader_status('Unvalidated overlay preview enabled for this runtime session')
  end
  if decorative_button then decorative_button.button_label=decorative_opt_in and'Disable preview'or'Enable preview' end
  return true
 end
 local function notice(why)
  local message=tostring(why);local changed=message~=self.reason;self.reason=message
  if menu then menu.notice=message end
  -- Error reporting must not prevent native restoration if the shared file
  -- transport has itself failed. This runs only on a changed notice.
  if changed then pcall(host.log,message)end
 end
 local function sync_bloom()
  if not bloom or bloom_revision==bloom.revision then return end
  bloom_revision=bloom.revision
  if texts.color_status then texts.color_status.label=bloom.status()end
 end
 local function tick_bloom(time)
  if not bloom then return end
  local ok,why=bloom.tick(time);sync_bloom()
  if not ok and why then notice(why)end
 end
 local function flush_roll()
  if photo and photo.roll~=nil then
   local value=photo.roll;photo.roll=nil
   local ok,why=handle.set('roll',value)
   if ok==false then notice(why);return false,why end
  end
  return true
 end
 local function stop_path()
  if path then path.stop()end
  if photo and photo.path_fov then
   local ok,why=handle.set_many({roll=(photo.path_roll+180)%360-180,fov=math.deg(photo.path_fov)})
   if ok==false then notice(why);return false,why end
   photo.path_fov,photo.path_roll=nil,nil
  end
  return true
 end
 local function edge(code)
  local down=input.down(code);local value=down and not edges[code];edges[code]=down;return value
 end
 local function read_options()
  if options_revision~=core.revision then options=deps.options.read(handle);options_revision=core.revision end
  return options
 end
 local function unhook()
  if wrapper and rawget(_G,'render')==wrapper then rawset(_G,'render',prior)end
  wrapper,prior=nil,nil
 end
 local function release_grain()
  if not grain_view then return true end
  local ok,why=grain_view.release()
  if ok==false then return false,why or 'Film grain cleanup pending'end
  grain_view,grain_commands,grain_phase=nil,nil,nil
  return true
 end
 local function capture_state()
  local world,generation
  if self.active and not pending_cleanup then world,generation=camera.scene()end
  capture_context.scene=world~=nil and world==capture_world and generation==capture_generation and capture_scene or nil
  capture_context.session=sr.Network and sr.Network.game_session()
  capture_context.focused=self.active and not pending_cleanup and input.focused()
  capture_context.frame_id=capture_completed_frame
  return capture_context
 end
 local function capture_notice()
  local result=capture.result()
  if not result then return end
  if result.state=='succeeded'then notice('Screenshot saved: '..result.output_path)
  elseif result.state=='cleanup_blocked'then notice('Screenshot cleanup unconfirmed; press Screenshot to retry')
  elseif result.state=='failed'then notice('Screenshot failed: '..tostring(result.reason))
  elseif result.state=='cancelled'then notice('Screenshot cancelled: '..tostring(result.reason))end
 end
 local function capture_tick()
  if not capture then return end
  local before=capture.state()
  if before=='idle'or before=='cleanup_blocked'then return end
  capture.tick(capture.active()and capture_state()or nil)
  if capture.state()~=before then capture_notice()end
 end
 function self.screenshot()
  if not capture then return false,'Screenshot unavailable'end
  if capture.state()=='cleanup_blocked'then
   local ok,why=capture.cancel('User requested screenshot cleanup retry');capture_notice();return ok,why
  end
  if not self.active or pending_cleanup then return false,'Screenshot unavailable'end
  if capture.busy()then return false,'Screenshot already active'end
  if menu.editing_key()or menu.editing_text()then return false,'Finish editing before taking a screenshot'end
  capture_world,capture_generation=camera.scene();capture_scene={}
  capture_sequence=capture_sequence+1
  -- Plain ASCII, one direct basename under the service's fixed directory.
  -- The service validates the path and never replaces an existing file.
  local stamp=string.format('%.0f',sr.Application.time_since_launch()*1000000)
  local name='War-Journalist-'..os.date('%Y%m%d-%H%M%S')..'-'..stamp..'-'..capture_sequence..'.png'
  local path=capture_backend.output_directory:gsub('[/\\]+$','')..'/'..name
  local ok,why=capture.begin({output_token=name,output_path=path},capture_state())
  if ok then menu.suspend()else notice(why)end
  return ok,why
 end
 self.capture=capture
 function self.close(clear_time,automatic)
  if capture then capture.close('Photo Mode closed')end
  if not pending_cleanup then close_persisted=false;close_persist_reason=nil;base_cleanup_done=false;full_time_released=false end
  full_cleanup=full_cleanup or clear_time==true
  self.state='closing';pending_cleanup=true
  if base_cleanup_done and full_cleanup and not full_time_released and simulation then
   local ok,why=simulation.release();if not ok then notice(why);return false,why end
   full_time_released=true
  end
  if not base_cleanup_done then
  if simulation then
   local ok,why
   if full_cleanup then ok,why=simulation.release()else ok,why=simulation.resume()end
   if not ok then notice(why);return false,why end
    if full_cleanup then full_time_released=true end
  end
  if not close_persisted then
   -- Saving the last lens is best effort during exit. A broken settings pipe
   -- must never starve camera/input restoration or be retried each frame.
   close_persisted=true
   for _,save in ipairs({stop_path,flush_roll})do
    local called,ok,why=pcall(save)
    if not called or ok==false then close_persist_reason=close_persist_reason or tostring(called and why or ok)end
   end
   if path then path.clear()end
  end
  if lighting then
   local called,ok,why=pcall(lighting.close)
   if not called then notice(ok);return false,ok end
   if ok==false then notice(why);return false,why end
  end
  local called,ok,why=pcall(camera.close)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  called,ok,why=pcall(input.release)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  unhook()
  if menu then
   called,ok,why=pcall(menu.close)
   if not called then notice(ok);return false,ok end
   if ok==false then notice(why);return false,why end
  end
  called,ok,why=pcall(overlay.release)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  called,ok,why=pcall(release_grain)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  local retired,reason=close_decorative(false)
  if not retired then notice(reason);return false,reason end
  base_cleanup_done=true;self.active=false
  photo,initial,shot=nil,nil,nil
  end
  -- Final disposal can fail after base cleanup has already succeeded. Its
  -- retained ownership must remain a separate barrier on every close retry.
  if decorative_finalizing then
   local retired,reason=close_decorative(true)
   if not retired then notice(reason);return false,reason end
  end
  if bloom then
   local ok,why=bloom.close(automatic~=true);sync_bloom()
   if not ok then notice(why);return false,why end
  end
  pending_cleanup=false;full_cleanup=false;self.state='closed'
  if close_persist_reason then notice('Camera restored; lens settings were not saved: '..close_persist_reason)end
  close_persist_reason=nil
  return true
 end
 function self.focus()
  if not self.active or pending_cleanup then return false end
  if self.mode=='shot'then return false,'Return using the Photo Mode key'end
  if not stop_path()then return false,self.reason end
  flush_roll();photo.target=nil
  if photo.view then photo.view.target_yaw=nil;photo.view.target_pitch=nil end
  local next_mode=self.mode=='menu'and'camera'or'menu'
  local ok,why=input.set_mode(next_mode)
  if not ok then notice(why);self.close();return false,why end
  self.mode=next_mode;menu.suspend();sample_sequence=sample_sequence+1
  return true
 end
 local function hide()
  if handle.get('hide_controls')or handle.get('clean_view')then
   return handle.set_many({hide_controls=false,clean_view=false})
  end
  return handle.set('hide_controls',not handle.get('hide_controls'))
 end
 local function reset()
  for id,c in pairs(controls)do
   if not c.disabled and c.default~=nil and(deps.options.defaults[id]~=nil or id=='light_subject_distance')then handle.set(id,c.default)end
  end
 end
 local bindings={
  {id='enabled',type='toggle',label='Enable Photo Mode',default=true},
  {id='toggle_key',type='keybind',label='Photo mode toggle',default=80},
  {id='focus_key',type='keybind',label='Switch camera / menu focus',default=9},
  {id='hide_controls_key',type='keybind',label='Show / hide photo controls',default=72},
  {id='lock_camera_key',type='keybind',label='Lock / unlock camera',default=76},
  {id='forward_key',type='keybind',label='Move forward',default=87},
  {id='back_key',type='keybind',label='Move backward',default=83},
  {id='left_key',type='keybind',label='Move left',default=65},
  {id='right_key',type='keybind',label='Move right',default=68},
  {id='up_key',type='keybind',label='Move up',default=16},
  {id='down_key',type='keybind',label='Move down',default=17},
  {id='roll_left_key',type='keybind',label='Roll left',default=81},
  {id='roll_right_key',type='keybind',label='Roll right',default=69},
  {id='screenshot_key',type='keybind',label='Screenshot key',default=19,disabled=not capture},
  {id='slowmo_key',type='keybind',label='Slow-motion key',default=220,disabled=not simulation},
  {id='recover_input_key',type='keybind',label='Recovery key (Ctrl+Shift)',default=121},
  {id='recover_input',type='button',label='Recover gameplay input',on_activate=function()return self.close(true)end},
  {id='runtime_status',type='text',label='Lua 5.1 development port: native feature backends are still being validated.'}}
 local movement={
  {id='speed',type='slider',label='Movement speed (m/s)',default=3,min=.1,max=50,step=.1},
  {id='wheel_step',type='slider',label='Wheel speed change (%)',default=20,min=5,max=100,step=5},
  {id='look_sensitivity',type='slider',label='Camera look sensitivity',default=.15,min=.01,max=1,step=.01},
  {id='roll_speed',type='slider',label='Roll speed (degrees/s)',default=45,min=1,max=180,step=1},
  {id='freeze_player',type='toggle',label='Freeze Action',default=true,disabled=not simulation,
   on_change=function(value)
    if freeze_sync or not self.active or self.mode=='shot'or not simulation then return end
    local ok,why;if value then ok,why=simulation.freeze()else ok,why=simulation.resume()end
    if not ok then notice(why)end
   end},
  {id='slowmo_speed',type='slider',label='Slow motion speed',default=.2,min=.05,max=1,step=.05,fine_step=.01,
   disabled=not simulation,on_change=function(value)
    if simulation then local ok,why=simulation.set_slowmo(simulation.slowmo_active,value);if not ok then notice(why)end end
   end},
  {id='freeze_hint',type='text',label='Solo true-zero pause. Resume uses selected slow motion or normal 1x; hoverpack guard is not ported yet.'}}
 local light_ids={light_add=true,light_selected=true,light_enabled=true,light_kind=true,
  light_intensity=true,light_color=true,light_cone=true,light_right=true,
  light_forward=true,light_up=true,light_follow=true,light_place=true,light_remove=true,light_clear=true,
  light_aim=true,light_preset=true,light_apply_preset=true,light_subject_distance=true,
  light_setup_slot=true,light_setup_save=true,light_setup_recall=true,light_setup_clear=true}
 local function light_action(action,value)
  if not lighting then return false,'Lighting backend unavailable'end
  local ok,why=lighting.action(action,value);if not ok then notice(why)end;return ok,why
 end
 local function subject_light(action)
  if not lighting or not photo then return false,'Place the Photo camera first'end
  local name=deps.options.light_presets[handle.get('light_preset')]
  local ok,why=lighting.subject(action,light_frame(),handle.get('light_subject_distance'),name)
  if not ok then notice(why)end;return ok,why
 end
 local function lighting_setup(action)
  if not lighting or not presets or not photo then return false,'Lighting setup storage unavailable'end
  local ok,why=lighting.setup(action,presets,handle.get('light_setup_slot'),light_frame(),handle.get('light_subject_distance'))
  refresh_setups();if not ok then notice(why)end;return ok,why
 end
 local function path_action(action)
  if not path or not photo then return false,'Open Photo Mode first'end
  if not stop_path()then return false,self.reason end
  local ok,why=true
  if action=='add'then
   flush_roll();local o=read_options();local f=photo.forward
   ok,why=path.add({pos=photo.pos,yaw=math.atan2(f[2],f[1]),pitch=math.asin(math.max(-1,math.min(1,f[3]))),
    roll=o.roll,fov=o.fov>0 and math.rad(o.fov)or initial.fov,
    duration=handle.get('path_duration'),transition=handle.get('path_transition')})
  elseif action=='remove'then ok,why=path.remove(handle.get('path_point'))
  elseif action=='clear'then path.clear()
  elseif action=='play'then ok,why=path.play(sr.Application.time_since_launch())end
  sync_path();if ok==false then notice(why)end;return ok,why
 end
 local function shot_context()
  local world,generation=camera.scene()
  local session=sr.Network and sr.Network.game_session()
  return world,generation,session
 end
 local function check_shot()
  if not shot then return false,'Action shot is unavailable'end
  local world,generation,session=shot_context()
  if not world or world~=shot.world or generation~=shot.generation or session~=shot.session then
   return false,'Action shot ended: session or camera changed'
  end
  return true
 end
 function self.begin_shot(play_path)
  if not self.active or self.mode=='shot'or pending_cleanup then return false,'Place the Photo camera first'end
  if handle.get('action_camera_mode')~=1 then
   notice('Handycam is waiting for a verified player backend; choose Placed camera')
   return false,self.reason
  end
  if play_path and(not path or path.count()<2)then notice('Record at least two camera points');return false,self.reason end
  if not stop_path()then return false,self.reason end
  flush_roll()
  local world,generation,session=shot_context()
  if not world or not session then notice('Action shot session unavailable');return false,self.reason end
  local was_frozen=simulation and simulation.frozen or false
  if simulation then
   local ok,why=simulation.resume();if not ok then notice(why);return false,why end
  end
  local ok,why=input.release()
  if not ok then notice(why);self.close(true);return false,why end
  local now=sr.Application.time_since_launch()
  shot={world=world,generation=generation,session=session,refreeze=was_frozen,started=now,check_at=now}
  self.mode='shot';menu.suspend();photo.target=nil
  if photo.view then photo.view.target_yaw=nil;photo.view.target_pitch=nil end
  if play_path then
   ok,why=path.play(now)
   if not ok then notice(why);self.reposition_shot();return false,why end
  end
  texts.cinema_status.label='Action shot active; Photo Mode key returns to placement'
  return true
 end
 function self.reposition_shot()
  if not self.active or self.mode~='shot'or pending_cleanup then return false,'No action shot is active'end
  local ok,why=check_shot()
  if not ok then notice(why);self.close(true);return false,why end
  -- The Photo key is processed before the next simulation tick. Consume an
  -- already observed foreign takeover here too, before considering refreeze.
  if simulation and simulation.reason then shot.refreeze=false end
  -- Reacquire only our cursor lease. Never replace another menu's owner.
  ok,why=input.set_mode('menu');if not ok then
   notice(why);if input.pending_restore()then self.close(true)end;return false,why
  end
  if not stop_path()then self.close(true);return false,self.reason end
  local refreeze=shot.refreeze;shot=nil;self.mode='menu';menu.suspend()
  sample_sequence=sample_sequence+1;last_time=sr.Application.time_since_launch()
  texts.cinema_status.label='Place a camera, then begin an action shot'
  if refreeze and simulation then
   ok,why=simulation.freeze()
   if not ok then notice(why);self.close(true);return false,why end
  elseif simulation and not simulation.frozen and handle.get('freeze_player')then
   -- A foreign time modifier may have revoked our pause during the shot.
   -- Reflect that single transition without reapplying its old preference.
   freeze_sync=true;local called,accepted=pcall(handle.set,'freeze_player',false);freeze_sync=false
   if not called or accepted==false then notice('Freeze setting synchronization failed')end
  end
  return true
 end
 local pages=deps.options.pages(reset,function()
  local was=self.active;local ok=self.close();if ok and was then self.open()end
 end,deps.composition,{camera_controls=movement,
  screenshot=capture and self.screenshot or nil,
  path_add=function()return path_action('add')end,path_remove=function()return path_action('remove')end,
  path_clear=function()return path_action('clear')end,path_play=function()return path_action('play')end,
  cinema_begin=function()return self.begin_shot()end,
  cinema_reposition=function()if self.mode=='shot'then return self.reposition_shot()else return self.focus()end end,
  cinema_end=function()return self.close()end,
  path_change=function(id)
   if path_sync or not path or not photo then return end
   if not stop_path()then return end
   local index=handle.get('path_point')
   if id=='path_point'then sync_path()
   else local ok,why=path.configure(index,handle.get('path_duration'),handle.get('path_transition'))
    if not ok then notice(why)end end
  end,
  light_change=function(id,value)if lighting and not light_sync then local ok,why=lighting.change(id,value);if not ok then notice(why)end end end,
  light_add=function()return light_action('create')end,
  light_place=function()return light_action('place_at_camera')end,
  light_aim=function()return subject_light('aim')end,
  light_apply_preset=function()return subject_light('preset')end,
  light_setup_save=function()return lighting_setup('save')end,
  light_setup_recall=function()return lighting_setup('recall')end,
  light_setup_clear=function()return lighting_setup('clear')end,
  light_remove=function()return light_action('remove')end,
  light_clear=function()return light_action('release','User cleared lights')end})
 pages[#pages+1]={id='camera',name='Controls',require_confirmation=false,controls=bindings}
 if path then for _,page in ipairs(pages)do if page.id=='director'then
  for index,c in ipairs(page.controls)do if c.id=='path_play'then
   table.insert(page.controls,index+1,{id='path_shot',type='button',label='Play path as action shot',
    on_activate=function()return self.begin_shot(true)end});break
  end end
 end end end
 for _,page in ipairs(pages)do if page.id=='lighting'then
  for index,c in ipairs(page.controls)do if c.id=='light_apply_preset'then
   table.insert(page.controls,index,{id='light_subject_distance',type='slider',label='Lighting subject distance (m)',
    default=5,min=.1,max=1000,step=.1,commit_on_blur=true});break
  end end
  for _,c in ipairs(page.controls)do if c.id=='light_preset_hint'then
   c.label='Aim and presets use a point ahead of the camera at Lighting subject distance.'
  end end
 end end
 if deps.decorative_overlay then for _,page in ipairs(pages)do if page.id=='effects'then
  for index,c in ipairs(page.controls)do if c.id=='shader'then
   table.insert(page.controls,index,{id='shader_preview',type='button',label='Unvalidated overlay preview (session)',
    button_label='Enable preview',photo_section=c.photo_section,on_activate=toggle_decorative})
   c.photo_section=nil;break
  end end
 end end end
 local supported={fov=true,focal_preset=true,roll=true,roll_preset=true,lock_camera=true,camera_smoothing=true,smoothing_strength=true,
  frame=true,grid=true,filter=true,filter_strength=true,vignette=true,vignette_width=true,grain=true,grain_size=true,
  logo=true,logo_size=true,logo_color=true,logo_opacity=true,logo_x=true,logo_y=true,
  hide_controls=true,clean_view=true,show_legend=true,legend_open=true,legend_docked=true,legend_tab_y=true,legend_columns=true,
  legend_x=true,legend_y=true,legend_size=true,tab_layout=true,menu_x=true,menu_y=true,menu_scale=true,menu_opacity=true,
  speed=true,wheel_step=true,look_sensitivity=true,roll_speed=true,reset_photo=true,recenter=true,saved_camera_radius=true,
  cinema_begin=true,cinema_reposition=true,cinema_end=true,cinema_notification=true,action_camera_mode=true}
 if deps.decorative_overlay then for _,id in ipairs({'shader_preview','shader','shader_opacity','shader_scale','shader_animate'})do supported[id]=true end end
 if simulation then supported.freeze_player=true;supported.slowmo_speed=true end
 if bloom then supported.bloom=true end
 if capture then supported.screenshot=true end
 if path then for _,id in ipairs({'path_add','path_remove','path_clear','path_play','path_shot','path_point','path_duration','path_transition'})do supported[id]=true end end
 for _,c in ipairs(bindings)do supported[c.id]=not c.disabled end
 for _,page in ipairs(pages)do for _,c in ipairs(page.controls)do
  if c.type~='text'and c.type~='section'then
   c.disabled=not supported[c.id]
   controls[c.id]=c
  elseif c.id and c.id:match('_status$')then texts[c.id]=c;c.label='Lua 5.1: backend validation pending'end
 end end
 handle=core.register({id='dbf_freecam',name='War Journalist',pages=pages})
 controls=core.mods.dbf_freecam.controls
 if capture then controls.screenshot.button_label='Take screenshot (SDR)'end
 -- Registration copies definitions. Keep live status references on those
 -- registered rows, not on the discarded construction tables.
 texts={}
 for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do
  if c.type=='text'and c.id and c.id:match('_status$')then texts[c.id]=c end
 end end
 decorative_button=controls.shader_preview
 shader_status(deps.decorative_overlay and'Overlay preview disabled; enable explicitly for this session'or'Decorative overlay adapter unavailable')
 if bloom then
  controls.bloom.on_change=function(value)
   if not self.active or pending_cleanup then return end
   local ok,why=bloom.request(value);sync_bloom();if not ok and why then notice(why)end
  end
  sync_bloom()
 end
 controls.action_camera_mode.choices={'Placed camera','First-person handycam (not yet available)'}
 texts.cinema_status.label='Place a camera, then begin an action shot'
 for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do if c.id=='cinema_hint'then
  c.label='Move and fight while the camera holds its shot. Your Photo Mode key returns to placement and restores Freeze Action.'
 end end end
 sync_path=function()
  if not path then return end
  local choices={};for i=1,path.count()do choices[i]='Point '..i end
  if #choices==0 then choices[1]='No recorded points'end
  controls.path_point.choices=choices
  local index=math.max(1,math.min(path.count(),handle.get('path_point')))
  local p=path.point(index);local values={path_point=index}
  if p then values.path_duration=p.duration;values.path_transition=p.transition end
  path_sync=true;local called,ok,why=pcall(handle.set_many,values);path_sync=false
  if not called or ok==false then error(called and why or ok)end
  texts.path_status.label=path.count()..' camera points recorded'
 end
 if path then
  controls.path_play.label='Preview camera path'
  for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do if c.id=='path_hint'then
   c.label='Preview within Photo Mode. Smooth transitions or timed cuts; Tab stops playback. Points clear on exit.'
  end end end
  sync_path()
 end
 controls.enabled.on_change=function(value)if not value then self.close(true)end end
 -- Expand coupled optical values before the core's single persistence commit.
 -- Post-commit callbacks would require a second save and can strand a preset
 -- label if that save fails. These wrappers cover UI edits, resets and batches.
 local set_value,set_values,get_value=handle.set,handle.set_many,handle.get
 local lens_fields={fov=true,focal_preset=true,roll=true,roll_preset=true}
 -- Historical files can contain a shortcut that disagrees with its actual
 -- lens value. Present that as Custom without requiring a disk write on entry.
 local preset_display={focal_preset={field='fov',tolerance=.0011},roll_preset={field='roll',tolerance=.01}}
 handle.get=function(id)
  local value=get_value(id);local cached=preset_display[id]
  if not cached then return value end
  local actual=get_value(cached.field)
  if cached.preset~=value or cached.actual~=actual then
   cached.preset,cached.actual=value,actual
   local target=id=='focal_preset'and deps.options.preset_fov(value)or deps.options.roll_presets[value]
   cached.value=target~=nil and target~=false and math.abs(actual-target)>cached.tolerance and 1 or value
  end
  return cached.value
 end
 local function lens_values(values)
  local expanded={};for key,value in pairs(values)do expanded[key]=value end
  for _,pair in ipairs({{'fov','focal_preset',.0011},{'roll','roll_preset',.01}})do
   local field,preset,tolerance=pair[1],pair[2],pair[3]
   if values[preset]~=nil then
    local target
    if preset=='focal_preset'then target=deps.options.preset_fov(values[preset])
    else target=deps.options.roll_presets[values[preset]]end
    if target~=nil and target~=false then
     if values[field]~=nil then
      local value=values[field]
      if type(value)~='number'or value~=value or math.abs(value-target)>tolerance then
       return nil,'Lens value conflicts with its preset'
      end
     end
     expanded[field]=target
    end
   elseif values[field]~=nil then expanded[preset]=1 end
  end
  return expanded
 end
 handle.set_many=function(values)
  local coupled=false;for key in pairs(values)do if lens_fields[key]then coupled=true;break end end
  if not coupled then return set_values(values)end
  local expanded,why=lens_values(values)
  if not expanded then notice(why);return false,why end
  local pending_photo=photo
  local path_fov=pending_photo and pending_photo.path_fov
  local path_roll=pending_photo and pending_photo.path_roll
  local replacing_path=path_fov and(expanded.fov~=nil or expanded.roll~=nil)
  if replacing_path then
   -- Editing a lens takes over from preview at its current frame. Preserve
   -- the other path lens value in the same transaction before stopping it.
   if expanded.fov==nil then expanded.fov=math.deg(path_fov);expanded.focal_preset=1 end
   if expanded.roll==nil then expanded.roll=(path_roll+180)%360-180;expanded.roll_preset=1 end
   pending_photo.path_fov,pending_photo.path_roll=nil,nil
  end
  -- A mixed batch may run enabled=false's close callback during commit. Hide
  -- the superseded keyboard roll before callbacks, restoring it on refusal.
  local replacing_roll=pending_photo and expanded.roll~=nil
  local pending_roll=replacing_roll and pending_photo.roll or nil
  if replacing_roll then pending_photo.roll=nil end
  local called,ok,why=pcall(set_values,expanded)
  if not called or ok==false then
   if replacing_roll and photo==pending_photo then pending_photo.roll=pending_roll end
   if replacing_path and photo==pending_photo then pending_photo.path_fov,pending_photo.path_roll=path_fov,path_roll end
   notice((called and why or ok)or'Lens settings could not be saved')
   if not called then error(ok,0)end
  elseif replacing_path and photo==pending_photo and path then path.stop()end
  return ok,why
 end
 handle.set=function(id,value)
  if lens_fields[id]then return handle.set_many({[id]=value})end
  return set_value(id,value)
 end
 deps.menu.legend_factory=deps.legend
 menu=deps.menu.new(view,{focus=self.focus,hide=hide,exit=self.close,
  freeze=simulation and function()
   local value=not simulation.frozen
   if handle.get('freeze_player')~=value then return handle.set('freeze_player',value)end
   local ok,why;if value then ok,why=simulation.freeze()else ok,why=simulation.resume()end
   if not ok then notice(why)end;return ok,why
  end or nil,
  freeze_state=simulation and function()return simulation.frozen,self.active and not pending_cleanup end or nil,
  slowmo=simulation and function()return self.toggle_slowmo()end or nil,
  slowmo_state=simulation and function()return simulation.slowmo_active,handle.get('enabled')and not pending_cleanup and not simulation.pending_restore end or nil,
  hud=function()notice('HUD backend validation pending')end})
 menu.bind(handle,core.mods.dbf_freecam.pages)
 if deps.gizmos and lighting then
  menu.light_gizmos=deps.gizmos.new(light_action)
  menu.prepare_light_gizmos=function(w,h,focused,hidden)
   local items=self.active and focused and not hidden and lighting.markers()or nil
   if not items then menu.light_gizmos.update(nil,nil,nil,w,h,false);return end
   local frame=light_frame();frame.world,frame.scene_epoch=lighting.scene()
   local o=read_options();local fov=photo.path_fov or(o.fov>0 and math.rad(o.fov)or initial.fov)
   menu.light_gizmos.update(items,frame,fov,w,h,true)
  end
 end
 self.handle=handle
 function self.toggle_slowmo()
  if not simulation or not handle.get('enabled')or pending_cleanup then return false,'Slow motion unavailable'end
  local ok,why=simulation.set_slowmo(not simulation.slowmo_active,handle.get('slowmo_speed'))
  if not ok then notice(why)end;return ok,why
 end
 refresh_setups=function()
  if not presets then return end
  controls.light_setup_slot.choices=presets.list()
  texts.light_setup_status.label=presets.status
 end
 refresh_setups()
 local function light_controls(enabled)
  for id in pairs(light_ids)do if controls[id]then controls[id].disabled=not enabled end end
  if not presets then for _,id in ipairs({'light_setup_slot','light_setup_save','light_setup_recall','light_setup_clear'})do
   controls[id].disabled=true
  end end
  if texts.light_status and lighting then texts.light_status.label=lighting.status end
 end
 light_frame=function()
  local o=read_options()
  local f=photo.forward;local u=deps.lens.up(f,photo.right,photo.path_roll or photo.roll or o.roll)
  local r={f[2]*u[3]-f[3]*u[2],f[3]*u[1]-f[1]*u[3],f[1]*u[2]-f[2]*u[1]}
  return{position=photo.pos,forward=f,right=r,up=u}
 end
 local function sync_light()
  if not lighting or light_revision==lighting.revision()then return end
  local values,selected,count=lighting.selected()
  light_sync=true
  local ok,why=pcall(function()
   local changes={}
   if count>0 then changes.light_selected=selected end
   if values then
    local fields={light_enabled='enabled',light_intensity='intensity',light_color='color',
     light_cone='cone',light_right='right',light_forward='forward',light_up='up',light_follow='follow_camera'}
    for id,field in pairs(fields)do changes[id]=values[field]end
    changes.light_kind=values.kind=='spot'and 2 or 1
   end
   local accepted,reason=handle.set_many(changes);if not accepted then error(reason)end
  end)
  light_sync=false
  if not ok then error(why)end
  light_revision=lighting.revision()
 end
 function self.render()
  if not self.active or pending_cleanup then return end
  local o=read_options()
  local f,r=photo.forward,photo.right
  local up=deps.lens.up(f,r,photo.path_roll or photo.roll or o.roll)
  local fov=photo.path_fov or(o.fov>0 and math.rad(o.fov)or initial.fov)
  if self.mode~='shot'and not o.hide_controls and not o.clean_view then
   local gameplay=not photo.path_fov and o.fov==0
   if lens_fov~=fov or lens_gameplay~=gameplay then
    lens_fov,lens_gameplay=fov,gameplay
    local mm=deps.options.focal_length(fov)
    local label=mm and('Focal length: '..string.format('%.1f mm',mm)..(gameplay and' (gameplay)'or''))or'Focal length: waiting for camera'
    if label~=lens_text then
     lens_text=label;texts.focal_length_status.label=label
    end
   end
  end
  local ok,why=camera.write_view(photo.pos,f,up,fov,self.mode=='shot')
  if not ok then notice(why);self.close(true);return end
  local width,height=sr.Gui.resolution()
  local capturing=capture and capture.active()or false
  if overlay_revision~=options_revision or overlay_width~=width or overlay_height~=height or overlay_capture~=capturing then
   local visible=o
   if capturing then visible={};for key,value in pairs(o)do visible[key]=value end;visible.grid=1 end
   overlay_commands=deps.composition.layout_static(width,height,visible)
   for _,command in ipairs(overlay_commands)do command.type=command.type or command.kind end
   overlay_revision,overlay_width,overlay_height,overlay_capture=options_revision,width,height,capturing
  end
  -- Geometry is immutable until the revision, viewport or capture mode changes.
  -- Retain it without rescanning thousands of logo primitives each frame.
  local decorative_drawn=true
  if decorative_opt_in and o.shader>1 and o.shader_opacity>0 then
   if not decorative then decorative=deps.decorative_overlay.new(sr,deps.view,deps.composition,host.log)end
   if not decorative_active then
    local called,ready,reason=pcall(decorative.open)
    if not called or ready==false then
     notice(called and reason or ready);self.close(true);return false
    end
    decorative_active=true
   end
   local called,done,reason=pcall(decorative.draw,width,height,o,last_time or 0)
   decorative_drawn=called and done==true
   if not called then
    notice(done);self.close(true);return false
   elseif done~=true then
    local _,pending=decorative.status()
    shader_status(reason or'Decorative overlay draw unacknowledged')
    if pending then notice(reason);self.close(true);return false end
   else shader_status('Unvalidated decorative overlay preview')end
  elseif decorative_active then
   local retired,reason=close_decorative(false)
   if not retired then notice(reason);self.close(true);return false end
   shader_status(decorative_opt_in and'Choose an overlay and nonzero opacity'or'Decorative overlay preview disabled')
  end
  local drawn=overlay.draw(overlay_commands,overlay_commands)
  local grain_drawn=true
  if o.grain>0 then
   if not grain_view then grain_view=deps.view.new(sr,true,host.log)end
   -- Reuse the active update's application time. World pause does not stop
   -- grain, and disabled/closed grain adds no clock reads or refresh work.
   local phase=math.floor((last_time or 0)*12)%4096
   if grain_phase~=phase or grain_width~=width or grain_height~=height or
    grain_amount~=o.grain or grain_size~=o.grain_size or grain_frame~=o.frame then
    grain_commands=deps.composition.layout_grain(width,height,o,phase)
    for _,command in ipairs(grain_commands)do command.type=command.type or command.kind end
    grain_phase,grain_width,grain_height=phase,width,height
    grain_amount,grain_size,grain_frame=o.grain,o.grain_size,o.frame
   end
   grain_drawn=grain_view.draw(grain_commands,grain_commands)
  elseif grain_view then
   local called,ok,why=pcall(release_grain)
   if not called or ok==false then
    notice(called and why or ok);self.close(true);return false
   end
  end
  if capturing then
   -- Destroy owned UI planes directly: an empty draw may refuse early when
   -- font/drawability is unavailable and leave retained controls visible.
   return menu.hide_for_capture()==true and decorative_drawn and drawn~=false and grain_drawn~=false
  elseif self.mode=='shot'then
   menu.draw_cinema(width,height,deps.legend.key_label(handle.get('toggle_key')),capturing or not o.cinema_notification,
    sr.Application.time_since_launch()-shot.started,capture~=nil)
  else
   menu.draw(width,height,self.mode=='menu',capturing or o.hide_controls or o.clean_view,
    {focus=deps.legend.key_label(handle.get('focus_key')),hide=deps.legend.key_label(handle.get('hide_controls_key')),slowmo=deps.legend.key_label(handle.get('slowmo_key'))})
  end
  return false
 end
 local function open()
  if disposed or self.active or pending_cleanup or not handle.get('enabled')then return false,'Photo Mode is unavailable'end
  local ok,why=input.set_mode('menu');if not ok then notice(why);self.close();return false,why end
  ok,why=camera.open();if not ok then notice(why);self.close();return false,why end
  initial=assert(camera.frame());photo={pos=copy(initial.position),forward=copy(initial.forward),right=copy(initial.right)}
  if lighting then
   local world,generation=camera.scene()
   local ready=lighting.open(world,generation,light_frame())
   light_controls(ready==true)
   light_revision=nil;sync_light()
  end
  self.active=true;self.mode='menu';self.state='active';self.reason=nil
  if bloom then local ok,why=bloom.open(handle.get('bloom'));sync_bloom();if not ok then notice(why)end end
  if simulation and handle.get('freeze_player')then
   local ok,why=simulation.freeze();if not ok then
    notice(why)
    if simulation.frozen then self.close();return false,why end
    -- An unavailable pause must never prevent the camera/menu from opening.
    freeze_sync=true;local called,accepted=pcall(handle.set,'freeze_player',false);freeze_sync=false
    if not called or accepted==false then self.close();return false,'Freeze setting synchronization failed'end
   end
  end
  if path then sync_path()end
  prior=assert(rawget(_G,'render'),'Game render callback unavailable')
  local saved=prior
  local owned
  local function rendered(frame,hidden,ok,...)
   if not ok then
    if capture then capture.invalidate('Game render failed')end
    error((...),0)
   end
   if wrapper==owned and not disposed and capture then
    capture_completed_frame=math.max(capture_completed_frame,frame)
    if capture.active()then capture.rendered(frame,hidden,true,capture_state())end
   end
   return ...
  end
  owned=function(...)
   local hidden=false
   if wrapper==owned and not disposed then
    local ok,result=pcall(self.render)
    if not ok then notice(result);self.close()else hidden=result==true end
   end
   -- Only active capture wraps the original callback. Preserve nil results
   -- without building a per-frame return table, and count after it succeeds.
   if wrapper==owned and capture then
    if capture.active()then return rendered(capture_frame,hidden,pcall(saved,...))end
    return rendered(capture_frame,hidden,true,saved(...))
   end
   return saved(...)
  end
  wrapper=owned
  rawset(_G,'render',wrapper)
  last_time=sr.Application.time_since_launch()
  return true
 end
 function self.open()
  local called,ok,why=pcall(open)
  if not called then notice(ok);self.close();return false,ok end
  return ok,why
 end
 function self.tick()
  if disposed then return end
  if capture then capture_frame=capture_frame+1 end
  input.frame()
  capture_tick()
  local recovery_key=handle.get('recover_input_key')
  local recovery_modifiers=input.down(17)and input.down(16)
  local recovery=recovery_modifiers and edge(recovery_key)
  if not recovery_modifiers then edges[recovery_key]=false end
  if recovery then self.close(true);return end
  if pending_cleanup then
   if simulation then
    local ok,why=simulation.tick();if not ok then notice(why);self.close(true);return end
   end
   if bloom and bloom.waiting()then tick_bloom()end
   self.close(nil,true);return
  end
  local slow_edge=edge(handle.get('slowmo_key'))
  if menu.bound_key and not input.down(menu.bound_key)then menu.bound_key=nil end
  if slow_edge and not(menu.editing_key()or menu.editing_text()or menu.bound_key)then self.toggle_slowmo()end
  if edge(handle.get('toggle_key'))then
   if self.mode=='shot'and self.active then self.reposition_shot()
   elseif self.active then self.close()else self.open()end
  end
  if simulation then
   local ok,why=simulation.tick();if not ok then notice(why);self.close(true);return end
   if simulation_revision~=simulation.revision then
    simulation_revision=simulation.revision
    if self.active and self.mode~='shot'and not simulation.frozen and handle.get('freeze_player')then
     freeze_sync=true;local called,accepted=pcall(handle.set,'freeze_player',false);freeze_sync=false
     if not called or accepted==false then notice('Freeze setting synchronization failed')end
    end
    if simulation.reason then if shot then shot.refreeze=false end;notice(simulation.reason)end
   end
  end
  if not self.active then return end
  local now=sr.Application.time_since_launch();local dt=math.max(0,math.min(.1,now-(last_time or now)));last_time=now
  tick_bloom(now)
  if self.mode=='shot'then
   if not input.focused()then self.close(true);return end
   -- No session notification is available here. One O(1) identity check each
   -- second during a shot; no world-unit scan or pointer snapshot.
   if now<shot.check_at or now-shot.check_at>=1 then
    shot.check_at=now;local ok,why=check_shot()
    if not ok then notice(why);self.close(true);return end
   end
  elseif not input.owns()then self.close(true);return end
  local sample
  if self.mode~='shot'then
   local why;sample,why=input.sample();if not sample then notice(why);self.close();return end
  end
  if self.mode~='shot'and edge(handle.get('focus_key'))then self.focus();return end
  if edge(27)then if not menu.dismiss()then self.close()end;return end
  if capture and edge(handle.get('screenshot_key'))and not(menu.editing_key()or menu.editing_text()or menu.bound_key)then self.screenshot()end
  if self.mode~='shot'and not(capture and capture.active())and edge(handle.get('hide_controls_key'))then hide()end
  if self.mode~='shot'and edge(handle.get('lock_camera_key'))then handle.set('lock_camera',not handle.get('lock_camera'))end
  local o=read_options()
  if self.mode=='menu'and not(capture and capture.active())then
   if not menu.scene_tick(sample,input.down)then menu.tick(sample,input.down)end
  elseif self.mode=='camera'and not o.lock_camera and not(path and path.playing)then
   sample_sequence=sample_sequence+1
   local f,r=deps.look.basis(photo,initial.forward,{mouse_x=sample.dx,mouse_y=sample.dy,dt=dt,
    sequence=sample_sequence,sensitivity=handle.get('look_sensitivity'),smoothing=o.camera_smoothing,
    smoothing_time=math.max(.001,o.smoothing_strength*.003)})
   photo.forward,photo.right=f,r
   local forward=(input.down(handle.get('forward_key'))and 1 or 0)-(input.down(handle.get('back_key'))and 1 or 0)
   local right=(input.down(handle.get('right_key'))and 1 or 0)-(input.down(handle.get('left_key'))and 1 or 0)
   local up=(input.down(handle.get('up_key'))and 1 or 0)-(input.down(handle.get('down_key'))and 1 or 0)
   local direction={f[1]*forward+r[1]*right,f[2]*forward+r[2]*right,f[3]*forward+r[3]*right+up}
   local norm=math.max(1,math.sqrt(direction[1]^2+direction[2]^2+direction[3]^2))
   local step=handle.get('speed')*dt/norm
   if o.camera_smoothing and o.smoothing_strength>0 then
    photo.target=photo.target or copy(photo.pos)
    local alpha=1-math.exp(-dt/math.max(.001,o.smoothing_strength*.003))
    for axis=1,3 do
     photo.target[axis]=photo.target[axis]+direction[axis]*step
     photo.pos[axis]=photo.pos[axis]+(photo.target[axis]-photo.pos[axis])*alpha
    end
   else
    photo.target=nil
    for axis=1,3 do photo.pos[axis]=photo.pos[axis]+direction[axis]*step end
   end
   local roll=(input.down(handle.get('roll_right_key'))and 1 or 0)-(input.down(handle.get('roll_left_key'))and 1 or 0)
   if roll~=0 then photo.roll=math.max(-180,math.min(180,(photo.roll or o.roll)+roll*handle.get('roll_speed')*dt))
   else flush_roll()end
   local wheel=input.wheel()
   if wheel~=0 then handle.set('speed',math.max(.1,math.min(50,handle.get('speed')*(1+handle.get('wheel_step')/100)^(wheel/120))))end
  end
  if path and path.playing then
   path_output.pos=photo.pos
   local ok,why=path.sample(now,path_output)
   if ok then
    local p=path_output;photo.target=nil
    photo.view=photo.view or{};photo.view.yaw,photo.view.pitch=p.yaw,p.pitch
    local cy,sy,cp,sp=math.cos(p.yaw),math.sin(p.yaw),math.cos(p.pitch),math.sin(p.pitch)
    local f,r=photo.forward,photo.right
    f[1],f[2],f[3]=cy*cp,sy*cp,sp;r[1],r[2],r[3]=sy,-cy,0
    photo.path_roll,photo.path_fov=p.roll,p.fov
    if not path.playing then stop_path();sync_path()end
   else stop_path();if why then notice(why)end end
  end
  if lighting then
   local ok,why=lighting.tick(light_frame)
   if not ok then notice(why)end
   sync_light()
   if texts.light_status then texts.light_status.label=lighting.status end
  end
 end
 function self.dispose()
  local ok,why=self.close(true);if not ok then return false,why end
  -- Disable can be retried without on_update between attempts. Keep pending
  -- retirement bounded by the same coordinator, without recancelling a job.
  capture_tick()
  if capture and capture.busy()then return false,'Screenshot cleanup unconfirmed'end
  local retired,reason=close_decorative(true)
  if not retired then pending_cleanup=true;self.state='closing';notice(reason);return false,reason end
  disposed=true;handle.unregister();return true
 end
 return self
end
return M

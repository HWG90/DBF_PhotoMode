-- Modular controller for the Steam build (LuaJIT or Lua 5.1). Native features
-- stay capability gated; never execute old-build addresses.
local M={}
-- True-zero pause and slow motion use the documented engine policy setter.
-- Resume is an explicit 1x policy, not an invented native-state snapshot.
-- Freeze Action is held: a direct foreign Lua multiplier write (focus loss, the
-- game, another mod) is followed by true zero again while we own the freeze.
function M.time_policy(sr,clock,before_nonzero,before_zero)
 local A,G,N=sr.Application,sr.GameSession,sr.Network
 local self={frozen=false,preparing=false,slowmo_active=false,rate=.2,owned=false,revision=0,reason=nil}
 local original,wrapper,world,session,last_check,zero_confirmed
 -- True while we are deliberately resuming or releasing time; a foreign write
 -- then takes control exactly as before instead of being held against.
 local releasing=false;local held_at
 local acquire
 local retry_at,retry_binding,retry_reason,retry_value,retry_dependency
 local function permit_nonzero()
  if not before_nonzero then return true end
  local called,ok,why,revision=pcall(before_nonzero)
  if not called then return false,ok end
  return ok==true,why,revision
 end
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
  zero_confirmed=false
  retry_at,retry_binding,retry_reason,retry_value,retry_dependency=nil,nil,nil,nil,nil
 end
 local function restore(value)
  local now=clock();local binding=A.set_time_step_policy
  local permitted,reason,dependency=true
  if value>0 and binding==wrapper then permitted,reason,dependency=permit_nonzero()end
  if retry_at and now<retry_at and binding==retry_binding and value==retry_value and dependency==retry_dependency then return false,retry_reason end
  local function pending(why)
   retry_at,retry_binding,retry_reason,retry_value,retry_dependency=now+1,binding,why,value,dependency;return false,why
  end
  if binding~=wrapper then return pending('Time-policy binding changed; restoration is pending')end
  if not permitted then return pending(reason or'Subject cleanup is pending')end
  -- Cleanup can synchronously notify another Lua policy owner. Respect that
  -- successor before submitting the nonzero value through our saved binding.
  if not self.owned then return true end
  binding=A.set_time_step_policy
  if binding~=wrapper then return pending('Time-policy binding changed; restoration is pending')end
  zero_confirmed=false
  local called,result=pcall(original,'external_multiplier',value)
  if not called or result==false then return pending('Time restoration failed: '..tostring(result))end
  retry_at,retry_binding,retry_reason,retry_value,retry_dependency=nil,nil,nil,nil,nil;return true
 end
 function self.release()
  local was_preparing=self.preparing
  if self.preparing then local ok,why=permit_nonzero();if not ok then return false,why end;self.preparing=false end
  if self.owned then local ok,why=restore(1);if not ok then self.pending_restore=true;return false,why end end
  local changed=self.owned or self.frozen or self.slowmo_active or was_preparing
  self.owned,self.frozen,self.slowmo_active,self.pending_restore=false,false,false,false
  if changed then self.revision=self.revision+1 end
  detach();return true
 end
 function self.resume()
  if self.preparing then
   local ok,why=permit_nonzero();if not ok then return false,why end
   self.preparing=false;self.reason=nil;self.revision=self.revision+1
  end
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
   local args={...}
   if wrapper==owned then for _,arg in ipairs(args)do if arg=='external_multiplier'then zero_confirmed=false;break end end end
   local result={saved(...)}
   if wrapper==owned and result[1]~=false then
    for _,arg in ipairs(args)do if arg=='external_multiplier'then
     -- Hold only while our wrapper is the live binding. A successor wrapper's
     -- write still takes control, so cleanup can never be starved by a hold.
     -- Only Freeze Action is held; a foreign rate still ends Slow Motion.
     -- At most one reassertion per second: a writer that keeps changing time
     -- takes control as before instead of a per-frame tug-of-war.
     local stamp=clock()
     local hold=self.owned and self.frozen and not self.pending_restore and not releasing and A.set_time_step_policy==owned and
      not(held_at and stamp>=held_at and stamp-held_at<1)
     local called,ok=false,false
     if hold then held_at=stamp;called,ok=pcall(saved,'external_multiplier',0)end
     if called and ok~=false then
      -- A notice, not a reason: reasons mean ownership was lost.
      zero_confirmed=true;self.notice='Freeze Action kept after another time change';self.revision=self.revision+1
     else
      self.owned,self.frozen,self.slowmo_active,self.pending_restore=false,false,false,false
      self.reason='Another time modifier took control';self.revision=self.revision+1
      detach()
     end
     break
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
  zero_confirmed=false
  local ok,result=pcall(original,'external_multiplier',value)
  if not ok or result==false then
   local restored,reason=self.release()
   return false,restored and(label..' failed: '..tostring(result))or reason
  end
  zero_confirmed=value==0;return true
 end
 function self.owns_zero()
  -- Frozen is a cleanup obligation after a partial resume failure, not proof
  -- that native time is still zero. Pose writes require our last zero receipt.
  return self.owned and self.frozen and not self.pending_restore and zero_confirmed==true and
   wrapper~=nil and A.set_time_step_policy==wrapper
 end
 function self.freeze()
  if self.frozen then return true end
  if before_zero then
   local called,allowed,reason,pending=pcall(before_zero)
   if called and allowed~=true and pending==true then
    if not self.preparing then self.preparing=true;self.revision=self.revision+1 end
    self.reason=reason or'Preparing hover pause';return true,self.reason
   end
   if not called or allowed~=true then return false,called and(reason or'Pause safety check refused')or tostring(allowed)end
   if self.preparing then self.preparing=false;self.reason=nil;self.revision=self.revision+1 end
  end
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
   local permitted,why=permit_nonzero();if not permitted then return false,why end
   local ok,why=acquire();if not ok then return false,why end
   ok,why=write(enabled and rate or 1,'Slow motion');if not ok then return false,why end
  end
  self.slowmo_active,self.rate=enabled,rate;self.revision=self.revision+1
  if not self.frozen and not enabled then self.owned=false;detach()end
  return true
 end
 do
  local release,resume=self.release,self.resume
  function self.release()releasing=true;local ok,why=release();releasing=false;return ok,why end
  function self.resume()releasing=true;local ok,why=resume();releasing=false;return ok,why end
 end
 function self.tick()
  if self.preparing then local ok,why=self.freeze();if not ok then return false,why end end
  if self.pending_restore then return self.release()end
  if not self.owned then return true end
  local now=clock()
  if now>=last_check and now-last_check<1 then return true end
  last_check=now
  -- No join notification exists in this API. At most one small peer read per
  -- wall second while modifying time; unmodified state performs zero reads.
  local ok,current=pcall(solo)
  if not ok or current~=session or A.main_world()~=world then
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
local render_observers=setmetatable({},{__mode='k'})
local function observer_contains(current,wanted)
 local seen={}
 while current do
  if current==wanted then return true end
  if seen[current]then return false end;seen[current]=true
  local node=render_observers[current];if not node then return false end
  current=node.prior
 end
 return false
end
local function observer_trim(current)
 local node=render_observers[current]
 while node and not node.active do current=node.prior;node=render_observers[current]end
 return current
end
function M.render_flag_policy(sr,setting,label)
 assert(setting=='bloom_enabled'or setting=='dof_enabled','Unsupported renderer flag')
 label=label or setting
 local A=sr and sr.Application
 if type(A)~='table'or type(A.render_setting)~='function'or type(A.set_render_setting)~='function'or
  type(A.time_since_launch)~='function'then return nil end
 local self={state='closed',revision=0,reason=nil,failures={}}
 local getter,prior,wrapper,baseline,observed,owned,desired,inflight
 local active,closing,written,restore_attempted,foreign,foreign_unknown=false,false,false,false,false,false
 local next_poll,deadline,last_clock,held_at
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
   if not result[1]then failure('clock',result,label..' clock failed; cleanup is pending');return nil end
   value=result[2]
  end
  if not finite(value)or last_clock and value<last_clock then
   failure('clock',{n=1,value},label..' clock changed; cleanup is pending');return nil
  end
  last_clock=value;return value
 end
 local function read()
  local result=pack(pcall(getter,setting))
  if not result[1]or result.n~=2 or type(result[2])~='boolean'then
   failure('getter',result,label..' getter failed or changed type; cleanup is pending');return nil
  end
  return result[2]
 end
 local function detach(final_state,message)
  if wrapper and A.set_render_setting==wrapper then
   local result=pack(pcall(function()A.set_render_setting=observer_trim(prior) end))
   if not result[1]or A.set_render_setting==wrapper then
    return failure('observer_restore',result,label..' observer restoration is pending')
   end
  end
  if wrapper and render_observers[wrapper]then render_observers[wrapper].active=false end
  wrapper=nil;prior=nil;inflight=nil;active=false;written=false;closing=false
  state(final_state,message);return true
 end
 local function check_foreign()
  if wrapper and(foreign or not observer_contains(A.set_render_setting,wrapper))then
   return detach(closing and'closed'or'foreign',label..' handed to another Lua writer; its value is preserved')
  end
 end
 local function submit(value,kind,time)
  local stamp=now(time);if not stamp then return false,self.reason end
  -- Mark attempted ownership before calling: false/throw may partially apply.
  written=true;inflight={value=value,kind=kind};next_poll,deadline=stamp+.1,stamp+2
  -- An apply back to the baseline is already the single baseline submission.
  -- A failed attempt must not authorize a duplicate cleanup setter.
  restore_attempted=kind=='restore'or value==baseline
  local result=pack(pcall(prior,setting,value and'true'or'false'))
  if not result[1]or result[2]==false then
   return failure(kind,result,label..' '..kind..' failed; partial application is unknown')
  end
  state('awaiting',kind=='restore'and'Restoring original '..label or'Applying selected '..label);return true
 end
 local cleanup
 cleanup=function(value,time)
  if not written then return detach('closed',label..' released without changing the native setting')end
  if foreign_unknown then return false,'Failed foreign '..label..' submission; native ownership remains unknown'end
  if value==baseline then
   -- An unacknowledged opposite submission can still be queued behind this
   -- old baseline. A submitted baseline itself cannot later undo cleanup.
   if inflight and inflight.value~=baseline and observed~=inflight.value then
    return failure('unacknowledged',{n=1,value},label..' submission remains unacknowledged; cleanup is unknown')
   end
   return detach('closed','Original '..label..' value restored')
  end
  if value~=owned and(not inflight or value~=inflight.value)then
   return detach('foreign',label..' changed outside Photo Mode; its value is preserved')
  end
  if restore_attempted then return failure('unacknowledged_restore',{n=1,value},label..' restore remains unacknowledged; no repeated setter')end
  local ok,why=submit(baseline,'restore',time)
  return false,ok and'Awaiting original '..label..' acknowledgement'or why
 end
 function self.open(value)
  if self.state~='closed'then return false,'Previous '..label..' ownership is not retired'end
  if type(value)~='boolean'then return false,label..' selection must be boolean'end
  getter=A.render_setting
  baseline=read();if baseline==nil then return false,self.reason end
  observed,owned,desired=baseline,baseline,value
  active,closing,written,restore_attempted,foreign,foreign_unknown=true,false,false,false,false,false
  inflight,next_poll,deadline,last_clock,held_at=nil,nil,nil,nil,nil;self.failures={}
  prior=A.set_render_setting
  if type(prior)~='function'then active=false;state('blocked',label..' setter unavailable');return false,self.reason end
  local saved=prior
  local owned_wrapper
  owned_wrapper=function(...)
   if wrapper~=owned_wrapper or not active and not written or(...)~=setting then return observer_trim(saved)(...)end
   local result=pack(pcall(observer_trim(saved),...))
   if not result[1]or result[2]==false then
    if written then foreign_unknown=true;failure('foreign',result,'Failed foreign '..label..' write; ownership remains unknown')
    else foreign=true end
   else
    -- Hold the selection: the foreign value becomes what close restores, and
    -- the selected value is submitted again once, through the wrapped setter.
    local value=select(2,...);local read_clock,stamp=pcall(A.time_since_launch);if not read_clock then stamp=nil end
    if active and not closing and(type(value)=='boolean'or value=='true'or value=='false')and
     not(held_at and stamp and stamp>=held_at and stamp-held_at<1)then
     held_at=stamp
     baseline=value==true or value=='true';observed,owned,inflight=baseline,baseline,nil
     if desired~=baseline then submit(desired,'apply')else state('active',label..' matches the selected value')end
    else foreign=true end
   end
   if not result[1]then error(result[2],0)end
   return unpack(result,2,result.n)
  end
  wrapper=owned_wrapper
  render_observers[wrapper]={prior=prior,active=true}
  local installed=pack(pcall(function()A.set_render_setting=wrapper end))
  if not installed[1]or A.set_render_setting~=wrapper then
   active=false;return failure('observer_install',installed,label..' observer unavailable')
  end
  state('active',label..' matches the selected value')
  if value~=baseline then return submit(value,'apply')end
  return true
 end
 function self.request(value)
  if type(value)~='boolean'then return false,label..' selection must be boolean'end
  if check_foreign()~=nil then return false,self.reason end
  if not active or closing or self.state=='blocked'then return false,self.reason or label..' is not active'end
  if desired==value then return true end
  desired=value;self.revision=self.revision+1
  if inflight then return true end -- Coalesce without another native submission.
  local current=read();if current==nil then return false,self.reason end
  -- A native-side change is adopted as the value to restore on close.
  if current~=observed then baseline,observed,owned=current,current,current end
  if current==value then return true end
  return submit(value,'apply')
 end
 function self.tick(time)
  if check_foreign()~=nil then return self.state~='blocked',self.reason end
  if self.state~='awaiting'then return self.state~='blocked',self.reason end
  local stamp=now(time);if not stamp then return false,self.reason end
  if stamp>deadline then return failure('timeout',{n=1,inflight.value},label..' acknowledgement timed out; cleanup is unknown')end
  if stamp<next_poll then return true end
  next_poll=stamp+.1
  local current=read();if current==nil then return false,self.reason end
  if current==inflight.value then
   observed,owned=current,current;inflight=nil;next_poll,deadline=nil,nil
   if closing then return cleanup(current,stamp)end
   state('active','Selected '..label..' value acknowledged')
   if desired~=current then return submit(desired,'apply',stamp)end
  elseif stamp>=deadline then return failure('timeout',{n=1,current},label..' acknowledgement timed out; cleanup is unknown')end
  return true
 end
 function self.close(explicit)
  closing=true;active=false
  -- A refused initial read created no native write to restore.
  if not written and not inflight and not foreign_unknown then return detach('closed',label..' released without native changes')end
  if check_foreign()~=nil then return self.state~='blocked',self.reason end
  if self.state=='closed'then return true end
  if self.state=='foreign'then return detach('closed','Foreign '..label..' value preserved')end
  if self.state=='awaiting'then return false,'Awaiting bounded '..label..' acknowledgement'end
  if self.state=='blocked'and explicit~=true then return false,self.reason end
  if not written then return detach('closed',label..' released without native changes')end
  if foreign_unknown then return false,'Failed foreign '..label..' submission; native ownership remains unknown'end
  local stamp=now();if not stamp then return false,self.reason end
  if next_poll and stamp<next_poll then return false,'Awaiting '..label..' cleanup read interval'end
  next_poll=stamp+.1
  local current=read();if current==nil then return false,self.reason end
  return cleanup(current,stamp)
 end
 function self.waiting()return self.state=='awaiting'end
 function self.status()
  if self.state=='active'then return label..': '..(observed and'ON'or'OFF')..' (native).'end
  return label..': '..tostring(self.reason or self.state)..'.'
 end
 return self
end
function M.bloom_policy(sr)return M.render_flag_policy(sr,'bloom_enabled','Bloom')end

local function copy(v)return{v[1],v[2],v[3]}end
function M.new(host,sr,deps,service)
 local self={active=false,state='closed',mode='menu',reason=nil}
 local bookmark=deps.bookmark and deps.bookmark.new()
 local subject_backend,visibility,handycam,ragdoll,hover,hover_fault,deferred_shot
 local backend_error
 local function ensure_subject_backend()
  if not subject_backend and deps.subject_backend and deps.subject_visibility then
   local ok,value=pcall(deps.subject_backend.new,sr)
   if ok then
    subject_backend=value;visibility=deps.subject_visibility.new(value,host.log)
    handycam=deps.handycam and deps.handycam.new()
    backend_error=nil
   elseif backend_error~=tostring(value)then
    backend_error=tostring(value);host.log('Subject backend unavailable: '..backend_error)
   end
  end
  if not ragdoll and deps.ragdoll and subject_backend then
   local ok,value=pcall(deps.ragdoll.native,sr,subject_backend)
   if ok then ragdoll=deps.ragdoll.new(value,host.log)
   elseif backend_error~=tostring(value)then
    backend_error=tostring(value);host.log('Ragdoll hold unavailable: '..backend_error)
   end
  end
  return subject_backend~=nil
 end
 ensure_subject_backend()
 local scene,scene_enabled,autofocus_write
 -- Scene/DoF readiness is retried only at known events (open, first frame,
 -- DoF acknowledgement, option change) plus a short bounded backoff.
 local scene_retry_at,scene_retries,ensure_scene=nil,0
 local native_lens,native_lens_fault
 local camera=deps.camera.new(sr);local input=deps.input.new(sr,service,deps.input_cleanup,deps.input_policy)
 local hud,hud_reason
 if deps.hud then local ok,value=pcall(deps.hud.new,sr,host.log);if ok then hud=value else host.log('HUD backend unavailable: '..tostring(value))end end
 function self.hover_status()return hover and hover.status()or{available=false,reason=hover_fault}end
 function self.input_status()return input.status and input.status()or{keyboard_isolated=false}end
 function self.hud_status()return hud and hud.status()or{available=false}end
 local subject_before_time
 local simulation=sr.Network and sr.GameSession and M.time_policy(sr,os.time,
  (type(deps.load_subject)=='function'or ragdoll or deps.load_hover)and function()return subject_before_time()end or nil,
  (deps.load_hover or deps.subject_backend and deps.subject_backend.pause_gate)and function()
   if hover then return hover.prepare()end
   if not subject_backend or type(subject_backend.can_freeze)~='function'then return false,'Local player pause check unavailable'end
   return subject_backend.can_freeze()
  end or nil)
 local bloom=M.bloom_policy(sr);local bloom_revision
 local dof=M.render_flag_policy(sr,'dof_enabled','Depth of field');local dof_revision
 -- The loader owns transport and the external worker. No capture service means
 -- the existing controls stay gated, with no new closed/idle work.
 local capture_backend=deps.capture_backend
 local capture=deps.capture and capture_backend and deps.capture.new(capture_backend,sr.Application.time_since_launch)
 local capture_frame,capture_completed_frame,capture_sequence=0,0,0
 local capture_world,capture_generation,capture_scene
 local capture_context={}
 local lighting=deps.lighting and deps.lighting.new(sr,deps.lights,host.log,deps.subject_backend and function()assert(subject_backend,'Local player backend unavailable');return subject_backend.frame()end or nil)
 local presets=deps.light_presets and deps.light_presets.new(host.config_dir..'/lighting-presets.ini')
 -- Per-value commit lines would log every slider step; keep other messages.
 local function core_log(message)
  if type(message)=='string'and(message:find('^Setting committed: ')or message:find('^Settings batch committed: '))then return end
  return host.log(message)
 end
 local core=deps.core.new(deps.store.new(host.config_dir),core_log)
 local view=deps.view.new(sr,nil,host.log);local overlay=deps.view.new(sr,true,host.log)
 if deps.font then
 local fonts=deps.font.new();view.set_font_source(fonts);overlay.set_font_source(fonts)
 end
 local handle,menu,prior,wrapper,photo,initial,options,options_revision,initial_player
 local light_sync=false;local light_revision
 local light_frame
 local refresh_setups
 local sample_sequence=0;local edges={};local hosted;local controls={};local texts={};local last_time
 local overlay_commands,overlay_revision,overlay_width,overlay_height,overlay_capture
 local grain_view,grain_commands,grain_phase,grain_width,grain_height,grain_amount,grain_size,grain_frame
 local lens_fov,lens_gameplay,lens_text
 local pending_cleanup=false;local full_cleanup=false;local disposed=false;local base_cleanup_done=false;local full_time_released=false;local time_cleanup_done=false
 local close_persisted=false;local close_persist_reason
 local input_cleanup_blocked,input_cleanup_reason
 local freeze_sync=false;local simulation_revision
 local subject,subject_opt_in,subject_status,subject_choices,subject_pose_ids
 local subject_pending,subject_holds,subject_cleanup_attempted,subject_close_started=false,false,false,false
 local subject_fault,subject_message
 local subject_revision=0;local sync_subject
 -- Double-click scene picking: one-shot, never a per-frame unit scan.
 local pick=deps.pick and deps.pick.new(sr);local pick_click,pick_held,picked_label
 local shot
 local first_render=false
 local function checkpoint(stage)
  host.log('Photo checkpoint: '..stage)
 end
 local path=deps.path and deps.path.new();local path_output={};local path_sync=false
 local sync_path
 local decorative,decorative_active,decorative_finalizing,decorative_fault
 local decorative_status
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
 local function sync_dof()
  if not dof or dof_revision==dof.revision then return end
  dof_revision=dof.revision
  if texts.focus_status then texts.focus_status.label=dof.status()end
  -- The native flag is what creates the depth target the scene shader reads.
  if dof.state=='active'and self.active and not scene_enabled and ensure_scene then ensure_scene(true)end
 end
 local function tick_bloom(time)
  if bloom then local ok,why=bloom.tick(time);sync_bloom();if not ok and why then notice(why)end end
  if dof then local ok,why=dof.tick(time);sync_dof();if not ok and why then notice(why)end end
 end
 -- Subject state is published only after explicit actions or known lifecycle
 -- transitions. There is no subject tick, discovery scan or status poll.
 sync_subject=function()
  if subject then
   local called,value=pcall(subject.status)
   if called and type(value)=='table'then subject_status=value
   else subject_fault='Subject status is unavailable'end
  end
  local s=subject_status
  subject_pending=subject_fault~=nil or s and s.pending==true or false
  subject_holds=subject_pending or s and s.state=='posed'or false
  if not subject_holds then subject_cleanup_attempted=false end
  subject_message=subject_fault or s and s.message or(type(deps.load_subject)=='function'and'Refresh to list up to four subjects'or'Selected-subject backend unavailable')
  subject_revision=subject_revision+1
  if not controls.subject_refresh then return end
  local enabled=subject_opt_in and self.active and not pending_cleanup and self.mode~='shot'and s and s.available==true
  controls.subject_refresh.disabled=not self.active or pending_cleanup or self.mode=='shot'or subject_holds
  for i=1,4 do
   local c=controls['subject_select_'..i];local choice=subject_choices and subject_choices[i]
   c.label=choice and choice.label or'No subject refreshed'
   c.button_label=choice and s and s.selected==choice.id and'Selected'or'Select'
   c.disabled=not enabled or subject_holds or not choice
  end
  controls.subject_pose.disabled=not enabled or subject_pending
  controls.subject_pose_play.disabled=not enabled or subject_pending or not(s and s.selected)or not(simulation and simulation.owns_zero())
  controls.subject_pose_stop.disabled=not enabled or not subject_holds
  controls.subject_recover.disabled=not subject_pending
  if texts.subject_pose_status then texts.subject_pose_status.label=(picked_label and picked_label..'  |  'or'')..subject_message end
 end
 local function subject_call(method,value)
  local called,ok,why=pcall(subject[method],value)
  if not called then subject_fault='Subject '..method..' failed';why=ok;ok=false
  elseif ok==true then subject_fault=nil end
  local listed,choices=pcall(subject.choices)
  if listed and type(choices)=='table'and #choices<=4 then subject_choices=choices
  else subject_fault='Subject choices are unavailable'end
  sync_subject()
  if ok~=true then notice(why or subject_message)end
  return ok==true,why or subject_message
 end
 subject_before_time=function()
  if ragdoll then local ok,why=ragdoll.release();if not ok then return false,why end end
  if not subject_holds then
   if hover then local ok,why=hover.release();if not ok then return false,why end end
   return true,nil,subject_revision
  end
  if subject_cleanup_attempted then return false,subject_message,subject_revision end
  subject_cleanup_attempted=true
  local ok,why=subject_call('resume')
  if ok and hover then ok,why=hover.release()end
  return ok,why,subject_revision
 end
 local function close_subject(explicit_retry)
  if ragdoll then local ok,why=ragdoll.release();if not ok then return false,why end end
  if not subject then return true end
  if explicit_retry and subject_pending then
   local ok,why=subject_call('recover');if not ok then return false,why end
   subject_close_started=false
  end
  if not subject_close_started then
   subject_close_started=true;subject_cleanup_attempted=true
   return subject_call('close')
  end
  return not subject_holds,subject_message
 end
 local function subject_action(method,value)
  if not subject then return false,'Refresh subjects first'end
  if method~='recover'and(not subject_opt_in or not self.active or pending_cleanup or self.mode=='shot')then
   return false,'Subject controls are unavailable'
  end
  if method=='apply'then
   if ragdoll then local ok,why=ragdoll.release();if not ok then return false,why end end
   subject_cleanup_attempted=false;subject_close_started=false
  end
  local ok,why=subject_call(method,value)
  if method=='recover'and ok and not subject_opt_in then close_subject(false)end
  if method=='recover'and ok and pending_cleanup then self.close(nil,true)end
  return ok,why
 end
 local function load_subject()
  if subject_opt_in then return true end
  if not self.active or pending_cleanup or subject_pending or type(deps.load_subject)~='function'then return false,'Subject controls are unavailable'end
  if not subject then
   local called,value=pcall(deps.load_subject,sr,function()return simulation and simulation.owns_zero()or false end,subject_backend)
   if not called or type(value)~='table'then notice(called and'Subject pose factory unavailable'or value);return false,'Subject pose factory unavailable'end
   for _,name in ipairs({'status','choices','refresh','select','apply','reset','recover','close','resume','invalidate'})do
    if type(value[name])~='function'then notice('Subject controller is incomplete');return false,'Subject controller is incomplete'end
   end
   local labels,ids={},{}
   if type(value.catalog)~='table'or #value.catalog==0 or #value.catalog>213 then return false,'Subject catalog is unavailable'end
   for i,item in ipairs(value.catalog)do
    if type(item)~='table'or type(item.id)~='string'or type(item.label)~='string'or #item.label>512 or item.label:find('%c')then return false,'Subject catalog is invalid'end
    ids[i],labels[i]=item.id,item.label
   end
   subject=value;subject_pose_ids=ids;subject_choices={}
   controls.subject_pose.choices=labels;controls.subject_pose.choices_revision=value.catalog
  end
  subject_opt_in=true;subject_close_started=false;subject_cleanup_attempted=false;sync_subject()
  return true
 end
 -- A picked character becomes the focus and lighting subject; a Helldiver is
 -- also selected for poses. The unit handle is used only within this frame.
 local function pick_subject(x,y,o)
  local width,height=sr.Gui.resolution()
  local f,r=photo.forward,photo.right
  local up=deps.lens.up(f,r,photo.path_roll or photo.roll or o.roll)
  local fov=photo.path_fov or(o.fov>0 and math.rad(o.fov)or initial.fov)
  local hit,why=pick.pick({pos=photo.pos,forward=f,up=up,fov=fov},x,y,width,height,math.max(24,height*.04))
  if not hit then notice(why);return false end
  local distance=math.max(.1,math.min(200,math.floor(hit.distance*1000+.5)/1000))
  if controls.focus_distance and not controls.focus_distance.disabled then
   autofocus_write=true;handle.set('focus_distance',distance);autofocus_write=false
  end
  if controls.light_subject_distance and not controls.light_subject_distance.disabled then handle.set('light_subject_distance',distance)end
  local message=hit.label..string.format(' selected (%.1f m)',hit.distance)
  if hit.helldiver and subject and type(subject.select_unit)=='function'then
   if subject_holds then message=message..'; reset the held pose to pose it'
   elseif subject_action('refresh')then
    local ok,reason=subject_call('select_unit',hit.unit);if not ok then message=message..'; '..tostring(reason)end
   end
  elseif not hit.helldiver then message=message..' for focus and lighting; poses need a Helldiver'end
  picked_label=message;sync_subject();notice(message)
  return true
 end
 -- On open, list the current subjects and select the one nearest the camera.
 local function auto_subject(point)
  if not subject or subject_holds or subject_pending or type(subject.select_nearest)~='function'then return end
  if subject_action('refresh')then subject_call('select_nearest',point)end
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
 -- A binding id reads the loader's bindings helper when it hosts that key, else the virtual
 -- key in our settings; a number is a raw virtual key (ESC, modifiers, other menus' keys).
 local function held(key)
  if type(key)=='string'then
   if hosted and hosted.hosted(key)then return hosted.down(key)end
   key=handle.get(key)
  end
  return input.down(key)
 end
 local function edge(key)
  local down=held(key);local value=down and not edges[key];edges[key]=down;return value
 end
 -- Other menus (LLL manager, MCM) open over Photo Mode. Their keys are read at
 -- open; pressing one yields our captured input while camera, freeze and UI
 -- state stay held, and our lease is retaken once that menu has closed.
 local handoff,handoff_keys
 local function menu_key(value)return type(value)=='number'and value%1==0 and value>=7 and value<=255 and value~=27 end
 local function read_handoff_keys()
  local keys={};local own={}
  for _,id in ipairs({'toggle_key','focus_key','hide_controls_key','lock_camera_key','screenshot_key','slowmo_key'})do own[handle.get(id)]=true end
  local loader=rawget(_G,'LiveLuaLoader')
  if type(loader)=='table'and type(loader.open_manager)=='function'then
   local key=45
   if type(loader.get_loader_option)=='function'then
    local ok,values=pcall(loader.get_loader_option,'manager_ui')
    if ok and type(values)=='table'and menu_key(values.menu_toggle_key)then key=values.menu_toggle_key end
   end
   keys[#keys+1]={label='Live Lua Loader',key=key,is_open=function()return false end,
    open=function()local ok,why=pcall(loader.open_manager);return ok,not ok and tostring(why)or nil end}
  end
  local mcm=rawget(_G,'DBFMCM')
  if type(mcm)=='table'and type(mcm.open)=='function'and type(mcm.is_open)=='function'then
   local key=46
   if type(mcm.menu_binding_status)=='function'then
    local ok,status=pcall(mcm.menu_binding_status)
    if ok and type(status)=='table'and menu_key(status.global_key)then key=status.global_key end
   end
   keys[#keys+1]={label='Mod Configuration Menu',key=key,is_open=function()local ok,value=pcall(mcm.is_open);return ok and value==true end,
    open=function()local ok,done,why=pcall(mcm.open);if not ok then return false,tostring(done)end;return done~=false,why end}
  end
  local usable={};for _,entry in ipairs(keys)do if not own[entry.key]then usable[#usable+1]=entry end end
  return usable
 end
 local generic_yields,generic_yield_at=0,nil
 local function yield_input(entry,now)
  if not entry then
   -- Repeated unexplained input loss (lease taken back, failed samples) ends
   -- in the ordinary full close rather than a held scene with no input.
   if generic_yield_at and now-generic_yield_at<2 then generic_yields=generic_yields+1 else generic_yields=1 end
   generic_yield_at=now
   if generic_yields>5 then notice('Photo input keeps failing; Photo Mode closed');self.close(true);return false end
  end
  local ok,why=input.release()
  -- A refused release still enters the bounded 4 Hz retake path; set_mode
  -- retries the release itself, so this never repeats every frame.
  if not ok then notice(why);entry=nil end
  menu.suspend();sample_sequence=sample_sequence+1
  handoff={entry=entry,phase=entry and'wait'or'open',started=now,up=0,next_try=now+.25}
  return true
 end
 -- Per-session state reset at every open (kept out of open: upvalue limit).
 local function begin_session()
  handoff,handoff_keys=nil,read_handoff_keys()
  decorative_fault,generic_yields,generic_yield_at=nil,0,nil
 end
 local function handoff_tick(now)
  local h=handoff
  if h.phase=='wait'then
   if h.entry.is_open()then h.phase,h.next_try='open',now+.25;return end
   -- Our capture consumed the key press, so open explicitly once it is up.
   if input.down(h.entry.key)then h.up=0 else h.up=h.up+1 end
   if h.up>=2 then
    local ok,why=h.entry.open();h.phase,h.next_try='open',now+.25
    if not ok then notice(why or(h.entry.label..' did not open'))end
   elseif now-h.started>3 then h.phase='open'end
   return
  end
  if now<h.next_try then return end
  h.next_try=now+.25
  if h.entry and h.entry.is_open()then return end
  -- Nobody else holds input yet ours is still refused: stop after 5 s.
  if not h.entry and now-h.started>5 then
   local called,status=pcall(service.status)
   if not called or type(status)~='table'or status.owner==nil then notice('Photo input could not be retaken; Photo Mode closed');self.close(true);return end
  end
  -- Acquisition is refused while the loader manager or MCM owns input.
  local ok=input.set_mode(self.mode=='camera'and'camera'or'menu')
  if not ok then return end
  for key in pairs(edges)do edges[key]=held(key)end
  handoff=nil;sample_sequence=sample_sequence+1;menu.suspend()
 end
 local function bookmark_context()
  if subject_backend then
   local ok,frame=pcall(subject_backend.frame)
   if not ok then return nil end
   return{world=frame.world,unit=frame.identity,position=frame.position}
  end
  return camera.bookmark_context()
 end
 local function bookmark_status()
  if bookmark and texts.saved_camera_status then texts.saved_camera_status.label=bookmark.status()end
 end
 local function save_camera()
  if not bookmark or not self.active or pending_cleanup then return false,'Start Photo Mode first'end
  if not stop_path()or not flush_roll()then return false,self.reason end
  local ok,why=bookmark.save(bookmark_context(),photo,
   {roll=handle.get('roll'),fov=handle.get('fov')},handle.get('saved_camera_radius'))
  bookmark_status();if not ok then notice(why)end;return ok,why
 end
 local function read_options()
  if options_revision~=core.revision then options=deps.options.read(handle);options_revision=core.revision end
  return options
 end
 local director_photo={}
 local director
 local function player_frame()
  if deps.player_frame then return deps.player_frame()end
  if subject_backend then return subject_backend.frame()end
  return nil,'Local player unavailable'
 end
 if deps.director then director=deps.director.new(director_photo,player_frame,host.config_dir..'/director-shots.ini',host.log)end
 local function director_status()
  if not director then return end
  if controls.director_slot then controls.director_slot.choices=director.list()end
  if texts.director_status then texts.director_status.label=director.status end
 end
 local function director_action(action)
  if not director or not photo or not self.active or pending_cleanup or self.mode=='shot'then return false,'Place the Photo camera first'end
  if not stop_path()or not flush_roll()then return false,self.reason end
  director_photo.active=true;director_photo.pos=copy(photo.pos)
  director_photo.view={yaw=math.atan2(photo.forward[2],photo.forward[1]),pitch=math.asin(math.max(-1,math.min(1,photo.forward[3])))}
  director_photo.options={fov=handle.get('fov'),roll=handle.get('roll')};director_photo.input={sequence=sample_sequence}
  local ok,why=director[action](handle.get('director_slot'),handle)
  if ok and action=='recall'then
   photo.pos=copy(director_photo.pos);photo.view=director_photo.view;photo.target=nil
   local yaw,pitch=photo.view.yaw,photo.view.pitch;local c=math.cos(pitch)
   photo.forward={math.cos(yaw)*c,math.sin(yaw)*c,math.sin(pitch)}
   photo.right={math.sin(yaw),-math.cos(yaw),0}
  end
  director_status();if not ok then notice(why)end;return ok,why
 end
 function self.native_lens_status()return native_lens and native_lens.message or'Native lens inactive',native_lens and native_lens.ready or false end
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
 -- The label names the game's current output color space (render setting).
 local function screenshot_label()
  if not(capture and controls.screenshot)then return end
  local ok,hdr=pcall(sr.Application.render_setting,'hdr_enabled')
  controls.screenshot.button_label=ok and hdr==true and'Take screenshot (HDR)'or'Take screenshot (SDR)'
 end
 function self.screenshot()
  if not capture then return false,'Screenshot unavailable'end
  screenshot_label()
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
 function self.close(clear_time,automatic,subject_retry)
  deferred_shot=nil
  if handycam then handycam.reset()end
  if photo then photo.handy_roll=nil end
  if capture then capture.close('Photo Mode closed')end
  if not pending_cleanup then close_persisted=false;close_persist_reason=nil;base_cleanup_done=false;full_time_released=false;time_cleanup_done=false
   input_cleanup_blocked,input_cleanup_reason=nil,nil
  end
  full_cleanup=full_cleanup or clear_time==true
  self.state='closing';pending_cleanup=true
  -- A refused release retains the captured lease. Its failed sample cannot
  -- supply recovery keys; only an explicit close/disable may retry cleanup.
  if automatic==true and input_cleanup_blocked then return false,input_cleanup_reason end
  local subject_ok,subject_why=close_subject(subject_retry==true)
  if hover and hover.owned()then
   -- The neutralizing field must survive a real resumed engine update. Keep
   -- keyboard capture until that field is restored, including close retries.
   if not subject_ok then notice(subject_why);return false,subject_why end
   local ok,why
   if full_cleanup then ok,why=simulation.release()else ok,why=simulation.resume()end
   if not ok then notice(why);return false,why end
   ok,why=hover.release();if not ok then notice(why);return false,why end
   ok,why=hover.cleanup();if not ok then notice(why);return false,why end
  end
  if subject_ok and base_cleanup_done and full_cleanup and not full_time_released and simulation then
   local ok,why=simulation.release();if not ok then notice(why);return false,why end
   full_time_released=true;time_cleanup_done=true
  end
  if not base_cleanup_done then
  if simulation and subject_ok then
   local ok,why
   if full_cleanup then ok,why=simulation.release()else ok,why=simulation.resume()end
   if not ok then notice(why);return false,why end
    if full_cleanup then full_time_released=true end
    time_cleanup_done=true
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
  if not called or ok~=true then
   local reason=called and why or ok
   notice(reason or'Gameplay input restoration requires explicit retry')
   input_cleanup_blocked,input_cleanup_reason=true,self.reason
   return false,reason or input_cleanup_reason
  end
  input_cleanup_blocked,input_cleanup_reason=nil,nil
  unhook()
  if menu then
   called,ok,why=pcall(menu.close)
   if not called then notice(ok);return false,ok end
   if ok==false then notice(why);return false,why end
  end
  if scene then local ok,why=scene.release();if not ok then notice(why);return false,why end end
  called,ok,why=pcall(overlay.release)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  called,ok,why=pcall(release_grain)
  if not called then notice(ok);return false,ok end
  if ok==false then notice(why);return false,why end
  local retired,reason=close_decorative(false)
  if not retired then notice(reason);return false,reason end
  base_cleanup_done=true;self.active=false;self.focus_suspended=nil;handoff=nil;pick_click,pick_held,picked_label=nil,nil,nil
  photo,initial,shot=nil,nil,nil
  end
  -- Subject failure never returns before camera/input/UI retirement. Time stays
  -- frozen until its independent owned-state barrier can be explicitly retired.
  if subject_ok and simulation and not time_cleanup_done then
   local ok,why;if full_cleanup then ok,why=simulation.release()else ok,why=simulation.resume()end
   if not ok then notice(why);return false,why end
   time_cleanup_done=true;if full_cleanup then full_time_released=true end
  end
  -- Final disposal can fail after base cleanup has already succeeded. Its
  -- retained ownership must remain a separate barrier on every close retry.
  if decorative_finalizing then
   local retired,reason=close_decorative(true)
   if not retired then notice(reason);return false,reason end
  end
  if hover then local ok,why=hover.dispose();if not ok then notice(why);return false,why end end
  if native_lens then local ok,why=native_lens.release();if not ok then notice(why);return false,why end end
  native_lens_fault=nil;if native_lens then native_lens.reacquires=nil end
  if hud then local ok,why=hud.release();if not ok then notice(why);return false,why end;hud_reason=nil end
  if visibility then
   local ok,why=visibility.release()
   if not ok then notice(why);return false,why end
  end
  if bloom then
   local ok,why=bloom.close(automatic~=true);sync_bloom()
   if not ok then notice(why);return false,why end
  end
  if not subject_ok then notice(subject_why);return false,subject_why end
  if dof then
   local ok,why=dof.close(automatic~=true);sync_dof()
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
  if not ok then notice(why);self.mode=next_mode;yield_input(nil,sr.Application.time_since_launch());return false,why end
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
  {id='recover_input',type='button',label='Recover gameplay input',on_activate=function()return self.close(true,nil,true)end},
  {id='runtime_status',type='text',label='Runtime: '..tostring(rawget(_G,'jit')and jit.version or _VERSION)}}
 if deps.hosted_bindings then
  table.insert(bindings,1,{id='keys_status',type='text',label='Keys are set in '..tostring(deps.hosted_bindings.window or'the loader\'s settings window')..'; they pause while chat is open.'})
 end
 local movement={
  {id='speed',type='slider',label='Movement speed (m/s)',default=3,min=.1,max=50,step=.1},
  {id='wheel_step',type='slider',label='Wheel speed change (%)',default=20,min=5,max=100,step=5},
  {id='look_sensitivity',type='slider',label='Camera look sensitivity',default=.15,min=.01,max=1,step=.01},
  {id='roll_speed',type='slider',label='Roll speed (degrees/s)',default=45,min=1,max=180,step=1},
  {id='freeze_player',type='toggle',label='Freeze Action',default=true,disabled=not simulation,
   on_change=function(value)
    if freeze_sync or not self.active or self.mode=='shot'or not simulation then return end
    local ok,why;if value then ok,why=simulation.freeze()else ok,why=simulation.resume()end
    if not ok then
     notice(why)
     local actual=simulation.frozen==true or simulation.preparing==true
     if value~=actual then freeze_sync=true;pcall(handle.set,'freeze_player',actual);freeze_sync=false end
    end
    sync_subject()
   end},
  {id='slowmo_speed',type='slider',label='Slow motion speed',default=.2,min=.05,max=1,step=.05,fine_step=.01,
   disabled=not simulation,on_change=function(value)
    if simulation then local ok,why=simulation.set_slowmo(simulation.slowmo_active,value);if not ok then notice(why)end end
   end},
  {id='freeze_hint',type='text',label='Solo true-zero pause. Hover Pack controls settle before freezing; Resume restores the selected speed.'}}
 local light_ids={light_add=true,light_selected=true,light_enabled=true,light_kind=true,
  light_intensity=true,light_color=true,light_range=true,light_cone=true,light_right=true,
  light_forward=true,light_up=true,light_follow=true,light_place=true,light_remove=true,light_clear=true,
  light_aim=true,light_preset=true,light_apply_preset=true,light_subject_distance=true,light_follow_player=true,
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
  sync_path(action=='add'and ok~=false and path.count()or nil);if ok==false then notice(why)end;return ok,why
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
 function self.begin_shot(play_path,refreeze_override)
  if not self.active or self.mode=='shot'or pending_cleanup then return false,'Place the Photo camera first'end
  local handheld=handle.get('action_camera_mode')==2
  if handheld and not handycam then return false,'Handycam player backend unavailable'end
  if handheld and play_path then return false,'Choose Placed camera for a recorded path'end
  local head
  if handheld then
   local called,value=pcall(subject_backend.head_frame)
   if not called then notice(value);return false,value end;head=value
   local ready,why=visibility.ready();if not ready then notice(why);return false,why end
  end
  if play_path and(not path or path.count()<2)then notice('Record at least two camera points');return false,self.reason end
  if not stop_path()then return false,self.reason end
  flush_roll()
  local world,generation,session=shot_context()
  if not world or not session then notice('Action shot session unavailable');return false,self.reason end
  local was_frozen=refreeze_override;if was_frozen==nil then was_frozen=simulation and(simulation.frozen or simulation.preparing)or false end
  local ready,issue=subject_before_time();if not ready then notice(issue);return false,issue end
  if simulation then
   local ok,why=simulation.resume();if not ok then notice(why);return false,why end
  end
  if hover and hover.owned()then
   local ok,why=hover.cleanup()
   if not ok then deferred_shot={play_path=play_path,refreeze=was_frozen};notice(why);return true,why end
  end
  local ok,why=input.release()
  if not ok then notice(why);self.close(true);return false,why end
  local now=sr.Application.time_since_launch()
  shot={world=world,generation=generation,session=session,refreeze=was_frozen,started=now,check_at=now}
  shot.handycam=handheld;shot.player_identity=head and head.identity
  if handheld then
   handycam.reset()
   visibility.queue({hide_player=true,hide_armour=true,hide_weapons=true,hide_cape=true})
   local hidden,reason=visibility.flush(0)
   if not hidden then notice(reason);self.close(true);return false,reason end
  end
  self.mode='shot';menu.suspend();photo.target=nil
  sync_subject()
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
  local refreeze=shot.refreeze
  if shot.handycam then handycam.reset();photo.handy_roll=nil;visibility.queue(read_options())end
  shot=nil;self.mode='menu';menu.suspend()
  sample_sequence=sample_sequence+1;last_time=sr.Application.time_since_launch()
  texts.cinema_status.label='Place a camera, then begin an action shot'
  if refreeze and simulation then
   ok,why=simulation.freeze()
   if not ok then notice(why);self.close(true);return false,why end
  elseif simulation and not simulation.frozen and not simulation.preparing and handle.get('freeze_player')then
   -- A foreign time modifier may have revoked our pause during the shot.
   -- Reflect that single transition without reapplying its old preference.
   freeze_sync=true;local called,accepted=pcall(handle.set,'freeze_player',false);freeze_sync=false
   if not called or accepted==false then notice('Freeze setting synchronization failed')end
  end
  sync_subject()
  return true
 end
 local function scene_status(message)if texts.scene_status then texts.scene_status.label=message end end
 local function scene_controls(enabled)
  for _,id in ipairs({'scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range','exposure','contrast','saturation','dof_mode','dof_quality','dof_strength','bokeh_shape','focus_mode'})do
   if controls[id]then controls[id].disabled=not enabled end
  end
 end
 ensure_scene=function(explicit)
  if scene_enabled then return true end
  if not deps.load_scene or not self.active or pending_cleanup then return false end
  if not scene then local ok,value=pcall(deps.load_scene,sr);if not ok then scene_status(tostring(value));return false,value end;scene=value end
  -- Only an explicit event clears the overlay's error latch.
  if explicit and scene.rearm then scene.rearm()end
  local ok,why=scene.ready()
  if not ok then
   -- Bounded backoff (0.25, 0.5, 1, 2 s) covers targets the renderer creates a
   -- few frames after DoF is enabled; afterwards only an explicit event retries.
   if scene_retries<4 then scene_retry_at=sr.Application.time_since_launch()+.25*2^scene_retries;scene_retries=scene_retries+1 end
   scene_status('Scene effects waiting: '..tostring(why));return false,why
  end
  scene_enabled,scene_retry_at=true,nil;scene_controls(true);scene_status('Scene effects ready')
  return true
 end
 -- Return to player moves the Photo camera back to its opening view, offset by
 -- any player movement since then. It never closes, so time stays frozen.
 local function return_to_player()
  if not self.active or pending_cleanup or self.mode=='shot'or not initial then return false,'Open Photo Mode first'end
  if not stop_path()then return false,self.reason end
  local pos=copy(initial.position)
  if initial_player and subject_backend then
   local ok,frame=pcall(subject_backend.frame)
   if ok and type(frame)=='table'and type(frame.position)=='table'then
    for axis=1,3 do pos[axis]=pos[axis]+frame.position[axis]-initial_player[axis]end
   end
  end
  photo.pos,photo.forward,photo.right=pos,copy(initial.forward),copy(initial.right)
  photo.view,photo.target,photo.roll=nil,nil,nil;sample_sequence=sample_sequence+1
  return true
 end
 local pages=deps.options.pages(reset,return_to_player,deps.composition,{camera_controls=movement,without_ai=true,
  director_save=function()return director_action('save')end,
  director_recall=function()return director_action('recall')end,
  director_clear=function()return director_action('clear')end,
  subject_change=function()
   -- Core publishes values before callbacks, and advances revision after them.
   -- Invalidate here so this click queues the committed values, not the last frame.
   options_revision=nil
   if visibility and self.active and not pending_cleanup then visibility.queue(read_options())end
  end,
  save=bookmark and save_camera,clear=bookmark and function()bookmark.clear();bookmark_status();return true end,
  screenshot=capture and self.screenshot or nil,
  path_add=function()return path_action('add')end,path_remove=function()return path_action('remove')end,
  path_clear=function()return path_action('clear')end,path_play=function()return path_action('play')end,
  subject_pose_play=function()return subject_action('apply',subject_pose_ids and subject_pose_ids[handle.get('subject_pose')])end,
  subject_pose_stop=function()
   -- Reset recovers automatically when the plain restoration is refused.
   local ok,why=subject_action('reset')
   if not ok and subject_pending then ok,why=subject_action('recover')end
   return ok,why
  end,
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
 pages[#pages+1]={id='camera' ,name='Controls',require_confirmation=false,controls=bindings}
 if type(deps.load_subject)=='function'then for _,page in ipairs(pages)do if page.id=='subject'then
  local rows={{id='subject_refresh',type='button',label='Refresh subjects (up to four)',on_activate=function()
   local ok,why=load_subject();if not ok then return false,why end;return subject_action('refresh')end}}
  for i=1,4 do local index=i
   rows[#rows+1]={id='subject_select_'..i,type='button',label='No subject refreshed',button_label='Select',
    on_activate=function()local choice=subject_choices and subject_choices[index];return choice and subject_action('select',choice.id)or false end}
  end
  rows[#rows+1]={id='subject_recover',type='button',label='Recover subject pose',on_activate=function()return subject_action('recover')end}
  for i=#rows,1,-1 do table.insert(page.controls,1,rows[i])end
 end end end
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
 local supported={fov=true,focal_preset=true,roll=true,roll_preset=true,lock_camera=true,camera_smoothing=true,smoothing_strength=true,
  frame=true,grid=true,filter=true,filter_strength=true,vignette=true,vignette_width=true,grain=true,grain_size=true,
  logo=true,logo_size=true,logo_color=true,logo_opacity=true,logo_x=true,logo_y=true,
  hide_controls=true,clean_view=true,show_legend=true,legend_open=true,legend_docked=true,legend_tab_y=true,legend_columns=true,
  legend_x=true,legend_y=true,legend_size=true,tab_layout=true,menu_x=true,menu_y=true,menu_scale=true,menu_opacity=true,
  speed=true,wheel_step=true,look_sensitivity=true,roll_speed=true,reset_photo=true,recenter=true,saved_camera_radius=true,
  cinema_begin=true,cinema_reposition=true,cinema_end=true,cinema_notification=true,action_camera_mode=true}
 if deps.decorative_overlay then for _,id in ipairs({'shader','shader_opacity','shader_scale','shader_animate'})do supported[id]=true end end
 if deps.load_native_lens then supported.focus_distance=true;supported.aperture=true end
 if handycam then supported.handycam_intensity=true end
 if visibility then for _,id in ipairs({'hide_player','hide_armour','hide_weapons','hide_cape'})do supported[id]=true end end
 if director then for _,id in ipairs({'director_slot','director_save','director_recall','director_clear'})do supported[id]=true end end
 if bookmark then supported.save_camera=true;supported.clear_saved_camera=true end
 if simulation then supported.freeze_player=true;supported.slowmo_speed=true end
 if type(deps.load_subject)=='function'then for _,id in ipairs({'subject_refresh','subject_select_1','subject_select_2',
  'subject_select_3','subject_select_4','subject_recover','subject_pose','subject_pose_play','subject_pose_stop'})do supported[id]=true end end
 if hud then supported.hide_hud=true end
 if bloom then supported.bloom=true end
 if dof then supported.dof=true end
 if capture then supported.screenshot=true end
 if path then for _,id in ipairs({'path_add','path_remove','path_clear','path_play','path_shot','path_point','path_duration','path_transition'})do supported[id]=true end end
 for _,c in ipairs(bindings)do supported[c.id]=not c.disabled end
 for _,page in ipairs(pages)do for _,c in ipairs(page.controls)do
  if c.type~='text'and c.type~='section'then
   c.disabled=not supported[c.id]
   controls[c.id]=c
  elseif c.id and c.id:match('_status$')then texts[c.id]=c end
 end end
 handle=core.register({id='dbf_freecam',name='War Journalist',pages=pages})
 controls=core.mods.dbf_freecam.controls
 screenshot_label()
 -- Registration copies definitions. Keep live status references on those
 -- registered rows, not on the discarded construction tables.
 texts={}
 for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do
  -- Registration clones definitions. Dynamic lists and callbacks must update
  -- the registered controls consumed by both validation and rendering.
  if c.id then controls[c.id]=c end
  if c.type=='text'and c.id and c.id:match('_status$')then texts[c.id]=c end
 end end
 if deps.hosted_bindings then
  local rows={}
  for _,c in ipairs(bindings)do
   if c.type=='keybind'and controls[c.id]and not controls[c.id].disabled then rows[#rows+1]={id=c.id,label=c.label,default=handle.get(c.id)}end
  end
  hosted=deps.hosted_bindings.factory.new(deps.hosted_bindings.api,rows,deps.input.key_names,host.log)
  for _,row in ipairs(rows)do if hosted.hosted(row.id)then
   local control=controls[row.id];control.disabled=true;control.key_label=function()return hosted.label(row.id)end
  end end
  deps.legend.hosted_label=hosted.label
 end
 if deps.decorative_overlay and controls.shader then
  controls.shader.on_change=function(value)
   decorative_fault=nil -- An explicit choice retries a parked overlay.
   if value>1 and decorative then
    local ok,why=decorative.invalidate();if not ok then notice(why)end
   end
  end
 end
 if controls.subject_refresh then
  controls.subject_pose.on_change=function()sync_subject()end
  for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do if c.id=='subject_pose_hint'then
   c.label='The Helldiver nearest the camera is selected on open. Double-click a character to choose another; poses apply to Helldivers while Freeze Action holds.'
  end end end
 end
 sync_subject()
 director_status()
 shader_status(deps.decorative_overlay and'Choose a decorative overlay'or'Decorative overlay adapter unavailable')
 if bloom then
  controls.bloom.on_change=function(value)
   if not self.active or pending_cleanup then return end
   local ok,why=bloom.request(value);sync_bloom();if not ok and why then notice(why)end
  end
  sync_bloom()
 end
 if dof then
  controls.dof.on_change=function(value)
   if not self.active or pending_cleanup then return end
   local ok,why=dof.request(value);sync_dof();if not ok and why then notice(why)end
  end
  sync_dof()
 end
 controls.action_camera_mode.choices={'Placed camera',handycam and'First-person handycam'or'First-person handycam (player unavailable)'}
 texts.cinema_status.label='Place a camera, then begin an action shot'
 for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do if c.id=='cinema_hint'then
  c.label='Move and fight while the camera holds its shot. Your Photo Mode key returns to placement and restores Freeze Action.'
 end end end
 sync_path=function(preferred)
  if not path then return end
  local choices={};for i=1,path.count()do choices[i]='Point '..i end
  if #choices==0 then choices[1]='No recorded points'end
  controls.path_point.choices=choices
  local index=math.max(1,math.min(path.count(),preferred or handle.get('path_point')))
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
  local ok,why=set_value(id,value)
  if id=='focus_distance'and not autofocus_write and ok~=false and not controls.focus_mode.disabled then set_value('focus_mode',1)end
  return ok,why
 end
 deps.menu.legend_factory=deps.legend
 menu=deps.menu.new(view,{focus=self.focus,hide=hide,exit=self.close,
  freeze=simulation and function()
   -- A pending (hover-settling) freeze counts as engaged, so this cancels it.
   local value=not(simulation.frozen or simulation.preparing)
   if handle.get('freeze_player')~=value then return handle.set('freeze_player',value)end
   local ok,why;if value then ok,why=simulation.freeze()else ok,why=simulation.resume()end
   if not ok then notice(why)end;sync_subject();return ok,why
  end or nil,
  freeze_state=simulation and function()return simulation.frozen or simulation.preparing,self.active and not pending_cleanup and self.mode~='shot',simulation.preparing end or nil,
  slowmo=simulation and function()return self.toggle_slowmo()end or nil,
  slowmo_state=simulation and function()return simulation.slowmo_active,not pending_cleanup and not simulation.pending_restore end or nil,
  hud=hud and function()return handle.set('hide_hud',not handle.get('hide_hud'))end or nil})
 menu.bind(handle,core.mods.dbf_freecam.pages)
 -- An input service without an OS cursor (Boot Mod Loader's engine input) moves a virtual one.
 menu.draw_pointer=type(service.capabilities)=='table'and service.capabilities.virtual_cursor==true
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
  if not simulation or pending_cleanup then return false,'Slow motion unavailable'end
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
  if controls.light_follow_player and not subject_backend then controls.light_follow_player.disabled=true end
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
     light_cone='cone',light_right='right',light_forward='forward',light_up='up',light_follow='follow_camera',light_follow_player='follow_player'}
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
  local probe=first_render;first_render=false
  if probe then checkpoint('render: begin')end
  if not self.active or pending_cleanup then return end
  local o=read_options()
  if self.mode=='shot'and shot and shot.handycam then
   local ok,reason=pcall(function()
    local head=subject_backend.head_frame()
    assert(head.identity==shot.player_identity,'Handycam local player changed')
    local frame=assert(camera.frame())
    local p,f,r,roll=handycam.step(head.head,frame.forward,sr.Application.time_since_launch(),o)
    photo.pos,photo.forward,photo.right,photo.handy_roll=p,f,r,roll
   end)
   if not ok then notice(reason);self.close(true);return end
  end
  local f,r=photo.forward,photo.right
  local roll=self.mode=='shot'and shot and shot.handycam and(photo.handy_roll or 0)or(photo.path_roll or photo.roll or o.roll)
  local up=deps.lens.up(f,r,roll)
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
  if not scene_enabled and(probe or scene_retry_at and sr.Application.time_since_launch()>=scene_retry_at)then
   scene_retry_at=nil;ensure_scene()
  end
  if scene_enabled then
   local called,ok,why,shader_dof=pcall(scene.render,o,fov)
   if not called or not ok then
    -- Keep Photo Mode open: drop the effect, report it and retry boundedly.
    local reason=tostring(called and why or ok);scene.release();scene_enabled=false;scene_status('Scene effects paused: '..reason)
    -- Retry within the same bounded budget; the latch stays until an event.
    if scene_retries<4 then scene_retry_at=sr.Application.time_since_launch()+.25*2^scene_retries;scene_retries=scene_retries+1 end
    if dof then local ok,why=dof.request(o.dof==true);if not ok then notice(why)end end
   elseif dof then local ok,why=dof.request(o.dof and not shader_dof);if not ok then notice(why)end end
  end
  if native_lens and not(native_lens_fault and sr.Application.time_since_launch()<native_lens_fault)then
   local called,ok,why=pcall(native_lens.tick,o,fov,camera.identity(),core.revision)
   if not called or not ok then
    -- A failed lens never closes Photo Mode; it reacquires after a 2 s pause.
    local reason=tostring(called and why or ok);pcall(native_lens.release)
    native_lens_fault=sr.Application.time_since_launch()+2
    if texts.lens_status then texts.lens_status.label='Native lens paused: '..reason end
   elseif texts.lens_status then texts.lens_status.label=native_lens.message end
  end
  if controls.focus_distance then controls.focus_distance.disabled=not(scene_enabled or native_lens and native_lens.ready)end
  if controls.aperture then controls.aperture.disabled=not(scene_enabled or native_lens and native_lens.ready)end
  if probe then checkpoint('render: camera write')end
  local ok,why=camera.write_view(photo.pos,f,up,fov,self.mode=='shot')
  if not ok then notice(why);self.close(true);return end
  local width,height=sr.Gui.resolution()
  local capturing=capture and capture.active()or false
  local hud_ready=true
  if hud then
   local ok,why=hud.set(capturing or o.hide_hud==true)
   if ok then ok,why=hud.tick(sr.Application.time_since_launch())end
   hud_ready=ok==true
   if not ok and why~=hud_reason then hud_reason=why;notice(why)elseif ok then hud_reason=nil end
  end
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
  -- A failed overlay is retired and parked until another overlay is chosen;
  -- Photo Mode itself stays open.
  if decorative_fault and decorative_fault~=o.shader then decorative_fault=nil end
  local function park_decorative(reason)
   decorative_fault=o.shader;notice(reason);shader_status('Decorative overlay stopped: '..tostring(reason))
  end
  if deps.decorative_overlay and o.shader>1 and o.shader_opacity>0 and not decorative_fault then
   if not decorative then decorative=deps.decorative_overlay.new(sr,deps.view,deps.composition,host.log)end
   local opened=true
   if not decorative_active then
    local called,ready,reason=pcall(decorative.open)
    if not called or ready==false then park_decorative(called and reason or ready);opened=false
    else decorative_active=true end
   end
   if opened then
    local called,done,reason=pcall(decorative.draw,width,height,o,last_time or 0)
    decorative_drawn=called and done==true
    if not called then park_decorative(done)
    elseif done~=true then
     local _,pending=decorative.status()
     shader_status(reason or'Decorative overlay draw unacknowledged')
     if pending then park_decorative(reason or'Decorative overlay draw unacknowledged')end
    else shader_status('Decorative overlay active')end
   end
  end
  if decorative_active and(decorative_fault or not(deps.decorative_overlay and o.shader>1 and o.shader_opacity>0))then
   local retired,reason=close_decorative(false)
   if not retired then notice(reason)
   elseif not decorative_fault then shader_status('Choose an overlay and nonzero opacity')end
  end
  if probe then checkpoint('render: overlay draw')end
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
   if not called or ok==false then notice(called and why or ok)end
  end
  if probe then checkpoint('render: menu draw')end
  if capturing then
   -- Destroy owned UI planes directly: an empty draw may refuse early when
   -- font/drawability is unavailable and leave retained controls visible.
   return hud_ready and menu.hide_for_capture()==true and decorative_drawn and drawn~=false and grain_drawn~=false
  elseif self.mode=='shot'then
   menu.draw_cinema(width,height,deps.legend.binding_label('toggle_key',handle),capturing or not o.cinema_notification,
    sr.Application.time_since_launch()-shot.started,capture~=nil)
  else
   menu.draw(width,height,self.mode=='menu'and not handoff,capturing or o.hide_controls or o.clean_view or handoff~=nil,
    {focus=deps.legend.binding_label('focus_key',handle),hide=deps.legend.binding_label('hide_controls_key',handle),slowmo=deps.legend.binding_label('slowmo_key',handle)})
  end
  return false
 end
 local function open()
  if disposed or self.active or pending_cleanup then return false,'Photo Mode is unavailable'end
  -- Native code may be unavailable during loader startup. Retry only at an
  -- explicit session boundary, preserving all current build/ownership guards.
  ensure_subject_backend()
  if not hover and deps.load_hover then
   local ok,value,why=pcall(deps.load_hover,sr)
   if ok and type(value)=='table'then hover=value;hover_fault=nil
   else hover_fault=tostring(ok and why or value);host.log('Hover pause unavailable: '..hover_fault)end
  end
  if handycam then
   if controls.action_camera_mode then controls.action_camera_mode.choices={'Placed camera','First-person handycam'}end
   if controls.handycam_intensity then controls.handycam_intensity.disabled=false end
  end
  checkpoint('open: input acquisition')
  local ok,why=input.set_mode('menu');if not ok then notice(why);self.close();return false,why end
  checkpoint('open: camera discovery')
  ok,why=camera.open();if not ok then notice(why);self.close();return false,why end
  checkpoint('open: camera frame')
  initial=assert(camera.frame());photo={pos=copy(initial.position),forward=copy(initial.forward),right=copy(initial.right)}
  initial_player=nil
  if subject_backend then
   local ok,frame=pcall(subject_backend.frame)
   if ok and type(frame)=='table'and type(frame.position)=='table'then initial_player=copy(frame.position)end
  end
  if lighting then
   local world,generation=camera.scene()
   local ready=lighting.open(world,generation,light_frame())
   light_controls(ready==true)
   light_revision=nil;sync_light()
  end
  checkpoint('open: saved camera')
  if bookmark then
   local restored,problem=bookmark.restore(bookmark_context(),handle.get('saved_camera_radius'),handle)
   if restored then photo=restored elseif problem then notice(problem)end
   bookmark_status()
  end
  checkpoint('open: visibility readiness')
  if visibility then
   local ready,why,caps=visibility.refresh(.5)
   for _,id in ipairs({'hide_player','hide_armour','hide_weapons','hide_cape'})do controls[id].disabled=not(ready and caps and caps[id])end
   if texts.subject_status then texts.subject_status.label=why end
   if ready then visibility.queue(read_options())end
  end
  self.active=true;self.mode='menu';self.state='active';self.reason=nil
  subject_close_started=false;begin_session();screenshot_label()
  if type(deps.load_subject)=='function'and load_subject()then auto_subject(initial.position)end
  checkpoint('open: renderer flags')
  if bloom then local ok,why=bloom.open(handle.get('bloom'));sync_bloom();if not ok then notice(why)end end
  if dof then local ok,why=dof.open(handle.get('dof'));sync_dof();if not ok then notice(why)end end
  -- Grab scene resources and the native lens now, after the DoF flag, instead
  -- of waiting for a render-time retry or a second open.
  scene_retries,scene_retry_at=0,nil;ensure_scene(true)
  if deps.load_native_lens and not native_lens then
   local ok,value=pcall(deps.load_native_lens,sr)
   if ok then native_lens=value elseif texts.lens_status then texts.lens_status.label=tostring(value)end
  end
  checkpoint('open: freeze action')
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
  sync_subject()
  checkpoint('open: render callback')
  first_render=true
  prior=assert(rawget(_G,'render'),'Game render callback unavailable')
  local saved=prior
  local owned
  local function observed(...)
   if native_lens and self.active then pcall(native_lens.observe)end
   return ...
  end
  local function rendered(frame,hidden,ok,...)
   if not ok then
    if capture then capture.invalidate('Game render failed')end
    error((...),0)
   end
   if wrapper==owned and not disposed and capture then
    capture_completed_frame=math.max(capture_completed_frame,frame)
    if capture.active()then capture.rendered(frame,hidden,true,capture_state())end
   end
   return observed(...)
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
   return observed(saved(...))
  end
  wrapper=owned
  rawset(_G,'render',wrapper)
  checkpoint('open: complete')
  last_time=sr.Application.time_since_launch()
  return true
 end
 function self.open()
  local called,ok,why=pcall(open)
  if not called then notice(ok);self.close();return false,ok end
  return ok,why
 end
 -- Per-frame helpers kept outside tick (Lua 5.1 allows 60 upvalues).
 local function handoff_frame(now)
  if not handoff then return false end
  -- Another menu owns input: keep the held scene, retake input when it closes.
  if ragdoll then local ok,why=ragdoll.flush(simulation and simulation.owns_zero()or false,subject_holds==true);if not ok then notice(why)end end
  -- ESC still exits when no other menu took the input.
  if not handoff.entry and input.focused()and edge(27)then self.close();return true end
  if input.focused()then handoff_tick(now)end
  return true
 end
 local function handoff_pressed(now)
  if not handoff_keys or menu.editing_key()or menu.editing_text()or menu.bound_key then return false end
  for _,entry in ipairs(handoff_keys)do if edge(entry.key)then yield_input(entry,now);return true end end
  return false
 end
 local function pick_tick(sample,o,now)
  if not pick or not sample or capture and capture.active()then return end
  local pressed=sample.click and not pick_held;pick_held=sample.click
  if not pressed or menu.contains_pointer(sample.x,sample.y)or menu.editing_text()or menu.editing_key()then return end
  if pick_click and now-pick_click.time<=.4 and math.abs(sample.x-pick_click.x)<=8 and math.abs(sample.y-pick_click.y)<=8 then
   pick_click=nil;pick_subject(sample.x,sample.y,o)
  else pick_click={x=sample.x,y=sample.y,time=now}end
 end
 function self.tick()
  if disposed then return end
  if capture then capture_frame=capture_frame+1 end
  input.frame()
  capture_tick()
  if input.focused()and not self.focus_suspended then
  local recovery_modifiers=input.down(17)and input.down(16)
  local recovery=recovery_modifiers and edge('recover_input_key')
  if not recovery_modifiers then edges.recover_input_key=false end
  if recovery then self.close(true,nil,true);return end
  end
  if pending_cleanup then
   if simulation and not subject_pending then
    local ok,why=simulation.tick();if not ok then notice(why);full_cleanup=true end
   end
   if bloom and bloom.waiting()or dof and dof.waiting()then tick_bloom()end
   self.close(nil,true);return
  end
  -- The Photo key stays usable during a handoff unless MCM itself is open.
  if input.focused()and not self.focus_suspended and not(handoff and handoff.entry and handoff.entry.is_open())then
  local slow_edge=edge('slowmo_key')
  if menu.bound_key and not input.down(menu.bound_key)then menu.bound_key=nil end
  if slow_edge and not handoff and not(menu.editing_key()or menu.editing_text()or menu.bound_key)then self.toggle_slowmo()end
  if edge('toggle_key')then
   if self.mode=='shot'and self.active then self.reposition_shot()
   elseif self.active then self.close()else self.open()end
  end
  end
  if simulation then
   -- A refused time state is reported; Photo Mode itself stays open.
   local ok,why=simulation.tick();if not ok then notice(why)end
   if simulation_revision~=simulation.revision then
    simulation_revision=simulation.revision
    if simulation.notice then notice(simulation.notice);simulation.notice=nil end
    if self.active and self.mode~='shot'and not simulation.frozen and not simulation.preparing and handle.get('freeze_player')then
     freeze_sync=true;local called,accepted=pcall(handle.set,'freeze_player',false);freeze_sync=false
     if not called or accepted==false then notice('Freeze setting synchronization failed')end
    end
    if simulation.reason then
     if shot then shot.refreeze=false end
     if subject_holds and not simulation.owned then subject_call('invalidate')end
     notice(simulation.reason)
    end
    sync_subject()
   end
  end
  if hover and hover.owned()and simulation and not simulation.frozen and not simulation.preparing then
   local ok,why=hover.release();if not ok then notice(why);self.close(true);return end
   ok,why=hover.cleanup();if not ok then notice(why)end
  end
  if deferred_shot and hover and not hover.owned()then
   local wanted=deferred_shot;deferred_shot=nil
   self.begin_shot(wanted.play_path,wanted.refreeze);return
  end
  if not self.active then return end
  if hover and simulation and simulation.owns_zero()then
   local ok,why=hover.hold();if not ok then notice(why)end
  end
  local now=sr.Application.time_since_launch();local dt=math.max(0,math.min(.1,now-(last_time or now)));last_time=now
  tick_bloom(now)
  if handoff_frame(now)then return end
  if not input.focused()then
   -- Focus loss only yields input. Freeze, camera and menu state are kept.
   self.focus_suspended=true
   if self.mode~='shot'then local ok,why=input.release();if not ok then notice(why)end end
   if ragdoll then local ok,why=ragdoll.flush(simulation and simulation.owns_zero()or false,subject_holds==true);if not ok then notice(why)end end
   return
  end
  if self.focus_suspended then
   if self.mode~='shot'then
    local ok,why=input.set_mode(self.mode);if not ok then notice(why);return end
    local sample,why=input.sample();if not sample or sample.pending then if why then notice(why)end;return end
   end
   for key in pairs(edges)do edges[key]=held(key)end
   self.focus_suspended=nil
   return
  end
  if self.mode=='shot'then
   -- No session notification is available here. One O(1) identity check each
   -- second during a shot; no world-unit scan or pointer snapshot.
   if now<shot.check_at or now-shot.check_at>=1 then
    shot.check_at=now;local ok,why=check_shot()
    if not ok then notice(why);self.close(true);return end
   end
  elseif not input.owns()then yield_input(nil,now);return end
  local sample
  if self.mode~='shot'then
   local why;sample,why=input.sample();if not sample then notice(why);yield_input(nil,now);return end
  end
  if self.mode~='shot'and handoff_pressed(now)then return end
  if self.mode~='shot'and edge('focus_key')then self.focus();return end
  if edge(27)then if not menu.dismiss()then self.close()end;return end
  if capture and edge('screenshot_key')and not(menu.editing_key()or menu.editing_text()or menu.bound_key)then self.screenshot()end
  if self.mode~='shot'and not(capture and capture.active())and edge('hide_controls_key')then hide()end
  if self.mode~='shot'and edge('lock_camera_key')then handle.set('lock_camera',not handle.get('lock_camera'))end
  if subject_holds and not subject_pending and subject and type(subject.maintain)=='function'then
   local ok,why=subject.maintain();if not ok then sync_subject();notice(why)end
  end
  if ragdoll then
   local ok,why=ragdoll.flush(simulation and simulation.owns_zero()or false,subject_holds==true)
   if not ok then notice(why)end
  end
  local o=read_options()
  if self.mode=='menu'then pick_tick(sample,o,now)end
  if scene_enabled and not(capture and capture.active())then
   local message=scene.focus(o,sample,self.mode=='menu',menu.contains_pointer,menu.editing_text()or menu.editing_key(),function(value)
    autofocus_write=true;local ok,why=handle.set('focus_distance',value);autofocus_write=false;return ok,why
   end)
   if message and texts.focus_status then texts.focus_status.label=message end
  end
  if self.mode=='menu'and not(capture and capture.active())then
   if not menu.scene_tick(sample,input.down)then menu.tick(sample,input.down)end
  elseif self.mode=='camera'and not o.lock_camera and not(path and path.playing)then
   sample_sequence=sample_sequence+1
   local f,r=deps.look.basis(photo,initial.forward,{mouse_x=sample.dx,mouse_y=sample.dy,dt=dt,
    sequence=sample_sequence,sensitivity=handle.get('look_sensitivity'),smoothing=o.camera_smoothing,
    smoothing_time=math.max(.001,o.smoothing_strength*.003)})
   photo.forward,photo.right=f,r
   local forward=(held('forward_key')and 1 or 0)-(held('back_key')and 1 or 0)
   local right=(held('right_key')and 1 or 0)-(held('left_key')and 1 or 0)
   local up=(held('up_key')and 1 or 0)-(held('down_key')and 1 or 0)
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
   local roll=(held('roll_right_key')and 1 or 0)-(held('roll_left_key')and 1 or 0)
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
  if visibility then
   local called,ok,why=pcall(visibility.flush,dt)
   if not called or ok==false then notice(called and why or ok)end
   local ready,status,caps=visibility.refresh(dt)
   for _,id in ipairs({'hide_player','hide_armour','hide_weapons','hide_cape'})do controls[id].disabled=not(ready and caps and caps[id])end
   if texts.subject_status then texts.subject_status.label=status end
  end
  if lighting then
   local ok,why=lighting.tick(light_frame)
   if not ok then notice(why)end
   sync_light()
   if texts.light_status then texts.light_status.label=lighting.status end
  end
 end
 function self.dispose()
  local ok,why=self.close(true,nil,true);if not ok then return false,why end
  -- Disable can be retried without on_update between attempts. Keep pending
  -- retirement bounded by the same coordinator, without recancelling a job.
  capture_tick()
  if capture and capture.busy()then return false,'Screenshot cleanup unconfirmed'end
  local retired,reason=close_decorative(true)
  if not retired then pending_cleanup=true;self.state='closing';notice(reason);return false,reason end
  if hosted and deps.legend.hosted_label==hosted.label then deps.legend.hosted_label=nil end
  disposed=true;handle.unregister();return true
 end
 return self
end
return M

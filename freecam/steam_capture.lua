-- Preparatory Lua 5.1 coordinator only: no loader, GUI, filesystem or encoding calls.
-- new(backend, app_clock, {timeout=15, cleanup_grace=2}) returns dot-call methods.
-- app_clock returns monotonic application seconds (not simulation time).
-- begin({output_token=string, output_path=string}, context) freezes primitives.
-- After validation, backend.new_job_token() purely issues a fresh session-scoped
-- monotonic token; backend.request accepts only its latest issued unused token.
-- Tokens are nonempty <=256 bytes. No coordinator token history or arbitrary cap.
-- Facade alone validates exact output spelling: ASCII-safe PNG basename <=128
-- bytes directly under its fixed output_directory; this model does no path IO.
-- context = {session=identity, scene=identity, focused=true, frame_id=integer}.
-- frame_id at begin is the latest completed render; session/scene identities must
-- change when replaced. Every active tick/rendered receives current context.
-- rendered(frame_id, ui_hidden, succeeded, context) reports completed render IDs
-- increasing from that baseline. After 12 consecutive successful hidden frames,
-- the next tick dispatches. Any new visible/failed frame resets this wait, even
-- when ready but not submitted; duplicate/old reports never change the count.
-- Backend functions are fast, nonblocking, nonreentrant injected adapter calls:
-- request(copied_intent) -> record OR nil/false, reason (rejected, no job created).
-- Uncertain native creation must return pending, never a rejection/new-job lease.
-- status(job_token, output_token) -> record; cancel(job_token, output_token) ->
-- true, terminal_record OR false, pending_record. Cancellation records require
-- matching job/output tokens AND output_path, including pending/failed/cancelled.
-- A record has matching job_token/output_token and state pending, succeeded,
-- failed or cancelled; EVERY record requires output_path exactly equal to intent.
-- All three terminal states acknowledge worker retirement and fence any later
-- publication. An adapter unable to establish this must not report terminal.
-- Other-token status records are stale and ignored. Missing tokens are errors.
-- Adapter maps this contract to the eventual service API; no loader field names.
-- active() alone hides the overlay; display preference is never changed. busy()
-- includes cleanup: continue tick() while busy, even with no current context.
-- close()/dispose()/invalidate() initiate cancellation once and restore overlay
-- immediately. Pending retirement polls <=10Hz for cleanup_grace, then blocks
-- without idle work. Explicit cancel() retries blocked cleanup. Terminal service
-- outcome is authoritative, including succeeded after publication has begun.
local M={}
local function finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
local function text(s,limit)return type(s)=='string'and #s>0 and #s<=limit end
local function copy(t)if not t then return nil end;local r={};for k,v in pairs(t)do r[k]=v end;return r end
local function context_ok(c,j)
 return type(c)=='table'and c.focused==true and c.session~=nil and c.session~=false and
  c.scene~=nil and c.scene~=false and(not j or(c.session==j.session and c.scene==j.scene))
end
function M.new(backend,clock,options)
 assert(type(backend)=='table'and type(backend.new_job_token)=='function'and type(backend.request)=='function'and type(backend.status)=='function'and
  type(backend.cancel)=='function'and type(clock)=='function','Async capture backend and application clock required')
 local request_backend,status_backend,cancel_adapter=backend.request,backend.status,backend.cancel
 local issue_token=backend.new_job_token
 local timeout=options and options.timeout or 15
 local grace=options and options.cleanup_grace or 2
 assert(finite(timeout)and timeout>0 and timeout<=120,'Capture timeout must be in (0,120] seconds')
 assert(finite(grace)and grace>0 and grace<=30,'Cleanup grace must be in (0,30] seconds')
 local api,current,blocked,last={},nil,nil,nil
 local function now()
  local ok,value=pcall(clock);if ok and finite(value)then return value end
  return nil
 end
 local function finish(j,state,reason)
  current=nil;blocked=nil
  last={state=state,reason=reason,job_token=j.job_token,output_token=j.output_token,
   output_path=state=='succeeded'and j.output_path or nil,cancel_confirmed=j.cancel_requested and true or nil,cleanup_blocked=false}
 end
 local function block(j,reason)
  current=nil;blocked=j
  last={state='cleanup_blocked',reason=reason,job_token=j.job_token,output_token=j.output_token,
   cancel_confirmed=false,cleanup_blocked=true}
  return false,reason
 end
 local function record(j,reply)
  if type(reply)~='table'or not text(reply.job_token,256)or not text(reply.output_token,256)then
   return nil,'backend record missing valid identity'
  end
  if reply.job_token~=j.job_token or reply.output_token~=j.output_token then return nil,'stale identity'end
  if reply.output_path~=j.output_path then return nil,'backend output identity mismatch'end
  if reply.state~='pending'and reply.state~='succeeded'and reply.state~='failed'and reply.state~='cancelled'then
   return nil,'backend state invalid'
  end
  return reply.state
 end
 local function terminal(j,reply)
  local reason=reply.state~='succeeded'and(text(reply.reason,2048)and reply.reason or j.cancel_reason or 'backend '..reply.state)or nil
  finish(j,reply.state,reason)
 end
 local function cancel_job(j,reason,retry)
  j.cancel_requested=true;j.cancel_reason=j.cancel_reason or reason;j.phase='cleanup_pending'
  current=j;blocked=nil -- Restore overlay before calling the adapter.
  if not j.submitted then finish(j,'cancelled',reason);return true end
  local time=now()
  local ok,retired,reply=pcall(cancel_adapter,j.job_token,j.output_token)
  if not ok then return block(j,'backend cancel error: '..tostring(retired))end
  local state,why=record(j,reply)
  if not state or reply.output_path~=j.output_path then return block(j,why or 'cancel output identity mismatch')end
  if(retired~=true and retired~=false)or(retired and state=='pending')or(not retired and state~='pending')then
   return block(j,'cancel retirement acknowledgement mismatch')
  end
  if retired then terminal(j,reply);return true end
  if not time or(not retry and time<j.last_time)then return block(j,'application clock invalid during cleanup')end
  j.last_time=time;j.cleanup_deadline=time+grace;j.next_poll=time+.1
  last={state='cleanup_pending',reason=j.cancel_reason,job_token=j.job_token,output_token=j.output_token,
   cancel_confirmed=false,cleanup_blocked=false}
  return false,'capture cleanup pending'
 end
 local function validate(context)
  local j=current
  if not context_ok(context,j)then cancel_job(j,'context invalidated');return nil end
  local time=now()
  if not time or time<j.last_time then cancel_job(j,'application clock invalid');return nil end
  if time>=j.deadline then cancel_job(j,'capture deadline exceeded');return nil end
  j.last_time=time;return time
 end
 local function consume(reply,request)
  local j=current
  local state,why=record(j,reply)
  if not state then
   if why=='stale identity'and not request then return false end
   if j.phase=='cleanup_pending'then block(j,why)else cancel_job(j,why)end
   return false
  end
  if state=='pending'then if j.phase~='cleanup_pending'then j.phase='pending'end;return true end
  terminal(j,reply);return state=='succeeded'
 end
 function api.begin(intent,context)
  if current or blocked then return false,blocked and 'capture cleanup unconfirmed'or 'capture already active'end
  if type(intent)~='table'or not text(intent.output_token,256)or
   not text(intent.output_path,32767)then return false,'valid immutable output identity required'end
  if not context_ok(context)or not finite(context.frame_id)or context.frame_id<0 or context.frame_id%1~=0 then
   return false,'current session, focus, scene and completed frame identity required'
  end
  local time=now();if not time then return false,'application clock invalid'end
  local ok,token=pcall(issue_token)
  if not ok or not text(token,256)then return false,'fresh job token unavailable'end
  current={job_token=token,output_token=intent.output_token,output_path=intent.output_path,
   session=context.session,scene=context.scene,phase='waiting_frames',frames=0,last_frame=context.frame_id,
   last_time=time,deadline=time+timeout,submitted=false}
  last=nil;return true
 end
 function api.rendered(frame_id,hidden,succeeded,context)
  if not current or current.phase=='cleanup_pending'then return false end
  if not validate(context)then return false end
  local j=current
  if j.submitted or not finite(frame_id)or frame_id%1~=0 or frame_id<=j.last_frame then return false end
  j.last_frame=frame_id
  if hidden~=true or succeeded~=true then j.frames=0;j.phase='waiting_frames';return false end
  if j.phase~='waiting_frames'then return false end
  j.frames=j.frames+1;if j.frames==12 then j.phase='ready'end
  return true
 end
 function api.tick(context)
  if not current then return false end
  local j=current
  local time
  if j.phase=='cleanup_pending'then
   time=now()
   if not time or time<j.last_time then return block(j,'application clock invalid during cleanup')end
   if time>=j.cleanup_deadline then return block(j,'cleanup deadline exceeded')end
   j.last_time=time
  else time=validate(context);if not time then return false end end
  if j.phase=='ready'then
   j.submitted=true;j.next_poll=time+.1
   local ok,reply,reason=pcall(request_backend,{job_token=j.job_token,output_token=j.output_token,output_path=j.output_path})
   if not ok then cancel_job(j,'backend request error: '..tostring(reply));return false end
   if reply==nil or reply==false then j.submitted=false;finish(j,'failed',text(reason,2048)and reason or 'request rejected');return false end
   return consume(reply,true)
  end
  if(j.phase=='pending'or j.phase=='cleanup_pending')and time>=j.next_poll then
   j.next_poll=time+.1
   local ok,reply=pcall(status_backend,j.job_token,j.output_token)
   if not ok then
    if j.phase=='cleanup_pending'then block(j,'backend status error: '..tostring(reply))else cancel_job(j,'backend status error: '..tostring(reply))end
    return false
   end
   return consume(reply,false)
  end
  return true
 end
 function api.close(reason)
  reason=text(reason,2048)and reason or 'capture cancelled'
  if current and current.phase~='cleanup_pending'then return cancel_job(current,reason)end
  return false,(current or blocked)and 'capture cleanup unconfirmed'or 'idle'
 end
 function api.cancel(reason)
  if blocked then return cancel_job(blocked,text(reason,2048)and reason or 'explicit cleanup retry',true)end
  return api.close(reason)
 end
 api.dispose=api.close;api.invalidate=api.close
 function api.active()return current~=nil and current.phase~='cleanup_pending'end
 function api.busy()return current~=nil or blocked~=nil end
 function api.state()return current and current.phase or(blocked and 'cleanup_blocked'or 'idle')end
 function api.result()return copy(last)end
 return api
end
return M

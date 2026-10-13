-- Local Helldiver animation events, dispatched only by the owning update hook.
-- Names/transitions come from the captured avatar graph; no raw state writes.
local M={catalog={{id='salute',label='Salute'},{id='wave',label='Wave'},{id='taunt',label='Taunt'}}}
local poses={
 salute={label='Salute',event='action_salute_01',states={[176]=true,[178]=true,[177]=true},exit='action_salute_exit'},
 wave={label='Wave',event='action_wave_01',states={[199]=true},exit='emote_wave_done'},
 taunt={label='Taunt',event='emote_taunt',states={[135]=true}},
}
local function pack(...)return{n=select('#',...),...}end
function M.new(sr,backend,is_paused,log)
 local U=sr and sr.Unit or{};log=log or function()end
 local self={available=false,pending=false,active=false,status='Subject poses are waiting for a local player',capabilities={}}
 local last,request,owned;local refresh_elapsed=.5
 local function snapshot()
  assert(backend and type(backend.frame)=='function','Local subject pose backend unavailable')
  for _,name in ipairs({'alive','has_animation_state_machine','animation_get_state','has_animation_event','animation_event'})do
   assert(type(U[name])=='function','Subject pose API unavailable: '..name)
  end
  local frame=assert(backend.frame(),'Local subject unavailable')
  assert(frame.local_owner==true and frame.identity and frame.root_handle,'Local subject pose ownership required')
  assert(U.alive(frame.root_handle)==true,'Subject pose Unit retired')
  assert(U.has_animation_state_machine(frame.root_handle)==true,'Subject pose animation graph unavailable')
  local states=pack(U.animation_get_state(frame.root_handle))
  -- The captured graph is zero-based; layer 8 is the ninth returned state.
  assert(states.n==31 and type(states[9])=='number'and states[9]>=0 and states[9]<1024 and states[9]%1==0,'Subject pose animation layout changed')
  frame.pose_state=states[9];return frame
 end
 local function forget(message)
  owned=nil;request=nil;self.pending=false;self.active=false
  if message then self.status=message end
 end
 local function current(expected)
  local frame=snapshot()
  assert(not expected or frame.identity==expected.identity,'Subject pose owner changed')
  return frame
 end
 local function dispatch(frame,event)
  local fresh=current(frame)
  assert(U.has_animation_event(fresh.root_handle,event)==true,'Subject pose event unavailable: '..event)
  -- Target binding accepts exactly two Lua arguments and returns no values.
  -- A nil return is normal. Native failures cannot be contained by pcall.
  U.animation_event(fresh.root_handle,event)
 end
 local function observe(frame)
  if owned and owned.identity~=frame.identity then forget('Subject pose owner changed');return end
  if not owned then return end
  local spec=poses[owned.id]
  if spec.states[frame.pose_state]then owned.observed=true;self.active=true
  elseif frame.pose_state==0 then
   if owned.observed then forget('Subject returned to gameplay')end
  else forget('Gameplay replaced the selected pose')end
 end
 local function ready()
  local frame=snapshot();observe(frame);last=frame
  local neutral=frame.pose_state==0
  local controlled=owned and owned.identity==frame.identity and poses[owned.id].states[frame.pose_state]
  self.capabilities={}
  for id,spec in pairs(poses)do
   self.capabilities[id]=(neutral or controlled)and U.has_animation_event(frame.root_handle,spec.event)==true
   if self.capabilities[id]and spec.exit then self.capabilities[id]=U.has_animation_event(frame.root_handle,spec.exit)==true end
  end
  self.available=neutral or controlled or false
  if not self.available then self.status='Wait for the Helldiver to finish the current action'
  elseif not owned and not request then self.status='Subject poses ready'end
  return self.available,self.status,self.capabilities
 end
 function self.refresh(dt)
  refresh_elapsed=refresh_elapsed+math.max(0,math.min(.5,tonumber(dt)or 0))
  if refresh_elapsed<.5 then return self.available,self.status,self.capabilities end
  refresh_elapsed=0
  local ok,a,b,c=pcall(ready)
  if not ok then
   self.available=false;self.capabilities={};last=nil
   self.status=tostring(a);return false,self.status,self.capabilities
  end
  return a,b,c
 end
 function self.queue(id)
  if not poses[id]then return false,'Unknown subject pose'end
  if not last or not self.available or not self.capabilities[id]then return false,self.status end
  request={id=id,identity=last.identity};self.pending=true;return true
 end
 function self.queue_stop()
  if not owned then request=nil;self.pending=false;self.active=false;return true end
  request={stop=true,identity=owned.identity};self.pending=true;return true
 end
 function self.release()return self.queue_stop()end
 local function paused()
  assert(type(is_paused)=='function','Subject pose pause state unavailable')
  local value=is_paused();assert(type(value)=='boolean','Subject pose pause state unavailable');return value
 end
 local function run()
  local frame=snapshot();last=frame;observe(frame)
  if not request then return true end
  local wanted=request;request=nil;self.pending=false
  if frame.identity~=wanted.identity then forget('Subject changed before the pose request');return false,self.status end
  if paused()then
   self.status='Turn Pause entire action off to play or stop; pause again to hold the pose'
   return false,self.status
  end
  if wanted.stop then
   if not owned then return true end
   local spec=poses[owned.id]
   if not owned.observed and frame.pose_state==0 then
    -- animation_event queues an engine event. A menu can request Stop before
    -- the next animation tick consumes Play; retain cleanup until it is seen.
    request=wanted;self.pending=true
    self.status='Waiting for the requested pose before returning to gameplay'
    return true,self.status
   end
   if not spec.states[frame.pose_state]then forget('Subject returned to gameplay');return true end
   owned.stopping=true
   if spec.exit then
    -- Salute already in its authored exit needs no repeated event.
    if not(owned.id=='salute'and frame.pose_state==177)then dispatch(frame,spec.exit)end
    self.status='Returning from '..spec.label..' to gameplay'
   else self.status='Taunt is finishing naturally; keep Pause entire action off'end
   return true,self.status
  end
  local spec=poses[wanted.id]
  local controlled=owned and owned.identity==frame.identity and poses[owned.id].states[frame.pose_state]
  assert(frame.pose_state==0 or controlled,'Gameplay owns the current animation')
  assert(U.has_animation_event(frame.root_handle,spec.event)==true,'Subject pose entry event unavailable')
  if spec.exit then assert(U.has_animation_event(frame.root_handle,spec.exit)==true,'Subject pose exit event unavailable')end
  owned={id=wanted.id,identity=frame.identity,observed=false,waiting=0};self.active=true
  dispatch(frame,spec.event)
  self.status=spec.label..' requested; pause again when the desired pose is reached'
  return true,self.status
 end
 function self.flush(dt)
  if not request and not owned then return true end
  if owned and not owned.observed then
   -- No repeated event sends. Discard an unobserved request after two seconds
   -- of unpaused updates, covering events ignored by the current gameplay state.
   local ok,value=pcall(paused)
   if ok and not value then owned.waiting=owned.waiting+math.max(0,math.min(.1,tonumber(dt)or 0))end
   if owned.waiting>=2 then forget('The requested pose did not start');return false,self.status end
  end
  local ok,a,b=pcall(run)
  if not ok then
   request=nil;self.pending=false;self.available=false;self.capabilities={};last=nil
   self.status='Subject pose unavailable: '..tostring(a);log(self.status)
   return false,self.status
  end
  return a,b
 end
 function self.current()return owned and owned.id or nil end
 return self
end
return M

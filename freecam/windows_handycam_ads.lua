-- First-person camera handoff from camera evidence. No engine calls.
-- Qualified near/far evidence: 0.163 m in first person, 1.132 m in normal aim.
-- This is camera evidence, not a claimed authoritative gameplay ADS flag.
-- Mouse edges open a short observation window, but the engine's input event
-- queue drops edges (the live log shows releases without a press), so both
-- directions also run a no-event watch: yielded, the first far frame reclaims
-- the mount; mounted, a confirmed native sight view yields. Measured in game,
-- the sight camera sits behind the head bone: the head is 0.10 to 0.25 m ahead
-- of it and 0.07 to 0.19 m off its axis (iron sights and a scope).
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function near(a,b)
 if not(a and b)then return false end
 local d=0;for i=1,3 do if not(finite(a[i])and finite(b[i]))then return false end;d=d+(a[i]-b[i])^2 end
 return d<1e-8
end
function M.new(log)
 local self={suspended=false};local active=false;local pending;local output
 local last_name,last_pressed,last_time
 local watch
 local function begin(now,reason)
  if not finite(now)then return end
  pending={deadline=now+.5,samples=0,streak=0,reason=reason};watch=nil
 end
 function self.reset()active=false;pending=nil;output=nil;last_time=nil;watch=nil;self.suspended=false end
 function self.set_active(value,now)
  value=value==true
  local was_active=active
  if value and not active then begin(now,'camera resumed')end
  active=value
  if not active and was_active then pending=nil;last_time=nil;watch=nil end
 end
 function self.event(name,pressed,now)
  if not active then return end
  if name~='right'and name~='middle'then return end
  pressed=pressed==true
  -- The event queue may miss a release across a camera/input context switch.
  -- A subsequent pressed event remains authoritative; deduplicate only an
  -- identical event at the same engine timestamp, not a guessed held state.
  if name==last_name and pressed==last_pressed and now==last_time then return end
  last_name,last_pressed,last_time=name,pressed,now
  -- Native input-context changes can drop either edge. A release is also a
  -- reconciliation notification; camera evidence still decides the state.
  begin(now,name..(pressed and ' pressed'or' released'))
 end
 function self.submitted(position,forward)
  output=output or{position={},forward={}}
  for i=1,3 do output.position[i]=position[i];output.forward[i]=forward[i]end
 end
 function self.observe(frame,head,now)
  if not active or not finite(now)then return self.suspended,false end
  if pending and(now>pending.deadline or pending.samples>=128)then pending=nil end
  local evidence=pending
  if not evidence then
   -- No qualified native entry or exit notification exists, and an input
   -- window may never open when the engine drops both edges of a click. Reuse
   -- the frame/head already required by Handycam: constant arithmetic, no API
   -- calls or timer delay. Yielded, the first far frame must reclaim the mount.
   -- Mounted, a confirmed near camera yields only inside the measured sight
   -- envelope: the head 0.03 to 0.35 m ahead of the camera and under 0.25 m
   -- off its axis. A third-person camera pushed to its shoulder pivot by
   -- collision has the head beside it, and our own mount sits ahead of the
   -- head, so neither qualifies.
   if not watch then
    if self.suspended then watch={streak=0,reason='native third-person return',only='far'}
    else watch={streak=0,reason='native first-person entry',only='near',sight=true}end
   end
   evidence=watch
  else evidence.samples=evidence.samples+1 end
  if not(frame and head and frame.position and frame.forward and head.head)then evidence.streak=0;return self.suspended,false end
  -- Never classify our own mount as native first person, even with zero lag.
  if not self.suspended and output and near(frame.position,output.position)and near(frame.forward,output.forward)then evidence.streak=0;return self.suspended,false end
  local d,ahead=0,0
  for i=1,3 do
   local a,b,f=frame.position[i],head.head[i],frame.forward[i]
   if not(finite(a)and finite(b)and finite(f))then evidence.streak=0;return self.suspended,false end
   d=d+(a-b)^2;ahead=ahead+(b-a)*f
  end
  local kind=d<.4*.4 and 'near'or d>.7*.7 and 'far'or nil
  local side=d-ahead*ahead
  if not kind or evidence.only and kind~=evidence.only or evidence.sight and not(ahead>.03 and ahead<.35 and side<.25*.25)then evidence.streak=0;return self.suspended,false end
  evidence.streak=kind==evidence.kind and evidence.streak+1 or 1;evidence.kind=kind
  -- Leave the first native near frame untouched so our aligned eye cannot
  -- become an indistinguishable output echo before the second confirmation.
  if evidence.streak<2 and not(self.suspended and kind=='far')then return self.suspended,false,kind=='near'and not self.suspended end
  local value=kind=='near';local changed=value~=self.suspended
  if changed then
   self.suspended=value
   if log then log('Handycam ADS: '..(value and 'yield'or'resume')..'; event='..evidence.reason..'; head_distance='..string.format('%.4f',math.sqrt(d))..'; head_ahead='..string.format('%.3f',ahead)..'; head_side='..string.format('%.3f',math.sqrt(math.max(0,side))))end
   -- An event batch can precede several native camera updates. Keep its
   -- original deadline/sample budget across handoffs so a delayed newer ADS
   -- entry is still observed after the previous exit reclaimed Handycam.
   -- Neither a handoff nor duplicate events extend the observation window.
   evidence.streak=0;evidence.kind=nil
   watch=nil
  end
  -- Before a handoff, keep observing: remembered ADS may appear after initial far frames.
  return self.suspended,changed
 end
 function self.pending()return pending~=nil end
 return self
end
return M

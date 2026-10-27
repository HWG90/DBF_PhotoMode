-- Event-triggered first-person camera handoff. No engine calls.
-- Qualified near/far evidence: 0.163 m in first person, 1.132 m in normal aim.
-- This is camera evidence, not a claimed authoritative gameplay ADS flag.
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
 local return_watch
 local function begin(now,reason)
  if not finite(now)then return end
  pending={deadline=now+.5,samples=0,streak=0,reason=reason};return_watch=nil
 end
 function self.reset()active=false;pending=nil;output=nil;last_time=nil;return_watch=nil;self.suspended=false end
 function self.set_active(value,now)
  value=value==true
  local was_active=active
  if value and not active then begin(now,'camera resumed')end
  active=value
  if not active and was_active then pending=nil;last_time=nil;return_watch=nil end
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
   if not self.suspended then return false,false end
   -- No qualified native exit notification exists. Reuse the frame/head already
   -- required by Handycam: constant arithmetic, no API calls or timer delay.
   -- The first far frame must reclaim the mount even if both input edges drop.
   return_watch=return_watch or{streak=0,reason='native third-person return',return_only=true}
   evidence=return_watch
  else evidence.samples=evidence.samples+1 end
  if not(frame and head and frame.position and frame.forward and head.head)then evidence.streak=0;return self.suspended,false end
  -- Never classify our own mount as native first person, even with zero lag.
  if not self.suspended and output and near(frame.position,output.position)and near(frame.forward,output.forward)then evidence.streak=0;return self.suspended,false end
  local d=0
  for i=1,3 do local a,b=frame.position[i],head.head[i];if not(finite(a)and finite(b))then evidence.streak=0;return self.suspended,false end;d=d+(a-b)^2 end
  local kind=d<.4*.4 and 'near'or d>.7*.7 and 'far'or nil
  if not kind or evidence.return_only and kind~='far'then evidence.streak=0;return self.suspended,false end
  evidence.streak=kind==evidence.kind and evidence.streak+1 or 1;evidence.kind=kind
  -- Leave the first native near frame untouched so our aligned eye cannot
  -- become an indistinguishable output echo before the second confirmation.
  if evidence.streak<2 and not(self.suspended and kind=='far')then return self.suspended,false,kind=='near'and not self.suspended end
  local value=kind=='near';local changed=value~=self.suspended
  if changed then
   self.suspended=value
   if log then log('Handycam ADS: '..(value and 'yield'or'resume')..'; event='..evidence.reason..'; head_distance='..string.format('%.4f',math.sqrt(d)))end
   -- An event batch can precede several native camera updates. Keep its
   -- original deadline/sample budget across handoffs so a delayed newer ADS
   -- entry is still observed after the previous exit reclaimed Handycam.
   -- Neither a handoff nor duplicate events extend the observation window.
   evidence.streak=0;evidence.kind=nil
   return_watch=nil
  end
  -- Before a handoff, keep observing: remembered ADS may appear after initial far frames.
  return self.suspended,changed
 end
 function self.pending()return pending~=nil end
 return self
end
return M

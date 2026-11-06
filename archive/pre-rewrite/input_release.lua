-- Lifecycle: begin before acquire/freeze; entry_ready on a later update;
-- observe only while Photo owns input; finish AFTER native + Window restoration.
-- Verification reads are bounded and never repeat the synthetic release batch.
local M={}
function M.new(backend,log)
 local self={active=false,pending=false,verified=false,pad_supported=false,status='Photo input release is idle'}
 local session;local phase;local last_observe;local check_count=0;local check_time;local started;local accepted=0;local unavailable
 local function now()local ok,v=pcall(backend.now);return ok and type(v)=='number'and v==v and v or nil end
 local function fail(why)self.status=tostring(why);return false,self.status end
 local function merge(snapshot)
  for k in pairs(snapshot.keys)do session.keys[k]=true end
  for _,button in ipairs(snapshot.buttons)do session.buttons[button.device..':'..button.index]={device=button.device,index=button.index,name=button.name}end
  if snapshot.unavailable then unavailable=snapshot.unavailable end
 end
 local function snapshot(expected)local ok,value,why=pcall(backend.snapshot,expected);if not ok then return nil,tostring(value)end;return value,why end
 local function send(which)
  local called,ok,why,count=pcall(backend.send,session.owner,session.keys);accepted=accepted+(called and tonumber(count)or 0)
  phase=which;self.pending=true;self.verified=false;started=now();check_count=0;check_time=started
  if not called or ok~=true then unavailable=tostring(called and why or ok);return fail('Photo '..which..' input release unconfirmed: '..unavailable)end
  self.status='Photo '..which..' releases accepted; waiting for engine button readback';return true
 end
 function self.begin()
  if session then return fail('Previous Photo input handoff is still active')end
  local value,why=snapshot();if not value then return fail('Photo input snapshot unavailable: '..tostring(why))end
  session={owner=value.owner,keys={},buttons={}};accepted=0;unavailable=nil;merge(value);self.active=true;last_observe=now()
  return send('entry')
 end
 function self.observe()
  if not self.active or not session then return true end
  local time=now();if time and last_observe and time-last_observe<.05 then return true end;last_observe=time
  local value,why=snapshot(session.owner);if not value then return fail('Photo input observation skipped: '..tostring(why))end
  merge(value);return true
 end
 local function verify()
  if not self.pending or not session then return self.verified,self.status end
  local time=now();if time and check_time and time<=check_time then return false,self.status end;check_time=time;check_count=check_count+1
  local called,ok,why=pcall(backend.verify,session.owner,session.buttons)
  if called and ok==true and not unavailable then
   self.pending=false;self.verified=true;self.status='Photo '..phase..' keyboard/mouse release verified'
   if phase=='exit'then session=nil;phase=nil end;return true,self.status
  end
  self.status='Photo '..tostring(phase)..' input release unconfirmed: '..tostring(unavailable or(called and why or ok)or'Engine still holds a button')
  if check_count>=12 or(time and started and time-started>=.25)then
   self.pending=false;self.verified=false
   if log then log(self.status)end
   if phase=='exit'then session=nil;phase=nil end
  end
  return false,self.status
 end
 function self.entry_ready()return verify()end
 function self.finish()
  self.active=false
  if not session then self.pending=false;return true end
  if phase=='exit'then return true,self.status end
  local value,why=snapshot(session.owner)
  if not value then
   if why=='focus_lost'or why=='window_retired'then session=nil;phase=nil;self.pending=false;self.verified=false;return fail('Photo input releases skipped: '..why)end
   return fail('Photo input release snapshot unavailable: '..tostring(why))
  end
  merge(value)
  -- A device inactive during capture may be readable again after restoration.
  -- The fresh exit snapshot is the authority for readback availability.
  unavailable=value.unavailable
  return send('exit')
 end
 function self.tick(photo_active)
  if photo_active then return self.observe()end
  if phase=='exit'then return verify()end
  return true
 end
 function self.state()
  local keys={};local buttons={};if session then for k in pairs(session.keys)do keys[#keys+1]=k end;table.sort(keys);for _,b in pairs(session.buttons)do buttons[#buttons+1]={device=b.device,index=b.index,name=b.name}end end
  return{active=self.active,pending=self.pending,verified=self.verified,phase=phase,status=self.status,accepted=accepted,keys=keys,buttons=buttons,window=session and session.owner.window,pad_supported=false}
 end
 self.release=self.finish;self.close=self.finish
 return self
end
return M

-- Explicit six-second A/B trial. The subject controller owns mode restoration;
-- this driver owns only copied diagnostic scalars and three scheduled samples.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-freeze-bone-probe.request';local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='freeze-bone-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function copy(frame)
 assert(type(frame)=='table'and type(frame.identity)=='string','Selected tracking frame unavailable')
 local out={identity=frame.identity,yaw=frame.yaw};assert(finite(out.yaw),'Invalid root yaw')
 for _,name in ipairs({'position','head'})do
  assert(type(frame[name])=='table','Missing subject position');out[name]={}
  for i=1,3 do local n=frame[name][i];assert(finite(n),'Invalid subject position');out[name][i]=n end
 end
 return out
end
local function distance(a,b)local d=0;for i=1,3 do d=d+(a[i]-b[i])^2 end;return math.sqrt(d)end
function M.new(log,measure)
 local self={};local work;local attempts=0
 local function emit(message)pcall(log,'Freeze bone probe: '..message)end
 function self.start(subject,now,action)
  if work or attempts>=3 then return false,'Bone-transfer trial is busy or exhausted'end
  if type(subject)~='table'or type(subject.hold_bone_transfer)~='function'or not finite(now)then return false,'Bone-transfer trial unavailable'end
  local ok,base=pcall(function()return copy(subject.tracking_frame())end)
  if not ok then return false,tostring(base)end
  attempts=attempts+1;local began=measure()
  local held,why=action('hold_bone_transfer')
  if not held then emit('start refused: '..tostring(why));return false,why end
  work={subject=subject,base=base,started=now,next_at=now+.5,sample=0,action=action,max_ms=(measure()-began)*1000}
  emit('started; six seconds; animation bone mode only; root/cloth pose writes=0; start_ms='..work.max_ms)
  return true
 end
 function self.tick(enabled,now)
  if not work then return end
  local w=work;local status=w.subject.status()
  -- A user pose/reset, subject retirement, or ordinary cleanup owns its state.
  if status.pose~='freeze-bone-trial'or status.selected~=w.base.identity then emit('ended by subject lifecycle');work=nil;return end
  if not enabled or not finite(now)or now<w.started or now>=w.started+6 then
   work=nil;local ok,why=w.action('reset')
   emit('restored='..tostring(ok)..'; samples='..w.sample..'; max_step_ms='..w.max_ms..(ok and''or'; '..tostring(why)))
   return
  end
  if now<w.next_at then return end
  local began=measure();local ok,current=pcall(function()return copy(w.subject.tracking_frame())end)
  if not ok or current.identity~=w.base.identity then
   work=nil;w.action('reset');emit('sample stopped: tracking identity unavailable');return
  end
  w.sample=w.sample+1;w.next_at=w.sample<3 and w.started+w.sample*2 or math.huge
  local angle=math.abs((current.yaw-w.base.yaw+math.pi)%(2*math.pi)-math.pi)
  w.max_ms=math.max(w.max_ms,(measure()-began)*1000)
  emit(string.format('sample=%d root_m=%.6f root_yaw_deg=%.3f head_m=%.6f',w.sample,distance(current.position,w.base.position),math.deg(angle),distance(current.head,w.base.head)))
 end
 function self.active()return work~=nil end
 return self
end
return M

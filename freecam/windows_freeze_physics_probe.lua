-- Explicit private off/on experiment, not an automatic freeze implementation.
-- There is no physics-enabled getter. The button deliberately requests disable
-- followed by enable on the same live, selected, visibly rotating Helldiver.
-- Never call this a restoration of arbitrary pre-existing physics flags.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-freeze-physics-probe.request';local f=io.open(path,'rb');if not f then return false end
 local value=f:read(64);f:close()
 return value=='freeze-physics-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function angle(a,b)
 local dot=0;for i=1,4 do dot=dot+a[i]*b[i]end
 return math.deg(2*math.acos(math.min(1,math.abs(dot))))
end
function M.new(sr,log,measure)
 local U,A,N,I,Q=sr.Unit,sr.Application,sr.Network,sr.IdString64,sr.Quaternion
 assert(type(U.disable_physics)=='function'and type(U.enable_physics)=='function','Unit physics off/on exports unavailable')
 local disable,enable=U.disable_physics,U.enable_physics
 local self={};local work;local attempts=0;local pending;local reason
 local function emit(s)pcall(log,'Freeze physics probe: '..s)end
 local function valid(w)
  assert(sr.Unit==U and U.disable_physics==disable and U.enable_physics==enable,'Physics binding changed')
  if N.game_session()~=w.session or A.main_world()~=w.world then return false end
  local alive=U.alive(w.unit);if alive==false then return false end
  assert(alive==true and U.world(w.unit)==w.world,'Physics subject world unavailable')
  assert(U.num_scene_graph_items(w.unit)==107,'Physics subject rig changed')
  local expected=I.from_hex('4d1c334d294dfa97')
  assert(I.equal(U.resource_name(w.unit),expected)==true,'Physics subject resource changed')
  return true
 end
 local function rotation(w)
  assert(valid(w),'Physics subject retired')
  local q={Q.to_elements(U.local_rotation(w.unit,1))};assert(#q==4,'Root rotation shape changed')
  local norm=0;for i=1,4 do assert(finite(q[i]),'Invalid root rotation');norm=norm+q[i]*q[i]end
  assert(math.abs(norm-1)<.01,'Root rotation is not normalized');norm=math.sqrt(norm)
  for i=1,4 do q[i]=q[i]/norm end;return q
 end
 function self.active()return work~=nil end
 function self.release(why,explicit_retry)
  if not work then return true end
  if pending and explicit_retry~=true then return false,reason end
  local w=work
  if not w.issued then work=nil;pending=nil;return true end
  local ok,value=pcall(function()
   if not valid(w)then return 'retired' end
   assert(enable(w.unit)~=false,'Unit.enable_physics refused')
   return 'enable call completed'
  end)
  if not ok then pending=true;reason=tostring(value);emit('enable pending: '..reason);return false,reason end
  emit(value..'; reason='..tostring(why)..'; samples='..w.samples..'; max_step_ms='..string.format('%.3f',w.max_ms))
  work=nil;pending=nil;reason=nil;return true
 end
 function self.start(frame,now)
  if work or attempts>=2 then return false,'Physics trial busy or exhausted'end
  local ok,w=pcall(function()
   assert(type(frame)=='table'and frame.explicit_subject and type(frame.root_handle)=='userdata'and type(frame.world)=='userdata','Select a Helldiver first')
   assert(finite(now),'Physics trial clock unavailable')
   local row={unit=frame.root_handle,world=frame.world,session=N.game_session(),samples=0,max_ms=0,started=now,next_at=now+.25}
   assert(type(row.session)=='userdata'and valid(row),'Physics subject unavailable')
   assert(U.animation_bone_mode(row.unit)=='position_and_rotation','Release the held pose before testing physics')
   row.before=rotation(row);return row
  end)
  if not ok then return false,tostring(w)end
  work=w;emit('armed; checking root rotation once before explicit disable/enable; no transform writes');return true
 end
 function self.tick(enabled,now)
  if not work then return true end
  if pending then return false,reason end -- Explicit cleanup may retry; never retry each frame.
  local w=work
  if not enabled or not finite(now)or now<w.started then return self.release('trial context ended')end
  if not w.issued and now>w.started+1 then return self.release('rotation check expired')end
  if w.issued and now>=w.deadline then return self.release('six-second timeout')end
  if now<w.next_at then return true end
  local began=measure()
  local ok,why=pcall(function()
   local q=rotation(w)
   if not w.issued then
    local drift=angle(w.before,q)
    if drift<5 then emit('not started: root rotation below five degrees');work=nil;return end
    -- Mark responsibility before calling: a native call may mutate then throw.
    attempts=attempts+1;w.issued=true;assert(disable(w.unit)~=false,'Unit.disable_physics refused')
    w.base=rotation(w);w.deadline=now+6;w.disabled_at=now;w.next_at=now+.5
    emit(string.format('disable call completed; before_deg=%.3f; enable due in six seconds; original enabled state has no getter',drift))
   else
    w.samples=w.samples+1;emit(string.format('sample=%d root_deg=%.3f',w.samples,angle(w.base,q)))
    w.next_at=w.samples<3 and w.disabled_at+w.samples*2 or math.huge
   end
  end)
  w.max_ms=math.max(w.max_ms,(measure()-began)*1000)
  if not ok then emit('trial interrupted: '..tostring(why));local released,problem=self.release('trial error');return released,released and tostring(why)or problem end
  return true
 end
 return self
end
return M

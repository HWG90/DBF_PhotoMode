DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local Clock=dofile('freecam/steam_update_clock.lua');local Hover=dofile('freecam/steam_hover_pause.lua');local Controller=dofile('freecam/hover_pause.lua')
local f=fixture(false,function(f,deps,sr)
 f.worldtime=0;f.value=6;f.z=1;f.engine_steps=0;f.hover_writes=0;f.zero_requests=0;f.factories=0
 sr.World={time=function(w)assert(w==f.world);return f.worldtime end}
 local time=sr.Application.set_time_step_policy
 sr.Application.set_time_step_policy=function(k,v)
  if v==0 then f.zero_requests=f.zero_requests+1;assert(f.z==0 and f.engine_steps>0,'Zero before a completed neutral engine update')end
  return time(k,v)
 end
 f.native_update=function(dt)
  f.runtime.tick()
  if dt>0 and f.rate>0 then f.worldtime=f.worldtime+dt*f.rate;f.engine_steps=f.engine_steps+1;if f.value==0 then f.z=0 end end
  return nil,'native',nil
 end
 update=f.native_update
 deps.load_hover=function()
  f.factories=f.factories+1
  local clock=Clock.new(sr,function(w)return w end)
  local backend={snapshot=function()
   assert(not f.read_failure,'Transient pack read unavailable')
   local e,dt=clock.sample();assert(e,dt)
   return{identity='local-pack',generation=1,epoch=e,dt=dt,active=true,hover=true,value=f.value,action=0,control={x=0,y=0,z=f.z}}
  end,input_supported=function()return true end,
  set=function(s,v)assert(f.lease and v==0 and s.value==f.value);f.value=v;f.hover_writes=f.hover_writes+1;return true end,
  restore=function(s,v)
   assert(f.lease and f.rate>0 and f.engine_steps>f.release_step,'Input or time released before owned hover restoration')
   assert(s.value==0 and v==6);f.value=v;f.hover_writes=f.hover_writes+1;return true
  end}
  local guard=Hover.new(backend,Controller,clock,sr.Application.time_since_launch)
  local release=guard.release
  guard.release=function()if guard.status().phase~='releasing'then f.release_step=f.engine_steps end;return release()end
  return guard
 end
end)
f.step=function(seconds,renders)
 local dt=seconds or.016;f.time=f.time+dt;local a,b,c=update(dt);assert(a==nil and b=='native'and c==nil)
 for i=1,renders or 0 do render()end
end
for i=1,100 do f.step(.016)end;assert(f.factories==0 and f.hover_writes==0,'Closed runtime loaded/probed hover')
f.open();assert(f.rate==1 and f.value==0 and f.zero_requests==0 and f.lease,'Preparation must retain input with positive engine time')
for i=1,8 do f.step(.016,1);if f.rate==0 then break end end
assert(f.rate==0 and f.zero_requests==1 and f.runtime.handle.get('freeze_player'))
for i=1,45 do f.step(.016,1)end;assert(f.zero_requests==1 and f.value==0)
assert(not f.runtime.close(true)and f.lease and f.rate==1 and f.value==0,'Close skipped deferred neutral restore')
f.read_failure=true;f.step(.016);assert(f.lease and f.value==0,'Unknown restore read dropped input ownership')
f.read_failure=false
for i=1,8 do f.step(.016);if not f.runtime.active then break end end
assert(not f.runtime.active and f.value==6 and not f.lease and f.zero_requests==1 and update==f.native_update)
assert(f.hover_writes==2,'Repeated close/hold rewrote settled hover data')
-- Action shots wait for the same positive-update restoration before gameplay.
assert(f.runtime.handle.set('freeze_player',true));f.z=1;f.open()
for i=1,8 do f.step(.016);if f.rate==0 then break end end
assert(f.rate==0)
local ok=f.runtime.begin_shot();assert(ok and f.runtime.mode=='menu'and f.lease and f.rate==1 and f.value==0)
for i=1,8 do f.step(.016);if f.runtime.mode=='shot'then break end end
assert(f.runtime.mode=='shot'and not f.lease and f.value==6,'Action handoff preceded hover restoration')
assert(f.runtime.close(true));f.finish()
print('Hover runtime: neutral positive preparation, true zero, retained input across resume/unknown restore, exact baseline, deferred action handoff and idle ownership passed')

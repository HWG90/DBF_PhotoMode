-- Source-only runtime integration with the actual decorative adapter and capture coordinator.
-- Native renderer, loader transport, filesystem and game state are isolated fixture doubles.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local Overlay=dofile('freecam/steam_overlay.lua')
local function configured(f,deps,sr)
 f.saved.shader=1;f.saved.shader_animate=false
 f.queries,f.adapter_creates,f.overlay_opens,f.overlay_closes,f.overlay_disposes,f.decorative_draws=0,0,0,0,0,0
 f.available=true;f.logs=0;f.log=function()f.logs=f.logs+1 end
 sr.Application.can_get=function(kind,path)
  f.queries=f.queries+1;assert(kind=='material'and path=='mods/dbf_hud/materials/mapped_crt_scan')
  return f.available
 end
 local make_view=deps.view.new
 deps.view.new=function(...)
  local view=make_view(...);local draw,release=view.draw,view.release
  view.draw=function(commands,token)
   if commands[1]and commands[1].preview_required then
    f.decorative_view=view;view.decorative=true;f.decorative_draws=f.decorative_draws+1
    f.decorative_commands=commands;f.decorative_token=token
    if f.draw_refuse then return false,'fixture overlay draw refused'end
   end
   return draw(commands,token)
  end
  view.release=function()
   if view.decorative then
    if f.retire_throw then error('fixture overlay retirement threw')end
    if f.retire_refuse then return false,'fixture overlay retirement refused'end
   end
   return release()
  end
  return view
 end
 deps.decorative_overlay={new=function(...)
  f.adapter_creates=f.adapter_creates+1
  local adapter=Overlay.new(...);f.adapter=adapter
  local open,close,dispose,draw=adapter.open,adapter.close,adapter.dispose,adapter.draw
  adapter.draw=function(...)if f.draw_unack then return nil end;return draw(...)end
  adapter.open=function()
   f.overlay_opens=f.overlay_opens+1
   if f.open_refuse then return false,'fixture overlay open refused'end
   return open()
  end
  adapter.close=function()f.overlay_closes=f.overlay_closes+1;return close()end
  adapter.dispose=function()
   f.overlay_disposes=f.overlay_disposes+1
   if f.dispose_refuse then return false,'fixture overlay disposal refused'end
   return dispose()
  end
  return adapter
 end}
end
local function preview(f)
 assert(f.runtime.handle.set('shader',2))
 assert(not f.controls.shader_preview)
 f.step(.016,1)
end
local function closed(f)
 f.retire_throw,f.retire_refuse,f.open_refuse,f.dispose_refuse=false,false,false,false
 f.finish()
end

do
 local f=fixture(nil,function(f,deps,sr)configured(f,deps,sr);f.saved.shader=2 end)
 local saves=f.saves;f.open()
 assert(f.adapter_creates==1 and f.queries==1 and f.decorative_draws==1 and f.saves==saves,
  'Saved nonzero overlay applies directly on open without rewriting preferences')
 assert(f.runtime.close()and f.runtime.open());f.step(.016,1)
 assert(f.adapter_creates==1 and f.overlay_opens==2 and f.decorative_draws==2,
  'Reopening restores saved overlay using the retained cleanup-qualified adapter')
 closed(f)
end

do
 local f=fixture(nil,configured);local clock=f.clock_reads
 for _=1,100 do f.step(.016)end
 assert(f.adapter_creates==0 and f.queries==0 and f.clock_reads==clock,'Closed overlays add no reads or allocations')
 f.open();assert(not f.controls.shader.disabled and not f.controls.shader_preview)
 for _=1,100 do f.step(.016,1)end
 assert(f.runtime.handle.get('shader')==1 and f.adapter_creates==0 and f.queries==0,
  'None does not instantiate decorative resources')
 local saves=f.saves;preview(f)
 assert(f.saves==saves+1 and f.adapter_creates==1 and f.queries==1,'Selecting an overlay activates it directly')
 local commands=f.decorative_commands;clock=f.clock_reads;local queries=f.queries
 for _=1,100 do f.step(.016,1)end
 assert(f.decorative_commands==commands and f.decorative_token==commands and f.queries==queries,
  'Static runtime uses immutable commands without repeated material discovery')
 assert(f.clock_reads==clock+100,'Decorative preview reuses the existing active tick clock')
 assert(f.runtime.handle.set('shader_animate',true));clock=f.clock_reads;f.step(.016,1)
 assert(f.clock_reads==clock+1 and f.decorative_commands[1].preview_time==f.time and not f.decorative_token,
  'Animation receives the already-sampled active time and uses the dynamic retained path')
 assert(f.runtime.handle.set('shader',1));f.step(.016,1)
 local draws,creates,closes=f.decorative_draws,f.adapter_creates,f.overlay_closes
 for _=1,100 do f.step(.016,1)end
 assert(f.decorative_draws==draws and f.adapter_creates==creates and f.overlay_closes==closes,
  'Disabled preview performs no adapter updates or repeated retirement')
 assert(f.runtime.close()and f.runtime.open());f.step(.016,1)
 assert(f.decorative_draws==draws,'Reopening does not re-enable a disabled preview')
 closed(f)
end

do
 local f=fixture(nil,configured);f.open();f.available=false;preview(f)
 local queries,logs=f.queries,f.logs;local writes=f.camera_writes
 for _=1,100 do f.step(.016,1)end
 assert(f.queries==queries and f.logs==logs and f.camera_writes>writes and f.runtime.active,
  'Unavailable assets stay cached while the camera and menu continue without log spam')
 f.start();for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==0 and f.capture().active(),'An explicitly requested missing overlay cannot acknowledge a clean screenshot')
 f.available=true
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==0 and f.queries==queries,'Appearance alone does not trigger negative-cache retries')
 assert(f.runtime.handle.set('shader',1)and f.runtime.handle.set('shader',2))
 for _=1,12 do f.step(.016,1);assert(f.requests==0)end
 f.step(0);assert(f.requests==1,'Explicit disable/enable retries and requires twelve fully acknowledged clean frames')
 closed(f)
end

do
 local f=fixture(nil,configured);f.open();preview(f)
 f.draw_refuse=true;f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==0 and f.runtime.active,'A refused required overlay draw keeps controls usable but blocks clean frames')
 f.draw_refuse=false
 local queries,draws,releases=f.queries,f.decorative_draws,f.decorative_view.releases
 for _=1,100 do f.step(.016,1);assert(f.requests==0)end
 assert(f.queries==queries and f.decorative_draws==draws and f.decorative_view.releases==releases,
  'Unchanged refused preview adds no material queries, draw/allocation attempts or retirements')
 assert(f.runtime.handle.set('shader',1)and f.runtime.handle.set('shader',2))
 for _=1,12 do f.step(.016,1);assert(f.requests==0)end
 f.step(0);assert(f.requests==1,'Explicit disable/enable permits capture after a fresh completed-frame wait')
 closed(f)
end

do
 local f=fixture(nil,configured);f.open();preview(f);f.draw_unack=true;f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==0 and f.capture().active()and f.runtime.active,
  'Nil adapter draw returns never acknowledge clean capture frames')
 f.draw_unack=false
 for _=1,12 do f.step(.016,1);assert(f.requests==0)end
 f.step(0);assert(f.requests==1,'Only explicit true draw acknowledgement permits capture')
 closed(f)
end

for _,fault in ipairs({'retire_refuse','retire_throw'})do
 local f=fixture(nil,configured);f.open();preview(f);f[fault]=true
 assert(not f.runtime.close(true)and f.runtime.state=='closing'and not f.lease and not f.camera_open,
  'Decorative cleanup failure participates after camera and input restoration')
 assert(not f.runtime.open(),'Pending decorative ownership prevents reopening')
 assert(not f.runtime.dispose(),'Disposal cannot discard failed decorative cleanup')
 f[fault]=false;assert(f.runtime.close(true)and f.runtime.state=='closed')
 assert(f.runtime.open());f.step(.016,1)
 assert(f.overlay_opens==2 and f.adapter_creates==1,'Reopening explicitly retries the retained session adapter')
 closed(f)
end

do
 local f=fixture(nil,configured);f.open();preview(f);f.retire_refuse=true
 assert(f.runtime.handle.set('shader',1));f.step(.016,1)
 assert(f.runtime.state=='closing'and not f.lease and not f.camera_open and not f.runtime.open(),
  'Turning an overlay off cannot discard refused ownership or trap gameplay input')
 f.retire_refuse=false;assert(f.runtime.close(true));closed(f)
end

do
 local f=fixture(nil,configured);f.open();f.open_refuse=true;preview(f)
 assert(not f.runtime.active and not f.lease and not f.camera_open,'Failed adapter open restores the camera and input')
 f.open_refuse=false;assert(f.runtime.open());f.step(.016,1);assert(f.runtime.active and f.decorative_draws==1)
 f.dispose_refuse=true
 assert(not f.runtime.dispose()and f.runtime.state=='closing'and not f.runtime.open(),
  'A refused final disposal retains the runtime registration and blocks reopen')
 f.step(.016);assert(f.runtime.state=='closing'and not f.runtime.open(),
  'Ordinary close retries cannot bypass an unresolved final disposal')
 f.dispose_refuse=false;closed(f)
end

do
 local f=fixture();f.open()
 assert(f.controls.shader.disabled and f.controls.shader_opacity.disabled and not f.controls.shader_preview,
  'Missing optional adapter gates only decorative controls')
 assert(f.runtime.active and f.camera_writes>0);f.finish()
end
print('Steam decorative runtime: direct selection, None idle, lazy static/negative caches, capture refusal/recovery and lifecycle ownership passed')

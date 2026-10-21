-- Renderer/readback is simulated; live Bloom visual acceptance remains pending.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local function configure(f,deps,sr)
 f.bloom_value=false;f.bloom_reads=0;f.bloom_calls={};f.bloom_queue={}
 f.native_bloom_setter=function(key,value)
  assert(key=='bloom_enabled'and(value=='true'or value=='false'))
  f.bloom_calls[#f.bloom_calls+1]={value=value,at=f.time}
  if not f.bloom_drop then f.bloom_queue[#f.bloom_queue+1]={value=value=='true',at=f.time+.15}end
  if f.bloom_fail==#f.bloom_calls then return false,'fixture native refusal'end
 end
 sr.Application.render_setting=function(key)assert(key=='bloom_enabled');f.bloom_reads=f.bloom_reads+1;return f.bloom_value end
 sr.Application.set_render_setting=f.native_bloom_setter
 f.advance_bloom=function()
  for i=#f.bloom_queue,1,-1 do if f.bloom_queue[i].at<=f.time then f.bloom_value=f.bloom_queue[i].value;table.remove(f.bloom_queue,i)end end
 end
end
local function step(f,dt,renders)
 f.time=f.time+(dt or .1);f.advance_bloom();f.runtime.tick()
 for _=1,renders or 0 do render()end
end
local function settle(f,count)for _=1,count or 30 do step(f,.1,1)end end
do
 local f=fixture(nil,configure)
 for _=1,100 do f.step(.016)end
 assert(f.bloom_reads==0 and #f.bloom_calls==0,'Closed runtime never reads Bloom')
 f.open();assert(not f.controls.bloom.disabled and f.bloom_reads==1 and #f.bloom_calls==1)
 settle(f,4);assert(f.bloom_value)
 local reads,calls=f.bloom_reads,#f.bloom_calls
 settle(f,100);assert(f.bloom_reads==reads and #f.bloom_calls==calls,'Settled runtime adds no native Bloom work')
 assert(f.runtime.begin_shot());settle(f,5);assert(f.bloom_value and #f.bloom_calls==calls,'Action shots retain the selected Bloom policy')
 assert(f.runtime.reposition_shot());assert(not f.runtime.close(true))
 assert(not f.lease and not f.camera_open and not f.runtime.active,'Async Bloom restore releases input/camera first')
 settle(f,5);assert(f.runtime.state=='closed'and not f.bloom_value and #f.bloom_calls==calls+1)
 assert(f.runtime.open());settle(f,4);assert(f.bloom_value)
 assert(f.runtime.handle.set('bloom',false));settle(f,4);assert(not f.bloom_value)
 assert(f.runtime.close(true));f.finish()
end
do
 local f=fixture(nil,configure);f.bloom_fail=1;f.open()
 assert(f.runtime.active and not f.controls.bloom.disabled,'Apply failure leaves camera/menu usable')
 local reads,calls=f.bloom_reads,#f.bloom_calls;settle(f,20)
 assert(f.bloom_reads==reads and #f.bloom_calls==calls,'Blocked apply does not poll while the menu remains usable')
 assert(not f.runtime.close(true));assert(not f.lease and not f.camera_open)
 settle(f,5);assert(f.runtime.state=='closed'and not f.bloom_value);f.finish()
end
do
 local f=fixture(nil,configure);f.bloom_drop=true;f.open();settle(f,25)
 assert(f.runtime.active);assert(not f.runtime.close(true)and not f.lease and not f.camera_open)
 local reads,clocks,writes=f.bloom_reads,f.clock_reads,#f.bloom_calls
 for _=1,100 do f.step(.016)end
 assert(f.bloom_reads==reads and f.clock_reads==clocks and #f.bloom_calls==writes,
  'Automatic pending_cleanup cannot restart blocked Bloom polling or setter submissions')
 assert(not f.runtime.open()and not f.runtime.dispose(),'Unknown native cleanup blocks reopen/dispose')
 f.bloom_value=true;f.bloom_drop=false;f.time=f.time+.2
 f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=true,true,true
 step(f,.016);assert(#f.bloom_calls==writes+1,'Physical recovery combo submits one guarded cleanup restore')
 settle(f,5);assert(f.runtime.state=='closed'and not f.bloom_value and #f.bloom_calls==writes+1,
  'Holding the recovery key cannot repeat the native setter')
 f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=false,false,false;step(f,.016)
 assert(f.runtime.open());settle(f,4);assert(f.runtime.active and f.bloom_value)
 assert(not f.runtime.close(true));settle(f,4);f.finish()
end
do
 local f=fixture(nil,configure);f.open();settle(f,4);assert(f.runtime.handle.set('freeze_player',false))
 assert(f.runtime.toggle_slowmo()and f.rate==.2)
 f.bloom_fail=2;assert(not f.runtime.close()and f.rate==.2 and not f.lease and not f.camera_open)
 f.time=f.time+.2;f.advance_bloom()
 assert(f.runtime.dispose()and f.rate==1,'A later disposal must escalate time cleanup after camera/UI cleanup already completed')
end
do
 local f=fixture(nil,configure);f.open();settle(f,4);f.bloom_fail,f.bloom_drop=2,true
 assert(not f.runtime.close(true)and not f.lease and not f.camera_open)
 settle(f,3);f.bloom_value=false
 f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=true,true,true
 step(f,.1);assert(f.runtime.state=='closed'and #f.bloom_calls==2,
  'Recovery acknowledges a partially applied restore without repeating its failed setter')
 f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=false,false,false;step(f,.016)
 f.bloom_drop=false;assert(f.runtime.open());settle(f,4)
 assert(not f.runtime.close(true));settle(f,4);f.finish()
end
print('Steam Bloom runtime: saved selection, native-only Color status, entry/idle, action-shot retention and input-first bounded/explicit cleanup passed')

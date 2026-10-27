-- BML's engine-only pause must not require a blocked native player/hover bridge.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps)
 deps.engine_time_only=true
 deps.subject_backend={pause_gate=true,new=function()error('system error 577')end}
 deps.subject_visibility={}
 -- Even if a host leaves a failed optional factory in the graph, it is not
 -- authority to refuse the independent engine time lease.
 deps.load_hover=function()error('system error 577')end
end)
f.open();f.step(.1,1)
assert(f.runtime.handle.get('freeze_player')and f.rate==0,'BML Freeze must use exact zero without native DLLs')
assert(f.runtime.handle.set('freeze_player',false));f.step(.1,1)
assert(f.rate==1,'BML Resume restores normal time')
assert(f.runtime.toggle_slowmo()and f.rate==.2)
assert(f.runtime.handle.set('freeze_player',true));f.step(.1,1);assert(f.rate==0)
assert(f.runtime.handle.set('freeze_player',false));f.step(.1,1);assert(f.rate==.2,'Resume retains selected Slow Motion')
assert(f.runtime.handle.set('freeze_player',true));f.step(.1,1);assert(f.rate==0)
assert(f.runtime.close(true));assert(f.rate==1,'Close always restores normal time')
f.finish()
print('BML engine-only Freeze: exact zero, resume to 1x/selected Slow Motion and close restoration despite error 577 passed')

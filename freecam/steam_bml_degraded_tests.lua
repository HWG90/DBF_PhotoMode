-- Engine-only BML behavior with the Windows native bridges refused.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps,sr)
 deps.diagnostics=true
 deps.subject_backend={pause_gate=true,new=function()error('system error 577')end}
 deps.subject_visibility={}
 deps.load_hover=function()error('system error 577')end
 deps.hud={new=function()error('system error 577')end}
 f.logs={};f.log=function(message)f.logs[#f.logs+1]=message end
 f.flags={bloom_enabled=false,dof_enabled=false};f.flag_reads=0;f.flag_writes=0
 sr.Application.render_setting=function(key)f.flag_reads=f.flag_reads+1;return f.flags[key]end
 sr.Application.set_render_setting=function(key,value)
  assert(value=='true'or value=='false');f.flag_writes=f.flag_writes+1;f.flags[key]=value=='true'
 end
end)
f.open();f.step(.2,1)
assert(f.rate==1 and not f.runtime.handle.get('freeze_player'),'Missing pause guard must refuse zero without closing Photo Mode')
assert(table.concat(f.logs,'\n'):find('Local player pause check unavailable',1,true))
assert(f.runtime.toggle_slowmo()and f.rate==.2,'Native refusal must not block engine Slow Motion')
assert(f.runtime.toggle_slowmo()and f.rate==1,'Engine Slow Motion must resume without a native backend')
for _,id in ipairs({'bloom','dof'})do
 assert(f.runtime.handle.set(id,false));f.step(.2,1)
 assert(f.flags[id..'_enabled']==false)
 assert(f.runtime.handle.set(id,true));f.step(.2,1)
 assert(f.flags[id..'_enabled']==true)
end
f.step(.2,1)
local reads,writes,logs=f.flag_reads,f.flag_writes,#f.logs
for _=1,100 do f.step(.016,1)end
assert(f.flag_reads==reads and f.flag_writes==writes and #f.logs==logs,'Settled renderer diagnostics must add no reads, writes or logs')
assert(table.concat(f.logs,'\n'):find('Selected Bloom value acknowledged',1,true))
assert(table.concat(f.logs,'\n'):find('Selected Depth of field value acknowledged',1,true))
f.runtime.close(true)
for _=1,10 do f.step(.2)end
assert(not f.flags.bloom_enabled and not f.flags.dof_enabled,'Restore the original renderer flags')
f.finish()
print('BML native refusal: safe Freeze rejection, independent engine Slow Motion/Bloom/DoF, acknowledged transitions, restoration and idle diagnostics passed')

-- A reload polls dispose without ticking the old runtime. Native render flags
-- can acknowledge asynchronously; retirement must advance their existing FSM.
do
 local queue,values={}, {bloom_enabled=false,dof_enabled=false}
 local h=fixture(false,function(h,deps,sr)
  sr.Application.render_setting=function(k)return values[k]end
  sr.Application.set_render_setting=function(k,v)queue[#queue+1]={k,v=='true'}end
 end)
 local function acknowledge()
  for _,r in ipairs(queue)do values[r[1]]=r[2]end;queue={};h.time=h.time+.2
 end
 h.open();h.runtime.handle.set('dof',true);h.step(.2,1);acknowledge();h.step(.2,1)
 assert(values.dof_enabled)
 assert(not h.runtime.dispose(),'Retirement waits for its original flag submission')
 local done=false
 for _=1,4 do acknowledge();done=h.runtime.dispose();if done then break end end
 assert(done,'Cleanup-only polling must process the flag acknowledgement')
 assert(values.dof_enabled==false and not h.lease,'Original DoF and input restored without gameplay tick')
 h.finish()
end

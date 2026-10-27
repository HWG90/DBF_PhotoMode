local factory=dofile('freecam/windows_dof_override.lua')
local discovery=dofile('freecam/windows_native_dof.lua')
local lens=dofile('freecam/lens.lua')
local mapping='core/stingray_renderer/shading_environment_components/dof'
local function fixture()
 local f={world={},manager={},entities={newproxy(),newproxy()},calls=0,writes=0,rows={},baseline={},logs={}}
 for i,e in ipairs(f.entities)do
  local row={shading_environment_mapping=mapping};f.rows[e]=row;f.baseline[e]={}
  for _,name in ipairs({'distance','region','region_start','region_end','near_scale','far_scale','near_max','far_max'})do
   for _,close in ipairs({'','_close'})do local key='dof_focal_'..name..close;row[key]=i;f.baseline[e][key]=i end
  end
 end
 local sr={Application={main_world=function()return f.world end,time_since_launch=function()return 0 end},
  World={entities=function()return f.entities end},EntityManager={alive=function(e)return not(f.dead==e)end,render_data_component=function()return f.manager end}}
 sr.RenderDataComponent={instances=function(m,e)assert(m==f.manager);f.calls=f.calls+1;return -140308449 end,
  get_property=function(m,e,id,path)assert(m==f.manager and id==-140308449);f.calls=f.calls+1;return f.rows[e][path[1]]end,
  set_property=function(m,e,id,path,value)
   assert(m==f.manager and id==-140308449 and f.rows[e][path[1]]~=nil and path[1]~='shading_environment_mapping')
   f.calls=f.calls+1;f.writes=f.writes+1
   if f.refuse_restore and value==f.baseline[e][path[1]]then error('restore refused')end
   f.rows[e][path[1]]=value
   if f.fail_after_write then f.fail_after_write=false;error('mutated then refused')end
  end}
 f.controller=factory.new(sr,function(s)f.logs[#f.logs+1]=s end,lens,discovery)
 f.o={dof=true,dof_mode=1,focus_distance=.7,aperture=1.2};f.frame={world=f.world,camera={},generation=1}
 function f.tick(n)for i=1,n or 1 do f.result,f.reason=f.controller.tick(f.o,1,f.frame)end end
 function f.restored(except)
  for e,row in pairs(f.baseline)do for k,v in pairs(row)do if not except or not except(e,k)then assert(f.rows[e][k]==v,k)end end end
 end
 return f
end
do
 local f=fixture();f.tick(10);assert(f.controller.ready)
 for k,v in pairs(f.rows[f.entities[1]])do assert(f.rows[f.entities[2]][k]==v,'Blend inputs must receive the same lens')end
 local after=f.calls;f.tick(1000);assert(f.calls==after,'Unchanged lens performs zero engine queries/writes')
 f.o.focus_distance=20;f.tick(3);assert(f.controller.ready)
 f.o.aperture=22;f.tick(3);assert(f.controller.ready)
 assert(f.controller.release());f.restored()
end
do
 local f=fixture();f.fail_after_write=true
 -- Discovery is time-budgeted; do not mistake a yielded discovery frame for
 -- the injected setter failure. Require evidence that the setter ran first.
 for i=1,100 do f.tick(1);if not f.fail_after_write then break end end
 assert(not f.fail_after_write and f.writes>0,'Injected setter failure must actually execute')
 assert(not f.controller.ready and f.result,'Mutation followed by error must restore immediately')
 f.restored();local before=f.writes;f.tick(100);assert(f.writes==before,'Setter failure must latch')
end
do
 local f=fixture();f.tick(10);local e=f.entities[1];local key='dof_focal_distance';f.rows[e][key]=99
 f.o.focus_distance=20;f.tick(1);assert(not f.controller.ready)
 assert(f.rows[e][key]==99,'Preserve a foreign writer')
 f.restored(function(x,k)return x==e and k==key end)
end
do
 local f=fixture();f.tick(10);f.refuse_restore=true
 assert(not f.controller.release(),'Do not discard restoration ownership after a refusal')
 f.refuse_restore=false;assert(f.controller.release());f.restored()
end
do
 local f=fixture();f.tick(10);f.world={};local before=f.calls
 assert(f.controller.release());assert(f.calls==before,'Retired worlds must not receive property calls')
end
do
 local f=fixture();f.rows[f.entities[2]].shading_environment_mapping='foreign'
 f.tick(10);assert(f.writes==0 and not f.controller.ready,'Reject the whole set before writing an incorrect schema')
end
do
 local f=fixture();f.tick(10);f.o.dof=false;f.tick(1);f.restored()
 local before=f.calls;f.tick(100);assert(f.calls==before,'Disabled lens is idle')
end
print('Native DoF override: real discovery, equal blend inputs, edit-only writes, partial failure rollback, foreign-writer preservation, cleanup retry, retired-world safety and idle disabled/steady states passed')

do
 local f=fixture();f.tick(10)
 for i=1,50 do f.o.focus_distance=1+i*.1;f.tick(1);assert(f.controller.ready,'Keep manual controls responsive during updates')end
 f.tick(4)
 for key,value in pairs(f.rows[f.entities[1]])do assert(f.rows[f.entities[2]][key]==value,'Do not starve later profiles during continuous edits')end
 local before=f.calls;f.tick(100);assert(f.calls==before)
 assert(f.controller.release());f.restored();f.tick(10);assert(f.controller.ready,'Normal close/reopen reacquires the lens')
 assert(f.controller.release());f.restored()
end
print('Native DoF continuous edits: bounded complete passes, latest-value coalescing, responsive controls, idle completion and close/reopen passed')

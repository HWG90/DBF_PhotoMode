local factory=dofile('freecam/windows_native_dof.lua')
local clock,queries,scans=0,0,0
local world={};local entities={};for i=1,200 do entities[i]=i end
local logs={};local fields={}
for _,key in ipairs({'distance','region','region_start','region_end','near_scale','far_scale','near_max','far_max'})do
 fields['dof_focal_'..key]=1;fields['dof_focal_'..key..'_close']=1
end
local render_handle,data_handle={},{}
local sr={Application={main_world=function()return world end,time_since_launch=function()return clock end},
 World={entities=function(w)assert(w==world);scans=scans+1;return entities end},
 EntityManager={alive=function()return true end,render_data_component=function(w)assert(w==world);return render_handle end,
 data_component=function(...)assert(select('#',...)==0);return data_handle end}}
local function instances(h,entity)
 queries=queries+1
 if h==render_handle and entity==42 then return 7 end
end
local function property(h,instance,key)queries=queries+1;assert(h==render_handle and instance==7);return fields[key]end
sr.RenderDataComponent={instances=instances,get_property=property,set_property=function()error('Discovery must not write')end}
sr.DataComponent={instances=instances,get_property=property,set_property=sr.RenderDataComponent.set_property}
local probe=factory.new(sr,function(s)logs[#logs+1]=s end)
local frame={world=world,camera={},generation=1}
for i=1,30 do clock=clock+.016;assert(probe.tick({},1,frame))end
assert(scans==1 and not probe.ready and probe.message=='Native profiles found; active-camera ownership unverified')
local after=queries
for i=1,120 do clock=clock+.016;probe.tick({},1,frame);probe.observe()end
assert(queries==after,'Completed discovery must remain idle')
assert(table.concat(logs,'\n'):find('provider=RenderDataComponent entity=42 instance=7',1,true))
assert(probe.release())
sr.World.entities=function()scans=scans+1;error('API not available')end
assert(probe.tick({},1,frame));after=scans
for i=1,120 do probe.tick({},1,frame)end
assert(scans==after,'Unavailable APIs must latch rather than rescan')
assert(probe.release())
sr.World.entities=function()return entities end
sr.RenderDataComponent.instances=function()return {}end
for i=1,30 do probe.tick({},1,frame)end
assert(probe.message=='No complete native lens profile exposed by component APIs','Empty instance array is valid')
for _,token in ipairs({7,-140308449,-1397583833,-2147483648,4294967295,newproxy()})do
 probe.release();sr.World.entities=function()return{42}end
 sr.RenderDataComponent.instances=function()return{token}end
 sr.RenderDataComponent.get_property=function(h,instance,key)assert(h==render_handle and instance==token);return fields[key]end
 for i=1,4 do probe.tick({},1,frame)end
 assert(probe.message=='Native profiles found; active-camera ownership unverified')
end
for _,bad in ipairs({{named=7},{'bad'},false,-2147483649,4294967296,.125,math.huge,0/0})do
 probe.release();sr.RenderDataComponent.instances=function()return bad end
 assert(probe.tick({},1,frame));assert(table.concat(logs,'\n'):find('Native DoF provider unavailable: RenderDataComponent',1,true),'Unsupported layout must refuse')
end
-- A bad DataComponent token must not suppress later render-data profiles.
probe.release();logs={};local rejected_reads=0;local bad_calls=0
sr.World.entities=function()return{1,2,42}end
sr.RenderDataComponent.instances=instances;sr.RenderDataComponent.get_property=property
sr.DataComponent.instances=function()bad_calls=bad_calls+1;return -.125 end
sr.DataComponent.get_property=function()rejected_reads=rejected_reads+1;error('Must not pass unqualified token to native getter')end
for i=1,30 do probe.tick({},1,frame)end
assert(bad_calls==1 and rejected_reads==0,'Latch the failed provider, never retry per entity')
assert(probe.message=='Native profiles found; active-camera ownership unverified')
assert(table.concat(logs,'\n'):find('value=-0.125',1,true),'Record the exact rejected number')
assert(table.concat(logs,'\n'):find('provider_failures=1',1,true))
-- Force a batch boundary and retire the outstanding component before the next getter.
probe.release();sr.World.entities=function()return{42}end;local old_clock=os.clock;local cpu=0;local count=0
os.clock=function()cpu=cpu+.002;return cpu end
sr.RenderDataComponent.instances=function()count=count+1;if count==1 then return{7,8}else return{9}end end
sr.RenderDataComponent.get_property=function(h,instance,key)assert(instance==7,'Retired instance read');return nil end
probe.tick({},1,frame);probe.tick({},1,frame);os.clock=old_clock
assert(probe.message:find('Components changed',1,true))
print('Native DoF discovery: integer and opaque arrays, empty/malformed layouts, lifetime revalidation, read-only bounded scan and idle completion passed; active lens unverified')

-- An explicitly armed entity-scoped experiment only reads the observed lens ID.
do
 local e1,e2=newproxy(),newproxy();local reads,enumerations,other_provider=0,0,0
 local messages={}
 sr.World.entities=function()return{e1,e2}end
 sr.EntityManager.alive=function(e)assert(e==e1 or e==e2);return true end
 sr.RenderDataComponent.instances=function(h,e)
  assert(h==render_handle and(e==e1 or e==e2));enumerations=enumerations+1
  return 9,-140308449
 end
 sr.DataComponent.instances=function()other_provider=other_provider+1;error('Not a render lens provider')end
 sr.RenderDataComponent.get_property=function(h,e,id,path)
  assert(h==render_handle and(e==e1 or e==e2)and id==-140308449)
  assert(type(path)=='table'and #path==1 and fields[path[1]])
  reads=reads+1;return fields[path[1]]
 end
 local candidate=factory.new(sr,function(s)messages[#messages+1]=s end,'entity-getter-v1')
 for i=1,30 do candidate.tick({},1,frame)end
 assert(reads==32 and other_provider==0,'Read only both complete profiles of the known class, using their distinct entities')
 assert(not candidate.ready and candidate.message=='Native profiles found; active-camera ownership unverified')
 local before=enumerations
 for i=1,100 do candidate.tick({},1,frame)end
 assert(reads==32 and enumerations==before,'Completed entity experiment stays idle')
 candidate.release();reads=0
 sr.RenderDataComponent.get_property=function()reads=reads+1;error('Getter signature refused')end
 for i=1,30 do candidate.tick({},1,frame)end
 assert(reads==1,'A refused signature latches; never enumerate alternative call shapes')
 assert(table.concat(messages,'\n'):find('contract=entity-getter-v1',1,true))
 assert(not pcall(factory.new,sr,function()end,'unknown'),'Reject unspecified reader contracts')
end
print('Entity getter experiment: explicit contract, genuine entity/ID pairs, known lens class only, fixed four-argument read, refusal latch and no writes passed')

do
 local e1,e2=newproxy(),newproxy();local unit=newproxy();local manager={};local messages={};local association_calls=0
 sr.World.entities=function()return{e1,e2}end
 sr.EntityManager.alive=function()return true end
 sr.EntityManager.debug_name=function(e)association_calls=association_calls+1;return e==e1 and'camera'or'other'end
 sr.EntityManager.unit_component=function(w)assert(w==world);return manager end
 sr.UnitComponent={instances=function(m,e)assert(m==manager);if e==e1 then return 77 end end,
  unit=function(m,e)assert(m==manager and e==e1);return unit end}
 sr.Unit={alive=function(u)assert(u==unit);return true end,resource_name=function()return'camera_unit'end,num_cameras=function()return 1 end}
 sr.RenderDataComponent.instances=function()return -140308449 end
 sr.RenderDataComponent.get_property=function(h,e,id,path)
  assert(h==render_handle and(e==e1 or e==e2)and id==-140308449)
  if path[1]=='shading_environment_mapping'then return'lens'end
  return fields[path[1]]
 end
 local identity={world=world,camera={},unit=unit,generation=1}
 local candidate=factory.new(sr,function(s)messages[#messages+1]=s end,'entity-owner-v1')
 for i=1,30 do candidate.tick({},1,identity)end
 assert(not candidate.ready,'An association never grants write ownership')
 local output=table.concat(messages,'\n')
 assert(output:find('matches_camera_unit=true',1,true)and output:find('matches_camera_unit=false',1,true))
 local before=association_calls
 for i=1,100 do candidate.tick({},1,identity)end
 assert(association_calls==before,'No association polling after inventory')
 candidate.release();association_calls=0
 sr.EntityManager.debug_name=function()association_calls=association_calls+1;error('Unavailable')end
 for i=1,30 do candidate.tick({},1,identity)end
 assert(association_calls==1,'Association getter errors latch for the whole inventory')
end
print('Native lens associations: observed entity/unit pairing, no absent-unit lookup, optional failure latch, no write ownership and idle completion passed')

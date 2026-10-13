local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local render=dofile(root..'render_profile.lua');local lens=dofile(root..'lens.lua')
local fields={focal_distance=2,focal_region=30,focal_region_start=1,focal_region_end=1,focal_near_scale=1,focal_far_scale=1,focal_near_max=1,focal_far_max=1,focal_far_max_close=1}
local baseline={};for k,v in pairs(fields)do baseline[k]=v end
local flags={dof_enabled=false,bloom_enabled=true};local restored=0;local valid=true;local available=false;local writes=0;local ticks=0;local released=0
local sr={Application={render_setting=function(k)return flags[k]end,set_render_setting=function(k,v)flags[k]=v=='true'end}}
render.camera_factory={new=function()
 if not available then return end
 local params={};for k in pairs(fields)do params[k]=true end
 return {native_numeric_candidate=true,parameters=params,read=function(k)return fields[k]end,
 write=function(k,v)assert(valid);fields[k]=v;writes=writes+1 end,
 restore=function()for k,v in pairs(baseline)do fields[k]=v end;restored=restored+1;return true end,
 release=function()for k,v in pairs(baseline)do fields[k]=v end;released=released+1;return true end,flush=function()assert(valid)end,tick=function()ticks=ticks+1;return valid end}
end}
local profile=assert(render.new(sr,42,function()return true end,7,8));profile.tick()
assert(not profile.native_numeric_ready and not profile.parameters.focal_distance,'Missing source must keep numeric controls disabled')
DBF_PHOTO_NATIVE_LENS_CANDIDATE=true;profile.tick()
assert(profile.native_numeric_candidate and not profile.native_numeric_ready and not profile.parameters.focal_distance,'Configured Native waiting for its packet must expose warming state while retaining the numeric gate')
DBF_PHOTO_NATIVE_LENS_CANDIDATE=nil
available=true;profile.tick();assert(profile.native_numeric_ready and profile.parameters.focal_distance,'Late camera source must attach')
assert(ticks==1,'A newly attached lens must validate once in its owning frame')
profile.tick();assert(ticks==2 and profile.native_numeric_ready,'An existing lens must not run its retirement check twice per frame')
DBF_PHOTO_RENDER_PROFILE=profile
local effect=dofile(root..'postfx.lua').new(sr,lens)
local opts=dofile(root..'photo_options.lua');local o=opts.read({get=function(k)return opts.defaults[k]end})
o.dof_mode=1;o.dof=true;o.focus_distance=1.4;o.aperture=2
assert(effect.apply(42,o,math.rad(90)));assert(effect.native_numeric_ready)
local near=lens.depth(1.4,2,math.rad(90));assert(fields.focal_distance==near.near and fields.focal_region==near.region)
o.aperture=22;effect.apply(42,o,math.rad(90));assert(fields.focal_region>near.region,'Closing aperture must deepen sharp interval')
o.dof_mode=2;local previous=writes;effect.apply(42,o,math.rad(90),nil,nil,true)
assert(not effect.native_numeric_ready and restored>0 and writes==previous,'Shader switch must restore and cease native lens writes')
for k,v in pairs(baseline)do assert(fields[k]==v,'Method switch must restore '..k)end
o.dof_mode=1;effect.apply(42,o,math.rad(90));assert(effect.native_numeric_ready)
valid=false;available=false;profile.tick();assert(not profile.native_numeric_ready and not profile.parameters.focal_distance,'Retired source must disable controls')
assert(released==1 and effect.release(),'Postfx cleanup must accept the numeric source restoration already acknowledged by retirement')
for k,v in pairs(baseline)do assert(fields[k]==v,'Retirement cleanup changed restored '..k)end
assert(not pcall(profile.restore,'unknown_parameter',1),'Absent-source restore must not accept an unsupported unowned parameter')
DBF_PHOTO_RENDER_PROFILE=nil
print('Native lens: late source attachment, capability gate, physical focus/aperture mapping, Shader switch restore and retired-source disable passed')

-- The production renderer checks before commands exist. Read them after the
-- original renderer returns, then attach from copied scalars next frame.
local camera=dofile(root..'camera_profile.lua')
local time,queued,observations=0,nil,0
local world={address=10,native=100,provider=200};local cam={address=300,id=400}
local function identity(w,c)return {world_address=w.address,native=w.native,provider=w.provider,camera_address=c.address,camera_id=c.id}end
local cache=camera.observation_cache(identity,function(native,id)
 observations=observations+1
 if queued and native==queued.native and id==queued.id then return queued.fields end
end,function()return time end,.5)
local values={distance=2,region=30,close_distance=1,close_region=1}
assert(cache.request(world,cam)==nil,'Cold start must wait before queued commands exist')
camera.observe=cache.observe;camera.clear_observations=cache.clear
local active=true;local logged=0
local wrapped=camera.after_render(function(a,b)
 assert(a==7 and b==nil,'Original render arguments must survive wrapping')
 queued={native=world.native,id=cam.id,fields=values};return 11,nil,13,nil
end,function()return active end,function()logged=logged+1 end)
local function pack(...)return {n=select('#',...),...}end
local result=pack(wrapped(7,nil))
assert(result.n==4 and result[1]==11 and result[2]==nil and result[3]==13 and result[4]==nil,'Original return arity and trailing nil must survive observation')
assert(observations==1 and logged==0)
values.distance=99;queued=nil;time=.016
local observed=assert(cache.request(world,cam),'Next frame must receive the exact queued camera observation')
assert(observed.distance==2 and observed.region==30,'Cache must copy numbers rather than retain renderer-owned tables')
assert(cache.request(world,cam)==nil,'An observation must be consumed only once')
assert(not cache.observe(),'Absent next-frame queue must remain waiting')
values.distance=2;queued={native=world.native,id=cam.id,fields=values};assert(cache.observe())
time=1
assert(cache.request(world,cam)==nil,'Expired observations must not unlock numeric controls')
assert(cache.observe());cam.id=401
assert(cache.request(world,cam)==nil,'A new camera ID must not consume the previous camera observation')
assert(not cache.observe(),'Queue belonging to the old camera must be ignored')
queued={native=world.native,id=cam.id,fields=values};assert(cache.observe())
world.native=101
assert(cache.request(world,cam)==nil,'Native world generation changes must invalidate observations')
assert(not cache.observe(),'The old native world queue must be ignored')
queued={native=world.native,id=cam.id,fields=values};assert(cache.observe())
world.provider=201
assert(cache.request(world,cam)==nil,'Provider retirement must invalidate an otherwise matching world/camera')
cam.address=301;assert(not cache.observe(),'Camera pointer generation must be rechecked after render')
assert(not cache.observe(),'A retired pending request must release its references')
cache.request(world,cam);active=false;wrapped(7,nil)
assert(not cache.observe(),'Photo exit must clear pending camera observations')
local failed_render=camera.after_render(function()error('original-render-sentinel')end,function()return true end,function()end)
local before=observations;local ran,why=pcall(failed_render)
assert(not ran and tostring(why):find('original%-render%-sentinel')and observations==before,'Original render errors must propagate without observation')
camera.observe=function()error('readonly-observer-sentinel')end
local stable=camera.after_render(function()return nil,42,nil end,function()return true end,function()logged=logged+1 end)
for _=1,601 do local out=pack(stable());assert(out.n==3 and out[2]==42)end
assert(logged==3,'Observation errors must preserve rendered results and log only bounded reminders')
camera.observe=cache.observe
cache.request(world,cam);cache.clear();assert(not cache.observe(),'Explicit cleanup must discard the final pending request')
-- The live game invokes its original render path without consulting the
-- public Application table. Its exact queued view is observable during update.
queued={native=world.native,id=cam.id,fields=values};cache.request(world,cam)
local during_update=false;local before_values
camera.observe=function()
 if not during_update then return false end
 return cache.observe()
end
local update=camera.around_update(function(a,b)
 assert(a==23 and b==nil);during_update=true;return 29,nil
end,function()return true end,function()end)
local out=pack(update(23,nil));assert(out.n==2 and out[1]==29 and out[2]==nil)
assert(cache.request(world,cam),'Update-phase observation must attach even when render/world hooks see no queue')
cache.request(world,cam);queued={native=world.native,id=cam.id,fields=values}
local consume_before=camera.around_update(function()
 before_values=cache.request(world,cam);during_update=false;return nil,31,nil
end,function()return true end,function()end)
out=pack(consume_before())
assert(before_values and out.n==3 and out[2]==31,'A queued view present before update must be copied before update consumes it')
camera.observe=cache.observe;cache.clear()
local time=0
local signatures=camera.selection_history({distance=2,region=30,close_distance=1,close_region=1},function()return time end)
signatures.record({distance=.9,region=.2,close_distance=.9,close_region=.2})
assert(signatures.accept({distance=2,region=30,close_distance=1,close_region=1}),'Initial GPU view lag must not retire the newly attached source')
time=.02;signatures.record({distance=1.1,region=.3,close_distance=1.1,close_region=.3})
assert(signatures.accept({distance=.9,region=.2,close_distance=.9,close_region=.2}),'The previous own write must remain valid during a one-frame GPU lag')
assert(not signatures.accept({distance=1.9,region=400,close_distance=1,close_region=3}),'A different active source must retire the old source despite identical camera/world ownership')
time=1;signatures.record({distance=1.1,region=.3,close_distance=1.1,close_region=.3})
assert(not signatures.accept({distance=2,region=30,close_distance=1,close_region=1}),'Old source signatures must expire instead of accepting an unchanged foreign camera profile')
-- Stock and owned packets may coexist for the same camera in different render
-- queues. Rejecting the first stock packet must not restore an owned source
-- while another exact-camera packet still contains its current lens values.
local stock={distance=2,region=30,close_distance=1,close_region=1}
local owned_view={distance=1.1,region=.3,close_distance=1.1,close_region=.3}
local foreign_view={distance=1.9,region=400,close_distance=1,close_region=3}
assert(camera.select_observed_view({stock,owned_view},signatures.accept)==owned_view,'A preceding stock packet must not mask the current owned lens')
assert(camera.select_observed_view({owned_view,stock},signatures.accept)==owned_view,'Packet queue order must not change the selected owned lens')
assert(camera.select_observed_view({stock,foreign_view},signatures.accept)==stock and not signatures.accept(stock),'A queue with no owned match must still refuse the source')
assert(camera.select_observed_view({},signatures.accept)==nil,'An empty queue must remain unavailable')
assert(camera.select_observed_view({stock,owned_view})==stock,'Cold acquisition retains its original source-selection behavior')
local lookup_count=0
local function other_source(values)lookup_count=lookup_count+1;return values==foreign_view end
for _=1,1000 do assert(camera.retain_lens_source(true,true,nil,stock,signatures.accept,other_source),'A paused empty queue must not retire a still-owned lens')end
assert(camera.retain_lens_source(true,true,stock,stock,signatures.accept,other_source)and lookup_count==0,'An expired stock queue must not force a handoff or scan')
assert(camera.retain_lens_source(true,true,owned_view,stock,signatures.accept,other_source)and lookup_count==0,'An own-history packet must retain the source without scanning')
assert(not camera.retain_lens_source(true,true,foreign_view,stock,signatures.accept,other_source)and lookup_count==1,'A uniquely validated different source must hand off')
assert(camera.retain_lens_source(true,true,foreign_view,stock,signatures.accept,function()return false end),'An unfamiliar or ambiguous queue alone must not retire a still-owned lens')
assert(not camera.retain_lens_source(false,true,owned_view,stock,signatures.accept,other_source)and lookup_count==1,'Foreign field ownership must retire immediately without relying on a queue')
assert(not camera.retain_lens_source(true,false,owned_view,stock,signatures.accept,other_source)and lookup_count==1,'Changed camera identity must retire immediately without relying on a queue')
local probe_time=0;local probes=0
local probe=camera.changed_source_probe(function()return probe_time end,function(values)probes=probes+1;return values==foreign_view end)
assert(probe(foreign_view)and probes==1,'A new unfamiliar signature must be independently inspected')
for _=1,1000 do probe(foreign_view)end;assert(probes==1,'An unchanged packet must not rescan profiles every frame')
probe_time=.05;assert(not probe(stock)and probes==1,'Changed packets must still respect the source scan throttle')
probe_time=.11;assert(not probe(stock)and probes==2,'A throttled change must remain eligible once its interval elapses')
probe_time=.5;assert(not probe(stock)and probes==2,'An unresolved unchanged packet must not rescan at the changed-packet frequency')
probe_time=1.12;assert(not probe(stock)and probes==3,'An unresolved signature must retry at the slower cadence')
local retry_time=0;local found_other=false;local retry_count=0
local retry_probe=camera.changed_source_probe(function()return retry_time end,function(values)retry_count=retry_count+1;return found_other and values==foreign_view end)
assert(not retry_probe(foreign_view)and retry_count==1,'A temporarily absent different source must remain unresolved')
found_other=true;retry_time=.5;assert(not retry_probe(foreign_view)and retry_count==1,'Temporary readiness must retain the bounded retry interval')
retry_time=1.01;assert(retry_probe(foreign_view)and retry_count==2,'The same queued values must transfer once their validated source becomes available')
assert(not camera.same_lens_values(stock,{distance=math.huge,region=30,close_distance=1,close_region=1}),'Nonfinite queue values must not match a baseline')
cache.request(world,cam);queued={native=world.native,id=cam.id,fields=values};assert(cache.observe())
local a=assert(cache.request(world,cam,true));local b=assert(cache.request(world,cam))
assert(a.distance==b.distance,'Read-only source revalidation must preserve the exact cached observation for the next factory during handoff')
local actual={distance=5,region=7};local own={distance=5,region=6};local baseline={distance=2,region=30};local count=0
local function read(name)return actual[name]end
local function write(name,value)actual[name]=value;count=count+1 end
assert(not camera.owns_fields(own,function()return true end,read),'External parameter changes must retire the source before another setter write')
assert(not camera.retain_lens_source(camera.owns_fields(own,function()return true end,read),true,owned_view,stock,signatures.accept,other_source),'Queue continuity must not relax the actual foreign-writer guard')
assert(camera.select_observed_view({stock,owned_view},signatures.accept)==owned_view and not camera.owns_fields(own,function()return true end,read),'A matching queued view must never excuse a foreign write to the owned source')
local ok,reason=camera.restore_owned(baseline,own,function()return true end,read,write)
assert(ok and reason=='foreign writer preserved'and actual.distance==2 and actual.region==7 and count==1,'Handoff must restore only still-owned fields and preserve a foreign writer without trapping source release')
count=0;ok,reason=camera.restore_owned(baseline,own,function()return false end,read,write)
assert(ok and reason=='retired'and count==0,'Retired world/profile memory must never be written during release')
assert(camera.select_observed_view({stock,owned_view},signatures.accept)==owned_view and not camera.owns_fields(own,function()return false end,read),'A matching queued view must never excuse retired profile ownership')
assert(not camera.retain_lens_source(camera.owns_fields(own,function()return false end,read),true,nil,stock,signatures.accept,other_source),'Empty-queue continuity must not relax actual profile retirement')
local weak=setmetatable({},{__mode='v'})
do
 local w={address=20,native=120,provider=220};local c={address=320,id=420};weak[1],weak[2]=w,c;cache.request(w,c)
end
collectgarbage();assert(weak[1]and weak[2],'Pending observations must keep only their exact camera/world references alive')
cache.clear();collectgarbage();collectgarbage();assert(not weak[1]and not weak[2],'Cleanup must release the pending Lua world/camera references')
print('Native cold-start observation: real after-render ordering, copied exact-camera values, return/error preservation, TTL/generation rejection and reference cleanup passed')

-- Mission render views can use materialized parameter instances. Their instance
-- identifier is part of ownership, not a requirement to equal zero.
local observed={distance=1.9,region=400,close_distance=1,close_region=3}
local instance_row={entity=292,class=0xf7a3101f,instance=65}
local snapshot=camera.profile_owner_snapshot(instance_row.entity,instance_row.class,instance_row.instance)
local instance_values={distance=1.9,region=400,close_distance=1,close_region=3}
local instance_writes=0
local instance_profile={fields=instance_values,owner=snapshot}
function instance_profile.valid()return camera.same_profile_owner(snapshot,instance_row.entity,instance_row.class,instance_row.instance)end
function instance_profile.write(name,value)assert(instance_profile.valid(),'Native profile ownership retired');instance_writes=instance_writes+1;instance_values[name]=value end
local primary={owner=camera.profile_owner_snapshot(108,0xf7a3101f,0),fields={distance=.2,region=.4296,close_distance=.2,close_region=.1}}
assert(camera.select_lens_source(observed,{primary,instance_profile})==instance_profile,'Exact queued view must acquire the materialized instance 65 rather than reject all nonzero instances')
instance_profile.write('distance',1.4);instance_profile.write('close_distance',1.4)
assert(instance_writes==2 and instance_values.distance==1.4 and instance_values.close_distance==1.4,'Same-instance reuse must retain its owned setter route')
instance_row.instance=66
local changed=pcall(instance_profile.write,'distance',2)
assert(not changed and instance_writes==2,'Recycling an instance at the same entity/class must retire it before any further setter write')
local cleanup_writes=0
local done,reason=camera.restore_owned({distance=1.9},{distance=1.4},instance_profile.valid,function(name)return instance_values[name]end,function()cleanup_writes=cleanup_writes+1 end)
assert(done and reason=='retired'and cleanup_writes==0,'Retired instance cleanup must not overwrite a new owner')
assert(not camera.same_profile_owner(snapshot,293,instance_row.class,65)and not camera.same_profile_owner(snapshot,292,0,65),'Entity and class guards remain exact')
instance_row.instance=65;assert(instance_profile.valid(),'The originally captured instance still satisfies the same owner guard')
assert(camera.select_lens_source(primary.fields,{primary})==primary,'Non-instanced primary row remains supported')
assert(not pcall(camera.select_lens_source,primary.fields,{primary,{fields=primary.fields}}),'An instanced-source fix must not remove unique-source ambiguity rejection')
assert(not pcall(camera.select_lens_source,{distance=1.9,region=400,close_distance=1},{instance_profile}),'Incomplete observed fields must not select a partial match')
for _,bad in ipairs({-1,65.5,4294967295})do assert(not pcall(camera.profile_owner_snapshot,292,0xf7a3101f,bad),'Invalid instance identifier accepted')end
assert(not pcall(camera.profile_owner_snapshot,0,0xf7a3101f,65),'Entity-zero default rows are not writable owners')
print('Native parameter instances: exact row acquisition, owned reuse, recycled-instance retirement/no-write cleanup, primary rows, complete observation and ambiguity guards passed')

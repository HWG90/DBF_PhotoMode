local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'subject_poses.lua')
local function fixture()
 local x={identity='local:1',paused=true,time=0,delta=0,frame_reads=0,captures=0,applies=0,restores=0,writes=0,logs={},units={}}
 local function unit()return{bones={10,20},mode='position_and_rotation',component={}}end
 x.units[x.identity]=unit()
 local A={}
 function A.frame()
  x.frame_reads=x.frame_reads+1
  assert(not x.frame_error,'Transient frame read failed')
  local u=x.units[x.identity];assert(u and not u.retired,'Local subject unavailable')
  return{identity=x.identity,root_handle=u,component=u.component}
 end
 function A.valid(f,require_owner)
  if x.read_error then return nil,'Transient ownership read failed'end
  local u=f.root_handle
  if u.retired or u.component~=f.component then return false end
  if require_owner and f.identity~=x.identity then return false end
  return true
 end
 function A.prepare(id)assert(not x.prepare_error,'Pose decode failed');assert(id=='salute'or id=='wave'or id=='taunt')end
 function A.capture(f)
  assert(A.valid(f,true)==true);assert(not x.capture_error,'Snapshot failed');x.captures=x.captures+1
  local u=f.root_handle;return{frame=f,original={u.bones[1],u.bones[2]},mode=u.mode}
 end
 function A.apply(lease,id)
  assert(A.valid(lease.frame,true)==true and x.paused,'Unsafe fixed pose application')
  x.applies=x.applies+1;local u=lease.frame.root_handle;u.mode='ignore';x.writes=x.writes+1
  local base=({salute=100,wave=200,taunt=300})[id]
  u.bones[1]=base+1;x.writes=x.writes+1
  if x.apply_error then error('Partial pose application failed')end
  u.bones[2]=base+2;x.writes=x.writes+1
 end
 function A.restore(lease)
  assert(A.valid(lease.frame,false)==true,'Unsafe fixed pose restoration')
  x.restores=x.restores+1;local u=lease.frame.root_handle
  u.bones[1]=lease.original[1];x.writes=x.writes+1
  if x.restore_error then error('Partial pose restoration failed')end
  u.bones[2]=lease.original[2];u.mode=lease.mode;x.writes=x.writes+2
 end
 x.api=M.new({},nil,function()if x.pause_error then error('Pause read failed')end;return x.paused end,function(s)x.logs[#x.logs+1]=s end,nil,A)
 x.add=function(id)x.units[id]=unit();return x.units[id]end
 x.unit=function()return x.units[x.identity]end
 assert(x.api.refresh(.5));return x
end
local function selected(x,id)assert(x.api.queue(id));assert(x.api.flush());assert(x.api.current()==id and x.api.active and not x.api.pending)end
local function original(u)assert(u.bones[1]==10 and u.bones[2]==20 and u.mode=='position_and_rotation','Original snapshot was not restored')end

do
 local x=fixture();x.paused=false
 assert(not x.api.refresh(.5)and not x.api.queue('salute'),'Unpaused catalog remained available')
 x.paused=true
 assert(x.api.refresh(0)and x.api.capabilities.salute,'Paused catalog stayed locked because game delta stopped')
 assert(x.api.queue('salute')and x.writes==0);assert(x.api.flush()and x.api.active)
 assert(x.time==0 and x.delta==0,'Availability refresh advanced game time')
 assert(x.api.release());assert(x.api.flush());original(x.unit())
 x.paused=false
 assert(not x.api.refresh(0)and not x.api.queue('wave'),'Zero-delta unpause retained stale pose availability')
end

do
 local x=fixture();x.frame_error=true
 assert(not x.api.refresh(.5,10)and not x.api.queue('salute'),'Failed owner read retained an actionable pose')
 local before=x.frame_reads;x.frame_error=false
 assert(not x.api.refresh(0,10.25)and x.frame_reads==before,'Owner retry ignored the real-time cadence')
 assert(x.api.refresh(0,10.5)and x.api.capabilities.wave,'Paused owner recovery waited for simulation time')
 assert(x.frame_reads==before+1 and x.writes==0 and x.time==0 and x.delta==0,'Availability retry mutated the scene')
 assert(x.api.queue('wave'));assert(x.api.flush());assert(x.api.release());assert(x.api.flush());original(x.unit())
end

do
 local x=fixture();x.frame_error=true;assert(not x.api.refresh(.5))
 local before=x.frame_reads;x.frame_error=false;local recovered=false
 for _=1,30 do if x.api.refresh(0)then recovered=true;break end end
 assert(recovered and x.api.capabilities.salute,'Clockless paused owner recovery starved beyond 30 refreshes')
 assert(x.frame_reads==before+1 and x.writes==0,'Clockless owner retry performed extra reads or writes')
end

do
 local x=fixture();x.frame_error=true;assert(not x.api.refresh(.5,20))
 x.frame_error=false;local before=x.frame_reads
 assert(x.api.refresh(0,19)and x.frame_reads==before+1,'Clock rollback left pose availability stale')
 assert(x.writes==0 and x.time==0 and x.delta==0)
end

for _,invalid_clock in ipairs({0/0,math.huge,-math.huge,'not-a-clock'})do
 local x=fixture();x.frame_error=true;assert(not x.api.refresh(.5,20))
 local before=x.frame_reads;x.frame_error=false;local recovered=false
 for _=1,30 do if x.api.refresh(0,invalid_clock)then recovered=true;break end end
 assert(recovered and x.api.capabilities.taunt,'Invalid input clock prevented bounded paused recovery')
 assert(x.frame_reads==before+1 and x.writes==0,'Invalid clock caused extra owner reads or scene writes')
end

do
 local x=fixture();assert(#M.catalog==3 and x.api.capabilities.salute and x.api.capabilities.wave and x.api.capabilities.taunt)
 assert(not x.api.queue('victory'),'Guessed pose accepted')
 assert(x.api.queue('salute')and x.writes==0);assert(x.api.after_update()and x.writes==0 and x.api.pending,'After-update hook consumed a menu request')
 assert(x.api.flush()and x.unit().bones[1]==101 and x.unit().mode=='ignore')
 assert(x.time==0 and x.delta==0 and x.paused,'Selecting a fixed pose advanced time')
 x.unit().bones[1]=-999;x.unit().bones[2]=-888
 assert(x.api.after_update()and x.unit().bones[1]==101 and x.unit().bones[2]==102,'Engine update overwrote held pose')
 selected(x,'wave');assert(x.unit().bones[1]==201 and x.captures==1,'Switch captured the already-posed skeleton')
 selected(x,'taunt');assert(x.unit().bones[1]==301 and x.captures==1)
 local before=x.writes;assert(x.api.queue_stop()and x.writes==before and x.api.pending)
 assert(x.api.flush()and not x.api.active and not x.api.pending);original(x.unit())
 assert(x.api.flush()and x.api.after_update()and x.writes==before+3,'Idle callbacks kept mutating bones')
end
do
 local x=fixture();selected(x,'salute');x.paused=false
 assert(x.api.after_update()and not x.api.active and not x.api.pending);original(x.unit())
 assert(not x.api.refresh(.5)and not x.api.queue('wave'),'Unpaused scene accepted a pose')
 x.paused=true;assert(x.api.refresh(.5));selected(x,'wave');local before=x.writes
 assert(x.api.release()and x.api.pending and x.api.active and x.writes==before,'Photo close performed synchronous writes')
 assert(x.api.flush()and not x.api.active);original(x.unit())
end
for _,retired in ipairs({'root','component'})do
 local x=fixture();selected(x,'salute');local before=x.writes
 if retired=='root'then x.unit().retired=true else x.unit().component={}end
 assert(x.api.flush()and not x.api.active and not x.api.pending and x.writes==before,'Retired '..retired..' received a bone/mode write')
end
do
 local x=fixture();selected(x,'salute');local before=x.writes;x.read_error=true
 assert(not x.api.after_update()and x.api.active and x.api.pending and x.api.current()=='salute'and x.writes==before,'Unknown read failure dropped lease or wrote')
 assert(not x.api.flush()and x.writes==before,'Unknown cleanup read failure wrote')
 x.read_error=false;assert(x.api.flush()and not x.api.active);original(x.unit())
end
do
 local x=fixture();x.apply_error=true;assert(x.api.queue('wave'));assert(not x.api.flush())
 assert(x.api.active and x.api.pending and x.api.current()=='wave'and x.unit().mode=='ignore'and x.unit().bones[1]==201 and x.unit().bones[2]==20,'Partial apply lost original lease')
 x.apply_error=false;x.restore_error=true;assert(not x.api.flush())
 assert(x.api.active and x.api.pending and x.unit().mode=='ignore','Partial restore discarded mode restoration')
 x.restore_error=false;assert(x.api.flush()and not x.api.active);original(x.unit());assert(x.captures==1)
end
do
 local x=fixture();selected(x,'salute');x.pause_error=true;local before=x.writes
 assert(not x.api.flush()and x.api.active and x.api.pending and x.writes==before,'Unknown pause state wrote a pose')
 -- A queued restore does not need a functioning pause reader.
 assert(x.api.flush()and not x.api.active);original(x.unit())
end
for _,failure in ipairs({'frame_error','prepare_error','capture_error'})do
 local x=fixture();assert(x.api.queue('wave'));x[failure]=true
 assert(not x.api.flush()and not x.api.active and not x.api.pending and x.writes==0,'Pre-write '..failure..' retained invalid ownership')
end
do
 local x=fixture();assert(x.api.queue('wave'));assert(x.api.queue_stop());assert(x.api.flush()and x.writes==0 and not x.api.pending,'Canceled menu request applied')
 assert(x.api.queue('wave'));assert(x.api.release());assert(x.api.after_update()and x.writes==0,'Closed queued pose still applied')
 assert(x.api.refresh(.5))
 assert(x.api.queue('wave'));x.identity='local:2';x.add(x.identity)
 assert(not x.api.flush()and x.writes==0 and not x.api.pending,'Queued pose followed a replacement subject')
end
do
 local x=fixture();selected(x,'salute');local old=x.unit();x.identity='local:2';local new=x.add(x.identity)
 assert(x.api.refresh(.5));assert(x.api.queue('taunt'));assert(x.api.flush(),'Restoring old owner cleared queued replacement pose ID')
 original(old);assert(new.bones[1]==301 and x.api.current()=='taunt'and x.captures==2)
 assert(x.api.queue_stop());assert(x.api.flush());original(new)
end
do
 local x=fixture();selected(x,'salute');local old=x.unit();x.identity='local:2';x.add(x.identity)
 assert(x.api.after_update()and not x.api.active,'Ownership loss kept applying a held pose');original(old);original(x.unit())
end

-- Closing releases every native lease but remembers only the selected ID.
-- Reopening requires a fresh supported local frame and a real paused edge.
do
 local x=fixture();selected(x,'wave');local old=x.unit();local before=x.writes
 assert(x.api.remembered()=='wave'and x.api.release()and x.writes==before,'Close forgot selection or wrote from a callback')
 assert(not x.api.queue('taunt'),'Closed service retained an actionable cached subject')
 assert(x.api.flush()and not x.api.active and not x.api.pending);original(old)
 assert(x.api.current()==nil and x.api.remembered()=='wave'and x.api.status:find('Wave remembered',1,true),'Released pose was not reported as remembered')
 x.paused=false;local reads=x.frame_reads
 for i=1,5 do assert(not x.api.refresh(.5,i)and x.api.flush()and x.api.after_update())end
 assert(x.frame_reads==reads and x.writes==before+3,'Closed service retained or queried native subject state')
 old.retired=true;x.identity='local:2';local new=x.add(x.identity);x.paused=true
 before=x.writes;assert(x.api.refresh(0,6)and x.api.pending and not x.api.active and x.writes==before,'Reopen did not queue against a fresh subject')
 assert(x.api.after_update()and x.writes==before,'Reopen applied a request from the wrong hook')
 assert(x.api.flush()and x.api.current()=='wave'and new.bones[1]==201 and x.captures==2)
 for i=7,12 do assert(x.api.refresh(.5,i)and x.api.flush()and x.api.after_update())end
 assert(x.captures==2 and x.api.current()=='wave','Refresh repeatedly recaptured a remembered pose')
 assert(x.api.queue_stop()and x.api.remembered()==nil);assert(x.api.flush());original(new)
 x.paused=false;assert(not x.api.refresh(.5,13));x.paused=true;assert(x.api.refresh(0,14))
 assert(not x.api.pending and x.api.flush()and not x.api.active and x.captures==2,'Explicit Reset reapplied a forgotten pose')
end

do
 local x=fixture();selected(x,'salute');assert(x.api.release()and x.api.flush())
 x.paused=false;assert(not x.api.refresh(.5,10));x.paused=true;x.frame_error=true
 assert(not x.api.refresh(0,11)and not x.api.pending,'Unavailable reopen queued a stale frame')
 local reads=x.frame_reads;x.frame_error=false
 assert(not x.api.refresh(0,11.25)and x.frame_reads==reads,'Reopen bypassed bounded reader retries')
 assert(x.api.refresh(0,11.5)and x.api.pending and x.api.remembered()=='salute')
 assert(x.api.flush()and x.api.current()=='salute'and x.captures==2,'Remembered pose did not recover after the reader became available')
end

do
 local x=fixture();selected(x,'wave');assert(x.api.release());x.paused=false;assert(not x.api.refresh(.5,10))
 x.paused=true;assert(x.api.refresh(0,11)and x.api.active and x.captures==1)
 assert(x.api.flush()and not x.api.active);original(x.unit())
 assert(x.api.refresh(0,11.1)and x.api.pending and x.api.flush()and x.api.current()=='wave'and x.captures==2,'A clean pending release lost the reopen request')
end

do
 local x=fixture();selected(x,'salute');assert(x.api.release()and x.api.flush())
 x.paused=false;assert(not x.api.refresh(.5,10));x.paused=true;x.frame_error=true;assert(not x.api.refresh(0,11))
 assert(x.api.queue_stop()and x.api.remembered()==nil)
 x.frame_error=false;assert(x.api.refresh(.5,12)and x.api.flush()and not x.api.active and not x.api.pending and x.captures==1,'Reset failed to cancel a deferred remembered pose')
end

do
 local x=fixture();selected(x,'taunt');assert(x.api.release());x.restore_error=true
 assert(not x.api.flush()and x.api.active and x.api.pending,'Close lost incomplete restoration')
 x.paused=false;assert(not x.api.refresh(.5,10));x.paused=true;assert(x.api.refresh(0,11))
 assert(x.api.current()=='taunt'and x.captures==1,'Reopen recaptured before the previous cleanup completed')
 assert(not x.api.flush()and x.api.active and x.api.pending,'Reopen dropped a still-failing cleanup')
 x.restore_error=false;assert(x.api.flush()and not x.api.active);original(x.unit())
 assert(x.api.refresh(.5,12)and not x.api.pending and x.api.flush()and x.captures==1,'Failed cleanup silently rearmed repeated pose applications')
 -- A later close/reopen may deliberately try the remembered pose again.
 assert(x.api.release());x.paused=false;assert(not x.api.refresh(.5,13));x.paused=true
 assert(x.api.refresh(0,14)and x.api.pending and x.api.flush()and x.captures==2)
end

for _,failure in ipairs({'prepare_error','capture_error','apply_error'})do
 local x=fixture();selected(x,'wave');assert(x.api.release()and x.api.flush())
 x.paused=false;assert(not x.api.refresh(.5,10));x.paused=true
 assert(x.api.refresh(0,11)and x.api.pending);x[failure]=true;assert(not x.api.flush())
 x[failure]=false;assert(x.api.flush());original(x.unit())
 local captures=x.captures;local writes=x.writes
 for i=12,17 do assert(x.api.refresh(.5,i)and x.api.flush()and x.api.after_update())end
 assert(not x.api.active and not x.api.pending and x.captures==captures and x.writes==writes and x.api.remembered()=='wave','Failed resume repeatedly reapplied '..failure)
 assert(x.api.queue_stop()and x.api.remembered()==nil)
end

do
 local x=fixture();selected(x,'salute');assert(x.api.release()and x.api.flush())
 x.paused=false;assert(not x.api.refresh(.5,10));x.paused=true;assert(x.api.refresh(0,11)and x.api.pending)
 x.identity='local:2';local new=x.add(x.identity);local before=x.writes
 assert(not x.api.flush()and x.writes==before and not x.api.pending,'Remembered request followed an identity change while paused')
 assert(x.api.refresh(.5,12)and x.api.flush()and not x.api.active and x.captures==1,'Identity failure repeatedly resumed against a replacement player')
 original(new);assert(x.api.remembered()=='salute','Identity failure forgot the session selection')
end

-- Real public-API adapter: exact node range, immutable capture, zero-time
-- writes, mapping guards, and component invalidation.
do
 local data=dofile(root..'assets/subject_pose_frames.lua');local unit={};local world={};local alive=true;local mode='position_and_rotation';local values={};local writes={};local updates=0;local bad_parent=false
 for i=1,107 do values[i]={tag=i}end
 local function clone(t)local c={};for k,v in pairs(t)do c[k]=type(v)=='table'and clone(v)or v end;return c end
 local sr={Unit={},World={update_unit=function(w,u)assert(w==world and u==unit);updates=updates+1 end},
  Vector3=function(x,y,z)return{x,y,z}end,Quaternion={axis_angle=function(axis,angle)return{axis=axis,angle=angle}end},
  Matrix4x4={from_quaternion_position=function(q,p)return{q=q,p=p}end},
  Matrix4x4Box=function(value)local saved=clone(value);return{unbox=function()return clone(saved)end}end}
 local U=sr.Unit
 U.num_scene_graph_items=function(u)assert(u==unit);return 107 end
 U.scene_graph_parent=function(u,i)assert(u==unit);return bad_parent and i==10 and 5 or data.rig.nodes[i].parent end
 U.has_node=function(u,name)assert(u==unit);for _,n in ipairs(data.rig.nodes)do if n.name==name then return true end end;return false end
 U.node=function(u,name)assert(u==unit);for i,n in ipairs(data.rig.nodes)do if n.name==name then return i end end end
 U.local_pose=function(u,i)assert(u==unit);return values[i]end
 U.set_local_pose=function(u,i,v)assert(u==unit and alive);writes[#writes+1]=i;values[i]=clone(v)end
 U.animation_bone_mode=function(u)assert(u==unit);return mode end
 U.set_animation_bone_mode=function(u,m)assert(u==unit and alive);mode=m end
 local subject={pose_frame=function()return{local_owner=true,identity='native:1',root_handle=unit,world=world}end,pose_valid=function()return alive end}
 local a=M.native(sr,subject,data);local frame=a.frame();bad_parent=true;assert(not pcall(a.capture,frame)and#writes==0,'Changed bone parent accepted');bad_parent=false
 local lease=a.capture(frame);a.prepare('wave');a.apply(lease,'wave');assert(mode=='ignore'and#writes==85 and updates==1)
 for _,i in ipairs(writes)do assert(i>=8 and i<=92,'Placement/gameplay node mutated')end
 for _,i in ipairs({1,2,5,8,93,107})do assert(values[i].tag==i,'Root/boss/collision anchor changed')end
 data.poses.taunt.full_body=true;a.apply(lease,'taunt');assert(values[8].tag==nil,'Full-body pose kept the old body orientation');a.apply(lease,'salute');assert(values[8].tag==8,'Switching back failed to restore the original body anchor');a.restore(lease);assert(mode=='position_and_rotation'and updates==4);data.poses.taunt.full_body=nil
 for i=1,107 do assert(values[i].tag==i,'Original native pose snapshot was overwritten')end
 -- Exercise every actual generated entry through the service and native
 -- adapter, including transitions between upper-body and full-body samples.
 -- A catalog count alone cannot establish that its frames are usable.
 local Options=dofile(root..'photo_options.lua');assert(Options.set_subject_poses(data.catalog))
 local phase='menu';local set_pose,set_mode=U.set_local_pose,U.set_animation_bone_mode
 U.set_local_pose=function(...)assert(phase=='update','Catalog bone write escaped the update');return set_pose(...)end
 U.set_animation_bone_mode=function(...)assert(phase=='update','Catalog mode write escaped the update');return set_mode(...)end
 local service=M.new(sr,subject,function()return true end,nil,data)
 assert(service.refresh(.5)and service.catalog==data.catalog)
 local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
 local function anchors()
  for i=1,107 do if i<8 or i>92 then assert(values[i].tag==i,'Catalog entry changed placement, collision or attachment anchor '..i)end end
 end
 local function apply_entry(entry)
  assert(service.refresh(.5))
  local source=assert(data.poses[entry.id],'Catalog entry has no frame')
  assert(source.label==entry.label and finite(source.time)and finite(source.duration)and source.time>=0 and source.time<=source.duration,'Catalog metadata and sampled clip disagree')
  assert(#source.nodes==107,'Incomplete sampled skeleton')
  for i=1,107 do
   local node=source.nodes[i]
   assert(#node.p==3 and#node.q==4 and#node.s==3,'Malformed sampled transform')
   for _,field in ipairs({'p','q','s'})do for _,v in ipairs(node[field])do assert(finite(v),'Nonfinite '..entry.id..' transform '..i)end end
   local norm=0;for _,v in ipairs(node.q)do norm=norm+v*v end
   assert(math.abs(norm-1)<.0001,'Nonunit sampled rotation '..entry.id..' node '..i)
  end
  local before=#writes;phase='menu'
  assert(service.capabilities[entry.id]and service.queue(entry.id)and#writes==before,'Selection wrote bones or rejected a catalog entry')
  phase='update';assert(service.flush(),entry.id..' could not apply')
  assert(service.current()==entry.id and service.active and not service.pending and mode=='ignore','Catalog selection did not hold the requested pose')
  anchors()
  for i=8,92 do
   if i==8 and not source.full_body then assert(values[i].tag==i,'Upper-body pose failed to restore body anchor')
   else
    for axis=1,3 do assert(math.abs(values[i].p[axis]-source.nodes[i].p[axis])<1e-7,'Selected entry applied a different frame')end
    assert(finite(values[i].q.angle),'Native rotation conversion produced a nonfinite angle')
   end
  end
  assert(service.after_update()and service.current()==entry.id,'Catalog entry could not remain held')
 end
 for _,entry in ipairs(data.catalog)do apply_entry(entry)end
 -- Reverse switching exercises returning from later full-body frames to the
 -- original upper-body entries without recapturing an already-posed snapshot.
 for index=#data.catalog,1,-1 do apply_entry(data.catalog[index])end
 phase='menu';local before=#writes;assert(service.queue_stop()and#writes==before,'Reset wrote from the menu')
 phase='update';assert(service.flush()and not service.active and not service.pending and mode=='position_and_rotation')
 for i=1,107 do assert(values[i].tag==i,'Catalog switching lost the original transform '..i)end
 -- A fresh capture/reset for each frame also checks the standalone selection
 -- path that users take when returning to the menu between photos.
 for _,entry in ipairs(data.catalog)do
  apply_entry(entry);phase='menu';assert(service.release());phase='update';assert(service.flush())
  for i=1,107 do assert(values[i].tag==i,'Catalog entry did not restore independently: '..entry.id)end
 end
 print('Generated pose catalog: '..#data.catalog..' real entries validated, selected, held, switched both ways and independently restored; all scene anchors retained')
 U.set_local_pose,U.set_animation_bone_mode=set_pose,set_mode
 alive=false;local before=#writes;assert(not pcall(a.apply,lease,'salute')and not pcall(a.restore,lease)and#writes==before,'Stale native component received writes')
end
print('Fixed subject poses: session ID memory, fresh close/reopen, deferred reader recovery, no failed-apply loop, explicit Reset, cleanup/identity guards, zero-time selection/hold and real native adapter guards passed')

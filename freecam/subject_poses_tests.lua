local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'subject_poses.lua')
local function fixture()
 local x={identity='local:1',paused=true,time=0,delta=0,captures=0,applies=0,restores=0,writes=0,logs={},units={}}
 local function unit()return{bones={10,20},mode='position_and_rotation',component={}}end
 x.units[x.identity]=unit()
 local A={}
 function A.frame()
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
 local lease=a.capture(frame);a.prepare('wave');a.apply(lease,'wave');assert(mode=='ignore'and#writes==84 and updates==1)
 for _,i in ipairs(writes)do assert(i>=9 and i<=92,'Placement/gameplay node mutated')end
 for _,i in ipairs({1,2,5,8,93,107})do assert(values[i].tag==i,'Root/boss/collision anchor changed')end
 a.apply(lease,'taunt');a.restore(lease);assert(mode=='position_and_rotation'and updates==3)
 for i=1,107 do assert(values[i].tag==i,'Original native pose snapshot was overwritten')end
 alive=false;local before=#writes;assert(not pcall(a.apply,lease,'salute')and not pcall(a.restore,lease)and#writes==before,'Stale native component received writes')
end
print('Fixed subject poses: zero-time selection/hold, original-snapshot switching, reset/exit/unpause, stale ownership, read/partial-write recovery, request cancellation and real native adapter guards passed')

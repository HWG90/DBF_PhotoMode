local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Ragdoll=dofile(root..'ragdoll_pause.lua')
local function copy(value)local out={};for key,item in pairs(value)do out[key]=item end;return out end
local function fixture()
 local f={alive=true,owner=true,ragdoll=true,mode='position_and_rotation',count=107,identity='subject:1',values={},writes={},reads=0,updates=0,frame_reads=0,logs={}}
 local unit,world={},{}
 for index=1,107 do f.values[index]={node=index,value=index*3}end
 local subject={}
 function subject.ragdoll_frame()
  f.frame_reads=f.frame_reads+1;assert(not f.frame_failure,'Ragdoll reader unavailable')
  return{local_owner=true,identity=f.identity,root_handle=unit,world=world,ragdoll_active=f.ragdoll}
 end
 function subject.pose_valid(frame,owned)
  if f.unknown then return nil,'Ownership read unavailable'end
  return f.alive and frame.identity==f.identity and(not owned or f.owner)
 end
 local function live(u)assert(u==unit and f.alive and not f.unknown,'Retired/unknown Unit dereferenced')end
 local sr={Unit={},World={},Matrix4x4Box=function(value)
  local saved=copy(value);return{unbox=function()return copy(saved)end}
 end}
 function sr.Unit.num_scene_graph_items(u)live(u);return f.count end
 function sr.Unit.local_pose(u,index)live(u);f.reads=f.reads+1;assert(index~=f.capture_failure,'Capture failed');return f.values[index]end
 function sr.Unit.animation_bone_mode(u)live(u);return f.mode end
 function sr.Unit.set_animation_bone_mode(u,value)
  live(u);f.writes[#f.writes+1]={kind='mode',value=value}
  if value==f.mode_refusal then return false end
  f.mode=value
  if value=='ignore'and f.acquire_failure then error('Partial bone-mode acquisition')end
  if value~='ignore'and f.restore_failure then error('Partial bone-mode restoration')end
 end
 function sr.Unit.set_local_pose(u,index,value)
  live(u);assert(f.owner and f.mode=='ignore','Pose write escaped owned bone transfer')
  assert(index~=f.pose_failure,'Pose write failed');f.writes[#f.writes+1]={kind='pose',index=index};f.values[index]=copy(value)
 end
 function sr.World.update_unit(w,u)live(u);assert(w==world);f.updates=f.updates+1;assert(not f.update_failure,'Render update failed')end
 f.adapter=Ragdoll.native(sr,subject);f.manager=Ragdoll.new(f.adapter,function(message)f.logs[#f.logs+1]=message end)
 return f
end
local function poses(f)local count=0;for _,write in ipairs(f.writes)do if write.kind=='pose'then count=count+1 end end;return count end
local f=fixture();assert(f.manager.flush(false,false)and f.frame_reads==0 and #f.writes==0)
f.ragdoll=false;assert(f.manager.flush(true,false)and f.reads==0 and #f.writes==0 and not f.manager.active)
f.ragdoll=true;assert(f.manager.flush(true,false)and f.manager.active and not f.manager.pending and f.mode=='ignore')
assert(f.reads==107 and poses(f)==107 and f.updates==1,'Capture/apply must include every one of the 107 scene nodes')
for index=1,107 do f.values[index].value=-index end
assert(f.manager.flush(true,false)and f.reads==107 and poses(f)==214 and f.updates==2)
for index=1,107 do assert(f.values[index].value==index*3,'Held snapshot retained transient native matrix storage')end
for index=1,107 do f.values[index].value=999 end
local before=poses(f);local updates=f.updates
assert(f.manager.release()and not f.manager.active and not f.manager.pending and f.mode=='position_and_rotation')
assert(poses(f)==before and f.updates==updates,'Resume must restore only bone mode, never an old pose/world transform')
for index=1,107 do assert(f.values[index].value==999,'Resume rewound a live transform')end

-- Fixed authored poses win before acquisition and can take over after cleanup.
f=fixture();assert(f.manager.flush(true,true)and #f.writes==0 and f.frame_reads==0)
assert(f.manager.flush(true,false));before=poses(f)
assert(f.manager.flush(true,true)and not f.manager.active and f.mode=='position_and_rotation'and poses(f)==before)
f.mode='ignore';assert(not f.manager.flush(true,false)and #f.writes==before+2 and not f.manager.active,'A pre-existing ignore mode must never be adopted')

-- Retired generations never reach even a mode getter; unknown generations
-- retain a retryable lease and do not mutate while their identity is unreadable.
f=fixture();assert(f.manager.flush(true,false));f.alive=false;before=#f.writes
assert(f.manager.release()and #f.writes==before and not f.manager.active)
f=fixture();assert(f.manager.flush(true,false));f.unknown=true;before=#f.writes
assert(not f.manager.release()and f.manager.active and f.manager.pending and #f.writes==before)
assert(not f.manager.flush(true,false)and #f.writes==before)
f.unknown=false;assert(f.manager.release()and f.mode=='position_and_rotation'and not f.manager.pending)
f=fixture();assert(f.manager.flush(true,false));f.identity='subject:2';before=#f.writes
assert(f.manager.flush(true,false)and not f.manager.active and #f.writes==before,'A replacement avatar inherited the previous ragdoll snapshot')

-- A live new bone-mode writer retains its mode. Lost local ownership never
-- receives further pose writes; cleanup can only CAS the old transfer mode.
f=fixture();assert(f.manager.flush(true,false));f.mode='rotation';before=#f.writes
assert(not f.manager.flush(true,false)and not f.manager.active and f.mode=='rotation'and #f.writes==before)
f=fixture();assert(f.manager.flush(true,false));f.owner=false;before=poses(f)
assert(f.manager.flush(true,false)and not f.manager.active and poses(f)==before and f.mode=='position_and_rotation')
f=fixture();assert(f.manager.flush(true,false));f.ragdoll=false;before=poses(f)
assert(f.manager.flush(true,false)and not f.manager.active and poses(f)==before)

-- No mutations are authorized until capture completes. A partial setter or
-- apply failure owns cleanup before the first write and retains failed cleanup.
f=fixture();f.capture_failure=12;assert(not f.manager.flush(true,false)and #f.writes==0 and not f.manager.active)
f.capture_failure=nil;assert(f.manager.flush(true,false));assert(f.manager.release())
f=fixture();f.count=108;assert(not f.manager.flush(true,false)and #f.writes==0 and not f.manager.active)
f=fixture();f.acquire_failure=true;f.mode_refusal='position_and_rotation'
assert(not f.manager.flush(true,false)and f.manager.active and f.manager.pending and f.mode=='ignore'and poses(f)==0)
f.acquire_failure=false;f.mode_refusal=nil;assert(f.manager.release()and f.mode=='position_and_rotation'and not f.manager.active)
f=fixture();f.pose_failure=14;assert(not f.manager.flush(true,false)and poses(f)==13 and not f.manager.active and f.mode=='position_and_rotation')
f=fixture();f.update_failure=true;assert(not f.manager.flush(true,false)and poses(f)==107 and not f.manager.active and f.mode=='position_and_rotation')
f=fixture();assert(f.manager.flush(true,false));f.restore_failure=true
assert(not f.manager.release()and f.manager.active and f.manager.pending and f.mode=='position_and_rotation')
before=#f.writes;f.restore_failure=false;assert(f.manager.release()and #f.writes==before,'Retry must accept an already-restored mode without another write')
f=fixture();assert(f.manager.flush(true,false));f.frame_failure=true;before=#f.writes
assert(not f.manager.flush(true,false)and f.manager.pending and f.manager.active and #f.writes==before)
f.frame_failure=false;assert(f.manager.flush(true,false)and not f.manager.active and f.mode=='position_and_rotation','Reader recovery must complete cleanup before reacquisition')
assert(f.manager.flush(true,false)and f.manager.active);assert(f.manager.flush(false,false)and not f.manager.active)
print('Ragdoll pause: copied 107-node observed frame, zero-time gate, fixed-pose yield, mode-only resume, generation/unknown/foreign ownership, partial capture/apply/cleanup failure and retry passed')

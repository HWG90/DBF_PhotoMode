-- Actual selected-subject controller, actual runtime/core/input/time policy;
-- engine mutation and qualification remain isolated dependency-injected doubles.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local base_fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local Subject=dofile('freecam/steam_subject.lua')
local bank;local wall=0;local original_clock=os.time;os.time=function()return wall end
local function copy(value)
 if type(value)~='table'then return value end
 local result={};for key,item in pairs(value)do result[key]=copy(item)end;return result
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not same(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end;return true
end
local function configure(f,deps,sr)
 f.sr=sr
 f.factories,f.subject_native,f.discoveries,f.snapshots,f.node_writes,f.mode_writes,f.commits,f.decodes,f.status_reads=0,0,0,0,0,0,0,0,0
 f.events={};f.subject_calls={};f.resolve=false
 local function event(value)f.events[#f.events+1]=value end
 local function target(id)
  local result={identity=id,label=id,resource='4d1c334d294dfa97',node_count=107,world=f.world,alive=true,mode='position_and_rotation',nodes={}}
  for i=1,107 do result.nodes[i]={p={i/10,2,3},q={0,0,0,1},s={1,1,1}}end
  return result
 end
 f.a,f.b=target('Helldiver A'),target('Helldiver B');f.original_a,f.original_b=copy(f.a.nodes),copy(f.b.nodes)
 local native_policy=sr.Application.set_time_step_policy
 sr.Application.set_time_step_policy=function(key,value)
  event('time:'..value);local result=native_policy(key,value)
  if value>0 and f.partial_resume then
   if f.partial_resume=='throw'then error('Fixture applied nonzero time before throwing')end
   return false
  end
  return result
 end
 local make_camera=deps.camera.new;deps.camera.new=function(...)
  local c=make_camera(...);local close=c.close;c.close=function()event('camera');return close()end;return c
 end
 local make_input=deps.input.new;deps.input.new=function(...)
  local i=make_input(...);local release=i.release;i.release=function()event('input');return release()end;return i
 end
 deps.path=dofile('freecam/steam_path.lua')
 deps.load_subject=function(native,is_frozen)
  assert(native==sr);f.factories=f.factories+1
  if f.factory_error then error('Fixture factory unavailable')end
  if not bank then bank=dofile('freecam/assets/steam_subject_poses.lua')end
  local data={version=bank.version,rig=bank.rig,catalog=bank.catalog,decode=function(id)
   f.decodes=f.decodes+1;local pose=assert(bank.decode(id))
   if f.partial then pose.nodes[13].p[2]=123 end
   return pose
  end}
  local function count()f.subject_native=f.subject_native+1 end
  local function valid(t)return t.alive and t.world==f.world end
  local adapter={version=1}
  local qualified_session=f.session
  adapter.session_current=function()f.session_checks=(f.session_checks or 0)+1;return f.session==qualified_session end
  adapter.discover=function(resource,limit,rig)
   count();f.discoveries=f.discoveries+1;assert(resource==data.rig.resource and limit==4 and rig==data.rig)
   if f.discovery_error then return nil,f.discovery_error end
   return f.sole and{f.b}or{f.a,f.b}
  end
  adapter.valid=function(t)count();if f.unknown then return nil,'Identity unavailable'end;return valid(t)end
  adapter.snapshot=function(t)
   count();f.snapshots=f.snapshots+1;assert(valid(t))
   return{identity=t.identity,resource=t.resource,node_count=107,mode=t.mode,nodes=t.nodes}
  end
  adapter.set_node=function(t,rig,index,expected,value,expected_mode)
   count();f.node_writes=f.node_writes+1;assert(valid(t)and rig==data.rig and index>=8 and index<=92)
   assert(t.mode==expected_mode and same(t.nodes[index],expected),'Fresh exact state must guard every write')
   if f.fail_node==index then
    t.nodes[index].p[1]=value.p[1]
    f.receipt={index=index,before=copy(expected),target=copy(value),current=copy(t.nodes[index]),mode=expected_mode}
    return false,'Fixture partial node write'
   end
   t.nodes[index]=copy(value)
   if f.receipt and f.receipt.index==index then f.receipt=nil end
   event('node:'..index);return true
  end
  adapter.set_mode=function(t,rig,expected,value)
   count();f.mode_writes=f.mode_writes+1;assert(valid(t)and rig==data.rig and t.mode==expected)
   if f.fail_mode then return false,'Fixture mode cleanup refused'end
   t.mode=value;if f.receipt then f.receipt.mode=value end
   event('mode:'..value);return true
  end
  adapter.resolve_node=function(t,_,index,before,value,current,expected_mode)
   count();local r=f.receipt
   if not f.resolve then return nil,'Component proof unavailable'end
   assert(r and r.index==index and r.mode==expected_mode and t.mode==expected_mode and
    same(r.before,before)and same(r.target,value)and same(r.current,current))
   return true
  end
  adapter.commit=function(t)
   count();f.commits=f.commits+1;assert(valid(t));event('commit')
   if f.commit_error then return false,f.commit_error end
   if f.foreign_commit then f.foreign_commit=false;sr.Application.set_time_step_policy('external_multiplier',.6)end
   return true
  end
  f.subject=Subject.new(adapter,data,is_frozen)
  for _,name in ipairs({'refresh','select','apply','reset','recover','close','resume','invalidate'})do
   local saved=f.subject[name];f.subject[name]=function(...)
    f.subject_calls[name]=(f.subject_calls[name]or 0)+1;return saved(...)
   end
  end
  local status=f.subject.status;f.subject.status=function()f.status_reads=f.status_reads+1;return status()end
  return f.subject
 end
end
local function fixture(extra)
 wall=0;local f=base_fixture(nil,function(f,deps,sr)configure(f,deps,sr);if extra then extra(f,deps,sr)end end);local step=f.step
 f.step=function(dt,renders)wall=f.time+(dt or .016);return step(dt,renders)end
 function f.action(id)return assert(f.controls[id],id).on_activate()end
 function f.enable()
  f.open();assert(f.factories==1)
  -- Opening lists the subjects once and selects one automatically.
  assert(f.subject.status().selected~=nil and f.discoveries==1,'Opening auto-selects a subject')
 end
 function f.select()
  local discoveries=f.discoveries
  assert(f.action('subject_refresh')and f.discoveries==discoveries+1)
  assert(f.subject.status().selected==nil and f.controls.subject_pose_play.disabled,'Refresh must never select a sole or first avatar')
  assert(f.action('subject_select_2'));assert(f.subject.status().selected=='Helldiver B')
 end
 function f.pose(index)
  local before=f.decodes
  assert(f.runtime.handle.set('subject_pose',index or 1))
  if f.decodes==before then assert(f.action('subject_pose_play'))end
  assert(f.subject.status().state=='posed')
 end
 function f.restored()
  assert(same(f.a.nodes,f.original_a),'Never mutate the unselected Helldiver')
  assert(same(f.b.nodes,f.original_b)and f.b.mode=='position_and_rotation','Restore the explicit subject baseline/mode')
 end
 function f.recovery_key()
  f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=true,true,true;f.step(.016)
 end
 return f
end
do
 local messages={}
 local f=fixture(function(f)f.discovery_error='Fixture inventory changed\nreason';f.log=function(s)messages[#messages+1]=s end end)
 f.open()
 for i=1,3 do assert(not f.action('subject_refresh'))end
 local function count()local n=0;for _,s in ipairs(messages)do if s=='Subject discovery detail: Fixture inventory changed reason'then n=n+1 end end;return n end
 assert(count()==1,'Repeated explicit failures log the same bounded reason only once')
 f.discovery_error=nil;assert(f.action('subject_refresh'))
 f.discovery_error='Fixture inventory changed\nreason';assert(not f.action('subject_refresh'))
 assert(count()==2,'A recovered discovery allows a subsequent failure to be diagnosed')
end
do
 -- Stop and Recover share generic pending messages; the log must name the refused check.
 local messages={}
 local f=fixture(function(f)f.log=function(s)messages[#messages+1]=s end end)
 f.enable();f.select();f.pose()
 f.commit_error='Subject changed during scene refresh\nnode 23'
 for i=1,3 do assert(not f.action('subject_pose_stop'))end
 local function count(line)local n=0;for _,s in ipairs(messages)do if s==line then n=n+1 end end;return n end
 assert(count('Subject reset detail: Subject changed during scene refresh node 23')==1,'A refused Stop names its check once')
 assert(count('Subject recover detail: Subject changed during scene refresh node 23')==1,'The automatic recovery names its check once')
 f.commit_error=nil;assert(f.action('subject_pose_stop'));f.restored()
end
local function index_of(events,value)
 for i,item in ipairs(events)do if item==value then return i end end
end
do
 local f=fixture(function(f,deps)
  f.root_held=false;f.root_renders=0
  deps.freeze_root_hold={tick=function(enabled)f.root_held=enabled end,
   render=function(enabled)if enabled then f.root_renders=f.root_renders+1 end end,
   release=function()f.root_held=false;return true end}
  local load=deps.load_subject
  deps.load_subject=function(...)
   local subject=load(...);local apply=subject.apply
   subject.apply=function(...)assert(not f.root_held,'Manual pose must release root hold before applying');return apply(...)end
   return subject
  end
 end)
 f.enable();f.select();f.step(.016,1);assert(f.root_held)
 f.pose(2);local renders=f.root_renders;f.step(.016,1)
 assert(not f.root_held and f.root_renders==renders,'Root hold yields while manual pose owns subject')
 assert(f.action('subject_pose_stop'));f.step(.016,1);assert(f.root_held,'Reset pose permits fresh root capture')
 f.finish();assert(not f.root_held)
end
do
 local f=fixture()
 for _=1,100 do f.step(.016)end
 assert(f.factories==0 and f.subject_native==0 and f.controls.subject_refresh.disabled==true)
 f.enable();assert(#f.controls.subject_pose.choices==213 and f.controls.subject_pose.choices_revision==f.subject.catalog)
 assert(f.controls.subject_preview==nil and f.controls.subject_select_3.disabled)
 f.select();local writes=f.node_writes
 assert(f.runtime.handle.set('subject_pose',2)and f.node_writes==writes and f.decodes==0,'Picking a pose never applies or decodes it')
 f.pose(2);local native,status,decodes=f.subject_native,f.status_reads,f.decodes
 for _=1,100 do f.step(.016,1)end
 assert(f.subject_native==native and f.status_reads==status and f.decodes==decodes,'Unchanged active posing has no subject update work')
 f.pose(3);assert(f.decodes==decodes+1);assert(f.action('subject_pose_stop'));f.restored()
 assert(f.subject.status().pose==nil);f.pose(1);assert(f.runtime.close(true));f.restored()
 assert(f.controls.subject_refresh.disabled and f.controls.subject_pose_play.disabled)
 f.finish()
 native,status=f.subject_native,f.status_reads;for _=1,100 do f.step(.016,1)end
 assert(f.subject_native==native and f.status_reads==status,'Closed subject controls remain idle')
 assert(f.runtime.close(true));f.finish()
end
do
 local f=fixture();f.enable();f.sole=true;assert(f.action('subject_refresh'))
 assert(f.controls.subject_select_1.button_label=='Select'and f.controls.subject_select_2.disabled and f.subject.status().selected==nil)
 assert(f.action('subject_select_1'));f.pose();f.events={}
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1);f.restored()
 assert(index_of(f.events,'mode:position_and_rotation')<index_of(f.events,'time:1'),'Resume restores the subject before nonzero time')
 assert(f.runtime.handle.set('freeze_player',true));local writes=f.node_writes;f.step(.016)
 assert(f.node_writes==writes and f.subject.status().pose==nil,'Refreeze never reapplies remembered pose')
 f.finish()
end
do
 local f=fixture();f.enable();f.select();f.pose();f.events={}
 assert(f.runtime.begin_shot());f.restored()
 assert(index_of(f.events,'mode:position_and_rotation')<index_of(f.events,'time:1')and
  index_of(f.events,'time:1')<index_of(f.events,'input'),'Action shot restores subject before time/input handoff')
 local writes=f.node_writes;assert(f.runtime.reposition_shot()and f.rate==0)
 assert(f.node_writes==writes and f.subject.status().pose==nil and not f.controls.subject_pose_play.disabled)
 assert(f.runtime.handle.activate('path_add'));assert(f.runtime.handle.activate('path_add'));f.pose()
 assert(f.runtime.begin_shot(true));f.restored();assert(f.runtime.reposition_shot());f.finish()
end
do
 local f=fixture();f.enable();f.select();f.partial=true;f.fail_node=13
 assert(not f.action('subject_pose_play')and f.controls.subject_recover.disabled==false)
 local writes=f.node_writes;f.events={};assert(not f.runtime.close(true))
 assert(not f.runtime.active and not f.camera_open and not f.lease and f.runtime.state=='closing'and f.rate==0)
 assert(f.b.mode=='position_and_rotation'and f.node_writes==writes and not index_of(f.events,'time:1'),
  'Unknown body never blocks camera/input/UI cleanup or guesses restoration before time resumes')
 local native,status,saves=f.subject_native,f.status_reads,f.saves
 for _=1,100 do f.step(.016)end
 assert(f.subject_native==native and f.status_reads==status and f.saves==saves and f.node_writes==writes,
  'Automatic pending close performs zero subject reads, writes, status polls or persistence')
 assert(not f.runtime.open());f.fail_node=nil;f.resolve=true;f.events={};f.recovery_key()
 assert(f.runtime.state=='closed'and f.rate==1 and not f.lease and not f.camera_open);f.restored()
 assert(not index_of(f.events,'camera')and not index_of(f.events,'input'),'Explicit recovery never repeats completed base cleanup')
 local recoveries=f.subject_calls.recover;native=f.subject_native
 for _=1,10 do f.step(.016)end
 assert(f.subject_calls.recover==recoveries and f.subject_native==native,'Held recovery keys cannot repeat partial cleanup')
 f.pressed['left ctrl'],f.pressed['left shift'],f.pressed.f10=false,false,false;f.step(.016)
 assert(f.runtime.open()and f.subject.status().selected~=nil and f.subject.status().pose==nil,
  'Reopening lists current subjects and auto-selects one; no stale pose survives exit')
 f.finish()
end
do
 local f=fixture();f.enable();f.select();f.partial=true;f.fail_node=13
 assert(not f.action('subject_pose_play'));local writes=f.node_writes
 assert(f.runtime.handle.set('freeze_player',false)and f.runtime.handle.get('freeze_player')and f.rate==0,
  'Refused resume keeps Freeze preference synchronized with true-zero state')
 assert(f.runtime.active and f.b.mode=='position_and_rotation'and f.node_writes==writes)
 local native=f.subject_native;assert(not f.runtime.begin_shot()and f.subject_native==native)
 f.fail_node=nil;f.resolve=true;assert(f.action('subject_recover'));f.restored()
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1,'Explicit cleanup invalidates cached time refusal immediately')
 f.finish()
end
for _,failure in ipairs({'false','throw'})do
 local f=fixture();f.enable();f.select();f.partial_resume=failure
 assert(f.rate==0 and not f.controls.subject_pose_play.disabled)
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1 and f.runtime.active,
  'A refused/throwing resume may already have applied positive native time')
 assert(f.controls.subject_pose_play.disabled,'Unconfirmed zero time disables Apply immediately, before another tick')
 local writes=f.node_writes
 assert(not f.action('subject_pose_play')and f.node_writes==writes,
  'The actual controller refuses every pose write without acknowledged owned zero time')
 f.partial_resume=nil;f.step(1.1);f.finish()
end

do
 local f=fixture();f.enable();f.select();local owned=f.sr.Application.set_time_step_policy
 local successor=function(...)return owned(...)end;f.sr.Application.set_time_step_policy=successor
 assert(f.runtime.handle.set('subject_pose',2)and f.controls.subject_pose_play.disabled,
  'A foreign setter binding invalidates owned zero without native reads')
 local writes=f.node_writes
 assert(not f.action('subject_pose_play')and f.node_writes==writes and f.sr.Application.set_time_step_policy==successor,
  'The actual controller preserves a foreign wrapper and performs zero pose writes')
 f.sr.Application.set_time_step_policy=owned;f.finish()
end

do
 local f=fixture();f.enable();f.select();f.pose();f.events={};f.foreground=false;f.step(1.1)
 assert(f.rate==0 and f.runtime.active,'Focus loss must preserve the frozen Photo Mode session')
 f.foreground=true;f.finish()
end
do
 local f=fixture();f.enable();f.select();f.pose();local writes=f.node_writes
 f.world={};f.step(1.1)
 assert(f.rate==1 and f.subject.status().state=='retired'and f.subject.status().restored==false and f.node_writes==writes,
  'Known world retirement clears the lease without guessed restoration or player identity')
 f.finish()
end
do
 local f=fixture();f.enable();f.select();f.pose()
 -- Freeze Action holds through a direct foreign policy write: true zero is
 -- submitted again once and the held pose survives until an explicit exit.
 f.sr.Application.set_time_step_policy('external_multiplier',.6);f.events={};f.step(.016)
 assert(f.rate==0 and f.subject.status().state=='posed','Freeze and the held pose survive a foreign time write')
 f.finish();f.restored();assert(f.rate==1)
end
do
 local f=fixture();f.enable();f.select();f.pose();f.events={};f.foreign_commit=true
 assert(f.runtime.handle.set('freeze_player',false));f.restored()
 assert(f.rate==.6 and not index_of(f.events,'time:1'),
  'A synchronous foreign takeover during subject cleanup must precede the saved time-policy write')
 f.finish();assert(f.rate==.6)
end
do
 local f=fixture();f.factory_error=true;f.open()
 assert(f.runtime.active and f.camera_open and f.lease and f.subject_native==0)
 assert(not f.controls.subject_refresh.disabled)
 f.factory_error=false;assert(f.action('subject_refresh')and f.factories==2 and f.discoveries==1)
 f.finish()
end
do
 wall=0;local f=base_fixture()
 assert(f.controls.subject_refresh==nil and f.controls.subject_pose.disabled and f.controls.subject_pose_play.disabled,
  'Absent optional factory preserves the current disabled subject controls')
 f.finish()
end
-- The real captured-keyboard adapter has no engine fallback after a refused
-- release. Only an explicit cleanup call may retry its retained lease.
for _,failure in ipairs({'nil','throw'})do
 local problem={kind='captured-release-'..failure}
 local f=fixture(function(f,deps,sr)
  f.release_calls,f.snapshot_calls,f.engine_reads=0,0,0
  local button=sr.Keyboard.button
  sr.Keyboard.button=function(...)f.engine_reads=f.engine_reads+1;return button(...)end
  local make_input=deps.input.new
  deps.input.new=function(native,service)
   local mask=('00331f08ffe1ff03feffff27fffffff7ff0003003f0000fc010000f804000000'):gsub('%x%x',
    function(hex)return string.char(tonumber(hex,16))end)
   local key_bytes={};for i=1,32 do key_bytes[i]=0 end
   for _,vk in ipairs({16,17,121})do local index=math.floor(vk/8)+1;key_bytes[index]=key_bytes[index]+2^(vk%8)end
   local key_chars={};for i=1,32 do key_chars[i]=string.char(key_bytes[i])end
   local chord=table.concat(key_chars)
   service.capabilities.keyboard=true;service.capabilities.keyboard_mask=mask
   local snapshot=service.snapshot
   service.snapshot=function(token)
    f.snapshot_calls=f.snapshot_calls+1;local raw=snapshot(token)
    raw.valid,raw.keyboard_state,raw.keyboard_active=true,2,true
    raw.keyboard_keys=f.physical_recovery and chord or string.rep('\0',32)
    raw.keyboard_mask,raw.keyboard_generation=mask,7;return raw
   end
   local release=service.release
   service.release=function(token)
    f.release_calls=f.release_calls+1
    if not f.release_ack then if failure=='throw'then error(problem,0)end;return nil,problem end
    return release(token)
   end
   return make_input(native,service)
  end
 end)
 f.enable();f.select();f.partial=true;f.fail_node=13;assert(not f.action('subject_pose_play'))
 local ok,why=f.runtime.close(true)
 assert(not ok and why==problem and f.lease and not f.camera_open and f.release_calls==1,
  'Unconfirmed captured release preserves the exact error and its cleanup lease')
 f.physical_recovery=true
 local native,status,reads,snapshots,saves=f.subject_native,f.status_reads,f.engine_reads,f.snapshot_calls,f.saves
 for _=1,100 do f.step(.016,1)end
 assert(f.release_calls==1 and f.snapshot_calls==snapshots and f.engine_reads==reads and
  f.subject_native==native and f.status_reads==status and f.saves==saves and not f.subject_calls.recover,
  'Automatic cleanup never resubmits release, reads captured keys, or falls back to engine input')
 assert(not f.runtime.open(),'An unconfirmed input/subject lease prevents reopening')
 f.release_ack=true;f.fail_node=nil;f.resolve=true
 assert(f.runtime.close(true,nil,true)and f.release_calls==2 and not f.lease and f.runtime.state=='closed',
  'Explicit cleanup retries once and retires the acknowledged captured lease')
 f.restored();assert(f.rate==1);f.finish()
end
do
 local f=fixture(function(f,deps)
  deps.freeze_bone_probe=dofile('freecam/windows_freeze_bone_probe.lua').new(function()end,function()return f.time end)
 end)
 f.enable();f.select()
 f.subject.tracking_frame=function()return{identity='Helldiver B',position={1,2,3},head={1,2,5},yaw=0}end
 assert(f.controls.subject_freeze_bone_test.disabled==false,'Diagnostic button must be admitted by the supported-control list')
 assert(f.runtime.handle.activate('subject_freeze_bone_test')and f.b.mode=='ignore'and f.node_writes==0,'Actual UI activation must start the trial')
 f.step(6.1);assert(f.b.mode=='position_and_rotation'and f.node_writes==0);f.restored()
 assert(f.action('subject_freeze_bone_test'));f.events={}
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1)
 assert(index_of(f.events,'mode:position_and_rotation')<index_of(f.events,'time:1'),'Bone trial restores before releasing zero time')
 f.step(.01);f.restored();assert(f.node_writes==0)
 assert(f.runtime.handle.set('freeze_player',true));assert(f.action('subject_freeze_bone_test'))
 assert(f.runtime.close(true));f.restored();f.finish()
end
do
 local active=false;local physics_pending=false;local physics_calls=0
 local f=fixture(function(f,deps)
  deps.freeze_physics_probe={active=function()return active end,start=function(frame)assert(frame.explicit_subject);active=true;return true end,
   tick=function()return true end,release=function(_,retry)
    if active then
     if physics_pending and retry~=true then return false,'Enable pending'end
     physics_calls=physics_calls+1
     if f.physics_fail then physics_pending=true;return false,'Enable pending'end
     f.events[#f.events+1]='physics-enable';active=false;physics_pending=false
    end;return true end}
 end)
 f.enable();f.select();f.subject.tracking_frame=function()return{explicit_subject=true}end
 assert(f.controls.subject_freeze_physics_test.disabled==false)
 assert(f.runtime.handle.activate('subject_freeze_physics_test')and active)
 f.events={};assert(f.runtime.handle.set('freeze_player',false))
 assert(index_of(f.events,'physics-enable')<index_of(f.events,'time:1')and not active,'Off/on trial enables before resuming time')
 assert(f.runtime.handle.set('freeze_player',true));assert(f.runtime.handle.activate('subject_freeze_physics_test')and active)
 assert(f.action('subject_refresh')and not active,'Changing discovery ends the physics trial first')
 f.select();assert(f.runtime.handle.activate('subject_freeze_physics_test')and active)
 f.physics_fail=true;assert(not f.runtime.close(true)and active and f.rate==0,'Failed enable prevents nonzero time while normal close can release input')
 local calls=physics_calls
 for i=1,100 do assert(not f.runtime.close(true,true))end
 assert(physics_calls==calls,'Automatic close does not retry failed physics cleanup')
 for i=1,100 do assert(not f.runtime.dispose())end
 assert(physics_calls==calls+1,'A reload gets one explicit cleanup retry, not one per cleanup poll')
 f.physics_fail=nil;assert(f.runtime.close(true,nil,true)and not active);f.finish()
end
do
 local active,pending,calls,renders=false,false,0,0
 local f=fixture(function(f,deps)
  deps.freeze_pose_probe={active=function()return active end,start=function(subject)
   assert(subject==f.subject);active=true;return true end,
   tick=function(enabled)if active then assert(enabled or not f.foreground)end;return true end,
   render=function(enabled)assert(enabled and active and f.rate==0);renders=renders+1;return true end,
   release=function(_,retry)
    if active then
     if pending and retry~=true then return false,'Bone cleanup pending'end
     calls=calls+1
     if f.pose_cleanup_fail then pending=true;return false,'Bone cleanup pending'end
     f.events[#f.events+1]='pose-release';active=false;pending=false
    end;return true end}
 end)
 f.enable();f.select()
 assert(f.controls.subject_freeze_pose_test.disabled==false,'Actual menu supports the private skeleton button')
 assert(f.runtime.handle.activate('subject_freeze_pose_test')and active);f.step(.016,1);assert(renders>0)
 f.events={};assert(f.runtime.handle.set('freeze_player',false))
 assert(index_of(f.events,'pose-release')<index_of(f.events,'time:1')and not active,'Skeleton releases before nonzero time')
 assert(not f.action('subject_freeze_pose_test')and not active,'Running simulation cannot start a skeleton hold')
 assert(f.runtime.handle.set('freeze_player',true));assert(f.runtime.handle.activate('subject_freeze_pose_test'))
 assert(f.action('subject_refresh')and not active,'Subject discovery releases the old skeleton first')
 f.select();assert(f.runtime.handle.activate('subject_freeze_pose_test'))
 f.pose_cleanup_fail=true;assert(not f.runtime.close(true)and active and f.rate==0)
 local count=calls
 for i=1,100 do assert(not f.runtime.close(true,true))end
 assert(calls==count,'Automatic close cannot hammer failed skeleton cleanup')
 for i=1,100 do assert(not f.runtime.dispose())end
 assert(calls==count+1,'Reload gets one explicit retry across all cleanup polls')
 f.pose_cleanup_fail=false;assert(f.runtime.close(true,nil,true)and not active);f.finish()
end
do
 local active,captures,renders=false,0,0
 local f=fixture(function(f,deps)
  deps.engine_time_only=true
  deps.freeze_pose_hold={active=function()return active end,prepare=function(subject)
   assert(subject==f.subject and f.rate>0,'Capture must precede the zero-time request')
   f.events[#f.events+1]='skeleton-capture';captures=captures+1;active=true;return true end,
   tick=function(enabled)assert(not active or enabled);return true end,
   render=function(enabled)assert(enabled and active and f.rate==0);renders=renders+1;return true end,
   release=function()if active then f.events[#f.events+1]='skeleton-release';active=false end;return true end}
 end)
 f.enable();assert(active and captures==1 and renders>0)
 assert(index_of(f.events,'skeleton-capture')<index_of(f.events,'time:0'),'Open captures the selected body before freezing')
 assert(f.controls.subject_freeze_pose_test==nil,'Integrated hold does not expose the temporary test button')
 f.foreground=false;f.step(.016,1);assert(active,'Focus loss preserves the zero-time skeleton hold')
 f.foreground=true;f.events={};assert(f.runtime.handle.set('freeze_player',false))
 assert(index_of(f.events,'skeleton-release')<index_of(f.events,'time:1'))
 assert(f.runtime.handle.set('freeze_player',true));assert(captures==2 and active)
 assert(f.action('subject_pose_play')and not active,'Authored poses acquire the skeleton after hold release')
 f.finish()
end
do
 local flips=0
 local f=fixture(function(f,deps)
  deps.freeze_root_flip=true
  deps.freeze_root_hold={tick=function()return true end,render=function()return true end,release=function()return true end,
   flip_body=function(frame)assert(frame.explicit_subject and f.rate==0);flips=flips+1;return true,'Flipped'end}
 end)
 f.enable();f.select();f.subject.tracking_frame=function()return{explicit_subject=true}end
 assert(f.controls.subject_freeze_body_flip.disabled==false,'Body flip is available through the actual menu')
 assert(f.runtime.handle.activate('subject_freeze_body_flip')and flips==1)
 assert(f.runtime.handle.set('freeze_player',false))
 assert(not f.action('subject_freeze_body_flip')and flips==1,'Running gameplay cannot queue a root flip')
 f.finish()
end
os.time=original_clock
print('Steam subject runtime: lazy session UI, explicit selection/apply, zero idle, exact cleanup before time/action, independent input/UI and explicit recovery passed')

-- Explicit refresh and subsequent entry rebuild a stale session adapter without
-- idle polling or discarding pending ownership.
do
 local f=fixture();f.enable();local first=f.subject;local checks=f.session_checks
 for i=1,100 do f.step(.016,1)end
 assert(f.session_checks==checks,'Subject session does not poll while idle')
 f.session={};assert(f.action('subject_refresh'))
 assert(f.factories==2 and f.subject~=first and f.subject.status().selected==nil,'Explicit refresh rebuilds for the new session')
 assert(f.action('subject_select_2')and f.subject.status().selected=='Helldiver B')
 assert(f.runtime.close(true));f.session={};f.open()
 assert(f.factories==3 and f.subject.status().selected~=nil,'New session entry rebuilds and auto-selects')
 f.finish()
end
print('Subject session lifecycle: no idle polling, explicit refresh requalification and fresh entry selection passed')

do
 local f=fixture();f.enable();f.select();f.pose(2);f.events={}
 assert(f.action('subject_pose_play'))
 assert(index_of(f.events,'mode:position_and_rotation')<index_of(f.events,'mode:ignore'),'Apply resets before reapplying the selected pose')
 f.events={};local before=f.decodes
 assert(f.runtime.handle.set('subject_pose',3))
 assert(f.decodes==before+1 and index_of(f.events,'mode:position_and_rotation')<index_of(f.events,'mode:ignore'),'Changing a held pose resets and applies in one action')
 local writes=f.node_writes;local reset=f.subject.reset
 f.subject.reset=function()return false,'Fixture restoration refused'end
 assert(not f.action('subject_pose_play')and f.node_writes==writes,'Failed reset must prevent the next pose write')
 f.subject.reset=reset
 writes=f.node_writes;for _=1,60 do f.step(.016,1)end
 assert(f.node_writes==writes,'A settled pose does not repeatedly reset or reapply')
 assert(f.action('subject_pose_stop'));f.restored();f.finish()
 print('Pose replacement: reset before Apply, automatic held-pose changes, refused reset and idle passed')
end

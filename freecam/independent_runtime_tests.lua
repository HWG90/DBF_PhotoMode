-- Execute the real orchestration template with controlled engine/feature
-- boundaries. Scene/movement modules have separate real-module fixtures.
assert(type(INDEPENDENT_RUNTIME_SOURCE)=='string')
assert(loadstring(INDEPENDENT_RUNTIME_SOURCE,'complete-independent-runtime'),'Complete runtime must compile')
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local file=assert(io.open(root..'independent_runtime.lua','rb'));local template=file:read('*a');file:close()
local features=[=[
local state=G.TEST
local DBF_FREECAM_LOOK={}
local DBF_PHOTO_RUNTIME={}
local DBF_PLAYER_FREEZE={}
H.dbf_actioncam_compat=state.compat
H.dbf_subject_backend={frame=function()return state.player end}
local DBF_PHOTO_LIGHTS={update_from_photo=function()state.flushes=state.flushes+1 end,cache_camera=function()state.cached=state.cached+1 end}
local DBF_SAVED_CAMERA={clear=function(reason)state.cleared=reason end}
local DBF_PHOTO_PROFILE={camera_factory={
 after_render=function(previous)return previous end,
 around_update=function(previous)return previous end}}
H.dbf_subject={flush=function()end}
H.dbf_pose_flush=function()
 state.pose_flushes=(state.pose_flushes or 0)+1
 if state.async_cleanup then state.restore_written=true end
end
H.dbf_input_before_update=function()state.before=state.before+1 end
H.dbf_input_after_update=function()
 state.after=state.after+1
 if state.restore_written then state.cleanup_pending=false;state.restore_written=nil;state.restore_acknowledged=true end
end
H.dbf_ragdoll_after_render=function()state.ragdolls=state.ragdolls+1 end
H.dbf_cinema={}
local DBF_FREECAM={}
function DBF_FREECAM.stop()
 state.stops=state.stops+1
 if state.cleanup_pending then return false,'effects pending'end
 PHOTO.active=false;PHOTO.pos=nil
 state.events[#state.events+1]='effects restored'
 return H.dbf_actioncam_compat.release()
end
function DBF_FREECAM.close()return DBF_FREECAM.stop()end
function DBF_FREECAM.camera_suspended()return state.menu_open end
local function bindings_step()
 state.inputs=state.inputs+1
 if state.intent=='enter'then
  if not target or not anchor or SPEC.active then state.rejected=(state.rejected or 0)+1;state.intent=nil;return end
  assert(H.dbf_actioncam_compat.acquire())
  PHOTO.active=true;PHOTO.cinema_state='place';state.intent=nil
 elseif state.intent=='exit'then
  assert(DBF_FREECAM.stop());state.intent=nil
 end
end
]=]
local scene_source=[=[
return{new=function()
 local state=G.TEST
 local self={retired=false}
 function self.refresh()
  state.refreshes=state.refreshes+1;self.retired=state.retired
  if state.scene_error then error(state.scene_error)end
  return state.frame,state.frame and nil or'camera temporarily unavailable'
 end
 return self
end}
]=]
local motion_source=[=[
return{new=function(sr,photo)
 local state=G.TEST;local written
 return{apply=function(frame,suspended)
  assert(frame==state.frame,'Retired camera reached movement')
  assert(state.compat.held,'Camera writes require ownership')
  state.writes=state.writes+1;state.suspended=suspended
  photo.pos=photo.pos or{1,2,3};written=true
  state.events[#state.events+1]='camera write'
  if state.motion_error then return false,state.motion_error end
  return true
 end,release=function()
  if state.position_pending then return false,'position pending'end
  if written then state.events[#state.events+1]='position restored';written=nil end
  return true
 end}
end}
]=]
local animation_source='return{new=function()return function()end end}'
local function replace(source,key,value)
 local count;source,count=source:gsub(key,function()return value end);assert(count==1,key);return source
end
local source=replace(template,'__STUDIO_FEATURES__',features)
source=replace(source,'__CAMERA_SCENE__',scene_source)
source=replace(source,'__CAMERA_MOTION__',motion_source)
source=replace(source,'__ANIMATION_STATE__',animation_source)
local function fixture(late_render)
 local state={updates=0,renders=0,inputs=0,writes=0,refreshes=0,stops=0,flushes=0,cached=0,before=0,after=0,ragdolls=0,events={}}
 local world,unit,cam,player={},{},{},{}
 state.frame={world=world,unit=unit,cam=cam,player=player,player_identity='avatar-one',epoch=1}
 state.player={world=world,root_handle=player,local_owner=true,identity='avatar-one',position={0,0,0}}
 local env=setmetatable({TEST=state},{__index=_G});env._G=env
 env.stingray={Vector3={},Matrix4x4={},Application={worlds=function()return{world}end}}
 env.update=function(dt,...)
  state.updates=state.updates+1
  if state.game_error then error(state.game_error,0)end
  return'game-update',nil,...
 end
 local function game_render(...)state.renders=state.renders+1;return'game-render',nil,... end
 if not late_render then env.render=game_render end
 state.compat={available=true,held=false,count=0,
  acquire=function()state.events[#state.events+1]='camera acquired';state.compat.held=true;return true end,
  release=function()state.events[#state.events+1]='compatibility released';state.compat.held=false;return true end,
  wrap_update=function(previous,on_conflict)return function(...)
   if state.conflict then on_conflict('camera provider changed')end
   return previous(...)
  end end}
 env.shutdown=function(...)state.shutdowns=(state.shutdowns or 0)+1;return'shutdown',nil,... end
 local chunk=assert(loadstring(source,'owned-runtime-template'));setfenv(chunk,env);chunk()
 return env,state,env.DBF_PHOTO_CAMERA_RUNTIME,game_render
end
local function packed(...)return{n=select('#',...),...}end
local env,s,owner=fixture()
assert(owner.engine=='independent'and owner.api==1 and not owner.ready)
local result=packed(env.update(.016,'tail',nil))
assert(result.n==4 and result[1]=='game-update'and result[2]==nil and result[3]=='tail'and result[4]==nil)
assert(s.updates==1 and owner.ready and s.before==1 and s.after==1)
result=packed(env.render('frame',nil))
assert(result.n==4 and result[1]=='game-render'and result[3]=='frame'and result[4]==nil)
assert(s.writes==0 and s.inputs==1,'Idle controller must not write a gameplay camera')
local ready_frame=s.frame
s.frame=nil;s.intent='enter';env.render()
assert(not owner.ready and not owner.photo.active and not s.compat.held and s.rejected==1,'A cached idle camera cannot authorize entry during a read gap')
s.frame=ready_frame
s.intent='enter';env.render()
assert(owner.photo.active and s.compat.held and s.writes==1 and s.events[1]=='camera acquired')
s.menu_open=true;env.render();assert(s.suspended and owner.photo.active and s.compat.held)
local old_frame=s.frame;local inputs,writes=s.inputs,s.writes
s.frame=nil;s.retired=false;env.render()
assert(owner.photo.active and s.compat.held and s.inputs==inputs and s.writes==writes,'Transient scene reads must not steal input or write stale camera handles')
s.frame=old_frame;env.render();assert(s.writes==writes+1 and owner.ready)
s.intent='exit';env.render()
assert(not owner.photo.active and not s.compat.held)
local order=table.concat(s.events,'|')
assert(order:find('effects restored|position restored|compatibility released',1,true),'Position/effects restoration must precede ActionCam resume')
s.intent='enter';env.render();s.cleanup_pending=true
s.frame={world=old_frame.world,unit={},cam={},player=old_frame.player,player_identity='avatar-one',epoch=2}
writes=s.writes;env.render()
assert(s.writes==writes and s.compat.held and not owner.ready,'A replacement camera must wait for old effects cleanup')
s.cleanup_pending=false;env.render();assert(not owner.photo.active and not s.compat.held and owner.ready and owner.epoch==2)
assert(s.cleared=='scene changed')
s.intent='enter';env.render();s.frame=nil;s.retired=true;env.render()
assert(not owner.photo.active and not s.compat.held and s.cleared=='scene retired')
assert(owner.stop());local flushes,refreshes,inputs,writes,ragdolls=s.flushes,s.refreshes,s.inputs,s.writes,s.ragdolls
env.update(0);env.render()
assert(s.flushes==flushes and s.refreshes==refreshes and s.inputs==inputs and s.writes==writes and s.ragdolls==ragdolls,'Stopped hooks must keep game callbacks without camera/native work')
assert(s.updates==2 and s.renders>3)
local late,ls,lo,game_render=fixture(true)
assert(late.render==nil);late.render=game_render;late.update(0);ls.intent='enter';late.render()
assert(lo.photo.active and ls.writes==1,'Render installed after startup must be hooked without restarting')
ls.conflict=true;late.update(.016)
assert(not lo.photo.active and not ls.compat.held,'Provider conflicts must cancel the photo lease')
ls.conflict=false;ls.intent='enter';late.render();ls.game_error='original engine update failure'
local ok,why=pcall(late.update,.016)
assert(not ok and why=='original engine update failure'and not ls.compat.held,'Game errors must propagate after owned camera cleanup')
ls.game_error=nil
result=packed(late.shutdown('bye',nil))
assert(result.n==4 and result[1]=='shutdown'and result[3]=='bye'and result[4]==nil and ls.shutdowns==1)
local gap,gs,go=fixture()
gap.update(.016);gs.intent='enter';gap.render();gs.frame=nil
local entered_inputs,entered_writes=gs.inputs,gs.writes
for i=1,8 do gap.render()end
assert(not go.photo.active and not gs.compat.held and gs.inputs==entered_inputs and gs.writes==entered_writes,'Persistent scene refusal must start cleanup instead of indefinitely trapping input/time')
local disabled,ds,do_=fixture()
disabled.update(.016);ds.intent='enter';disabled.render()
ds.cleanup_pending=true;ds.async_cleanup=true
disabled.DBF_PHOTO_MODE_OWNER={stopped=true}
assert(do_.stop()==false and do_.stopping and ds.compat.held)
local writes_before,inputs_before,ragdolls_before=ds.writes,ds.inputs,ds.ragdolls
disabled.render();disabled.update(.016)
assert(ds.pose_flushes>0 and ds.restore_acknowledged and not ds.compat.held and do_.state=='stopped','MDL stopped owner must still service and acknowledge asynchronous teardown')
assert(ds.writes==writes_before and ds.inputs==inputs_before and ds.ragdolls==ragdolls_before,'Pending teardown cannot sample input, write a camera or run active ragdoll capture')
local flushes_before=ds.pose_flushes;disabled.update(.016);assert(ds.pose_flushes==flushes_before,'Acknowledged teardown leaves retained callbacks inert')
print('Independent runtime: full-source compilation, transparent callbacks, idle no-writes, acquire/restore order, bounded transient gaps, camera replacement, retirement, late render, conflict/error cleanup, asynchronous MDL teardown and inert shutdown passed')

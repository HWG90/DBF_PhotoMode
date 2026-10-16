-- Execute the real orchestration template with controlled engine/feature
-- boundaries. Scene/movement modules have separate real-module fixtures.
assert(type(INDEPENDENT_RUNTIME_SOURCE)=='string')
assert(loadstring(INDEPENDENT_RUNTIME_SOURCE,'complete-independent-runtime'),'Complete runtime must compile')
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local file=assert(io.open(root..'independent_runtime.lua','rb'));local template=file:read('*a');file:close()
local features=[=[
local state=G.TEST
local DBF_FREECAM_LOOK={basis=function(photo,forward)
 photo.view=photo.view or{yaw=0,pitch=0}
 return{forward[1],forward[2],forward[3]},{0,-1,0}
end}
local DBF_PHOTO_RUNTIME={apply=function(cam,unit)
 assert(cam==state.camera_handle and unit==state.camera_unit,'Retired camera reached lens output')
 state.lens_writes=(state.lens_writes or 0)+1
end}
local DBF_PLAYER_FREEZE={}
H.dbf_camera_ownership=state.ownership
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
 state.warming=nil
 state.events[#state.events+1]='effects restored'
 return H.dbf_camera_ownership.release()
end
function DBF_FREECAM.close()return DBF_FREECAM.stop()end
function DBF_FREECAM.camera_suspended()return state.menu_open end
function DBF_FREECAM.entry_pending()return state.warming==true end
function DBF_FREECAM.scene_required()
 return PHOTO.active or state.warming==true or state.cleanup_pending==true or state.slowmo==true or state.bookmark==true
end
local function bindings_step()
 state.inputs=state.inputs+1
 if state.intent=='enter'then
  if CFG.ensure_scene then CFG.ensure_scene()end
  if not target or not anchor or SPEC.active then state.warming=true;return end
  state.warming=nil
  assert(H.dbf_camera_ownership.acquire())
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
return{new=function(sr,photo,look,runtime,freeze,cinema,config)
 local state=G.TEST;local written,written_frame
 return{apply=function(frame,suspended)
  assert(frame.world==state.frame.world and frame.unit==state.frame.unit and frame.cam==state.frame.cam,'Retired camera reached movement')
  assert(state.ownership.held,'Camera writes require ownership')
  state.writes=state.writes+1;state.suspended=suspended
  photo.pos=photo.pos or{1,2,3};written=true;written_frame=frame
  state.events[#state.events+1]='camera write'
  if state.motion_error then return false,state.motion_error end
  return true
 end,release=function()
  if state.position_pending then return false,'position pending'end
  if written then
   state.events[#state.events+1]='position restored';written=nil
   if config.scene.clear_written then config.scene.clear_written(written_frame)end
  end
  return true
 end}
end}
]=]
local animation_source='return{new=function()return function()end end}'
local function replace(source,key,value)
 local count;source,count=source:gsub(key,function()return value end);assert(count==1,key);return source
end
local function assemble(scene_code,motion_code)
 local value=replace(template,'__STUDIO_FEATURES__',features)
 value=replace(value,'__CAMERA_SCENE__',scene_code)
 value=replace(value,'__CAMERA_MOTION__',motion_code or motion_source)
 return replace(value,'__ANIMATION_STATE__',animation_source)
end
local source=assemble(scene_source)
local scene_file=assert(io.open(root..'camera_scene.lua','rb'));local actual_scene_source=scene_file:read('*a');scene_file:close()
local actual_scene_runtime=assemble(actual_scene_source)
local motion_file=assert(io.open(root..'camera_motion.lua','rb'));local actual_motion_source=motion_file:read('*a');motion_file:close()
local actual_motion_runtime=assemble(actual_scene_source,actual_motion_source)
local function fixture(late_render,actual_scene,actual_motion)
 local state={updates=0,renders=0,inputs=0,writes=0,refreshes=0,stops=0,flushes=0,cached=0,before=0,after=0,ragdolls=0,events={}}
 local world,unit,cam,player={},{},{},{}
 state.frame={world=world,unit=unit,cam=cam,player=player,player_identity='avatar-one',epoch=1}
 state.camera_unit=unit;state.camera_handle=cam;state.camera_alive=true;state.retired_units={}
 state.player={world=world,root_handle=player,local_owner=true,identity='avatar-one',position={0,0,0}}
 local env=setmetatable({TEST=state},{__index=_G});env._G=env
 env.stingray={Vector3={},Matrix4x4={},Application={worlds=function()return{world}end}}
 if actual_scene then
  state.camera_position={0,0,1};state.rendered_position={0,0,1}
  local sr=env.stingray
  sr.Vector3=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return{...}end})
  local function pose(p)return{position=p,forward={1,0,0},right={0,-1,0},up={0,0,1}}end
  sr.Application.main_world=function()return world end
  sr.World={units=function(w)assert(w==world);state.unit_scans=(state.unit_scans or 0)+1;return{state.camera_unit,player}end,
   debug_camera_pose=function(w)assert(w==world);return pose(state.rendered_position)end,
   update_unit=function(w,u)assert(w==world and u==state.camera_unit and state.camera_alive,'Retired camera reached world update');state.world_updates=(state.world_updates or 0)+1 end}
  sr.Unit={alive=function(u)
    if u==player then return true end
    if state.retired_units[u]then return false end
    assert(u==state.camera_unit);return state.camera_alive
   end,
   num_cameras=function(u)return u==state.camera_unit and 1 or 0 end,
   camera=function(u,index)assert(u==state.camera_unit and index==1);return state.camera_handle end}
  sr.Camera={world_position=function(c)assert(c==state.camera_handle);return state.camera_position end,
   local_position=function(c,u)assert(c==state.camera_handle and u==state.camera_unit);return state.camera_position end,
   world_pose=function(c)assert(c==state.camera_handle);return pose(state.camera_position)end,
   set_local_position=function(c,u,p)
    assert(c==state.camera_handle and u==state.camera_unit and state.camera_alive,'Retired camera reached native position setter')
    state.writes=state.writes+1;state.camera_position={unpack(p)}
    state.events[#state.events+1]='camera write'
   end}
  for _,name in ipairs({'translation','forward','right','up'})do
   local field=name=='translation'and'position'or name
   sr.Matrix4x4[name]=function(p)return p[field]end
  end
 end
 env.update=function(dt,...)
  state.updates=state.updates+1
  if actual_scene and state.moving then
   state.camera_position={state.camera_position[1]+.25,0,1}
   state.player.position={state.camera_position[1],0,0}
  end
  if state.on_game_update then local callback=state.on_game_update;state.on_game_update=nil;callback()end
  if state.game_error then error(state.game_error,0)end
  return'game-update',nil,...
 end
 local function game_render(...)
  state.renders=state.renders+1
  state.refreshes_at_game_render=state.refreshes
  if state.stop_on_render then env.DBF_PHOTO_MODE_OWNER={stopped=true}end
  if actual_scene then state.rendered_position={unpack(state.camera_position)}end
  return'game-render',nil,...
 end
 if not late_render then env.render=game_render end
 state.ownership={available=true,held=false,count=0,
  acquire=function()state.events[#state.events+1]='camera acquired';state.ownership.held=true;return true end,
  release=function()state.events[#state.events+1]='ownership released';state.ownership.held=false;return true end}
 env.shutdown=function(...)state.shutdowns=(state.shutdowns or 0)+1;return'shutdown',nil,... end
 local code=actual_motion and actual_motion_runtime or actual_scene and actual_scene_runtime or source
 local chunk=assert(loadstring(code,'owned-runtime-template'));setfenv(chunk,env);chunk()
 return env,state,env.DBF_PHOTO_CAMERA_RUNTIME,game_render
end
local function packed(...)return{n=select('#',...),...}end
local env,s,owner=fixture()
assert(owner.engine=='independent'and owner.api==1 and not owner.ready)
local result=packed(env.update(.016,'tail',nil))
assert(result.n==4 and result[1]=='game-update'and result[2]==nil and result[3]=='tail'and result[4]==nil)
assert(s.updates==1 and not owner.ready and s.refreshes==0 and s.before==1 and s.after==1,'Ordinary gameplay must not discover a camera')
result=packed(env.render('frame',nil))
assert(result.n==4 and result[1]=='game-render'and result[3]=='frame'and result[4]==nil)
assert(s.writes==0 and s.inputs==1 and s.refreshes==0,'Idle controller must not discover or write a gameplay camera')
local ready_frame=s.frame
s.frame=nil;s.intent='enter';env.render()
assert(not owner.ready and not owner.photo.active and not s.ownership.held and s.warming,'A cached idle camera cannot authorize entry during a read gap')
s.frame=ready_frame
s.intent='enter';env.render()
assert(owner.photo.active and s.ownership.held and s.writes==1 and s.events[1]=='camera acquired')
s.menu_open=true;env.render();assert(s.suspended and owner.photo.active and s.ownership.held)
local old_frame=s.frame;local inputs,writes=s.inputs,s.writes
s.frame=nil;s.retired=false;env.render()
assert(owner.photo.active and s.ownership.held and s.inputs==inputs and s.writes==writes,'Transient scene reads must not steal input or write stale camera handles')
s.frame=old_frame;env.render();assert(s.writes==writes+1 and owner.ready)
s.intent='exit';env.render()
assert(not owner.photo.active and not s.ownership.held)
local order=table.concat(s.events,'|')
assert(order:find('effects restored|position restored|ownership released',1,true),'Position/effects restoration must precede local camera lease release')
s.intent='enter';env.render();s.cleanup_pending=true
s.frame={world=old_frame.world,unit={},cam={},player=old_frame.player,player_identity='avatar-one',epoch=2}
writes=s.writes;env.render()
assert(s.writes==writes and s.ownership.held and not owner.ready,'A replacement camera must wait for old effects cleanup')
s.cleanup_pending=false;env.render();assert(not owner.photo.active and not s.ownership.held and owner.ready and owner.epoch==2)
assert(s.cleared=='scene changed')
s.intent='enter';env.render();s.frame=nil;s.retired=true;env.render()
assert(not owner.photo.active and not s.ownership.held and s.cleared=='scene retired')
assert(owner.stop());local flushes,refreshes,inputs,writes,ragdolls=s.flushes,s.refreshes,s.inputs,s.writes,s.ragdolls
env.update(0);env.render()
assert(s.flushes==flushes and s.refreshes==refreshes and s.inputs==inputs and s.writes==writes and s.ragdolls==ragdolls,'Stopped hooks must keep game callbacks without camera/native work')
assert(s.updates==2 and s.renders>3)
local late,ls,lo,game_render=fixture(true)
assert(late.render==nil);late.render=game_render;late.update(0);ls.intent='enter';late.render()
assert(lo.photo.active and ls.writes==1,'Render installed after startup must be hooked without restarting')
ls.conflict=true;late.update(.016)
assert(lo.photo.active and ls.ownership.held,'Unrelated provider state must not influence the local Photo camera lease')
ls.conflict=false;ls.intent='enter';late.render();ls.game_error='original engine update failure'
local ok,why=pcall(late.update,.016)
assert(not ok and why=='original engine update failure'and not ls.ownership.held,'Game errors must propagate after owned camera cleanup')
ls.game_error=nil
result=packed(late.shutdown('bye',nil))
assert(result.n==4 and result[1]=='shutdown'and result[3]=='bye'and result[4]==nil and ls.shutdowns==1)
local gap,gs,go=fixture()
gap.update(.016);gs.intent='enter';gap.render();gs.frame=nil
local entered_inputs,entered_writes=gs.inputs,gs.writes
for i=1,8 do gap.render()end
assert(not go.photo.active and not gs.ownership.held and gs.inputs==entered_inputs and gs.writes==entered_writes,'Persistent scene refusal must start cleanup instead of indefinitely trapping input/time')
local disabled,ds,do_=fixture()
disabled.update(.016);ds.intent='enter';disabled.render()
ds.cleanup_pending=true;ds.async_cleanup=true
disabled.DBF_PHOTO_MODE_OWNER={stopped=true}
assert(do_.stop()==false and do_.stopping and ds.ownership.held)
local writes_before,inputs_before,ragdolls_before=ds.writes,ds.inputs,ds.ragdolls
disabled.render();disabled.update(.016)
assert(ds.pose_flushes>0 and ds.restore_acknowledged and not ds.ownership.held and do_.state=='stopped','MDL stopped owner must still service and acknowledge asynchronous teardown')
assert(ds.writes==writes_before and ds.inputs==inputs_before and ds.ragdolls==ragdolls_before,'Pending teardown cannot sample input, write a camera or run active ragdoll capture')
local flushes_before=ds.pose_flushes;disabled.update(.016);assert(ds.pose_flushes==flushes_before,'Acknowledged teardown leaves retained callbacks inert')
local moving,ms,mo=fixture(false,true)
moving.update(.016);moving.render();ms.moving=true
for frame=1,6 do
 moving.update(.016)
 if frame==3 then ms.intent='enter'end
 moving.render()
 if frame>=4 then assert(mo.photo.active and ms.ownership.held,'The first toggle while moving must use the actual Scene rendered-pose identity rather than reject a one-update pose lag')end
end
assert(not ms.rejected and ms.writes>=3,'Continuous movement must not consume the opening toggle as unavailable')
ms.intent='exit';moving.update(.016);moving.render();assert(not mo.photo.active)
ms.intent='enter';moving.update(.016);moving.render()
if not mo.photo.active then moving.update(.016);moving.render()end
assert(mo.photo.active and not ms.rejected,'The first immediate reopen while still moving must survive completed camera cleanup')
local idle,is,io_=fixture(false,true)
for frame=1,600 do is.moving=true;idle.update(.016);idle.render()end
assert(not io_.photo.active and (is.unit_scans or 0)==0 and is.writes==0,'600 moving gameplay frames with Photo closed must perform zero camera Unit inventory scans')
is.intent='enter';idle.render();if not io_.photo.active then idle.update(.016);idle.render()end
assert(io_.photo.active and is.ownership.held,'A cold idle camera must open from one retained request')
is.intent='exit';idle.render();idle.update(.016);local after_exit=is.unit_scans or 0
for frame=1,600 do idle.update(.016);idle.render()end
assert((is.unit_scans or 0)==after_exit,'Normal gameplay after exit must stop enumerating camera Units')
is.bookmark=true;idle.update(.016);assert((is.unit_scans or 0)>after_exit,'A retained camera bookmark keeps its fresh lifetime checks')
local retiring,rs,ro=fixture();rs.warming=true;rs.stop_on_render=true
retiring.render()
assert(rs.refreshes==rs.refreshes_at_game_render and rs.ragdolls==0,'An owner stopped inside game render must not trigger post-render entry discovery or ragdoll work')
-- Exercise the actual Scene AND Motion modules: the game's update can retire a
-- camera after our pre-update proof. No output may use that snapshot before the
-- next render revalidates it; retirement must discard, never restore, old data.
local counted,cs,co=fixture(false,true,true)
counted.update(.016);counted.render();cs.intent='enter';counted.render()
assert(co.photo.active and cs.writes==1 and cs.lens_writes==1)
local scans,positions,lenses,after=cs.unit_scans,cs.writes,cs.lens_writes,cs.after
counted.update(.016)
assert(cs.unit_scans==scans+1 and cs.after==after+1,'Active update keeps pre-update proof and input acknowledgement but skips duplicate post-update discovery')
assert(cs.writes==positions and cs.lens_writes==lenses,'No position/lens output belongs between gameplay update and render')
counted.render()
assert(cs.unit_scans==scans+4 and cs.writes==positions+1 and cs.lens_writes==lenses+1,'Active frame retains four fresh inventories: pre-update, render, and both Motion lifetime checks')
positions,lenses=cs.writes,cs.lens_writes
local retired_unit=cs.camera_unit
cs.on_game_update=function()
 cs.retired_units[retired_unit]=true
 cs.camera_unit={};cs.camera_handle={}
 cs.frame={world=cs.frame.world,unit=cs.camera_unit,cam=cs.camera_handle,player=cs.frame.player,player_identity='avatar-one',epoch=2}
end
scans=cs.unit_scans
counted.update(.016)
assert(co.photo.active and cs.unit_scans==scans+1 and cs.writes==positions and cs.lens_writes==lenses,'Replacement during gameplay cannot trigger output from the now stale pre-update snapshot')
counted.render()
assert(not co.photo.active and not cs.ownership.held and cs.writes==positions and cs.lens_writes==lenses,'Render replacement must complete cleanup before any camera/lens output')
assert(co.ready and co.epoch==2 and cs.cleared=='scene changed')
cs.intent='enter';counted.render()
assert(co.photo.active and cs.writes==positions+1 and cs.lens_writes==lenses+1,'A replacement may receive output only after a fresh explicit opening')
positions,lenses=cs.writes,cs.lens_writes
cs.on_game_update=function()cs.camera_alive=false end
counted.update(.016)
assert(co.photo.active and cs.writes==positions and cs.lens_writes==lenses)
counted.render()
assert(not co.photo.active and not cs.ownership.held and not co.ready and cs.writes==positions and cs.lens_writes==lenses,'Render retirement must discard old position/lens ownership without touching the retired camera')
-- Closed persistent leases and pending entry still require post-update proof.
local persistent,ps,po=fixture()
ps.bookmark=true;local refreshes=ps.refreshes;persistent.update(.016)
assert(ps.refreshes==refreshes+2,'Closed bookmark lifetime checks retain both update refreshes')
ps.bookmark=false;ps.slowmo=true;refreshes=ps.refreshes;persistent.update(.016)
assert(ps.refreshes==refreshes+2,'Closed slow-motion lifetime checks retain both update refreshes')
ps.slowmo=false;ps.intent='enter';persistent.render();ps.warming=true
refreshes=ps.refreshes;persistent.update(.016)
assert(ps.refreshes==refreshes+2 and po.photo.active,'Pending entry keeps its post-update proof even if Photo is active')
ps.warming=false;ps.cleanup_pending=true
ps.frame={world=ps.frame.world,unit={},cam={},player=ps.frame.player,player_identity='avatar-one',epoch=2}
refreshes=ps.refreshes;local pending_writes=ps.writes;persistent.update(.016)
assert(ps.refreshes==refreshes+2 and po.photo.active and ps.ownership.held and ps.writes==pending_writes,'A pending effects/position cleanup retains post-update retries and forbids output')
print('Independent runtime: full-source compilation, transparent callbacks, idle no-writes, acquire/restore order, bounded transient gaps, moving first-press entry/reopen, actual Scene/Motion four-proof active frames, update-time replacement/retirement, closed/pending proof retention, late render, conflict/error cleanup, asynchronous MDL teardown and inert shutdown passed')

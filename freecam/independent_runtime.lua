-- War Journalist's owned camera runtime and scene lifecycle.
local G=_G
local sr=assert(rawget(G,'stingray'),'Photo camera engine unavailable')
local V,M=assert(sr.Vector3),assert(sr.Matrix4x4)
local function finite(value)return type(value)=='number'and value==value and math.abs(value)<math.huge end
local function try(fn,...)
 if type(fn)~='function'then return end
 local ok,value=pcall(fn,...);if ok then return value end
end
local function xyz(value)return V.x(value),V.y(value),V.z(value)end
local function pack(...)return{n=select('#',...),...}end
local function log(message)
 local root=rawget(G,'DBF_PHOTO_PACKAGE_ROOT')
 if not root then return end
 local file=io.open(root..'/PhotoCamera.log','a')
 if file then file:write(tostring(message),'\n');file:close()end
end
local function world_alive(world)
 local worlds=sr.Application and try(sr.Application.worlds)
 if type(worlds)~='table'then return false end
 for _,current in pairs(worlds)do if current==world then return true end end
 return false
end
local PHOTO={active=false,pos=nil,view=nil,was={},input={},locked=false,lock_pose=nil}
local CFG={PHOTO_SPEED=3,PHOTO_MAX_RANGE=500,PHOTO_FAST=1}
local H={}
H.dbf_animation_get_state=(function()
__ANIMATION_STATE__
end)().new(sr)
local target,anchor,scene
local WORLD={epoch=0}
local SPEC={active=true}
local SAFE={gate=nil}
local last_dt=0
-- The verified local-player provider supplies the avatar directly. Discovery
-- does not guess identity from animation layers or camera-to-body distances.
local function known_body(unit)return not anchor or unit~=anchor.unit end

__STUDIO_FEATURES__

local Scene=(function()
__CAMERA_SCENE__
end)()
local Motion=(function()
__CAMERA_MOTION__
end)()
scene=Scene.new(sr,{
 frame=function()
  if not H.dbf_subject_backend then return nil,'Verified local player unavailable'end
  return H.dbf_subject_backend.frame()
 end,
 unit_lifetime=H.dbf_subject_backend and H.dbf_subject_backend.unit_lifetime
},log)
CFG.scene=scene
local motion=Motion.new(sr,PHOTO,DBF_FREECAM_LOOK,DBF_PHOTO_RUNTIME,DBF_PLAYER_FREEZE,H.dbf_cinema,CFG,log)
local runtime={engine='independent',api=1,ready=false,state='waiting',epoch=0,photo=PHOTO}
rawset(G,'DBF_PHOTO_CAMERA_RUNTIME',runtime)
local stopped=false
local closing_reason
local announced
local current_frame
local frame_serial=0
local unreadable_renders=0
local MAX_UNREADABLE_RENDERS=8
local render_wrapper
local function status(state,why)
 runtime.state,runtime.reason=state,why
 local message=state..(why and(': '..tostring(why))or'')
 if announced~=message then announced=message;log('Photo camera: '..message)end
end
local function same_frame(a,b)
 return a and b and a.world==b.world and a.unit==b.unit and a.cam==b.cam
  and a.player==b.player and a.player_identity==b.player_identity and a.epoch==b.epoch
end
-- Position restoration belongs to the same transaction as effects/time/input.
-- It must complete before the controller relinquishes its own local lease.
local camera_release=H.dbf_camera_ownership.release
H.dbf_camera_ownership.release=function(...)
 local ok,why=motion.release(scene)
 if ok==false then return false,why end
 return camera_release(...)
end
local function clear_context()
 target,anchor,current_frame=nil,nil,nil
 SPEC.active=true
 runtime.ready=false;runtime.camera=nil;runtime.player=nil
end
local function close_camera(reason,disposing)
 local called,ok,why=pcall(disposing and DBF_FREECAM.close or DBF_FREECAM.stop)
 if not called or ok==false then
  closing_reason=reason or closing_reason or'cleanup'
  status('cleanup pending',called and why or ok)
  return false,called and why or tostring(ok)
 end
 local released,problem=motion.release(scene)
 if released==false then closing_reason=reason or'cleanup';status('cleanup pending',problem);return false,problem end
 closing_reason=nil
 if reason=='scene changed'or reason=='scene retired'or reason=='shutdown'then
  DBF_SAVED_CAMERA.clear(reason)
 end
 return true
end
local function drop_all(reason)
 local ok,why=close_camera(reason or'released')
 if ok==false then return false,why end
 clear_context();return true
end
local function refresh_camera()
 local called,frame,why=pcall(scene.refresh)
 if not called then why=tostring(frame);frame=nil end
 if closing_reason then
  local done=close_camera(closing_reason)
  if not done then runtime.ready=false;SPEC.active=true;return nil end
  clear_context()
 end
 if not frame then
  runtime.ready=false
  SPEC.active=true
  if scene.retired then
   local done=close_camera('scene retired')
   if done then clear_context()end
  end
  status('waiting',why or scene.reason or'Rendered camera unavailable')
  return nil
 end
 if current_frame and not same_frame(current_frame,frame)then
  local done=close_camera('scene changed')
  if not done then runtime.ready=false;SPEC.active=true;return nil end
  clear_context()
 end
 current_frame=frame
 target={world=frame.world,unit=frame.unit,cam=frame.cam}
 anchor={unit=frame.player,node=1,spectate=false}
 WORLD.epoch=frame.epoch;runtime.epoch=frame.epoch
 SPEC.active=false
 runtime.ready=true;runtime.camera=tostring(frame.cam);runtime.player=frame.player_identity
 status(PHOTO.active and(PHOTO.cinema_state=='perform'and'cinema'or'photo')or'ready')
 return frame
end
DBF_PHOTO_LIGHTS.player_context=function()
 local f=current_frame
 if not runtime.ready or not f or f.world~=(target and target.world)then return end
 return{world=f.world,position=f.player_position}
end
-- A closed, clean camera owns no scene handles. Only an opening request or a
-- persistent time/bookmark/cleanup lease justifies discovery during gameplay.
local function scene_needed()
 return PHOTO.active or closing_reason~=nil or motion.pending==true or H.dbf_camera_ownership.held==true
  or type(DBF_FREECAM.scene_required)=='function'and DBF_FREECAM.scene_required()==true
end
local function idle_camera()
 if target or anchor or current_frame then clear_context()end
 status('idle')
end
CFG.ensure_scene=function()
 if current_frame and runtime.ready then return true end
 local frame=refresh_camera()
 return frame~=nil,runtime.reason or scene.reason or'Waiting for a rendered camera',true
end
local function cleanup_error(where,why)
 log('Photo '..where..': '..tostring(why))
 local done=close_camera('error')
 if done then clear_context()end
end
local function flush_owned()
 DBF_PHOTO_LIGHTS.update_from_photo()
 H.dbf_subject.flush(last_dt)
 H.dbf_pose_flush(last_dt)
 if H.dbf_ai then H.dbf_ai.flush(PHOTO.active)end
end
local function render_photo()
 if stopped or runtime.stopping then return end
 local owner=rawget(G,'DBF_PHOTO_MODE_OWNER');if owner and owner.stopped then return end
 local frame
 if scene_needed()then frame=refresh_camera()else idle_camera()end
 -- Keep servicing the menu/hotkey while idle so it can register before a
 -- player exists. During a transient read gap retain its existing GUI and
 -- camera lease briefly, issuing no camera writes or new input samples. A
 -- persistent refusal must enter cleanup rather than trapping input/time.
 if frame then unreadable_renders=0
 elseif PHOTO.active then
  unreadable_renders=unreadable_renders+1
  if unreadable_renders>=MAX_UNREADABLE_RENDERS then
   local done=close_camera('scene unavailable')
   if done then clear_context()end
   return
  end
 else unreadable_renders=0 end
 local was_active=PHOTO.active
 if frame or not PHOTO.active and not H.dbf_camera_ownership.held then bindings_step()end
 if not was_active and PHOTO.active then frame=current_frame end
 if PHOTO.active and frame then
  local ok,why=motion.apply(frame,DBF_FREECAM.camera_suspended())
  if ok==false then cleanup_error('movement',why);return end
  DBF_PHOTO_LIGHTS.cache_camera()
 end
end
local function hook_render()
 if render_wrapper then return true end
 local previous=rawget(G,'render');if type(previous)~='function'then return false end
 local observed=DBF_PHOTO_PROFILE.camera_factory.after_render(previous,function()return PHOTO.active end,log)
 render_wrapper=function(...)
  frame_serial=frame_serial+1;runtime.render_frame=frame_serial
  local ok,why=pcall(render_photo)
  if not ok then cleanup_error('render',why)end
  local result=pack(pcall(observed,...))
  if not result[1]then cleanup_error('game render',result[2]);error(result[2],0)end
  local owner=rawget(G,'DBF_PHOTO_MODE_OWNER')
  if not stopped and not runtime.stopping and not(owner and owner.stopped)and not PHOTO.active and DBF_FREECAM.entry_pending()then
   -- A first opening during movement can precede the game's debug-pose update.
   -- Qualify the view after render, then satisfy that same request next frame.
   local ready,problem=pcall(refresh_camera)
   if not ready then cleanup_error('entry discovery',problem)end
  end
  if not stopped and not runtime.stopping and not(owner and owner.stopped)then H.dbf_ragdoll_after_render()end
  return unpack(result,2,result.n)
 end
 rawset(G,'render',render_wrapper)
 return true
end
local function step(dt)
 if stopped then return end
 last_dt=finite(dt)and math.max(0,math.min(.1,dt))or 0
 local owner=rawget(G,'DBF_PHOTO_MODE_OWNER')
 if runtime.stopping or owner and owner.stopped then
  -- MDL marks its owner stopped before requesting teardown. Pose/AI leases
  -- still need their owning update to restore and acknowledge queued work.
  -- No input sampling, discovery, light creation or camera motion runs here.
  runtime.stopping=true;runtime.ready=false;SPEC.active=true
  H.dbf_subject.flush(last_dt)
  H.dbf_pose_flush(last_dt)
  if H.dbf_ai then H.dbf_ai.flush(false)end
  runtime.stop()
  return
 end
 hook_render()
 -- Scene refresh happens after the game's update as well as before it, so
 -- respawn and scene replacement cannot retain a borrowed previous camera.
 if scene_needed()then refresh_camera()else idle_camera()end
 H.dbf_input_before_update()
 flush_owned()
end
local previous_update=assert(rawget(G,'update'),'Game update callback unavailable')
local function after_update()
 H.dbf_input_after_update()
 local owner=rawget(G,'DBF_PHOTO_MODE_OWNER')
 if runtime.stopping or owner and owner.stopped then runtime.stop()
 elseif scene_needed()then
  -- Active camera output always refreshes immediately before render, then
  -- validates again around callbacks that can retire the scene. Nothing writes
  -- that camera here; avoid a duplicate full discovery between those phases.
  if not PHOTO.active or closing_reason or DBF_FREECAM.entry_pending()then refresh_camera()end
 else idle_camera()end
end
local owned_update=function(dt,...)
 local ok,why=pcall(step,dt)
 if not ok then cleanup_error('update',why)end
 local result=pack(pcall(previous_update,dt,...))
 if not result[1]then cleanup_error('game update',result[2]);error(result[2],0)end
 if not stopped then
  local done,problem=pcall(after_update)
  if not done then cleanup_error('after update',problem)end
 end
 return unpack(result,2,result.n)
end
owned_update=DBF_PHOTO_PROFILE.camera_factory.around_update(owned_update,function()return PHOTO.active end,log)
rawset(G,'update',owned_update)
local previous_shutdown=rawget(G,'shutdown')
rawset(G,'shutdown',function(...)
 runtime.stopping=true
 local ok,why=close_camera('shutdown',true)
 if ok==false then return false,why end
 stopped=true;runtime.ready=false;status('stopped')
 clear_context()
 if type(previous_shutdown)=='function'then return previous_shutdown(...)end
end)
function runtime.stop()
 runtime.stopping=true
 local ok,why=close_camera('shutdown',true)
 if ok==false then return false,why end
 stopped=true;clear_context();status('stopped');return true
end
hook_render()
log('War Journalist independent camera controller ready')

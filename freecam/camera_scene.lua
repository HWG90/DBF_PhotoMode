-- Discover only a rendered main-world camera and the verified local player.
-- All Unit calls use handles from this refresh's World.units enumeration.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function copy(v)return{v[1],v[2],v[3]}end
local function near(a,b,t)
 if not(a and b)then return false end
 local x,y,z=a[1]-b[1],a[2]-b[2],a[3]-b[3];return x*x+y*y+z*z<=(t or .01)^2
end
local function same(a,b)return a~=nil and b~=nil and a==b end
local function pose_near(a,b)
 return a and b and near(a.position,b.position,.025)and near(a.forward,b.forward,.01)
  and near(a.right,b.right,.01)and near(a.up,b.up,.01)
end
function M.new(sr,player_reader,log,clock)
 local self={epoch=0,retired=false,reason='Camera not discovered'};local accepted,verified,written;local validate
 local history={};local history_scope;local serial=0
 local V=sr.Vector3;local A,W,U,C,B=sr.Application,sr.World,sr.Unit,sr.Camera,sr.Matrix4x4
 local function clear_history()history={};history_scope=nil end
 local function now()
  local source=clock
  if not source then
   local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
   source=api and api.camera_input and api.camera_input.now
  end
  if type(source)=='function'then local ok,time=pcall(source);if ok and finite(time)then return time,source end end
 end
 local function numeric_pose(p)
  return{position=copy(p.position),forward=copy(p.forward),right=copy(p.right),up=copy(p.up)}
 end
 local function exact_pose(a,b)
  return near(a.position,b.position,1e-7)and near(a.forward,b.forward,1e-7)
   and near(a.right,b.right,1e-7)and near(a.up,b.up,1e-7)
 end
 local function scope(world,player)
  if not history_scope or history_scope.world~=world or history_scope.player~=player.root_handle or history_scope.identity~=player.identity then
   clear_history();history_scope={world=world,player=player.root_handle,identity=player.identity}
  end
 end
 local function observation(unit,cam,pose)
  local entry
  for _,item in ipairs(history)do if same(item.unit,unit)and same(item.cam,cam)then entry=item;break end end
  if not entry then entry={unit=unit,cam=cam};history[#history+1]=entry end
  if entry.current and not exact_pose(entry.current,pose)then entry.previous=entry.current;entry.current=nil end
  if not entry.current then entry.current=numeric_pose(pose)end
  local time,source=now();entry.current.serial=serial;entry.current.time=time;entry.current.clock=source
  return entry
 end
 local function phase_match(entry,rendered)
  -- Two distinct observed transforms, never an accumulating trail. Repeated
  -- update/render probes of the same transform refresh it without evicting the
  -- preceding engine update. Stored values are numbers, not engine poses.
  local time,source=now()
  for _,pose in pairs({entry.current,entry.previous})do
   local recent=serial-pose.serial<=16
   if pose.time~=nil then recent=source==pose.clock and time~=nil and time>=pose.time and time-pose.time<=.25 end
   if recent and pose_near(pose,rendered)then return true end
  end
  return false
 end
 local function vector(v)
  if v==nil then return nil end
  local ok,x,y,z=pcall(function()
   if type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])then return v[1],v[2],v[3]end
   return V.x(v),V.y(v),V.z(v)
  end)
  if ok and finite(x)and finite(y)and finite(z)then return{x,y,z}end
 end
 local function read(fn,...)
  if type(fn)~='function'then return nil end
  local ok,value=pcall(fn,...);if ok then return value end
 end
 local function basis(pose)
  if not pose or not B then return nil end
  local p=vector(read(B.translation,pose));local f=vector(read(B.forward,pose))
  local r=vector(read(B.right,pose));local u=vector(read(B.up,pose))
  if not(p and f and r and u)then return nil end
  local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
  for _,axis in ipairs({f,r,u})do if math.abs(dot(axis,axis)-1)>.02 then return nil end end
  if math.abs(dot(f,r))>.01 or math.abs(dot(f,u))>.01 or math.abs(dot(r,u))>.01 then return nil end
  local cross={r[2]*f[3]-r[3]*f[2],r[3]*f[1]-r[1]*f[3],r[1]*f[2]-r[2]*f[1]}
  if dot(cross,u)<.98 then return nil end
  return{position=p,forward=f,right=r,up=u}
 end
 local function refused(why,retired)
  verified=nil;self.reason=why
  if retired and accepted and not accepted.retired then
   accepted.retired=true;self.epoch=self.epoch+1;written=nil;self.written=nil;clear_history()
  end
  self.retired=accepted~=nil and accepted.retired==true
  return nil,why
 end
 local function identity(a,b)
  return a and b and same(a.world,b.world)and same(a.unit,b.unit)and same(a.cam,b.cam)
   and same(a.player,b.player)and a.player_identity==b.player_identity
 end
 local function contains(list,value)
  for _,item in pairs(list)do if same(item,value)then return item end end
 end
 local function prior_retired(world,units)
  if not accepted or accepted.retired or not same(world,accepted.world)then return false end
  -- The verified player reader can itself disappear during death/respawn.
  -- Prove absence first; never ask Unit.alive about a cached, absent handle.
  local player,unit=contains(units,accepted.player),contains(units,accepted.unit)
  if not player or not unit then refused(not player and'Local player retired from the main world'or'Camera unit left the main world',true);return true end
  if read(U.alive,player)==false or read(U.alive,unit)==false then refused('Player or camera unit retired',true);return true end
  return false
 end
 function self.refresh(force)
  serial=serial+1
  -- Once discovery has proved uniqueness, retain that exact camera until its
  -- render/owner proof fails. Re-enumerating every Unit's camera count on every
  -- draw is expensive; narrow validation still obtains genuine current handles.
  if not force and accepted and not accepted.retired then
   local current,why,rediscover=validate(accepted)
   if current==true then return verified end
   if current==nil and not rediscover then return nil,why end
  end
  verified=nil
  if not(A and W and U and C and B)then return refused('Camera engine API unavailable')end
  local world=read(A.main_world)
  if not world then return refused('Main world unavailable')end
  if accepted and not same(world,accepted.world)then refused('Main world replaced',true)end
  if type(A.worlds)=='function'then
   local worlds=read(A.worlds)
   if type(worlds)~='table'then clear_history();return refused('World inventory unavailable')end
   if not contains(worlds,world)then return refused('Main world is not in the current world inventory',true)end
  end
  local units=read(W.units,world)
  if type(units)~='table'then clear_history();return refused('Main-world unit inventory unavailable')end
  prior_retired(world,units)
  local reader=type(player_reader)=='function'and player_reader or type(player_reader)=='table'and player_reader.frame
  local player=read(reader)
  if type(player)~='table'or player.local_owner~=true or player.identity==nil or player.root_handle==nil then
   clear_history();return refused('Verified local player unavailable')
  end
  if not same(player.world,world)then return refused('Local player is not in the main world')end
  if accepted and(accepted.player_identity~=player.identity or not same(accepted.player,player.root_handle))then
   refused('Local player replaced',true)
  end
  local point=vector(player.position);if not point then return refused('Local player position unavailable')end
  local player_unit=contains(units,player.root_handle)
  if not player_unit then return refused('Local player retired from the main world',true)end
  local alive=read(U.alive,player_unit)
  if alive~=true then return refused('Local player is not alive',alive==false)end
  scope(world,player)
  local rendered=basis(read(W.debug_camera_pose,world))
  if not rendered then clear_history();return refused('Rendered main-world camera pose unavailable')end
  local candidate,count,incomplete=nil,0,false;local prior_present=false;local candidates={}
  local seen={}
  for _,unit in pairs(units)do
   if not seen[unit]then
    seen[unit]=true
    local live=read(U.alive,unit)
    if accepted and same(unit,accepted.unit)then
     prior_present=true
     if live==false then refused('Camera unit retired',true)end
    end
    if live==true then
     local n=read(U.num_cameras,unit)
     if not finite(n)or n<0 or n%1~=0 or n>32 then incomplete=true
     else
      local prior_camera=false;local cameras_complete=true
      for i=1,n do
       local cam=read(U.camera,unit,i)
       if accepted and same(unit,accepted.unit)and same(cam,accepted.cam)then prior_camera=true end
       if cam then
        local wp=vector(read(C.world_position,cam));local lp=vector(read(C.local_position,cam,unit))
        local pose=basis(read(C.world_pose,cam))
        if not(wp and lp and pose)then incomplete=true
        elseif near(wp,lp,.01)and near(wp,pose.position,.01)then
         candidates[#candidates+1]={world=world,unit=unit,cam=cam,player=player_unit,
          player_position=point,player_identity=player.identity,position=wp,
          forward=pose.forward,right=pose.right,up=pose.up,rendered=rendered,scene=self}
        end
       else incomplete=true;cameras_complete=false end
      end
      if accepted and same(unit,accepted.unit)and cameras_complete and not prior_camera then refused('Camera instance replaced',true)end
     end
    elseif live~=false then incomplete=true end
   end
  end
  if accepted and not prior_present then refused('Camera unit left the main world',true)end
  if incomplete then clear_history();return refused('Camera inventory is temporarily unreadable')end
  scope(world,player)
  local next_history={}
  for _,frame in ipairs(candidates)do
   local entry=observation(frame.unit,frame.cam,frame);next_history[#next_history+1]=entry
   if phase_match(entry,rendered)then
    local duplicate=false
    if candidate and same(candidate.unit,frame.unit)and same(candidate.cam,frame.cam)then duplicate=true end
    if not duplicate then count=count+1;candidate=frame end
   end
  end
  history=next_history -- Retired/replaced camera instances retain no history.
  if count~=1 then return refused(count>1 and'Rendered camera is ambiguous'or'No main-world camera matches the rendered view')end
  if not identity(accepted,candidate)then
   if not accepted or not accepted.retired then self.epoch=self.epoch+1 end
   written=nil;self.written=nil
  end
  candidate.epoch=self.epoch
  accepted=candidate;verified=candidate;self.retired=false;self.reason=nil
  return candidate
 end
 function self.current()return verified end
 validate=function(snapshot,lifetime_only)
  if type(snapshot)~='table'or not accepted or accepted.retired or snapshot.epoch~=self.epoch or not identity(snapshot,accepted)then
   return false,'Camera snapshot retired'
  end
  local function unavailable(why,retired)
   refused(why,retired);if self.retired then return false,why end;return nil,why
  end
  local world=read(A.main_world)
  if not world then return unavailable('Main world unavailable')end
  if not same(world,snapshot.world)then return unavailable('Main world replaced',true)end
  if type(A.worlds)=='function'then
   local worlds=read(A.worlds)
   if type(worlds)~='table'then clear_history();return unavailable('World inventory unavailable')end
   if not contains(worlds,world)then return unavailable('Main world retired',true)end
  end
  local units=read(W.units,world)
  if type(units)~='table'then clear_history();return unavailable('Main-world unit inventory unavailable')end
  if prior_retired(world,units)then return false,self.reason end
  local reader=type(player_reader)=='function'and player_reader or type(player_reader)=='table'and player_reader.frame
  local player=read(reader)
  if type(player)~='table'or player.local_owner~=true or player.identity==nil or player.root_handle==nil then
   clear_history();return unavailable('Verified local player unavailable')
  end
  if not same(player.world,world)then return unavailable('Local player is not in the main world')end
  if player.identity~=snapshot.player_identity or not same(player.root_handle,snapshot.player)then
   return unavailable('Local player replaced',true)
  end
  local point=vector(player.position);if not point then return unavailable('Local player position unavailable')end
  local player_unit,unit=contains(units,player.root_handle),contains(units,snapshot.unit)
  if not player_unit then return unavailable('Local player retired from the main world',true)end
  if not unit then return unavailable('Camera unit left the main world',true)end
  local player_alive,unit_alive=read(U.alive,player_unit),read(U.alive,unit)
  if player_alive==false or unit_alive==false then return unavailable('Player or camera unit retired',true)end
  if player_alive~=true or unit_alive~=true then return unavailable('Player or camera lifetime unavailable')end
  local count=read(U.num_cameras,unit)
  if not finite(count)or count<0 or count%1~=0 or count>32 then clear_history();return unavailable('Camera inventory unreadable')end
  local current_cam;local complete=true
  for i=1,count do local cam=read(U.camera,unit,i);if not cam then complete=false end;if same(cam,snapshot.cam)then current_cam=cam end end
  if not complete then clear_history();return unavailable('Camera instance temporarily unreadable')end
  if not current_cam then return unavailable('Camera instance replaced',true)end
  -- Cleanup restores only a compare-owned local position. It still needs the
  -- same live main-world/player/camera instance, but that instance may already
  -- have stopped being rendered. No render-pose or lens read belongs here.
  if lifetime_only then return true end
  local wp=vector(read(C.world_position,current_cam));local lp=vector(read(C.local_position,current_cam,unit))
  local pose=basis(read(C.world_pose,current_cam));local rendered=basis(read(W.debug_camera_pose,world))
  if not(wp and lp and pose and rendered)then clear_history();return unavailable('Rendered camera pose temporarily unavailable')end
  local root_pose=near(wp,lp,.01)and near(wp,pose.position,.01)
  local rendered_match=root_pose and pose_near(pose,rendered)
  local phase_lag=false
  if root_pose and not rendered_match and not written then
   -- A unique discovered camera may advance before the engine publishes its
   -- rendered pose. Reuse the same bounded numeric proof as discovery instead
   -- of rescanning every world's Unit at each update/render phase. More than
   -- one candidate still needs full discovery to recheck render uniqueness.
   scope(world,player)
   local entry=history[1]
   if #history==1 and same(entry.unit,unit)and same(entry.cam,current_cam)then
    phase_lag=phase_match(observation(unit,current_cam,pose),rendered)
   end
  end
  local own_lag=false
  if root_pose and not rendered_match and written and written.epoch==self.epoch and written.uses<8 then
   -- Only bridge our exact, successfully written view and its immediately
   -- preceding rendered pose. This permits one in-flight engine reset/lag;
   -- unrelated camera/debug poses can never acquire ownership this way.
   own_lag=pose_near(rendered,written)or(pose_near(pose,written)
    and(pose_near(rendered,written.before)or pose_near(rendered,written.rendered)))
   if own_lag then written.uses=written.uses+1 end
  end
  if not(rendered_match or own_lag or phase_lag)then
   unavailable('Current camera no longer matches the rendered view')
   return nil,self.reason,true -- Discovery may now find a different rendered camera.
  end
  local fresh={world=world,unit=unit,cam=current_cam,player=player_unit,player_identity=player.identity,
   player_position=point,position=wp,forward=pose.forward,right=pose.right,up=pose.up,rendered=rendered,epoch=self.epoch,scene=self}
  accepted=fresh;verified=fresh;self.reason=nil;self.retired=false
  if rendered_match then scope(world,player);observation(unit,current_cam,pose)end
  return true
 end
 function self.valid(snapshot)
  serial=serial+1
  local ok,why,rediscover=validate(snapshot)
  if ok==nil and rediscover then
   local fresh,reason=self.refresh(true)
   if fresh then
    if snapshot.epoch~=self.epoch or not identity(snapshot,fresh)then return false,'Camera snapshot retired'end
    return true
   end
   if self.retired then return false,reason end;return nil,reason
  end
  return ok,why
 end
 function self.owned(snapshot)return validate(snapshot,true)end
 function self.mark_written(frame,position,forward,right,up)
  if not verified or frame.epoch~=self.epoch or not identity(frame,verified)then return false,'Camera snapshot is not verified'end
  local p,f,r,u=vector(position),vector(forward),vector(right),vector(up)
  if not(p and f and r and u)then return false,'Written camera pose is invalid'end
  written={epoch=self.epoch,position=copy(p),forward=copy(f),right=copy(r),up=copy(u),uses=0,
   before={position=copy(verified.position),forward=copy(verified.forward),right=copy(verified.right),up=copy(verified.up)},
   rendered=verified.rendered}
  self.written=written
  return true
 end
 function self.clear_written(frame)
  -- The owned-write bridge ends with its lease. Numeric observations of a
  -- genuinely rendered camera remain useful for an immediate same-scene reopen;
  -- they still expire by time/generation and cannot bypass lifetime/uniqueness.
  if written and type(frame)=='table'and frame.epoch==written.epoch then written=nil;self.written=nil end
  return true
 end
 return self
end
return M

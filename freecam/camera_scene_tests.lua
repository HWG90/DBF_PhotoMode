local root=DBF_PHOTO_TEST_ROOT or'freecam/'
local counted_lists=setmetatable({}, {__mode='k'})
local scene_env=setmetatable({pairs=function(list)
 local state=counted_lists[list];if state then state.unit_walks=(state.unit_walks or 0)+1 end
 return pairs(list)
end}, {__index=_G})
local Scene=setfenv(assert(loadfile(root..'camera_scene.lua')),scene_env)()
local function point(x,y,z)return{x or 0,y or 0,z or 0}end
local function pose(p,f,r,u)return{p=p,f=f or{1,0,0},r=r or{0,-1,0},u=u or{0,0,1}}end
local function fixture()
 local world={name='main'}
 local player={name='player'};local unit={name='camera'};local cam={name='camera-instance'}
 local S={world=world,units={player,unit},player=player,unit=unit,cam=cam,identity='local:1',p={2,3,4},
  wp={0,0,1},lp={0,0,1},rendered=pose({0,0,1}),camera_pose=pose({0,0,1}),live={},calls=0,time=0,camera_data={}}
 S.live[player]=true;S.live[unit]=true
 local function genuine(u)
  if S.poison_native then S.poison_touches=(S.poison_touches or 0)+1;error('Retired post-reader Unit access')end
  for _,entry in ipairs(S.units)do if entry==u then return true end end
  error('Native Unit call on a stale or invented handle')
 end
 local sr={Application={},World={},Unit={},Camera={},Matrix4x4={}}
 sr.Vector3=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  {__call=function(_,...)return{...}end})
 function sr.Application.main_world()if S.main_error then error('main unavailable')end;return S.world end
 function sr.Application.worlds()return S.worlds or{S.world}end
 function sr.World.units(w)assert(w==S.world);S.unit_reads=(S.unit_reads or 0)+1;if S.units_error then error('units unavailable')end;counted_lists[S.units]=S;return S.units end
 function sr.World.debug_camera_pose(w)assert(w==S.world);return S.rendered end
 function sr.Unit.alive(u)genuine(u);S.calls=S.calls+1;if S.alive_error then return nil end;return S.live[u]end
 function sr.Unit.num_cameras(u)genuine(u);S.counts=(S.counts or 0)+1;if S.count_error then return nil end;return u==S.unit and 1 or u==S.second and 1 or 0 end
 function sr.Unit.camera(u,i)genuine(u);assert(i==1);if S.camera_error then error('camera temporarily unreadable')end;return u==S.second and S.second_cam or S.cam end
 function sr.Camera.world_position(c)assert(c==S.cam or c==S.second_cam);return S.camera_data[c]and S.camera_data[c].wp or S.wp end
 function sr.Camera.local_position(c,u)genuine(u);return S.camera_data[c]and S.camera_data[c].lp or S.lp end
 function sr.Camera.world_pose(c)return S.camera_data[c]and S.camera_data[c].pose or S.camera_pose end
 for name,key in pairs({translation='p',forward='f',right='r',up='u'})do sr.Matrix4x4[name]=function(m)return m[key]end end
 local function read()
  if S.on_player_read then S.on_player_read()end
  if S.player_error then error('player temporarily unavailable')end
  if S.player_nil then return nil end
  return{local_owner=S.local_owner~=false,identity=S.identity,root_handle=S.player,position=S.p,world=S.player_world or S.world}
 end
 S.scene=Scene.new(sr,read,function()end,function()if S.clock_error then error('clock unavailable')end;return S.time end);return S
end
do
 local s=fixture();local frame=assert(s.scene.refresh())
 assert(frame.world==s.world and frame.player==s.player and frame.unit==s.unit and frame.cam==s.cam)
 assert(frame.epoch==1 and frame.player_identity=='local:1'and frame.position[3]==1 and frame.player_position[1]==2)
 assert(s.scene.valid(frame)==true)
 s.player_error=true;assert(s.scene.refresh()==nil and not s.scene.retired and s.scene.current()==nil)
 assert(s.scene.epoch==1 and s.scene.valid(frame)==nil)
 s.player_error=false;assert(s.scene.refresh().epoch==1,'transient read refusal must retain identity')
 s.units_error=true;assert(s.scene.valid(frame)==nil);s.units_error=false
 s.main_error=true;assert(s.scene.valid(frame)==nil);s.main_error=false
 assert(s.scene.valid(frame)==true)
 s.camera_error=true;assert(s.scene.valid(frame)==nil and s.scene.epoch==1 and not s.scene.retired)
 assert(s.scene.refresh(true)==nil and s.scene.epoch==1,'an unavailable camera read does not prove retirement')
 s.camera_error=false;assert(s.scene.refresh().epoch==1)
end
do
 local s=fixture();local frame=assert(s.scene.refresh())
 s.units={s.player};assert(s.scene.valid(frame)==false and s.scene.retired and s.scene.epoch==2)
 assert(s.scene.valid(frame)==false and s.scene.epoch==2,'retirement must increment only once')
 s.unit={name='replacement-camera'};s.cam={};s.live[s.unit]=true;s.units={s.player,s.unit}
 local next_frame=assert(s.scene.refresh());assert(next_frame.epoch==2 and not s.scene.retired)
 assert(s.scene.valid(frame)==false)
end
do
 local s=fixture()
 for i=1,250 do local unit={};s.live[unit]=true;s.units[#s.units+1]=unit end
 local frame=assert(s.scene.refresh());local calls=s.counts
 assert(s.scene.valid(frame)==true and s.counts-calls==1,'retained validation must not scan unrelated camera counts')
 calls=s.counts;assert(s.scene.refresh()and s.counts-calls==1,'normal refresh uses narrow ownership validation')
end
do
 local s=fixture();local frame=assert(s.scene.refresh())
 s.identity='local:2';local replacement=assert(s.scene.refresh());assert(replacement.epoch==2)
 assert(s.scene.valid(frame)==false)
 s.cam={};assert(s.scene.refresh().epoch==3,'camera replacement must advance the scene epoch')
 s.world={name='new-main'};assert(s.scene.refresh().epoch==4,'world replacement must advance the scene epoch')
end
do
 local s=fixture();assert(s.scene.refresh())
 s.second={};s.second_cam={};s.live[s.second]=true;s.units[#s.units+1]=s.second
 assert(s.scene.refresh(true)==nil and s.scene.reason:find('ambiguous',1,true))
 s.units={s.player,s.unit};s.lp={1,0,1};assert(s.scene.refresh()==nil,'parented/non-root camera refused')
 s.lp={0,0,1};s.camera_pose=pose({0,0,1},{0,1,0},{1,0,0},{0,0,1})
 assert(s.scene.refresh()==nil,'position alone cannot identify a rendered camera')
 s.camera_pose=pose({0,0,1});s.rendered=pose({0/0,0,1});assert(s.scene.refresh()==nil,'NaN rendered pose refused')
 s.rendered=pose({0,0,1});s.p={math.huge,0,0};assert(s.scene.refresh()==nil)
 s.p={2,3,4};s.local_owner=false;assert(s.scene.refresh()==nil)
 s.local_owner=true;s.player_world={};assert(s.scene.refresh()==nil,'foreign-world player refused')
 s.player_world=nil;s.worlds={{name='UI'}};assert(s.scene.refresh()==nil,'non-current main world refused')
end
do
 local s=fixture();local frame=assert(s.scene.refresh());local old=s.scene.epoch
 assert(s.scene.mark_written(frame,{5,6,7},frame.forward,frame.right,frame.up))
 s.wp={5,6,7};s.lp={5,6,7};s.camera_pose=pose({5,6,7});s.rendered=pose({5,6,7})
 assert(s.scene.refresh().epoch==old,'our frozen render pose must not cause rediscovery or retirement')
 assert(s.scene.valid(frame)==true)
 s.live[s.player]=false;assert(s.scene.valid(frame)==false)
end
do
 local s=fixture();local frame=assert(s.scene.refresh())
 assert(s.scene.mark_written(frame,{5,6,7},frame.forward,frame.right,frame.up))
 s.wp={5,6,7};s.lp={5,6,7};s.camera_pose=pose({5,6,7})
 assert(s.scene.valid(frame)==true,'own successful write may precede the rendered debug pose')
 s.rendered=pose({5,6,7});s.wp={1,2,3};s.lp={1,2,3};s.camera_pose=pose({1,2,3})
 assert(s.scene.valid(frame)==true,'an exact last-written rendered pose permits the same camera to be reset by the engine')
 for i=1,6 do assert(s.scene.valid(frame)==true)end
 assert(s.scene.valid(frame)==nil,'owned render lag is bounded until another successful owned write')
 assert(s.scene.owned(frame)==true,'compare-owned cleanup remains possible after render proof expires')
 s.scene.clear_written(frame);assert(s.scene.valid(frame)==nil,'completed cleanup clears the owned pose bridge')
 s.camera_pose=pose({1,2,3},{0,1,0},{1,0,0},{0,0,1})
 assert(s.scene.owned(frame)==true,'lifetime-only cleanup is independent of a restored/foreign lens orientation')
 s.world={};assert(s.scene.owned(frame)==false,'cleanup does not bypass world retirement')
end
do
 local s=fixture();local frame=assert(s.scene.refresh())
 assert(s.scene.mark_written(frame,{5,6,7},frame.forward,frame.right,frame.up))
 s.wp={8,8,8};s.lp={8,8,8};s.camera_pose=pose({8,8,8});s.rendered=pose({9,9,9})
 assert(s.scene.valid(frame)==nil,'unrelated mismatched poses cannot use an owned-write bridge')
 s.player_error=true;s.units={s.unit}
 assert(s.scene.refresh()==nil and s.scene.retired and s.scene.epoch==2,
  'unavailable player reader cannot mask an avatar absent from the fresh genuine unit list')
 assert(s.scene.owned(frame)==false)
 s=fixture();frame=assert(s.scene.refresh());s.player_error=true;s.live[s.player]=false
 assert(s.scene.valid(frame)==false and s.scene.retired,'unavailable reader cannot mask a confirmed dead avatar')
 s=fixture();frame=assert(s.scene.refresh());s.player_error=true;s.units_error=true
 assert(s.scene.valid(frame)==nil and not s.scene.retired,'unavailable inventory is not proof of avatar retirement')
end
local function moving_pose(s,x,angle)
 local c,t=math.cos(angle or 0),math.sin(angle or 0)
 s.wp={x,x*.25,1};s.lp={x,x*.25,1};s.camera_pose=pose({x,x*.25,1},{c,t,0},{t,-c,0},{0,0,1})
end
do
 local s=fixture();moving_pose(s,0,0);s.rendered=s.camera_pose
 local frame=assert(s.scene.refresh())
 for tick=1,90 do
  assert(s.scene.refresh(),'before-update rendered camera remains ready')
  moving_pose(s,tick*.25,tick*.01);s.time=s.time+1/120
  for probe=1,8 do
   local fresh=assert(s.scene.refresh(),'one-update camera/debug skew must not discard readiness')
   assert(fresh.epoch==frame.epoch and fresh.position[1]==tick*.25)
   assert(s.scene.valid(frame)==true,'repeated pre-render validation must retain the preceding observed transform')
  end
  s.rendered=s.camera_pose
  local drawn=assert(s.scene.refresh())
  if tick==45 then
   assert(s.scene.mark_written(drawn,drawn.position,drawn.forward,drawn.right,drawn.up))
   assert(s.scene.clear_written(drawn)and s.scene.written==nil)
   -- The next iteration represents immediate reopening after normal cleanup.
  end
 end
 assert(s.scene.epoch==1,'continuous directional/rotational motion is not camera replacement')
end
do
 local s=fixture();moving_pose(s,0);s.rendered=s.camera_pose;assert(s.scene.refresh())
 moving_pose(s,1);assert(s.scene.refresh(),'fresh numeric history bridges one prior game update')
 s.time=.30;assert(s.scene.refresh()==nil,'historical render proof expires in real time')
 s.rendered=s.camera_pose;assert(s.scene.refresh(),'actual current render proof recovers readiness')
 moving_pose(s,2);s.count_error=true;assert(s.scene.refresh()==nil)
 s.count_error=false;assert(s.scene.refresh(true)==nil,'unknown camera inventory clears historical proof')
 s.rendered=s.camera_pose;assert(s.scene.refresh())
 moving_pose(s,3);s.units_error=true;assert(s.scene.refresh()==nil)
 s.units_error=false;assert(s.scene.refresh(true)==nil,'unknown World.units cannot reuse a previous historical proof')
 s.rendered=s.camera_pose;local old=assert(s.scene.refresh())
 s.unit={};s.cam={};s.live[s.unit]=true;s.units={s.player,s.unit};moving_pose(s,4)
 assert(s.scene.refresh()==nil and s.scene.retired,'camera replacement cannot inherit the prior instance history')
 assert(s.scene.valid(old)==false)
 s.rendered=s.camera_pose;assert(s.scene.refresh().epoch==2)
end
do
 local s=fixture();moving_pose(s,0);s.rendered=s.camera_pose
 s.second={};s.second_cam={};s.live[s.second]=true;s.units[#s.units+1]=s.second
 s.camera_data[s.second_cam]={wp={50,0,1},lp={50,0,1},pose=pose({50,0,1})}
 assert(s.scene.refresh())
 moving_pose(s,1)
 s.camera_data[s.second_cam]={wp={0,0,1},lp={0,0,1},pose=pose({0,0,1})}
 assert(s.scene.refresh()==nil and s.scene.reason:find('ambiguous',1,true),
  'a current matching camera and a different historical matching camera are ambiguous')
 s.rendered=pose({999,999,1});assert(s.scene.refresh()==nil,'unmatched unrelated render poses remain refused')
end
do
 local s=fixture();s.clock_error=true;moving_pose(s,0);s.rendered=s.camera_pose;assert(s.scene.refresh())
 moving_pose(s,1);assert(s.scene.refresh())
 for i=1,20 do s.scene.refresh()end
 assert(s.scene.refresh()==nil,'without a clock, a bounded observation serial prevents indefinite history retention')
 s.rendered=s.camera_pose;assert(s.scene.refresh())
end
do
 local s=fixture()
 for i=1,1000 do local unit={};s.live[unit]=true;s.units[#s.units+1]=unit end
 moving_pose(s,0);s.rendered=s.camera_pose;assert(s.scene.refresh())
 local initial_counts,initial_alive=s.counts,s.calls
 for tick=1,60 do
  assert(s.scene.refresh()) -- Before update, the previous render is exact.
  moving_pose(s,tick*.25,tick*.01);s.time=s.time+1/120
  local frame=assert(s.scene.refresh()) -- After update, debug pose lags.
  assert(s.scene.refresh()) -- Pre-render observes the same bounded proof.
  assert(s.scene.valid(frame)) -- Motion validates before its own writes.
  assert(s.scene.valid(frame)) -- Its second check cannot trigger discovery.
  s.rendered=s.camera_pose
 end
 assert(s.counts-initial_counts==60*5,
  'one unique camera must use narrow camera validation, never a full Unit camera scan during phase skew')
 assert(s.calls-initial_alive==60*5*2,
  'each validation must check its fresh player/camera once without touching unrelated Units')
 assert(s.scene.epoch==1,'phase-only movement must not retire or replace the current scene')
end
do
 local s=fixture();local original=assert(s.scene.refresh())
 local reads,walks,alive=s.unit_reads,s.unit_walks,s.calls
 assert(s.scene.valid(original)==true)
 assert(s.unit_reads-reads==1 and s.unit_walks-walks==1 and s.calls-alive==2,
  'retained validation must obtain one fresh Unit list and find both genuine handles in one traversal')
 local fresh=s.scene.current();assert(fresh~=original and fresh.position~=original.position)
 s.wp={4,5,6};s.lp={4,5,6};s.camera_pose=pose(s.wp);s.rendered=s.camera_pose
 assert(s.scene.valid(fresh)==true and s.unit_reads-reads==2)
 assert(original.position[1]==0 and fresh.position[1]==0 and s.scene.current().position[1]==4,
  'new numeric observations must never mutate externally retained snapshots')
 local frame=s.scene.current();local p,f,r,u={8,9,10},{1,0,0},{0,-1,0},{0,0,1}
 assert(s.scene.mark_written(frame,p,f,r,u));p[1]=999;f[1]=0;r[2]=0;u[3]=0
 assert(s.scene.written.position[1]==8 and s.scene.written.forward[1]==1 and s.scene.written.right[2]==-1 and s.scene.written.up[3]==1,
  'owned-write numeric state must remain isolated from caller mutations')
 s.alive_error=true;reads=s.unit_reads
 assert(s.scene.valid(frame)==nil and not s.scene.retired and s.unit_reads==reads+1,
  'a new unreadable lifetime result cannot reuse a previous successful validation')
 s.alive_error=false;s.units={s.player}
 assert(s.scene.valid(frame)==false and s.scene.retired,
  'removal between validations must be detected before any Unit call on the removed camera')
end
do
 local s=fixture();s.player=s.unit;s.units={s.unit};local frame=assert(s.scene.refresh())
 local reads,alive=s.unit_reads,s.calls
 assert(s.scene.valid(frame)==true and s.unit_reads==reads+1 and s.calls==alive+1,
  'a player-owned camera Unit needs only one alive read per invocation')
 s.alive_error=true;alive=s.calls
 assert(s.scene.valid(frame)==nil and s.calls==alive+1,'unreadable shared-handle life must not be sampled twice')
end
do
 local s=fixture();local frame=assert(s.scene.refresh());local counts=s.counts
 s.on_player_read=function()s.live[s.unit]=false end
 assert(s.scene.valid(frame)==false and s.scene.retired and s.counts==counts,
  'death during the player reader must be checked before any camera inventory API')
 s=fixture();frame=assert(s.scene.refresh());counts=s.counts
 s.on_player_read=function()s.live[s.player]=false end;s.player_error=true
 assert(s.scene.valid(frame)==false and s.scene.retired and s.counts==counts,
  'a failed player reader must not hide a present avatar that has died')
end
-- A reader may report the next avatar/world before the old Unit can safely be queried.
do
 for _,change in ipairs({'avatar','player_world','main_world','failed_reader_world'})do
  local s=fixture();local frame=assert(s.scene.refresh())
  s.on_player_read=function()
   s.poison_native=true
   if change=='avatar'then s.identity='local:replacement';s.player={}
   elseif change=='player_world'then s.player_world={}
   else s.world={};if change=='failed_reader_world'then s.player_error=true end end
  end
  assert(s.scene.valid(frame)~=true and not s.poison_touches,
   'returned/replaced player or world must reject old post-reader Unit APIs: '..change)
 end
end
do
 for _,failure in ipairs({'throw_removed_camera','nil_removed_player','nil_unknown_inventory'})do
  local s=fixture();local frame=assert(s.scene.refresh())
  s.on_player_read=function()
   s.poison_native=true
   if failure=='throw_removed_camera'then s.player_error=true;s.units={s.player}
   elseif failure=='nil_removed_player'then s.player_nil=true;s.units={s.unit}
   else s.player_nil=true;s.units_error=true end
  end
  local valid=s.scene.valid(frame)
  assert(not s.poison_touches,'failed reader must not query an absent/unproven post-reader Unit: '..failure)
  if failure=='nil_unknown_inventory'then assert(valid==nil and not s.scene.retired)
  else assert(valid==false and s.scene.retired)end
 end
end
print('camera_scene_tests: rendered-camera identity, ambiguity, finite pose and retirement passed')

local root=DBF_PHOTO_TEST_ROOT or'freecam/'
local Scene=dofile(root..'camera_scene.lua')
local function point(x,y,z)return{x or 0,y or 0,z or 0}end
local function pose(p,f,r,u)return{p=p,f=f or{1,0,0},r=r or{0,-1,0},u=u or{0,0,1}}end
local function fixture()
 local world={name='main'}
 local player={name='player'};local unit={name='camera'};local cam={name='camera-instance'}
 local S={world=world,units={player,unit},player=player,unit=unit,cam=cam,identity='local:1',p={2,3,4},
  wp={0,0,1},lp={0,0,1},rendered=pose({0,0,1}),camera_pose=pose({0,0,1}),live={},calls=0}
 S.live[player]=true;S.live[unit]=true
 local function genuine(u)
  for _,entry in ipairs(S.units)do if entry==u then return true end end
  error('Native Unit call on a stale or invented handle')
 end
 local sr={Application={},World={},Unit={},Camera={},Matrix4x4={}}
 sr.Vector3=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  {__call=function(_,...)return{...}end})
 function sr.Application.main_world()if S.main_error then error('main unavailable')end;return S.world end
 function sr.Application.worlds()return S.worlds or{S.world}end
 function sr.World.units(w)assert(w==S.world);if S.units_error then error('units unavailable')end;return S.units end
 function sr.World.debug_camera_pose(w)assert(w==S.world);return S.rendered end
 function sr.Unit.alive(u)genuine(u);S.calls=S.calls+1;return S.live[u]end
 function sr.Unit.num_cameras(u)genuine(u);S.counts=(S.counts or 0)+1;return u==S.unit and 1 or u==S.second and 1 or 0 end
 function sr.Unit.camera(u,i)genuine(u);assert(i==1);if S.camera_error then error('camera temporarily unreadable')end;return u==S.second and S.second_cam or S.cam end
 function sr.Camera.world_position(c)assert(c==S.cam or c==S.second_cam);return S.wp end
 function sr.Camera.local_position(c,u)genuine(u);return S.lp end
 function sr.Camera.world_pose(c)return S.camera_pose end
 for name,key in pairs({translation='p',forward='f',right='r',up='u'})do sr.Matrix4x4[name]=function(m)return m[key]end end
 local function read()
  if S.player_error then error('player temporarily unavailable')end
  return{local_owner=S.local_owner~=false,identity=S.identity,root_handle=S.player,position=S.p,world=S.player_world or S.world}
 end
 S.scene=Scene.new(sr,read,function()end);return S
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
print('camera_scene_tests: rendered-camera identity, ambiguity, finite pose and retirement passed')

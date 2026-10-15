local root=DBF_PHOTO_TEST_ROOT or'freecam/'
local Scene=dofile(root..'camera_scene.lua')
local Original=dofile(root..'lens.lua')
local Guard=dofile(root..'camera_lens.lua')
local function close(a,b)return math.abs(a-b)<1e-9 end
local function pose()return{p={0,0,1},f={1,0,0},r={0,-1,0},u={0,0,1}}end
local function fixture()
 local s={world={},player={},unit={},cam={},identity='local:1',camera_calls=0,reads=0,writes=0,rotations=0}
 s.units={s.player,s.unit};s.live={[s.player]=true,[s.unit]=true};s.fovs={[s.cam]=math.rad(80)}
 local sr={Application={},World={},Unit={},Camera={},Matrix4x4={},Quaternion={}}
 local function genuine(u)
  for _,entry in ipairs(s.units or{})do if entry==u then return end end
  error('Native Unit call on a retired handle')
 end
 local function camera(c)
  s.camera_calls=s.camera_calls+1
  assert(c==s.cam,'Native Camera call on a retired instance')
 end
 sr.Vector3=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  {__call=function(_,...)return{...}end})
 function sr.Application.main_world()if s.world_error then error('world temporarily unreadable')end;return s.world end
 function sr.Application.worlds()return{s.world}end
 function sr.World.units(w)assert(w==s.world);if s.units_error then error('inventory temporarily unreadable')end;return s.units end
 function sr.World.debug_camera_pose(w)assert(w==s.world);return pose()end
 function sr.Unit.alive(u)genuine(u);return s.live[u]end
 function sr.Unit.num_cameras(u)genuine(u);return u==s.unit and 1 or 0 end
 function sr.Unit.camera(u,i)genuine(u);assert(i==1);if s.camera_error then error('camera slot unreadable')end;return s.cam end
 function sr.Camera.world_position(c)camera(c);return{0,0,1}end
 function sr.Camera.local_position(c,u)camera(c);genuine(u);return{0,0,1}end
 function sr.Camera.world_pose(c)camera(c);return pose()end
 function sr.Camera.vertical_fov(c)camera(c);s.reads=s.reads+1;return s.fovs[c]end
 function sr.Camera.set_vertical_fov(c,fov)
  camera(c);s.writes=s.writes+1
  if s.fov_error then error('FOV setter refused before write')end
  s.fovs[c]=fov
 end
 function sr.Camera.set_local_rotation(c,u,q)
  camera(c);genuine(u);s.rotations=s.rotations+1
  if s.rotation_error then error('Rotation failed after FOV write')end
 end
 function sr.Quaternion.look(f,u)return{forward=f,up=u}end
 for name,key in pairs({translation='p',forward='f',right='r',up='u'})do sr.Matrix4x4[name]=function(m)return m[key]end end
 local function player()
  if s.player_error then error('player reader unavailable')end
  return{local_owner=true,identity=s.identity,root_handle=s.player,position={0,0,0},world=s.world}
 end
 s.scene=Scene.new(sr,player,function()end)
 s.factory=Guard.new(Original,function()if s.scene_error then error('scene reader unavailable')end;return s.scene end)
 s.lens=s.factory.new(sr);s.sr=sr
 function s.refresh()return assert(s.scene.refresh())end
 function s.apply(fov)
  local f=s.refresh();return s.lens.apply(f.cam,f.unit,f.forward,f.right,{fov=fov or 60,roll=0})
 end
 function s.replace_camera()
  local old=s.cam;s.cam={};s.fovs[s.cam]=math.rad(90);return old
 end
 return s
end
do
 local s=fixture()
 assert(s.factory.up==Original.up and s.factory.depth==Original.depth,'static lens helpers retain their original identity')
 local up=s.factory.up({1,0,0},{0,-1,0},0);assert(up[3]==1)
 assert(s.factory.depth(2,2,math.rad(60)).near>0)
 assert(s.lens.release()and s.camera_calls==0,'unused wrapper performs no native cleanup')
 assert(close(s.apply(),math.rad(60))and close(s.fovs[s.cam],math.rad(60)))
 assert(s.lens.release()and close(s.fovs[s.cam],math.rad(80)),'owned camera restores original FOV')
 assert(s.lens.release(),'cleanup acknowledgment is idempotent')
 s.apply(50);s.fovs[s.cam]=math.rad(72);local writes=s.writes
 assert(s.lens.release()and s.writes==writes and close(s.fovs[s.cam],math.rad(72)),'foreign FOV change is preserved by original compare-owned restoration')
end
do
 local s=fixture();s.apply();local old=s.replace_camera();local calls=s.camera_calls
 assert(s.live[s.unit]and s.lens.release(),'camera replacement retires lens even while its Unit remains alive')
 assert(s.camera_calls==calls and close(s.fovs[old],math.rad(60)),'retired Camera is never read or restored')
 s.apply(55);assert(s.lens.release()and close(s.fovs[s.cam],math.rad(90)),'fresh implementation snapshots the replacement camera baseline')
end
do
 local s=fixture();s.apply();s.units={s.player};local calls=s.camera_calls
 assert(s.lens.release()and s.camera_calls==calls,'absent camera Unit discards saved lens without a stale native call')
 s=fixture();s.apply();s.world={};calls=s.camera_calls
 assert(s.lens.release()and s.camera_calls==calls,'world replacement discards saved lens without a stale native call')
 s=fixture();s.apply();s.live[s.unit]=false;calls=s.camera_calls
 assert(s.lens.release()and s.camera_calls==calls,'dead inventoried camera Unit never reaches the original lens release')
end
do
 local s=fixture();s.apply();s.units_error=true;local calls=s.camera_calls
 local ok,why=s.lens.release()
 assert(ok==false and type(why)=='string'and s.camera_calls==calls,'unreadable inventory leaves cleanup pending without Camera calls')
 s.units_error=false
 assert(s.lens.release()and close(s.fovs[s.cam],math.rad(80)),'cleanup retries safely when inventory returns')
 s=fixture();s.apply();s.camera_error=true;calls=s.camera_calls
 assert(s.lens.release()==false and s.camera_calls==calls,'unreadable camera slot is unknown, not retirement')
 s.camera_error=false;assert(s.lens.release()and close(s.fovs[s.cam],math.rad(80)))
 s=fixture();s.apply();s.player_error=true;calls=s.camera_calls
 assert(s.lens.release()==false and s.camera_calls==calls,'unreadable local owner retains cleanup without Camera calls')
 s.player_error=false;assert(s.lens.release())
end
do
 local s=fixture();s.rotation_error=true
 local ok,why=pcall(s.apply)
 assert(not ok and tostring(why):find('Rotation failed',1,true)and close(s.fovs[s.cam],math.rad(60)))
 s.rotation_error=false
 assert(s.lens.release()and close(s.fovs[s.cam],math.rad(80)),'ownership snapshot precedes partial real-lens writes')
 s=fixture();s.rotation_error=true;assert(not pcall(s.apply));s.replace_camera();local calls=s.camera_calls
 assert(s.lens.release()and s.camera_calls==calls,'partially applied lens also discards safely after Camera retirement')
 s=fixture();s.apply();s.fov_error=true
 assert(s.lens.release()==false,'failed restore retains its scene snapshot for retry')
 s.fov_error=false;assert(s.lens.release()and close(s.fovs[s.cam],math.rad(80)))
end
do
 local s=fixture();s.refresh();local calls=s.camera_calls
 assert(not pcall(s.lens.apply,{},s.unit,{1,0,0},{0,-1,0},{fov=60,roll=0})and s.camera_calls==calls,'unverified supplied camera is rejected before the real lens')
 assert(s.lens.release()and s.camera_calls==calls,'rejected apply creates no cleanup obligation')
 s.apply();s.scene_error=true;calls=s.camera_calls
 assert(s.lens.release()==false and s.camera_calls==calls,'scene-reader failure retains cleanup')
 s.scene_error=false;local original=s.scene;s.scene=Scene.new(s.sr,function()end,function()end)
 assert(s.lens.release()==false and s.camera_calls==calls,'foreign validator cannot authorize restoration of the saved scene')
 s.scene=original;assert(s.lens.release())
end
print('camera_lens_tests: real lens/scene restoration, stale Camera retirement, inventory gaps, partial writes and compare-owned FOV passed')

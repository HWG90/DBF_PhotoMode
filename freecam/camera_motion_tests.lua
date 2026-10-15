local root=DBF_PHOTO_TEST_ROOT or'freecam/'
local Motion=dofile(root..'camera_motion.lua');local Look=dofile(root..'look.lua')
local function copy(p)return{p[1],p[2],p[3]}end
local function close(a,b)return math.abs(a-b)<1e-6 end
local function fixture()
 local s={writes=0,updates=0,effects=0,valid=true,current={10,0,2},order={}}
 local frame={world={},unit={},cam={},player={},player_identity='p:1',epoch=1,
  position={10,0,2},player_position={10,0,2},forward={1,0,0},right={0,-1,0},up={0,0,1}}
 local photo={active=true,options={fov=45,roll=0},input={sequence=1,dt=.1,forward=true,mouse_x=0,mouse_y=0}}
 local scene={}
 function scene.valid(f)if s.valid==true then return f.epoch==frame.epoch end;return s.valid,'scene unavailable'end
 function scene.owned(f)if s.cleanup_valid~=nil then return s.cleanup_valid,'cleanup lifetime unavailable'end;return scene.valid(f)end
 function scene.clear_written()s.cleared=(s.cleared or 0)+1;return true end
 function scene.mark_written(f,p)s.marked=copy(p);return true end
 frame.scene=scene
 local sr={Camera={},World={}}
 sr.Vector3=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},
  {__call=function(_,...)return{...}end})
 function sr.Camera.local_position(cam,unit)assert(cam==frame.cam and unit==frame.unit);return s.current end
 function sr.Camera.set_local_position(cam,unit,p)
  assert(cam==frame.cam and unit==frame.unit);s.order[#s.order+1]='position';s.writes=s.writes+1;s.current=copy(p)
  if s.setter_fail then error('position setter failed after write')end
 end
 function sr.World.update_unit(world,unit)
  assert(world==frame.world and unit==frame.unit);s.updates=s.updates+1
  if s.update_fail then error('update refused')end
 end
 local runtime={apply=function(cam,unit,world,f,r,o,dt)
  assert(world==frame.world,'photo_runtime requires the engine world as its third argument, never a discovery snapshot')
  s.effects=s.effects+1;s.fov=o.fov;s.forward=copy(f);s.effect_dt=dt
  if s.effect_fail then error('lens failed')end
  return false -- No active shader is a successful camera render.
 end}
 local freeze={hold=function()s.order[#s.order+1]='freeze';return not s.freeze_fail,'freeze refused'end}
 local cinema={state='place',hold=function()
  s.order[#s.order+1]='cinema'
  if s.cinema_fail then return false,'cinema refused'end
  if s.cinema_position then photo.pos=copy(s.cinema_position);photo.view={yaw=0,pitch=0,sequence=photo.input.sequence}end
  return true
 end}
 local config={PHOTO_SPEED=10,PHOTO_MAX_RANGE=500};local motion=Motion.new(sr,photo,Look,runtime,freeze,cinema,config,function()end)
 s.frame,s.photo,s.scene,s.motion,s.cinema,s.config=frame,photo,scene,motion,cinema,config;return s
end
do
 local s=fixture();assert(s.motion.apply(s.frame));assert(close(s.current[1],11),'input dt moves with zero simulation dt')
 assert(table.concat(s.order,',')=='cinema,freeze,position','holds must precede camera writes')
 s.photo.options.fov=70;assert(s.motion.apply(s.frame));assert(close(s.current[1],11)and s.effects==2 and s.fov==70,'redraw lens each render, movement once per sample')
 s.photo.input={sequence=2,dt=.1,forward=true,right=true,up=true}
 local before=copy(s.current);assert(s.motion.apply(s.frame))
 local x,y,z=s.current[1]-before[1],s.current[2]-before[2],s.current[3]-before[3]
 assert(close(math.sqrt(x*x+y*y+z*z),1),'diagonal movement is normalized')
 s.photo.input={sequence=3,dt=100,forward=true};before=copy(s.current);assert(s.motion.apply(s.frame))
 assert(close(s.current[1]-before[1],1),'paused or delayed input dt is clamped')
 s.photo.view={yaw=0,pitch=math.rad(60)};s.photo.input={sequence=4,dt=.1,forward=true,up=true}
 before=copy(s.current);assert(s.motion.apply(s.frame))
 x,y,z=s.current[1]-before[1],s.current[2]-before[2],s.current[3]-before[3]
 assert(close(math.sqrt(x*x+y*y+z*z),1),'pitched forward plus vertical movement is normalized in world space')
 s.photo.input={sequence=0/0,dt=.1,forward=true};before=copy(s.current)
 assert(s.motion.apply(s.frame)and s.current[1]==before[1]and s.current[3]==before[3],'invalid sequence cannot replay movement')
end
do
 local s=fixture();s.photo.input.mouse_x=20;assert(s.motion.apply(s.frame));local yaw=s.photo.view.yaw
 assert(s.motion.apply(s.frame));assert(s.photo.view.yaw==yaw,'mouse delta must not repeat on high-FPS redraws')
 s.photo.locked=true;s.photo.input={sequence=2,dt=.1,forward=true,mouse_x=40};local p=copy(s.current)
 assert(s.motion.apply(s.frame));assert(close(s.current[1],p[1])and s.photo.view.yaw==yaw and s.effects==3)
 s.photo.locked=false;s.photo.input={sequence=3,dt=.1,forward=true,mouse_x=100};assert(s.motion.apply(s.frame,true))
 assert(s.photo.view.yaw==yaw and close(s.current[1],p[1]),'native menu preserves view but still renders')
 assert(s.motion.apply(s.frame,false));assert(s.photo.view.yaw==yaw,'suspended mouse sample cannot replay when menu closes')
 s.photo.input={sequence=4,dt=.1,forward=true};assert(s.motion.apply(s.frame));assert(not close(s.current[1],p[1]))
end
do
 local s=fixture();s.config.PHOTO_MAX_RANGE=2;s.photo.input.dt=10;s.config.PHOTO_SPEED=1000
 assert(s.motion.apply(s.frame));assert(close(s.current[1],12),'range capped relative to current local player')
 s.cinema.state='perform';s.cinema_position={999,5,6};s.photo.input.sequence=2
 assert(s.motion.apply(s.frame));assert(s.current[1]==999 and s.current[2]==5,'cinema holds its view without input or freecam range clamp')
 assert(s.motion.release());assert(s.current[1]==10 and s.current[2]==0,'exit restores original owned camera position')
end
do
 local s=fixture();s.freeze_fail=true;assert(s.motion.apply(s.frame)==false and s.writes==0)
 s.freeze_fail=false;s.cinema_fail=true;assert(s.motion.apply(s.frame)==false and s.writes==0)
 s.cinema_fail=false;s.valid=nil;assert(s.motion.apply(s.frame)==false and s.writes==0)
 s.valid=true;assert(s.motion.apply(s.frame));s.valid=nil
 assert(s.motion.release()==false and s.motion.pending and s.writes==1,'unknown scene retains cleanup without writes')
 s.valid=true;assert(s.motion.release()and s.writes==2)
end
do
 local s=fixture();assert(s.motion.apply(s.frame));s.current={777,0,2}
 assert(s.motion.release()and s.writes==1 and s.current[1]==777,'foreign position owner is preserved')
 s=fixture();assert(s.motion.apply(s.frame));s.valid=false
 assert(s.motion.release()and s.writes==1,'retired scene never dereferenced for restoration')
 s=fixture();s.setter_fail=true;local ok,why=s.motion.apply(s.frame)
 assert(ok==false and why:find('setter failed',1,true)and s.motion.pending)
 s.setter_fail=false;assert(s.motion.release()and s.current[1]==10,'partial write remains available for compare-owned restoration')
 s=fixture();s.effect_fail=true;assert(s.motion.apply(s.frame)==false and s.motion.pending)
 s.effect_fail=false;assert(s.motion.release()and s.current[1]==10)
 s=fixture();assert(s.motion.apply(s.frame));s.update_fail=true
 assert(s.motion.release()==false and s.motion.pending and s.current[1]==10)
 local writes=s.writes;s.update_fail=false
 assert(s.motion.release()and s.writes==writes,'partial restore retries its world update without a second setter')
 s=fixture();assert(s.motion.apply(s.frame));local writes=s.writes
 assert(s.motion.release(function()return false end)and s.writes==writes,'explicit confirmed retirement does not dereference the old camera')
 s=fixture();assert(s.motion.apply(s.frame));s.valid=nil;s.cleanup_valid=true
 assert(s.motion.release()and s.current[1]==10 and s.cleared==1,
  'cleanup uses fresh camera lifetime plus position CAS despite transient rendered-pose refusal')
end
do
 local s=fixture();assert(s.motion.apply(s.frame));local swapped={}
 for k,v in pairs(s.frame)do swapped[k]=v end
 swapped.world={};swapped.unit={};swapped.cam={};swapped.epoch=2
 assert(s.motion.apply(swapped)==false and s.writes==1,'world/camera swap cannot reuse a position lease')
end
print('camera_motion_tests: zero-time movement, render/input cadence, holds and owned cleanup passed')

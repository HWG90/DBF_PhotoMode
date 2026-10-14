"""Execute the actual generated Photo render function in an isolated Lua fixture."""
from pathlib import Path
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT/'tools'))
import run_lua

spec = importlib.util.spec_from_file_location('cinema_photo_build', ROOT/'freecam/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
source = build.patch((ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_text(),
                     dof_candidate=True, native_candidate=True, combined_scene_candidate=True)
begin = source.index('function PHOTO.apply(cam, unit, pose, cx, cy, cz)')
end = source.index('-- High frame rates', begin)
render = source[begin:end]
assert "if hp and PHOTO.cinema_state~='perform' then" in render

fixture = r'''
local factory=dofile(PHOTO_ROOT..'cinema_camera.lua')
local look=dofile(PHOTO_ROOT..'look.lua');local lens_factory=dofile(PHOTO_ROOT..'lens.lua')
local PHOTO={active=true,pos={2,3,4},view={yaw=math.pi/2,pitch=.2},options={fov=60,roll=17},sample_sequence=7}
local player_point={3000,800,100};local camera_position={};local camera_rotation;local fov=.7;local updates=0;local stopped=false
local sr={Vector3=function(...)return {...}end,Quaternion={look=function(f,u)return{f=f,u=u}end},
 Unit={alive=function()return true end,world_position=function()return player_point end},
 Camera={vertical_fov=function()return fov end,set_vertical_fov=function(_,v)fov=v end,
  set_local_rotation=function(_,_,value)camera_rotation=value end,
  set_local_position=function(_,_,value)camera_position=value end},
 World={update_unit=function()updates=updates+1 end}}
local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return{...}end})
local M={forward=function(pose)return pose.forward end};local function xyz(v)return unpack(v)end
local function try(fn,...)local ok,value=pcall(fn,...);if ok then return value end end
local target={world='mission'};local anchor={unit='player',node=1};local counts={applied=0};local last_written;local last_dt=.016
local function anim_classify()return{dead=false}end;local function near_restore()end;local function restore_fov()end
local function log()end;local CFG={PHOTO_SPEED=10,PHOTO_MAX_RANGE=60}
local cinema=factory.new(PHOTO,function()return{world='mission',epoch=1,player='player'}end)
local H={dbf_cinema=cinema};local DBF_FREECAM_LOOK=look;local camera_lens=lens_factory.new(sr)
local DBF_PLAYER_FREEZE={hold=function()return true end};local native_open=false;local DBF_FREECAM={stop=function()stopped=true end,camera_suspended=function()return native_open end}
local DBF_SAVED_CAMERA={clear=function()end};local DBF_PHOTO_OPTIONS={defaults=PHOTO.options}
local DBF_PHOTO_RUNTIME={apply=function(cam,unit,world,forward,right,options,dt)
 assert(dt==0,'Gameplay input delta reached static camera movement')
 camera_lens.apply(cam,unit,forward,right,options)
end}
'''
fixture += render
fixture += r'''
assert(cinema.place()and cinema.prepare(math.rad(60))and cinema.commit())
for frame=1,100 do
 native_open=frame%2==0
 player_point={3000+frame*10,-500-frame,100};camera_position={unpack(player_point)};fov=.6
 PHOTO.input={sequence=frame,forward=true,right=true,up=true,mouse_x=1000,mouse_y=500,dt=.1}
 PHOTO.apply('camera','camera-unit',{forward={1,0,0}},unpack(camera_position))
 assert(camera_position[1]==2 and camera_position[2]==3 and camera_position[3]==4,'Static camera followed the distant avatar or sampled movement')
 assert(math.abs(fov-math.rad(60))<1e-8,'Game camera FOV overwrote the shot lens')
 assert(math.abs(camera_rotation.f[1])<1e-8 and math.abs(camera_rotation.f[2]-math.cos(.2))<1e-8,'Game camera rotation overwrote the shot orientation')
end
assert(not stopped and updates==100 and counts.applied==100,'Static camera failed to render continuously')
assert(cinema.reposition()and cinema.state=='place');cinema.stop()
print('Generated Cinema render: actual packaged Photo.apply with alternating native-menu input suspension holds position, orientation and FOV over 100 game/input updates; moving avatar does not activate the placement range clamp')
'''
bootstrap = ('PHOTO_ROOT='+repr((ROOT/'freecam').as_posix()+'/')+'\n').encode()
run_lua.run(bootstrap+fixture.encode(), 'cinema-generated-render')

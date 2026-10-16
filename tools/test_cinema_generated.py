"""Exercise the owned movement code embedded in the generated camera runtime."""
from pathlib import Path
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT/'tools'))
import run_lua

spec = importlib.util.spec_from_file_location('cinema_owned_build', ROOT/'freecam/independent_build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
source = build.generate(dof_candidate=True, native_candidate=True, combined_scene_candidate=True)
assert 'local function render_photo()' in source
begin = source.index('local Motion=(function()\n') + len('local Motion=(function()\n')
end = source.index('\nend)()\nscene=Scene.new', begin)
render = source[begin:end]
assert render == (ROOT/'freecam/camera_motion.lua').read_text(), 'Generated motion differs from owned source'
from freecam.build import compile_lua
compile_lua(source.encode(), 'cinema-complete-owned-runtime')

fixture = r'''
local factory=dofile(PHOTO_ROOT..'cinema_camera.lua')
local look=dofile(PHOTO_ROOT..'look.lua');local lens_factory=dofile(PHOTO_ROOT..'lens.lua')
local PHOTO={active=true,pos={2,3,4},view={yaw=math.pi/2,pitch=.2},options={fov=60,roll=17},sample_sequence=7}
local player_point={3000,800,100};local camera_position={};local camera_rotation;local fov=.7;local updates=0;local effects=0
local sr={Vector3=function(...)return {...}end,Quaternion={look=function(f,u)return{f=f,u=u}end},
 Unit={alive=function()return true end,world_position=function()return player_point end},
 Camera={vertical_fov=function()return fov end,set_vertical_fov=function(_,v)fov=v end,
  set_local_rotation=function(_,_,value)camera_rotation=value end,
  set_local_position=function(_,_,value)camera_position=value end},
 World={update_unit=function()updates=updates+1 end}}
local function log()end;local CFG={PHOTO_SPEED=10,PHOTO_MAX_RANGE=60}
local cinema=factory.new(PHOTO,function()return{world='mission',epoch=1,player='player'}end)
local camera_lens=lens_factory.new(sr)
local DBF_PLAYER_FREEZE={hold=function()return true end};local native_open=false
local DBF_PHOTO_RUNTIME={apply=function(cam,unit,world,forward,right,options,dt)
 assert(dt==0,'Gameplay input delta reached static camera movement');effects=effects+1
 camera_lens.apply(cam,unit,forward,right,options)
end}
'''
fixture += '\nlocal Motion=(function()\n'+render+'\nend)()\n'
fixture += r'''
local scene={valid=function()return true end,owned=function()return true end}
CFG.scene=scene
local motion=Motion.new(sr,PHOTO,look,DBF_PHOTO_RUNTIME,DBF_PLAYER_FREEZE,cinema,CFG,log)
assert(cinema.place()and cinema.prepare(math.rad(60))and cinema.commit())
for frame=1,100 do
 native_open=frame%2==0
 player_point={3000+frame*10,-500-frame,100};camera_position={unpack(player_point)};fov=.6
 PHOTO.input={sequence=frame,forward=true,right=true,up=true,mouse_x=1000,mouse_y=500,dt=.1}
 local frame={world='mission',unit='camera-unit',cam='camera',player='player',player_identity='local-player',epoch=1,position={unpack(camera_position)},
  forward={1,0,0},right={0,-1,0},player_position=player_point}
 assert(motion.apply(frame,native_open))
 assert(camera_position[1]==2 and camera_position[2]==3 and camera_position[3]==4,'Static camera followed the distant avatar or sampled movement')
 assert(math.abs(fov-math.rad(60))<1e-8,'Game camera FOV overwrote the shot lens')
 assert(math.abs(camera_rotation.f[1])<1e-8 and math.abs(camera_rotation.f[2]-math.cos(.2))<1e-8,'Game camera rotation overwrote the shot orientation')
end
assert(updates==100 and effects==100,'Static camera failed to render continuously')
assert(cinema.reposition()and cinema.state=='place');cinema.stop()
print('Generated Cinema render: actual packaged owned Motion.apply with alternating native-menu input suspension holds position, orientation and FOV over 100 game/input updates; moving avatar does not activate the placement range clamp')
'''
bootstrap = ('PHOTO_ROOT='+repr((ROOT/'freecam').as_posix()+'/')+'\n').encode()
run_lua.run(bootstrap+fixture.encode(), 'cinema-generated-render')

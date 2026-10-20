"""Exercise the removable proof probe without accessing the game process."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import run_lua
source = (ROOT/'dist/dof-investigation-20261011/photo_dof_registration_probe.lua').read_text()
body = source[source.index("local sr=assert(rawget(_G,'stingray'))"):]
fixture = r'''
local command='green first';local captures,created,destroyed,tiles=0,0,0,0
local supported=true;local output
local capture_factory={new=function()return {capture=function(path)
 captures=captures+1;return true,{path=path}
end}end}
io.open=function(path,mode)
 if mode=='rb' then return {read=function()return command end,close=function()end}end
 return {write=function(_,text)output=text end,close=function()end}
end
stingray={Application={can_get=function()return supported end,main_world=function()return 1 end,worlds=function()return {1,2}end},
World={create_screen_gui=function(world)assert(world==2);created=created+1;return created end,
destroy_gui=function(world)assert(world==2);destroyed=destroyed+1 end},
Gui={material=function()return 3 end,bitmap=function(_,material,position,size,color)
 assert(material=='mods/dbf_photo/materials/scene_color'and position[3]==800 and size[1]==256 and color[1]==255)
 tiles=tiles+1;return 7
end},Material={set_scalar=function()end,set_vector4=function()end},
Vector3=function(...)return {...}end,Vector2=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end}
local probe=(function()
__BODY__
end)()
local ctx={log=function()end};probe.on_enable()
for _=1,9 do probe.on_update(ctx)end
assert(created==1 and tiles==1 and captures==0,'Wait for rendered frames before capture')
probe.on_update(ctx);assert(captures==1)
for _=1,20 do probe.on_update(ctx)end
assert(captures==1 and created==1,'Unchanged commands must not redraw or recapture')
command='capture second';probe.on_update(ctx);assert(destroyed==1,'Capture baseline removes proof tile')
for _=1,9 do probe.on_update(ctx)end;assert(captures==2)
command='green third';probe.on_update(ctx);assert(created==2)
assert(probe.on_disable()and destroyed==2,'Disable restores the unmodified view')
supported=false;command='green unavailable';assert(not pcall(probe.on_update,ctx))
assert(created==2,'Unavailable shaders must not create a GUI')
print('DoF proof probe: UI world, bounded tile, delayed capture, duplicate suppression, baseline/disable cleanup and absent-shader refusal passed; no game process accessed')
'''.replace('__BODY__', body)
run_lua.run(fixture.encode(), 'dof-probe-fixture')

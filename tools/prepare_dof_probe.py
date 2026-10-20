"""Build an isolated, removable shader execution probe; never edits camera state."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'freecam'))
from build import compile_lua
OUT = ROOT/'dist/dof-investigation-20261011'
source = "local capture_factory=(function()\n"+(ROOT/'freecam/screenshot_backend.lua').read_text()+"\nend)()\n"+r'''
local sr=assert(rawget(_G,'stingray'))
local gui,world,backend,last,pending,frames
local root='C:/Users/david/OneDrive/Documents/GitHub/DBF_PhotoMode/dist/dof-investigation-20261011/'
local function clear()
 if gui then sr.World.destroy_gui(world,gui)end
 gui,world=nil,nil
end
local function status(text)
 local f=assert(io.open(root..'PROBE-STATUS.txt','wb'));f:write(text);f:close()
end
return {name='Photo DoF shader execution probe',on_enable=function()status('Waiting for probe command')end,
on_update=function(ctx)
 local f=io.open(root..'PROBE-COMMAND.txt','rb');local command=f and f:read('*a');if f then f:close()end
 if command and command~=last then
  last=command;clear();pending=nil
  local mode,name=command:match('^(%w+)%s+([%w_]+)')
  -- Numeric/depth materials require an offline ABI review after the DoF crash.
  if mode=='dof' or mode=='depth'then status('DoF/depth probe disabled pending ABI review');return end
  if mode=='green' then
   local material='mods/dbf_photo/materials/scene_color'
   assert(sr.Application.can_get('material',material),'Registered proof material unavailable')
   local main=sr.Application.main_world()
   for _,candidate in pairs(sr.Application.worlds())do if candidate~=main then world=candidate;break end end
   assert(world,'Photo UI world unavailable');gui=assert(sr.World.create_screen_gui(world,'scale',1,1))
   local handle=assert(sr.Gui.material(gui,material))
   sr.Material.set_scalar(handle,'scissor_mode',0);sr.Material.set_scalar(handle,'threshold_fade',0)
   sr.Material.set_vector4(handle,'clip_box',sr.Vector4(0,0,1,0))
   sr.Material.set_vector4(handle,'scissor_rect',sr.Vector4(1,1.2,.61,32))
   sr.Material.set_vector4(handle,'atlas_scissor',sr.Vector4(1,mode=='depth'and 1 or 0,0,0))
   assert(sr.Gui.bitmap(gui,material,sr.Vector3(30,30,800),sr.Vector2(256,256),sr.Color(255,255,255,255)))
   status('Proof tile submitted; visible execution remains unverified')
  end
  if mode=='green'or mode=='dof'or mode=='depth'or mode=='capture'then pending=name;frames=0 end
 end
 if pending then
  frames=frames+1
  if frames>=10 then
   backend=backend or assert(capture_factory.new(sr));local ok,result=backend.capture(root..pending..'.dds')
   pending=nil
   if ok then status('Game capture saved: '..result.path);ctx.log('DoF proof game capture saved')
   else status('Game capture refused: '..tostring(result));ctx.log('DoF proof capture refused: '..tostring(result))end
  end
 end
end,on_disable=function()clear();status('Probe removed');return true end}
'''
compile_lua(source.encode(), 'photo-dof-registration-probe')
target = OUT/'photo_dof_registration_probe.lua'
target.write_text(source, encoding='utf-8')
print(target)

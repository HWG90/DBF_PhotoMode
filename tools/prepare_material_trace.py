"""Prepare a one-shot availability check, without material creation or drawing."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'freecam'))
from build import compile_lua
source=r'''
local done=false
return {name='Photo material availability trace',on_enable=function()end,on_update=function(ctx)
 if done then return end
 local sr=assert(rawget(_G,'stingray'));local rows={};local util=require('jit.util')
 for _,item in ipairs({{'shader_library','mods/dbf_photo/shaders/dof_local_depth_v1'},
 {'material','mods/dbf_photo/materials/dof_local_depth_v1'}, {'material','mods/dbf_photo/materials/scene_color'}})do
  local ok,result=pcall(sr.Application.can_get,item[1],item[2])
  rows[#rows+1]=item[1]..' '..item[2]..' '..tostring(ok)..' '..tostring(result)
 end
 rows[#rows+1]='can_get_address '..tostring(util.funcinfo(sr.Application.can_get).addr)
 rows[#rows+1]='gui_material_address '..tostring(util.funcinfo(sr.Gui.material).addr)
 local f=assert(io.open('C:/Users/david/OneDrive/Documents/GitHub/DBF_PhotoMode/dist/dof-investigation-20261011/MATERIAL-AVAILABILITY-API.txt','wb'))
 f:write(table.concat(rows,'\n'));f:close();done=true;ctx.log('Material availability API trace saved; no material created or drawn')
end,on_disable=function()return true end}
'''
compile_lua(source.encode(),'photo-material-availability-trace')
out=ROOT/'dist/dof-investigation-20261011/photo_material_trace.lua';out.write_text(source);print(out)

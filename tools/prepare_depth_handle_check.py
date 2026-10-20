"""One-shot guarded existing-depth lookup. No materials or geometry."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'freecam'))
from build import compile_lua
source='local depth_factory=(function()\n'+(ROOT/'freecam/depth_resource.lua').read_text()+'\nend)()\n'+r'''
local done=false
return {name='Photo depth handle check',on_enable=function()end,on_update=function(ctx)
 if done then return end;done=true
 local sr=assert(rawget(_G,'stingray'));local rows={}
 rows[#rows+1]='shader_available '..tostring(sr.Application.can_get('shader_library','mods/dbf_photo/shaders/dof_local_depth_v1'))
 rows[#rows+1]='material_available '..tostring(sr.Application.can_get('material','mods/dbf_photo/materials/dof_local_depth_v1'))
 local ok,depth=pcall(depth_factory.new,sr)
 if ok then local resource,reason=depth.get();rows[#rows+1]='depth_handle '..tostring(resource);rows[#rows+1]='depth_reason '..tostring(reason)
 else rows[#rows+1]='depth_setup_error '..tostring(depth)end
 local f=assert(io.open('C:/Users/david/OneDrive/Documents/GitHub/DBF_PhotoMode/dist/dof-investigation-20261011/DEPTH-HANDLE-CHECK.txt','wb'))
 f:write(table.concat(rows,'\n'));f:close();ctx.log('Existing depth handle check complete; no geometry or material created')
end,on_disable=function()return true end}
'''
compile_lua(source.encode(),'photo-depth-handle-check')
out=ROOT/'dist/dof-investigation-20261011/photo_depth_handle_check.lua';out.write_text(source);print(out)

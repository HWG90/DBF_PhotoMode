"""Prepare a one-shot read-only Lua API inventory; no renderer calls."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'freecam'))
from build import compile_lua
source=r'''
local done=false
return {name='Photo resource API inventory (read-only)',on_enable=function()end,on_update=function(ctx)
 if done then return end
 local sr=rawget(_G,'stingray');if not sr then return end
 local util=require('jit.util');local entries={}
 for name,object in pairs(sr)do if type(object)=='table'then
  for key,value in pairs(object)do
   local label=tostring(key):lower()
   if type(value)=='function'and(name=='ResourcePackage'or name=='Renderer'or label:find('resource')or label:find('package'))then
    local info=util.funcinfo(value);entries[#entries+1]=name..'.'..tostring(key)..'\t'..tostring(info.addr or '')
   end
  end
 end end
 table.sort(entries)
 local f=assert(io.open('dist/dof-investigation/RESOURCE-API-INVENTORY.txt','wb'))
 f:write(table.concat(entries,'\n'));f:close();done=true;ctx.log('Read-only resource API inventory saved; no native functions called')
end,on_disable=function()return true end}
'''
compile_lua(source.encode(),'photo-resource-inventory')
target=ROOT/'dist/dof-investigation-20261011/photo_resource_api_inventory.lua'
target.write_text(source)
print(target)

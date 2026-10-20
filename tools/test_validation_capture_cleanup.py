"""Run the actual generated capture block through failure and restoration cases."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import run_lua
source=(ROOT/'dist/dof-investigation-20261011/photo_dof_validation.lua').read_text()
start=source.index('    backend=backend or assert(capture_factory.new(sr))',source.index('  if pending then'))
end=source.index('   end\n  end\n  return result',start)
capture=source[start:end]
fixture=r'''
local real_open=io.open
for _,case in ipairs({'existing_output','native_failure','success'})do
 local mode,pending,root='colorcheck','capture','review/'
 local native_trial=false;local released,restored=0,0;local message;local seen={}
 local overlay={release=function()released=released+1;return true end}
 local function restore_custom()restored=restored+1 end
 local function status(value)message=value end
 local backend={ready=function()return true end,capture=function()return true end}
 local sr={Application={save_render_target=function()if case=='native_failure'then error('native save refused')end end}}
 io.open=function(path)if case=='existing_output'and path:find('_hdr0',1,true)then return {close=function()end}end end
 local options={dof=true};local function frame()
  local render_options=options
  if mode=='colorcheck'then render_options={dof=false}end
  seen[#seen+1]=render_options.dof
  if pending then
'''+capture+r'''
  end
 end
 frame();assert(mode=='off'and pending==nil and released==1 and restored==1)
 frame();assert(seen[1]==false and seen[2]==true and options.dof==true,'Capture failure retained DoF override')
 assert(message:find(case=='success'and'Game capture saved'or'Game capture refused',1,true))
end
io.open=real_open
print('Validation capture: collision/native failure/success all restore normal DoF on the next frame')
'''
run_lua.run(fixture.encode(),'validation-capture-cleanup')
assert "consumed:write('off')"in source and "f:write('off');f:close();last='off'"in source

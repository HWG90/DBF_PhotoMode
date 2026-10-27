DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local calls,picks=0,0;local ready_at=2;local no_surface=false
local f=fixture(false,function(f,deps,sr)
 deps.engine_shader_lens=true
 deps.selection_probe=true
 deps.operation_clock=function()return f.time end
 deps.pick={new=function()return{pick=function(camera,x,y,w,h,radius,depth)
  picks=picks+1;assert(depth==.708,'Use visible depth, not stale root distance')
  return{label='Fixture',distance=depth,helldiver=false}
 end}end}
 deps.load_scene=function()return{
  ready=function()return true end,rearm=function()end,release=function()return true end,
  render=function()return true,'fixture',false end,focus=function()end,
  pick_depth=function(x,y,w,h)
   calls=calls+1;assert(w==1920 and h==1080)
   if no_surface then return nil,'No focusable surface at this point'end
   if f.time<ready_at then return nil,'display settling',{pending=true,retry_at=ready_at}end
   return .708
  end}end
end)
f.open();if f.runtime.mode~='menu'then f.runtime.focus()end
assert(f.runtime.handle.set('dof_mode',2),'Selection-to-focus fixture explicitly uses its shader lens')
f.step(.016,1)
f.menu.contains_pointer=function(x)return x<200 end
f.pointer.x=960;f.pointer.y=540;f.step(.02)
local function click()f.pointer.buttons=1;f.step(.03);f.pointer.buttons=0;f.step(.03)end
local function double()click();click()end
double();assert(calls==1 and picks==0)
for i=1,20 do f.step(.02)end
assert(calls==1,'Pending depth must remain idle before the explicit retry time')
f.step(2);assert(calls==2 and picks==1 and f.runtime.handle.get('focus_distance')==.708)
for i=1,30 do f.step(.02)end;assert(calls==2 and picks==1,'No idle depth sampling or unit enumeration')
ready_at=f.time+2;double();assert(calls==3 and picks==1)
assert(f.runtime.handle.set('fov',75));f.step(.02);f.step(2)
assert(calls==3 and picks==1,'Changing the view cancels pending selection before reading units')
no_surface=true;double();assert(calls==4 and picks==1,'Missing depth must not select a projected character')
f.pointer.x=100;double();assert(calls==4 and picks==1,'Menu double-click must not sample depth')
-- A queued depth retry belongs to an exact world, even with identical labels.
local function world()local w=newproxy(true);getmetatable(w).__tostring=function()return'[World]'end;return w end
no_surface=false;f.world=world();ready_at=f.time+2;f.pointer.x=960
double();local before_calls,before_picks=calls,picks;f.world=world();f.step(.03);f.step(2)
assert(calls==before_calls and picks==before_picks,'A queued selection cannot cross identical-string world handles')
ready_at=f.time+1
local result,why,info=f.runtime.selection_probe(.5,.5)
assert(not result and info.pending,'Diagnostic uses the production pending depth contract')
f.step(1.1);result=assert(f.runtime.selection_probe(.5,.5))
assert(result.selected and result.depth==.708 and result.pick_ms>=0 and result.sample_ms>=0,'Diagnostic resolves through production selection')
assert(not pcall(f.runtime.selection_probe,0/0,.5),'Invalid diagnostic coordinates refuse')
f.finish()
local ordinary=fixture(false);assert(ordinary.runtime.selection_probe==nil,'Ordinary runtime must not expose development probe');ordinary.finish()
print('Depth picking integration: fresh surface, bounded delayed retry, idle work, view-change cancellation, invalid surface and menu exclusion passed')

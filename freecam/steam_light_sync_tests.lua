DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
for _,with_subject in ipairs({false,true})do
 local state={revision=0,count=0,selected=1,pending=nil}
 local f=fixture(nil,function(f,deps)
  deps.subject_backend=with_subject and {new=function()return{}end}or nil
  deps.subject_visibility=with_subject and {new=function()return{refresh=function()return true,'fixture',{}end,queue=function()return true end,flush=function()return true end,release=function()return true end}end}or nil
  deps.lighting={new=function()return{status='fixture lights',open=function()return true end,close=function()return true end,
   revision=function()return state.revision end,
   selected=function()return state.count>0 and state.values or nil,state.selected,state.count end,
   markers=function()return nil end,
   action=function(action)state.pending=action;return true end,
   tick=function()
    if state.pending=='create'then
     state.count=state.count+1;state.selected=state.count
     state.values={enabled=true,intensity=3,color='#FFFFFF',cone=45,right=0,forward=1,up=0,follow_camera=false,follow_player=false,kind='omni'}
    elseif state.pending=='delete'then state.count=0;state.values=nil end
    if state.pending then state.revision=state.revision+1;state.pending=nil end
    return true
   end,
   change=function(id,v)
    if id=='light_intensity'then state.values.intensity=v end
    if id=='light_selected'then state.selected=v end
    state.revision=state.revision+1;return true
   end}
  end}
 end)
 f.open();assert(f.controls.light_follow_player.disabled==not with_subject)
 for i=1,3 do
  assert(f.controls.light_add.on_activate());f.step(.016)
  assert(f.runtime.active and f.camera_open,'Adding a light must keep Photo Mode running')
  assert(f.runtime.handle.get('light_selected')==i)
 end
 assert(f.runtime.handle.get('light_intensity')==3)
 assert(f.runtime.handle.set('light_intensity',5));f.step(.016)
 assert(f.runtime.handle.get('light_intensity')==5)
 local revision=state.revision;local saves=f.saves
 for i=1,30 do f.step(.016)end
 assert(state.revision==revision and f.saves==saves,'Unchanged light selection must stay idle')
 assert(f.runtime.close(true));f.finish()
end
print('BML lights: creation/selection/edit/idle/close with unavailable or available subject support passed using strict real settings API')

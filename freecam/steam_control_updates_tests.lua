DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local ids={'hide_player','hide_armour','hide_weapons','hide_cape'}
local f=fixture(nil,function(f,deps)
 deps.path=dofile('freecam/steam_path.lua')
 deps.subject_backend={new=function()return{}end}
 local caps={hide_player=true,hide_armour=true,hide_weapons=true,hide_cape=true}
 deps.subject_visibility={new=function()return{
  refresh=function()return true,'fixture visibility',caps end,
  queue=function(o)f.queued={};for k,v in pairs(o)do f.queued[k]=v end;return true end,
  flush=function()f.applied=f.queued;return true end,release=function()return true end}
 end}
 local selected,count,revision,pending=0,0,0,false
 deps.lighting={new=function()return{status='fixture lights',open=function()return true end,close=function()return true end,
  revision=function()return revision end,selected=function()return count>0 and{enabled=true,intensity=3,color='#FFFFFF',cone=45,right=0,forward=1,up=0,follow_camera=false,kind='omni'}or nil,selected,count end,
  markers=function()return nil end,action=function(a)assert(a=='create');pending=true;return true end,
  tick=function()if pending then count=count+1;selected=count;revision=revision+1;pending=false end;return true end,
  change=function(id,v)if id=='light_selected'then selected=v;revision=revision+1 end;return true end}
 end}
end)
f.open()
for _,id in ipairs(ids)do
 assert(not f.controls[id].disabled,'Registered visibility controls must reflect live capabilities')
 assert(f.runtime.handle.set(id,true));assert(f.queued[id]==true,'On must queue On on the first click')
 f.step(.016);assert(f.applied[id]==true)
 assert(f.runtime.handle.set(id,false));assert(f.queued[id]==false,'Off must queue Off on the first click')
 f.step(.016);assert(f.applied[id]==false)
end
for n=1,3 do
 assert(f.controls.light_add.on_activate());f.step(.016)
 assert(f.runtime.handle.get('light_selected')==n,'Adding a light must select the new light')
end
for n=1,3 do
 assert(f.controls.path_add.on_activate());assert(#f.controls.path_point.choices==n)
 assert(f.runtime.handle.get('path_point')==n,'Adding a point must advance the actual dropdown selection')
end
assert(f.runtime.handle.set('path_point',1));assert(f.runtime.handle.get('path_point')==1)
assert(f.runtime.close(true));f.finish()
print('Steam registered controls: immediate visibility On/Off, live capabilities, new-light and new-point selection passed')

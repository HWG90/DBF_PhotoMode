DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local D=dofile('freecam/director.lua')
local f=fixture(nil,function(f,deps)
 f.player={local_owner=true,identity='player',position={10,20,3},yaw=0}
 f.player_reads=0;deps.player_frame=function()f.player_reads=f.player_reads+1;return f.player end
 local rows={}
 deps.director={new=function(photo,context,path,log)
  return D.new(photo,context,path,log,{load=function()return rows end,save=function(v)
   if f.refuse_save then return false,'fixture save refused'end;rows=v;return true end})
 end}
 local factory=deps.camera.new
 deps.camera={new=function(...)
  local c=factory(...);local write=c.write_view
  c.write_view=function(pos,forward,...)f.position={unpack(pos)};f.forward={unpack(forward)};return write(pos,forward,...)end
  return c
 end}
end)
local function action(name)return f.controls[name].on_activate()end
assert(f.player_reads==0,'Closed Director must not read player state')
f.open();assert(not f.controls.director_save.disabled)
assert(action('director_save'));assert(f.controls.director_slot.choices[1]:find('saved'))
f.player.position={20,30,4}
assert(action('director_recall'));render()
assert(f.position[1]==10 and f.position[2]==10 and f.position[3]==1,'Relative shot must follow player displacement')
local reads=f.player_reads;for i=1,100 do f.step(.016)end
assert(f.player_reads==reads,'Director must not poll player state')
f.refuse_save=true;assert(action('director_clear')==false)
assert(f.controls.director_slot.choices[1]:find('saved'),'Failed save must preserve stored shot')
f.refuse_save=false;assert(action('director_clear'));assert(action('director_recall')==false)
assert(f.runtime.close(true));f.finish()
print('Steam Director integration: original persistent model, relative recall, bounded actions and failed-save retention passed')

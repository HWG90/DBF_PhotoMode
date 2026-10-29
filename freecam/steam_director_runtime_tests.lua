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
-- Closing remembers the camera relative to the player (the selected Helldiver under Boot
-- Mod Loader); reopening returns there. On by default; off starts at the gameplay camera.
do
 local g=fixture(nil,function(g,deps)
  g.player={local_owner=true,identity='player',position={10,20,3},yaw=0}
  deps.player_frame=function()return g.player end
  deps.director={new=function(photo,context,path,log)
   return D.new(photo,context,path,log,{load=function()return{}end,save=function()return true end})
  end}
  local factory=deps.camera.new
  deps.camera={new=function(...)
   local c=factory(...);local write=c.write_view
   c.write_view=function(pos,...)g.position={unpack(pos)};return write(pos,...)end
   return c
  end}
 end)
 local function close()assert(g.runtime.close(true));for _=1,8 do if g.runtime.state=='closed'then break end;g.step(.2)end;assert(g.runtime.state=='closed')end
 assert(g.runtime.handle.get('return_to_last_camera')==true,'Returning to the last camera is the default')
 g.open();render();local start={unpack(g.position)}
 close();g.player.position={15,26,4}
 g.open();render()
 assert(math.abs(g.position[1]-(start[1]+5))<1e-9 and math.abs(g.position[2]-(start[2]+6))<1e-9 and math.abs(g.position[3]-(start[3]+1))<1e-9,
  'Reopening returns to the camera relative to the player')
 assert(g.runtime.handle.set('return_to_last_camera',false));close()
 g.player.position={30,40,5};g.open();render()
 assert(g.position[1]==start[1]and g.position[2]==start[2]and g.position[3]==start[3],'Off: reopening starts at the gameplay camera')
 close();g.finish()
 print('Return to last camera: remembered on close relative to the player, restored on open by default, off starts at the gameplay camera passed')
end

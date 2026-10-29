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
-- Bone-anchored shots (user: "if I position the camera on my face and turn around, it should
-- still be on my face"): the nearest of head/chest/hips within 1 m, else the body root, with
-- the bone's full position and orientation.
do
 local function near(a,b)for i=1,3 do if math.abs(a[i]-b[i])>1e-9 then return false end end;return true end
 local function wrap(a)return(a+math.pi)%(2*math.pi)-math.pi end
 local head={p={0,0,1.7},x={1,0,0},y={0,1,0},z={0,0,1}}
 local player={local_owner=true,identity='p',position={0,0,0},yaw=math.pi/2,
  bones={root={p={0,0,0},x={1,0,0},y={0,1,0},z={0,0,1}},head=head}}
 local rows,photo={},{active=true,options={fov=50,roll=0}}
 local d=D.new(photo,function()return player end,'unused',nil,{load=function()return rows end,save=function(v)rows=v;return true end})
 local handle={get=function()return 0 end,set_many=function()return true end}
 -- 0.4 m in front of the face (the face looks along +y), looking back at it.
 photo.pos={0,.4,1.7};photo.view={yaw=-math.pi/2,pitch=0}
 assert(d.save(1)and rows[1].bone==4,'A camera on the face anchors on the head')
 -- Turn around (180 degrees about up) and walk away.
 head.p={5,5,1.7};head.x={-1,0,0};head.y={0,-1,0}
 assert(d.recall(1,handle))
 assert(near(photo.pos,{5,4.6,1.7}),'Still in front of the face')
 assert(math.abs(wrap(photo.view.yaw-math.pi/2))<1e-9 and math.abs(photo.view.pitch)<1e-9,'Still looking at the face')
 -- A head tilted back carries the camera with it.
 head.p={0,0,1.7};head.x={1,0,0};head.y={0,0,1};head.z={0,-1,0}
 assert(d.recall(1,handle)and near(photo.pos,{0,0,2.1}),'Follows the head\'s tilt')
 -- A wide shot anchors on the body root.
 head.y={0,1,0};head.z={0,0,1}
 photo.pos={0,4,1};photo.view={yaw=-math.pi/2,pitch=0}
 assert(d.save(2)and rows[2].bone==1,'A wide shot anchors on the body')
 -- The bone survives the file; shots saved before it still load.
 local back=assert(D.decode(D.encode(rows)));assert(back[1].bone==4 and back[2].bone==1)
 local legacy=assert(D.decode('version=1\n1.right=1\n1.forward=2\n1.up=0\n1.yaw=0\n1.pitch=0\n1.roll=0\n1.fov=0\n'))
 assert(legacy[1].bone==nil,'Old shots keep the body-yaw model')
 assert(not D.decode('version=1\n1.right=1\n1.forward=2\n1.up=0\n1.yaw=0\n1.pitch=0\n1.roll=0\n1.fov=0\n1.bone=9\n'),'Unknown bones are refused')
 print('Bone-anchored shots: head for the face, root for wide shots, turn and tilt followed, file round trip and old shots passed')
end

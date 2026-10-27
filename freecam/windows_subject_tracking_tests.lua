local T=dofile('freecam/windows_subject_tracking.lua')
local value={explicit_subject=true,identity='chosen teammate',root_handle={},world={},position={1,2,3},head={1,2,4}}
local t=T.new(function()return value end)
assert(t.head_frame()==value);value=nil;assert(not pcall(t.head_frame))
do
 local unit,world={},{};local reads,lines=0,{}
 local frame={explicit_subject=true,identity='mesh subject',root_handle=unit,world=world,position={0,0,0},head={0,0,1}}
 local sr={Unit={alive=function(u)return u==unit end,world=function()return world end,
  num_meshes=function()reads=reads+1;return 2 end,mesh=function(_,i)return i end},
  Mesh={name=function(i)return i==1 and'helmet'or'body' end,node=function()return 1 end,visibility=function()return true end,num_materials=function()return 1 end}}
 local probe=T.new(function()return frame end,sr,function(s)lines[#lines+1]=s end)
 for _=1,120 do probe.head_frame()end
 assert(reads==1 and #lines==3,'Selected mesh inventory must run once, never every frame')
 sr.Unit.num_meshes=function()return 65 end
 assert(not pcall(T.inspect,frame,sr,function()error('Over-budget inventory logged rows')end))
end
do
 local inventory=dofile('freecam/windows_api_inventory.lua');local logs={}
 local forbidden=function()error('Unknown HUD function was invoked')end
 local globals={GameHUD={hide=forbidden},hide_hud=forbidden};globals.cycle=globals
 local tables,keys,hits=inventory.hud_environment(globals,function(s)logs[#logs+1]=s end)
 assert(tables<=64 and keys<=4097 and hits==3 and #logs>0,'HUD environment probe must be bounded and metadata-only')
end

-- The private outfit probe is bounded, read-only and stops after one inventory.
do
 local root={name='root',x=0};local matching={name='outfit',x=0};local foreign={name='other player',x=20}
 local world={};local reads,snapshots,lines=0,0,{}
 local frame={root_handle=root,world=world,identity='selected',explicit_subject=true}
 local units={root,matching,foreign};for i=1,60 do units[#units+1]={name='prop',x=i+100}end
 local sr={Application={main_world=function()return world end},World={units=function()snapshots=snapshots+1;return units end},
  Unit={alive=function(u)return not u.dead end,world=function()return world end,
   has_node=function(_,name)reads=reads+1;return name=='head'or name=='chest'end,node=function(_,name)return name=='head'and 1 or 2 end,
   world_pose=function(u,node)return{1,0,0,0,1,0,0,0,1,u.x,0,node}end,
   num_meshes=function()reads=reads+1;return 1 end,resource_name=function(u)return u.name end,mesh=function(u)return u end},
  Matrix4x4={to_elements=function(v)return unpack(v)end},Mesh={node=function()return 3 end,visibility=function()return true end}}
 local t=0;local probe=T.inventory(sr,function(s)lines[#lines+1]=s end,function()t=t+.000001;return t end)
 assert(probe.request(frame));probe.tick(frame);assert(snapshots==1 and reads==9,'Snapshot is separate from scanning')
 for _=1,5 do probe.tick(frame)end
 assert(probe.result.reason=='complete'and probe.result.candidates==1 and probe.result.visited==#units)
 assert(lines[1]:find('resource=outfit',1,true)and not table.concat(lines):find('resource=other player',1,true))
 local before=reads;for _=1,120 do probe.tick(frame)end;assert(reads==before and snapshots==1 and not probe.request(frame),'Finished discovery is idle')
 local changed=T.inventory(sr,function()end);changed.request(frame);changed.tick(frame);changed.tick(nil)
 assert(changed.result.reason:find('Selected subject changed',1,true))
 local slowclock=0;local slow=T.inventory(sr,function()end,function()slowclock=slowclock+.02;return slowclock end)
 slow.request(frame);slow.tick(frame);assert(slow.result.reason=='stopped at read budget')
 local retired=T.inventory(sr,function()end);retired.request(frame);root.dead=true;retired.tick(frame)
 assert(retired.result.reason:find('Selected subject retired',1,true));root.dead=false
 local over=T.inventory(sr,function()end);local old=sr.World.units;sr.World.units=function()local a={};for i=1,16385 do a[i]=root end;return a end
 over.request(frame);over.tick(frame);assert(over.result.reason:find('inventory exceeds bound',1,true));sr.World.units=old
 local selected_reads=0;local backend=T.new(function()selected_reads=selected_reads+1;return frame end,sr,function()end,true)
 for _=1,120 do backend.tick()end;assert(selected_reads==0,'No selection polling before an explicit discovery event')
 backend.request_inventory();for _=1,8 do backend.tick()end
 before=selected_reads;for _=1,120 do backend.tick();backend.request_inventory()end
 assert(selected_reads==before,'Completed probe must not reread selection')
 local scans=snapshots
 for _=1,6 do backend.request_inventory(true);for i=1,8 do backend.tick()end end
 assert(snapshots==scans+3,'Explicit visibility actions may rearm only three further scans, four total')
 before=selected_reads;for _=1,120 do backend.request_inventory(true);backend.tick()end
 assert(selected_reads==before,'Exhausted explicit discovery budget stays idle')
end

-- Attachment evidence is exact-matrix, bounded, and never changes visibility.
do
 local owner,weapon,prop={},{},{};local reads=0
 local function matrix(x,rot)return{rot or 1,0,0,0,1,0,0,0,1,x,0,0}end
 local sr={Unit={num_scene_graph_items=function()return 12 end,
  has_node=function(u,n)assert(u==owner);return n=='attach_weapon'end,
  node=function()return 3 end,
  world_pose=function(u,n)
   reads=reads+1
   if u==owner then return matrix(n==3 and 1 or 0)end
   if u==prop then return matrix(20)end
   return matrix(n==2 and 1 or 2)
  end},Matrix4x4={to_elements=function(v)return unpack(v)end}}
 local result,next_node,spent,total=T.attachment_matches(sr,owner,weapon)
 assert(next_node==9 and spent==8 and total==12)
 assert(#result==1 and result[1]=='2:attach_weapon'and reads==10,'Match full anchor transform with eight-node bound')
 local later,done,n=T.attachment_matches(sr,owner,weapon,9,12);assert(#later==0 and done==nil and n==4)
 assert(not pcall(T.attachment_matches,sr,owner,weapon,9,13),'Changed graph cannot resume')
 reads=0;assert(#T.attachment_matches(sr,owner,prop)==0 and reads==2,'Distant props require no anchor scan')
 sr.Unit.world_pose=function(u,n)if u==owner then return matrix(n==3 and 1 or 0)end;return matrix(n==12 and 1 or 2)end
 local early,next_node=T.attachment_matches(sr,owner,weapon);assert(#early==0 and next_node==9)
 local late,done=T.attachment_matches(sr,owner,weapon,next_node,12);assert(#late==1 and late[1]=='12:attach_weapon'and not done)
 sr.Unit.world_pose=function(u,n)if u==owner then return matrix(n==3 and 1 or 0)end;return matrix(1,-1)end
 assert(#T.attachment_matches(sr,owner,weapon)==0,'Same position with different orientation is not a match')
 sr.Unit.num_scene_graph_items=function()return 1025 end
 assert(not pcall(T.attachment_matches,sr,owner,weapon),'Reject oversized graphs')
end

-- A nearby weapon's deeper nodes resume on a later callback, including when
-- it is the final world unit; completion never discards a pending chunk.
do
 local root,weapon,world={},{},{};local logs={};local time=0
 local sr={Application={main_world=function()return world end},World={units=function()return{root,weapon}end},
  Unit={alive=function(u)return not u.dead end,world=function()return world end,
   resource_name=function(u)return u==root and'body'or(weapon.resource or'weapon')end,
   num_meshes=function()return 1 end,num_scene_graph_items=function()return 12 end,
   has_node=function(u,n)return u==root and n=='attach_weapon'end,node=function()return 5 end,
   world_pose=function(u,n)local x=u==root and(n==5 and 1 or 0)or(n==12 and 1 or 2);return{1,0,0,0,1,0,0,0,1,x,0,0}end},
  Matrix4x4={to_elements=function(v)return unpack(v)end}}
 local frame={root_handle=root,world=world,identity='owner',explicit_subject=true}
 local function make()return T.inventory(sr,function(s)logs[#logs+1]=s end,function()time=time+.001;return time end)end
 local p=make();p.request(frame);p.tick(frame);p.tick(frame);p.tick(frame)
 assert(not p.result,'Final world unit still has a pending attachment chunk')
 p.tick(frame);assert(p.result.reason=='complete'and p.result.attachments==1 and p.result.attachment_nodes==12)
 assert(table.concat(logs):find('12:attach_weapon',1,true),'Late node match must be logged')
 local before=time;for _=1,120 do p.tick(frame)end;assert(time==before,'Finished deep scan stays idle')
 local changed=make();changed.request(frame);changed.tick(frame);changed.tick(frame);changed.tick(frame);weapon.resource='replacement';changed.tick(frame)
 assert(changed.result.reason:find('Attachment resource changed',1,true),'Do not resume a replacement attachment')
 weapon.resource=nil
end

-- Nested weapon accessories need their own root-to-weapon-node evidence.
-- Nearness alone is never emitted as an attachment, and discovery never writes.
do
 local function fixture()
  local world={};local root={resource='body'};local weapon={resource='weapon',x=1,nodes=12}
  local scope={resource='scope',x=2,nodes=2};local nearby={resource='nearby prop',x=2,rotation=-1,nodes=2}
  local distant={resource='distant prop',x=20,nodes=2};local lines={};local snapshots,reads=0,0;local time=0
  local sr={Application={main_world=function()return world end},World={units=function()snapshots=snapshots+1;return{root,scope,weapon,nearby,distant}end},
   Unit={alive=function(u)return not u.dead end,world=function()return world end,
    resource_name=function(u)return u.resource end,num_meshes=function()return 1 end,
    num_scene_graph_items=function(u)return u.nodes or 6 end,
    has_node=function(u,n)return u==root and n=='attach_weapon'end,node=function()return 5 end,
    world_pose=function(u,n)
     reads=reads+1
     local x=u==root and(n==5 and 1 or 0)or(u==weapon and n==12 and 2 or u.x)
     return{u.rotation or 1,0,0,0,1,0,0,0,1,x,0,0}
    end,
    set_mesh_visibility=function()error('Discovery wrote visibility')end},
   Matrix4x4={to_elements=function(v)return unpack(v)end}}
  local frame={root_handle=root,world=world,identity='owner',explicit_subject=true}
  local probe=T.inventory(sr,function(s)lines[#lines+1]=s end,function()time=time+.00001;return time end)
  probe.request(frame)
  local function first_pass()
   for _=1,100 do probe.tick(frame);if table.concat(lines):find('bounded second pass',1,true)then return end end
   error('Second pass never started')
  end
  local function finish()for _=1,100 do probe.tick(frame);if probe.result then return end end;error('Nested scan did not terminate')end
  return{probe=probe,frame=frame,root=root,sr=sr,weapon=weapon,scope=scope,logs=lines,first_pass=first_pass,finish=finish,stats=function()return snapshots,reads end}
 end
 local f=fixture();f.first_pass();f.finish()
 assert(f.probe.result.reason=='complete'and f.probe.result.nested==1 and f.probe.result.nested_nodes==24)
 local log=table.concat(f.logs,'\n')
 assert(log:find('resource=scope meshes=1 nodes=2 parent=weapon parent_nodes=12',1,true),'Find accessory root at a deeper weapon node')
 assert(not log:find('resource=nearby prop',1,true)and not log:find('resource=distant prop',1,true),'No ownership from proximity or translation alone')
 local snapshots,reads=f.stats();for _=1,120 do f.probe.tick(f.frame)end
 local after_snapshots,after_reads=f.stats();assert(snapshots==1 and after_snapshots==1 and after_reads==reads,'Finished nested scan stays idle with one world snapshot')
 f=fixture();f.first_pass();f.weapon.resource='reused';f.finish()
 assert(f.probe.result.reason:find('Nested attachment identity changed',1,true))
 f=fixture();f.first_pass();f.scope.dead=true;f.finish()
 assert(f.probe.result.reason:find('Nested attachment retired',1,true))
 f=fixture();f.first_pass();f.weapon.x=4;f.finish()
 assert(f.probe.result.reason=='complete'and f.probe.result.nested==0,'Dropped parent must be revalidated against the current body anchor')
 f=fixture();f.first_pass();f.probe.release();assert(f.probe.result.reason=='cancelled at Photo Mode close')
 for _,resource in ipairs({'968211c0033dce64','27ee1ed8f6fb6356'})do
  f=fixture();f.root.resource='4d1c334d294dfa97';f.root.nodes=107;f.weapon.resource=resource;f.weapon.x=.5
  local pose=f.sr.Unit.world_pose
  f.sr.Unit.world_pose=function(u,n)
   if u==f.root and n==80 then return{1,0,0,0,1,0,0,0,1,.5,0,0}end
   return pose(u,n)
  end
  f.first_pass();f.finish();assert(f.probe.result.reason=='complete')
  assert(table.concat(f.logs):find('resource='..resource..' meshes=1 nodes=12 parent=4d1c334d294dfa97 parent_nodes=80',1,true),'Known weapon variants can reveal a numeric holster anchor without broad prop-to-body scans')
 end
end

-- Exercise the actual native adapter with its established synthetic userdata fixture.
local f=assert(io.open('freecam/steam_subject_native_tests.lua','rb'));local source=f:read('*a');f:close()
source=source:sub(1,assert(source:find('-- NATIVE_FIXTURE_END',1,true))-1)
local make=assert(loadstring(source..'\nreturn fixture'))()
local n=make();local U,B,V=n.sr.Unit,n.sr.Matrix4x4,n.sr.Vector3
local camera=newproxy();local mismatch=false
local alive,world,node=U.alive,U.world,U.node
U.alive=function(u)if u==camera then return true end;return alive(u)end
U.world=function(u)if u==camera then return n.world end;return world(u)end
U.num_cameras=function(u)return u==camera and 1 or 0 end
U.node=function(u,name)if name=='head'then return 91 end;return node(u,name)end
U.world_pose=function(u,i)
 local index=u==camera and(mismatch and 8 or 7)or i
 return U.local_pose(n.unit,index)
end
U.world_position=function(u,i)return V(i,2,3)end
B.forward=function()return V(0,1,0)end
n.arm();n.discover()
assert(n.adapter.camera_target(camera,n.rig)==n.target)
mismatch=true;assert(n.adapter.camera_target(camera,n.rig)==nil)
assert(n.adapter.camera_target(camera,n.rig,{91,2,5})==n.target,'Unambiguous nearby head is a photographic tracking fallback')
assert(n.adapter.camera_target(camera,n.rig,{91,2,15})==nil,'Do not track a distant candidate automatically')
local Native=dofile('freecam/steam_subject_native.lua')
assert(Native.choose_tracking({{target='a',distance=2},{target='b',distance=2.2}})==nil,'Close ties require explicit selection')
assert(Native.choose_tracking({{target='b',distance=4},{target='a',distance=2}})=='a')
assert(Native.choose_tracking({})==nil)
local frame=assert(n.adapter.tracking_frame(n.target,n.rig));assert(frame.head[1]==91 and frame.root_handle==n.unit and frame.world==n.world and frame.explicit_subject)
assert(n.writes==0 and n.updates==0,'Tracking and automatic association are read-only')
n.alive=false;assert(n.adapter.tracking_frame(n.target,n.rig)==nil)

DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local h=fixture(false,function(h,deps)
 deps.handycam=dofile('freecam/steam_handycam.lua')
 deps.subject_backend={new=function()error('fixture: native unavailable')end}
 deps.subject_visibility={}
 h.reads=0;h.selected=true
 deps.mesh_visibility={};deps.pov_visibility={new=function()return{queue=function()end,flush=function()return true end,release=function()return true end,selection_changed=function()end}end}
 deps.subject_tracking={new=function()return{head_frame=function()
  h.reads=h.reads+1;assert(h.selected,'No selection')
  return{identity=h.changed and'new target'or'chosen target',head={1,2,3}}
 end}end}
end)
for _=1,40 do h.step(.016)end;assert(h.reads==0)
h.open();h.runtime.handle.set('action_camera_mode',2);assert(h.runtime.begin_shot())
assert(h.runtime.mode=='shot'and not h.lease,'Handycam releases control without requiring the failed native visibility reader')
h.step(.016,1);assert(h.reads>=2)
assert(h.runtime.reposition_shot());assert(h.runtime.mode=='menu'and h.lease)
assert(h.runtime.begin_shot());h.changed=true;h.step(.016,1);assert(not h.runtime.active and not h.lease)
h.finish()
print('Windows subject tracking: genuine selected handles, camera-anchor match, no visibility writes, idle behavior, shot handoff and target retirement passed')

-- A non-identity authored local root can hide an otherwise exact parent link.
-- Derive it read-only, but keep the result out of direct ownership matches.
do
 local function mul(a,b)
  local c={};for r=0,2 do for col=1,3 do c[r*3+col]=0;for k=1,3 do c[r*3+col]=c[r*3+col]+a[r*3+k]*b[(k-1)*3+col]end end end
  for col=1,3 do c[9+col]=b[9+col];for k=1,3 do c[9+col]=c[9+col]+a[9+k]*b[(k-1)*3+col]end end;return c
 end
 local function inv(a)
  local b={a[1],a[4],a[7],a[2],a[5],a[8],a[3],a[6],a[9],0,0,0}
  for col=1,3 do for k=1,3 do b[9+col]=b[9+col]-a[9+k]*b[(k-1)*3+col]end end;return b
 end
 local identity={1,0,0,0,1,0,0,0,1,0,0,0}
 local bind={1,0,0,0,0,1,0,-1,0,.2,.3,.5};local parent={0,1,0,-1,0,0,0,0,1,1,0,0}
 local owner,weapon={},{};local current=mul(bind,parent);local local_reads=0;local alive=true;local known=true;local scratch={}
 local function temporary(a)for i=1,12 do scratch[i]=a[i]end;return scratch end
 local sr={Unit={alive=function()return alive end,num_scene_graph_items=function(u)return u==owner and 107 or 2 end,
  local_pose=function(u,n)assert(u==weapon and n==1);local_reads=local_reads+1;return temporary(bind)end,
  world_pose=function(u,n)return temporary(u==weapon and current or n==1 and identity or parent)end,
  has_node=function(u,n)return u==owner and n=='sling'end,node=function()return 28 end,
  resource_name=function()return known and '0x27ee1ed8f6fb6356'or'unknown'end,
  set_local_pose=function()error('Read-only derivation wrote pose')end,set_mesh_visibility=function()error('Read-only derivation wrote visibility')end},
  Matrix4x4={from_elements=function(...)return{...}end,to_elements=function(a)return unpack(a)end,multiply=mul,inverse=inv}}
 local result=assert(T.root_parent_pose(sr,weapon));for i=1,12 do assert(math.abs(result[i]-parent[i])<1e-6,'Inverse-local multiplication order is wrong')end
 local_reads=0;local direct,_,_,_,derived=T.attachment_matches(sr,owner,weapon)
 assert(#direct==0 and #derived==1 and derived[1]=='sling'and local_reads==1,'Derived link is logged separately from direct links')
 T.attachment_matches(sr,owner,weapon,2);assert(local_reads==1,'Later node chunks do not repeat the extra root derivation')
 known=false;T.attachment_matches(sr,owner,weapon);assert(local_reads==1,'Unknown props never use root derivation')
 alive=false;local n=local_reads;assert(not T.root_parent_pose(sr,weapon)and local_reads==n,'Dead roots are never read')
 alive=true;bind={0,0,0,0,0,0,0,0,0,0,0,0};assert(not T.root_parent_pose(sr,weapon),'Singular local root refuses inversion')
end
print('Attachment parent evidence: rotated local bind, copied scratch values, read-only separation, known-resource/one-chunk bounds and singular/dead guards passed')

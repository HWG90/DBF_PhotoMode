-- Pose editor runtime contracts: actual runtime, controller and core; engine mutation stays a double.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
DBF_PHOTO_SUBJECT_FIXTURE_ONLY=true;local subject_fixture=dofile('freecam/steam_subject_runtime_tests.lua');DBF_PHOTO_SUBJECT_FIXTURE_ONLY=nil
local E=dofile('freecam/pose_editor.lua')
-- The pose editor is an injected dependency, as in steam51.
local function fixture(extra)return subject_fixture(function(f,deps,sr)deps.pose_editor=E;if extra then extra(f,deps,sr)end end)end
local function near(a,b)for i=1,4 do if math.abs(a[i]-b[i])>1e-9 then return false end end;return true end
local function elbow(f)assert(f.runtime.handle.set('bone_group',3));assert(f.runtime.handle.set('bone',3))end -- Right arm / Elbow = node 70
do -- first edit resets and settles, later edits apply directly, one write per update
 local f=fixture();f.enable();f.select();elbow(f)
 assert(f.controls.bone_bend.disabled==false,'Frozen, selected: sliders live')
 assert(f.runtime.handle.set('bone_bend',45))
 f.step(.016,1);assert(f.subject.status().state~='posed','First edit waits for the reset to settle')
 f.settle();local s=f.subject.status();assert(s.state=='posed'and s.pose=='edited',s.message)
 assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,45,0,0))and f.b.nodes[47].q[4]==1)
 local after_first=f.node_writes
 assert(f.runtime.handle.set('bone_bend',50));assert(f.runtime.handle.set('bone_bend',55));assert(f.runtime.handle.set('bone_twist',10))
 f.step(.016,1);assert(f.node_writes==after_first+1,'A burst of changes is one write per update')
 assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,55,0,10)))
 assert(f.runtime.handle.set('bone',4));assert(f.runtime.handle.get('bone_bend')==0 and f.runtime.handle.get('bone_twist')==0,'Sliders follow the selected bone')
 assert(f.runtime.handle.set('bone',3));assert(f.runtime.handle.get('bone_bend')==55,'...and show its angles again')
 local w=f.node_writes;f.step(.016,1);assert(f.node_writes==w,'Slider sync is not an edit')
 assert(f.controls.bone_status.label:find('Right arm / Elbow',1,true),f.controls.bone_status.label)
 assert(f.action('subject_pose_stop'));f.restored();assert(f.runtime.handle.get('bone_bend')==0,'Reset pose clears edits')
end
do -- catalogue pose while editing rebases and clears; unfreeze keeps the working pose
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 assert(f.runtime.handle.set('subject_pose',2));f.settle();assert(f.subject.status().pose==f.subject.catalog[2].id,'Catalogue pose applies over edits')
 assert(f.runtime.handle.get('bone_bend')==0,'Rebase clears angles')
 f.runtime.handle.set('bone_bend',20);f.step(.016,1);assert(f.subject.status().pose=='edited')
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1);f.step(.016,1);assert(f.subject.status().state~='posed')
 assert(f.runtime.handle.get('bone_bend')==20,'Working pose survives an unfreeze')
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end
 assert(f.action('bone_apply'));for _=1,3 do f.step(.016,1)end;assert(f.subject.status().pose=='edited','Apply edits brings it back')
 local base=dofile('freecam/assets/steam_subject_poses.lua').decode(f.subject.catalog[2].id).nodes[70].q
 assert(near(f.b.nodes[70].q,E.compose(base,20,0,0)),'Edits sit on the catalogue base')
 assert(f.action('subject_pose_stop'));f.restored()
end
do -- subject retires mid-edit
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 f.b.alive=false;f.runtime.handle.set('bone_bend',40);f.step(.016,1)
 assert(f.subject.status().state=='retired'and f.runtime.handle.get('bone_bend')==40,'Refused apply keeps the working pose')
end
do -- not frozen: rows disabled; Reset edits holds the plain base
 local f=fixture();f.enable();f.select();elbow(f)
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1);f.step(.016,1);assert(f.controls.bone_bend.disabled==true)
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end;assert(f.controls.bone_bend.disabled==false)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.action('bone_reset_all'));f.step(.016,1)
 assert(f.subject.status().pose=='edited'and near(f.b.nodes[70].q,f.original_b[70].q),'Reset edits holds the plain base')
 assert(f.action('subject_pose_stop'));f.restored()
end
do -- an explicit Refresh is a subject change: it clears the working pose
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1);f.step(.016,1);assert(f.runtime.handle.get('bone_bend')==30)
 assert(f.action('subject_refresh'));assert(f.runtime.handle.get('bone_bend')==0,'Refresh clears edits')
end
do -- save, load, overwrite, delete through an injected store; save needs true zero
 local F=dofile('freecam/pose_files.lua');local files={}
 local fs={open=function(p,m)if m=='rb'then local c=files[p];if c==nil then return nil end;return{read=function()return c end,close=function()end}end;local b={};return{write=function(_,s)b[#b+1]=s;return true end,close=function()files[p]=table.concat(b);return true end}end,
  rename=function(a,b)files[b]=files[a];files[a]=nil;return true end,remove=function(p)files[p]=nil;return true end}
 local f=fixture(function(f,deps)deps.pose_files={storage=function()return F.storage('C:/cfg',fs)end}end)
 f.enable();f.select();elbow(f)
 assert(f.runtime.handle.set('freeze_player',false)and f.rate==1);f.step(.016,1)
 assert(select(2,f.action('pose_save_new'))=='Freeze Action first','save needs true zero')
 assert(f.runtime.handle.set('freeze_player',true));for _=1,3 do f.step(.016,1)end
 assert(f.action('pose_save_new'));assert(files['C:/cfg/wj-pose-01.txt']and F.decode(files['C:/cfg/wj-pose-01.txt']).label=='Snapshot')
 assert(f.controls.pose_file.choices[1]=='01 — Snapshot',tostring(f.controls.pose_file.choices[1]))
 f.runtime.handle.set('bone_bend',30);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 assert(f.action('pose_save_new'));assert(F.decode(files['C:/cfg/wj-pose-02.txt']).label=='Snapshot edits')
 assert(f.action('subject_pose_stop'));f.restored()
 assert(f.runtime.handle.set('pose_file',2));assert(f.action('pose_load'));f.settle()
 assert(f.subject.status().pose=='edited'and near(f.b.nodes[70].q,E.compose(f.original_b[70].q,30,0,0)),'Loaded pose is applied')
 assert(f.runtime.handle.get('bone_bend')==0,'Loaded pose is the new base')
 assert(f.action('pose_overwrite')and F.decode(files['C:/cfg/wj-pose-02.txt']).label=='Snapshot edits')
 assert(f.action('pose_delete')and files['C:/cfg/wj-pose-02.txt']==nil and #f.controls.pose_file.choices==1)
 assert(f.action('subject_pose_stop'));f.restored()
end
do -- preview discarded on bone change
 local f=fixture();f.enable();f.select();elbow(f)
 f.runtime.handle.set('bone_bend',10);f.step(.016,1);f.settle();assert(f.subject.status().pose=='edited')
 assert(f.menu.actions.bone_adjust({bone_bend=40}));assert(f.runtime.handle.get('bone_bend')==40,'A preview reads back through the handle')
 assert(f.runtime.handle.set('bone',4))
 f.step(.016,1);assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,10,0,0)),'Preview never reached the old bone after the change')
 assert(f.runtime.handle.set('bone',3));assert(f.runtime.handle.get('bone_bend')==10)
 assert(f.menu.actions.bone_adjust({bone_bend=25}));f.step(.016,1);assert(near(f.b.nodes[70].q,E.compose(f.original_b[70].q,25,0,0)),'Previews apply live')
 assert(f.menu.actions.bone_adjust(nil,true));assert(f.runtime.handle.get('bone_bend')==25,'Release commits the slider once')
 assert(f.action('subject_pose_stop'));f.restored()
end
do -- marker: ring at the selected bone while shown; hidden by the toggle or a failed read
 -- The base fixture stubs the gizmo module; the marker needs its numeric projection.
 local f=fixture(function(f,deps)deps.pose_marker=dofile('freecam/pose_marker.lua');deps.gizmos=deps.gizmos or{new=function()return{update=function()end,cancel=function()end,draw=function()end,tick=function()return false end}end};deps.gizmos.project=dofile('freecam/photo_light_gizmos.lua').project end)
 f.enable();f.select();elbow(f)
 assert(f.menu.prepare_bone_marker and f.menu.bone_marker,'Runtime installs the marker on the menu')
 local seen;local update=f.menu.bone_marker.update
 f.menu.bone_marker.update=function(frame,...)seen=frame;return update(frame,...)end
 local ahead;f.subject.node_position=function(index)
  if not f.b.alive then return nil,'Selected subject retired'end
  if not ahead then return{0,0,0}end;return{ahead[1],ahead[2],ahead[3]+index/1000}
 end
 local function drawn()f.menu.prepare_bone_marker(1920,1080,true,false);local cmds={};f.menu.bone_marker.draw(cmds);local n=0;for _,c in ipairs(cmds)do if c.ui_role=='bone_marker'then n=n+1 end end;return n end
 drawn();assert(seen and seen.position and seen.forward,'The marker projects with the Photo Mode camera frame')
 ahead={};for i=1,3 do ahead[i]=seen.position[i]+seen.forward[i]*5 end
 assert(drawn()==1,'Marker drawn for the selected bone in front of the camera')
 assert(f.runtime.handle.set('bone_marker',false));assert(drawn()==0,'Toggle off hides it');assert(f.runtime.handle.set('bone_marker',true))
 assert(drawn()==1);f.b.alive=false;assert(drawn()==0,'A failed read hides it without an error')
end
print('Pose editor runtime: settle, coalesced apply, slider sync, rebase, unfreeze, retire and enabled rules passed')

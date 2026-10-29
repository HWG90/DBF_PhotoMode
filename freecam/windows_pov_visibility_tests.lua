local P=dofile('freecam/windows_pov_visibility.lua');local L=dofile('freecam/windows_mesh_visibility.lua')
local function fixture(full)
 local f={world={},reads=0,writes=0};local root={x=0};f.root=root
 local catalog={
  ['98ef4e039e963bdb']={-1507809972,1834168505,1254990207,281914907,-912447649},
  ['d2a2e2bc4fa5be21']={-1507809972,-2146726238,1969322454,1910610386,-333112902,531958952},
  ['544ed679357b6cb7']={-2146726238,1417423069,-486531110,1988273415,1447930109},
  ['ea846ef460cc5ba0']={-13682950,523982579,-308352159,-925021909}}
 if full then
  for _,item in ipairs({{'a5710e9464a26f48',5},{'6a589144bb3f838f',5},{'a70972419680b0b2',5},{'3bae7995707e30fb',5},{'619253c08af8dfdf',5},{'abf65fc9fc79fa96',5},{'c80b17cf0adc14a8',5},{'b0552d54fcd2a0d3',5},{'86b26185ad78f9e8',6},{'ad4f0063842dbb63',5},{'312c88caefdf6f9c',5},{'1ab1fdccc59f05da',5},{'e17025ba1d43acd3',6},{'968211c0033dce64',9},{'416d053372c4e433',9},{'a9936cbe561e8180',6},{'1c8764d62e12925a',10}})do
   local names={};for i=1,item[2]do names[i]=i end;catalog[item[1]]=names
  end
 end
 if full then
  for _,item in ipairs({{'e60ae045e0090f4c',21},{'a8cffb316f0b5c5f',9}})do
   local names={};for i=1,item[2]do names[i]=i end;catalog[item[1]]=names
  end
 end
 f.units={};f.by_resource={}
 for resource,names in pairs(catalog)do
  local u={x=0,resource=resource,meshes={}}
  for _,name in ipairs(names)do u.meshes[#u.meshes+1]={name=name,visible=true}end
  f.units[#f.units+1]=u;f.by_resource[resource]={u}
 end
 f.frame={explicit_subject=true,identity='selected',root_handle=root,world=f.world}
 local sr={IdString64={from_hex=function(s)return s end},
  World={units_by_resource=function(w,r)assert(w==f.world);f.reads=f.reads+1;return f.by_resource[r]or{}end},
  Unit={alive=function()return true end,world=function()return f.world end,resource_name=function(u)return u.resource end,
   has_node=function()return true end,node=function(_,name)return name end,
   world_pose=function(u,node)return{1,0,0,0,1,0,0,0,1,u.x,0,node=='head'and 2 or 1}end,
   num_meshes=function(u)return #u.meshes end,mesh=function(u,i)return u.meshes[i]end,
   set_mesh_visibility=function(u,i,v,context)assert(context=='default');f.writes=f.writes+1;u.meshes[i].visible=v end},
  Matrix4x4={to_elements=function(p)return unpack(p)end},
  Mesh={name=function(m)return m.name end,visibility=function(m)return m.visible end}}
 f.sr=sr
 f.p=P.new(sr,function()return f.frame end,L);return f
end
local f=fixture();for _=1,120 do f.p.flush();f.p.selection_changed()end;assert(f.reads==0 and f.writes==0,'Off stays idle')
f.p.queue(true);assert(f.p.flush()and f.reads==4 and f.writes==20)
for _=1,120 do f.p.flush();f.p.selection_changed()end;assert(f.reads==4 and f.writes==20,'Unchanged state does not scan or reapply')
f.p.queue(false);assert(f.p.flush()and f.writes==40);assert(f.p.release())
local wrong=fixture();wrong.units[2].x=20;wrong.p.queue(true);assert(not wrong.p.flush()and wrong.writes==0,'Reject a different body before any write')
local ambiguous=fixture();local u=ambiguous.units[1];ambiguous.by_resource[u.resource]={u,u};ambiguous.p.queue(true)
assert(not ambiguous.p.flush()and ambiguous.writes==0,'Reject ambiguous corresponding units')
local changed=fixture();changed.units[2].meshes[1].name=123;changed.p.queue(true)
assert(not changed.p.flush()and changed.writes==0,'Mesh names and layout are pinned before hiding')
local lost=fixture();lost.p.queue(true);assert(lost.p.flush());lost.frame=nil;lost.p.selection_changed()
assert(not lost.p.flush()and lost.writes==40,'Lost selection restores the old visible outfit')
-- Native sparse resource inventories must neither omit equipment nor conceal
-- an ambiguous owner beyond a gap. Validate the complete bounded result first.
do
 local sparse=fixture(true)
 for resource,units in pairs(sparse.by_resource)do sparse.by_resource[resource]={[3]=units[1]}end
 sparse.p.queue_player(true);assert(sparse.p.flush()and sparse.writes==151,'Sparse outfit and weapon inventories are enumerated')
 local reads,writes=sparse.reads,sparse.writes
 for i=1,120 do assert(sparse.p.flush())end
 assert(sparse.reads==reads and sparse.writes==writes,'Sparse enumeration adds no idle work')
 assert(sparse.p.release()and sparse.writes==302)
 local ambiguous=fixture();local u=ambiguous.by_resource['544ed679357b6cb7'][1]
 ambiguous.by_resource[u.resource]={[1]=u,[3]=u};ambiguous.p.queue('helmet',true)
 assert(not ambiguous.p.flush()and ambiguous.writes==0,'A matching entry beyond a gap still prevents hiding')
 local large=fixture();local u=large.by_resource['544ed679357b6cb7'][1];local rows={}
 for i=1,17 do rows[i*3]=u end
 large.by_resource[u.resource]=rows;large.p.queue('helmet',true)
 assert(not large.p.flush()and large.writes==0,'Bounds count actual entries rather than Lua array length')
 for _,key in ipairs({'metadata',0,-1,1.5,math.huge})do
  local invalid=fixture();local u=invalid.by_resource['544ed679357b6cb7'][1]
  invalid.by_resource[u.resource]={[key]=u};invalid.p.queue('helmet',true)
  assert(not invalid.p.flush()and invalid.writes==0,'Invalid inventory keys refuse before any visibility write')
 end
end
-- Each group owns a separate lease; changing cape never rewrites helmet/torso.
do
 local f=fixture()
 local function visible(resource,want)
  for _,mesh in ipairs(f.by_resource[resource][1].meshes)do assert(mesh.visible==want)end
 end
 f.p.queue('helmet',true);assert(f.p.flush()and f.reads==1 and f.writes==5)
 visible('544ed679357b6cb7',false);visible('d2a2e2bc4fa5be21',true);visible('ea846ef460cc5ba0',true)
 f.p.queue('cape',true);assert(f.p.flush()and f.reads==2 and f.writes==9)
 visible('544ed679357b6cb7',false);visible('ea846ef460cc5ba0',false)
 f.p.queue('torso',true);assert(f.p.flush()and f.reads==4 and f.writes==20)
 f.p.queue('cape',false);assert(f.p.flush()and f.writes==24 and f.reads==4)
 visible('544ed679357b6cb7',false);visible('d2a2e2bc4fa5be21',false);visible('ea846ef460cc5ba0',true)
 for _=1,120 do f.p.queue('helmet',true);f.p.flush()end;assert(f.writes==24 and f.reads==4)
 assert(f.p.release()and f.writes==40)
end
-- Full hiding and independent POV requests share one effective lease per group.
do
 local f=fixture(true);local total=0;for _,u in ipairs(f.units)do total=total+#u.meshes end;assert(total==151)
 f.p.queue('helmet',true);assert(f.p.flush()and f.writes==5)
 f.p.queue_player(true);assert(f.p.flush()and f.writes==total)
 for _,u in ipairs(f.units)do for _,m in ipairs(u.meshes)do assert(not m.visible)end end
 local reads,writes=f.reads,f.writes
 for _=1,120 do f.p.flush();f.p.queue_player(true)end
 assert(f.reads==reads and f.writes==writes,'Full hide steady state is idle')
 f.p.queue('cape',true);assert(f.p.flush()and f.writes==writes,'Full hide already owns cape; do not restore/re-hide it')
 f.p.queue_player(false);assert(f.p.flush())
 for _,u in ipairs(f.units)do local visible=u.resource~='544ed679357b6cb7'and u.resource~='ea846ef460cc5ba0'
  for _,m in ipairs(u.meshes)do assert(m.visible==visible,'Full-hide release preserves independent POV requests')end
 end
 assert(f.p.release()and f.writes==total*2)
 local bad=fixture(true);bad.by_resource['a5710e9464a26f48'][1].x=20;bad.p.queue_player(true)
 assert(not bad.p.flush()and bad.writes==0,'Validate all body groups before hiding any')
 local outside=fixture(true);outside.by_resource['968211c0033dce64'][1].x=20;outside.p.queue_player(true);assert(outside.p.flush())
 assert(outside.by_resource['968211c0033dce64'][1].meshes[1].visible,'Do not hide another subject weapon merely because its resource matches')
 outside.p.release()
 local absent=fixture(true);absent.by_resource.e60ae045e0090f4c={};absent.by_resource.a8cffb316f0b5c5f={}
 absent.p.queue_player(true);assert(absent.p.flush()and absent.writes==121,'Unequipped optional support/backpack do not block body hiding');absent.p.release()
 for _,resource in ipairs({'e60ae045e0090f4c','a8cffb316f0b5c5f'})do
  local other=fixture(true);other.by_resource[resource][1].x=20;other.p.queue_player(true);assert(other.p.flush())
  for _,mesh in ipairs(other.by_resource[resource][1].meshes)do assert(mesh.visible,'Foreign support/backpack must remain visible')end
  other.p.release()
  local layout=fixture(true);table.remove(layout.by_resource[resource][1].meshes);layout.p.queue_player(true)
  assert(not layout.p.flush()and layout.writes==0,'Changed attachment mesh layout refuses the whole acquisition before writes')
 end
end
-- Nested accessories are acquired only through a qualified selected pistol.
do
 local function nested()
  local f=fixture(true)
  for _,row in ipairs({{'e53e4b0c20563d21',1,5,2},{'78829731a0563576',4,13,3},
   {'f9df21c8e52cac95',4,13,4},{'7be1e04a7738e673',4,18,5},{'5c1e075cba68340b',4,12,6}})do
   local u={resource=row[1],nodes=row[3],x=row[4],meshes={}}
   for i=1,row[2]do u.meshes[i]={name=i,visible=true}end
   f.units[#f.units+1]=u;f.by_resource[row[1]]={u}
  end
  local prior=f.sr.Unit.world_pose
  f.sr.Unit.world_pose=function(u,node)
   if u.resource=='416d053372c4e433'and(node==24 or node==15)then return{1,0,0,0,1,0,0,0,1,node==24 and 2 or 3,0,1}end
   if u.resource=='968211c0033dce64'and(node==12 or node==14 or node==15)then return{1,0,0,0,1,0,0,0,1,node==12 and 4 or node==14 and 5 or 6,0,1}end
   return prior(u,node)
  end
  f.sr.Unit.num_scene_graph_items=function(u)return u.nodes or(u.resource=='968211c0033dce64'and 43 or 32)end
  return f
 end
 local f=nested();f.p.queue_player(true);assert(f.p.flush()and f.writes==168)
 local reads,writes=f.reads,f.writes;for _=1,120 do f.p.flush()end
 assert(f.reads==reads and f.writes==writes,'Nested accessories do not introduce idle scans or reapplication')
 f.p.queue_player(false);assert(f.p.flush()and f.writes==336)
 for _,u in ipairs(f.units)do for _,m in ipairs(u.meshes)do assert(m.visible)end end
 f=nested();f.by_resource['416d053372c4e433'][1].x=20;f.p.queue_player(true);assert(f.p.flush())
 for _,r in ipairs({'e53e4b0c20563d21','78829731a0563576'})do
  assert(f.by_resource[r][1].meshes[1].visible,'Never hide accessories of a foreign/dropped parent')
 end
 f=nested();f.by_resource.e53e4b0c20563d21[1].x=99;f.p.queue_player(true);assert(f.p.flush())
 assert(f.by_resource.e53e4b0c20563d21[1].meshes[1].visible,'Resource identity alone cannot associate an accessory')
 f=nested();f.by_resource['968211c0033dce64'][1].x=20;f.p.queue_player(true);assert(f.p.flush())
 for _,r in ipairs({'f9df21c8e52cac95','7be1e04a7738e673','5c1e075cba68340b'})do
  assert(f.by_resource[r][1].meshes[1].visible,'Foreign primary accessories remain visible')
 end
 f=nested();f.by_resource['416d053372c4e433'][1].nodes=31;f.p.queue_player(true)
 assert(not f.p.flush()and f.writes==0,'Validate parent graph before indexed node access and before any visibility writes')
 f=nested();f.by_resource.e53e4b0c20563d21[1].nodes=6;f.p.queue_player(true)
 assert(not f.p.flush()and f.writes==0,'Changed accessory graph refuses the transaction')
 f=nested();table.remove(f.by_resource['78829731a0563576'][1].meshes);f.p.queue_player(true)
 assert(not f.p.flush()and f.writes==0,'Changed accessory mesh layout refuses the transaction')
 f=nested();local u=f.by_resource.e53e4b0c20563d21[1];f.by_resource.e53e4b0c20563d21={u,u};f.p.queue_player(true)
 assert(not f.p.flush()and f.writes==0,'Ambiguous nested matches are never hidden')
end
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture_runtime=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local h=fixture_runtime(false,function(h,deps)
 deps.handycam=dofile('freecam/steam_handycam.lua');deps.subject_backend={new=function()error('No native DLL')end};deps.subject_visibility={}
 deps.subject_tracking={new=function()return{head_frame=function()return{identity='body',head={0,0,2}}end}end}
 deps.mesh_visibility={};deps.pov_visibility={new=function()return{
  queue_player=function(value)h.full_desired=value end,queue=function(group,v)h.pov_desired=h.pov_desired or{};h.pov_desired[group]=v end,selection_changed=function()end,
  flush=function()h.pov_hidden=h.pov_desired and(h.pov_desired.helmet or h.pov_desired.torso or h.pov_desired.cape);return true end,release=function()h.pov_hidden=false;return true end}end}
end)
h.open();assert(not h.controls.hide_player.disabled);assert(h.menu.handle.set('hide_player',true)and h.full_desired);assert(h.menu.handle.set('hide_player',false)and not h.full_desired);assert(not h.controls.handycam_hide_helmet.disabled and not h.menu.handle.get('handycam_hide_helmet'))
assert(not h.menu.handle.get('handycam_hide_helmet'),'Saved helmet preference starts Off')
h.menu.handle.set('action_camera_mode',2);assert(h.runtime.begin_shot());h.step(.016)
assert(h.pov_hidden and h.menu.handle.get('handycam_hide_helmet')and h.controls.handycam_hide_helmet.disabled,'Handycam forces helmet hidden without requiring the toggle');assert(h.runtime.reposition_shot());h.step(.016);assert(h.pov_hidden,'Settings must retain POV hiding')
assert(h.menu.handle.get('handycam_hide_helmet')and h.controls.handycam_hide_helmet.disabled)
assert(h.runtime.close()and not h.pov_hidden);assert(not h.menu.handle.get('handycam_hide_helmet'),'Shot override must not persist into saved choice');h.finish()
print('Windows POV: explicit target correspondence, ambiguity/layout guards, idle state, restoration and Handycam menu/exit lifecycle passed')

-- Observed 40-node primary variant and two legitimate magazine/scope slots.
do
 local function variant()
  local f=fixture(true)
  local function add(resource,count,nodes,x)
   local u={resource=resource,nodes=nodes,x=x,meshes={}}
   for i=1,count do u.meshes[i]={name=i,visible=true}end
   f.units[#f.units+1]=u;local rows=f.by_resource[resource]or{};rows[#rows+1]=u;f.by_resource[resource]=rows;return u
  end
  f.primary=add('27ee1ed8f6fb6356',10,40,0)
  f.scope=add('309f7e645a8d2b56',4,14,2)
  f.part=add('cebd25f8778bfdee',5,14,3)
  f.mag1=add('b1bc2b7252ccbc03',5,12,4);f.mag2=add('b1bc2b7252ccbc03',5,12,5)
  local prior=f.sr.Unit.world_pose
  f.sr.Unit.world_pose=function(u,node)
   if u==f.primary and type(node)=='number'and node~=1 then
    local x=({[19]=2,[17]=3,[28]=4,[29]=5})[node];assert(x,'Unexpected parent node');return{1,0,0,0,1,0,0,0,1,x,0,1}
   end
   return prior(u,node)
  end
  f.sr.Unit.num_scene_graph_items=function(u)return u.nodes or 32 end
  return f
 end
 local f=variant();f.p.queue_player(true);assert(f.p.flush()and f.writes==180,'Both qualified accessory instances must hide')
 for _,u in ipairs({f.primary,f.scope,f.part,f.mag1,f.mag2})do for _,m in ipairs(u.meshes)do assert(not m.visible)end end
 local reads,writes=f.reads,f.writes;for i=1,120 do assert(f.p.flush())end;assert(f.reads==reads and f.writes==writes,'Variant adds no idle work')
 f.p.queue_player(false);assert(f.p.flush()and f.writes==360)
 for _,u in ipairs(f.units)do for _,m in ipairs(u.meshes)do assert(m.visible,'Variant restoration failed')end end
 local foreign=variant();foreign.primary.x=20;foreign.p.queue_player(true);assert(foreign.p.flush())
 for _,u in ipairs({foreign.primary,foreign.scope,foreign.part,foreign.mag1,foreign.mag2})do assert(u.meshes[1].visible,'Foreign/dropped weapon accessories remain visible')end
 local unmatched=variant();unmatched.scope.x=99;unmatched.p.queue_player(true);assert(unmatched.p.flush()and unmatched.scope.meshes[1].visible,'Unmatched accessory remains visible')
 local duplicate=variant();duplicate.mag2.x=4;duplicate.p.queue_player(true);assert(not duplicate.p.flush()and duplicate.writes==0,'Two distinct units at one slot are ambiguous')
 local repeated=variant();repeated.by_resource.b1bc2b7252ccbc03={repeated.mag1,repeated.mag1};repeated.p.queue_player(true);assert(not repeated.p.flush()and repeated.writes==0,'Duplicate inventory entries are refused')
 local changed=variant();changed.primary.nodes=41;changed.p.queue_player(true);assert(not changed.p.flush()and changed.writes==0,'Parent graph mismatch refuses before hiding')
 local child=variant();child.scope.nodes=15;child.p.queue_player(true);assert(not child.p.flush()and child.writes==0,'Child graph mismatch refuses before hiding')
 local hidden=variant();hidden.mag1.meshes[1].visible=false;hidden.p.queue_player(true);assert(hidden.p.flush());hidden.p.queue_player(false);assert(hidden.p.flush()and hidden.mag1.meshes[1].visible==false,'Pre-hidden mesh remains hidden after release')
end
print('Observed weapon variant: direct and nested associations, two distinct slots, ambiguity/foreign/layout guards, restoration and idle passed')

-- Repeated shared body anchors are read once per explicit association plan;
-- scalar caching cannot leak a stale correspondence into the next plan.
do
 local f=fixture(true);local old=f.sr.Unit.world_pose;local calls,root_calls=0,0
 f.sr.Unit.world_pose=function(u,node)calls=calls+1;if u==f.root then root_calls=root_calls+1 end;return old(u,node)end
 f.p.queue('body',true);assert(f.p.flush())
 assert(root_calls==5 and calls==31,'Read each selected body bone once per body association instead of 26 times')
 local reads=f.reads;for i=1,120 do assert(f.p.flush())end;assert(calls==31 and f.reads==reads,'Unchanged plan stays idle')
 f.p.queue('body',false);assert(f.p.flush());f.root.x=20
 local writes=f.writes;f.p.queue('body',true)
 assert(not f.p.flush()and f.writes==writes,'A later plan must read new poses and reject stale correspondence')
end
print('Visibility association: per-transition scalar cache cuts shared body reads 26 to 5, has no idle reads and cannot survive into the next plan')
-- Unknown resources must hide from the selected bones, with nested equipment,
-- sparse inventories, no proximity authority and no steady-state scans.
do
 local p=dofile('freecam/windows_pov_visibility.lua');local world={};local reads=0
 local function matrix(x)return{1,0,0,0,1,0,0,0,1,x,0,1}end
 local root={name='body',nodes={head=12,chest=11},poses={[1]=10}}
 local armour={name='new-armour',nodes={head=12,chest=11},poses={[1]=10},meshes=3}
 local rifle={name='unknown-rifle',nodes={},poses={[1]=12,[2]=15},meshes=4}
 local scope={name='unknown-scope',nodes={},poses={[1]=15},meshes=2}
 local foreign={name='foreign',nodes={head=52,chest=51},poses={[1]=50},meshes=4}
 local nearby={name='nearby-unrelated',nodes={},poses={[1]=10.01},meshes=1}
 local units={[1]=foreign,[3]=scope,[6]=armour,[7]=nearby,[8]=rifle}
 local sr={World={units=function()reads=reads+1;return units end},Unit={alive=function(u)return not u.dead end,world=function()return world end,
  has_node=function(u,n)return u.nodes[n]~=nil end,node=function(u,n)return n end,
  world_pose=function(u,n)return matrix(u==root and(n==6 and 12 or n==7 and 11)or u.nodes[n]or u.poses[n])end,num_meshes=function(u)return u.meshes or 0 end,
  num_scene_graph_items=function(u)return #u.poses end,resource_name=function(u)return u.name end},Matrix4x4={to_elements=function(a)return unpack(a)end}}
 local rig={{},{},{},{},{},{name='head'},{name='chest'}}
 local frame={world=world,root_handle=root,identity='same',rig_nodes=rig}
 local scan=p.skeleton_scan(sr,frame,{},function()return 0 end)
 local rows;for i=1,10 do rows=scan.tick(frame);if rows then break end end
 assert(rows and #rows==3 and reads==1,'Find unknown armour, weapon and separately attached scope')
 local found={};for _,r in ipairs(rows)do found[r.unit]=true end
 assert(found[armour]and found[rifle]and found[scope]and not found[foreign]and not found[nearby],'Never hide an unrelated nearby unit')
 for i=1,120 do assert(scan.tick(frame)==rows)end;assert(reads==1,'Completed discovery stays idle')
 local changed=p.skeleton_scan(sr,frame,{},function()return 0 end);changed.tick(frame)
 assert(not pcall(changed.tick,{world=world,root_handle=root,identity='different'}),'Retire discovery when selection changes')
 local dead=p.skeleton_scan(sr,frame,{},function()return 0 end);root.dead=true;assert(not pcall(dead.tick,frame));root.dead=nil
end
print('Full hide: unknown armour/weapon/nested scope, sparse inventory, foreign/nearby exclusion, retirement and completed idle passed')
-- Separate weapons switch uses an independent reversible equipment lease.
do
 local f=fixture(true);f.p.queue_weapons(true);assert(f.p.flush())
 assert(not f.by_resource['968211c0033dce64'][1].meshes[1].visible)
 assert(f.by_resource['544ed679357b6cb7'][1].meshes[1].visible,'Weapons switch must retain helmet/body')
 local writes,reads=f.writes,f.reads;for i=1,120 do assert(f.p.flush())end
 assert(f.writes==writes and f.reads==reads,'Weapons stays idle while unchanged')
 f.p.queue_weapons(false);assert(f.p.flush())
 for _,u in ipairs(f.units)do for _,m in ipairs(u.meshes)do assert(m.visible,'Weapon restoration failed')end end
end
-- The rewrite menu has no depth-shader choices or blur/fog controls. Native DoF remains.
do
 local options=dofile('freecam/photo_options.lua');local pages=options.pages(function()end,function()end,nil,{without_depth_shaders=true})
 local controls={};for _,page in ipairs(pages)do for _,c in ipairs(page.controls)do controls[c.id]=c end end
 assert(#controls.dof_mode.choices==1 and controls.dof_mode.choices[1]=='Native camera')
 assert(#controls.scene_shader.choices==6 and controls.dof and controls.focus_distance and controls.aperture)
 for _,id in ipairs({'dof_quality','dof_strength','bokeh_shape','fog_distance','fog_density','scene_depth_range'})do assert(not controls[id],id)end
 local values=options.read({get=function(id)assert(controls[id],'Read a removed setting');return options.defaults[id]end},controls)
 assert(values.dof_mode==1 and values.scene_depth_range==100,'Missing UI settings retain safe model defaults')
end
print('Hide Weapons: reversible independent lease and idle; depth menu removal preserves native lens and safe settings reads passed')
-- Holstered equipment has an authored local root offset, unlike a hand-held
-- weapon at the bone origin. Recover parent space; hide the nested scope too.
do
 local P=dofile('freecam/windows_pov_visibility.lua');local world={}
 local function mat(x)return{1,0,0,0,1,0,0,0,1,x,0,0}end
 local body={resource='body',root=10};local weapon={resource='holstered',root=12.5,local_x=.5,meshes=2}
 local scope={resource='scope',root=13,local_x=0,meshes=1};local foreign={resource='foreign',root=15,local_x=.5,meshes=2}
 local sr={World={units=function()return{scope,foreign,weapon}end},Unit={alive=function()return true end,world=function()return world end,
  has_node=function()return false end,num_meshes=function(u)return u.meshes or 0 end,resource_name=function(u)return u.resource end,
  num_scene_graph_items=function(u)return u==weapon and 2 or 1 end,
  world_pose=function(u,n)return mat(u==body and(n==6 and 12 or 10)or u==weapon and n==2 and 13 or u.root)end,
  local_pose=function(u)return mat(u.local_x or 0)end},Matrix4x4={to_elements=function(a)return unpack(a)end,from_elements=function(...)return{...}end,
   inverse=function(a)return mat(-a[10])end,multiply=function(a,b)return mat(a[10]+b[10])end}}
 local frame={world=world,root_handle=body,identity='one',rig_nodes={{},{},{},{},{},{}}}
 local scan=P.skeleton_scan(sr,frame,{},function()return 0 end,nil,true);local rows
 for i=1,12 do rows=scan.tick(frame);if rows then break end end
 assert(rows and #rows==2,'Holster bind plus nested scope must be discovered')
 local found={};for _,r in ipairs(rows)do found[r.unit]=true end
 assert(found[weapon]and found[scope]and not found[foreign],'Do not hide a different holstered weapon')
end
print('Holstered weapon regression: authored local offset, selected parent space, nested scope and foreign-equipment refusal passed')
-- Stock equipment visibility writes after update must not defeat a held hide.
do
 local f=fixture(true);f.p.queue_weapons(true);assert(f.p.flush())
 local weapon=f.by_resource['968211c0033dce64'][1];weapon.meshes[1].visible=true
 local writes=f.writes;assert(f.p.maintain()and not weapon.meshes[1].visible and f.writes==writes+1,'Rehide only the changed owned equipment mesh')
 writes=f.writes;for i=1,120 do assert(f.p.maintain())end;assert(f.writes==writes,'Unchanged render ownership performs no setters')
 f.p.queue_weapons(false);assert(f.p.flush()and weapon.meshes[1].visible)
 writes=f.writes;for i=1,120 do assert(f.p.maintain())end;assert(f.writes==writes,'Off performs no enforcement')
end
-- Incremental leases keep earlier discovered parts owned while later units arrive.
do
 local f=fixture(true);local lease=L.new(f.sr);local a=f.units[1];local b=f.units[2]
 local function row(u)return{unit=u,world=f.world,resource=u.resource,indices={1}}end
 assert(lease.hide({row(a)}));assert(lease.append({row(a),row(b)}))
 assert(lease.count()==2 and not a.meshes[1].visible and not b.meshes[1].visible)
 assert(lease.release()and a.meshes[1].visible and b.meshes[1].visible,'Every incremental acquisition restores')
end
print('Equipment render handoff: changed-owned-only enforcement, unchanged/no-off writes and incremental lease restoration passed')
-- The captured holstered resource differs from the held/display resource.
do
 local f=fixture(true);local function mat(x)return{1,0,0,0,1,0,0,0,1,x,0,1}end
 local gun={resource='b80951732a5f58f4',meshes={},graph=40};for i=1,10 do gun.meshes[i]={name=i,visible=true}end
 local scope={resource='309f7e645a8d2b56',meshes={},graph=14};for i=1,4 do scope.meshes[i]={name=i,visible=true}end
 f.by_resource[gun.resource]={gun};f.by_resource[scope.resource]={scope}
 local prior=f.sr.Unit.world_pose
 f.sr.Unit.world_pose=function(u,n)
  if u==gun then return mat(n==1 and .5 or n==19 and 2 or 3)end
  if u==scope then return mat(2.2)end
  return prior(u,n)
 end
 f.sr.Unit.local_pose=function(u,n)assert(n==1);return{1,0,0,0,1,0,0,0,1,u==gun and .5 or .2,0,0}end
 f.sr.Unit.num_scene_graph_items=function(u)return u.graph or 32 end
 f.sr.Matrix4x4.from_elements=function(...)return{...}end
 f.sr.Matrix4x4.inverse=function(a)return{1,0,0,0,1,0,0,0,1,-a[10],-a[11],-a[12]}end
 f.sr.Matrix4x4.multiply=function(a,b)return{1,0,0,0,1,0,0,0,1,a[10]+b[10],a[11]+b[11],a[12]+b[12]}end
 f.p.queue_weapons(true);assert(f.p.flush())
 assert(not gun.meshes[1].visible and not scope.meshes[1].visible,'Hide the offset holstered variant and its offset scope')
 gun.meshes[1].visible=true;assert(f.p.maintain()and not gun.meshes[1].visible,'After-game visibility ownership holds the holstered model')
 f.p.queue_weapons(false);assert(f.p.flush()and gun.meshes[1].visible and scope.meshes[1].visible,'Restore both holstered model and accessory')
end
print('Observed holstered variant: resource/layout, local-root parent, nested offset scope, after-game enforcement and restoration passed')

-- Any other outfit: the units bound to the selected skeleton (shared bones on the same
-- world matrices), grouped by their bones. Another player's or a prop's units never match.
do
 local world={}
 local root={nodes={head=1,chest=1,spine1=1,hips=1,l_hand=1,r_hand=1,cape1=1}}
 -- up: where the piece's LOD meshes sit (bounds centre, metres above the root); proxy: a first mesh
 -- with other bounds, as live pieces have.
 local function unit(name,nodes,meshes,offset,up,proxy)return{name=name,nodes=nodes,meshes=meshes,offset=offset or 0,up=up or 1,proxy=proxy}end
 local all={unit('helmet',{head=1},5,0,1.74),unit('collar',{head=1,chest=1,spine1=1},6,0,1.66),unit('chest',{chest=1,spine1=1},5),
  unit('arm',{chest=1,spine1=1,l_hand=1},5),unit('legs',{hips=1},5),unit('cape',{head=1,chest=1,cape1=1},4),
  unit('other_helmet',{head=1},5,7),unit('prop',{},3),unit('empty',{head=1},0),
  -- Live 2026-10-29: a chest shell authored on the whole rig, one reaching the hips, and a waist piece.
  unit('shell',{head=1,chest=1,spine1=1,hips=1,l_hand=1,r_hand=1},5,0,1.30),unit('vest',{chest=1,spine1=1,hips=1},5),unit('waist',{spine1=1,hips=1},5),
  -- Live: a torso shell with the helmet's bones (its geometry 1.28 m up, a proxy mesh at 2.70), and
  -- a whole-rig suit centred at the hips.
  unit('neck_shell',{head=1,chest=1,spine1=1},5,0,1.28,2.70),unit('suit',{head=1,chest=1,spine1=1,hips=1,l_hand=1,r_hand=1},5,0,.95)}
 local logged={}
 local sr={IdString64={from_hex=function(s)return s end},Matrix4x4={to_elements=function(m)return unpack(m)end},
  World={units_by_resource=function()return{}end,units=function(w)assert(w==world);return all end},
  Unit={alive=function()return true end,world=function()return world end,resource_name=function(u)return u.name end,
   num_meshes=function(u)return u.meshes end,node=function(_,n)return n end,
   has_node=function(u,n)if u==root then return root.nodes[n]~=nil end;return u.nodes[n]~=nil end,
   world_pose=function(u,n)return{1,0,0,0,1,0,0,0,1,u==root and 0 or u.offset,type(n)=='number'and 0 or #n,0}end,
   mesh=function(u,i)return{u=u,i=i}end},
  Mesh={world_pose=function()return{1,0,0,0,1,0,0,0,1,0,0,0}end,
   bounding_volume_components=function(m)local up=m.i==1 and m.u.proxy or m.u.up;return{-.2,-.1,up-.3},{.2,.1,up+.3},.4 end},
  Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end}}
 local rows=P.association(sr,function(m)logged[#logged+1]=m end,function()return 0 end)
 local frame={explicit_subject=true,identity='other outfit',root_handle=root,world=world}
 local function names(group)local r={};for _,row in ipairs(rows(frame,group))do r[#r+1]=row.resource..':'..#row.indices end;table.sort(r);return table.concat(r,',')end
 local helmet,torso,cape,body=names('helmet'),names('torso'),names('cape'),names('body')
 assert(helmet=='collar:6,helmet:5',helmet);assert(torso=='chest:5,neck_shell:5,shell:5,vest:5',torso);assert(cape=='cape:4',cape)
 assert(body=='arm:5,legs:5,suit:5,waist:5',body)
 assert(#logged==4 and logged[1]:find('POV outfit discovery: helmet=2 of 11 bound units',1,true)and logged[1]:find('collar[head+chest+spine1@1.66]',1,true),#logged..' '..table.concat(logged,' | '))
 assert(not rows(frame,'helmet').unsettled,'A bound outfit is settled')
 -- Caught mid-update (no unit on the skeleton yet): flagged for a retry, not an empty hide.
 for _,u in ipairs(all)do u.offset=u.offset+3 end
 local caught=rows(frame,'helmet');assert(#caught==0 and caught.unsettled,'An unsettled outfit is retried')
 for _,u in ipairs(all)do u.offset=u.offset-3 end
 assert(M_short==nil and P.short('[IdString64 "#ID[a5ba6eec2f15cf2d]" 0xa5ba]')=='a5ba6eec2f15cf2d')
 assert(P.classify({head=true,chest=true,cape1=true})=='cape'and P.classify({chest=true,r_hand=true})=='body'and P.classify({})==nil)
 assert(P.classify({head=true,chest=true,spine1=true,hips=true,l_hand=true,r_hand=true})=='torso','A whole-rig chest shell is torso')
 assert(P.classify({chest=true,spine1=true,hips=true})=='torso'and P.classify({spine1=true,hips=true})=='body','Chest reaching the hips is torso; a waist is body')
 -- Geometry decides only where bones are ambiguous; without it the bone rules stand.
 assert(P.classify({head=true,chest=true},{up=1.28})=='torso'and P.classify({head=true,chest=true},{up=1.74})=='helmet','Head pieces by height')
 assert(P.classify({chest=true,hips=true,l_hand=true,r_hand=true},{up=.95})=='body','A whole-rig suit at the hips stays with the body')
 assert(P.ambiguous({head=true})and P.ambiguous({chest=true,hips=true,l_hand=true,r_hand=true})and not P.ambiguous({chest=true,l_hand=true})and not P.ambiguous({head=true,cape1=true}))
 assert(P.geometry({Unit={}},{},5,{})==nil,'No mesh natives: no geometry, bone rules')
 print('Other outfits: skeleton-bound units grouped into helmet, torso, cape and body; foreign and mesh-less units refused passed')
end

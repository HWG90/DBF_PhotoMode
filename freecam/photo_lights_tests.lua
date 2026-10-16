local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'photo_lights.lua')
local a,b={},{};local worlds={a,b};local main=a;local resource=true;local next_id=0;local units={};local destroyed={};local writes={};local fail_destroy=false;local fail_component=false;local light_node=2;local light_parent=1;local fail_intensity_once=false;local fail_position_once=false
local function vector(...)return{...}end
local temp_count=10;local restored_scopes=0;local fail_marker=false
local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return vector(...)end})
local sr={Application={main_world=function()return main end,worlds=function()return worlds end,can_get=function(kind,id)assert(kind=='unit'and id==M.resource);return resource end},
 Vector3=V,Quaternion={look=function(forward,up)return{forward=forward,up=up}end},IdString64={from_hex=function(id)return id end},World={},Unit={},Light={},
 Script={temp_count=function()return temp_count end,set_temp_count=function(value)temp_count=value;restored_scopes=restored_scopes+1 end},Matrix4x4={forward=function(pose)return pose.forward end}}
function sr.World.spawn_unit(world,id,position,rotation)
 assert(world==main and id==M.resource);next_id=next_id+1;local unit={id=next_id,alive=true,world=world,pos=position,rot=rotation,light={node=light_node}};units[next_id]=unit;unit.light.unit=unit;return unit
end
function sr.World.destroy_unit(world,unit)
 assert(world==unit.world,'Foreign-world destruction');assert(units[unit.id]==unit,'Unowned unit destruction')
 if fail_destroy then error('retry cleanup')end;unit.alive=false;destroyed[#destroyed+1]=unit.id
end
function sr.World.update_unit(world,unit)assert(world==unit.world);writes[#writes+1]={'update',unit.id}end
function sr.Unit.alive(unit)return unit.alive end
function sr.Unit.num_lights(unit)return 1 end
function sr.Unit.light(unit,index)assert(index==1);if fail_component then error('component missing')end;return unit.light end
function sr.Unit.set_local_position(unit,node,p)if fail_position_once then fail_position_once=false;error('Position update refused')end;assert(node==1);unit.pos=p end
function sr.Unit.set_local_rotation(unit,node,q)assert(node==1);unit.rot=q end
function sr.Unit.scene_graph_parent(unit,node)assert(unit.light.node==node);return light_parent end
function sr.Light.node(light)return light.node end
function sr.Light.world_position(light)temp_count=temp_count+1;if fail_marker then error('marker unavailable')end;return{unpack(light.unit.pos)}end
function sr.Light.world_pose(light)temp_count=temp_count+1;return{forward={unpack(light.unit.rot.forward)}}end
function sr.Light.set_local_position(light,parent,position)assert(parent.light==light);light.local_position=position;if light.node==1 then parent.pos=position end end
function sr.Light.set_local_rotation(light,parent,rotation)assert(parent.light==light);light.local_rotation=rotation;if light.node==1 then parent.rot=rotation end end
for _,key in ipairs({'type','color','intensity','casts_shadows','enabled','baked','auto_falloff_end_and_culling','falloff_start','falloff_end','spot_angle_start','spot_angle_end'})do
 sr.Light['set_'..key]=function(light,value)if key=='intensity'and fail_intensity_once then fail_intensity_once=false;error('native intensity update refused')end;light[key]=value;writes[#writes+1]={key,value}end
end
local camera={position={10,20,30},forward={0,1,0},right={1,0,0},up={0,0,1}}
local manager=M.new(sr)
assert(not manager.create({}), 'Spawned without camera context')
assert(manager.tick(a,camera));assert(manager.ready(a));assert(manager.count()==0)
assert(manager.create({kind='omni',color='#8080FF',right=2,forward=3,up=4,range=12,intensity=6}))
local first=units[1];assert(first.pos[1]==12 and first.pos[2]==23 and first.pos[3]==34)
assert(first.light.type=='omni'and first.light.enabled and first.light.intensity==6 and first.light.falloff_end==12 and first.light.falloff_start==0)
assert(math.abs(first.light.color[1]-.2158605)<.000001 and first.light.color[3]==1,'sRGB picker color was not decoded to linear')
assert(first.light.casts_shadows==false and first.light.baked==false)
assert(first.light.auto_falloff_end_and_culling==false,'Prefab automatic falloff overrode manual range')
assert(first.light.local_position[1]==0 and first.light.local_rotation.forward[2]==1,'Authored light offset leaked into camera placement')
local markers=manager.markers();assert(#markers==1 and markers[1].id==1 and markers[1].position[1]==12 and markers[1].forward[2]==1 and markers[1].color=='#8080FF'and markers[1].enabled and markers[1].selected)
markers[1].position[1]=999;assert(manager.markers()[1].position[1]==12 and first.pos[1]==12,'Marker data leaked owned vectors')
assert(temp_count==10 and restored_scopes==2,'Marker readback leaked engine temporary objects')
fail_marker=true;local missing,marker_why=manager.markers();assert(#missing==0 and marker_why and temp_count==10 and restored_scopes==3,'Failed marker readback did not restore temporary scope');fail_marker=false
worlds={b};fail_marker=true;missing,marker_why=manager.markers();assert(#missing==0 and marker_why==nil and manager.count()==1 and temp_count==10,'Marker dereferenced a retired world or mutated owned records');worlds={a,b};fail_marker=false
local scope=sr.Script;sr.Script=nil;missing,marker_why=manager.markers();assert(#missing==0 and marker_why and temp_count==10,'Missing temporary API was not an honest marker gate');sr.Script=scope
local count_fn,set_fn=scope.temp_count,scope.set_temp_count;scope.temp_count=nil;scope.set_temp_count=nil;scope.temp_byte_count=count_fn;scope.set_temp_byte_count=set_fn
assert(#manager.markers()==1 and temp_count==10,'Byte-count temporary scope fallback did not preserve marker data')
scope.temp_count=count_fn;scope.set_temp_count=set_fn;scope.temp_byte_count=nil;scope.set_temp_byte_count=nil
local copied,index,total=manager.selected();assert(index==1 and total==1 and copied.color=='#8080FF');copied.intensity=100
assert(manager.selected().intensity==6,'Caller changed owned state without an update')
assert(manager.create({kind='spot',cone=60}));assert(units[2].light.type=='spot'and math.abs(units[2].light.spot_angle_end-math.pi/3)<.0000001)
assert(manager.create({kind='omni'}));assert(not manager.create({}), 'More than three lights spawned')
assert(manager.select(1));assert(manager.update({enabled=false,intensity=8,range=10}));assert(not first.light.enabled and first.light.intensity==8)
local before=#writes;assert(not manager.update({intensity=0/0}));assert(not manager.update({color='#bad'}));assert(#writes==before,'Invalid settings touched native light properties')
assert(not manager.select(99));assert(not manager.remove(99));assert(#destroyed==0)
-- Stationary light positions stay fixed as the camera moves. Opting into
-- follow-camera rebases its offsets; moving to camera rebases a fixed light.
local moved={position={100,200,300},forward={1,0,0},right={0,-1,0},up={0,0,1}}
assert(manager.tick(a,moved));assert(first.pos[1]==12 and first.pos[2]==23)
assert(manager.update({follow_camera=true}));assert(first.pos[1]==103 and first.pos[2]==198 and first.pos[3]==304)
local moved_again={position={200,300,400},forward={0,1,0},right={1,0,0},up={0,0,1}}
assert(manager.tick(a,moved_again));assert(first.pos[1]==202 and first.pos[2]==303 and first.pos[3]==404)
assert(manager.update({follow_camera=false}));assert(manager.tick(a,camera));assert(first.pos[1]==202)
assert(manager.place_at_camera());assert(first.pos[1]==12 and first.pos[2]==23)
assert(manager.remove(2));assert(manager.count()==2 and destroyed[1]==2)
fail_destroy=true;assert(not manager.release('exit')and manager.count()==2,'Failed cleanup lost an owned handle')
local old_count=next_id;main=b
assert(not manager.tick(b,camera));assert(not manager.create({}));assert(next_id==old_count,'Changed scene spawned while cleanup was pending')
fail_destroy=false;assert(manager.tick(b,camera));assert(manager.count()==0 and#destroyed==3)
-- A retired world already destroyed its units. Never call a stale world API.
assert(manager.create({}));local destroyed_before=#destroyed;worlds={a};main=a
assert(manager.tick(a,camera));assert(manager.count()==0 and#destroyed==destroyed_before)
assert(manager.create({}));units[next_id].alive=false;assert(manager.tick(a,camera));assert(manager.count()==0 and#destroyed==destroyed_before)
-- Missing assets/APIs are honest capability gates; no placeholder spawns.
resource=false;before=next_id;assert(not manager.ready(a));assert(not manager.create({}));assert(next_id==before);resource=true
local spot_start=sr.Light.set_spot_angle_start;sr.Light.set_spot_angle_start=nil
local ready,why,caps=manager.ready(a);assert(ready and caps.spot);assert(manager.create({kind='spot'}),'Helldivers cone-end API alone should support spot lights');assert(manager.release())
sr.Light.set_spot_angle_start=spot_start
local spot_end=sr.Light.set_spot_angle_end;sr.Light.set_spot_angle_end=nil
ready,why,caps=manager.ready(a);assert(ready and not caps.spot);before=next_id;assert(not manager.create({kind='spot'}));assert(next_id==before)
sr.Light.set_spot_angle_end=spot_end;assert(manager.tick(a,camera))
local range_end=sr.Light.set_falloff_end;sr.Light.set_falloff_end=nil
assert(manager.create({kind='omni'}));assert(not manager.update({range=5}));sr.Light.set_falloff_end=range_end
assert(manager.release());local intensity=sr.Light.set_intensity;sr.Light.set_intensity=nil
assert(not manager.ready(a));assert(not manager.create({}));sr.Light.set_intensity=intensity
assert(manager.tick(a,camera));fail_component=true;fail_destroy=true;before=next_id
assert(not manager.create({}));assert(next_id==before+1 and manager.count()==1,'Partial initialization was not retained for cleanup')
fail_component=false;fail_destroy=false;assert(manager.release());assert(manager.count()==0)
-- Invalid camera data is not retained, and cannot produce an accidental spawn.
local malformed={position={1,2,3},forward={0,1,0},right={0,1,0},up={0,0,1}}
assert(not manager.tick(a,malformed));before=next_id;assert(not manager.create({}));assert(next_id==before)
assert(manager.tick(a,camera));assert(manager.create({}));assert(manager.tick(nil,nil));assert(manager.count()==0)
-- Render/menu requests perform no native mutations until the update drain.
before=next_id;assert(manager.queue('create',{kind='omni'}));assert(next_id==before and manager.pending)
assert(manager.flush(a,camera));assert(next_id==before+1 and manager.count()==1 and not manager.pending)
local queued_unit=units[next_id];assert(manager.queue('update',{intensity=4}));assert(manager.queue('update',{range=6}));assert(queued_unit.light.intensity==3)
assert(manager.flush(a,camera));assert(queued_unit.light.intensity==4 and queued_unit.light.falloff_end==6)
assert(manager.queue('create',{}));assert(manager.queue('release','exit before spawn'));assert(manager.flush(a,malformed));assert(next_id==before+1 and manager.count()==0,'Exit did not discard a pending spawn')
-- Root and child attachments share the unit's placement. Light setters on a
-- root-attached component must never zero or reorient the placed unit.
assert(manager.tick(a,camera));light_node=1;assert(manager.create({kind='spot',right=2,forward=3,up=4}))
local root_light=units[next_id]
assert(root_light.pos[1]==12 and root_light.pos[2]==23 and root_light.pos[3]==34,'Root light placement was reset')
assert(root_light.rot.forward[2]==1 and root_light.light.local_position==nil,'Root light received a child transform reset')
assert(manager.update({follow_camera=true}));assert(manager.tick(a,moved));assert(root_light.pos[1]==103 and root_light.pos[2]==198)
assert(manager.release());assert(manager.tick(a,camera));light_node=2;light_parent=3;before=next_id
assert(not manager.create({})and next_id==before+1 and manager.count()==0,'Unsupported child hierarchy was kept as usable')
light_parent=1;local node_api=sr.Light.node;sr.Light.node=nil;before=next_id
assert(not manager.ready(a)and not manager.create({})and next_id==before,'Missing transform node API spawned a light');sr.Light.node=node_api
-- A failed native edit restores all previous properties and camera anchor.
assert(manager.tick(a,camera));assert(manager.create({intensity=6,color='#FFFFFF'}));local restored_unit=units[next_id]
assert(manager.tick(a,moved));fail_intensity_once=true
assert(not manager.update({kind='spot',color='#FF0000',intensity=9,follow_camera=true}))
assert(manager.selected().intensity==6 and not manager.selected().follow_camera)
assert(restored_unit.light.type=='omni'and restored_unit.light.color[2]==1 and restored_unit.light.intensity==6 and restored_unit.light.enabled,'Failed update left partial native properties')
assert(restored_unit.pos[1]==10 and restored_unit.pos[2]==21,'Failed edit retained a changed camera anchor')
assert(manager.update({follow_camera=true}));fail_position_once=true
assert(not manager.tick(a,moved_again));assert(restored_unit.pos[1]==101 and restored_unit.pos[2]==200,'Failed follow tick retained partial placement')
assert(manager.tick(a,moved_again));assert(restored_unit.pos[1]==200 and restored_unit.pos[2]==301,'Follow movement did not recover after failure')
-- Deleting an earlier light retains selection of the same owned light.
assert(manager.create({intensity=7}));assert(manager.create({intensity=8}));assert(manager.select(2));assert(manager.remove(1))
local selected_values,selected_index=manager.selected();assert(selected_values.intensity==7 and selected_index==1,'Removing an earlier record changed the selected light')
assert(manager.release());assert(manager.tick(a,camera));before=next_id
assert(not manager.create(1)and not manager.queue('create',1)and not manager.queue('update','bad')and next_id==before,'Invalid action payload reached native mutation')
local mirrored={position={1,2,3},forward={0,1,0},right={-1,0,0},up={0,0,1}}
assert(not manager.tick(a,mirrored)and not manager.create({}),'Mirrored camera basis was accepted')
assert(manager.tick(a,camera))
assert(manager.create({intensity=10000,range=1000}));assert(manager.selected().intensity==10000 and manager.selected().range==1000,'Requested expanded lighting limits were clamped')
assert(manager.update({intensity=10100,range=1100}));assert(manager.selected().intensity==10000 and manager.selected().range==1000,'Expanded lighting limits were not bounded')
assert(manager.update({intensity=.01,range=.11}));assert(manager.selected().intensity==.01 and manager.selected().range==.11,'Fine light values were discarded')
local function up(fn,wanted)for i=1,80 do local key,value=debug.getupvalue(fn,i);if not key then return end;if key==wanted then return value end end end
local shared=manager;local borrowed={owner=manager,records=up(manager.list,'records'),selected=up(manager.selected,'selected'),world=up(manager.tick,'world'),frame=up(manager.tick,'frame'),serial=up(manager.create,'serial')}
local preserved=units[next_id];local serial_before=next_id;local destroyed_handoff=#destroyed
local original_create=manager.create;local serial_saved=borrowed.serial;borrowed.serial=-1
assert(not pcall(M.new,sr,nil,manager,borrowed)and manager.create==original_create and manager.count()==1,'Invalid handoff changed ownership before validation');borrowed.serial=serial_saved
manager=M.new(sr,nil,manager,borrowed)
assert(manager==shared and manager.count()==1 and manager.selected().intensity==.01 and next_id==serial_before and#destroyed==destroyed_handoff,'Owned handoff changed units or values')
assert(manager.queue('update',{intensity=123.45,range=567.89}));assert(manager.flush(a,camera));assert(preserved.light.intensity==123.45 and preserved.light.falloff_end==567.89,'Transferred light did not accept extended live values')
assert(manager.create({}));assert(manager.list()[2].id>manager.list()[1].id,'Owned handoff reset the session serial')
assert(manager.release());assert(not preserved.alive and#destroyed==destroyed_handoff+2,'Transferred ownership did not clean up exact original units')
assert(manager.tick(a,camera))
local prior_manager=manager;local marker=function()return true end;manager.update_from_photo=marker
manager=M.new(sr,nil,manager);assert(manager==prior_manager and manager.update_from_photo==marker,'Empty refresh changed shared manager identity')
assert(manager.tick(a,camera));assert(manager.create({}));assert(not pcall(M.new,sr,nil,manager),'Refresh abandoned an owned light')
assert(manager.release());assert(manager.queue('create',{}));assert(not pcall(M.new,sr,nil,manager),'Refresh abandoned queued work');assert(manager.queue('release'));assert(manager.flush(a,camera))
-- Full Photo exit keeps only numeric setup data; update-time re-entry creates
-- fresh units at the saved placements. The world handle alone is insufficient:
-- this game can reuse it for a different mission/ship generation.
local epoch=70
manager.scene_context=function()return main,epoch end
assert(manager.tick(a,camera));assert(manager.create({kind='spot',cone=75,right=2,forward=3,up=4,intensity=123,color='#10A0FF',range=44}))
local fixed=units[next_id];local fixed_id=manager.list()[1].id
assert(manager.create({enabled=false,intensity=9,follow_camera=true}));local followed=units[next_id];local followed_id=manager.list()[2].id
assert(manager.tick(a,moved));assert(manager.select(1))
local fixed_pos={unpack(fixed.pos)};local followed_pos={unpack(followed.pos)}
assert(manager.queue('update',{intensity=999}));assert(manager.queue('release','photo mode exited'))
fail_destroy=true;assert(not manager.flush(nil,nil)and manager.count()==2)
local retained=assert(manager.saved_setup());assert(#retained.definitions==2 and retained.definitions[1].values.intensity==123,'Exit saved uncommitted menu edits')
retained.definitions[1].anchor.position[1]=999;assert(manager.saved_setup().definitions[1].anchor.position[1]==10,'Retained definition leaked mutable state')
for _,definition in ipairs(manager.saved_setup().definitions)do
 assert(definition.unit==nil and definition.world==nil and definition.light==nil and type(definition.anchor.position[1])=='number','Retained setup kept native handles')
end
fail_destroy=false;assert(manager.flush(nil,nil));assert(manager.count()==0 and not fixed.alive and not followed.alive)
local suspended_serial=next_id;assert(manager.flush(nil,nil));assert(next_id==suspended_serial and manager.saved_setup(),'Inactive update discarded or respawned setup')
-- Empty in-place migration retains setup, provider and shared callback identity.
local shared_retained=manager;manager=M.new(sr,nil,manager);assert(manager==shared_retained and manager.saved_setup())
assert(not manager.flush(a,malformed)and next_id==suspended_serial and manager.saved_setup(),'Unavailable camera restored or discarded retained placement')
resource=false;assert(not manager.flush(a,moved_again)and manager.count()==0 and manager.saved_setup(),'Temporary missing asset discarded retained lights');resource=true
fail_component=true;fail_destroy=true;assert(not manager.flush(a,moved_again)and manager.count()==1 and manager.saved_setup(),'Failed restoration abandoned owned cleanup')
fail_component=false;fail_destroy=false;assert(manager.flush(a,moved_again));assert(manager.count()==2 and not manager.saved_setup())
local reopened_fixed=units[next_id-1];local reopened_followed=units[next_id]
assert(reopened_fixed~=fixed and reopened_followed~=followed and reopened_fixed.pos[1]==fixed_pos[1]and reopened_fixed.pos[2]==fixed_pos[2]and reopened_fixed.pos[3]==fixed_pos[3],'Re-entry reused a stale unit or changed fixed placement')
assert(reopened_followed.pos[1]==followed_pos[1]and reopened_followed.pos[2]==followed_pos[2],'Initial follow placement was not retained')
local restored_values,restored_index=manager.selected();assert(restored_index==1 and restored_values.kind=='spot'and restored_values.cone==75 and restored_values.intensity==123 and restored_values.color=='#10A0FF'and restored_values.range==44)
assert(manager.list()[1].id==fixed_id and manager.list()[2].id==followed_id and not reopened_followed.light.enabled,'Selection, identity or disabled state changed on re-entry')
assert(manager.flush(a,moved_again));assert(manager.count()==2 and reopened_fixed.pos[1]==fixed_pos[1]and reopened_followed.pos[1]==200,'Follow setting did not resume or duplicated lights')
fail_intensity_once=true;assert(not manager.update({intensity=500}));assert(manager.release('photo mode exited'));assert(manager.flush(a,camera));assert(manager.selected().intensity==123 and manager.count()==2,'Successful edit rollback was lost when reopening')
assert(manager.remove(1));assert(manager.release('photo mode exited'));assert(manager.flush(a,camera));assert(manager.count()==1 and manager.list()[1].id==followed_id,'Removed light resurrected')
assert(manager.queue('release','removed manually'));assert(manager.flush(a,camera));assert(not manager.saved_setup());assert(manager.flush(a,camera)and manager.count()==0,'Remove all resurrected setup')
assert(manager.create({}));assert(manager.release('photo mode exited'));local retired_destroyed=#destroyed;epoch=epoch+1
assert(manager.flush(nil,nil)and not manager.saved_setup());assert(manager.flush(a,camera)and manager.count()==0 and#destroyed==retired_destroyed,'Reused world handle restored a previous scene')
assert(manager.create({}));local live_retired=units[next_id];local alive_api=sr.Unit.alive;local stale_reads=0
sr.Unit.alive=function(unit)if unit==live_retired then stale_reads=stale_reads+1;error('stale generation')end;return alive_api(unit)end
epoch=epoch+1;assert(#manager.markers()==0 and stale_reads==0,'Render marker dereferenced a retired scene generation')
assert(manager.flush(a,camera)and manager.count()==0 and stale_reads==0,'Epoch retirement dereferenced an old owned unit');sr.Unit.alive=alive_api
assert(manager.create({}));assert(manager.release('photo mode exited'));local provider=manager.scene_context;manager.scene_context=function()error('generation temporarily unavailable')end
assert(not manager.flush(a,camera)and manager.saved_setup()and manager.count()==0,'Unknown scene identity restored or discarded setup');manager.scene_context=provider
assert(manager.flush(a,camera)and manager.count()==1);assert(manager.close('loader disabled'));assert(not manager.saved_setup())
assert(manager.tick(a,camera));assert(manager.create({}));assert(manager.release('photo mode exited'));main=b;worlds={a,b}
assert(manager.flush(nil,nil)and not manager.saved_setup());assert(manager.flush(b,camera)and manager.count()==0,'Different live world reused retained setup');main=a
assert(manager.tick(a,camera));assert(manager.create({}));assert(manager.release('photo mode exited'));assert(manager.clear());assert(manager.flush(a,camera)and manager.count()==0,'Explicit clear while suspended left retained definitions')
-- Marker drags queue one absolute-world edit; aiming rebuilds an orthonormal
-- facing basis and leaves light movement independent of the camera afterward.
assert(manager.create({kind='spot',right=2,forward=3,up=4,follow_camera=true}));local move_id=manager.list()[1].id;local moving=units[next_id]
assert(manager.markers()[1].index==1 and manager.list()[1].position[1]==12)
before=#writes
for i=1,50 do assert(manager.queue('move',{id=move_id,position={40+i,50,60},aim={90,55,60}}))end
assert(#writes==before,'Gizmo drag wrote from render');assert(manager.flush(a,camera));assert(moving.pos[1]==90 and moving.pos[2]==50 and moving.rot.forward[2]==1)
assert(not manager.selected().follow_camera and manager.selected().right==0 and manager.selected().forward==0,'World drag retained camera offsets/follow')
assert(manager.queue('aim',{id=move_id,target={90,50,70}}));assert(manager.flush(a,camera));assert(math.abs(moving.rot.forward[3]-1)<1e-9,'Vertical subject aim failed')
before=#writes;assert(not manager.move({id=move_id,position={0/0,0,0}}));assert(not manager.aim({id=move_id,target={90,50,60}}));assert(#writes==before,'Invalid/coincident aim changed the light')
fail_intensity_once=true;assert(not manager.move({id=move_id,position={1,2,3},aim={2,2,3}}));assert(moving.pos[1]==90 and moving.pos[3]==60 and moving.rot.forward[3]==1,'Failed move did not roll back placement')
local function same(x,y)
 if type(x)~=type(y)then return false end;if type(x)~='table'then return x==y end
 for k,v in pairs(x)do if not same(v,y[k])then return false end end;for k in pairs(y)do if x[k]==nil then return false end end;return true
end
local subject={10,25,30};local spawn_api=sr.World.spawn_unit
sr.World.spawn_unit=function(...)assert(manager.count()<M.maximum,'Setup exceeded three owned units');return spawn_api(...)end
before=next_id;assert(manager.queue('preset',{name='key_fill_rim',target=subject,frame=camera,distance=3}));assert(next_id==before)
assert(manager.flush(a,camera));assert(manager.count()==3)
for _,light in ipairs(manager.list())do
 local dx,dy,dz=subject[1]-light.position[1],subject[2]-light.position[2],subject[3]-light.position[3];local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
 assert(math.abs(light.forward[1]-dx/distance)<1e-8 and math.abs(light.forward[2]-dy/distance)<1e-8 and math.abs(light.forward[3]-dz/distance)<1e-8,'Preset spot missed the subject')
end
local exported=manager.export_setup();exported.definitions[1].anchor.position[1]=999;assert(manager.export_setup().definitions[1].anchor.position[1]~=999,'Export leaked mutable anchors')
local original_setup=manager.export_setup();fail_intensity_once=true
assert(not manager.preset({name='portrait',target={20,30,40},frame=camera}));assert(same(original_setup,manager.export_setup())and not manager.pending,'Preset failure lost the original setup')
before=#writes;assert(not manager.preset({name='bad',target=subject}));assert(not manager.preset({name='portrait',target=subject,distance=0/0}));assert(#writes==before,'Invalid setup began a replacement')
local cone_end=sr.Light.set_spot_angle_end;sr.Light.set_spot_angle_end=nil
assert(not manager.preset({name='portrait',target=subject})and same(original_setup,manager.export_setup()),'Unsupported spots replaced existing lights');sr.Light.set_spot_angle_end=cone_end
assert(manager.preset({name='dramatic_side',target=subject,frame=camera}));assert(manager.count()==2)
assert(manager.release('photo mode exited'));assert(manager.flush(a,moved));assert(manager.count()==2,'Preset did not survive same-scene Photo exit')
assert(manager.clear());assert(manager.tick(a,camera));assert(manager.create({intensity=7}));original_setup=manager.export_setup()
local original_light=sr.Unit.light;local failed_unit=next_id+1
sr.Unit.light=function(unit,index)if unit.id==failed_unit then error('new light component unavailable')end;return original_light(unit,index)end
fail_destroy=true;assert(not manager.preset({name='portrait',target=subject,frame=camera}));assert(manager.pending and manager.count()==2 and same(original_setup,manager.export_setup()),'Partial preset lost retry ownership or original setup')
fail_destroy=false;sr.Unit.light=original_light
assert(not manager.flush(a,camera));assert(not manager.pending and manager.count()==1 and same(original_setup,manager.export_setup()),'Preset rollback did not finish owned cleanup')
assert(manager.flush(a,camera));assert(manager.clear());sr.World.spawn_unit=spawn_api
local options=dofile(root..'photo_options.lua');local controller_factory=dofile(root..'controller.lua')
local previous_api=DBFMCM;local values={};local controls={};local open=false;local owned=false
local api={camera_input={down=function()return false end,focused=function()return true end,
 acquire=function()owned=true;return{}end,release=function()owned=false;return true end,
 sample=function()return{dt=.016,wheel=0,mouse_x=0,mouse_y=0}end},is_open=function()return open end,close=function()open=false;return true end}
function api.register(definition)
 api.definition=definition
 for _,page in ipairs(definition.pages)do for _,control in ipairs(page.controls)do controls[control.id]=control;values[control.id]=control.default end end
 local handle={get=function(key)return values[key]end,unregister=function()return true end}
 handle.set=function(key,value)local control=controls[key];assert(not(control and control.disabled),'Control disabled');values[key]=value;if control and control.on_change then control.on_change(value)end;return true end
 api.handle=handle;return handle
end
DBFMCM=api;local photo={active=false,input={}}
local controller=controller_factory.new(photo,{},function()return true end,function()end,nil,options,nil,nil,nil,nil,nil,nil,manager)
controller.tick(.016);assert(controls.light_add.disabled,'Inactive lighting action was enabled')
controls.toggle.on_activate();assert(photo.active and owned)
photo.light_context={world=a,position=camera.position,forward=camera.forward,right=camera.right,up=camera.up}
controller.tick(.016);assert(not controls.light_add.disabled and controls.light_intensity.disabled)
before=next_id;controls.light_add.on_activate();assert(manager.pending and next_id==before,'Lighting UI spawned a unit in render')
assert(manager.flush(a,photo.light_context));controller.tick(.016)
assert(manager.count()==1 and not controls.light_intensity.disabled and not manager.pending,'Light control readback queued an unintended edit')
api.handle.set('light_intensity',7);assert(manager.pending and units[next_id].light.intensity==3)
assert(manager.flush(a,photo.light_context));controller.tick(.016);assert(units[next_id].light.intensity==7 and api.handle.get('light_intensity')==7)
api.handle.set('hide_controls',true);controller.tick(.016);assert(manager.count()==1,'Hiding controls removed photo lighting')
open=true;controller.tick(.016);assert(manager.count()==1,'MCM input handoff removed photo lighting');open=false
assert(controller.stop());assert(manager.count()==1 and manager.pending and photo.light_context==nil,'Photo exit performed render-phase destruction')
assert(manager.flush(nil,nil));assert(manager.count()==0)
controls.toggle.on_activate();photo.light_context={world=a,position=moved.position,forward=moved.forward,right=moved.right,up=moved.up}
assert(manager.flush(a,photo.light_context));controller.tick(.016);assert(manager.count()==1 and manager.selected().intensity==7 and units[next_id].pos[1]==10,'Controller re-entry required Add light or lost placement/settings')
assert(controller.close());assert(manager.count()==0 and not manager.pending and not owned,'Loader close did not perform final owned cleanup')
DBFMCM=previous_api
-- The owning MCM core rejects writes to disabled controls. Exercise its real
-- cloned registration and handles, rather than permissive UI readback mocks.
local real_api=dofile('src/core.lua').new(nil,function()end)
real_api.camera_input=api.camera_input;real_api.is_open=function()return false end;real_api.close=function()return true end
DBFMCM=real_api;local real_photo={active=false,input={}}
local real_controller=controller_factory.new(real_photo,{},function()return true end,function()end,nil,options,nil,nil,nil,nil,nil,nil,manager)
real_controller.tick(.016);local real_mod=assert(real_api.mods.dbf_freecam);local real_handle=real_mod.handle
real_mod.controls.toggle.on_activate();real_photo.light_context={world=a,position=camera.position,forward=camera.forward,right=camera.right,up=camera.up}
real_controller.tick(.016);assert(manager.queue('create',{kind='omni',enabled=false}));assert(manager.flush(a,real_photo.light_context))
real_controller.tick(.016);assert(real_photo.active and real_mod.controls.light_cone.disabled,'Point readback closed Photo Mode or enabled the cone')
assert(real_handle.get('light_enabled')==false and manager.count()==1 and not manager.pending,'MCM readback changed lighting state')
assert(real_handle.set('light_kind',2));assert(manager.flush(a,real_photo.light_context));real_controller.tick(.016)
assert(not real_mod.controls.light_cone.disabled and real_handle.get('light_cone')==45,'Spot readback did not enable its stored cone')
assert(real_handle.set('light_cone',75));assert(manager.flush(a,real_photo.light_context));real_controller.tick(.016)
assert(manager.selected().cone==75 and manager.selected().kind=='spot')
assert(real_controller.stop());assert(manager.flush(nil,nil));assert(real_controller.close());assert(manager.count()==0 and not owned)
DBFMCM=previous_api
-- Follow Player retains the authored placement and orientation; only the
-- player's translation is applied, independently of free-camera movement.
do
 main=a;worlds={a,b};local follower=M.new(sr);local player={1,2,3}
 follower.scene_context=function()return main,1 end
 follower.player_context=function()return{world=main,position=player}end
 assert(follower.tick(a,camera)and follower.create({right=2,forward=3,up=4}))
 local lamp=units[next_id];local x,y,z=lamp.pos[1],lamp.pos[2],lamp.pos[3]
 assert(follower.update({follow_player=true})and not follower.selected().follow_camera)
 assert(lamp.pos[1]==x and lamp.pos[2]==y,'Enabling player follow snapped placement')
 local unchanged=#writes;assert(follower.tick(a,moved));assert(#writes==unchanged,'Stationary player caused redundant native light writes')
 player={11,22,33};local appearance_writes=#writes;assert(follower.tick(a,moved));assert(#writes==appearance_writes+1 and writes[#writes][1]=='update','Player follow reapplied light appearance')
 assert(lamp.pos[1]==x+10 and lamp.pos[2]==y+20 and lamp.pos[3]==z+30,'Player translation did not move the light rig')
 local export=follower.export_setup();assert(export.definitions[1].anchor.forward[2]==1,'Free camera changed player rig orientation')
 follower.player_context=function()return nil end;assert(follower.tick(a,camera));assert(lamp.pos[1]==x+10,'Missing player jumped light')
 follower.player_context=function()return{world=main,position=player}end
 assert(follower.release('photo mode exited'));player={21,32,43}
 assert(follower.flush(a,camera));assert(follower.tick(a,camera));lamp=units[next_id]
 assert(lamp.pos[1]==x+20 and lamp.pos[2]==y+30,'Reopening lost the player-relative rig')
 assert(follower.update({follow_player=false}));player={31,42,53};assert(follower.tick(a,moved));assert(lamp.pos[1]==x+20,'Disabled player follow kept moving')
 assert(follower.update({follow_player=true}));assert(follower.update({follow_camera=true})and not follower.selected().follow_player,'Follow modes conflict')
 assert(follower.release('shutdown'))
end
-- The UI's Follow Player switch owns the complete rig, including new lights.
do
 main=a;worlds={a,b};local rig=M.new(sr);local player={0,0,0}
 rig.scene_context=function()return main,1 end;rig.player_context=function()return{world=main,position=player}end
 assert(rig.tick(a,camera)and rig.create({right=-2})and rig.create({right=2})and rig.select(1))
 assert(rig.queue('set_follow_player',true)and rig.flush(a,camera)and rig.follow_player)
 local _,selection=rig.selected();assert(selection==1,'Rig toggle changed selected light')
 assert(rig.create({up=2})and rig.selected().follow_player,'New rig member did not inherit player follow')
 local positions={};for _,marker in ipairs(rig.markers())do positions[marker.id]=marker.position end
 local appearance=#writes;player={5,6,7};assert(rig.tick(a,moved));assert(#writes==appearance+3,'Rig movement reset appearance properties')
 for _,marker in ipairs(rig.markers())do local p=positions[marker.id];assert(marker.position[1]==p[1]+5 and marker.position[2]==p[2]+6 and marker.position[3]==p[3]+7,'A rig member failed to follow')end
 assert(not rig.update({follow_camera=true}),'Camera follow conflicted with the player rig')
 assert(rig.set_follow_player(false)and not rig.follow_player)
 for i=1,3 do assert(rig.select(i)and not rig.selected().follow_player)end
 local intensity=sr.Light.set_intensity;local calls=0
 sr.Light.set_intensity=function(...)calls=calls+1;if calls==2 then error('second member refused')end;return intensity(...)end
 assert(not rig.set_follow_player(true)and not rig.follow_player,'Partial rig toggle reported success')
 sr.Light.set_intensity=intensity
 for i=1,3 do assert(rig.select(i)and not rig.selected().follow_player,'Partial rig toggle was not rolled back')end
 assert(rig.release('shutdown'))
end
print('Photo lights: owned point/spot units, linear color, placement, limits, selection, visibility, follow camera, exact cleanup/retry/retirement and capability gates passed')

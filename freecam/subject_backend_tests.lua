-- Exercise the real renderer backend against a bounded synthetic image. No
-- game process, native getter, or arbitrary memory write is used by this test.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'subject_backend.lua');local core=dofile(root..'subject.lua')
local bytes={};local game,exe=0x10000000,0x20000000;local cursor=0x80000000
local function alloc(n)local at=cursor;cursor=cursor+n+256;cursor=math.ceil(cursor/8)*8;return at end
local function put(at,s)for i=1,#s do bytes[at+i-1]=s:byte(i)end end
local function u32(at,v)local s={};for i=1,4 do s[i]=string.char(v%256);v=math.floor(v/256)end;put(at,table.concat(s))end
local function pointer(at,v)u32(at,v%4294967296);u32(at+4,math.floor(v/4294967296))end
local memory={game=game,exe=exe}
function memory.read(at,n)local s={};for i=0,n-1 do s[#s+1]=string.char(bytes[at+i]or 0)end;return table.concat(s)end
local function word(at)local a,b,c,d=memory.read(at,4):byte(1,4);return a+b*256+c*65536+d*16777216 end
local function ptr(at)return word(at)+word(at+4)*4294967296 end
function memory.function_address()return exe+0x4128e0 end
function memory.handle_ref(handle)return handle.ref end
function memory.world_address(world)return world.native end
for _,image in ipairs({{game,0x6ab3b43f},{exe,0x6ab382e4}})do u32(image[1]+60,128);put(image[1]+128,'PE\0\0');u32(image[1]+136,image[2])end
put(exe+0x4128e0,'\x48\x8b\xd1\xe9\xe8\xfb\xff\xff')
put(exe+0x50f620,'\x40\x57\x48\x83\xec\x30\x44\x0f\xb6\x89\xdc\x00\x00\x00')
put(exe+0x9d8c0,'\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01')
put(exe+0x2beb90,'\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x20\x48\x8d\xb9\xd8\x01\x00\x00')
put(exe+0x2bebf5,'\x48\x8b\x3f\x8b\x13\x48\x81\xc7\xe0\x01\x00\x00')
local function map(owner,off,rows)
 local data=alloc(128);pointer(owner+off,data);u32(owner+off+8,16);u32(owner+off+12,0xffffffff);u32(owner+off+16,1)
 for i=0,15 do u32(data+i*8,0xffffffff)end
 for key,index in pairs(rows)do local slot=key%16;while word(data+slot*8)~=0xffffffff do slot=(slot+1)%16 end;u32(data+slot*8,key);u32(data+slot*8+4,index)end
end
local players,entities,avatars,inventory=alloc(2048),alloc(256),alloc(256),alloc(256)
pointer(game+0x3326468,players);pointer(game+0x346bf98,entities);pointer(game+0x3326d20,avatars);pointer(game+0x3326738,inventory)
local local_record=alloc(32);u32(players+132,1);pointer(players+232,local_record);u32(local_record+20,1);u32(local_record+8,7);map(players,208,{[7]=0});u32(players+936,402)
map(entities,0xf22ec8,{[402]=0});map(entities,0xf1aeb0,{[1001]=1,[1002]=2})
local base=entities+0xf32f18
u32(base,0x294dfa97);u32(base+4,0x4d1c334d);u32(base+8,900);u32(base+12,0x400001);u32(base+16,402);u32(base+20,1)
for i,entity in ipairs({1001,1002})do u32(base+i*24+8,entity);u32(base+i*24+12,0x400002+i);u32(base+i*24+20,1)end
map(avatars,248,{[900]=0});u32(avatars+0x6c,1)
local clothes=avatars+5532272+220;for off=0,116,4 do u32(clothes+off,0xffffffff)end;u32(clothes,0x400002)
map(inventory,40,{[900]=0});local equipment=alloc(48);pointer(inventory+80,equipment);for off=0,44,4 do u32(equipment+off,0xffffffff)end;u32(equipment,1001);u32(equipment+12,1002)
local registry,slots,generations,vtable=alloc(256),alloc(32*8),alloc(32),alloc(1024)
pointer(exe+0x1a100f0,registry);u32(registry+0x98,32);pointer(registry+0x88,slots);pointer(registry+0xa0,generations)
pointer(vtable+0xf8,exe+0x2bd890);pointer(vtable+0xc8,exe+0x2c3990);pointer(vtable+0x1e8,exe+0x2beb90)
local world={native=alloc(256)};local handles={};local writes={}
local function unit(index,masks)
 local native,array=alloc(512),alloc(#masks*16);pointer(native,vtable);u32(native+8,0x400000+index);pointer(native+0x18,world.native);u32(native+0xc8,#masks);pointer(native+0xd0,array)
 local objects={};for i,mask in ipairs(masks)do objects[i]=alloc(256);pointer(array+(i-1)*16,objects[i]);put(objects[i]+0xdc,string.char(mask))end
 put(generations+index,'\1');pointer(slots+index*8,native)
 local handle={ref=0x400000+index,native=native};handles[#handles+1]=handle;return handle,objects
end
local hero,hero_objects=unit(1,{255});local armour,armour_objects=unit(2,{255,0});local weapon,weapon_objects=unit(3,{255});local pack,pack_objects=unit(4,{255});local foreign,foreign_objects=unit(5,{255})
local component,component_objects=unit(6,{255});local nested,nested_objects=unit(7,{255,0})
pointer(hero.native+0x1d8,weapon.native);pointer(weapon.native+0x1d0,hero.native);pointer(weapon.native+0x1e0,pack.native)
pointer(pack.native+0x1d0,hero.native);pointer(pack.native+0x1e0,armour.native);pointer(armour.native+0x1d0,hero.native)
pointer(weapon.native+0x1d8,component.native);pointer(component.native+0x1d0,weapon.native)
pointer(component.native+0x1d8,nested.native);pointer(nested.native+0x1d0,component.native)
local sr={Application={main_world=function()return world end},World={units=function()return handles end},Unit={}}
function sr.Unit.set_mesh_visibility(handle,index,visible)
 assert(ptr(slots+(handle.ref%4194304)*8)==handle.native,'Fixture received stale native handle')
 local object=ptr(ptr(handle.native+0xd0)+(index-1)*16);writes[#writes+1]={ref=handle.ref,index=index,visible=visible};put(object+0xdc,visible and'\255'or'\0')
end
local backend=factory.new(sr,memory);local context=backend.resolve()
assert(#context.groups.hide_player==6 and#context.groups.hide_armour==1 and#context.groups.hide_weapons==3,'Exact local backpack/weapon/armour/attachment groups are incomplete')
for _,part in ipairs(context.groups.hide_player)do assert(part.ref~=foreign.ref,'Unrelated scene Unit entered player group')end
local subject=core.new(backend);assert(subject.apply({hide_player=true})and subject.count()==6)
assert(not pcall(core.new,backend,nil,subject),'Occupied hotrefresh abandoned hidden renderer rows')
assert(word(foreign_objects[1]+0xdc)%256==255 and word(armour_objects[2]+0xdc)%256==0,'Foreign or pre-hidden mesh changed')
-- Barrel/magazine replacement can grow/reorder meshes without changing roots.
local barrel,new_array=alloc(256),alloc(32);put(barrel+0xdc,'\255');pointer(new_array,barrel);pointer(new_array+16,weapon_objects[1]);u32(weapon.native+0xc8,2);pointer(weapon.native+0xd0,new_array)
context=backend.resolve();local weapon_part
for _,part in ipairs(context.groups.hide_weapons)do if part.ref==weapon.ref then weapon_part=part end end
assert(weapon_part.mesh_count==2 and weapon_part.mesh_objects[1]==barrel,'Unchanged root refs reused cached mesh descriptors')
assert(subject.apply({hide_player=true})and subject.count()==7,'New barrel mesh was not hidden')
assert(subject.release()and word(barrel+0xdc)%256==255 and word(weapon_objects[1]+0xdc)%256==255,'Reordered original mesh or new attachment was not restored')
assert(word(armour_objects[2]+0xdc)%256==0,'Pre-hidden armour became visible on release')
assert(word(component_objects[1]+0xdc)%256==255 and word(nested_objects[1]+0xdc)%256==255 and word(nested_objects[2]+0xdc)%256==0,'Nested equipment original visibility was not restored')
local same=subject;subject=core.new(backend,nil,subject);assert(subject==same,'Idle hotrefresh changed the controller shared subject table')
assert(subject.apply({hide_weapons=true}));assert(word(hero_objects[1]+0xdc)%256==255 and word(pack_objects[1]+0xdc)%256==255 and word(component_objects[1]+0xdc)%256==0,'Weapon-only group hid the player/backpack or omitted attachments')
pointer(weapon.native+0x1d8,0);pointer(component.native+0x1d0,0)
assert(subject.apply({hide_weapons=true})and word(component_objects[1]+0xdc)%256==255 and word(nested_objects[1]+0xdc)%256==255,'Detached equipment lost original visibility or stayed in weapon group')
assert(subject.release());pointer(weapon.native+0x1d8,component.native);pointer(component.native+0x1d0,weapon.native)
assert(subject.apply({hide_weapons=true}));local normal_read=memory.read;local unavailable=true
memory.read=function(at,n)if unavailable and at==weapon.native+0x18 then error('Subject read unavailable')end;return normal_read(at,n)end
assert(backend.valid(weapon_part)==nil and not subject.release()and subject.count()==2,'Transient owner read failure discarded hidden restoration ownership')
unavailable=false;assert(subject.release()and subject.count()==0 and word(weapon_objects[1]+0xdc)%256==255);memory.read=normal_read
pointer(component.native+0x1d0,hero.native);local before_bad=#writes;assert(not pcall(backend.resolve)and#writes==before_bad,'Unproven parent backpointer caused a visibility setter');pointer(component.native+0x1d0,weapon.native)
pointer(component.native+0x1e0,component.native);assert(not pcall(backend.resolve),'Sibling cycle was accepted');pointer(component.native+0x1e0,0)
-- Retired generation must not emit a setter, even if old native data remains.
assert(subject.apply({hide_player=true}));local before=#writes;put(generations+3,'\2')
assert(not backend.valid(weapon_part)and subject.release());for i=before+1,#writes do assert(writes[i].ref~=weapon.ref,'Recycled weapon Unit was restored through an old handle')end
assert(not pcall(backend.resolve),'Retired equipment reference was accepted')
put(generations+3,'\1');put(weapon_objects[1]+0xdc,'\255');put(barrel+0xdc,'\255')
local wrong=world.native+4096;pointer(pack.native+0x18,wrong);assert(not pcall(backend.resolve),'Foreign-world equipment was accepted');pointer(pack.native+0x18,world.native)
-- Fixed poses acquire their bone component lazily. Existing visibility setup
-- above intentionally had no bone APIs; that must remain a valid backend.
local transform_reads=0
sr.Unit.world_pose=function(handle,index)assert(handle==hero and index==1);transform_reads=transform_reads+1;return{}end
sr.Unit.animation_bone_mode=function()error('Ownership reader must not dereference the native bone getter')end
sr.Unit.set_animation_bone_mode=function()error('Ownership reader must not invoke a bone setter')end
sr.Matrix4x4={translation=function()return{2,3,4}end,forward=function()return{0,1,0}end}
sr.Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end}
local visibility_address=memory.function_address
memory.function_address=function(fn)
 if fn==sr.Unit.animation_bone_mode then return exe+0x410470 end
 if fn==sr.Unit.set_animation_bone_mode then return exe+0x410700 end
 return visibility_address(fn)
end
pointer(vtable+0x1a8,exe+0x2bd9a0);put(exe+0x2bd9a0,'\x48\x8b\x81\x68\x01\x00\x00\xc3')
local bone_component=alloc(0x300);pointer(hero.native+0x168,bone_component);u32(bone_component+0x284,3)
local pose_frame=backend.pose_frame();local before_pose_writes=#writes
assert(pose_frame.root_handle==hero and pose_frame.root_ref==hero.ref and pose_frame.native==hero.native and pose_frame.component==bone_component and pose_frame.local_owner)
assert(pose_frame.world_native==world.native and pose_frame.position[1]==2 and backend.pose_valid(pose_frame,true)==true)
local normal_world_pose=sr.Unit.world_pose
sr.Unit.world_pose=function(handle,index)local value=normal_world_pose(handle,index);u32(base+8,901);return value end
local stable_frame=pcall(backend.pose_frame);sr.Unit.world_pose=normal_world_pose;u32(base+8,900)
assert(not stable_frame,'Pose frame combined an old root identity with replacement owner key')
-- Losing local ownership still permits restoring the same intact borrowed
-- Unit, but cannot permit a new application on behalf of its replacement.
u32(base+8,901);assert(backend.pose_valid(pose_frame,true)==false and backend.pose_valid(pose_frame,false)==true);u32(base+8,900)
pointer(hero.native+0x168,0)
assert(backend.pose_valid(pose_frame,false)==false and not pcall(backend.pose_frame),'Null bone component reached public getter')
pointer(hero.native+0x168,alloc(0x300));assert(backend.pose_valid(pose_frame,false)==false,'Replacement bone component reused prior lease')
pointer(hero.native+0x168,bone_component)
u32(bone_component+0x284,8);assert(backend.pose_valid(pose_frame,false)==nil and not pcall(backend.pose_frame),'Unknown bone mode accepted');u32(bone_component+0x284,3)
local pose_read=memory.read
memory.read=function(at,n)if at==hero.native+0x168 then error('Transient pose component read failed')end;return pose_read(at,n)end
local valid,why=backend.pose_valid(pose_frame,false)
assert(valid==nil and why:find('Transient pose component',1,true),'Unknown component read was treated as retirement');memory.read=pose_read
assert(backend.pose_valid(pose_frame,true)==true,'Read recovery did not retain original component identity')
local reads_before=transform_reads;put(generations+1,'\2')
assert(backend.pose_valid(pose_frame,false)==false and not pcall(backend.pose_frame)and transform_reads==reads_before,'Retired root reached transform getter')
put(generations+1,'\1')
pointer(hero.native+0x18,world.native+4096);assert(backend.pose_valid(pose_frame,false)==false);pointer(hero.native+0x18,world.native)
local replacement=alloc(512);pointer(replacement,vtable);u32(replacement+8,hero.ref);pointer(replacement+0x18,world.native);pointer(slots+8,replacement)
assert(backend.pose_valid(pose_frame,false)==false,'Replaced root native object reused prior lease');pointer(slots+8,hero.native)
pointer(vtable+0x1a8,exe+0x2bd9a1);assert(backend.pose_valid(pose_frame,false)==nil and not pcall(backend.pose_frame),'Changed bone getter layout accepted');pointer(vtable+0x1a8,exe+0x2bd9a0)
local pose_address=memory.function_address;memory.function_address=function(fn)if fn==sr.Unit.animation_bone_mode then return exe+0x410471 end;return pose_address(fn)end
assert(not pcall(backend.pose_frame),'Changed public bone-mode binding accepted');memory.function_address=pose_address
assert(backend.pose_valid(pose_frame,true)==true and#writes==before_pose_writes,'Read-only fixed-pose ownership check mutated renderer')
put(exe+0x4128e0,'\0');assert(not pcall(factory.new,sr,memory),'Changed renderer binding passed exact build validation')
print('Subject renderer backend: visibility restoration plus lazy fixed-pose root/component ownership, null/layout/mode guards, transient read retry, foreign world and recycled generations passed')

-- TwoPointChain feed links are separate render Units, not Unit children. Only
-- a verified row between two current local carried entities grants membership.
put(exe+0x4128e0,'\x48\x8b\xd1\xe9\xe8\xfb\xff\xff')
put(game+0x8c75fa,'\x48\x8b\x1d\x87\xf5\xa5\x02')
put(game+0x8c7623,'\x44\x8b\x43\x0c\x0f\x57\xc0\x33\xc9\x49\x69\xc0\x9c\x00\x00\x00\x48\x03\x43\x38')
put(game+0x8c7676,'\x48\x8b\x43\x30\x0f\x47\x4b\x04\x89\x4b\x04\x48\x8d\x4b\x18\x4a\x89\x3c\xc0\x8b\x57\x08')
put(game+0x8c6eb9,'\x44\x8b\x49\x20\x44\x8b\x51\x28\x44\x0f\xaf\xd2\x41\x8d\x79\xff\x45\x85\xc9\x74\x33\x4c\x8b\x59\x18')
put(game+0x8c567f,'\x41\x89\x5f\x04')
local feed,feed_objects=unit(8,{255,0,255})
assert(ptr(feed.native+0x1d0)==0 and ptr(feed.native+0x1d8)==0,'Chain fixture accidentally joined the child graph')
local chain_manager,chain_descriptors,chain_rows,chain_descriptor=alloc(256),alloc(32),alloc(4*0x9c),alloc(32)
pointer(game+0x3326b88,chain_manager);u32(chain_manager,4);u32(chain_manager+8,1)
pointer(chain_manager+0x30,chain_descriptors);pointer(chain_manager+0x38,chain_rows)
local function configure_chain(index,descriptor)
 index=index or 0;descriptor=descriptor or chain_descriptor
 u32(chain_manager,4);u32(chain_manager+8,index+1);map(chain_manager,0x18,{[1002]=index})
 pointer(chain_descriptors+index*8,descriptor);u32(descriptor+8,1002);u32(descriptor+12,pack.ref);put(descriptor+0x14,'\1')
 u32(chain_rows+index*0x9c,feed.ref);u32(chain_rows+index*0x9c+4,1001)
end
local function feed_part(group)
 for _,part in ipairs(backend.resolve().groups[group or'hide_weapons'])do if part.ref==feed.ref then return part end end
end
local function mask(object)return memory.read(object+0xdc,1):byte()end
local function restore_feed_fixture()
 put(feed_objects[1]+0xdc,'\255');put(feed_objects[2]+0xdc,'\0');put(feed_objects[3]+0xdc,'\255')
end
local function refused_hide(part,message)
 local n=#writes
 assert(not backend.owned(part),message..': stale membership still reports owned')
 assert(not pcall(backend.write,part,1,false)and#writes==n,message..': stale membership reached a native visibility setter')
end
configure_chain()
local feed_row=assert(feed_part());assert(feed_row.chain_link and feed_row.chain_link.descriptor==chain_descriptor and feed_row.chain_link.owner_entity==1002 and feed_row.chain_link.target_entity==1001)
assert(feed_part('hide_player')and not feed_part('hide_armour')and backend.owned(feed_row),'Verified feed link did not join player/weapon groups only')
local chains=core.new(backend)
assert(chains.apply({hide_weapons=true})and mask(feed_objects[1])==0 and mask(feed_objects[2])==0 and mask(feed_objects[3])==0,'Weapon hiding omitted independently rendered feed meshes')
assert(chains.release()and mask(feed_objects[1])==255 and mask(feed_objects[2])==0 and mask(feed_objects[3])==255,'Feed release changed the originally hidden mesh or failed to restore visible meshes')
assert(chains.apply({hide_player=true})and mask(feed_objects[1])==0 and mask(feed_objects[3])==0)
assert(chains.release()and mask(feed_objects[2])==0)

-- Follow a manager compaction through its current owner map; do not read the
-- old numeric row index once the same descriptor and link move to another row.
assert(chains.apply({hide_weapons=true}));feed_row=assert(feed_part())
configure_chain(1);u32(chain_rows,foreign.ref);u32(chain_rows+4,1900)
assert(backend.owned(feed_row),'Manager row compaction retired a still-owned stable descriptor/link')
local moved=assert(feed_part());assert(moved.chain_link.index==1 and chains.apply({hide_weapons=true}))
assert(mask(feed_objects[1])==0 and chains.release()and mask(feed_objects[1])==255,'Compaction lost the original feed visibility restoration lease')

-- Reassigned equipment relationships cannot authorize a new hide. Dropping a
-- link's membership still restores its own live generation's original masks.
configure_chain();feed_row=assert(feed_part());assert(chains.apply({hide_weapons=true}))
u32(chain_rows+4,1900);refused_hide(feed_row,'Foreign chain endpoint')
assert(not feed_part()and chains.apply({hide_weapons=true})and mask(feed_objects[1])==255 and mask(feed_objects[3])==255,'Removed endpoint retained stale membership or lost same-Unit restoration')
assert(chains.release());configure_chain()
local function mutate_refuse(change,undo,message)
 local part=assert(feed_part());change();refused_hide(part,message);undo()
 assert(backend.owned(assert(feed_part())),message..': fixture did not recover')
end
mutate_refuse(function()map(chain_manager,0x18,{[1900]=0})end,function()configure_chain()end,'Foreign chain owner map')
mutate_refuse(function()u32(chain_descriptor+8,1900)end,function()u32(chain_descriptor+8,1002)end,'Reassigned descriptor owner')
mutate_refuse(function()u32(chain_descriptor+12,foreign.ref)end,function()u32(chain_descriptor+12,pack.ref)end,'Reassigned descriptor owner Unit')
mutate_refuse(function()put(chain_descriptor+0x14,'\0')end,function()put(chain_descriptor+0x14,'\1')end,'Retired chain descriptor')
local replacement_descriptor=alloc(32)
mutate_refuse(function()
 u32(replacement_descriptor+8,1002);u32(replacement_descriptor+12,pack.ref);put(replacement_descriptor+0x14,'\1');pointer(chain_descriptors,replacement_descriptor)
end,function()pointer(chain_descriptors,chain_descriptor)end,'Replaced chain descriptor')
mutate_refuse(function()u32(chain_rows,foreign.ref)end,function()u32(chain_rows,feed.ref)end,'Reassigned chain render Unit')
mutate_refuse(function()u32(equipment+12,0xffffffff)end,function()u32(equipment+12,1002)end,'Dropped source equipment')
mutate_refuse(function()u32(equipment,0xffffffff)end,function()u32(equipment,1001)end,'Dropped target weapon')
mutate_refuse(function()u32(base+24+12,foreign.ref)end,function()u32(base+24+12,weapon.ref)end,'Reassigned target entity Unit')
mutate_refuse(function()put(generations+4,'\2')end,function()put(generations+4,'\1')end,'Retired source equipment generation')
mutate_refuse(function()pointer(pack.native+0x18,world.native+4096)end,function()pointer(pack.native+0x18,world.native)end,'Foreign source equipment world')
mutate_refuse(function()pointer(weapon.native+0x18,world.native+4096)end,function()pointer(weapon.native+0x18,world.native)end,'Foreign target weapon world')

-- The renderer always receives a handle actually returned by World.units.
local actual_feed_handle=table.remove(handles,#handles);assert(actual_feed_handle==feed)
local count_before=#writes;assert(not pcall(backend.resolve)and#writes==count_before,'Missing World.units feed handle was fabricated')
handles[#handles+1]=actual_feed_handle
local actual_weapon_handle=table.remove(handles,3);assert(actual_weapon_handle==weapon)
assert(not pcall(backend.resolve)and#writes==count_before,'Missing World.units endpoint handle was fabricated')
table.insert(handles,3,actual_weapon_handle)

-- Retired/recycled link Units must never receive an old visibility restore.
local function retired_restore(change,undo,message)
 assert(chains.apply({hide_weapons=true}));local part=assert(feed_part());local first=#writes
 change();assert(backend.valid(part,1)==false and chains.release(),message..': retirement was not recognized')
 for i=first+1,#writes do assert(writes[i].ref~=feed.ref,message..': old link handle received a restore setter')end
 undo();restore_feed_fixture()
end
retired_restore(function()put(generations+8,'\2')end,function()put(generations+8,'\1')end,'Recycled chain generation')
retired_restore(function()pointer(feed.native+0x18,world.native+4096)end,function()pointer(feed.native+0x18,world.native)end,'Retired chain world')
local replacement_feed=alloc(512);pointer(replacement_feed,vtable);u32(replacement_feed+8,feed.ref);pointer(replacement_feed+0x18,world.native)
retired_restore(function()pointer(slots+8*8,replacement_feed)end,function()pointer(slots+8*8,feed.native)end,'Replaced chain native Unit')

-- Unsupported active chain layouts fail closed; a null optional manager keeps
-- ordinary player/weapon visibility available on builds/scenes without chains.
count_before=#writes;u32(chain_manager,385);assert(not pcall(backend.resolve)and#writes==count_before);u32(chain_manager,4)
put(game+0x8c567f,'\0');assert(not pcall(backend.resolve)and#writes==count_before,'Changed chain row semantics passed fingerprint validation');put(game+0x8c567f,'\x41\x89\x5f\x04')
pointer(game+0x3326b88,0);put(game+0x8c567f,'\0')
assert(not feed_part()and backend.resolve().local_owner,'Absent optional chain manager disabled normal subject controls')
put(game+0x8c567f,'\x41\x89\x5f\x04')
print('Subject TwoPointChain backend: independent feed meshes, local equipment proof, manager compaction, relationship replacement, actual Unit handles, retired generations/worlds, original-mask restoration and exact layout guards passed')

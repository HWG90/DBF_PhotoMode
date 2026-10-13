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
put(exe+0x4128e0,'\0');assert(not pcall(factory.new,sr,memory),'Changed renderer binding passed exact build validation')
print('Subject renderer backend: local inventory/backpack ownership, fresh descriptors, mesh-object replacement/reordering, exact visibility restore, foreign world and recycled generations passed')

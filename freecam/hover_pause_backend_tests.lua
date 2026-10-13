local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'hover_pause_backend.lua');local ffi=require('ffi');local L=M.layout
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function f32(v)local b=ffi.new('float[1]',v);return ffi.string(b,4)end
local function unhex(s)return(s:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))end
local function fixture()
 local f={bytes={},writes={},reads=0,next=0x60000000,scene=0x50000000,peers={},pad=true}
 local function put(at,s)for i=1,#s do f.bytes[at+i-1]=s:byte(i)end end
 local function alloc(size,align)local at=f.next;f.next=f.next+(size or 4096);if align then at=at+align end;return at end
 local function u32(at,v)put(at,le(v,4))end;local function ptr(at,v)put(at,le(v,8))end
 local memory={game=0x10000000,exe=0x20000000}
 function memory.read(at,size)
  f.reads=f.reads+1;if f.fail_read and f.fail_read(at,size)then error('Injected unreadable field')end
  local out={};for i=0,size-1 do local b=f.bytes[at+i];if b==nil then error('Fixture read unmapped '..at..'+'..i)end;out[#out+1]=string.char(b)end;return table.concat(out)
 end
 function memory.write(at,s)assert(#s==4,'Only float field writes allowed');if f.fail_write then error('Injected write refusal')end;f.writes[#f.writes+1]={at=at,bytes=s};put(at,s);return true end
 function memory.scene()return f.scene end;function memory.pad_absent()return f.pad,f.pad_reason end
 local function image(base,stamp,size)put(base,'MZ');u32(base+60,0x80);put(base+0x80,'PE\0\0\x64\x86');u32(base+0x88,stamp);put(base+0x98,'\x0b\x02');u32(base+0xd0,size or 0x4000000)end
 image(memory.game,L.game_stamp,L.game_size);image(memory.exe,L.exe_stamp)
 for _,fp in ipairs(M.fingerprints)do put(memory.game+fp[1],unhex(fp[2]))end
 put(memory.exe+0x9d8c0,'\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01')
 local maps={}
 local function newmap(header,cap)
  local data=alloc(4096,4);put(header,le(data,8)..le(cap,4)..le(4294967295,4)..le(1,4)..le(0,4))
  for i=0,cap-1 do put(data+i*8,le(4294967295,4)..le(4294967295,4))end
  maps[header]={data=data,cap=cap};return maps[header]
 end
 local function bucket(m,key)
  for i=0,m.cap-1 do local at=m.data+((key+i)%m.cap)*8;local raw=memory.read(at,4);local found=raw:byte(1)+raw:byte(2)*256+raw:byte(3)*65536+raw:byte(4)*16777216;if found==key or found==4294967295 then return at end end;error('Fixture map full')
 end
 local function insert(header,key,index)local m=maps[header];put(bucket(m,key),le(key,4)..le(index,4))end
 local function remove(header,key)local m=maps[header];put(bucket(m,key),le(4294967295,4)..le(4294967295,4))end
 f.world=alloc();f.players=alloc();f.inventory=alloc();f.avatars=alloc(0x180000);f.manager=alloc();f.registry=alloc();f.scene=alloc()
 ptr(memory.game+L.WORLD,f.world);ptr(memory.game+L.PLAYER,f.players);ptr(memory.game+L.INVENTORY,f.inventory);ptr(memory.game+L.AVATAR,f.avatars);ptr(memory.game+L.JUMP,f.manager);ptr(memory.exe+L.REGISTRY,f.registry)
 f.unit_list=alloc();f.generations=alloc(4096,1);u32(f.registry+0x98,16);ptr(f.registry+0x88,f.unit_list);ptr(f.registry+0xa0,f.generations)
 newmap(f.world+L.WORLD_UNITS,16);newmap(f.world+L.WORLD_ENTITIES,16);newmap(f.players+208,8);newmap(f.inventory+40,16);newmap(f.avatars+0xf8,16);newmap(f.manager+0x60,64)
 local local_record=alloc();u32(f.players+132,1);ptr(f.players+232,local_record);u32(local_record+20,1);u32(local_record+8,10);insert(f.players+208,10,0)
 f.inventory_rows=alloc(4096,4);ptr(f.inventory+80,f.inventory_rows);insert(f.inventory+40,100,0)
 f.descriptors=alloc();f.controls=alloc(4096,4);f.flags=alloc(4096,1);f.definitions=alloc(4096,4)
 ptr(f.manager+0x38,f.descriptors);ptr(f.manager+0x40,f.controls);ptr(f.manager+0x50,f.flags);ptr(f.manager+0xa0,f.definitions);u32(f.manager,64);u32(f.manager+0xc,1);u32(f.manager+0x98,2)
 local function entity(e,index,unit_index,typebytes,game_ref)
  local ref=4194304+unit_index;local object=alloc();local vt=alloc();local raw=typebytes..le(e,4)..le(ref,4)..le(game_ref or 77,4)..le(1,4)
  put(f.world+L.WORLD_RECORDS+index*24,raw);insert(f.world+L.WORLD_ENTITIES,e,index);insert(f.world+L.WORLD_UNITS,ref,index)
  ptr(f.unit_list+unit_index*8,object);put(f.generations+unit_index,'\1');ptr(object,vt);ptr(vt+0xf8,memory.exe+0x2bd890);ptr(vt+0xc8,memory.exe+0x2c3990);ptr(object+0x18,f.scene)
  return ref,raw,object
 end
 local hero_type=le(0x294dfa97,4)..le(0x4d1c334d,4);local pack_type='\xcf\x66\xdb\x1c\x4f\x0f\xc8\x5e'
 local hero=entity(100,0,1,hero_type,402);u32(f.players+936,402);insert(f.world+L.WORLD_UNITS,402,0);insert(f.avatars+0xf8,100,0)
 f.pack_ref,f.pack_raw,f.pack_native=entity(200,1,2,pack_type);u32(f.inventory_rows+12,200)
 f.pack_descriptor=alloc();put(f.pack_descriptor,f.pack_raw:sub(1,16)..le(999,4)..le(1,4));ptr(f.descriptors,f.pack_descriptor)
 insert(f.manager+0x60,200,0);put(f.definitions,'immutable-header');put(f.definitions+0x99,'\1\1');put(f.definitions+0x9c,f32(6));put(f.controls,f32(0)..f32(0)..f32(0));put(f.flags,'\1\0\1\0\0')
 put(f.avatars+0x1ea0,f32(0));put(f.avatars+0xa7c18,f32(0)..f32(0))
 local sr={Application={main_world=function()return{}end},Network={game_session=function()return nil end,connections=function()return f.peers end},GameSession={}}
 for i=1,4 do sr['Pad'..i]={active=function()return false end}end
 function f.respawn()
  local ref=entity(101,2,3,hero_type,403);u32(f.players+936,403);insert(f.world+L.WORLD_UNITS,403,2);insert(f.avatars+0xf8,101,1);insert(f.inventory+40,101,1);u32(f.inventory_rows+48+12,0)
  put(f.avatars+0xa7aec+0x1ea0,f32(0));put(f.avatars+0xa7aec+0xa7c18,f32(0)..f32(0))
 end
 function f.repack()
  -- The same owned definition and runtime row move; restore must reacquire them.
  u32(f.manager+0xc,2);ptr(f.descriptors+8,f.pack_descriptor);local other=alloc();put(other,pack_type..le(201,4)..le(4194308,4)..le(0,4)..le(1,4));ptr(f.descriptors,other)
  put(f.controls+12,memory.read(f.controls,12));put(f.flags+5,memory.read(f.flags,5));put(f.definitions+0x118,memory.read(f.definitions,16));put(f.definitions+0x118+0x99,memory.read(f.definitions+0x99,2));put(f.definitions+0x118+0x9c,memory.read(f.definitions+0x9c,4));insert(f.manager+0x60,200,1)
 end
 f.put=put;f.u32=u32;f.remove=remove;f.maps=maps;f.memory=memory;f.sr=sr
 return f,M.new(sr,memory)
end
do
 local f,b=fixture();local s=assert(b.snapshot());assert(s.avatar_ref==4194305 and s.active and s.hover and s.value==6 and s.action==0 and s.control.x==0 and s.epoch==0 and s.dt==0)
 assert(b.input_supported());assert(b.set(s,0));assert(#f.writes==1 and f.writes[1].at==f.definitions+0x9c and f.writes[1].bytes==f32(0))
 local zero=assert(b.snapshot(s));assert(zero.identity==s.identity and zero.generation==s.generation and zero.value==0)
 b.after_update(.016);zero=assert(b.snapshot(s));assert(zero.epoch==1 and zero.dt==.016);assert(b.restore(zero,6));assert(assert(b.snapshot()).value==6)
end
-- Respawn and unequip keep old pack lifetime valid; only its own four bytes restore.
do
 local f,b=fixture();local original=assert(b.snapshot());b.set(original,0);f.respawn();local old=assert(b.snapshot(original));assert(old.entity==200 and old.value==0 and not old.equipped and old.identity==original.identity)
 assert(not b.set(old,0),'A detached old pack cannot acquire a new override');assert(b.restore(old,original.value));assert(f.memory.read(f.definitions+0x9c,4)==f32(6))
 local current=assert(b.snapshot());assert(current.absent and not current.active and not current.hover)
end
do
 local f,b=fixture();local original=assert(b.snapshot());b.set(original,0);f.repack();local moved=assert(b.snapshot(original));assert(moved.field_address==f.definitions+0x118+0x9c and moved.generation==original.generation);assert(b.restore(moved,6));assert(f.writes[#f.writes].at==moved.field_address)
end
-- External writers, recycled Unit generation, missing records and unreadable
-- maps never permit a stale write or silently manufacture an absent backpack.
do
 local f,b=fixture();local original=assert(b.snapshot());b.set(original,0);local zero=assert(b.snapshot(original));f.put(zero.field_address,f32(2));assert(not b.restore(zero,6)and#f.writes==1)
 local f2,b2=fixture();local s=assert(b2.snapshot());f2.put(f2.generations+2,'\2');assert(b2.snapshot(s).expired and not b2.set(s,0)and#f2.writes==0)
 local f3,b3=fixture();local s3=assert(b3.snapshot());f3.remove(f3.world+L.WORLD_ENTITIES,200);assert(b3.snapshot(s3).expired and b3.snapshot()==nil)
 local f4,b4=fixture();f4.remove(f4.inventory+40,100);assert(b4.snapshot()==nil,'Missing inventory is unavailable, not absent')
 local f5,b5=fixture();local s5=assert(b5.snapshot());f5.fail_read=function(at)return at==f5.definitions+0x9c end;assert(b5.snapshot(s5)==nil and not b5.set(s5,0)and#f5.writes==0)
 local f6,b6=fixture();local s6=assert(b6.snapshot());f6.fail_write=true;assert(not b6.set(s6,0)and#f6.writes==0)
end
do
 local f,b=fixture();local s=assert(b.snapshot());f.put(f.definitions,'changed!-header!');assert(b.snapshot(s)==nil and not b.set(s,0))
 local f2,b2=fixture();f2.peers={other=true};assert(b2.snapshot()==nil and#f2.writes==0)
 local f3,b3=fixture();f3.u32(f3.manager+0xc,100000);assert(b3.snapshot()==nil and#f3.writes==0)
 local f4,b4=fixture();f4.put(f4.controls,f32(0/0));assert(b4.snapshot()==nil)
end
-- Equipment construction can temporarily have no owned definition. This is
-- unavailable (not an absent pack or fallback); retry only after it is indexed.
do
 local f,b=fixture();local before=assert(b.snapshot());f.u32(f.manager+0x98,0)
 assert(b.snapshot()==nil and b.snapshot(before)==nil and not b.set(before,0)and#f.writes==0)
 f.u32(f.manager+0x98,1);local fresh=assert(b.snapshot());assert(fresh.identity==before.identity and fresh.value==6 and b.set(fresh,0))
end
-- Constructor refuses the build/code contract before any data writes.
for _,change in ipairs({'stamp','size','gate','registry'})do
 local f=fixture();if change=='stamp'then f.u32(f.memory.game+0x88,0)elseif change=='size'then f.u32(f.memory.game+0xd0,0)elseif change=='gate'then f.put(f.memory.game+0x9b4e07,'\0')else f.put(f.memory.exe+0x9d8c0,'\0')end
 assert(not pcall(M.new,f.sr,f.memory)and#f.writes==0)
end
do
 local f,b=fixture();f.pad=false;assert(not b.input_supported());f.pad=nil;assert(not b.input_supported());f.pad=true;f.sr.Pad1.active=function()return true end;assert(not b.input_supported());f.sr.Pad1=nil;assert(not b.input_supported())
end
print('Hover data backend: exact build/gates, four-byte ownership, local/old pack, respawn/repacking restore, foreign writes, retirement, unreadable/absent distinction and controller fail-close passed')

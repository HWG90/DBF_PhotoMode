-- Current-process data-only hover control. No game-function call, hook, DLL,
-- executable write, lifecycle/event invocation, or shared definition fallback.
-- Local avatar/inventory layout follows the existing subject identity adapter
-- and Link's MIT address reference (vendor/LICENSE-Link.txt).
local M={}
M.layout={game_stamp=0x6ab3b43f,game_size=0x4744000,exe_stamp=0x6ab382e4,
 WORLD=0x346bf98,PLAYER=0x3326468,INVENTORY=0x3326738,AVATAR=0x3326d20,JUMP=0x3326bb8,
 WORLD_UNITS=0xf22ec8,WORLD_ENTITIES=0xf1aeb0,WORLD_RECORDS=0xf32f18,REGISTRY=0x1a100f0}
M.fingerprints={{0x9b4790,'48895c24185556574154415541564157'},
 {0x9b4cb2,'f3410f1084249c000000'},
 {0x9b4e07,'0f2e3d9234de027a1575130f2ef27a0e750c440f2ee37a060f8474040000'},
 {0x9b50fa,'f3450f5eee'},{0x9b5127,'f3410f5efef3410f5ef6'},
 {0x585b80,'83f90c771d4c8d0574a4a7ff8bc1418b9480a85b58004903d0ffe248c1e9208bc1c3b8ffffffffc3'},
 {0x585bb0,'9b5b5800'}}
local ffi=require('ffi');local bit=require('bit')
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function word(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Hover data truncated');return a+b*256+c*65536+d*16777216 end
local function address(s,o)return word(s,o)+word(s,o+4)*4294967296 end
local function decode(s)local f=ffi.new('float[1]');ffi.copy(f,s,4);local v=tonumber(f[0]);assert(finite(v)and math.abs(v)<=1e6,'Hover float invalid');return v end
local function encode(v)assert(finite(v)and math.abs(v)<=1e6,'Hover write value invalid');local f=ffi.new('float[1]',v);return ffi.string(f,4)end
local function unhex(s)return(s:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))end
local function native_memory()
 pcall(ffi.cdef,[[void* HPB_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void* HPB_GetCurrentProcess(void) __asm__("GetCurrentProcess");
 int HPB_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");int HPB_WriteProcessMemory(void*,void*,const void*,size_t,size_t*) __asm__("WriteProcessMemory");]])
 local K=ffi.load('kernel32');local process=K.HPB_GetCurrentProcess();local buffer=ffi.new('uint8_t[512]');local got=ffi.new('size_t[1]')
 local memory={game=tonumber(ffi.cast('uintptr_t',K.HPB_GetModuleHandleA('game.dll'))),exe=tonumber(ffi.cast('uintptr_t',K.HPB_GetModuleHandleA(nil)))}
 function memory.read(at,size)assert(K.HPB_ReadProcessMemory(process,ffi.cast('void*',at),buffer,size,got)~=0 and tonumber(got[0])==size,'Hover memory read unavailable');return ffi.string(buffer,size)end
 function memory.write(at,bytes)local done=ffi.new('size_t[1]');assert(K.HPB_WriteProcessMemory(process,ffi.cast('void*',at),bytes,#bytes,done)~=0 and tonumber(done[0])==#bytes,'Hover data write unavailable');return true end
 function memory.scene(world)return address(memory.read(tonumber(ffi.cast('uintptr_t',world)),8),0)end
 local ok,xinput=pcall(ffi.load,'xinput1_4');if not ok then ok,xinput=pcall(ffi.load,'xinput9_1_0')end
 if ok then
  pcall(ffi.cdef,[[unsigned long HPB_XInputGetState(unsigned long,void*) __asm__("XInputGetState");]])
  local state=ffi.new('uint8_t[16]')
  function memory.pad_absent()for i=0,3 do local code=tonumber(xinput.HPB_XInputGetState(i,state));if code==0 then return false,'XInput controller present'elseif code~=1167 then return nil,'XInput presence unavailable'end end;return true end
 end
 return memory
end
function M.new(sr,memory,completed_update)
 memory=memory or native_memory();local L=M.layout;local epoch,delta=0,0;local self={}
 local function read(at,size)
  assert(type(at)=='number'and at>=65536 and at<2^47 and size>0 and size<=512,'Hover read bounds invalid')
  local s=memory.read(at,size);assert(type(s)=='string'and#s==size,'Hover read incomplete');return s
 end
 local function u32(at)return word(read(at,4),0)end
 local function ptr(at,alignment)local p=address(read(at,8),0);assert(p==0 or(p>=65536 and p<2^47 and p%(alignment or 8)==0),'Hover pointer invalid');return p~=0 and p or nil end
 local function image(base,stamp,size)
  assert(read(base,2)=='MZ','Hover module unavailable');local pe=u32(base+60);assert(pe>=64 and pe<1048576,'Hover PE bounds invalid')
  assert(read(base+pe,4)=='PE\0\0'and read(base+pe+4,2)=='\x64\x86'and read(base+pe+24,2)=='\x0b\x02'and u32(base+pe+8)==stamp,'Hover build unsupported')
  assert(not size or u32(base+pe+80)==size,'Hover game image changed')
 end
 image(memory.game,L.game_stamp,L.game_size);image(memory.exe,L.exe_stamp)
 for _,fp in ipairs(M.fingerprints)do assert(read(memory.game+fp[1],#fp[2]/2)==unhex(fp[2]),'Hover control fingerprint changed')end
 assert(read(memory.exe+0x9d8c0,22)=='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01','Hover Unit registry changed')
 local function map(header,key,limit)
  local s=read(header,24);local data,cap,empty,seed=address(s,0),word(s,8),word(s,12),word(s,16)
  assert(data>=65536 and data<2^47 and data%4==0 and cap>0 and cap<=4194304 and bit.band(cap,cap-1)==0,
   string.format('Hover map bounds invalid: header=%.0f data=%.0f cap=%d empty=%u seed=%u',header,data,cap,empty,seed))
  local low=key%65536;local hash=(low*seed+(((key-low)/65536*seed)%65536)*65536)%4294967296
  for i=0,math.min(cap,64)-1 do local row=read(data+((hash+i)%cap)*8,8);local found=word(row,0)
   if found==key then local index=word(row,4);assert(index<limit,'Hover packed row invalid');return index end
   if found==empty then return nil,true end
  end
  return nil,false -- A bounded search exhaustion is unavailable, not absent.
 end
 local function entity(world,e)
  local i,absent=map(world+L.WORLD_ENTITIES,e,4194304);if i==nil then return nil,absent end
  local at=world+L.WORLD_RECORDS+i*24;local raw=read(at,24);assert(word(raw,8)==e,'Hover entity record changed')
  if raw:byte(21)%2~=1 then return nil,true end
  return{address=at,raw=raw,entity=e,ref=word(raw,12),type=raw:sub(1,8)}
 end
 local function unit(record)
  local ref=record.ref;assert(ref>0 and ref<4294967295,'Hover Unit reference invalid')
  local registry=assert(ptr(memory.exe+L.REGISTRY),'Hover registry unavailable');local index=ref%4194304;local generation=math.floor(ref/4194304)
  local count=u32(registry+0x98);assert(count>0 and count<=4194304,'Hover registry bounds invalid')
  if index>=count then return nil,true end
  if read(assert(ptr(registry+0xa0,1))+index,1):byte()~=generation then return nil,true end
  local object=ptr(assert(ptr(registry+0x88))+index*8);if not object then return nil,true end
  local vt=assert(ptr(object));assert(ptr(vt+0xf8)==memory.exe+0x2bd890 and ptr(vt+0xc8)==memory.exe+0x2c3990,'Hover Unit type changed')
  return object
 end
 local function local_owner()
  local N,G=sr.Network,sr.GameSession;assert(N and G and type(N.game_session)=='function','Hover solo authority unavailable')
  local session=N.game_session();local peers,joining
  if session then peers=G.other_peers(session);joining=G.synchronizing_peers(session)else peers=N.connections();joining={}end
  assert(type(peers)=='table'and type(joining)=='table'and not next(peers)and not next(joining),'Hover override requires a verified solo session')
  local players=assert(ptr(memory.game+L.PLAYER));local count=u32(players+132);assert(count>0 and count<=8,'Hover local player unavailable');local player
  for i=0,count-1 do local rec=assert(ptr(players+232+i*8));if u32(rec+20)%2==1 then assert(not player,'Hover local owner ambiguous');player=u32(rec+8)end end
  assert(player,'Hover local player unavailable');local pi=assert(map(players+208,player,8));local root=u32(players+936+pi*32)
  local world=assert(ptr(memory.game+L.WORLD));local wi=assert(map(world+L.WORLD_UNITS,root,4194304));local raw=read(world+L.WORLD_RECORDS+wi*24,24)
  assert(word(raw,16)==root and word(raw,0)==0x294dfa97 and word(raw,4)==0x4d1c334d and raw:byte(21)%2==1,'Hover current local avatar required')
  local avatar=word(raw,8);local avatar_record=assert(entity(world,avatar));local native=assert(unit(avatar_record),'Hover local Unit retired')
  local scene=assert(sr.Application.main_world(),'Hover world unavailable');local scene_native=memory.scene(scene)
  assert(ptr(native+0x18)==scene_native,'Hover local scene changed')
  local inventory=assert(ptr(memory.game+L.INVENTORY));local ii,absent=map(inventory+40,avatar,4194304)
  assert(ii~=nil,'Hover local inventory unavailable');local pack=u32(assert(ptr(inventory+80,4))+ii*48+12)
  return{players=players,player=player,world=world,scene=scene_native,avatar=avatar,avatar_ref=word(raw,12),game_ref=root,avatar_native=native,pack=pack}
 end
 local function clock()
  if completed_update then local a,b=completed_update();assert(finite(a)and finite(b)and a>=0 and b>=0,'Hover completed update unavailable');return a,b end
  return epoch,delta
 end
 -- Integrator calls ONLY after the previous native/game update has returned.
 -- Render/UI sampling must never manufacture this completion evidence.
 function self.after_update(dt)assert(finite(dt)and dt>=0,'Hover completed dt invalid');epoch=epoch+1;delta=dt;return epoch end
 function self.input_supported()
  local ok,supported,why=pcall(function()
   for i=1,4 do local pad=sr['Pad'..i];assert(type(pad)=='table'and type(pad.active)=='function','Game pad presence unavailable');local active=pad.active();assert(type(active)=='boolean','Game pad presence unavailable');if active then return false,'Game controller present'end end
   assert(type(memory.pad_absent)=='function','XInput presence unavailable');local absent,reason=memory.pad_absent();if absent~=true then return false,reason or'Controller presence unavailable'end;return true
  end)
  if not ok then return false,tostring(supported)end;return supported,why
 end
 local function snapshot(expected)
  local owner=local_owner();local seen,dt=clock()
  if expected and(owner.world~=expected.world or owner.scene~=expected.scene)then return{expired=true}end
  local e=expected and expected.entity or owner.pack
  local empty=e==0 or e==4294967295
  if empty then assert(not expected,'Owned hover entity invalid');return{active=false,hover=false,value=0,epoch=seen,dt=dt,control={x=0,y=0,z=0},action=0,absent=true}end
  local record,absent=entity(owner.world,e)
  if not record then if expected and absent then return{expired=true}end;error('Hover pack entity unavailable')end
  local native,retired=unit(record);if not native then if expected and retired then return{expired=true}end;error('Hover pack Unit unavailable')end
  assert(ptr(native+0x18)==owner.scene,'Hover pack scene changed')
  if record.type~='\xcf\x66\xdb\x1c\x4f\x0f\xc8\x5e'then
   if expected then return{expired=true}end
   return{active=false,hover=false,value=0,epoch=seen,dt=dt,control={x=0,y=0,z=0},action=0,other_pack=true}
  end
  if expected and(record.ref~=expected.unit_ref or native~=expected.unit_native)then return{expired=true}end
  local manager=assert(ptr(memory.game+L.JUMP));local count,capacity=u32(manager+0xc),u32(manager)
  assert(capacity>0 and capacity<=4096 and count<=capacity,'Hover manager bounds invalid')
  local list=assert(ptr(manager+0x38));local row,descriptor
  for i=0,count-1 do local rec=assert(ptr(list+i*8));local raw=read(rec,24)
   if word(raw,8)==e then assert(row==nil,'Hover component identity ambiguous');assert(raw:sub(1,16)==record.raw:sub(1,16)and raw:byte(21)%2==1,'Hover component record changed');row=i;descriptor=rec end
  end
  if row==nil then if expected then return{expired=true}end;error('Hover component unavailable')end
  local definitions=u32(manager+0x98);assert(definitions>0 and definitions<=capacity,'Hover definition bounds invalid')
  local di,definition_absent=map(manager+0x60,e,definitions)
  if di==nil then if expected and definition_absent then return{expired=true}end;error('Entity-owned hover definition unavailable')end
  local definition=assert(ptr(manager+0xa0,4))+di*0x118;local header=read(definition,16);local mode=read(definition+0x99,2)
  assert(mode:byte(1)<=1 and mode:byte(2)<=1,'Hover mode field changed')
  local generation=table.concat({record.ref,native,descriptor},':')..':'..header..mode
  if expected and generation~=expected.generation then return nil,'Owned hover definition identity changed'end
  local field_bytes=read(definition+0x9c,4);local value=decode(field_bytes)
  local flags=read(assert(ptr(manager+0x50,1))+row*5,5);assert(flags:byte(1)<=1,'Hover flight flag invalid')
  local vector=read(assert(ptr(manager+0x40,4))+row*12,12)
  local avatars=assert(ptr(memory.game+L.AVATAR));local ai=assert(map(avatars+0xf8,owner.avatar,8),'Hover gameplay owner unavailable');local gameplay=avatars+ai*0xa7aec
  local action=decode(read(gameplay+0x1ea0,4));local xy=read(gameplay+0xa7c18,8)
  -- Avatar/Unit changes on respawn do not retire a still-living owned pack.
  -- Restore keys the pack lifetime plus stable local player, never the current
  -- equipped avatar or saved packed-row/definition addresses.
  local identity=table.concat({owner.world,owner.scene,owner.players,owner.player,e},':')
  if expected and identity~=expected.identity then return nil,'Local hover owner changed'end
  local latest=read(descriptor,24);assert(ptr(memory.game+L.JUMP)==manager and latest:sub(1,16)==record.raw:sub(1,16)and latest:byte(21)%2==1 and ptr(memory.game+L.WORLD)==owner.world,'Hover owner changed during snapshot')
  return{identity=identity,generation=generation,entity=e,unit_ref=record.ref,unit_native=native,world=owner.world,scene=owner.scene,
   avatar=owner.avatar,avatar_ref=owner.avatar_ref,player=owner.player,players=owner.players,manager=manager,descriptor=descriptor,definition=definition,field_address=definition+0x9c,field_bytes=field_bytes,
   value=value,active=flags:byte(1)==1,hover=mode:byte(1)==1,epoch=seen,dt=dt,control={x=decode(vector:sub(1,4)),y=decode(vector:sub(5,8)),z=decode(vector:sub(9,12))},
   action=action,gameplay={x=decode(xy:sub(1,4)),y=decode(xy:sub(5,8))},equipped=owner.pack==e,flags=flags}
 end
 function self.snapshot(expected)local ok,value,why=pcall(snapshot,expected);if not ok then return nil,tostring(value)end;return value,why end
 local function write(expected,value,restore)
  local committed=false;local ok,why=pcall(function()
   assert(type(expected)=='table'and expected.identity and expected.generation,'Hover write ownership unavailable')
   local fresh,reason=snapshot(expected);assert(fresh and not fresh.expired,reason or'Hover owner retired')
   assert(fresh.identity==expected.identity and fresh.generation==expected.generation,'Hover owner changed')
   assert(restore or fresh.equipped,'Hover pack is no longer equipped')
   assert(fresh.value==expected.value and fresh.field_bytes==expected.field_bytes,'Hover field belongs to another writer')
   local bytes=encode(value);assert(memory.write(fresh.field_address,bytes)~=false,'Hover data write refused');committed=true
   local after,problem=snapshot(expected);assert(after and not after.expired and after.identity==expected.identity and after.generation==expected.generation and after.field_bytes==bytes,problem or'Hover write readback changed')
  end)
  return ok,not ok and tostring(why)or nil,committed
 end
 function self.set(expected,value)assert(value==0,'Hover override only permits zero');return write(expected,value,false)end
 function self.restore(expected,value)return write(expected,value,true)end
 return self
end
return M

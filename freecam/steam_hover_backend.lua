-- Current-process data-only hover control through a typed ordinary-Lua bridge.
-- No game-function calls, executable writes, or shared-definition changes.
-- Local avatar/inventory layout follows the existing subject identity adapter
-- and Link's MIT address reference (vendor/LICENSE-Link.txt).
local M={}
M.layout={game_stamp=0x6ad7c05d,game_size=0x3382000,exe_stamp=0x6ad78c0d,
 WORLD=0x2ce41b8,PLAYER=0x2ce1618,INVENTORY=0x2ce18e8,AVATAR=0x2ce1ee0,JUMP=0x2ce1d78,
 WORLD_UNITS=0xf24990,WORLD_ENTITIES=0xf1c978,WORLD_RECORDS=0xf349e0,REGISTRY=0x1ab76f8}
M.fingerprints={{0x9c6420,'48895c241855565741544155415641'},{0x9c6942,'f3410f1084249c000000'},{0x9c6a97,'0f2e3d72cf78027a1575130f2ef27a0e750c440f2ee37a060f84740400'},{0x9c6d8a,'f3450f5eee'},{0x9c6db7,'f3410f5efef3410f5ef6'},{0x58e860,'83f90c771d4c8d059417a7ff8bc1418b948088e858004903d0ffe248c1e9208bc1c3b8ffffffff'},{0x58e890,'7be85800'}}

local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function word(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Hover data truncated');return a+b*256+c*65536+d*16777216 end
local function address(s,o)return word(s,o)+word(s,o+4)*4294967296 end
local function decode(s)
 local bits=word(s,0);local sign=bits>=2147483648 and -1 or 1
 local exponent=math.floor(bits/8388608)%256;local fraction=bits%8388608
 assert(exponent~=255,'Hover float invalid')
 local value=sign*(exponent==0 and fraction*2^-149 or(1+fraction/8388608)*2^(exponent-127))
 assert(finite(value)and math.abs(value)<=1e6,'Hover float invalid');return value
end
local function encode(v)
 assert(finite(v)and math.abs(v)<=1e6,'Hover write value invalid')
 local sign=v<0 or(v==0 and 1/v==-math.huge);v=math.abs(v)
 local bits=0
 if v~=0 then
  local m,e=math.frexp(v);local exponent=e+126
  local scaled=exponent<=0 and v*2^149 or m*16777216
  local q=math.floor(scaled);local remainder=scaled-q
  if remainder>.5 or remainder==.5 and q%2==1 then q=q+1 end
  bits=exponent<=0 and q or(exponent-1)*8388608+q
 end
 if sign then bits=bits+2147483648 end
 local bytes={};for i=1,4 do bytes[i]=string.char(bits%256);bits=math.floor(bits/256)end
 return table.concat(bytes)
end
local function power_two(v)
 while v>1 and v%2==0 do v=v/2 end;return v==1
end
local function unhex(s)return(s:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))end
local function native_memory()
 local memory=mod.require('src/host_native.lua').memory()
 memory.scene=memory.world_address
 local open,why=package.loadlib(mod.dir..'/port51/hd2_nativeinfo_3139cc5f8ecb4078.dll','luaopen_hd2_nativeinfo')
 assert(open,why);local bridge=open()
 for _,name in ipairs({'hover_ensure','hover_height','gamepads_absent'})do assert(type(bridge[name])=='function','Hover native bridge incomplete')end
 function memory.ensure_private(frame)return bridge.hover_ensure(frame.entity,frame.unit_ref)end
 function memory.write_hover(frame,value)return bridge.hover_height(frame.entity,frame.unit_ref,frame.value,value)==value end
 memory.pad_absent=bridge.gamepads_absent
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
  assert(read(base+pe,4)=='PE\0\0'and read(base+pe+4,2)=='\100\134'and read(base+pe+24,2)=='\011\002'and u32(base+pe+8)==stamp,'Hover build unsupported')
  assert(not size or u32(base+pe+80)==size,'Hover game image changed')
 end
 image(memory.game,L.game_stamp,L.game_size);image(memory.exe,L.exe_stamp)
 for _,fp in ipairs(M.fingerprints)do assert(read(memory.game+fp[1],#fp[2]/2)==unhex(fp[2]),'Hover control fingerprint changed')end
 assert(read(memory.exe+0xa06b0,22)=='\072\137\092\036\008\072\137\116\036\016\087\072\131\236\032\072\139\053\050\112\161\001','Hover Unit registry changed')
 local function map(header,key,limit)
  local s=read(header,24);local data,cap,empty,seed=address(s,0),word(s,8),word(s,12),word(s,16)
  assert(data>=65536 and data<2^47 and data%4==0 and cap>0 and cap<=4194304 and power_two(cap),
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
  local vt=assert(ptr(object));assert(ptr(vt+0xf8)==memory.exe+0x28d3c0 and ptr(vt+0xc8)==memory.exe+0x2935e0,'Hover Unit type changed')
  return object
 end
 local function local_owner(cleanup)
  local N,G=sr.Network,sr.GameSession;assert(N and G and type(N.game_session)=='function','Hover solo authority unavailable')
  local session=N.game_session();local peers,joining
  if session then peers=G.other_peers(session);joining=G.synchronizing_peers(session)else peers=N.connections();joining={}end
  assert(type(peers)=='table'and type(joining)=='table','Hover session inventory unavailable')
  assert(cleanup or not next(peers)and not next(joining),'Hover override requires a verified solo session')
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
  local owner=local_owner(expected~=nil)
  if expected and(owner.world~=expected.world or owner.scene~=expected.scene)then return{expired=true}end
  local seen,dt=clock()
  local e=expected and expected.entity or owner.pack
  local empty=e==0 or e==4294967295
  if empty then assert(not expected,'Owned hover entity invalid');return{active=false,hover=false,value=0,epoch=seen,dt=dt,control={x=0,y=0,z=0},action=0,absent=true}end
  local record,absent=entity(owner.world,e)
  if not record then if expected and absent then return{expired=true}end;error('Hover pack entity unavailable')end
  local native,retired=unit(record);if not native then if expected and retired then return{expired=true}end;error('Hover pack Unit unavailable')end
  assert(ptr(native+0x18)==owner.scene,'Hover pack scene changed')
  if record.type~='\207\102\219\028\079\015\200\094'then
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
  local definitions=u32(manager+0x98);local private_capacity=u32(manager+4)
  assert(private_capacity>0 and private_capacity<=256 and definitions<=private_capacity,'Hover definition bounds invalid')
  local di=map(manager+0x60,e,private_capacity)
  local definition;local shared=di==nil
  if di~=nil then
   assert(di<definitions,'Private hover definition index invalid')
   definition=assert(ptr(manager+0xa0,4))+di*0x118
  else
   -- Diagnostic only: observe the default resource without ever writing it.
   local pool=assert(ptr(owner.world+0xf14780,4));local headers=read(pool,96)
   for i=0,5 do if headers:sub(i*16+1,i*16+8)==record.type then
    assert(not definition,'Ambiguous hover template');local index=word(headers,i*16+8);assert(index<3)
    definition=pool+96+index*280
   end end
   assert(definition,'Hover default resource unavailable')
  end
;local header=read(definition,16);local mode=read(definition+0x99,2)
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
   value=value,shared=shared,active=flags:byte(1)==1,hover=mode:byte(1)==1,epoch=seen,dt=dt,control={x=decode(vector:sub(1,4)),y=decode(vector:sub(5,8)),z=decode(vector:sub(9,12))},
   action=action,gameplay={x=decode(xy:sub(1,4)),y=decode(xy:sub(5,8))},equipped=owner.pack==e,flags=flags}
 end
 function self.snapshot(expected)local ok,value,why=pcall(snapshot,expected);if not ok then return nil,tostring(value)end;return value,why end
 local function write(expected,value,restore)
  local committed=false;local ok,why=pcall(function()
   assert(type(expected)=='table'and expected.identity and expected.generation,'Hover write ownership unavailable')
   local fresh,reason=snapshot(expected);assert(fresh and not fresh.expired,reason or'Hover owner retired')
   assert(fresh.identity==expected.identity and fresh.generation==expected.generation,'Hover owner changed')
   if fresh.shared then
    assert(not restore and type(memory.ensure_private)=='function','Owned hover override unavailable')
    assert(memory.ensure_private(fresh)==true,'Private hover copy refused')
    fresh=assert(snapshot(expected),'Private hover copy unreadable')
    assert(not fresh.shared and fresh.identity==expected.identity and fresh.generation==expected.generation,'Private hover copy owner changed')
   end
   assert(restore or fresh.equipped,'Hover pack is no longer equipped')
   assert(fresh.value==expected.value and fresh.field_bytes==expected.field_bytes,'Hover field belongs to another writer')
   local bytes=encode(value);assert((memory.write_hover and memory.write_hover(fresh,value)or not memory.write_hover and memory.write(fresh.field_address,bytes))~=false,'Hover data write refused');committed=true
   local after,problem=snapshot(expected);assert(after and not after.expired and after.identity==expected.identity and after.generation==expected.generation and after.field_bytes==bytes,problem or'Hover write readback changed')
  end)
  return ok,not ok and tostring(why)or nil,committed
 end
 function self.set(expected,value)assert(value==0,'Hover override only permits zero');return write(expected,value,false)end
 function self.restore(expected,value)return write(expected,value,true)end
 return self
end
return M

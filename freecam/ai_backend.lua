-- Enemy component layouts adapted from Link's MIT hd2_enemy/hd2_addresses/
-- hd2_net libraries. Copyright (c) 2026 Link; see vendor/LICENSE-Link.txt.
-- This backend changes behavior fields only: no clock, pose, velocity, stun,
-- spawn, despawn, physics API, or game-function invocation.
local M={game_stamp=0x6ab3b43f,exe_stamp=0x6ab382e4}
M.layout={WORLD=0x346bf98,DIRECTOR=0x3326d10,AI=0x33266c8,BEHAVIOR=0x3326740,DETECTOR=0x3326548,ALERT=0x3326528,
 INVALID=0x3483c20,NET=0x347cef0,GAME_STATE=0x3326340,GAME_MODE=0x33266a0,STATE_VALUE=0xac21c,
 WORLD_ENTITIES=0xf1aeb0,WORLD_RECORDS=0xf32f18,UNIT_REGISTRY=0x1a100f0}
local specs={ai={map=0x2330,list=0x2348,rows=0x2360,stride=0x14},behavior={map=0x40,list=0x58,rows=0x60,stride=0x1f8},
 detector={map=0x30,list=0x48,rows=0x50,stride=0x13f8},alert={map=0x20,list=0x38,rows=0x50,stride=4}}
local bit=require('bit')
local function word(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'AI data truncated');return a+b*256+c*65536+d*16777216 end
local function address(s,o)return word(s,o)+word(s,o+4)*4294967296 end
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
function M.new(sr,memory)
 if not memory then
  local ffi=require('ffi');pcall(ffi.cdef,[[void* AIB_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void* AIB_GetCurrentProcess(void) __asm__("GetCurrentProcess");
   int AIB_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");int AIB_WriteProcessMemory(void*,void*,const void*,size_t,size_t*) __asm__("WriteProcessMemory");
   unsigned long long AIB_GetTickCount64(void) __asm__("GetTickCount64");]])
  local K=ffi.load('kernel32');local process=K.AIB_GetCurrentProcess()
  local buffer=ffi.new('uint8_t[4096]');local got=ffi.new('size_t[1]')
  memory={game=tonumber(ffi.cast('uintptr_t',K.AIB_GetModuleHandleA('game.dll'))),exe=tonumber(ffi.cast('uintptr_t',K.AIB_GetModuleHandleA(nil)))}
  function memory.read(at,size)assert(K.AIB_ReadProcessMemory(process,ffi.cast('void*',at),buffer,size,got)~=0 and tonumber(got[0])==size,'AI memory unavailable');return ffi.string(buffer,size)end
  function memory.write(at,data)local got=ffi.new('size_t[1]');assert(K.AIB_WriteProcessMemory(process,ffi.cast('void*',at),data,#data,got)~=0 and tonumber(got[0])==#data,'AI write unavailable')end
  function memory.scene(world)return address(memory.read(tonumber(ffi.cast('uintptr_t',world)),8),0)end
  function memory.now()return tonumber(K.AIB_GetTickCount64())/1000 end
 end
 local L=M.layout;local self={};local function read(at,size)
  assert(type(at)=='number'and at>=65536 and at<2^47 and size>0 and size<=4096,'AI read bounds changed')
  local data=memory.read(at,size);assert(type(data)=='string'and#data==size,'AI read incomplete');return data
 end
 local function u32(at)return word(read(at,4),0)end
 local function ptr(at)local p=address(read(at,8),0);assert(p==0 or(p>=65536 and p<2^47 and p%8==0),'AI pointer invalid');return p~=0 and p or nil end
 local function image(base,stamp)local pe=u32(base+60);assert(pe>=64 and pe<1048576 and read(base+pe,4)=='PE\0\0'and u32(base+pe+8)==stamp,'Enemy behavior build unsupported')end
 image(memory.game,M.game_stamp);image(memory.exe,M.exe_stamp)
 -- Registry fingerprint shared with the already verified local-subject route.
 assert(read(memory.exe+0x9d8c0,22)=='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01','AI Unit registry changed')
 local function map(header,key)
  local h=read(header,24);local data,cap,empty,seed=address(h,0),word(h,8),word(h,12),word(h,16)
  assert(data>=65536 and cap>0 and cap<=1048576 and bit.band(cap,cap-1)==0,'AI map layout changed')
  if not key then return data,cap,empty end
  local low=key%65536;local hash=(low*seed+(((key-low)/65536*seed)%65536)*65536)%4294967296
  for i=0,math.min(cap,64)-1 do local row=read(data+((hash+i)%cap)*8,8);local found=word(row,0)
   if found==key then local index=word(row,4);if index~=4294967295 then assert(index<1048576,'AI row index invalid');return index end;return end
   if found==empty then return end
  end
 end
 local function part(manager,spec,e)
  if not manager then return end
  local index=map(manager+spec.map,e);if index==nil then return end
  local list=ptr(manager+spec.list);local descriptor=list and ptr(list+index*8);if not descriptor then return end
  local d=read(descriptor,24);if word(d,8)~=e or d:byte(21)%2~=1 then return end
  local rows=ptr(manager+spec.rows);if not rows then return end
  return rows+index*spec.stride,descriptor
 end
 function self.now()return memory.now()end
 local function session_authority(cleanup)
  local net=ptr(memory.game+L.NET);if not net then return nil,'Host authority unavailable','unknown_session'end
  local local_peer,host_peer=read(net+0xb398,8),read(net+0xb3a8,8);local zero=string.rep('\0',8)
  if local_peer==zero then return nil,'Local peer authority unavailable','unknown_session'end
  local N,G=sr.Network,sr.GameSession
  if not(N and G and type(N.game_session)=='function')then return nil,'Solo session reader unavailable','unknown_session'end
  local known,peers,joining=pcall(function()
   local session=N.game_session()
   if session then
    assert(type(G.other_peers)=='function'and type(G.synchronizing_peers)=='function','Session peer reader unavailable')
    return G.other_peers(session),G.synchronizing_peers(session)
   end
   assert(type(N.connections)=='function','Connection reader unavailable');return N.connections(),{}
  end)
  if not known or type(peers)~='table'or type(joining)~='table'then return nil,'Solo player count unavailable','unknown_session'end
  -- other_peers excludes the verified local peer. Count map entries rather than
  -- array length: game session peer tables may be sparse or keyed by peer id.
  local player_count=1;for _ in pairs(peers)do player_count=player_count+1 end
  local solo=player_count==1 and next(joining)==nil
  if not cleanup and not solo then return nil,'Enemy behavior is solo-only; another player is connected or joining','not_solo'end
  if local_peer~=host_peer and not(host_peer==zero and solo)then return nil,'Local solo authority unavailable','unknown_session'end
  return {local_peer=local_peer,solo=solo,player_count=player_count}
 end
 local function session_context(cleanup)
  local world=ptr(memory.game+L.WORLD);local state=ptr(memory.game+L.GAME_STATE);local mode=ptr(memory.game+L.GAME_MODE)
  if not(world and state and mode and u32(state+L.STATE_VALUE)==4 and u32(mode+8)==1)then return nil,'Enemy controls require a mission'end
  -- Classify network uncertainty explicitly. Ordinary world/scene reads may
  -- fail during respawn or loading; that suspends work without losing intent.
  local checked,session,why,policy=pcall(session_authority,cleanup)
  if not checked then return nil,'Session authority unreadable: '..tostring(session),'unknown_session'end
  if not session then return nil,why,policy end
  local scene=sr.Application.main_world();if not scene then return nil,'Main scene unavailable'end
  local scene_native=memory.scene(scene);local director=ptr(memory.game+L.DIRECTOR);if not director then return nil,'Enemy director unavailable'end
  assert(type(scene_native)=='number'and scene_native>=65536 and scene_native<2^47,'Enemy scene pointer invalid')
  -- Authority is rechecked for every access. A solo session can establish its
  -- host id after startup without retiring the world or our restoration leases.
  return {world=world,scene=scene,scene_native=scene_native,director=director,identity=table.concat({world,scene_native,director,session.local_peer},':'),authority=true,solo=session.solo,player_count=session.player_count,cleanup=cleanup==true}
 end
 function self.context()return session_context(false)end
 function self.restore_context()return session_context(true)end
 local function valid_context(ctx)local current=ctx.cleanup and self.restore_context()or self.context();return current and current.identity==ctx.identity end
 local function unit(ctx,e)
  local i=map(ctx.world+L.WORLD_ENTITIES,e);if i==nil then return end
  local row=read(ctx.world+L.WORLD_RECORDS+i*24,24);if word(row,8)~=e then return end
  local ref=word(row,12);local registry=ptr(memory.exe+L.UNIT_REGISTRY);if not registry then return end
  local index=ref%4194304;local generation=math.floor(ref/4194304)
  if index>=u32(registry+0x98)or read(assert(ptr(registry+0xa0))+index,1):byte()~=generation then return end
  local object=ptr(assert(ptr(registry+0x88))+index*8);if not object or ptr(object+0x18)~=ctx.scene_native then return end
  local vt=ptr(object);if not vt or ptr(vt+0xf8)~=memory.exe+0x2bd890 or ptr(vt+0xc8)~=memory.exe+0x2c3990 then return end
  return ref
 end
 local function identity(ctx,e,ref)return ctx.identity..':'..e..':'..ref end
 -- Movement ownership belongs to this Unit/AI row. A retired borrowed
 -- detector must not prevent restoring this still-live unit's movement bit.
 function self.observe_restore(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local ai,token=part(ptr(memory.game+L.AI),specs.ai,e);if not ai or u32(ai)==16 then return nil,'retired'end
  return {kind='movement',entity=e,identity=identity(ctx,e,ref),unit=ref,fields={still={value=u32(ai+4),address=ai+4,size=4,token=token}}}
 end
 -- A detector can be borrowed by another enemy. Resolve its real owner even
 -- after that borrower dies, without depending on the owner's Behavior row.
 function self.observe_detector(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local ai=part(ptr(memory.game+L.AI),specs.ai,e);if not ai or u32(ai)==16 then return nil,'retired'end
  local detector,token=part(ptr(memory.game+L.DETECTOR),specs.detector,e)
  if not detector then return nil,'Enemy detector component unavailable'end
  return {kind='detector',entity=e,identity=identity(ctx,e,ref),unit=ref,fields={detector={value=read(detector+0x13f0,1):byte(),address=detector+0x13f0,size=1,token=token}}}
 end
 function self.observe(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local ai,ai_token=part(ptr(memory.game+L.AI),specs.ai,e);if not ai or u32(ai)==16 then return nil,'retired'end
  local behavior,b_token=part(ptr(memory.game+L.BEHAVIOR),specs.behavior,e)
  local invalid=u32(memory.game+L.INVALID);local owner=behavior and u32(behavior+0x68)or e
  if owner==0 or owner==invalid then owner=e end
  local owner_ref=ref
  if owner~=e then
   local owner_ai=part(ptr(memory.game+L.AI),specs.ai,owner)
   owner_ref=unit(ctx,owner)
   if not owner_ai or not owner_ref or u32(owner_ai)==16 then return nil,'Enemy detector owner is not a live enemy'end
  end
  local detector,d_token=part(ptr(memory.game+L.DETECTOR),specs.detector,owner)
  local alert,a_token=part(ptr(memory.game+L.ALERT),specs.alert,e)
  if not(behavior and detector)then return nil,'Enemy detector/behavior components unavailable'end
  local fields={};local function field(key,at,size,token)fields[key]={value=size==1 and read(at,1):byte()or u32(at),address=at,size=size,token=token}end
  field('still',ai+4,4,ai_token);field('detector',detector+0x13f0,1,d_token);field('hostiles',detector+0x310,4,d_token);field('target',behavior+0x18,4,b_token)
  fields.detector.owner=owner;fields.detector.owner_identity=identity(ctx,owner,owner_ref)
  fields.hostiles.owner=owner;fields.hostiles.owner_identity=fields.detector.owner_identity
  if alert then field('alert',alert,4,a_token)end
  return {entity=e,identity=identity(ctx,e,ref),unit=ref,fields=fields,invalid=invalid}
 end
 local function write_field(ctx,record,key,value,expected,cleanup)
  local committed=false
  local ran,why=pcall(function()
   assert((ctx.cleanup==true)==cleanup,'Enemy write context mismatch')
   if cleanup then
    assert(key=='detector'or key=='still','Only owned behavior baselines may be restored')
    if key=='still'then assert(bit.band(bit.bxor(value,expected),bit.bnot(0x80))==0,'Restoration changed unrelated movement flags')
    else assert(expected==0,'Detector restoration no longer owns the disabled state')end
   end
   local observe=record.kind=='detector'and self.observe_detector or record.kind=='movement'and self.observe_restore or self.observe
   local fresh,why=observe(ctx,record.entity);assert(fresh and fresh.identity==record.identity,why or'Enemy generation changed')
   local before=assert(record.fields[key]);local field=assert(fresh.fields[key]);assert(field.token==before.token and field.owner_identity==before.owner_identity and field.value==expected,'Enemy field ownership changed')
   assert(type(value)=='number'and value==math.floor(value)and value>=0 and value<2^(8*field.size),'Invalid enemy field value')
   memory.write(field.address,le(value,field.size));committed=true
   local after=observe(ctx,record.entity);assert(after and after.identity==record.identity and after.fields[key]and after.fields[key].token==field.token and after.fields[key].owner_identity==field.owner_identity and after.fields[key].value==value,'Enemy write readback changed')
  end)
  return ran,not ran and tostring(why)or nil,committed
 end
 function self.write(ctx,record,key,value,expected)return write_field(ctx,record,key,value,expected,false)end
 function self.restore(ctx,record,key,value,expected)return write_field(ctx,record,key,value,expected,true)end
 function self.scan(ctx,cursor,budget)
  if ctx.cleanup then return{},0,'Restoration context cannot discover new enemies'end
  if not valid_context(ctx)then return{},0,'Enemy scene or authority changed'end
  local manager=ptr(memory.game+L.AI);if not manager then return{},0,'Enemy manager unavailable'end
  local data,cap,empty=map(manager+specs.ai.map);cursor=math.max(0,math.min(cursor or 0,cap-1));budget=math.max(1,math.min(budget or 256,256,cap-cursor))
  local block=read(data+cursor*8,budget*8);local out={}
  for i=0,budget-1 do local e=word(block,i*8);if e~=empty and word(block,i*8+4)~=4294967295 then out[#out+1]=e end end
  return out,(cursor+budget)%cap
 end
 return self
end
return M

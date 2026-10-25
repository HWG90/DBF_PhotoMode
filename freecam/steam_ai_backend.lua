local PORT51=mod.require('src/cffi.lua')
-- Enemy component layouts adapted from Link's MIT hd2_enemy/hd2_addresses/
-- hd2_net libraries. Copyright (c) 2026 Link; see vendor/LICENSE-Link.txt.
-- This backend changes behavior fields and the solo player no-aggro bit only: no clock, pose, velocity, stun,
-- spawn, despawn, physics API, or game-function invocation.
local M={game_stamp=0x6ad7c05d,exe_stamp=0x6ad78c0d}
M.layout={WORLD=0x2ce41b8,DIRECTOR=0x2ce1ed0,AI=0x2ce1878,BEHAVIOR=0x2ce18f0,DETECTOR=0x2ce16f8,ALERT=0x2ce16d8,
 INVALID=0x2e3f0d0,NET=0x2e38228,GAME_STATE=0x2ce1508,GAME_MODE=0x2ce1850,STATE_VALUE=0xac29c,
 WORLD_ENTITIES=0xf1c978,WORLD_RECORDS=0xf349e0,UNIT_REGISTRY=0x1ab76f8}
local specs={ai={map=0x2430,list=0x2448,rows=0x2460,stride=0x14},behavior={map=0x40,list=0x58,rows=0x60,stride=0x1f8},
 detector={map=0x30,list=0x48,rows=0x50,stride=0x13f8},alert={map=0x20,list=0x38,rows=0x50,stride=4}}
local bit=PORT51.bit 
local function word(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'AI data truncated');return a+b*256+c*65536+d*16777216 end
local function address(s,o)return word(s,o)+word(s,o+4)*4294967296 end
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
function M.new(sr,memory)
 if not memory then
  local ffi=PORT51.ffi ;pcall(ffi.cdef,[[void* AIB_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void* AIB_GetCurrentProcess(void) __asm__("GetCurrentProcess");
   int AIB_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");int AIB_WriteProcessMemory(void*,void*,const void*,size_t,size_t*) __asm__("WriteProcessMemory");
   unsigned long long AIB_GetTickCount64(void) __asm__("GetTickCount64");int AIB_QueryPerformanceCounter(int64_t*) __asm__("QueryPerformanceCounter");int AIB_QueryPerformanceFrequency(int64_t*) __asm__("QueryPerformanceFrequency");]])
  local K=ffi.load('kernel32');local process=K.AIB_GetCurrentProcess()
  local counter=ffi.new('int64_t[1]');assert(K.AIB_QueryPerformanceFrequency(counter)~=0,'AI performance clock unavailable');local frequency=PORT51.number(counter[0])
  local buffer=ffi.new('uint8_t[4096]');local got=ffi.new('size_t[1]')
  memory={game=PORT51.number(ffi.cast('uintptr_t',K.AIB_GetModuleHandleA('game.dll'))),exe=PORT51.number(ffi.cast('uintptr_t',K.AIB_GetModuleHandleA(nil)))}
  function memory.read(at,size)assert(K.AIB_ReadProcessMemory(process,ffi.cast('void*',at),buffer,size,got)~=0 and PORT51.number(got[0])==size,'AI memory unavailable');return ffi.string(buffer,size)end
  function memory.write(at,data)local got=ffi.new('size_t[1]');assert(K.AIB_WriteProcessMemory(process,ffi.cast('void*',at),data,#data,got)~=0 and PORT51.number(got[0])==#data,'AI write unavailable')end
  function memory.scene(world)return address(memory.read(PORT51.number(ffi.cast('uintptr_t',world)),8),0)end
  function memory.now()return PORT51.number(K.AIB_GetTickCount64())/1000 end
  function memory.cost_now()assert(K.AIB_QueryPerformanceCounter(counter)~=0,'AI performance clock unavailable');return PORT51.number(counter[0])/frequency end
 end
 local L=M.layout;local self={};local function read(at,size)
  assert(PORT51.kind(at)=='number'and at>=65536 and at<2^47 and size>0 and size<=4096,'AI read bounds changed')
  local data=memory.read(at,size);assert(PORT51.kind(data)=='string'and#data==size,'AI read incomplete');return data
 end
 local function u32(at)return word(read(at,4),0)end
 local function checked_pointer(p)assert(p==0 or(p>=65536 and p<2^47 and p%8==0),'AI pointer invalid');return p~=0 and p or nil end
 local function ptr(at)return checked_pointer(address(read(at,8),0))end
 -- Copies live only for this operation. A span crossing unreadable padding
 -- falls back to the original scalar reads; optional components stay isolated.
 local function span(at,size)local ok,data=pcall(read,at,size);if ok then return data end end
 local function copied_pointer(copied,offset,at)
  if copied then return checked_pointer(address(copied,offset))end
  return ptr(at)
 end
 local function image(base,stamp)local pe=u32(base+60);assert(pe>=64 and pe<1048576 and read(base+pe,4)=='PE\0\0'and u32(base+pe+8)==stamp,'Enemy behavior build unsupported')end
 image(memory.game,M.game_stamp);image(memory.exe,M.exe_stamp)
 -- Registry fingerprint shared with the already verified local-subject route.
 assert(read(memory.exe+0xa06b0,22)=='\072\137\092\036\008\072\137\116\036\016\087\072\131\236\032\072\139\053\050\112\161\001','AI Unit registry changed')
 local function map(header,key,copied)
  local h=copied or read(header,24);local data,cap,empty,seed=address(h,0),word(h,8),word(h,12),word(h,16)
  assert(data>=65536 and cap>0 and cap<=1048576 and bit.band(cap,cap-1)==0,'AI map layout changed')
  if not key then return data,cap,empty end
  local low=key%65536;local hash=(low*seed+(((key-low)/65536*seed)%65536)*65536)%4294967296
  local inspected,limit=0,math.min(cap,64)
  while inspected<limit do
   local slot=(hash+inspected)%cap;local length=math.min(8,limit-inspected,cap-slot)
   local block=span(data+slot*8,length*8)
   for i=0,length-1 do
    local row=block or read(data+(slot+i)*8,8);local offset=block and i*8 or 0;local found=word(row,offset)
    if found==key then local index=word(row,offset+4);if index~=4294967295 then assert(index<1048576,'AI row index invalid');return index end;return end
    if found==empty then return end
   end
   inspected=inspected+length
  end
 end
 local function part(manager,spec,e)
  if not manager then return end
  local header=span(manager+spec.map,spec.rows-spec.map+8)
  local index=map(manager+spec.map,e,header);if index==nil then return end
  local list=copied_pointer(header,spec.list-spec.map,manager+spec.list)
  local descriptor=list and ptr(list+index*8);if not descriptor then return end
  local d=read(descriptor,24);if word(d,8)~=e or d:byte(21)%2~=1 then return end
  local rows=copied_pointer(header,spec.rows-spec.map,manager+spec.rows);if not rows then return end
  return rows+index*spec.stride,descriptor
 end
 local function managers()return span(memory.game+L.ALERT,L.BEHAVIOR-L.ALERT+8)end
 local function manager(label,copied)
  if copied then return checked_pointer(address(copied,L[label]-L.ALERT))end
  return ptr(memory.game+L[label])
 end
 function self.now()return memory.now()end
 function self.cost_now()return memory.cost_now and memory.cost_now()end
 -- Read the current mission record, rather than classifying nearby enemies.
 -- The current-build GameStart serializer and faction-specific native callers
 -- use GameState+AE288 -> record+F8 (2 Bugs, 3 Cyborg, 4 Illuminate).
 local faction_cache;local faction_deadline=0
 function self.faction()
  local now=memory.now();if now<faction_deadline then return faction_cache end
  faction_deadline=now+.5;faction_cache=nil
  local ok,value=pcall(function()
   assert(read(memory.game+0x11da689,22)=='\076\139\037\120\110\176\001\073\139\156\036\008\227\010\000\076\141\171\248\000\000\000','Mission faction owner reader changed')
   assert(read(memory.game+0x11da6de,5)=='\065\015\182\069\008','Mission faction byte reader changed')
   local state=ptr(memory.game+L.GAME_STATE);local mode=ptr(memory.game+L.GAME_MODE)
   if not(state and mode and u32(state+L.STATE_VALUE)==4 and u32(mode+8)==1)then return end
   local record=ptr(state+0xae308);if not record then return end
   local id=read(record+0x100,1):byte()
   if ptr(memory.game+L.GAME_STATE)~=state or ptr(state+0xae308)~=record or u32(state+L.STATE_VALUE)~=4 then return end
   return ({[2]='terminids',[3]='automatons',[4]='illuminate'})[id]
  end)
  if ok then faction_cache=value end;return faction_cache
 end
 local function session_authority(cleanup)
  local net=ptr(memory.game+L.NET);if not net then return nil,'Host authority unavailable','unknown_session'end
  local peer_bytes=span(net+0xb398,24)
  local local_peer,host_peer=peer_bytes and peer_bytes:sub(1,8)or read(net+0xb398,8),peer_bytes and peer_bytes:sub(17,24)or read(net+0xb3a8,8);local zero=string.rep('\0',8)
  if local_peer==zero then return nil,'Local peer authority unavailable','unknown_session'end
  local N,G=sr.Network,sr.GameSession
  if not(N and G and PORT51.kind(N.game_session)=='function')then return nil,'Solo session reader unavailable','unknown_session'end
  local known,peers,joining=pcall(function()
   local session=N.game_session()
   if session then
    assert(PORT51.kind(G.other_peers)=='function'and PORT51.kind(G.synchronizing_peers)=='function','Session peer reader unavailable')
    return G.other_peers(session),G.synchronizing_peers(session)
   end
   assert(PORT51.kind(N.connections)=='function','Connection reader unavailable');return N.connections(),{}
  end)
  if not known or PORT51.kind(peers)~='table'or PORT51.kind(joining)~='table'then return nil,'Solo player count unavailable','unknown_session'end
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
  assert(PORT51.kind(scene_native)=='number'and scene_native>=65536 and scene_native<2^47,'Enemy scene pointer invalid')
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
  local registry_data=span(registry+0x88,32)
  local capacity=registry_data and word(registry_data,16)or u32(registry+0x98)
  if index>=capacity then return end
  local generations=copied_pointer(registry_data,24,registry+0xa0)
  if read(assert(generations)+index,1):byte()~=generation then return end
  local pointers=copied_pointer(registry_data,0,registry+0x88)
  local object=ptr(assert(pointers)+index*8);if not object then return end
  local object_data=span(object,32)
  local object_world=copied_pointer(object_data,24,object+0x18)
  if object_world~=ctx.scene_native then return end
  local vt=copied_pointer(object_data,0,object);if not vt then return end
  local methods=span(vt+0xc8,56)
  local alive=copied_pointer(methods,48,vt+0xf8)
  local visible=copied_pointer(methods,0,vt+0xc8)
  if alive~=memory.exe+0x28d3c0 or visible~=memory.exe+0x2935e0 then return end
  return ref
 end
 -- Solo Passive owns one player flag, rather than touching every enemy.
 -- Build 6AB3B43F detector candidate and existing-target paths reject bit 25.
 -- Live solo testing confirmed no aggro; this does not disable AI simulation.
 function self.passive_update(ctx,lease,restore)
  assert(valid_context(ctx),'Passive scene or authority changed')
  assert(read(memory.game+0x894a30,6)=='\072\169\000\000\000\006' and
   read(memory.game+0x893015,5)=='\072\015\186\224\025','Passive detector fingerprint changed')
  local mask=0x2000000
  local function row(e)
   local ref=unit(ctx,e);if not ref then return end
   local mgr=ptr(memory.game+0x2ce15e0);if not mgr then return end
   local index=map(mgr+0x18,e);if index==nil then return end
   local list,rows=ptr(mgr+0x30),ptr(mgr+0x38);if not(list and rows)then return end
   local d=ptr(list+index*8);if not d then return end
   local bytes=read(d+8,16);if word(bytes,0)~=e or bytes:byte(13)%2~=1 then return end
   return {entity=e,ref=ref,manager=mgr,descriptor=d,generation=bytes:sub(1,8),at=rows+index*8,identity=ctx.identity}
  end
  local function matches(a,b)return a and a.identity==b.identity and a.ref==b.ref and a.manager==b.manager and a.descriptor==b.descriptor and a.generation==b.generation end
  local function clear()
   if lease.entity then
    local r=lease.identity==ctx.identity and row(lease.entity)
    if matches(r,lease)and lease.owned then
     assert(valid_context(ctx),'Passive cleanup context changed');local fresh=row(lease.entity);assert(matches(fresh,lease),'Passive cleanup owner changed')
     local value=u32(fresh.at);if bit.band(value,mask)~=0 then memory.write(fresh.at,le(bit.band(value,bit.bnot(mask))%4294967296,4));assert(bit.band(u32(fresh.at),mask)==0,'Passive cleanup readback failed')end
    end
   end
   for k in pairs(lease)do lease[k]=nil end
  end
  if restore then clear();return true end
  local player=ptr(memory.game+0x2ce1618);local handle=player and u32(player+0x3a8)
  local index=handle and map(ctx.world+0xf24990,handle);local entity=index and u32(ctx.world+L.WORLD_RECORDS+index*24+8)
  local current=entity and row(entity)
  if lease.entity and(not current or lease.entity~=entity or not matches(current,lease))then clear()end
  assert(current,'Passive player unavailable')
  if not lease.entity then for k,v in pairs(current)do lease[k]=v end;lease.owned=false end
  assert(valid_context(ctx),'Passive authority changed');local fresh=row(entity);assert(matches(fresh,lease),'Passive player changed')
  local value=u32(fresh.at)
  if bit.band(value,mask)==0 then lease.owned=true;memory.write(fresh.at,le(bit.bor(value,mask)%4294967296,4));assert(bit.band(u32(fresh.at),mask)~=0,'Passive apply readback failed')end
  return true
 end
 local function identity(ctx,e,ref)return ctx.identity..':'..e..':'..ref end
 -- Movement ownership belongs to this Unit/AI row. A retired borrowed
 -- detector must not prevent restoring this still-live unit's movement bit.
 function self.observe_restore(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local ai,token=part(ptr(memory.game+L.AI),specs.ai,e);if not ai then return nil,'retired'end
  local values=read(ai,8);if word(values,0)==16 then return nil,'retired'end
  return {kind='movement',entity=e,identity=identity(ctx,e,ref),unit=ref,fields={still={value=word(values,4),address=ai+4,size=4,token=token}}}
 end
 -- A detector can be borrowed by another enemy. Resolve its real owner even
 -- after that borrower dies, without depending on the owner's Behavior row.
 function self.observe_detector(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local copied=managers()
  local ai=part(manager('AI',copied),specs.ai,e);if not ai or u32(ai)==16 then return nil,'retired'end
  local detector,token=part(manager('DETECTOR',copied),specs.detector,e)
  if not detector then return nil,'Enemy detector component unavailable'end
  return {kind='detector',entity=e,identity=identity(ctx,e,ref),unit=ref,fields={detector={value=read(detector+0x13f0,1):byte(),address=detector+0x13f0,size=1,token=token}}}
 end
 function self.observe(ctx,e)
  if not valid_context(ctx)then return nil,'Enemy scene or authority changed'end
  local ref=unit(ctx,e);if not ref then return nil,'retired'end
  local copied=managers()
  local ai,ai_token=part(manager('AI',copied),specs.ai,e);if not ai then return nil,'retired'end
  local ai_values=span(ai,8);if(ai_values and word(ai_values,0)or u32(ai))==16 then return nil,'retired'end
  local invalid=u32(memory.game+L.INVALID);local fields={};local issues={}
  local function field(key,at,size,token,copied)
   local ok,value=pcall(function()if copied~=nil then return copied end;return size==1 and read(at,1):byte()or u32(at)end)
   if ok then fields[key]={value=value,address=at,size=size,token=token}
   else issues[#issues+1]=key..' field unreadable'end
  end
  local function optional_part(key,label)
   local ok,row,token=pcall(function()return part(manager(label,copied),specs[key],e)end)
   if not ok or not row then issues[#issues+1]=key..' component unavailable';return end
   return row,token
  end
  field('still',ai+4,4,ai_token,ai_values and word(ai_values,4))
  local behavior,b_token=optional_part('behavior','BEHAVIOR')
  local owner=e
  if behavior then
   local values=span(behavior+0x18,0x54)
   field('target',behavior+0x18,4,b_token,values and word(values,0))
   local ok,value=pcall(function()return values and word(values,0x50)or u32(behavior+0x68)end)
   if ok and value~=0 and value~=invalid then owner=value end
  end
  local requested_owner=owner
  local function detector_for(entity)
   local owner_ref=ref
   if entity~=e then
    owner_ref=unit(ctx,entity)
    local owner_ai=owner_ref and part(manager('AI',copied),specs.ai,entity)
    if not owner_ref or not owner_ai or u32(owner_ai)==16 then return nil,'Borrowed detector owner retired'end
   end
   local row,token=part(manager('DETECTOR',copied),specs.detector,entity)
   if not row then return nil,'Detector component unavailable'end
   return row,token,owner_ref
  end
  local ok,detector,d_token,owner_ref=pcall(detector_for,owner)
  local owner_issue
  if not ok or not detector then
   owner_issue=ok and d_token or'Borrowed detector owner unreadable'
   -- A stale behavior owner is not permission to write its surviving detector
   -- row. Only fall back to this independently validated live enemy's own row.
   if owner~=e then owner=e;ok,detector,d_token,owner_ref=pcall(detector_for,e)end
  end
  if ok and detector then
   field('detector',detector+0x13f0,1,d_token);field('hostiles',detector+0x310,4,d_token)
   for _,key in ipairs({'detector','hostiles'})do if fields[key]then
    fields[key].owner=owner;fields[key].owner_identity=identity(ctx,owner,owner_ref)
   end end
  else issues[#issues+1]='detector component unavailable'end
  local alert,a_token=optional_part('alert','ALERT');if alert then field('alert',alert,4,a_token)end
  return {entity=e,identity=identity(ctx,e,ref),unit=ref,fields=fields,invalid=invalid,
   partial_issue=#issues>0 and table.concat(issues,'; ')or nil,
   detector_fallback=requested_owner~=e and owner==e and fields.detector~=nil,
   detector_owner_issue=owner_issue}
 end
 local function write_field(ctx,record,key,value,expected,cleanup)
  local committed=false;local verified
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
   assert(PORT51.kind(value)=='number'and value==math.floor(value)and value>=0 and value<2^(8*field.size),'Invalid enemy field value')
   memory.write(field.address,le(value,field.size));committed=true
   local after=observe(ctx,record.entity);assert(after and after.identity==record.identity and after.fields[key]and after.fields[key].token==field.token and after.fields[key].owner_identity==field.owner_identity and after.fields[key].value==value,'Enemy write readback changed')
   verified=after
  end)
  return ran,not ran and tostring(why)or nil,committed,ran and verified or nil
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

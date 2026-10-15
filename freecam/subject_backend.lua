-- Exact local avatar render references; never fabricate engine Unit arguments.
-- Ownership layout follows the maintained Epic LUT avatar/Unit identity adapter.
local M={}
local function native_memory()
 local ffi=require('ffi');local util=require('jit.util')
 pcall(ffi.cdef,[[void *FSB_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void *FSB_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FSB_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local process=kernel.FSB_GetCurrentProcess();local buffer=ffi.new('uint8_t[256]');local got=ffi.new('size_t[1]')
 local memory={game=tonumber(ffi.cast('uintptr_t',kernel.FSB_GetModuleHandleA('game.dll'))),exe=tonumber(ffi.cast('uintptr_t',kernel.FSB_GetModuleHandleA(nil)))}
 function memory.read(address,size)
  assert(kernel.FSB_ReadProcessMemory(process,ffi.cast('void*',address),buffer,size,got)~=0 and tonumber(got[0])==size,'Subject read unavailable')
  return ffi.string(buffer,size)
 end
 function memory.function_address(fn)return util.funcinfo(fn).addr end
 function memory.handle_ref(handle)return math.floor(tonumber(ffi.cast('uintptr_t',handle))/4)end
 function memory.world_address(world)
  local address=tonumber(ffi.cast('uintptr_t',world))
  assert(kernel.FSB_ReadProcessMemory(process,ffi.cast('void*',address),buffer,8,got)~=0 and tonumber(got[0])==8,'Subject world unavailable')
  local s=ffi.string(buffer,8);local function u(o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
  return u(0)+u(4)*4294967296
 end
 return memory
end
function M.new(sr,memory)
 memory=memory or native_memory();local game,exe=memory.game,memory.exe
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=256,'Subject read bounds changed')
  local bytes=memory.read(address,size);assert(type(bytes)=='string'and#bytes==size,'Subject read unavailable');return bytes
 end
 local function word(address)local s=read(address,4);return s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216 end
 local function ptr(address)local s=read(address,8);local low=s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216;local high=s:byte(5)+s:byte(6)*256+s:byte(7)*65536+s:byte(8)*16777216;return low+high*4294967296 end
 local function image(base,stamp)
  local pe=word(base+60);assert(pe>=64 and pe<1048576 and read(base+pe,4)=='PE\0\0'and word(base+pe+8)==stamp,'Subject game build unsupported')
 end
 image(game,0x6ab3b43f);image(exe,0x6ab382e4)
 assert(sr.Application and sr.World and sr.Unit and type(sr.World.units)=='function','Subject Unit API unavailable')
 assert(memory.function_address(sr.Unit.set_mesh_visibility)==exe+0x4128e0 and read(exe+0x4128e0,8)=='\x48\x8b\xd1\xe9\xe8\xfb\xff\xff','Subject visibility binding changed')
 assert(read(exe+0x50f620,14)=='\x40\x57\x48\x83\xec\x30\x44\x0f\xb6\x89\xdc\x00\x00\x00','Subject mesh visibility layout changed')
 assert(read(exe+0x9d8c0,22)=='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01','Subject Unit registry changed')
 -- Verified Unit children getter: first child +1D8, next sibling +1E0.
 -- Read the list directly; the game's Lua is_child binding drops its result.
 assert(read(exe+0x2beb90,17)=='\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x20\x48\x8d\xb9\xd8\x01\x00\x00'
  and read(exe+0x2bebf5,12)=='\x48\x8b\x3f\x8b\x13\x48\x81\xc7\xe0\x01\x00\x00','Subject attachment layout changed')
 local function lookup(owner,offset,key,limit)
  local data=ptr(owner+offset);local cap=word(owner+offset+8);local empty=word(owner+offset+12);local seed=word(owner+offset+16)
  assert(cap>0 and cap<=4194304,'Subject owner map bounds changed')
  local low=key%65536;local hash=(low*seed+(((key-low)/65536*seed)%65536)*65536)%4294967296
  for i=0,math.min(cap,64)-1 do local at=data+((hash+i)%cap)*8;local found=word(at)
   if found==key then local index=word(at+4);assert(index<limit,'Subject owner map index changed');return index end
   if found==empty then break end
  end
 end
 local function native(ref)
  assert(type(ref)=='number'and ref>0 and ref<4294967295,'Subject render reference invalid')
  local registry=ptr(exe+0x1a100f0);local index=ref%4194304;local generation=math.floor(ref/4194304)
  assert(index<word(registry+0x98)and read(ptr(registry+0xa0)+index,1):byte()==generation,'Subject Unit generation retired')
  local unit=ptr(ptr(registry+0x88)+index*8);local vt=ptr(unit)
  assert(ptr(vt+0xf8)==exe+0x2bd890 and ptr(vt+0xc8)==exe+0x2c3990 and ptr(vt+0x1e8)==exe+0x2beb90 and word(unit+8)==ref,'Subject Unit renderer type changed')
  return unit
 end
 local root_cache;local self={}
 local carried,chain_link_valid
 local function locate(part,mesh)
  assert(native(part.ref)==part.native and ptr(part.native+0x18)==part.world_native,'Subject Unit owner changed')
  local count=word(part.native+0xc8);assert(count<=512,'Subject mesh count changed');local meshes=ptr(part.native+0xd0)
  local expected=part.mesh_objects and part.mesh_objects[mesh];assert(expected,'Subject mesh identity unavailable')
  if mesh<=count and ptr(meshes+(mesh-1)*16)==expected then return expected,mesh end
  -- Mesh array replacement/reordering does not change ownership of an object
  -- still listed by the same generation-checked Unit. Never dereference an old
  -- array or restore visibility on a replacement object at the old index.
  local found
  for i=1,count do if ptr(meshes+(i-1)*16)==expected then assert(not found,'Subject mesh identity ambiguous');found=i end end
  return found and expected or nil,found
 end
 function self.valid(part,mesh)
  local ok,value=pcall(function()
   if mesh then return locate(part,mesh)~=nil end
   return native(part.ref)==part.native and ptr(part.native+0x18)==part.world_native
  end)
  if not ok then
   local why=tostring(value)
   if why:find('Subject Unit generation retired',1,true)or why:find('Subject Unit owner changed',1,true)then return false end
   return nil,why -- Unknown read failure must retain restoration ownership.
  end
  return value==true
 end
 function self.read(part,mesh)
  assert(mesh>=1 and mesh<=part.mesh_count,'Subject mesh owner changed')
  local object=assert(locate(part,mesh),'Subject mesh retired');return read(object+0xdc,1):byte()
 end
 function self.write(part,mesh,value)
  assert(mesh>=1 and mesh<=part.mesh_count and type(value)=='boolean','Subject visibility owner changed')
  local object,index=locate(part,mesh);assert(object and index,'Subject mesh retired')
  if not value then assert(self.owned(part),'Subject attachment ownership changed')end
  sr.Unit.set_mesh_visibility(part.handle,index,value)
 end
 local function owner()
  local players=ptr(game+0x3326468);local count=word(players+132);assert(count>0 and count<=8,'Local player unavailable')
  local player
  for i=0,count-1 do local record=ptr(players+232+i*8)
   if word(record+20)%2==1 then assert(not player,'Local player ownership ambiguous');player=word(record+8)end
  end
  assert(player,'Local player unavailable');local pi=assert(lookup(players,208,player,8),'Local player not indexed');local game_ref=word(players+936+pi*32)
  local entities=ptr(game+0x346bf98);local ei=assert(lookup(entities,0xf22ec8,game_ref,4194304),'Local avatar unavailable');local at=entities+0xf32f18+ei*24
  assert(word(at)==0x294dfa97 and word(at+4)==0x4d1c334d and word(at+20)%2==1,'Current local Helldiver ownership required')
  return{players=players,player=player,game_ref=game_ref,entities=entities,avatar=word(at+8),root=word(at+12)}
 end
 local function owner_key(value)return table.concat({value.players,value.player,value.game_ref,value.avatar,value.root},':')end
 function self.owned(part)
  local ok,result=pcall(function()
   if owner_key(owner())~=part.owner_key or not self.valid(part)then return false end
   if part.chain_link and not chain_link_valid(part.chain_link)then return false end
   for _,link in ipairs(part.attachment_path or{})do
    if native(link.ref)~=link.native or native(link.parent_ref)~=link.parent or ptr(link.native+0x1d0)~=link.parent then return false end
   end
   return true
  end)
  return ok and result==true
 end
 carried=function(local_player)
  local result={};local inventory=ptr(game+0x3326738);local ii=lookup(inventory,40,local_player.avatar,4194304)
  if ii then
   local row=ptr(inventory+80)+ii*48
   for _,offset in ipairs({0,4,8,12,16})do
    local entity=word(row+offset)
    if entity~=0 and entity~=4294967295 then
     local index=lookup(local_player.entities,0xf1aeb0,entity,4194304)
     if index then
      local record=local_player.entities+0xf32f18+index*24
      assert(word(record+8)==entity and word(record+20)%2==1,'Carried equipment identity changed')
      result[entity]={ref=word(record+12),weapon=offset~=12}
     end
    end
   end
  end
  return result
 end
 local function chain_manager()
  -- Verified separately from Unit child attachments: ammunition feeds are
  -- independent TwoPointChain Units owned by two carried equipment entities.
  local manager=ptr(game+0x3326b88)
  if manager==0 then return end
  assert(read(game+0x8c75fa,7)=='\x48\x8b\x1d\x87\xf5\xa5\x02'
   and read(game+0x8c7623,20)=='\x44\x8b\x43\x0c\x0f\x57\xc0\x33\xc9\x49\x69\xc0\x9c\x00\x00\x00\x48\x03\x43\x38'
   and read(game+0x8c7676,22)=='\x48\x8b\x43\x30\x0f\x47\x4b\x04\x89\x4b\x04\x48\x8d\x4b\x18\x4a\x89\x3c\xc0\x8b\x57\x08'
   and read(game+0x8c6eb9,25)=='\x44\x8b\x49\x20\x44\x8b\x51\x28\x44\x0f\xaf\xd2\x41\x8d\x79\xff\x45\x85\xc9\x74\x33\x4c\x8b\x59\x18'
   and read(game+0x8c567f,4)=='\x41\x89\x5f\x04','Subject chain layout changed')
  assert(manager>=65536 and manager<2^47,'Subject chain manager unavailable')
  local capacity,count=word(manager),word(manager+8)
  assert(capacity>0 and capacity<=384 and count<=capacity,'Subject chain bounds changed')
  return manager,count
 end
 chain_link_valid=function(link)
  local equipment=carried(owner());local source,target=equipment[link.owner_entity],equipment[link.target_entity]
  if not source or not target or source.ref~=link.owner_ref or target.ref~=link.target_ref then return false end
  if native(source.ref)~=link.owner_native or native(target.ref)~=link.target_native
   or ptr(link.owner_native+0x18)~=link.world_native or ptr(link.target_native+0x18)~=link.world_native then return false end
  local manager,count=chain_manager();if manager~=link.manager then return false end
  local index=lookup(manager,0x18,link.owner_entity,count)
  if index==nil then return false end
  local descriptor=ptr(ptr(manager+0x30)+index*8);local row=ptr(manager+0x38)+index*0x9c
  return descriptor==link.descriptor and word(descriptor+20)%2==1 and word(descriptor+8)==link.owner_entity and word(descriptor+12)==link.owner_ref
   and word(row)==link.ref and word(row+4)==link.target_entity
 end
 function self.frame()
  local local_player=owner();local ref=local_player.root;local world=sr.Application.main_world();assert(world,'Local player world unavailable')
  local world_native=memory.world_address(world);local unit=native(ref);assert(ptr(unit+0x18)==world_native,'Local player world changed')
  local identity=table.concat({local_player.players,local_player.player,local_player.game_ref,local_player.avatar,world_native,ref},':')
  if not root_cache or root_cache.identity~=identity or root_cache.native~=unit then
   local handle;local units=sr.World.units(world);assert(type(units)=='table'and #units<=131072,'Local player Unit list changed')
   for _,candidate in ipairs(units)do
    local ok,value=pcall(memory.handle_ref,candidate)
    if ok and value==ref then assert(not handle,'Local player Unit reference ambiguous');handle=candidate end
   end
   root_cache={identity=identity,native=unit,handle=assert(handle,'Local player render handle unavailable')}
  end
  assert(type(sr.Unit.world_pose)=='function'and sr.Matrix4x4 and sr.Vector3,'Local player transform API unavailable')
  local pose=sr.Unit.world_pose(root_cache.handle,1);local point=sr.Matrix4x4.translation(pose);local forward=sr.Matrix4x4.forward(pose)
  local V=sr.Vector3;local x,y=V.x(forward),V.y(forward);assert(x*x+y*y>.000001,'Local player facing unavailable')
  local position={V.x(point),V.y(point),V.z(point)}
  for i=1,3 do assert(type(position[i])=='number'and position[i]==position[i]and math.abs(position[i])<1e8,'Local player transform invalid')end
  assert(native(ref)==unit and ptr(unit+0x18)==world_native,'Local player retired during transform read')
  return{local_owner=true,identity=identity,owner_key=owner_key(local_player),position=position,yaw=math.atan2(y,x),root_ref=ref,root_handle=root_cache.handle,world=world}
 end
 -- The public bone-mode getter dereferences Unit+168 without a null check.
 -- This is distinct from the animation state machine at Unit+178.
 local function pose_component(unit)
  assert(ptr(ptr(unit)+0x1a8)==exe+0x2bd9a0 and read(exe+0x2bd9a0,8)=='\x48\x8b\x81\x68\x01\x00\x00\xc3','Subject bone component layout changed')
  local component=ptr(unit+0x168)
  assert(component>=65536 and component<2^47,'Subject bone component unavailable')
  assert(word(component+0x284)<=7,'Subject bone transfer mode changed')
  return component
 end
 function self.pose_frame()
  local frame=self.frame();local unit=native(frame.root_ref)
  assert(memory.function_address(sr.Unit.animation_bone_mode)==exe+0x410470
   and memory.function_address(sr.Unit.set_animation_bone_mode)==exe+0x410700,'Subject bone mode binding changed')
  frame.native=unit;frame.component=pose_component(unit);frame.world_native=ptr(unit+0x18)
  assert(frame.owner_key==owner_key(owner()),'Subject pose owner changed during lookup');return frame
 end
 function self.pose_valid(frame,require_owner)
  local ok,result=pcall(function()
   local unit=native(frame.root_ref)
   if unit~=frame.native or ptr(unit+0x18)~=frame.world_native or ptr(unit+0x168)~=frame.component then return false end
   if require_owner and owner_key(owner())~=frame.owner_key then return false end
   return pose_component(unit)==frame.component
  end)
  if not ok then
   if tostring(result):find('Subject Unit generation retired',1,true)then return false end
   return nil,tostring(result)
  end
  return result
 end
 function self.ragdoll_frame()
  -- Native avatar telemetry names this exact bit avatar_ragdoll_active.
  -- Validate lazily so unrelated subject controls do not depend on this layout.
  assert(read(game+0x8e327d,7)=='\x4c\x8b\x3d\x9c\x3a\xa4\x02'
   and read(game+0x8e34a7,4)=='\x4c\x6b\xe9\x78'
   and read(game+0x8e3608,8)=='\x4b\x8b\x84\x2f\x40\x78\x54\x00'
   and read(game+0x8e3610,11)=='\x4c\x8d\x05\xf9\x8f\x96\x01\x48\xc1\xe8\x24'
   and read(game+0x8e361e,3)=='\x83\xe0\x01'
   and read(game+0x224c610,22)=='avatar_ragdoll_active\0','Subject ragdoll layout changed')
  local frame=self.pose_frame();local current=owner()
  assert(frame.owner_key==owner_key(current),'Subject ragdoll owner changed during lookup')
  local avatars=ptr(game+0x3326d20)
  assert(avatars>=65536 and avatars<2^47,'Subject ragdoll manager unavailable')
  local capacity=word(avatars+0x6c)
  assert(capacity>0 and capacity<=4096,'Subject ragdoll bounds changed')
  local index=assert(lookup(avatars,0xf8,current.avatar,capacity),'Subject ragdoll avatar unavailable')
  local descriptor=ptr(avatars+0x110+index*8);local record=read(descriptor,24)
  assert(word(descriptor)==0x294dfa97 and word(descriptor+4)==0x4d1c334d
   and word(descriptor+8)==current.avatar and word(descriptor+12)==frame.root_ref
   and record:byte(21)%2==1,'Subject ragdoll component owner changed')
  local address=avatars+0x547840+index*0x78;local flags=read(address,8)
  -- Read byte 4 rather than a Lua double containing a 64-bit bitset: higher
  -- active flags must not round away the ragdoll bit at position 36.
  local active=math.floor(flags:byte(5)/16)%2==1
  assert(self.pose_valid(frame,true)==true and owner_key(owner())==frame.owner_key
   and ptr(game+0x3326d20)==avatars and word(avatars+0x6c)==capacity
   and lookup(avatars,0xf8,current.avatar,capacity)==index
   and ptr(avatars+0x110+index*8)==descriptor and read(descriptor,24)==record
   and read(address,8)==flags,'Subject ragdoll owner changed during readback')
  frame.ragdoll=active;frame.ragdoll_active=active
  frame.avatar_manager=avatars;frame.avatar_index=index;frame.ragdoll_descriptor=descriptor
  return frame
 end
 function self.resolve()
  local local_player=owner();local players,player,game_ref,entities,avatar,root=local_player.players,local_player.player,local_player.game_ref,local_player.entities,local_player.avatar,local_player.root
  local avatars=ptr(game+0x3326d20);local ai=assert(lookup(avatars,248,avatar,word(avatars+0x6c)),'Local avatar renderer unavailable')
  local clothes=read(avatars+5532272+ai*440+220,120);local refs={};local groups={hide_player={},hide_armour={},hide_weapons={}}
  local function add(ref,group)
   if ref==0 or ref==4294967295 then return end
   refs[ref]=true;group[#group+1]=ref
  end
  add(root,groups.hide_player)
  for offset=0,116,4 do local a,b,c,d=clothes:byte(offset+1,offset+4);local ref=a+b*256+c*65536+d*16777216;add(ref,groups.hide_armour);add(ref,groups.hide_player)end
  local world=sr.Application.main_world();assert(world,'Subject world unavailable');local world_native=memory.world_address(world)
  local equipment=carried(local_player)
  for _,item in pairs(equipment)do if item.weapon then add(item.ref,groups.hide_weapons)end;add(item.ref,groups.hide_player)end
  local chain_links={};local manager,count=chain_manager()
  if manager then
   for entity,item in pairs(equipment)do
    local index=lookup(manager,0x18,entity,count)
    if index~=nil then
     local descriptor=ptr(ptr(manager+0x30)+index*8);local row=ptr(manager+0x38)+index*0x9c
     assert(word(descriptor+8)==entity and word(descriptor+12)==item.ref,'Subject chain equipment owner changed')
     local target_entity=word(row+4);local target=equipment[target_entity];local ref=word(row)
     if word(descriptor+20)%2==1 and target and ref~=0 and ref~=4294967295 then
      local owner_native,target_native=native(item.ref),native(target.ref)
      assert(ptr(owner_native+0x18)==world_native and ptr(target_native+0x18)==world_native,'Subject chain endpoint world changed')
      chain_links[ref]={manager=manager,index=index,descriptor=descriptor,owner_entity=entity,owner_ref=item.ref,target_entity=target_entity,target_ref=target.ref,ref=ref,owner_native=owner_native,target_native=target_native,world_native=world_native}
      add(ref,groups.hide_player);if item.weapon or target.weapon then add(ref,groups.hide_weapons)end
     end
    end
   end
  end
  local graph,paths,visiting={},{},{};local total=0
  local function walk(ref,depth,path)
   assert(depth<=16 and not visiting[ref],'Subject attachment depth/cycle changed')
   if graph[ref]then return end
   total=total+1;assert(total<=256,'Subject attachment count changed')
   local unit=native(ref);assert(ptr(unit+0x18)==world_native,'Subject attachment world changed')
   visiting[ref]=true;graph[ref]={};paths[ref]=path
   local first=ptr(unit+0x1d8);local child=first;local seen={}
   while child~=0 do
    assert(not seen[child],'Subject sibling cycle changed');seen[child]=true
    local child_ref=word(child+8)
    assert(native(child_ref)==child and ptr(child+0x1d0)==unit,'Subject attachment parent/reference changed')
    local sibling=ptr(child+0x1e0);graph[ref][#graph[ref]+1]=child_ref;refs[child_ref]=true
    local chain={};for i,link in ipairs(path)do chain[i]=link end
    chain[#chain+1]={ref=child_ref,native=child,parent_ref=ref,parent=unit}
    walk(child_ref,depth+1,chain)
    assert(ptr(child+0x1e0)==sibling and ptr(child+0x1d0)==unit,'Subject attachment changed during lookup')
    child=sibling
   end
   assert(ptr(unit+0x1d8)==first,'Subject child list changed during lookup');visiting[ref]=nil
  end
  local roots={};for ref in pairs(refs)do roots[#roots+1]=ref end
  walk(root,0,{})
  for _,ref in ipairs(roots)do walk(ref,0,{})end
  for name,items in pairs(groups)do
   local out,seen={},{}
   local function include(ref)
    if seen[ref]then return end;seen[ref]=true;out[#out+1]=ref
    for _,child in ipairs(graph[ref])do include(child)end
   end
   for _,ref in ipairs(items)do include(ref)end;groups[name]=out
  end
  assert(owner_key(owner())==owner_key(local_player),'Subject local owner changed during lookup')
  local keys={};for ref in pairs(refs)do keys[#keys+1]=ref end;table.sort(keys)
  local identity=table.concat({players,player,game_ref,avatar,world_native,table.concat(keys,',')},':')
  local units=sr.World.units(world);assert(type(units)=='table'and #units<=131072,'Subject world Unit list changed');local handles={}
  for _,handle in ipairs(units)do
   local ok,value=pcall(memory.handle_ref,handle)
   if ok and refs[value]then assert(not handles[value],'Subject Unit reference ambiguous');handles[value]=handle end
  end
  local parts={}
  for ref in pairs(refs)do
   local handle=assert(handles[ref],'Local subject render handle unavailable');local unit=native(ref);assert(ptr(unit+0x18)==world_native,'Local subject world changed')
   local n=word(unit+0xc8);assert(n>=0 and n<=512,'Subject mesh count changed');local meshes=ptr(unit+0xd0);local objects={}
   for mesh=1,n do objects[mesh]=ptr(meshes+(mesh-1)*16);assert(objects[mesh]>=65536 and objects[mesh]<2^47,'Subject mesh object invalid')end
   parts[ref]={identity=table.concat({world_native,ref,unit},':'),ref=ref,handle=handle,native=unit,mesh_count=n,meshes=meshes,mesh_objects=objects,world_native=world_native,
    owner_key=owner_key(local_player),attachment_path=paths[ref],chain_link=chain_links[ref]}
  end
  for group,items in pairs(groups)do local out,seen={},{};for _,ref in ipairs(items)do if not seen[ref]then out[#out+1]=parts[ref];seen[ref]=true end end;groups[group]=out end
  return{local_owner=true,identity=identity,groups=groups}
 end
 return self
end
return M

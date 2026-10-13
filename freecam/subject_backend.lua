-- Exact local avatar render references; never fabricate engine Unit arguments.
-- Ownership layout follows the maintained Epic LUT avatar/Unit identity adapter.
local M={}
function M.new(sr)
 local ffi=require('ffi');local util=require('jit.util')
 pcall(ffi.cdef,[[void *FSB_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void *FSB_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FSB_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local process=kernel.FSB_GetCurrentProcess();local buffer=ffi.new('uint8_t[256]');local got=ffi.new('size_t[1]')
 local game=tonumber(ffi.cast('uintptr_t',kernel.FSB_GetModuleHandleA('game.dll')));local exe=tonumber(ffi.cast('uintptr_t',kernel.FSB_GetModuleHandleA(nil)))
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=256,'Subject read bounds changed')
  assert(kernel.FSB_ReadProcessMemory(process,ffi.cast('void*',address),buffer,size,got)~=0 and tonumber(got[0])==size,'Subject read unavailable')
  return ffi.string(buffer,size)
 end
 local function word(address)local s=read(address,4);return s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216 end
 local function ptr(address)local s=read(address,8);local low=s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216;local high=s:byte(5)+s:byte(6)*256+s:byte(7)*65536+s:byte(8)*16777216;return low+high*4294967296 end
 local function image(base,stamp)
  local pe=word(base+60);assert(pe>=64 and pe<1048576 and read(base+pe,4)=='PE\0\0'and word(base+pe+8)==stamp,'Subject game build unsupported')
 end
 image(game,0x6ab3b43f);image(exe,0x6ab382e4)
 assert(sr.Application and sr.World and sr.Unit and type(sr.World.units)=='function','Subject Unit API unavailable')
 assert(util.funcinfo(sr.Unit.set_mesh_visibility).addr==exe+0x4128e0 and read(exe+0x4128e0,8)=='\x48\x8b\xd1\xe9\xe8\xfb\xff\xff','Subject visibility binding changed')
 assert(read(exe+0x50f620,14)=='\x40\x57\x48\x83\xec\x30\x44\x0f\xb6\x89\xdc\x00\x00\x00','Subject mesh visibility layout changed')
 assert(read(exe+0x9d8c0,22)=='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01','Subject Unit registry changed')
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
  assert(ptr(vt+0xf8)==exe+0x2bd890 and ptr(vt+0xc8)==exe+0x2c3990,'Subject Unit renderer type changed')
  return unit
 end
 local cached;local root_cache;local self={}
 function self.valid(part)
  local ok,value=pcall(function()return native(part.ref)==part.native and ptr(part.native+0x18)==part.world_native and word(part.native+0xc8)==part.mesh_count and ptr(part.native+0xd0)==part.meshes end)
  return ok and value==true
 end
 function self.read(part,mesh)
  assert(self.valid(part)and mesh>=1 and mesh<=part.mesh_count,'Subject mesh owner changed')
  local object=ptr(part.meshes+(mesh-1)*16);return read(object+0xdc,1):byte()
 end
 function self.write(part,mesh,value)
  assert(self.valid(part)and mesh>=1 and mesh<=part.mesh_count and type(value)=='boolean','Subject visibility owner changed')
  sr.Unit.set_mesh_visibility(part.handle,mesh,value)
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
 function self.frame()
  local local_player=owner();local ref=local_player.root;local world=sr.Application.main_world();assert(world,'Local player world unavailable')
  local world_native=ptr(tonumber(ffi.cast('uintptr_t',world)));local unit=native(ref);assert(ptr(unit+0x18)==world_native,'Local player world changed')
  local identity=table.concat({local_player.players,local_player.player,local_player.game_ref,local_player.avatar,world_native,ref},':')
  if not root_cache or root_cache.identity~=identity or root_cache.native~=unit then
   local handle;local units=sr.World.units(world);assert(type(units)=='table'and #units<=131072,'Local player Unit list changed')
   for _,candidate in ipairs(units)do
    local ok,value=pcall(function()return math.floor(tonumber(ffi.cast('uintptr_t',candidate))/4)end)
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
  return{local_owner=true,identity=identity,position=position,yaw=math.atan2(y,x),root_ref=ref,root_handle=root_cache.handle,world=world}
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
  local inventory=ptr(game+0x3326738);local ii=lookup(inventory,40,avatar,4194304)
  if ii then
   local row=ptr(inventory+80)+ii*48
   for _,offset in ipairs({0,4,8,16})do
    local entity=word(row+offset)
    if entity~=0 and entity~=4294967295 then
     local index=lookup(entities,0xf1aeb0,entity,4194304)
     if index then local record=entities+0xf32f18+index*24;assert(word(record+8)==entity,'Carried weapon identity changed');local ref=word(record+12);add(ref,groups.hide_weapons);add(ref,groups.hide_player)end
    end
   end
  end
  local world=sr.Application.main_world();assert(world,'Subject world unavailable');local world_native=ptr(tonumber(ffi.cast('uintptr_t',world)))
  local keys={};for ref in pairs(refs)do keys[#keys+1]=ref end;table.sort(keys)
  local identity=table.concat({players,player,game_ref,avatar,world_native,table.concat(keys,',')},':')
  if cached and cached.identity==identity then return cached end
  local units=sr.World.units(world);assert(type(units)=='table'and #units<=131072,'Subject world Unit list changed');local handles={}
  for _,handle in ipairs(units)do
   local ok,value=pcall(function()return math.floor(tonumber(ffi.cast('uintptr_t',handle))/4)end)
   if ok and refs[value]then assert(not handles[value],'Subject Unit reference ambiguous');handles[value]=handle end
  end
  local parts={}
  for ref in pairs(refs)do
   local handle=assert(handles[ref],'Local subject render handle unavailable');local unit=native(ref);assert(ptr(unit+0x18)==world_native,'Local subject world changed')
   local n=word(unit+0xc8);assert(n>=0 and n<=512,'Subject mesh count changed');parts[ref]={identity=world_native..':'..ref,ref=ref,handle=handle,native=unit,mesh_count=n,meshes=ptr(unit+0xd0),world_native=world_native}
  end
  for group,items in pairs(groups)do local out,seen={},{};for _,ref in ipairs(items)do if not seen[ref]then out[#out+1]=parts[ref];seen[ref]=true end end;groups[group]=out end
  cached={local_owner=true,identity=identity,groups=groups};return cached
 end
 return self
end
return M

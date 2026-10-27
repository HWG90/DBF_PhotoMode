
-- Exact local avatar render references; never fabricate engine Unit arguments.
-- Ownership layout follows the maintained Epic LUT avatar/Unit identity adapter.
local M={pause_gate=true}
local function native_memory()return mod.require('src/host_native.lua').memory()end
-- Little-endian IEEE-754 single from bytes; infinities and NaN read as NaN.
function M.f32(s,at)
 local a,b,c,d=s:byte(at+1,at+4)
 local sign=d>=128 and -1 or 1;local exponent=(d%128)*2+math.floor(c/128);local mantissa=(c%128)*65536+b*256+a
 if exponent==255 then return 0/0 end
 if exponent==0 then return sign*math.ldexp(mantissa,-149)end
 return sign*math.ldexp(mantissa+8388608,exponent-150)
end

function M.new(sr,memory)
 memory=memory or native_memory();local game,exe=memory.game,memory.exe
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=256,'Subject read bounds changed')
  local bytes=memory.read(address,size);assert(type(bytes)=='string'and#bytes==size,'Subject read unavailable');return bytes
 end
 -- Code witnesses tolerate packed pages of this hash-verified build (host_native).
 local function code(address,bytes)if memory.code then return memory.code(address,bytes)end;return read(address,#bytes)==bytes end
 local function word(address)local s=read(address,4);return s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216 end
 local function ptr(address)local s=read(address,8);local low=s:byte(1)+s:byte(2)*256+s:byte(3)*65536+s:byte(4)*16777216;local high=s:byte(5)+s:byte(6)*256+s:byte(7)*65536+s:byte(8)*16777216;return low+high*4294967296 end
 local function image(base,stamp)
  local pe=word(base+60);assert(pe>=64 and pe<1048576 and read(base+pe,4)=='PE\0\0'and word(base+pe+8)==stamp,'Subject game build unsupported')
 end
 image(game,0x6ad7c05d);image(exe,0x6ad78c0d)
 assert(sr.Application and sr.World and sr.Unit and type(sr.World.units)=='function','Subject Unit API unavailable')
 assert(memory.function_address(sr.Unit.set_mesh_visibility)==exe+0x3f4c80 and code(exe+0x3f4c80,'\072\139\209\233\168\248\255\255'),'Subject visibility binding changed')
 assert(code(exe+0x51fe50,'\064\087\072\131\236\048\068\015\182\137\220\000\000\000'),'Subject mesh visibility layout changed')
 assert(code(exe+0xa06b0,'\072\137\092\036\008\072\137\116\036\016\087\072\131\236\032\072\139\053\050\112\161\001'),'Subject Unit registry changed')
 -- Verified Unit children getter: first child +1D8, next sibling +1E0.
 -- Read the list directly; the game's Lua is_child binding drops its result.
 assert(code(exe+0x28e6e0,'\072\137\092\036\016\087\072\131\236\032\072\141\185\216\001\000\000')
  and code(exe+0x28e745,'\072\139\063\139\019\072\129\199\224\001\000\000'),'Subject attachment layout changed')
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
  local registry=ptr(exe+0x1ab76f8);local index=ref%4194304;local generation=math.floor(ref/4194304)
  assert(index<word(registry+0x98)and read(ptr(registry+0xa0)+index,1):byte()==generation,'Subject Unit generation retired')
  local unit=ptr(ptr(registry+0x88)+index*8);local vt=ptr(unit)
  assert(ptr(vt+0xf8)==exe+0x28d3c0 and ptr(vt+0xc8)==exe+0x2935e0 and ptr(vt+0x1e8)==exe+0x28e6e0 and word(unit+8)==ref,'Subject Unit renderer type changed')
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
  local players=ptr(game+0x2ce1618);local count=word(players+132);assert(count>0 and count<=8,'Local player unavailable')
  local player
  for i=0,count-1 do local record=ptr(players+232+i*8)
   if word(record+20)%2==1 then assert(not player,'Local player ownership ambiguous');player=word(record+8)end
  end
  assert(player,'Local player unavailable');local pi=assert(lookup(players,208,player,8),'Local player not indexed');local game_ref=word(players+936+pi*32)
  local entities=ptr(game+0x2ce41b8);local ei=assert(lookup(entities,0xf24990,game_ref,4194304),'Local avatar unavailable');local at=entities+0xf349e0+ei*24
  assert(word(at)==0x294dfa97 and word(at+4)==0x4d1c334d and word(at+20)%2==1,'Current local Helldiver ownership required')
  return{players=players,player=player,game_ref=game_ref,entities=entities,avatar=word(at+8),root=word(at+12)}
 end
 local function owner_key(value)return table.concat({value.players,value.player,value.game_ref,value.avatar,value.root},':')end
 -- Numeric proof for a previously discovered genuine SDK handle. Never
 -- constructs a handle or invokes a Unit API before registry/world validation.
 function self.unit_lifetime(handle,world)
  local ok,value=pcall(function()
   local unit=native(memory.handle_ref(handle))
   if ptr(unit+0x18)~=memory.world_address(world)then return false end
   return unit
  end)
  if ok then return value end
  if tostring(value):find('Subject Unit generation retired',1,true)then return false end
  return nil,tostring(value)
 end
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
  local result={};local inventory=ptr(game+0x2ce18e8);local ii=lookup(inventory,40,local_player.avatar,4194304)
  if ii then
   local row=ptr(inventory+80)+ii*48
   for _,offset in ipairs({0,4,8,12,16})do
    local entity=word(row+offset)
    if entity~=0 and entity~=4294967295 then
     local index=lookup(local_player.entities,0xf1c978,entity,4194304)
     if index then
      local record=local_player.entities+0xf349e0+index*24
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
  local manager=ptr(game+0x2ce1d48)
  if manager==0 then return end
  assert(code(game+0x8d76ba,'\072\139\029\135\166\064\002')
   and code(game+0x8d76e3,'\068\139\067\012\015\087\192\051\201\073\105\192\156\000\000\000\072\003\067\056')
   and code(game+0x8d7736,'\072\139\067\048\015\071\075\004\137\075\004\072\141\075\024\074\137\060\192\139\087\008')
   ,'Subject chain constructor layout changed')
  assert(manager>=65536 and manager<2^47,'Subject chain manager unavailable')
  local capacity,count=word(manager),word(manager+8)
  assert(capacity>0 and capacity<=384 and count<=capacity,'Subject chain bounds changed')
  if count==0 then return manager,count end
  assert(code(game+0x8c6eb9,'\068\139\073\032\068\139\081\040\068\015\175\210\065\141\121\255\069\133\201\116\051\076\139\089\024')
   and code(game+0x8c567f,'\065\137\095\004'),'Subject chain layout changed')
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
 -- Equipment has no supported change notification in this adapter. A bounded
 -- half-second topology check replaces repeated world discovery and mesh masks.
 -- Every cached native address is generation-checked before dereferencing it.
 local function topology(parts)
  local player=owner();local key={owner_key(player)}
  local world=assert(sr.Application.main_world(),'Subject world unavailable')
  key[#key+1]=tostring(memory.world_address(world))
  local avatars=ptr(game+0x2ce1ee0);local ai=assert(lookup(avatars,248,player.avatar,word(avatars+0x6c)),'Local avatar renderer unavailable')
  key[#key+1]=read(avatars+0x546ab0+ai*440+220,120)
  local equipment=carried(player);local entities={};for entity in pairs(equipment)do entities[#entities+1]=entity end;table.sort(entities)
  local manager,count=chain_manager();key[#key+1]=tostring(manager or 0);key[#key+1]=tostring(count or 0)
  for _,entity in ipairs(entities)do
   local item=equipment[entity];key[#key+1]=table.concat({entity,item.ref,tostring(item.weapon)},':')
   if manager then
    local index=lookup(manager,0x18,entity,count)
    if index~=nil then
     local descriptor=ptr(ptr(manager+0x30)+index*8);local row=ptr(manager+0x38)+index*0x9c
     key[#key+1]=tostring(descriptor);key[#key+1]=read(descriptor+8,16);key[#key+1]=read(row,8)
    end
   end
  end
  local refs={};for ref in pairs(parts)do refs[#refs+1]=ref end;table.sort(refs)
  for _,ref in ipairs(refs)do
   local part=parts[ref];local unit=native(ref)
   assert(unit==part.native and ptr(unit+0x18)==part.world_native,'Subject Unit owner changed')
   local count=word(unit+0xc8);assert(count<=512,'Subject mesh count changed')
   local meshes=ptr(unit+0xd0)
   key[#key+1]=tostring(ref);key[#key+1]=read(unit+0x1d0,24)
   key[#key+1]=tostring(count);key[#key+1]=tostring(meshes)
   for mesh=1,count do key[#key+1]=read(meshes+(mesh-1)*16,8)end
  end
  return table.concat(key,'|')
 end
 function self.unchanged(context)
  return type(context)=='table'and context._parts~=nil and context._topology==topology(context._parts)
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
 -- Until the neutralization lifecycle is qualified, never submit true zero
 -- with a Hover Pack. This checks exact current local ownership and refuses
 -- unknown reads as well as the known unsafe equipment type.
 function self.can_freeze()
  local current=owner();local key=owner_key(current)
  local inventory=ptr(game+0x2ce18e8)
  assert(inventory>=65536,'Pause inventory unavailable')
  local index=assert(lookup(inventory,40,current.avatar,4194304),'Pause inventory owner unavailable')
  local rows=ptr(inventory+80);local at=rows+index*48+12;local entity=word(at)
  local hover=false;local record,bytes
  if entity~=0 and entity~=4294967295 then
   local item=assert(lookup(current.entities,0xf1c978,entity,4194304),'Pause backpack unavailable')
   record=current.entities+0xf349e0+item*24;bytes=read(record,24)
   assert(word(record+8)==entity and bytes:byte(21)%2==1,'Pause backpack lifetime changed')
   native(word(record+12))
   hover=bytes:sub(1,8)==string.char(207,102,219,28,79,15,200,94)
  end
  assert(owner_key(owner())==key and ptr(game+0x2ce18e8)==inventory
   and ptr(inventory+80)==rows and word(at)==entity
   and(not record or read(record,24)==bytes),'Pause backpack changed during check')
  if hover then return false,'Hover Pack pause is being repaired; the camera remains available'end
  return true
 end
 function self.head_frame()
  local frame=self.frame();local handle=frame.root_handle
  assert(self.unit_lifetime(handle,frame.world),'Handycam player lifetime changed')
  assert(sr.Unit.has_node(handle,'head'),'Handycam head attachment unavailable')
  local node=sr.Unit.node(handle,'head');local count=sr.Unit.num_scene_graph_items(handle)
  assert(type(node)=='number'and node%1==0 and node>=1 and node<=count,'Handycam head node invalid')
  local p=sr.Unit.world_position(handle,node);local V=sr.Vector3
  frame.head={V.x(p),V.y(p),V.z(p)}
  for i=1,3 do assert(type(frame.head[i])=='number'and frame.head[i]==frame.head[i]and math.abs(frame.head[i])<1e8,'Handycam head transform invalid')end
  assert(self.unit_lifetime(handle,frame.world) and frame.owner_key==owner_key(owner()),'Handycam player changed during read')
  return frame
 end
 -- The public bone-mode getter dereferences Unit+168 without a null check.
 -- This is distinct from the animation state machine at Unit+178.
 local function pose_component(unit)
  assert(ptr(ptr(unit)+0x1a8)==exe+0x28d4d0 and code(exe+0x28d4d0,'\072\139\129\104\001\000\000\195'),'Subject bone component layout changed')
  local component=ptr(unit+0x168)
  assert(component>=65536 and component<2^47,'Subject bone component unavailable')
  assert(word(component+0x164)<=7,'Subject bone transfer mode changed')
  return component
 end
 function self.pose_frame()
  local frame=self.frame();local unit=native(frame.root_ref)
  assert(memory.function_address(sr.Unit.animation_bone_mode)==exe+0x3f1c30
   and memory.function_address(sr.Unit.set_animation_bone_mode)==exe+0x3f1f50
   and code(exe+0x3f1c89,'\139\136\100\001\000\000\133\201')
   and code(exe+0x3f1f40,'\137\184\100\001\000\000'),'Subject bone mode binding changed')
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
  assert(code(game+0x8f3b01,'\076\139\061\216\227\062\002')
   and code(game+0x8f3c40,'\076\107\225\120')
   and code(game+0x8f3e14,'\185\180\130\118\252')
   and code(game+0x8f3e1e,'\075\139\140\060\128\120\084\000')
   and code(game+0x8f3e2f,'\072\193\233\036\131\225\001'),'Subject ragdoll layout changed')
  local frame=self.pose_frame();local current=owner()
  assert(frame.owner_key==owner_key(current),'Subject ragdoll owner changed during lookup')
  local avatars=ptr(game+0x2ce1ee0)
  assert(avatars>=65536 and avatars<2^47,'Subject ragdoll manager unavailable')
  local capacity=word(avatars+0x6c)
  assert(capacity>0 and capacity<=4096,'Subject ragdoll bounds changed')
  local index=assert(lookup(avatars,0xf8,current.avatar,capacity),'Subject ragdoll avatar unavailable')
  local descriptor=ptr(avatars+0x110+index*8);local record=read(descriptor,24)
  assert(word(descriptor)==0x294dfa97 and word(descriptor+4)==0x4d1c334d
   and word(descriptor+8)==current.avatar and word(descriptor+12)==frame.root_ref
   and record:byte(21)%2==1,'Subject ragdoll component owner changed')
  local address=avatars+0x547880+index*0x78;local flags=read(address,8)
  -- Read byte 4 rather than a Lua double containing a 64-bit bitset: higher
  -- active flags must not round away the ragdoll bit at position 36.
  local active=math.floor(flags:byte(5)/16)%2==1
  assert(self.pose_valid(frame,true)==true and owner_key(owner())==frame.owner_key
   and ptr(game+0x2ce1ee0)==avatars and word(avatars+0x6c)==capacity
   and lookup(avatars,0xf8,current.avatar,capacity)==index
   and ptr(avatars+0x110+index*8)==descriptor and read(descriptor,24)==record
   and read(address,8)==flags,'Subject ragdoll owner changed during readback')
  frame.ragdoll=active;frame.ragdoll_active=active
  frame.avatar_manager=avatars;frame.avatar_index=index;frame.ragdoll_descriptor=descriptor
  return frame
 end
 -- The local avatar's aim point as the game caches it for the weapon: the aim
 -- query writes it at game+0x837e3a and the weapon copies it at 0x78d9aa. Three
 -- floats in the avatar's 0x78-byte record at manager+0x5478a8, beside the
 -- ragdoll flags (+0x547880). Read-only; nothing here feeds back into aiming.
 local aim_layout;local f32=M.f32
 -- Whether a stock Unit handle is the local avatar's root (no handle equality assumed).
 function self.is_local_unit(handle)return type(handle)=='userdata'and memory.handle_ref(handle)==owner().root end
 function self.aim_target()
  if not aim_layout then
   assert(code(game+0x78d99f,'\072\107\193\120')
    and code(game+0x78d9aa,'\242\066\015\016\132\008\168\120\084\000\066\139\132\008\176\120\084\000')
    and code(game+0x837e20,'\073\129\192\168\120\084\000\077\003\199'),'Aim target layout changed')
   aim_layout=true
  end
  local current=owner();local avatars=ptr(game+0x2ce1ee0)
  assert(avatars>=65536 and avatars<2^47,'Aim avatar manager unavailable')
  local capacity=word(avatars+0x6c);assert(capacity>0 and capacity<=4096,'Aim avatar bounds changed')
  local index=assert(lookup(avatars,0xf8,current.avatar,capacity),'Aim avatar unavailable')
  local bytes=read(avatars+0x5478a8+index*0x78,12);local point={f32(bytes,0),f32(bytes,4),f32(bytes,8)}
  for i=1,3 do assert(point[i]==point[i]and math.abs(point[i])<1e6,'Aim target invalid')end
  return point
 end
 function self.resolve()
  local local_player=owner();local players,player,game_ref,entities,avatar,root=local_player.players,local_player.player,local_player.game_ref,local_player.entities,local_player.avatar,local_player.root
  local avatars=ptr(game+0x2ce1ee0);local ai=assert(lookup(avatars,248,avatar,word(avatars+0x6c)),'Local avatar renderer unavailable')
  local clothes=read(avatars+0x546ab0+ai*440+220,120);local refs={};local groups={hide_player={},hide_armour={},hide_weapons={}}
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
  -- Reuse the already bounded, ownership-verified attachment inventory. Cape
  -- rig discovery adds no world scan or new polling path.
  groups.hide_cape={}
  if type(sr.Unit.has_node)=='function'then
   for _,ref in ipairs(groups.hide_player)do
    local part=parts[ref]
    if ref~=root and sr.Unit.has_node(part.handle,'cape1')then groups.hide_cape[#groups.hide_cape+1]=ref end
   end
  end
  for group,items in pairs(groups)do local out,seen={},{};for _,ref in ipairs(items)do if not seen[ref]then out[#out+1]=parts[ref];seen[ref]=true end end;groups[group]=out end
  return{local_owner=true,identity=identity,groups=groups,_parts=parts,_topology=topology(parts)}
 end
 return self
end
return M

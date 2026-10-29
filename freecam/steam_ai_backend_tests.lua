package.preload.cffi=function()return{}end;local adapter;mod={require=function(path)assert(path=='src/cffi.lua');if not adapter then adapter=dofile('freecam/cffi.lua')end;return adapter end}
local PORT51=mod.require('src/cffi.lua')
-- Real byte-backed native backend; no process attachment or native invocation.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local B=dofile(root..'steam_ai_backend.lua')
local function fixture(entity_override)
local s={reads=0,read_bytes=0,writes=0};local now=0;local bytes={};local function put(at,data)for i=1,#data do bytes[at+i-1]=data:byte(i)end end
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function num(at,n,size)put(at,le(n,size or 4))end
local game,exe=0x10000000,0x20000000;local L=B.layout;local memwrites=0
local memory={game=game,exe=exe,now=function()return now end,scene=function()return 0x30000000 end,
 read=function(at,size)s.reads=s.reads+1;s.read_bytes=s.read_bytes+size;if s.fault and at<=s.fault and at+size>s.fault then error('Injected unreadable memory')end;local out={};for i=1,size do out[i]=string.char(bytes[at+i-1]or 0)end;return table.concat(out)end,
 write=function(at,data)memwrites=memwrites+1;s.writes=s.writes+1;put(at,data);if s.after_write then s.after_write(at,data)end end}
for _,item in ipairs({{game,B.game_stamp},{exe,B.exe_stamp}})do num(item[1]+60,0x100);put(item[1]+0x100,'PE\0\0');num(item[1]+0x108,item[2])end
put(exe+0xa06a0,'\072\137\092\036\008\072\137\116\036\016\087\072\236\032\072\139\053\066\112\161\001')
assert(not pcall(B.new,{},memory),'Invalid registry fingerprint accepted')
put(exe+0xa06a0,'\072\137\092\036\008\072\137\116\036\016\087\072\131\236\032\072\139\053\066\112\161\001')
local scene={};local peers={};local joining={}
local sr={Application={main_world=function()return scene end},Network={game_session=function()return{}end,connections=function()return peers end},GameSession={other_peers=function()return peers end,synchronizing_peers=function()return joining end}}
local world,state,mode,net,director=0x40000000,0x41000000,0x42000000,0x43000000,0x44000000
for key,p in pairs({WORLD=world,GAME_STATE=state,GAME_MODE=mode,NET=net,DIRECTOR=director})do num(game+L[key],p,8)end
num(state+L.STATE_VALUE,4);num(mode+8,1);num(net+0xb398,123,8);num(net+0xb3a8,123,8);num(game+L.INVALID,4294967295)
local ai,behavior,detector,alert=0x45000000,0x46000000,0x47000000,0x48000000
for key,p in pairs({AI=ai,BEHAVIOR=behavior,DETECTOR=detector,ALERT=alert})do num(game+L[key],p,8)end
local next_address=0x50000000
local function allocate()local p=next_address;next_address=next_address+0x10000;return p end
local entity=entity_override or 0x12345678;local ref=4194304+5
local function map(header,key,index)local data=allocate();num(header,data,8);num(header+8,8);num(header+12,4294967295);num(header+16,1)
 for i=0,7 do num(data+i*8,4294967295);num(data+i*8+4,4294967295)end;num(data+(key%8)*8,key);num(data+(key%8)*8+4,index);return data end
local function part(manager,map_offset,list_offset,rows_offset,stride)
 map(manager+map_offset,entity,0);local list,descriptor,rows=allocate(),allocate(),allocate();num(manager+list_offset,list,8);num(list,descriptor,8);num(descriptor+8,entity);num(descriptor+0x14,1,1);num(manager+rows_offset,rows,8);return rows,descriptor
end
local airow,aidesc=part(ai,0x2430,0x2448,0x2460,0x14);local brow=part(behavior,0x40,0x58,0x60,0x1f8);local drow=part(detector,0x30,0x48,0x50,0x13f8);local arow=part(alert,0x20,0x38,0x50,4)
num(airow,0);num(airow+4,0x200);num(brow+0x68,entity);num(brow+0x18,77);num(drow+0x13f0,1,1);num(drow+0x310,3);num(arow,4)
local world_map=map(world+L.WORLD_ENTITIES,entity,0);num(world+L.WORLD_RECORDS+8,entity);num(world+L.WORLD_RECORDS+12,ref)
local registry,pointers,generations,unit,vt=allocate(),allocate(),allocate(),allocate(),allocate();num(exe+L.UNIT_REGISTRY,registry,8);num(registry+0x98,10);num(registry+0x88,pointers,8);num(registry+0xa0,generations,8);num(generations+5,1,1);num(pointers+5*8,unit,8);num(unit+0x18,0x30000000,8);num(unit,vt,8);num(vt+0xf8,exe+0x28d330,8);num(vt+0xc8,exe+0x293550,8)
local native=B.new(sr,memory);local ctx=assert(native.context());assert(ctx.solo and ctx.player_count==1);local record=assert(native.observe(ctx,entity));assert(record.fields.detector.value==1 and record.fields.still.value==0x200)
 s.reads,s.read_bytes,s.writes=0,0,0
 s.native,s.ctx,s.record,s.memory,s.sr=native,ctx,record,memory,sr
 s.num,s.put,s.bytes=num,put,bytes
 s.entity,s.airow,s.brow,s.drow,s.registry,s.object,s.vt=entity,airow,brow,drow,registry,unit,vt
 s.generations,s.aidesc,s.net,s.ai,s.world_map=generations,aidesc,net,ai,world_map
 s.join=function()peers={[99]=true}end
 return s
end
do
 local f=fixture();local r=assert(f.native.observe(f.ctx,f.entity))
 assert(f.reads<=40,'Stable observation must substantially reduce the original58 scalar memory reads')
 local done,why,committed,after=f.native.write(f.ctx,r,'detector',0,1)
 assert(done and committed and why==nil and after and after.entity==r.entity and after.identity==r.identity)
 assert(after.fields.detector.value==0 and after.fields.detector.token==r.fields.detector.token)
 assert(after.fields.still and after.fields.target and after.fields.hostiles and after.fields.alert,
  'successful write must return the complete independently validated post-write record')
 local cleanup=assert(f.native.restore_context())
 local restored,problem,written,final=f.native.restore(cleanup,after,'detector',1,0)
 assert(restored and written and problem==nil and final and final.fields.detector.value==1)
 local count=f.writes
 done,why,committed,after=f.native.restore(cleanup,final,'target',77,final.fields.target.value)
 assert(not done and not committed and not after and f.writes==count,'cleanup cannot mutate target state')
end
-- Larger copies cannot turn unreadable padding or unused probe rows into a
-- missing component: fall back to the original narrow fields in those cases.
for _,where in ipairs({'network_padding','registry_padding','object_padding','vtable_padding','manager_padding','unused_probe'})do
 local f=fixture()
 f.fault=({network_padding=f.net+0xb3a0,registry_padding=f.registry+0x90,object_padding=f.object+8,
  vtable_padding=f.vt+0xd0,manager_padding=f.ai+0x2458,unused_probe=f.world_map+8})[where]
 local ctx=assert(f.native.context(),where)
 local r=assert(f.native.observe(ctx,f.entity),where)
 assert(r.fields.detector and r.fields.target and r.fields.still and not r.partial_issue,where)
 local done,why,committed,after=f.native.write(ctx,r,'still',0x280,0x200)
 assert(done and committed and after and after.fields.still.value==0x280,where..': '..tostring(why))
end
do
 local f=fixture();f.num(f.generations+5,2,1)
 local done,_,committed,after=f.native.write(f.ctx,f.record,'detector',0,1)
 assert(not done and not committed and not after and f.writes==0,'generation retirement cannot use a prior copied record')
 f=fixture();f.num(f.aidesc+8,f.entity+1)
 done,_,committed,after=f.native.write(f.ctx,f.record,'still',0x280,0x200)
 assert(not done and not committed and not after and f.writes==0,'component replacement cannot use copied manager headers')
 f=fixture();f.join()
 done,_,committed,after=f.native.write(f.ctx,f.record,'detector',0,1)
 assert(not done and not committed and not after and f.writes==0,'a new peer must be rechecked before every native write')
end
do
 local f=fixture();f.after_write=function()f.num(f.generations+5,2,1)end
 local done,why,committed,after=f.native.write(f.ctx,f.record,'detector',0,1)
 assert(not done and committed and after==nil and f.writes==1 and PORT51.kind(why)=='string',
  'failed post-write ownership/readback retains partial-commit semantics without returning a trusted record')
 f=fixture();f.after_write=function()f.fault=f.net+0xb398 end
 done,why,committed,after=f.native.write(f.ctx,f.record,'detector',0,1)
 assert(not done and committed and after==nil and f.writes==1,'authority loss after a commit cannot publish a verified record')
end
do
 local f=fixture();f.num(f.registry+0xa0,0,8)
 local original=f.memory.read
 f.memory.read=function(at,size)
  local copied=original(at,size)
  if at==f.registry+0x88 and size==32 then f.num(f.registry+0xa0,f.generations,8)end
  return copied
 end
 assert(not pcall(f.native.observe,f.ctx,f.entity)and f.writes==0,
  'a copied null pointer must not be replaced by a later scalar read from another registry observation')
end
do
 local f=fixture();f.num(f.world_map,f.entity+8);f.num(f.world_map+4,0)
 f.num(f.world_map+8,f.entity+16);f.num(f.world_map+12,0)
 f.num(f.world_map+16,f.entity);f.num(f.world_map+20,0)
 assert(f.native.observe(f.ctx,f.entity),'bounded contiguous probes must resolve hash collisions in order')
 f=fixture(0x1234567f)
 f.num(f.world_map+7*8,f.entity+8);f.num(f.world_map+7*8+4,0)
 f.num(f.world_map,f.entity);f.num(f.world_map+4,0)
 assert(f.native.observe(f.ctx,f.entity),'batched probes must split at the end of the current map allocation')
end
print('AI backend: bounded copied scalar batches, narrow fallback, collision/wrap probes, fresh authority/generation/component guards and verified post-write record contracts passed')

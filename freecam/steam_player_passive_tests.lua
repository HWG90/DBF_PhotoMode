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
put(exe+0xa06b0,'\072\137\092\036\008\072\137\116\036\016\087\072\236\032\072\139\053\050\112\161\001')
assert(not pcall(B.new,{},memory),'Invalid registry fingerprint accepted')
put(exe+0xa06b0,'\072\137\092\036\008\072\137\116\036\016\087\072\131\236\032\072\139\053\050\112\161\001')
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
local registry,pointers,generations,unit,vt=allocate(),allocate(),allocate(),allocate(),allocate();num(exe+L.UNIT_REGISTRY,registry,8);num(registry+0x98,10);num(registry+0x88,pointers,8);num(registry+0xa0,generations,8);num(generations+5,1,1);num(pointers+5*8,unit,8);num(unit+0x18,0x30000000,8);num(unit,vt,8);num(vt+0xf8,exe+0x28d3c0,8);num(vt+0xc8,exe+0x2935e0,8)
local native=B.new(sr,memory);local ctx=assert(native.context());assert(ctx.solo and ctx.player_count==1);local record=assert(native.observe(ctx,entity));assert(record.fields.detector.value==1 and record.fields.still.value==0x200)
 s.reads,s.read_bytes,s.writes=0,0,0
 s.native,s.ctx,s.record,s.memory,s.sr=native,ctx,record,memory,sr
 s.num,s.put,s.bytes=num,put,bytes
 s.entity,s.airow,s.brow,s.drow,s.registry,s.object,s.vt=entity,airow,brow,drow,registry,unit,vt
 s.generations,s.aidesc,s.net,s.ai,s.world_map=generations,aidesc,net,ai,world_map
 s.join=function()peers={[99]=true}end
 return s
end
local C=dofile(root..'steam_ai_control.lua')
local function passive_fixture()
 local f=fixture();local game=0x10000000;local world=0x40000000;local mgr=0x71000000;local rows=0x71030000;local desc=0x71020000
 local function map(at,key,data)
  f.num(at,data,8);f.num(at+8,8);f.num(at+12,4294967295);f.num(at+16,1)
  for k=0,7 do f.num(data+k*8,4294967295);f.num(data+k*8+4,4294967295)end
  f.num(data+(key%8)*8,key);f.num(data+(key%8)*8+4,0)
 end
 f.num(game+0x2ce1618,0x72000000,8);f.num(0x720003a8,7);map(world+0xf24990,7,0x73000000)
 f.num(game+0x2ce15e0,mgr,8);map(mgr+0x18,f.entity,0x71010000);f.num(mgr+0x30,0x71040000,8);f.num(0x71040000,desc,8);f.num(mgr+0x38,rows,8)
 f.num(desc+8,f.entity);f.num(desc+12,17);f.num(desc+20,1,1);f.num(rows,9)
 f.put(game+0x894a30,'\072\169\000\000\000\006');f.put(game+0x893015,'\072\015\186\224\025')
 f.rows,f.desc=rows,desc
 f.value=function()local a,b,c,d=f.bytes[rows],f.bytes[rows+1],f.bytes[rows+2],f.bytes[rows+3];return a+b*256+c*65536+d*16777216 end
 return f
end
for _,baseline in ipairs({9,0x2000009,0x84000009})do
 local f=passive_fixture();f.num(f.rows,baseline);local lease={};local n=f.writes
 assert(f.native.passive_update(f.ctx,lease,false));assert(PORT51.bit .band(f.value(),0x2000000)~=0)
 local written=f.writes;for _=1,4 do assert(f.native.passive_update(f.ctx,lease,false))end;assert(f.writes==written,'Stable Passive repeatedly wrote')
 f.num(f.rows,PORT51.bit .bor(f.value(),0x100)%4294967296)
 assert(f.native.passive_update(assert(f.native.restore_context()),lease,true));assert(f.value()==PORT51.bit .bor(baseline,0x100)%4294967296,'Restoration changed foreign/preexisting bits')
end
do
 local f=passive_fixture();local lease={};f.native.passive_update(f.ctx,lease,false);f.num(f.desc+12,18);local count=f.writes
 f.native.passive_update(assert(f.native.restore_context()),lease,true);assert(f.writes==count,'Wrote to recycled descriptor')
end
do
 local f=passive_fixture();local lease={};f.native.passive_update(f.ctx,lease,false);f.num(f.generations+5,2,1);local count=f.writes
 f.native.passive_update(assert(f.native.restore_context()),lease,true);assert(f.writes==count,'Wrote to recycled Unit')
end
do
 local f=passive_fixture();f.join();local count=f.writes
 assert(not pcall(f.native.passive_update,f.ctx,{},false)and f.writes==count,'Applied Passive in multiplayer')
end
do
 local f=passive_fixture();f.put(0x10000000+0x893015,'xxxxx');local count=f.writes
 assert(not pcall(f.native.passive_update,f.ctx,{},false)and f.writes==count,'Unsupported target reader accepted')
end
do
 local f=passive_fixture();local control=C.new(f.native);f.native.scan=function()error('Passive enumerated enemies')end
 assert(control.queue('passive')and control.flush(false));local n=f.writes
 for _=1,200 do assert(control.flush(false))end;assert(f.writes==n and control.count()==0,'Passive entered population loop')
 assert(control.queue('normal')and control.flush(false)and f.value()==9,'Normal did not restore player')
 assert(control.queue('passive')and control.flush(false));f.join();assert(control.release()and f.value()==9,'Cleanup failed after another peer joined')
end
do
 local f=passive_fixture();local lease={};f.after_write=function()error('Readback interruption')end
 assert(not pcall(f.native.passive_update,f.ctx,lease,false)and lease.owned,'Partial commit lost lease')
 f.after_write=nil;assert(f.native.passive_update(assert(f.native.restore_context()),lease,true)and f.value()==9)
end
do
 local f=passive_fixture();local time=0;f.memory.now=function()return time end
 local control=C.new(f.native);assert(control.queue('passive')and control.flush(false))
 f.join();time=.99;assert(control.flush(false)and control.mode=='passive')
 time=1;assert(control.flush(false)and control.mode=='normal'and f.value()==9,'Join cleanup missed the one-second boundary')
end
do
 local f=passive_fixture();local control=C.new(f.native)
 assert(control.queue('passive')and control.flush(false));f.native.scan=function()return{},0 end
 assert(control.queue('dummy')and control.flush(false)and f.value()==9,'Dummy retained player Passive bit')
end
print('Player Passive: single-bit writes, idle zero writes/no enemy scans, Normal/peer cleanup, foreign flags, fingerprint, recycled Unit/descriptor and partial commit restoration passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local C=dofile(root..'ai_control.lua');local B=dofile(root..'ai_backend.lua');local bit=require('bit')
local function clone(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table'and clone(v)or v end;return out end
local now=0;local authority=true;local epoch='mission1';local writes={};local enemies={};local fail=false;local partial=false;local fail_entity
local function enemy(e,detector,flags)
 enemies[e]={entity=e,identity=epoch..':'..e..':generation1',invalid=4294967295,fields={
  detector={value=detector or 1,token='det'..e},still={value=flags or 0x200,token='ai'..e},
  target={value=77,token='behavior'..e},hostiles={value=3,token='det'..e},alert={value=5,token='alert'..e}}}
 return enemies[e]
end
local backend={now=function()return now end,context=function()if authority then return{identity=epoch,authority=true}end;return nil,'not host'end,
 scan=function()local list={};for e in pairs(enemies)do list[#list+1]=e end;table.sort(list);return list,0 end,
 observe=function(ctx,e)if not authority or ctx.identity~=epoch then return nil,'not host'end;return enemies[e]and clone(enemies[e])or nil,'retired'end}
function backend.write(ctx,record,key,value,expected)
 local actual=enemies[record.entity];assert(authority and ctx.identity==epoch and actual.identity==record.identity)
 assert(actual.fields[key].token==record.fields[key].token and actual.fields[key].value==expected,'stale record write')
 if fail or record.entity==fail_entity then return false,'retry write',false end
 actual.fields[key].value=value;writes[#writes+1]={entity=record.entity,key=key,value=value}
 if partial then partial=false;return false,'readback unavailable',true end
 return true,nil,true
end
local one=enemy(1);local two=enemy(2,0,0x280);local control=C.new(backend)
assert(control.ready());assert(not control.queue('frozen'));assert(control.queue('passive'));assert(#writes==0,'Menu callback wrote AI state')
assert(control.flush(true));assert(control.affected==2 and one.fields.detector.value==0 and one.fields.target.value==4294967295 and one.fields.hostiles.value==0 and one.fields.alert.value==0)
assert(one.fields.still.value==0x200,'Passive stopped movement');local count=#writes
now=.1;assert(control.flush(true));assert(#writes==count,'Unchanged AI fields were rewritten')
assert(control.queue('dummy'));assert(control.flush(true));assert(one.fields.still.value==0x280 and two.fields.still.value==0x280)
one.fields.still.value=0x80000480;assert(control.queue('passive'));assert(control.flush(true));assert(one.fields.still.value==0x80000400 and two.fields.still.value==0x280,'Movement restoration cleared unrelated or preexisting bits')
one.fields.detector.value=2;assert(control.queue('normal'));assert(control.flush(true));assert(one.fields.detector.value==2 and two.fields.detector.value==0,'Normal clobbered another writer or preexisting disabled detection')
assert(one.fields.target.value==4294967295 and one.fields.hostiles.value==0,'Restoration revived stale targets/hostile list counts')
one.fields.detector.value=1;assert(control.queue('dummy'));assert(control.flush(true));authority=false;count=#writes
assert(not control.release()and control.count()>0 and#writes==count,'Lost authority wrote or abandoned cleanup')
authority=true;assert(control.release());assert(one.fields.detector.value==1 and one.fields.still.value==0x80000400)
assert(control.queue('dummy'));assert(control.flush(true));local old_identity=one.identity;one.identity=epoch..':1:generation2';one.fields.detector.value=7;one.fields.still.value=0x900
assert(control.release());assert(one.fields.detector.value==7 and one.fields.still.value==0x900,'Cleanup touched a reused unit generation')
one.identity=old_identity;one.fields.detector.value=1;one.fields.still.value=0x200;assert(control.queue('dummy'));assert(control.flush(true));fail=true
assert(not control.release()and control.count()>0,'Failed restoration lost ownership');fail=false;assert(control.release())
assert(control.queue('passive'));partial=true;assert(control.flush(true));assert(control.release());assert(one.fields.detector.value==1,'Committed write/readback failure lost detector restoration')
assert(control.queue('dummy'));assert(control.flush(true));one.fields.detector.token='replacement';one.fields.detector.value=9;assert(control.release());assert(one.fields.detector.value==9,'Component replacement inherited an old baseline')
one.fields.detector.token='det1';one.fields.detector.value=1;assert(control.queue('dummy'));assert(control.flush(true));count=#writes;epoch='mission2';assert(control.release());assert(#writes==count,'World retirement dereferenced old records')
enemies={};for i=1,40 do enemy(i)end;assert(control.queue('passive'));assert(control.flush(true));assert(control.affected<=C.batch,'One refresh exceeded the bounded enemy batch')
count=#writes;assert(control.flush(true));assert(#writes==count,'Refresh ignored real-time throttling');now=now+.1;assert(control.flush(true));assert(control.affected>C.batch)
assert(control.release());assert(control.count()==0)
-- Menu exit keeps the chosen behavior and continues discovering new enemies.
enemies={};now=now+.1;one=enemy(1);assert(control.queue('dummy'));assert(control.flush(true))
now=now+.1;two=enemy(2);assert(control.flush(false));assert(control.mode=='dummy' and control.affected==2)
assert(two.fields.detector.value==0 and two.fields.still.value==0x280,'New arrival escaped persistent Dummy')
assert(control.queue('passive'));assert(control.flush(false));assert(two.fields.still.value==0x200 and two.fields.detector.value==0,'Passive did not release Dummy movement')
now=now+.1;local incoming=enemy(3);assert(control.flush(false));assert(incoming.fields.detector.value==0 and incoming.fields.still.value==0x200,'New arrival escaped Passive')
assert(control.queue('normal'));assert(control.flush(false));assert(control.count()==0 and two.fields.detector.value==1 and incoming.fields.detector.value==1,'Reset outside menu did not restore normal behavior')
assert(control.queue('passive'));assert(control.flush(false));authority=false;now=now+.1;count=#writes
assert(not control.flush(false) and #writes==count and control.mode=='passive','Transient authority loss changed requested mode or wrote')
authority=true;epoch='mission3';enemies={};one=enemy(1);now=now+.1;assert(control.flush(false));assert(one.fields.detector.value==0,'Selection did not resume in fresh authoritative scene')
assert(control.release());assert(one.fields.detector.value==1 and control.mode=='normal','Shutdown did not restore persistent behavior')
-- A borrowed detector belongs to its live owner, not the first processed user.
enemies={};one=enemy(1);two=enemy(2);local original_scan=backend.scan
one.fields.detector=two.fields.detector;one.fields.hostiles=two.fields.hostiles
two.fields.detector.owner=2;two.fields.detector.owner_identity=two.identity
backend.scan=function()return{1},0 end -- owner need not be admitted as a borrower
assert(control.queue('passive'));assert(control.flush(false));assert(two.fields.detector.value==0)
enemies[1]=nil;now=now+.1;assert(control.flush(false))
assert(control.count()>0,'Borrower retirement discarded a surviving detector lease')
assert(control.release());assert(two.fields.detector.value==1,'Reset failed to restore the surviving detector owner')
one=enemy(1);one.fields.detector=two.fields.detector;one.fields.hostiles=two.fields.hostiles
assert(control.queue('passive'));assert(control.flush(false));two.identity=epoch..':2:generation2';two.fields.detector.value=9
assert(control.release());assert(two.fields.detector.value==9,'Borrowed detector cleanup wrote a reused owner generation')
two.fields.detector.value=1;two.fields.detector.owner_identity=two.identity
assert(control.queue('passive'));assert(control.flush(false));enemies[1]=nil;enemies[2]=nil;count=#writes
assert(control.release());assert(control.count()==0 and #writes==count,'Retired detector owner was retained or written')
-- Untouched/unusable records release their slots for the next discovery page.
backend.scan=original_scan;enemies={};local original_observe=backend.observe
for i=1,C.batch do enemy(i)end;incoming=enemy(C.batch+1)
backend.observe=function(ctx,e)if e<=C.batch then return nil,'components unavailable'end;return original_observe(ctx,e)end
local page=0;backend.scan=function()page=page+1;local ids={};if page==1 then for i=1,C.batch do ids[#ids+1]=i end else ids={C.batch+1}end;return ids,0 end
assert(control.queue('passive'));assert(control.flush(false));assert(control.count()==0,'Untouched records retained capacity')
now=now+.1;assert(control.flush(false));assert(incoming.fields.detector.value==0,'New arrival was starved by unusable records')
assert(control.release());backend.observe=original_observe;backend.scan=original_scan
-- One failed restore cannot leave all other healthy enemies suppressed.
enemies={};one=enemy(1);two=enemy(2);assert(control.queue('dummy'));assert(control.flush(false));fail_entity=1
assert(not control.release());assert(two.fields.detector.value==1 and two.fields.still.value==0x200,'Failed cleanup blocked another enemy restoration')
assert(control.count()>0 and one.fields.detector.value==0,'Failed cleanup lost its lease')
fail_entity=nil;assert(control.release());assert(one.fields.detector.value==1 and one.fields.still.value==0x200)
-- Real backend layout exercises use an isolated byte-addressed memory fixture.
local bytes={};local function put(at,data)for i=1,#data do bytes[at+i-1]=data:byte(i)end end
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function num(at,n,size)put(at,le(n,size or 4))end
local game,exe=0x10000000,0x20000000;local L=B.layout;local memwrites=0
local memory={game=game,exe=exe,now=function()return now end,scene=function()return 0x30000000 end,
 read=function(at,size)local out={};for i=1,size do out[i]=string.char(bytes[at+i-1]or 0)end;return table.concat(out)end,
 write=function(at,data)memwrites=memwrites+1;put(at,data)end}
for _,item in ipairs({{game,B.game_stamp},{exe,B.exe_stamp}})do num(item[1]+60,0x100);put(item[1]+0x100,'PE\0\0');num(item[1]+0x108,item[2])end
put(exe+0x9d8c0,'\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\xec\x20\x48\x8b\x35\x1a\x28\x97\x01')
assert(not pcall(B.new,{},memory),'Invalid registry fingerprint accepted')
put(exe+0x9d8c0,'\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x35\x1a\x28\x97\x01')
local scene={};local peers={};local joining={}
local sr={Application={main_world=function()return scene end},Network={game_session=function()return{}end,connections=function()return peers end},GameSession={other_peers=function()return peers end,synchronizing_peers=function()return joining end}}
local world,state,mode,net,director=0x40000000,0x41000000,0x42000000,0x43000000,0x44000000
for key,p in pairs({WORLD=world,GAME_STATE=state,GAME_MODE=mode,NET=net,DIRECTOR=director})do num(game+L[key],p,8)end
num(state+L.STATE_VALUE,4);num(mode+8,1);num(net+0xb398,123,8);num(net+0xb3a8,123,8);num(game+L.INVALID,4294967295)
local ai,behavior,detector,alert=0x45000000,0x46000000,0x47000000,0x48000000
for key,p in pairs({AI=ai,BEHAVIOR=behavior,DETECTOR=detector,ALERT=alert})do num(game+L[key],p,8)end
local next_address=0x50000000
local function allocate()local p=next_address;next_address=next_address+0x10000;return p end
local entity=0x12345678;local ref=4194304+5
local function map(header,key,index)local data=allocate();num(header,data,8);num(header+8,8);num(header+12,4294967295);num(header+16,1)
 for i=0,7 do num(data+i*8,4294967295);num(data+i*8+4,4294967295)end;num(data+(key%8)*8,key);num(data+(key%8)*8+4,index);return data end
local function part(manager,map_offset,list_offset,rows_offset,stride)
 map(manager+map_offset,entity,0);local list,descriptor,rows=allocate(),allocate(),allocate();num(manager+list_offset,list,8);num(list,descriptor,8);num(descriptor+8,entity);num(descriptor+0x14,1,1);num(manager+rows_offset,rows,8);return rows,descriptor
end
local airow,aidesc=part(ai,0x2330,0x2348,0x2360,0x14);local brow=part(behavior,0x40,0x58,0x60,0x1f8);local drow=part(detector,0x30,0x48,0x50,0x13f8);local arow=part(alert,0x20,0x38,0x50,4)
num(airow,0);num(airow+4,0x200);num(brow+0x68,entity);num(brow+0x18,77);num(drow+0x13f0,1,1);num(drow+0x310,3);num(arow,4)
map(world+L.WORLD_ENTITIES,entity,0);num(world+L.WORLD_RECORDS+8,entity);num(world+L.WORLD_RECORDS+12,ref)
local registry,pointers,generations,unit,vt=allocate(),allocate(),allocate(),allocate(),allocate();num(exe+L.UNIT_REGISTRY,registry,8);num(registry+0x98,10);num(registry+0x88,pointers,8);num(registry+0xa0,generations,8);num(generations+5,1,1);num(pointers+5*8,unit,8);num(unit+0x18,0x30000000,8);num(unit,vt,8);num(vt+0xf8,exe+0x2bd890,8);num(vt+0xc8,exe+0x2c3990,8)
local native=B.new(sr,memory);local ctx=assert(native.context());local record=assert(native.observe(ctx,entity));assert(record.fields.detector.value==1 and record.fields.still.value==0x200)
assert(record.fields.detector.owner==entity and record.fields.detector.owner_identity==record.identity,'Detector owner lacks generation identity')
num(net+0xb3a8,0,8);local solo_context=assert(native.context());assert(solo_context.identity==ctx.identity,'Host-id establishment retired a live solo scene');num(net+0xb3a8,123,8)
assert(native.write(ctx,record,'detector',0,1));assert(memwrites==1);assert(not native.write(ctx,record,'detector',1,1),'Stale expected value accepted')
record=assert(native.observe(ctx,entity));local moved=allocate();num(moved+0x13f0,0,1);num(moved+0x310,0);num(detector+0x50,moved,8)
assert(native.write(ctx,record,'detector',1,0));assert(bytes[drow+0x13f0]==0 and bytes[moved+0x13f0]==1,'Relocated component wrote a cached row address')
record=assert(native.observe(ctx,entity));num(generations+5,2,1);assert(not native.observe(ctx,entity));assert(not native.write(ctx,record,'detector',1,0),'Reused Unit generation accepted');num(generations+5,1,1)
local detector_record=assert(native.observe_detector(ctx,entity));assert(detector_record.identity==record.identity and detector_record.kind=='detector')
num(behavior+0x60,0,8);assert(not native.observe(ctx,entity));assert(native.observe_detector(ctx,entity),'Direct detector restoration depended on a Behavior row')
assert(native.write(ctx,detector_record,'detector',0,1),'Direct detector write required a Behavior row')
detector_record=assert(native.observe_detector(ctx,entity));assert(native.write(ctx,detector_record,'detector',1,0));num(behavior+0x60,brow,8)
num(generations+5,2,1);assert(not native.observe_detector(ctx,entity));assert(not native.write(ctx,detector_record,'detector',0,1),'Direct detector cleanup accepted a stale owner generation');num(generations+5,1,1)
num(aidesc+8,entity+1);assert(not native.observe(ctx,entity),'Moved/reused descriptor with another entity accepted');num(aidesc+8,entity);num(aidesc+0x14,0,1);assert(not native.observe(ctx,entity),'Retired descriptor accepted');num(aidesc+0x14,1,1)
num(net+0xb3a8,456,8);assert(not native.context(),'Client authority accepted');num(net+0xb3a8,123,8);joining={1};assert(not native.context(),'Joining authority accepted');joining={};peers={9};assert(native.context(),'Authoritative host with peers refused')
num(mode+8,0);assert(not native.context(),'Ship/loading context accepted')
assert(memwrites==4,'Rejected identities or authority wrote memory')
print('Photo AI: honest Passive/Dummy behavior, bounded changed-only updates, conditional restoration, transient target safety, retry/generation/component/world ownership, fixed build/registry guards and fresh byte-backed native lookups passed')

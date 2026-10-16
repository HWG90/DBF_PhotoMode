local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local C=dofile(root..'ai_control.lua');local B=dofile(root..'ai_backend.lua');local bit=require('bit')
-- Ownership/cleanup fixtures below exercise every batch without a timer.
assert(C.hold_interval==1 and C.interval==1,'Production AI must use one-second cadence')
C.hold_interval=0;C.interval=.05
local function clone(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table'and clone(v)or v end;return out end
local now=0;local authority=true;local solo=true;local unknown_session=false;local scene_read_error=false;local epoch='mission1';local writes={};local enemies={};local fail=false;local partial=false;local fail_entity;local fail_key
local function enemy(e,detector,flags)
 enemies[e]={entity=e,identity=epoch..':'..e..':generation1',invalid=4294967295,fields={
  detector={value=detector or 1,token='det'..e},still={value=flags or 0x200,token='ai'..e},
  target={value=77,token='behavior'..e},hostiles={value=3,token='det'..e},alert={value=5,token='alert'..e}}}
 return enemies[e]
end
local backend={now=function()return now end,context=function()
 if scene_read_error then error('World read temporarily unavailable')end
 if unknown_session then return nil,'Solo player count unavailable','unknown_session'end
 if not solo then return nil,'Solo only','not_solo'end
 if authority then return{identity=epoch,authority=true,solo=true,player_count=1}end;return nil,'not host'end,
 restore_context=function()if unknown_session then return nil,'Solo player count unavailable'end;if authority then return{identity=epoch,authority=true,cleanup=true}end;return nil,'not host'end,
 scan=function()local list={};for e in pairs(enemies)do list[#list+1]=e end;table.sort(list);return list,0 end,
 observe=function(ctx,e)if not authority or ctx.identity~=epoch then return nil,'not host'end;return enemies[e]and clone(enemies[e])or nil,'retired'end}
function backend.write(ctx,record,key,value,expected)
 local actual=enemies[record.entity];assert(authority and ctx.identity==epoch and actual.identity==record.identity)
 assert(ctx.cleanup or(solo and not unknown_session),'Non-restoring mutation reached multiplayer/unknown session')
 assert(actual.fields[key].token==record.fields[key].token and actual.fields[key].value==expected,'stale record write')
 if fail or record.entity==fail_entity or key==fail_key then return false,'retry write',false end
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
count=#writes;assert(control.flush(true));assert(#writes>count and control.affected>C.batch,'Existing enemies were not held on the next update');now=now+.1;assert(control.flush(true));assert(control.affected>C.batch)
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
-- A respawn/scene read exception suspends work without becoming a network reset.
enemies={};one=enemy(1);assert(control.queue('dummy'));assert(control.flush(false));count=#writes
scene_read_error=true;now=now+.1;assert(not control.flush(false)and control.mode=='dummy'and control.count()>0 and#writes==count)
incoming=enemy(2);scene_read_error=false;now=now+.1;assert(control.flush(false)and control.mode=='dummy')
assert(incoming.fields.still.value==0x280 and incoming.fields.detector.value==0,'New arrivals escaped after a transient scene read')
assert(control.release())
-- One failed restore cannot leave all other healthy enemies suppressed.
enemies={};one=enemy(1);two=enemy(2);assert(control.queue('dummy'));assert(control.flush(false));fail_entity=1
assert(not control.release());assert(two.fields.detector.value==1 and two.fields.still.value==0x200,'Failed cleanup blocked another enemy restoration')
assert(control.count()>0 and one.fields.detector.value==0,'Failed cleanup lost its lease')
fail_entity=nil;assert(control.release());assert(one.fields.detector.value==1 and one.fields.still.value==0x200)
-- Joining cancels suppression and restores owned baselines, even with the menu closed.
enemies={};one=enemy(1);assert(control.queue('dummy'));assert(control.flush(false));incoming=enemy(2);solo=false;now=now+.1
assert(not control.ready());assert(control.flush(false)and control.mode=='normal'and control.solo_reset==1)
assert(one.fields.detector.value==1 and one.fields.still.value==0x200 and incoming.fields.detector.value==1 and incoming.fields.target.value==77,'Join cleanup suppressed a new enemy or left a baseline changed')
count=#writes;assert(control.queue('passive'));assert(control.flush(false)and#writes==count,'Queued multiplayer behavior bypassed the backend policy')
solo=true;now=now+.1;assert(control.flush(false)and control.mode=='normal'and#writes==count,'Leaving multiplayer silently reapplied suppression')
assert(control.queue('dummy'));assert(control.flush(false));unknown_session=true;now=now+.1;count=#writes
assert(not control.flush(false)and control.mode=='normal'and control.count()>0 and#writes==count,'Unknown session wrote or abandoned restoration')
unknown_session=false;now=now+.1;assert(control.flush(false)and control.count()==0 and one.fields.detector.value==1,'Pending policy cleanup did not retry')
local unverified=C.new({now=function()return now end,context=function()return{identity='unknown',authority=true}end,scan=function()error('Unverified player count scanned enemies')end})
assert(not unverified.ready());assert(unverified.queue('dummy'));assert(unverified.flush(false)and unverified.mode=='normal','Missing solo proof was accepted')
-- Real backend layout exercises use an isolated byte-addressed memory fixture.
-- A changed target/movement bit is held on the next update, without scanning
-- again or waiting for the slower discovery timer (including paused time).
enemies={};one=enemy(1);local scans=0;local base_scan=backend.scan
backend.scan=function(...)scans=scans+1;return base_scan(...)end
assert(control.queue('dummy'));assert(control.flush(false));local before_scans=scans
one.fields.target.value=77;one.fields.still.value=0x200
assert(control.flush(false));assert(one.fields.target.value==4294967295 and one.fields.still.value==0x280,'Game target/movement rewrite survived the next update')
assert(scans==before_scans,'Holding known enemies bypassed the discovery throttle')
assert(control.release());backend.scan=base_scan
-- Discovery exceptions and explicit unavailable results delay new arrivals,
-- without abandoning the independently validated enemies already held.
enemies={};one=enemy(1);assert(control.queue('dummy'));assert(control.flush(false))
incoming=enemy(2);backend.scan=function()error('Enumeration temporarily unreadable')end
one.fields.target.value=77;one.fields.still.value=0x200;now=now+.1
assert(control.flush(false)and control.mode=='dummy'and control.discovery_error and control.status:find('discovery retry pending',1,true))
assert(one.fields.target.value==4294967295 and one.fields.still.value==0x280 and incoming.fields.detector.value==1,'Discovery error skipped holding or admitted an unscanned enemy')
backend.scan=function()return{},0,'Enemy manager unavailable'end;one.fields.target.value=77;now=now+.1
assert(control.flush(false)and control.discovery_error=='Enemy manager unavailable'and one.fields.target.value==4294967295,'Explicit discovery failure skipped holding')
backend.scan=base_scan;now=now+.1;assert(control.flush(false)and not control.discovery_error and incoming.fields.detector.value==0,'Discovery retry failed to cover new enemies')
authority=false;one.fields.target.value=77;count=#writes;now=now+.1
assert(not control.flush(false)and#writes==count and one.fields.target.value==77,'Discovery recovery bypassed authority validation')
authority=true;assert(control.release())
enemies={}
-- An unrelated detector write failure cannot block validated movement, target,
-- and alert fields. Partial application must not be counted as fully affected.
one=enemy(1);fail_key='detector';assert(control.queue('dummy'));assert(control.flush(false))
assert(one.fields.detector.value==1 and one.fields.still.value==0x280 and one.fields.target.value==4294967295 and one.fields.alert.value==0,'Detector error blocked independent suppression')
assert(control.affected==0 and control.status:find('1 unavailable',1,true),'Partial failure was hidden by the affected count')
fail_key=nil;assert(control.flush(false));assert(one.fields.detector.value==0 and control.affected==1)
assert(control.release());assert(one.fields.detector.value==1 and one.fields.still.value==0x200,'Partial-then-complete cleanup lost the original baseline')
one=enemy(1);one.fields.detector=nil;one.fields.hostiles=nil;one.partial_issue='Detector unavailable'
assert(control.queue('dummy'));assert(control.flush(false))
assert(one.fields.still.value==0x280 and one.fields.target.value==4294967295 and control.affected==0,'Missing optional detector suppressed no local fields or claimed full success')
assert(control.release());assert(one.fields.still.value==0x200)
-- Passive retries a failed Dummy movement release without losing the lease
-- or allowing independent target suppression to stop.
one=enemy(1);assert(control.queue('dummy'));assert(control.flush(false));fail_key='still'
one.fields.target.value=77;assert(control.queue('passive'));assert(control.flush(false))
assert(one.fields.still.value==0x280 and one.fields.target.value==4294967295 and control.affected==0,'Movement restore error blocked targets or claimed success')
fail_key=nil;assert(control.flush(false));assert(one.fields.still.value==0x200,'Passive dropped pending movement restoration')
assert(control.release());assert(one.fields.detector.value==1)
local bytes={};local function put(at,data)for i=1,#data do bytes[at+i-1]=data:byte(i)end end
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function num(at,n,size)put(at,le(n,size or 4))end
local game,exe=0x10000000,0x20000000;local L=B.layout;local memwrites=0;local fault_address
local memory={game=game,exe=exe,now=function()return now end,scene=function()return 0x30000000 end,
 read=function(at,size)if fault_address and at<=fault_address and at+size>fault_address then error('Injected unreadable memory')end;local out={};for i=1,size do out[i]=string.char(bytes[at+i-1]or 0)end;return table.concat(out)end,
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
local native=B.new(sr,memory);local ctx=assert(native.context());assert(ctx.solo and ctx.player_count==1);local record=assert(native.observe(ctx,entity));assert(record.fields.detector.value==1 and record.fields.still.value==0x200)
do
 local before=memwrites;local mission_record=0x6a000000
 local owner_code='\x4c\x8b\x25\xa0\x12\xfe\x01\x49\x8b\x9c\x24\x88\xe2\x0a\x00\x4c\x8d\xab\xf0\x00\x00\x00'
 put(game+0x1345099,owner_code);put(game+0x13450ee,'\x41\x0f\xb6\x45\x08');num(state+0xae288,mission_record,8)
 for id,name in pairs({[2]='terminids',[3]='automatons',[4]='illuminate'})do
  num(mission_record+0xf8,id,1);now=now+.6;assert(native.faction()==name,'Mission faction enum mapping changed')
 end
 num(mission_record+0xf8,1,1);now=now+.6;assert(native.faction()==nil,'Human/unknown records must not invent an enemy emblem')
 num(mission_record+0xf8,2,1);num(state+L.STATE_VALUE,2);now=now+.6;assert(native.faction()==nil,'Ship/loading states must not display a cached mission emblem')
 num(state+L.STATE_VALUE,4);put(game+0x13450ee,'xxxxx');now=now+.6;assert(native.faction()==nil,'Changed code fingerprint must refuse the native field')
 put(game+0x13450ee,'\x41\x0f\xb6\x45\x08');fault_address=mission_record+0xf8;now=now+.6;assert(native.faction()==nil,'Unreadable mission record must fail safely');fault_address=nil
 local original_read=memory.read;local changed=false
 memory.read=function(at,size)
  local data=original_read(at,size)
  if at==mission_record+0xf8 and not changed then changed=true;num(state+0xae288,0,8)end
  return data
 end
 now=now+.6;assert(native.faction()==nil,'Retired mission owner must not supply faction data');memory.read=original_read
 num(state+0xae288,mission_record,8);now=now+.6;assert(native.faction()=='terminids')
 assert(memwrites==before,'Faction observation must never write gameplay state')
end
assert(record.fields.detector.owner==entity and record.fields.detector.owner_identity==record.identity,'Detector owner lacks generation identity')
num(net+0xb3a8,0,8);local solo_context=assert(native.context());assert(solo_context.identity==ctx.identity,'Host-id establishment retired a live solo scene');num(net+0xb3a8,123,8)
assert(native.write(ctx,record,'detector',0,1));assert(memwrites==1);assert(not native.write(ctx,record,'detector',1,1),'Stale expected value accepted')
record=assert(native.observe(ctx,entity));local moved=allocate();num(moved+0x13f0,0,1);num(moved+0x310,0);num(detector+0x50,moved,8)
assert(native.write(ctx,record,'detector',1,0));assert(bytes[drow+0x13f0]==0 and bytes[moved+0x13f0]==1,'Relocated component wrote a cached row address')
record=assert(native.observe(ctx,entity));num(generations+5,2,1);assert(not native.observe(ctx,entity));assert(not native.write(ctx,record,'detector',1,0),'Reused Unit generation accepted');num(generations+5,1,1)
local detector_record=assert(native.observe_detector(ctx,entity));assert(detector_record.identity==record.identity and detector_record.kind=='detector')
num(behavior+0x60,0,8);local partial_record=assert(native.observe(ctx,entity));assert(partial_record.fields.still and partial_record.fields.detector and partial_record.fields.alert and not partial_record.fields.target and partial_record.partial_issue,'Missing Behavior discarded independently valid components');assert(native.observe_detector(ctx,entity),'Direct detector restoration depended on a Behavior row')
assert(native.write(ctx,detector_record,'detector',0,1),'Direct detector write required a Behavior row')
detector_record=assert(native.observe_detector(ctx,entity));assert(native.write(ctx,detector_record,'detector',1,0));num(behavior+0x60,brow,8)
num(generations+5,2,1);assert(not native.observe_detector(ctx,entity));assert(not native.write(ctx,detector_record,'detector',0,1),'Direct detector cleanup accepted a stale owner generation');num(generations+5,1,1)
num(aidesc+8,entity+1);assert(not native.observe(ctx,entity),'Moved/reused descriptor with another entity accepted');num(aidesc+8,entity);num(aidesc+0x14,0,1);assert(not native.observe(ctx,entity),'Retired descriptor accepted');num(aidesc+0x14,1,1)
num(net+0xb3a8,456,8);assert(not native.context(),'Client authority accepted');num(net+0xb3a8,123,8);joining={1};assert(not native.context(),'Joining authority accepted');joining={};peers={[900]=9};assert(not native.context(),'Sparse remote peer map accepted as solo')
local cleanup=assert(native.restore_context());assert(not cleanup.solo and cleanup.player_count==2 and cleanup.cleanup)
assert(not native.write(ctx,record,'detector',0,1),'Stale solo context wrote after a peer joined')
assert(not native.write(cleanup,record,'detector',0,1),'Cleanup context allowed an ordinary write')
assert(not native.restore(cleanup,record,'target',4294967295,77),'Cleanup context cleared a target')
assert(not native.restore(cleanup,record,'still',0x1000,0x200),'Cleanup context changed unrelated movement bits')
peers=nil;assert(not native.context()and not native.restore_context(),'Unknown peer count accepted')
peers={};joining=nil;assert(not native.context(),'Unknown joining state accepted');joining={}
local previous_reader=sr.GameSession.other_peers;sr.GameSession.other_peers=function()error('reader unavailable')end;assert(not native.context(),'Peer reader exception accepted');sr.GameSession.other_peers=previous_reader
num(net+0xb398,0,8);local _,_,policy=native.context();assert(policy=='unknown_session','Unknown local peer retained the selected mode');num(net+0xb398,123,8)
num(game+L.NET,0,8);local _,_,policy=native.context();assert(policy=='unknown_session','Missing net state retained the selected mode');num(game+L.NET,net,8)
num(net+0xb3a8,456,8);local _,_,policy=native.context();assert(policy=='unknown_session','Changed host authority retained the selected mode');num(net+0xb3a8,123,8)
num(mode+8,0);assert(not native.context(),'Ship/loading context accepted')
assert(memwrites==4,'Rejected identities or authority wrote memory')
-- Real memory backend and manager restore through their separate cleanup route.
num(mode+8,1);local live_control=C.new(native);assert(live_control.queue('dummy'));assert(live_control.flush(false));assert(bytes[moved+0x13f0]==0)
joining={[44]=true};now=now+.1;assert(live_control.flush(false)and live_control.mode=='normal'and live_control.count()==0)
assert(bytes[moved+0x13f0]==1 and memory.read(airow+4,4)==le(0x200,4),'Native joining cleanup failed to restore detection/movement')
-- A stale borrowed detector may retain a live-looking descriptor. It must never
-- be touched; use this living enemy's independently validated own detector.
joining={};assert(live_control.queue('dummy'));assert(live_control.flush(false))
local function number(at,size)local n=0;local raw=memory.read(at,size or 8);for i=#raw,1,-1 do n=n*256+raw:byte(i)end;return n end
local stale_owner=entity+1;local stale_descriptor=allocate();local detector_map=number(detector+0x30);local detector_list=number(detector+0x48)
num(detector_map+(stale_owner%8)*8,stale_owner);num(detector_map+(stale_owner%8)*8+4,1)
num(detector_list+8,stale_descriptor,8);num(stale_descriptor+8,stale_owner);num(stale_descriptor+0x14,1,1)
local stale_detector=moved+0x13f8;num(stale_detector+0x13f0,7,1);num(stale_detector+0x310,11)
num(brow+0x68,entity+1);num(airow+4,0x680)
local fallback=assert(native.observe(assert(native.context()),entity))
assert(fallback.detector_fallback and fallback.fields.detector.owner==entity and fallback.fields.detector.address==moved+0x13f0 and fallback.fields.hostiles.address==moved+0x310,'Stale borrowed owner did not resolve the independently validated own detector')
assert(fallback.fields.still and fallback.fields.target and fallback.fields.alert and not fallback.partial_issue,'Detector fallback discarded valid independent components')
num(airow+4,0x600);now=now+.1;local before_renew=memwrites
assert(live_control.flush(false)and live_control.mode=='dummy')
assert(memory.read(airow+4,4)==le(0x680,4)and memwrites==before_renew+1,'Missing borrowed detector blocked renewal of our movement lease')
assert(bytes[stale_detector+0x13f0]==7 and memory.read(stale_detector+0x310,4)==le(11,4),'Suppression wrote a stale borrowed detector row')
local movement=assert(native.observe_restore(assert(native.context()),entity));assert(movement.kind=='movement')
num(generations+5,2,1);local prior_writes=memwrites
assert(not native.restore(assert(native.restore_context()),movement,'still',0x600,0x680),'Movement cleanup accepted a reused Unit generation')
assert(memwrites==prior_writes);num(generations+5,1,1)
assert(live_control.queue('normal'));assert(live_control.flush(false)and live_control.count()==0,'Borrowed detector retirement blocked movement cleanup')
assert(memory.read(airow+4,4)==le(0x600,4)and bytes[moved+0x13f0]==1,'Movement cleanup lost unrelated flags or detector baseline')
assert(bytes[stale_detector+0x13f0]==7 and memory.read(stale_detector+0x310,4)==le(11,4),'Reset wrote a stale borrowed detector row')
-- Native context classifies scene-read loss separately from network evidence.
num(brow+0x68,entity);assert(live_control.queue('dummy'));assert(live_control.flush(false));prior_writes=memwrites
fault_address=game+L.WORLD;now=now+.1
assert(not live_control.flush(false)and live_control.mode=='dummy'and live_control.count()>0 and memwrites==prior_writes,'Transient world read reset behavior or wrote')
fault_address=nil;now=now+.1;assert(live_control.flush(false)and live_control.mode=='dummy')
fault_address=game+L.NET;now=now+.1;prior_writes=memwrites
assert(not live_control.flush(false)and live_control.mode=='normal'and live_control.count()>0 and memwrites==prior_writes,'Unknown native authority failed to cancel safely')
fault_address=nil;now=now+.1;assert(live_control.flush(false)and live_control.count()==0)
assert(memory.read(airow+4,4)==le(0x600,4)and bytes[moved+0x13f0]==1,'Native authority cleanup did not retry')
-- No usable detector still permits this enemy's own movement, target and alert.
num(brow+0x68,stale_owner);num(detector_list,0,8);num(brow+0x18,77);num(arow,4)
partial_record=assert(native.observe(assert(native.context()),entity))
assert(not partial_record.fields.detector and not partial_record.fields.hostiles and partial_record.fields.still and partial_record.fields.target and partial_record.fields.alert and partial_record.partial_issue,'Missing detector rejected independent behavior fields')
assert(live_control.queue('dummy'));assert(live_control.flush(false))
assert(memory.read(airow+4,4)==le(0x680,4)and memory.read(brow+0x18,4)==le(4294967295,4)and memory.read(arow,4)==le(0,4),'Detector absence prevented independent suppression')
assert(live_control.queue('normal'));assert(live_control.flush(false)and live_control.count()==0)
assert(memory.read(airow+4,4)==le(0x600,4)and bytes[stale_detector+0x13f0]==7,'Partial Reset did not restore movement or touched a stale detector')
-- An unreadable optional component is isolated. Own Unit/AI identity remains
-- mandatory, and a component changing between observation/write is rejected.
fault_address=behavior+0x40
partial_record=assert(native.observe(assert(native.context()),entity))
assert(partial_record.fields.still and partial_record.fields.alert and not partial_record.fields.target and partial_record.partial_issue,'Unreadable Behavior blocked independent fields')
fault_address=nil;partial_record=assert(native.observe(assert(native.context()),entity));num(behavior+0x60,0,8);prior_writes=memwrites
assert(not native.write(assert(native.context()),partial_record,'target',77,4294967295)and memwrites==prior_writes,'Disappearing optional component accepted a stale write')
num(behavior+0x60,brow,8);num(airow,16);prior_writes=memwrites
assert(not native.observe(assert(native.context()),entity)and not native.write(assert(native.context()),partial_record,'still',0x680,0x600)and memwrites==prior_writes,'Dead own AI accepted partial suppression')
num(airow,0)
-- Post-write records remove only the caller's redundant observation. They do
-- not bypass expected-value writes, partial-commit ownership or old adapters.
do
 local function fixture(verified)
  local s={time=0,records={},ids={},observations=0,restore_observations=0,detector_observations=0,writes=0,verified=verified,visits={}}
  function s.add(e)
   local fields={};for i,key in ipairs({'still','target','alert','detector','hostiles'})do
    fields[key]={value=({0x200,77,5,1,3})[i],token=key..e,address=e*256+i}
   end
   s.records[e]={entity=e,identity='perf:'..e,invalid=4294967295,fields=fields};s.ids[#s.ids+1]=e;return s.records[e]
  end
  local function read(e)return s.records[e]and clone(s.records[e])or nil,'retired'end
  local b={now=function()return s.time end,context=function()if s.context_error then return nil,'authority temporarily unavailable'end;return{identity='perf',solo=true,player_count=1}end,
   scan=function()return s.ids,0 end,
   observe=function(_,e)s.observations=s.observations+1;s.visits[e]=(s.visits[e]or 0)+1;return read(e)end,
   observe_restore=function(_,e)s.restore_observations=s.restore_observations+1;return read(e)end,
   observe_detector=function(_,e)s.detector_observations=s.detector_observations+1;return read(e)end}
  function b.write(_,r,key,value,expected)
   local current=assert(s.records[r.entity]);local field=assert(current.fields[key]);assert(current.identity==r.identity and field.token==r.fields[key].token and field.value==expected,'Fast path accepted a stale expected-value write')
   s.writes=s.writes+1;field.value=value
   if s.partial==key then s.partial=nil;return false,'readback unavailable',true end
   if not s.verified then return true,nil,true end
   local after=clone(current)
   if s.bad=='entity'then after.entity=after.entity+1000
   elseif s.bad=='identity'then after.identity='another generation'
   elseif s.bad=='token'then after.fields[key].token='another component'
   elseif s.bad=='address'then after.fields[key].address=0
   elseif s.bad=='owner'then after.fields[key].owner=99
   elseif s.bad=='value'then after.fields[key].value=value+1 end
   return true,nil,true,after
  end
  b.restore=b.write;s.backend=b;s.control=C.new(b);return s
 end
 for _,verified in ipairs({false,true})do
  local s=fixture(verified);local r=s.add(1);assert(s.control.queue('dummy')and s.control.flush(false))
  assert(s.writes==5 and s.observations==(verified and 1 or 6),'Verified post-write path did not remove exactly the redundant caller reads')
  assert(s.control.release()and r.fields.still.value==0x200 and r.fields.detector.value==1)
  assert(s.restore_observations==(verified and 1 or 2),'Verified restoration record was not reused')
 end
 for _,bad in ipairs({'entity','identity','token','address','owner','value'})do
  local s=fixture(true);s.bad=bad;local r=s.add(1);assert(s.control.queue('dummy')and s.control.flush(false))
  assert(s.observations==6,'Unverified post-write identity/readback bypassed the old observation path: '..bad)
  assert(s.control.release()and r.fields.still.value==0x200 and r.fields.detector.value==1)
 end
 local s=fixture(true);local r=s.add(1);s.partial='detector'
 assert(s.control.queue('dummy')and s.control.flush(false)and s.control.affected==0)
 assert(s.observations==2,'Partial committed write must fall back to a fresh observation')
 assert(s.control.release()and r.fields.detector.value==1 and r.fields.still.value==0x200,'Partial commit lost detector/movement cleanup leases')
 s=fixture(true);r=s.add(1);assert(s.control.queue('dummy')and s.control.flush(false));s.partial='still'
 assert(not s.control.release()and s.control.count()>0,'Partial committed restore discarded its retained lease')
 assert(s.control.release()and s.control.count()==0 and r.fields.still.value==0x200 and r.fields.detector.value==1)

 -- Stable registries retain bounded round-robin suppression without rebuilding
 -- sorted ID arrays or formatting an unchanged status each gameplay frame.
 s=fixture(true);for e=64,1,-1 do s.add(e)end
 assert(s.control.queue('dummy'));for _=1,4 do assert(s.control.flush(false))end
 for e=1,64 do assert(s.visits[e]and s.records[e].fields.detector.value==0,'Stable iteration starved an admitted enemy')end
 local original_sort,original_format=table.sort,string.format;local sorts,formats=0,0
 table.sort=function(...)sorts=sorts+1;return original_sort(...)end
 string.format=function(pattern,...)if pattern:find('Enemy behavior:',1,true)then formats=formats+1 end;return original_format(pattern,...)end
 local ran,problem=pcall(function()
  for _=1,4 do assert(s.control.flush(false))end
  assert(sorts==0 and formats==0,'Unchanged enemy registries/status rebuilt each frame')
  s.records[1].fields.still.value=0x200;s.records[1].fields.target.value=77
  assert(s.control.flush(false));assert(s.records[1].fields.still.value==0x280 and s.records[1].fields.target.value==4294967295,'Optimization throttled per-update movement/target suppression')
 end)
 table.sort,string.format=original_sort,original_format;assert(ran,problem)
 s.records[1]=nil;for i=#s.ids,1,-1 do if s.ids[i]==1 then table.remove(s.ids,i)end end
 for _=1,4 do assert(s.control.flush(false))end
 local incoming=s.add(65);s.time=.1;for _=1,5 do assert(s.control.flush(false))end
 assert(incoming.fields.detector.value==0 and incoming.fields.still.value==0x280,'Registry retirement/discovery lost a new enemy')
 s.context_error=true;assert(not s.control.flush(false));s.context_error=false;assert(s.control.flush(false)and s.control.status:find('Enemy behavior: Dummy',1,true),'Cached status retained an authority error after recovery')
 assert(s.control.release())

 -- Stable suppression must not enumerate the complete tracked registry just
 -- to count status/capacity. Only the bounded batch needs work each update.
 s=fixture(true);for i=1,256 do s.add(i)end
 assert(s.control.queue('dummy'));for _=1,16 do assert(s.control.flush(false))end
 assert(s.control.affected==256)
 local original_pairs=pairs;local enumerations=0;local registry
 for i=1,80 do local name,value=debug.getupvalue(s.control.flush,i);if name=='held'then registry=value;break end end
 assert(registry)
 local detector_registry
 for i=1,80 do local name,value=debug.getupvalue(s.control.flush,i);if name=='detectors'then detector_registry=value;break end end
 assert(detector_registry and s.control.count()==512)
 _G.pairs=function(t)if t==registry or t==detector_registry then enumerations=enumerations+1 end;return original_pairs(t)end
 local ok,why=pcall(function()for _=1,32 do assert(s.control.flush(false));assert(s.control.affected==256);for _=1,8 do assert(s.control.count()==512)end end end)
 _G.pairs=original_pairs;assert(ok,why)
 assert(enumerations==0,'Stable AI update enumerated registries for status/capacity')
 assert(s.control.queue('passive'));for _=1,16 do assert(s.control.flush(false))end
 assert(s.control.affected==256 and s.control.release()and s.control.count()==0)

 -- Production cadence uses wall time, never catches up in a burst, and
 -- preserves immediate mode changes, authority loss and Reset.
 C.hold_interval=1;C.interval=1
 s=fixture(true);local paced=s.add(1);assert(s.control.queue('dummy')and s.control.flush(false))
 local reads=s.observations;local base_context=s.backend.context;local contexts=0
 s.backend.context=function(...)contexts=contexts+1;return base_context(...)end
 paced.fields.target.value=77
 for i=1,99 do s.time=i*.01;assert(s.control.flush(false))end
 assert(s.observations==reads and contexts==0 and paced.fields.target.value==77,'Skipped AI ticks performed native work')
 s.time=1;assert(s.control.flush(false)and paced.fields.target.value==4294967295)
 assert(s.observations==reads+1,'Due AI holding did not run exactly once')
 s.time=5;assert(s.control.flush(false)and s.observations==reads+2,'AI cadence caught up with a burst')
 assert(s.control.queue('passive')and s.control.flush(false)and paced.fields.still.value==0x200,'Mode change waited for timer')
 assert(s.control.queue('normal')and s.control.flush(false)and paced.fields.detector.value==1 and s.control.count()==0,'Reset waited for timer')
 assert(s.control.queue('dummy')and s.control.flush(false))
 s.context_error=true;s.time=6.1;assert(not s.control.flush(false),'Due AI batch bypassed fresh authority validation')
 s.context_error=false;s.time=-1;assert(s.control.flush(false),'Backward wall clock blocked suppression')
 assert(s.control.release());C.hold_interval=0;C.interval=.05

 -- Model the review helper's acknowledged-method migration. Authoritative
 -- maps/leases are shared; derived ID/status caches are rebuilt, never copied.
 local function cell(fn,name)for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return i,v end end end
 local function copy_state(target,source)
  for _,name in ipairs({'requested','context','held','detectors','cursor','next_refresh','round','detector_round'})do
   local ti=assert(cell(target,name));local si,value=cell(source,name);assert(si);debug.setupvalue(target,ti,value)
  end
  for _,name in ipairs({'held_dirty','detector_dirty'})do local index=cell(target,name);if index then debug.setupvalue(target,index,true)end end
  local _,records=cell(target,'held');local _,leases=cell(target,'detectors')
  local n,a,e,d=0,0,0,0;for _,h in pairs(records)do n=n+1;if h.applied then a=a+1 end;if h.error then e=e+1 end end;for _ in pairs(leases)do d=d+1 end
  for name,value in pairs({tracked=n,affected=a,errors=e,detector_count=d})do local index=cell(target,name);if index then debug.setupvalue(target,index,value)end end
 end
 local function migrate(ai,b)
  local old={};for k,v in pairs(ai)do if type(v)=='function'then old[k]=v end end
  local replacement=C.new(b);copy_state(replacement.flush,old.flush);debug.setupvalue(replacement.flush,assert(cell(replacement.flush,'self')),ai)
  for k,v in pairs(replacement)do if type(v)=='function'then assert(old[k]);ai[k]=v end end
  return function()copy_state(old.flush,ai.flush);for k,v in pairs(old)do ai[k]=v end end
 end
 s=fixture(true);local first=s.add(1);s.add(2);assert(s.control.queue('dummy')and s.control.flush(false))
 local same_object=s.control;assert(s.control.queue('passive'));local original_writes=s.writes
 local rollback=migrate(s.control,s.backend)
 assert(s.control==same_object and s.control.mode=='dummy'and s.control.pending and s.writes==original_writes,'Migration changed mode, public identity or live leases')
 assert(s.control.flush(false)and s.control.mode=='passive'and first.fields.still.value==0x200 and first.fields.detector.value==0,'Migration lost pending mode request or owned baseline')
 incoming=s.add(3);s.time=.1;assert(s.control.flush(false)and incoming.fields.detector.value==0,'Migrated dirty registry missed a new arrival')
 rollback();assert(s.control==same_object and s.control.mode=='passive')
 assert(s.control.queue('dummy')and s.control.flush(false)and incoming.fields.still.value==0x280,'Rollback reused stale registry membership')
 assert(s.control.queue('normal')and s.control.flush(false)and s.control.count()==0 and incoming.fields.detector.value==1 and first.fields.detector.value==1,'Migration/rollback lost Normal cleanup')
 print('AI control performance: verified caller reads 6->1 per initial Dummy, safe fallback/partial cleanup, stable bounded registries/status and lease-preserving migration/rollback passed')
end
print('Photo AI: honest Passive/Dummy behavior, bounded changed-only updates, conditional restoration, transient target safety, retry/generation/component/world ownership, fixed build/registry guards and fresh byte-backed native lookups passed')

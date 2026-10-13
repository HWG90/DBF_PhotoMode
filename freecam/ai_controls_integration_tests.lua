local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Options=dofile(root..'photo_options.lua')
local AI=dofile(root..'ai_control.lua')
local function clone(t)local r={};for k,v in pairs(t)do r[k]=type(v)=='table'and clone(v)or v end;return r end
local now=0;local writes=0;local authority=true;local solo=true;local fail_restore=false;local inside_update=false
local enemy={entity=1,identity='scene:enemy:1',invalid=4294967295,fields={detector={value=1,token='detector'},still={value=0x200,token='still'},target={value=70,token='target'},hostiles={value=3,token='hostiles'},alert={value=2,token='alert'}}}
local enemies={[1]=enemy}
local backend={now=function()return now end,context=function()if not solo then return nil,'Solo only','not_solo'end;if authority then return{identity='scene:1',authority=true,solo=true,player_count=1}end;return nil,'Only the authoritative host controls enemy behavior'end,
 restore_context=function()if authority then return{identity='scene:1',authority=true,cleanup=true}end;return nil,'No cleanup authority'end,
scan=function()local ids={};for id in pairs(enemies)do ids[#ids+1]=id end;return ids,0 end,observe=function(_,id)return clone(enemies[id])end,
write=function(_,record,key,value,expected)
 local current=enemies[record.entity]
 assert(inside_update,'AI write escaped the update callback');assert(current.fields[key].value==expected)
 if fail_restore and key=='detector'and value==1 then return false,'restore retry'end
 writes=writes+1;current.fields[key].value=value;return true,nil,true
end}
local ai=AI.new(backend)
local photo={active=false};local keys={};local stored={ai_behavior=3,ai_dummy=true}
local api=Core.new({load=function(id)return id=='dbf_freecam'and clone(stored)or{}end,save=function(id,values)if id=='dbf_freecam'then stored=clone(values)end;return true end},function()end)
api.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()return{}end,release=function()return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
api.is_open=function()return false end;api.close=function()return true end;DBFMCM=api
local controller=Controller.new(photo,{},function()return true end,function()end,nil,Options,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,ai)
local function flush()now=now+.1;inside_update=true;local ok,why=ai.flush(photo.active);inside_update=false;return ok,why end
controller.tick(.016)
local mod=api.mods.dbf_freecam;local handle=mod.handle;local controls={};local director
for _,page in ipairs(mod.pages)do if page.id=='director'then director=page end;for _,c in ipairs(page.controls)do controls[c.id]=c end end
assert(director and director.controls[1].id=='ai_behavior'and controls.ai_behavior.label=='Enemy behavior')
assert(#controls.ai_behavior.choices==3 and controls.ai_behavior.choices[2]=='Passive'and controls.ai_behavior.choices[3]=='Dummy','Unsupported mode exposed')
assert(handle.get('ai_behavior')==1 and stored.ai_behavior==1 and not ai.pending and writes==0,'Saved behavior resumed suppression on restart')
assert(controls.ai_behavior.disabled,'Inactive photo mode exposed AI control')
keys[80]=true;controller.tick(.016);keys[80]=false;controller.tick(.016)
assert(photo.active and not controls.ai_behavior.disabled)
assert(handle.set('ai_behavior',3)and ai.pending and writes==0,'Menu callback wrote enemy state')
assert(flush()and ai.mode=='dummy'and ai.affected==1 and enemy.fields.detector.value==0 and enemy.fields.still.value==0x280)
controller.tick(.1);assert(controls.ai_status.label:find('1 affected',1,true),'Affected count missing')
authority=false;for i=1,6 do controller.tick(.1)end
assert(controls.ai_behavior.disabled and not controls.ai_reset.disabled,'Authority loss must disable behavior choices but retain cleanup Reset')
local before=writes;assert(handle.activate('ai_reset')and handle.get('ai_behavior')==1 and writes==before)
assert(not flush()and ai.count()>0 and writes==before,'Lost authority abandoned restoration')
controller.tick(.1);assert(controls.ai_status.label:find('cleanup waiting',1,true),'Pending cleanup status hidden')
authority=true;assert(flush()and ai.count()==0 and enemy.fields.detector.value==1 and enemy.fields.still.value==0x200)
for i=1,6 do controller.tick(.1)end
assert(handle.set('ai_behavior',3));assert(flush());before=writes
assert(controller.stop()and handle.get('ai_behavior')==3 and writes==before,'Photo exit changed selected behavior or wrote from render')
assert(flush()and ai.mode=='dummy'and enemy.fields.detector.value==0,'Photo exit stopped selected behavior')
local next_enemy=clone(enemy);next_enemy.entity=2;next_enemy.identity='scene:enemy:2';next_enemy.fields.detector.value=1;next_enemy.fields.still.value=0x200;enemies[2]=next_enemy
assert(flush()and ai.affected==2 and next_enemy.fields.detector.value==0 and next_enemy.fields.still.value==0x280,'New enemy escaped persistent behavior')
-- An MCM/private provider replacement is not a new game session.
local previous_api=api;before=writes
api=Core.new(nil,function()end);api.camera_input=previous_api.camera_input;api.is_open=function()return false end;api.close=function()return true end;DBFMCM=api
controller.tick(.1);mod=api.mods.dbf_freecam;handle=mod.handle
assert(handle.get('ai_behavior')==3 and ai.mode=='dummy'and writes==before,'Provider replacement lost the displayed session behavior')
keys[80]=true;controller.tick(.016);keys[80]=false;controller.tick(.016);assert(photo.active and handle.get('ai_behavior')==3)
assert(handle.set('ai_behavior',2));assert(flush()and ai.mode=='passive'and enemy.fields.detector.value==0 and enemy.fields.still.value==0x200,'Passive did not restore movement')
before=writes;assert(handle.activate('ai_reset')and handle.get('ai_behavior')==1 and writes==before,'Reset must only queue restoration')
assert(flush()and ai.mode=='normal'and ai.count()==0 and enemy.fields.detector.value==1 and next_enemy.fields.detector.value==1,'Reset did not restore normal detection')
assert(handle.set('ai_behavior',3));assert(flush());solo=false;assert(flush()and ai.mode=='normal');for i=1,6 do controller.tick(.1)end
assert(mod.controls.ai_behavior.disabled and mod.controls.ai_reset.disabled and handle.get('ai_behavior')==1,'Multiplayer did not gray choices/reset UI to Normal after cleanup')
assert(not pcall(handle.set,'ai_behavior',3),'Disabled multiplayer behavior remained writable through the handle')
solo=true;for i=1,6 do controller.tick(.1)end;assert(not mod.controls.ai_behavior.disabled and handle.get('ai_behavior')==1,'Verified solo return silently restored the old choice')
assert(handle.set('ai_behavior',3));assert(flush());fail_restore=true;before=writes
assert(controller.close()==false and api.mods.dbf_freecam and writes==before,'Shutdown wrote directly or discarded pending enemy ownership')
assert(handle.get('ai_behavior')==1 and not flush()and ai.count()>0)
fail_restore=false;assert(flush());assert(controller.close()and not api.mods.dbf_freecam)
DBFMCM=nil
-- No backend must remain honestly disabled even in an otherwise ready scene.
api=Core.new(nil,function()end);api.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()return{}end,release=function()return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end};api.is_open=function()return false end;DBFMCM=api
controller=Controller.new({active=false},{},function()return true end,function()end,nil,Options)
controller.tick(.016);keys[80]=true;controller.tick(.016);keys[80]=false;controller.tick(.016)
mod=api.mods.dbf_freecam;assert(mod.controls.ai_behavior.disabled and mod.controls.ai_reset.disabled)
local status;for _,p in ipairs(mod.pages)do for _,c in ipairs(p.controls)do if c.id=='ai_status'then status=c.label end end end
assert(status:find('unavailable',1,true));assert(controller.close());DBFMCM=nil
-- Generated wiring keeps writes on the update hook and records source provenance.
local repo=rawget(_G,'DBF_PHOTO_REPO_ROOT')or''
local file=assert(io.open(repo..'freecam/build.py','rb'));local source=file:read('*a');file:close()
assert(source:find('pcall(H.dbf_ai.flush,PHOTO.active)',1,true)and source:find("('__AI_CONTROL__','ai_control.lua')",1,true))
assert(source:find('if cleared==false then return false,why end',1,true),'Shutdown ignored pending restore')
print('Enemy behavior integration: three supported modes, startup Normal, queued writes, authority gates, affected count, Photo exit persistence, new enemies, Reset and shutdown retry passed')

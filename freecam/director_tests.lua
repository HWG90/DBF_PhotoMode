local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'director.lua')
local photo={active=true,pos={12,-3,6},view={yaw=.4,pitch=.2},input={sequence=41,mouse_x=20},options={fov=55,roll=17}}
local player={local_owner=true,identity='local:1',position={10,0,2},yaw=0}
local stored;local fail_save=false
local storage={load=function()return stored and assert(module.decode(stored))or{}end,save=function(rows)if fail_save then return false,'disk sentinel'end;stored=module.encode(rows);return true end}
local director=module.new(photo,function()return player end,nil,nil,storage)
assert(director.save(1)and director.occupied(1));assert(stored:find('1.right=3',1,true))
photo.pos={-20,0,0};photo.view={yaw=2,pitch=-.1};player.position={100,200,20};player.yaw=math.pi/2
local values={fov=10,roll=0};local handle={get=function(k)return values[k]end,set_many=function(v)for k,n in pairs(v)do values[k]=n end;return true end}
assert(director.recall(1,handle));assert(math.abs(photo.pos[1]-103)<1e-9 and math.abs(photo.pos[2]-202)<1e-9 and photo.pos[3]==24,'Recall must rotate local offsets around the current player, not restore old world position')
assert(math.abs(photo.view.yaw-(math.pi/2+.4))<1e-9 and photo.view.pitch==.2 and photo.view.sequence==41,'Recall must rotate relative yaw and consume the current input sample once')
assert(values.fov==55 and values.roll==17)
photo.pos[1]=999;assert(director.recall(1,handle)and photo.pos[1]==103,'Recall must copy immutable persisted shots')
local loaded=module.new(photo,function()return player end,nil,nil,storage);assert(loaded.occupied(1)and loaded.recall(1,handle),'Fresh runtime must read the same five-slot file')
assert(loaded.save(5)and loaded.occupied(5)and not loaded.occupied(2));assert(not loaded.save(6))
local before=stored;fail_save=true;assert(not loaded.clear(1)and loaded.occupied(1)and stored==before,'Failed disk save must retain the last committed slot')
fail_save=false;assert(loaded.clear(1)and not loaded.occupied(1))
assert(not module.decode('version=2\n'));assert(not module.decode('version=1\n1.right=0\n'));assert(not module.decode('version=1\n1.right=0/0\n'))
assert(not module.decode(before..'version=1\n'),'Duplicate keys must be rejected')
assert(not module.decode(before:gsub('1.fov=55','1.fov=500')),'Persisted lens limits must be validated')
player.local_owner=false;local oldpos=photo.pos;assert(not loaded.recall(5,handle)and photo.pos==oldpos,'Unverified player ownership must never move the camera')
player.local_owner=true;photo.active=false;assert(not loaded.save(2)and not loaded.recall(5,handle),'Inactive Photo Mode must never capture or move a gameplay camera')
photo.active=true;photo.pos={10000,200,20};assert(not loaded.save(2),'Out-of-bounds offsets must be rejected')
-- Exercise the real atomic replacement route, including rollback after rename failure.
local files={['shots.ini']=before};local fail_rename=false
local fs={remove=function(path)files[path]=nil;return true end,rename=function(a,b)if fail_rename and a=='shots.ini.tmp'then return false,'rename sentinel'end;files[b]=files[a];files[a]=nil;return true end,
 open=function(path,mode)if mode=='rb'then if not files[path]then return nil end;return{read=function(_,n)return files[path]:sub(1,n)end,close=function()return true end}end
 return{write=function(_,data)files[path]=data;return true end,close=function()return true end}end}
local disk=module.storage('shots.ini',fs);local rows=assert(disk.load());assert(rows[1].fov==55)
fail_rename=true;assert(not disk.save({})and files['shots.ini']==before and not files['shots.ini.tmp'],'Failed final rename must recover the original complete file')
fail_rename=false;assert(disk.save({})and files['shots.ini']=='version=1\n')
print('Director: player-relative translation/rotation, immutable slots, persistent reload, lens/input application, ownership/inactive bounds, malformed data and atomic rollback passed')

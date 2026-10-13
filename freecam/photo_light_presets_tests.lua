local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'photo_light_presets.lua');local L=dofile(root..'photo_lights.lua')
local function copy(v)local out={};for k,x in pairs(v)do out[k]=type(x)=='table'and copy(x)or x end;return out end
local function close(a,b)return math.abs(a-b)<1e-9 end
local frame={position={0,0,0},forward={0,1,0},right={1,0,0},up={0,0,1}}
local target={10,20,30};local anchor=copy(frame);anchor.position={8,16,31}
local values=copy(L.defaults);values.kind='spot';values.forward=0;values.intensity=123.456;values.range=99;values.cone=67;values.color='#A1B2C3'
local setup={version=1,selected=1,definitions={{values=values,anchor=anchor}}}
local files={};local replace_fail=false;local write_fail=false
local fs={}
function fs.open(path,mode)
 if mode=='rb'and not files[path]then return nil,'missing'end
 if mode=='wb'then files[path]=''end
 return{read=function(_,limit)return files[path]:sub(1,limit)end,write=function(_,data)if write_fail then return nil,'write refused'end;files[path]=files[path]..data;return true end,close=function()return true end}
end
function fs.replace(from,to)if replace_fail then return false,'replace refused'end;assert(files[from]);files[to]=files[from];files[from]=nil;return true end
function fs.remove(path)files[path]=nil;return true end
local storage=M.storage('lighting-presets.ini',fs);local presets=M.new(nil,storage)
assert(not presets.occupied(1)and not presets.recall(1,target,frame))
assert(presets.save(1,setup,target,frame));assert(presets.occupied(1)and presets.list()[1]:find('saved',1,true))
local bytes=files['lighting-presets.ini'];assert(not bytes:find('unit',1,true)and not bytes:find('world',1,true),'Saved native ownership')
local rows=assert(M.decode(bytes));assert(rows[1].definitions[1].anchor.position[1]==-2 and rows[1].definitions[1].anchor.position[2]==-4)
assert(M.encode(rows)==bytes,'Codec roundtrip changed stored numbers')
local restarted=M.new(nil,storage);assert(restarted.occupied(1),'Restart did not load saved setup')
local rotated={position={0,0,0},forward={1,0,0},right={0,-1,0},up={0,0,1}}
local recalled=assert(restarted.recall(1,{100,200,300},rotated));local d=recalled.definitions[1]
assert(close(d.anchor.position[1],96)and close(d.anchor.position[2],202)and close(d.anchor.position[3],301),'Recall did not follow the new subject basis')
assert(d.anchor.forward[1]==1 and d.anchor.right[2]==-1,'Recall did not rotate light orientation')
assert(d.values.intensity==123.456 and d.values.range==99 and d.values.cone==67 and d.values.color=='#A1B2C3')
d.anchor.position[1]=999;assert(restarted.recall(1,{100,200,300},rotated).definitions[1].anchor.position[1]==96,'Recall leaked saved state')
for i=2,5 do assert(restarted.save(i,setup,target,frame))end;assert(not restarted.save(6,setup,target,frame))
replace_fail=true;local durable=files['lighting-presets.ini'];assert(not restarted.clear(1));assert(restarted.occupied(1)and files['lighting-presets.ini']==durable and not files['lighting-presets.ini.tmp'],'Failed atomic replacement damaged previous setups')
replace_fail=false;write_fail=true;assert(not restarted.clear(2));assert(restarted.occupied(2)and files['lighting-presets.ini']==durable and not files['lighting-presets.ini.tmp'],'Failed write damaged previous setups');write_fail=false
assert(restarted.clear(1));assert(not M.new(nil,storage).occupied(1))
local offset=copy(setup);offset.definitions[1].values.right=2;offset.definitions[1].values.forward=3;offset.definitions[1].values.up=4;offset.definitions[1].values.enabled=false;offset.definitions[1].values.follow_camera=true
assert(restarted.save(1,offset,target,frame));d=restarted.recall(1,{100,200,300},rotated).definitions[1]
assert(d.anchor.position[1]==99 and d.anchor.position[2]==200 and d.anchor.position[3]==305 and d.values.right==0 and d.values.forward==0 and d.values.up==0,'Save failed to fold actual light offsets into subject placement')
assert(not d.values.enabled and d.values.follow_camera,'Complete setup lost enable/follow state')
local malformed=copy(frame);malformed.right={-1,0,0};assert(not restarted.save(2,setup,target,malformed));assert(not restarted.recall(2,target,malformed))
local invalid=copy(setup);invalid.definitions[1].anchor.position={1/0,0,0};assert(not restarted.save(2,invalid,target,frame))
invalid=copy(setup);invalid.definitions[1].anchor.position={2000,0,0};assert(not restarted.save(2,invalid,target,frame))
invalid=copy(setup);invalid.definitions[1].values.intensity=10001;assert(not restarted.save(2,invalid,target,frame))
for _,bad in ipairs({bytes..'version=1\n',bytes..'1.1.unit=1234\n',bytes:gsub('enabled=1','enabled=true'),bytes:gsub('version=1','version=2'),bytes:gsub('1.count=1','1.count=2'),bytes:gsub('intensity=123.456','intensity=nan'),string.rep('x',M.bytes+1)})do assert(not M.decode(bad),'Malformed preset file accepted')end
-- Exercise the real filesystem replacement, including replacing an existing
-- file on Windows. This fixture path contains only disposable test data.
local repo=rawget(_G,'DBF_PHOTO_REPO_ROOT')or'./';local path=repo..'dist/validation/photo-light-presets-fixture.ini'
local disk=M.storage(path);assert(disk.save(rows));assert(disk.save({}));assert(next(assert(disk.load()))==nil)
assert(os.remove(path));os.remove(path..'.tmp')
print('Photo light presets: five persistent slots, subject-relative position/orientation, complete values, bounded strict codec, immutable readback and atomic save/replacement failure preservation passed')

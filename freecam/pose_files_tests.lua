-- Pose file contracts in actual Lua 5.1: strict text format, probing storage with an injected filesystem.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local F=dofile('freecam/pose_files.lua')
local function frame(x)local f={full_body=true,nodes={}};for i=8,92 do f.nodes[i]={p={x+i,.5,-.25},q={0,0,math.sin(.3),math.cos(.3)},s={1,1,1}}end;return f end
local text=F.encode(frame(1),{label='Arms crossed',source='salute'})
assert(text:find('^version=1\nrig=4d1c334d294dfa97\nnodes=107\nlabel=Arms crossed\nsource=salute\n8='),text:sub(1,120))
local back,why=F.decode(text);assert(back,why);assert(back.label=='Arms crossed'and back.full_body==true)
for i=8,92 do for k=1,3 do assert(back.nodes[i].p[k]==frame(1).nodes[i].p[k])end;assert(back.nodes[i].q[4]==math.cos(.3))end
assert(select(2,F.decode((text:gsub('rig=4d1c334d294dfa97','rig=0000000000000000'))))=='This pose is for a different rig')
assert(select(2,F.decode((text:gsub('\n50=[^\n]*',''))))=='Pose file is missing node 50')
assert(select(2,F.decode(text..'\n50=0,0,0;0,0,0,1;1,1,1'))=='Pose file repeats 50')
assert(select(2,F.decode(text..'\ncolour=red'))=='Pose file has an unknown line')
assert(select(2,F.decode((text:gsub('\n9=[^\n]*','\n9=1,nan,0;0,0,0,1;1,1,1'))))=='Pose value is not a number')
assert(select(2,F.decode((text:gsub('\n9=[^\n]*','\n9=1,0,0;0,0,0,2;1,1,1'))))=='Pose quaternion is not normalised')
assert(select(2,F.decode(text..string.rep('\n',32768)))=='Pose file is too large')
-- Fake filesystem: files[path]=content; open modes 'rb'/'wb'; rename/remove.
local files,fail_write={},false
local fs={}
function fs.open(path,mode)
 if mode=='rb'then local c=files[path];if c==nil then return nil,'missing'end;return{read=function()return c end,close=function()end}end
 if fail_write then return nil,'disk full'end
 local buf={};return{write=function(_,s)buf[#buf+1]=s;return true end,close=function()files[path]=table.concat(buf);return true end}
end
function fs.rename(a,b)if files[a]==nil then return nil,'missing'end;files[b]=files[a];files[a]=nil;return true end
function fs.remove(p)if files[p]==nil then return nil,'missing'end;files[p]=nil;return true end
assert(F.path('C:/cfg',7)=='C:/cfg/wj-pose-07.txt')
local store=F.storage('C:/cfg',fs)
assert(#store.list()==0 and store.labels()[1]=='No saved poses')
assert(store.save_new(frame(1),{label='First',source='snapshot'})==1 and files['C:/cfg/wj-pose-01.txt'])
files['C:/cfg/wj-pose-05.txt']=F.encode(frame(5),{label='Dropped in',source='file'});files['C:/cfg/wj-pose-03.txt']=''
store.rescan();local l=store.list();assert(#l==3 and l[2].number==3 and l[2].readable==false and store.labels()[2]=='03 — unreadable','unreadable file listed')
assert(store.labels()[3]=='05 — Dropped in');assert(select(2,store.load(3))~=nil and not store.load(3))
assert(store.save_new(frame(2),{label='Second'})==2,'Lowest free number')
assert(store.overwrite(5,frame(9))and F.decode(files['C:/cfg/wj-pose-05.txt']).label=='Dropped in','Overwrite keeps the label')
assert(F.decode(files['C:/cfg/wj-pose-05.txt']).nodes[8].p[1]==17)
fail_write=true;local before=files['C:/cfg/wj-pose-05.txt'];assert(not store.overwrite(5,frame(1))and files['C:/cfg/wj-pose-05.txt']==before,'Failed write leaves the old file');fail_write=false
files['C:/cfg/wj-pose-02.txt.bak']='x';assert(store.delete(2)and files['C:/cfg/wj-pose-02.txt']==nil and files['C:/cfg/wj-pose-02.txt.bak']==nil)
for n=1,99 do files[F.path('C:/cfg',n)]=F.encode(frame(n),{label='n'..n})end;store.rescan()
assert(select(2,store.save_new(frame(1),{label='x'}))=='No free pose number; delete one first','cap reached')
print('Pose files: round trip, rejections, probing, numbering, overwrite, failed write, delete and cap passed')

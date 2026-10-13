local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'focus_sampler.lua');local ffi=require('ffi')
local function integer(v)local out={};for i=1,4 do out[i]=string.char(v%256);v=math.floor(v/256)end;return table.concat(out)end
local function packed(v)local n=ffi.new('float[1]',v);return ffi.string(n,4)end
local function dds(w,h,values)
 local header='DDS '..integer(124)..integer(0x100f)..integer(h)..integer(w)..integer(w*4)..integer(0)..integer(1)..string.rep('\0',44)
 header=header..integer(32)..integer(4)..'DX10'..string.rep('\0',40);assert(#header==128)
 local pixels={};for i=1,w*h do pixels[i]=packed(type(values)=='table'and values[i]or values or 5)end
 return header..integer(41)..integer(3)..integer(0)..integer(1)..integer(0)..table.concat(pixels)
end
local function replace(data,offset,value)return data:sub(1,offset)..integer(value)..data:sub(offset+5)end
local function file(content)
 local at=0;local closed=false;local reads=0
 return {seek=function(_,mode,offset)assert(not closed);if mode=='end'then at=#content+(offset or 0)else at=offset or 0 end;return at end,
 read=function(_,n)assert(not closed);reads=reads+n;local out=content:sub(at+1,at+n);at=at+#out;return #out>0 and out or nil end,
 close=function()closed=true end,bytes_read=function()return reads end}
end
local body=dds(5,5,5);local info=factory.inspect(body:sub(1,148),#body);assert(info.width==5 and info.height==5 and info.format==41)
for _,bad in ipairs({replace(body,128,28),replace(body,132,4),replace(body,136,4),replace(body,140,2),replace(body,112,512),replace(body,28,2),replace(body,20,24),replace(body,16,0),body:sub(1,-2),body..'x'})do
 assert(not pcall(factory.inspect,bad:sub(1,148),#bad),'Malformed, incompatible or multi-surface DDS accepted')
end
assert(not pcall(factory.inspect,body:sub(1,147),#body),'Truncated DX10 header accepted')
for _,point in ipairs({{-.1,0},{1.1,0},{0,-.1},{0,1.1},{0/0,0},{math.huge,0}})do assert(not pcall(factory.read,file(body),unpack(point)))end
local gradient={};for y=0,4 do for x=0,4 do gradient[#gradient+1]=1+y*10+x end end
local top,point=factory.read(file(dds(5,5,gradient)),0,0,{radius=0});assert(top==1 and point.x==0 and point.y==0)
local bottom,point=factory.read(file(dds(5,5,gradient)),1,1,{radius=0});assert(bottom==45 and point.x==4 and point.y==4,'UV1 must map to bottom-right pixel')
local values={};for i=1,25 do values[i]=5 end;values[7],values[13],values[19]=math.huge,50,0/0
local window=file(dds(5,5,values));local distance,point=factory.read(window,.5,.5)
assert(distance==5 and point.samples==7 and window.bytes_read()==148+36,'Median must ignore invalid neighbors and suppress depth outliers with a tiny window')
for _,bad in ipairs({0,-1,math.huge,0/0,10000})do assert(not pcall(factory.read,file(dds(5,5,bad)),.5,.5),'Sky or invalid center accepted')end
values[13]=0;assert(not pcall(factory.read,file(dds(5,5,values)),.5,.5),'Sky center must not focus neighboring objects')

local original_open,original_remove,original_getenv=io.open,os.remove,os.getenv
local files={['C:/Local/keep.dds']='unrelated'};local removed={};local paths={};local calls=0;local now=0;local allowed=true;local mode='ok';local delay=.03;local locked=false
io.open=function(path,access)if access=='rb'and files[path]then return file(files[path])end end
os.remove=function(path)removed[#removed+1]=path;if locked then return nil,'file locked'end;if not files[path]then return nil,'missing'end;files[path]=nil;return true end
os.getenv=function(key)if key=='LOCALAPPDATA'then return'C:/Local'end;return original_getenv(key)end
local sr={Application={save_render_target=function(target,path)
 assert(target=='linear_depth');assert(not files[path],'Readback overwrote another file');calls=calls+1;paths[#paths+1]=path;now=now+delay
 if mode=='throw'then files[path]='partial';error('native readback refused')end
 if mode=='missing'then return end
 if mode=='bad'then files[path]='bad';return end
 files[path]=dds(5,5,gradient)
end}}
local meta={format=1,kind=2,mips=1,array=1,width=5,height=5,identity='depth-a'}
local function guard()return allowed,meta end
local config={now=function()return now end,mkdir=function(path)assert(path=='C:/Local/DBF_PhotoMode'or path=='C:/Local/DBF_PhotoMode/FocusCache');return true end,pid=7,radius=0}
local sampler=assert(factory.new(sr,nil,guard,config));assert(sampler.interval==1 and sampler.path:find('C:/Local/DBF_PhotoMode/FocusCache/',1,true)==1)
assert(not sampler.sample(-1,.5)and calls==0,'Invalid UV must not trigger a readback')
local d,why,metadata=sampler.sample(0,0);assert(d==1 and calls==1 and math.abs(metadata.capture_ms-30)<.001)
now=.4;d,why,metadata=sampler.sample(1,1);assert(d==45 and calls==1 and metadata.cached and metadata.age>.3,'Cooldown must reuse one depth file while allowing another selected subject')
now=1.02;assert(sampler.sample(.5,.5)==23 and calls==1,'Cooldown ends after capture completion')
now=1.1;assert(sampler.sample(.5,.5)==23 and calls==2,'Depth must refresh after cooldown')
assert(#paths==2 and paths[1]==paths[2],'Sampler must reuse one bounded owned file')
meta.identity='depth-b';now=1.3;assert(not sampler.sample(.5,.5)and calls==2 and not files[sampler.path],'Retired target must discard old depth during cooldown')
now=2.2;mode='throw';d,why=sampler.sample(.5,.5);assert(not d and why:find('native readback refused',1,true)and calls==3 and not files[sampler.path],'Native failure must clean partial depth')
now=2.4;assert(not sampler.sample(.5,.5)and calls==3,'Failed readbacks must also respect cooldown')
now=3.3;mode='missing';assert(not sampler.sample(.5,.5)and calls==4 and not files[sampler.path],'Missing readback file must not return stale focus')
now=4.4;mode='bad';assert(not sampler.sample(.5,.5)and calls==5 and not files[sampler.path],'Invalid depth file must be deleted')
now=5.5;mode='ok';assert(sampler.sample(.5,.5)==23 and calls==6)
allowed=false;assert(not sampler.sample(.5,.5)and calls==6 and not files[sampler.path],'Guard refusal must discard cached depth and avoid engine call')
allowed=true;now=7;delay=.6;d,why,metadata=sampler.sample(.5,.5);assert(d==23 and metadata.next_capture>=9.39,'Slow full-surface capture must extend cooldown')
now=8.5;assert(sampler.sample(.5,.5)==23 and calls==7,'Adaptive cooldown must suppress expensive repeated readback')
locked=true;assert(not sampler.release()and files[sampler.path],'Failed cleanup must retain ownership for retry');locked=false
assert(sampler.release()and not files[sampler.path]and files['C:/Local/keep.dds']=='unrelated','Release must only delete the owned cache file')
local other=assert(factory.new(sr,nil,guard,config));assert(other.path~=sampler.path,'Separate samplers need separate owned paths')
files[other.path]='foreign';now=10;local before=calls;assert(not other.sample(.5,.5)and calls==before and files[other.path]=='foreign');assert(other.release()and files[other.path]=='foreign','Never delete a preexisting foreign file')
assert(not factory.new(sr,nil,guard,{now=config.now,mkdir=config.mkdir,pid=7,interval=.1}),'Cooldown below2Hz must be rejected')
meta.format=0;assert(not other.ready(),'Unsupported native depth format must refuse capture');meta.format=1
-- Display changes must pause even when the depth binding itself is unchanged.
local display_meta={format=1,kind=2,mips=1,array=1,width=5,height=5,identity='depth-stable',display_identity='display:hdr:a'}
local function display_guard()return allowed,display_meta end
now=20;delay=.03;local transitioning=assert(factory.new(sr,nil,display_guard,config));before=calls
local d,why=transitioning.sample(.5,.5)
assert(not d and why:find('display settling',1,true)and calls==before,'First display generation must settle before native readback')
now=21.999;assert(not transitioning.sample(.5,.5)and calls==before,'Two-second startup pause must not capture')
now=22;assert(transitioning.sample(.5,.5)==23 and calls==before+1,'Stable initial display must resume normal sampling')
now=22.4;assert(transitioning.sample(.5,.5)==23 and calls==before+1,'Stable display must retain ordinary cached focus')
display_meta.display_identity='display:sdr:a';now=22.5
assert(not transitioning.sample(.5,.5)and calls==before+1 and not files[transitioning.path],'HDR-to-SDR transition must invalidate cached depth before any engine call')
now=23.5;assert(not transitioning.sample(.5,.5)and calls==before+1,'Changed display must suppress readback during settling')
display_meta.display_identity='display:sdr:new-backing';now=24
assert(not transitioning.sample(.5,.5)and calls==before+1,'Another display generation must restart the stable interval')
now=25.999;assert(not transitioning.sample(.5,.5)and calls==before+1)
now=26;assert(transitioning.sample(.5,.5)==23 and calls==before+2,'Stable SDR generation must resume autofocus without changing its chosen mode')
locked=true;display_meta.display_identity='display:hdr:new-backing';now=26.1
assert(not transitioning.sample(.5,.5)and files[transitioning.path]and calls==before+2,'Failed transition cleanup must retain ownership and avoid capture')
locked=false;now=26.2
assert(not transitioning.sample(.5,.5)and not files[transitioning.path]and calls==before+2,'Transition pause must retry bounded owned-file cleanup')
now=28.1;assert(transitioning.sample(.5,.5)==23 and calls==before+3)
allowed=false;now=28.5;assert(not transitioning.sample(.5,.5)and not files[transitioning.path])
allowed=true;now=28.6;assert(not transitioning.sample(.5,.5)and calls==before+3,'Reappearing display must settle after guard unavailability')
now=30.6;assert(transitioning.sample(.5,.5)==23 and calls==before+4)
assert(transitioning.release()and not files[transitioning.path]and files['C:/Local/keep.dds']=='unrelated','Display pause must preserve foreign files')
io.open,os.remove,os.getenv=original_open,original_remove,original_getenv
print('Focus sampler: R32_FLOAT validation, top-origin median depth, sky rejection, bounded cleanup, adaptive cooldown and two-second stable HDR/SDR display-generation pause passed; no game process accessed')

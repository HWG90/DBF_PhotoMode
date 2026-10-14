-- MDL's sandbox _G is a proxy; callbacks must install once into the real game
-- globals and teardown must close only this camera's owned resources.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local file=assert(io.open(root..'mdl.lua','rb'));local template=file:read('*a');file:close()
local function fixture(mcm,body)
 local count={start=0,stop=0,release=0,standalone=0,shared=0,previous=0};local directories,logs,cleanup={},{},{}
 local G={rawget=rawget,rawset=rawset,package={loaded={}},os={getenv=function(name)assert(name=='LOCALAPPDATA');return 'C:/fixture/appdata'end}}
 setmetatable(G,{__index=_G});G._G=G
 local input={release=function()count.release=count.release+1;return true end}
 local files={['src/actioncam_compat.lua']="return {new=function()return {refresh=function()return true end,release=function()return true end,dispose=function()return true end}end}",
 ['src/standalone.lua']="return {new=function(host,sr) _TEST.standalone=_TEST.standalone+1;_TEST.host=host;return {camera_input=_TEST.input}end,shared=function(host,sr,mcm) _TEST.shared=_TEST.shared+1;_TEST.parent=mcm;_TEST.host=host;return setmetatable({camera_input=_TEST.input,photo_standalone=false},{__index=mcm})end}",
 ['src/actioncam.lua']=body or "_TEST.start=_TEST.start+1;local previous=update;update=function(dt)local owner=rawget(_G,'DBF_PHOTO_MODE_OWNER');if not owner.stopped then _TEST.step=(_TEST.step or 0)+1 end;previous(dt)end;return {stop=function()_TEST.stop=_TEST.stop+1;return true end}"}
 G._TEST=count;count.input=input
 G.update=function()count.previous=count.previous+1 end
 G.shutdown=function()error('Must not invoke another provider or game shutdown')end
 G.io={open=function(path,mode)
  assert(mode=='rb');local prefix='C:/fixture/mod/';assert(path:sub(1,#prefix)==prefix,'File read escaped package root')
  local text=files[path:sub(#prefix+1)];if not text then return end
  return {read=function(_,format)assert(format=='*a');return text end,close=function()end}
 end}
 G.require=function(name)
  assert(name=='ffi','Unexpected bootstrap dependency')
  return {cdef=function()end,load=function(name)assert(name=='kernel32');return {CreateDirectoryA=function(path)directories[#directories+1]=path;return 1 end}end}
 end
 G.DBFMCM=mcm
 -- Faithfully model MDL's callback/global proxy. rawget(proxy,'_G') returns G.
 local proxy=setmetatable({},{__index=function(_,key)return G[key]end,__newindex=function()error('MDL sandbox callback/global proxy was mutated')end})
 local env=setmetatable({_G=proxy,rawget=function(tbl,key)if tbl==proxy then return proxy[key]end;return rawget(tbl,key)end},{__index=_G})
 local chunk=assert(loadstring(template,'@PhotoMode-MDL-fixture'));setfenv(chunk,env);local mod=chunk()
 local ctx={api=2,dir='C:/fixture/mod',read=function()error('ctx.read is native memory read, never package file IO')end,
  log=function(message)logs[#logs+1]=message end,on_cleanup=function(fn)cleanup[#cleanup+1]=fn end}
 return mod,ctx,G,count,cleanup,directories,logs
end

local mod,ctx,G,count,cleanup,directories=fixture()
mod.on_enable(ctx);assert(G.DBF_PHOTO_MODE_OWNER and not G.DBF_PHOTO_MODE_STARTED)
mod.on_update(ctx,.016);assert(count.start==0,'Startup must wait for the game API')
G.stingray={};mod.on_update(ctx,.016);mod.on_update(ctx,.016)
assert(count.start==1 and count.standalone==1 and G.DBF_PHOTO_MODE_STARTED,'Standalone camera must start exactly once')
assert(G.DBF_PHOTO_STANDALONE_API and G.DBF_PHOTO_PACKAGE_ROOT==ctx.dir)
assert(count.host.config_dir=='C:/fixture/appdata/DBF/PhotoMode/settings' and #directories==3)
assert(not pcall(count.host.read,'../secrets') and not pcall(count.host.require,'src/../../secrets.lua'),'Private host must reject traversal')
G.update(.016);assert(count.step==1 and count.previous==1)
mod.on_disable(ctx);cleanup[1]();G.update(.016)
assert(count.stop==1 and count.release==1 and G.DBF_PHOTO_STANDALONE_API==nil,'Teardown must be owned and idempotent')
assert(count.step==1 and count.previous==2,'Disabled camera hooks must remain inert while preserving the game update')
assert(G.DBF_PHOTO_MODE_OWNER.stopped and G.DBF_PHOTO_MODE_STARTED,'Hook reservation must remain until normal restart')
assert(not pcall(mod.on_enable,ctx),'A restart is required after retained hooks stop')

local external_release=0;local external_input={set_focus=function()end,release=function()external_release=external_release+1;return true end}
local shared={camera_input=external_input,create_photo_view=function()end,settings={held='external'}}
local second,c2,g2,n2=fixture(shared);g2.stingray={};second.on_enable(c2);second.on_update(c2)
assert(n2.start==1 and n2.standalone==0 and n2.shared==1 and g2.DBF_PHOTO_STANDALONE_API==nil,'Existing MCM must receive a Photo-owned input facade instead of a private settings service')
assert(g2.DBF_PHOTO_CAMERA_API and g2.DBF_PHOTO_CAMERA_API.camera_input==n2.input and g2.DBF_PHOTO_CAMERA_API.settings==shared.settings and n2.parent==shared,'The facade must proxy MCM settings while owning only its camera input')
second.on_disable(c2);assert(n2.stop==1 and n2.release==1 and external_release==0 and g2.DBF_PHOTO_CAMERA_API==nil and g2.DBFMCM==shared and shared.camera_input==external_input and shared.settings.held=='external','Teardown must release only facade input and preserve external MCM input/settings/global')

local failed,c3,g3,n3,_,_,logs=fixture(nil,"error('partial camera startup')")
g3.stingray={};failed.on_enable(c3);failed.on_update(c3);failed.on_update(c3)
assert(g3.DBF_PHOTO_MODE_OWNER.failed and g3.DBF_PHOTO_MODE_OWNER.stopped and not g3.DBF_PHOTO_MODE_STARTED)
assert(n3.standalone==1 and n3.release==1 and g3.DBF_PHOTO_STANDALONE_API==nil and #logs==1,'Failed startup must close owned resources and never retry hooks')

local invalid,c4,g4=fixture();c4.api=1;assert(not pcall(invalid.on_enable,c4) and not g4.DBF_PHOTO_MODE_OWNER,'Wrong MDL API must be rejected before ownership is claimed')
local duplicate,c5,g5,n5=fixture();g5.DBF_PHOTO_MODE_OWNER={provider='BSL'}
assert(not pcall(duplicate.on_enable,c5) and n5.start==0 and g5.DBF_PHOTO_MODE_OWNER.provider=='BSL','MDL must not replace another provider')
print('MDL adapter: real-global sandbox contract, isolated file host, standalone/shared MCM, startup guards and idempotent owned teardown passed')

-- Cursor flags belong to a later external owner; restore only our own lease.
do
 local Capture=dofile(root..'photo_input_capture.lua');local active=false;local throws=false
 local focus,cursor,clip=true,false,false;local writes={};local refusal;local bad_readback=false
 local function setter(name,value)writes[#writes+1]={name,value};if refusal==name then return false end
  if not bad_readback then if name=='focus'then focus=value elseif name=='cursor'then cursor=value else clip=value end end;return true
 end
 local window={mouse_focus=function()return focus end,show_cursor=function()return cursor end,clip_cursor=function()return clip end,
  set_mouse_focus=function(v)return setter('focus',v)end,set_show_cursor=function(v)return setter('cursor',v)end,set_clip_cursor=function(v)return setter('clip',v)end}
 local capture=Capture.new(window,function()if throws then error('Parent ownership unavailable')end;return active end)
 active=true;assert(capture.acquire('photo')==nil and #writes==0,'Foreign ownership must refuse a new lease without changing Window flags')
 active=nil;assert(capture.acquire('photo')==nil);throws=true;assert(capture.acquire('photo')==nil);throws=false
 active=false;local token=assert(capture.acquire('photo'));assert(capture.owns(token)and capture.status().owner=='photo')
 focus,cursor,clip=false,true,true;active=true;assert(capture.release(token)and not capture.owns(token)and #writes==0 and focus==false and cursor==true and clip==true,'Foreign takeover must drop only the Photo lease and leave its current Window flags intact')
 active=false;focus,cursor,clip=true,false,false;token=assert(capture.acquire('photo'));focus,cursor,clip=false,true,true
 active=nil;assert(capture.release(token)==false and capture.owns(token)and #writes==0,'Unknown release ownership must retain a retryable lease without cursor writes')
 throws=true;assert(capture.release(token)==false and capture.owns(token)and #writes==0,'Parent-reader exceptions must retain release ownership for retry without cursor writes');throws=false
 active=false;refusal='cursor';assert(capture.release(token)==false and capture.owns(token)and focus==true and cursor==true,'Refused cursor restoration must retain the lease after partial restoration')
 refusal=nil;writes={};assert(capture.release(token)and not capture.owns(token)and focus==true and cursor==false and clip==false)
 assert(#writes==2 and writes[1][1]=='cursor'and writes[2][1]=='clip','A retry must restore only flags still different from the saved state')
 token=assert(capture.acquire('photo'));focus=false;bad_readback=true;assert(capture.release(token)==false and capture.owns(token),'Accepted writes with failed readback must retain a retryable lease')
 bad_readback=false;writes={};assert(capture.release(token)and #writes==1 and writes[1][1]=='focus'and focus==true)
 token=assert(capture.acquire('photo'));writes={};assert(capture.release(token)and #writes==0,'Unchanged flags must release without redundant Window writes')
 assert(capture.release(token)==false,'An already released token must not restore another owner')
end
print('Photo cursor ownership: foreign takeover, unknown/error release, partial restore and readback retries passed')

-- The actual shared facade must deny unknown or superseded parent ownership.
do
 local Standalone=dofile(root..'standalone.lua');local actual_input=Standalone.input
 local available,parent;local old_mcm=rawget(_G,'DBFMCM');local open=false;local status={active=false,pending_restore=false};local throws=false
 local marker={};local mcm={settings=marker,camera_input=external_input,is_open=function()if throws then error('MCM menu unavailable')end;return open end,
  input_status=function()if throws then error('MCM status unavailable')end;return status end}
 Standalone.input=function(host,sr,a,p)assert(host==marker and sr==marker);available,parent=a,p;return marker end
 DBFMCM=mcm;local facade=Standalone.shared(marker,marker,mcm)
 assert(facade~=mcm and facade.camera_input==marker and facade.settings==marker and facade.photo_input_parent==mcm and facade.photo_standalone==false and mcm.camera_input==external_input)
 assert(available()==true and parent()==false,'Known idle MCM ownership must permit the Photo lease')
 local function denied()local ok,value=pcall(available);assert(not ok or value~=true,'Unknown/foreign MCM ownership must deny Photo acquisition')end
 open=true;denied();open=false
 status.owner='other';denied();status.owner=nil
 status.active=true;denied();status.active=false
 status.pending_restore=true;denied();status.pending_restore=false
 status=nil;denied();status={active=false};denied();status={active=0,pending_restore=false};denied()
 status={active=false,pending_restore=false};open=nil;denied();open=0;denied();open=false
 throws=true;denied();throws=false
 DBFMCM={};denied();DBFMCM=mcm;assert(available()==true)
 Standalone.input=actual_input;DBFMCM=old_mcm
end

print('Photo-owned input: MCM facade teardown isolation, strict parent availability, foreign cursor takeover, unknown release retention and exact readback/retry restoration passed')

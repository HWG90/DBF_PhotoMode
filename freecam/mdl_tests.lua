-- MDL's sandbox _G is a proxy; callbacks must install once into the real game
-- globals and teardown must close only this camera's owned resources.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local file=assert(io.open(root..'mdl.lua','rb'));local template=file:read('*a');file:close()
local function fixture(mcm,body)
 local count={start=0,stop=0,release=0,standalone=0,previous=0};local directories,logs,cleanup={},{},{}
 local G={rawget=rawget,rawset=rawset,package={loaded={}},os={getenv=function(name)assert(name=='LOCALAPPDATA');return 'C:/fixture/appdata'end}}
 setmetatable(G,{__index=_G});G._G=G
 local input={release=function()count.release=count.release+1;return true end}
 local files={['src/standalone.lua']="return {new=function(host,sr) _TEST.standalone=_TEST.standalone+1;_TEST.host=host;return {camera_input=_TEST.input}end}",
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

local shared={camera_input={set_focus=function()end},create_photo_view=function()end}
local second,c2,g2,n2=fixture(shared);g2.stingray={};second.on_enable(c2);second.on_update(c2)
assert(n2.start==1 and n2.standalone==0 and g2.DBF_PHOTO_STANDALONE_API==nil,'Existing compatible MCM must be reused without creating private input')
second.on_disable(c2);assert(n2.stop==1 and n2.release==0,'Shared MCM input must not be torn down by the adapter')

local failed,c3,g3,n3,_,_,logs=fixture(nil,"error('partial camera startup')")
g3.stingray={};failed.on_enable(c3);failed.on_update(c3);failed.on_update(c3)
assert(g3.DBF_PHOTO_MODE_OWNER.failed and g3.DBF_PHOTO_MODE_OWNER.stopped and not g3.DBF_PHOTO_MODE_STARTED)
assert(n3.standalone==1 and n3.release==1 and g3.DBF_PHOTO_STANDALONE_API==nil and #logs==1,'Failed startup must close owned resources and never retry hooks')

local invalid,c4,g4=fixture();c4.api=1;assert(not pcall(invalid.on_enable,c4) and not g4.DBF_PHOTO_MODE_OWNER,'Wrong MDL API must be rejected before ownership is claimed')
local duplicate,c5,g5,n5=fixture();g5.DBF_PHOTO_MODE_OWNER={provider='BSL'}
assert(not pcall(duplicate.on_enable,c5) and n5.start==0 and g5.DBF_PHOTO_MODE_OWNER.provider=='BSL','MDL must not replace another provider')
print('MDL adapter: real-global sandbox contract, isolated file host, standalone/shared MCM, startup guards and idempotent owned teardown passed')

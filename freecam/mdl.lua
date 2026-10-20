-- MDL API 2 alternative. The camera's global hooks remain reserved until restart.
local G=rawget(_G,'_G')or _G
local get,set=G.rawget,G.rawset
local state={provider='MDL',version='__VERSION__',started=false,failed=false,stopped=false}
local host,standalone,camera_api,owned,camera_owner
local function cleanup()
 state.stopped=true
 if owned and owned.stop then
  local ok,why=owned.stop();if ok==false then error(tostring(why))end;owned=nil
 end
 if standalone and get(G,'DBF_PHOTO_STANDALONE_API')==standalone then
  if standalone.camera_input then local ok,why=standalone.camera_input.release();if ok==false then error(tostring(why))end end
  set(G,'DBF_PHOTO_STANDALONE_API',nil)
 end
 if camera_api and get(G,'DBF_PHOTO_CAMERA_API')==camera_api then
  local ok,why=camera_api.camera_input.release();if ok==false then error(tostring(why))end
  set(G,'DBF_PHOTO_CAMERA_API',nil)
 end
 if camera_owner then local ok,why=camera_owner.dispose();if ok==false then error(tostring(why))end;camera_owner=nil end
end
local function start(ctx)
 if state.started or state.failed or state.stopped then return end
 local sr=get(G,'stingray');if not sr then return end
 camera_owner=host.require('src/camera_ownership.lua').new(G,ctx.log)
 local ready,reason=camera_owner.refresh();assert(ready,reason)
 set(G,'DBF_PHOTO_CAMERA_OWNERSHIP',camera_owner)
 local mcm=get(G,'DBFMCM')
 if mcm then
  assert(mcm.camera_input and mcm.camera_input.set_focus and mcm.create_photo_view,'Update MCM for shared photo input, or disable it and restart for standalone controls')
  camera_api=host.require('src/standalone.lua').shared(host,sr,mcm)
  set(G,'DBF_PHOTO_CAMERA_API',camera_api)
 else
  standalone=host.require('src/standalone.lua').new(host,sr)
  set(G,'DBF_PHOTO_STANDALONE_API',standalone)
 end
 set(G,'DBF_PHOTO_PACKAGE_ROOT',host.dir)
 local chunk=assert(G.loadstring(assert(host.read('src/camera_runtime.lua')),'@WarJournalist/PhotoMode-MDL-runtime.lua'))
 G.setfenv(chunk,G);owned=chunk()
 assert(type(owned)=='table'and type(owned.stop)=='function','Owned camera cleanup contract missing')
 state.started=true;set(G,'DBF_PHOTO_MODE_STARTED',true)
 ctx.log('War Journalist __VERSION__ enabled; camera hooks require a normal restart after disabling or changing packages')
end
return {name='War Journalist',version='__VERSION__',author='Goose',
 description='Photo Mode. MCM optional. Preview; focus/f-stop and scene shaders disabled. Normal restart required after disabling/reloading.',
 on_enable=function(ctx)
  assert(ctx.api==2 and type(ctx.dir)=='string'and type(ctx.on_cleanup)=='function','MDL API 2 required')
  assert(not get(G,'DBF_PHOTO_CAMERA_RUNTIME')and not get(G,'DBF_PHOTO_MODE_OWNER')and not get(G,'DBF_PHOTO_MODE_STARTED')and not get(G,'DBF_PHOTO_SAFE_EFFECTS'),'Another Photo Mode provider has installed camera hooks; choose one package and restart')
  set(G,'DBF_PHOTO_MODE_OWNER',state)
  local appdata=assert(G.os.getenv('LOCALAPPDATA'),'Local AppData unavailable')
  local ffi=G.require('ffi');pcall(ffi.cdef,'int CreateDirectoryA(const char *,void *);')
  local kernel=ffi.load('kernel32');local config=appdata
  for _,part in ipairs({'DBF','PhotoMode','settings'})do config=config..'/'..part;kernel.CreateDirectoryA(config,nil)end
  host={dir=ctx.dir,config_dir=config,log=ctx.log};local cache={}
  function host.read(name)
   assert(type(name)=='string'and name:match('^[%w_/%.-]+$')and not name:find('..',1,true)and name:sub(1,1)~='/','Invalid photo package path')
   local file=G.io.open(host.dir..'/'..name,'rb');if not file then return end
   local body=file:read('*a');file:close();return body
  end
  function host.require(name)
   if cache[name]~=nil then return cache[name]end
   assert(name:match('^src/[%w_/-]+%.lua$'),'Invalid photo module path')
   local chunk=assert(G.loadstring(assert(host.read(name)),'@WarJournalist/'..name));G.setfenv(chunk,G)
   local value=chunk();cache[name]=value or true;return cache[name]
  end
  ctx.on_cleanup(cleanup)
 end,
 on_update=function(ctx)
  if state.started or state.failed or state.stopped then return end
  local ok,why=pcall(start,ctx)
  if not ok then state.failed=true;cleanup();ctx.log('Photo Mode startup failed: '..tostring(why)..'; restart before retrying')end
 end,
 on_disable=function(ctx)
  cleanup();ctx.log('Photo Mode stopped; retained camera hooks are inert until a normal restart')
 end}

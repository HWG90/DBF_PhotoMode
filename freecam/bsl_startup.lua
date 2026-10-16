-- HD2-Addon: mods/dbf_photomode/startup
-- Bingus Shared Loader startup. All runtime resources are embedded in this entry.
local ffi=require('ffi')
pcall(ffi.cdef,'int CreateDirectoryA(const char *,void *);')
local kernel=ffi.load('kernel32')
local appdata=assert(os.getenv('LOCALAPPDATA'),'Local AppData unavailable')
local root=appdata..'/DBF';kernel.CreateDirectoryA(root,nil)
root=root..'/PhotoMode';kernel.CreateDirectoryA(root,nil)
local function log(message)
 local file=io.open(root..'/PhotoMode-startup.log','a')
 if file then file:write(tostring(message),'\n');file:close()end
end
local occupied=rawget(_G,'DBF_PHOTO_MODE_OWNER')
if occupied or rawget(_G,'DBF_PHOTO_MODE_STARTED')or rawget(_G,'DBF_PHOTO_SAFE_EFFECTS')then
 log('Another Photo Mode provider is already active; choose one package and restart.');return
end
local files={
-- __EMBEDDED_FILES__
}
local cache={}
local function body(name)
 local value=assert(files[name],'Photo package resource missing: '..tostring(name))
 if type(value)=='table'then return(value.hex:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))end
 return value
end
local function write_native(name)
 assert(name:match('^[%w_%-]+%.dll$'),'Invalid native library name')
 local payload=body(name);local path=root..'/'..name;local existing=io.open(path,'rb');local matches=false
 if existing then matches=existing:read('*a')==payload;existing:close()end
 if not matches then local file=assert(io.open(path,'wb'));assert(file:write(payload));assert(file:close())end
end
local native=body('standalone-library.txt'):match('^(mcm_input_%x+%.dll)%s*$');assert(native,'Photo input library manifest invalid')
write_native(native);write_native('__CAPTURE_LIBRARY__')
if files['assets/helldivers_cursor.cur']then
 kernel.CreateDirectoryA(root..'/assets',nil)
 local payload=body('assets/helldivers_cursor.cur');local path=root..'/assets/helldivers_cursor.cur'
 local existing=io.open(path,'rb');local matches=false
 if existing then matches=existing:read('*a')==payload;existing:close()end
 if not matches then local file=assert(io.open(path,'wb'));assert(file:write(payload));assert(file:close())end
end
local config=root..'/settings';kernel.CreateDirectoryA(config,nil)
local host={dir=root,config_dir=config,log=log}
function host.read(name)return files[name]and body(name)or nil end
function host.require(name)
 if cache[name]~=nil then return cache[name]end
 assert(type(name)=='string'and name:match('^src/[%w_/-]+%.lua$')and not name:find('..',1,true),'Invalid photo module path')
 local chunk=assert(loadstring(body(name),'@WarJournalist/'..name));setfenv(chunk,_G)
 local value=chunk();cache[name]=value or true;return cache[name]
end
local state={provider='BSL',version='__VERSION__',started=false,failed=false}
rawset(_G,'DBF_PHOTO_MODE_OWNER',state)
local previous_update=assert(rawget(_G,'update'),'Game update callback unavailable')
local previous_shutdown=rawget(_G,'shutdown');local standalone,camera_api,camera_owner
local function start()
 if state.started or state.failed then return end
 local sr=rawget(_G,'stingray');if not sr then return end
 camera_owner=host.require('src/camera_ownership.lua').new(_G,log)
 local ready,reason=camera_owner.refresh();if not ready then state.failed=true;log(reason);return end
 rawset(_G,'DBF_PHOTO_CAMERA_OWNERSHIP',camera_owner)
 local mcm=rawget(_G,'DBFMCM')
 if mcm then
  if not mcm.camera_input or not mcm.camera_input.set_focus or not mcm.create_photo_view then
   state.failed=true;if camera_owner then pcall(camera_owner.dispose)end;log('Update MCM for shared photo input, or disable MCM and restart for standalone controls.');return
  end
  camera_api=host.require('src/standalone.lua').shared(host,sr,mcm)
  rawset(_G,'DBF_PHOTO_CAMERA_API',camera_api)
 else
  standalone=host.require('src/standalone.lua').new(host,sr)
  rawset(_G,'DBF_PHOTO_STANDALONE_API',standalone)
 end
 rawset(_G,'DBF_PHOTO_PACKAGE_ROOT',root)
 local chunk=assert(loadstring(body('src/camera_runtime.lua'),'@WarJournalist/PhotoMode-runtime.lua'));setfenv(chunk,_G)
 chunk();state.started=true;rawset(_G,'DBF_PHOTO_MODE_STARTED',true)
 log('War Journalist __VERSION__ enabled through Bingus Shared Loader; MCM is optional.')
end
local wrapper
wrapper=function(dt,...)
 if not state.started and not state.failed then
  local ok,why=pcall(start);if not ok then state.failed=true;if camera_owner then pcall(camera_owner.dispose)end;log('Photo Mode startup failed: '..tostring(why))end
 end
 return previous_update(dt,...)
end
rawset(_G,'update',wrapper)
rawset(_G,'shutdown',function(...)
 if camera_api and rawget(_G,'DBF_PHOTO_CAMERA_API')==camera_api then
  pcall(camera_api.camera_input.release)
  rawset(_G,'DBF_PHOTO_CAMERA_API',nil)
 end
 if standalone and rawget(_G,'DBF_PHOTO_STANDALONE_API')==standalone then
  if standalone.camera_input then pcall(standalone.camera_input.release)end
  rawset(_G,'DBF_PHOTO_STANDALONE_API',nil)
 end
 if type(previous_shutdown)=='function'then return previous_shutdown(...)end
end)
log('War Journalist startup prepared; camera hooks start once after game initialization.')
return state

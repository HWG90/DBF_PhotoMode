-- Entry contract only. No real loader, helper, GUI, filesystem or native calls.
local globals={mod=mod,stingray=stingray,loader=LiveLuaLoader,owner=DBF_PHOTO_MODE_OWNER}
local function service()
 local caps={async=true,game_window=true,format='png',color_space='sdr',max_jobs=1}
 return{version=1,capabilities=caps,output_directory='C:/captures',
  new_job_token=function()end,request=function()end,status=function()end,cancel=function()end},caps
end
local qualified_revision='R33-steam-screenshots-factoryfix-candidate'
local function trial(backend,expected,loader_caps,subject_case,ffi_case)
 -- A loader may still offer cffi; the entry must never import it or ffi.
 local saved={cffi={package.preload.cffi,package.loaded.cffi},ffi={package.preload.ffi,package.loaded.ffi}};local ffi_imports=0
 for name in pairs(saved)do
  package.loaded[name]=nil;package.preload[name]=function()ffi_imports=ffi_imports+1;if ffi_case then return{}end;error('No CFFI build')end
 end
 local required={};local created;local disposed=false
 local composition,art,crest,decorative={},{},{},{}
 local camera_service={};local input_service={}
 local runtime={tick=function()end,dispose=function()disposed=true;return true end}
 LiveLuaLoader={capabilities=loader_caps or{native_ffi=false,revision=qualified_revision},capture_service=backend,input_service=input_service}
 local subject,bank,avatar_session={}, {}, newproxy()
 local session_reads=0
 DBF_PHOTO_MODE_OWNER=nil;stingray={Network={game_session=function()
  session_reads=session_reads+1
  if subject_case=='trailing_nil'then return avatar_session,nil end
  if subject_case=='two'then return avatar_session,avatar_session end
  if subject_case=='missing'then return end
  if subject_case=='wrong_type'then return 1 end
  return avatar_session
 end}}
 mod={log=function()end,require=function(path)
  required[path]=true
  if path=='src/steam_runtime.lua'then return{new=function(host,sr,deps,input)
   assert(host==mod and sr==stingray and input==input_service)
   assert(deps.ai==nil and deps.load_ai==nil,'The Lua 5.1 build has no FFI enemy behavior')
   assert(deps.hosted_bindings==nil,'LLL keeps our own key bindings')
   assert(ffi_imports==0,'Entry imported cffi or ffi')
   assert(type(deps.load_scene)=='function'and type(deps.load_hover)=='function','Keep the other feature factories')
   assert(deps.decorative_overlay==decorative,'Declare the optional decorative adapter in the module graph')
   assert(deps.composition==composition and composition.logo_art==art and art[2]==crest,
    'Load composition assets without changing the capture service gate')
   assert((deps.capture_backend~=nil)==expected,'Incorrect optional capture gate')
   if expected then assert(deps.capture_backend==backend and deps.capture==camera_service)end
   local subject_admitted=LiveLuaLoader.capabilities.revision=='R34-steam-lua51-preview.1'
   assert((type(deps.load_subject)=='function')==subject_admitted,'Incorrect development Subject admission')
   assert(session_reads==0 and not required['src/steam_subject_native.lua']and not required['src/steam_subject.lua']and
    not required['src/assets/steam_subject_poses.lua'],'Do not read sessions or load Subject before explicit enable')
   if subject_case then
    local frozen=function()return true end
    local value=deps.load_subject(stingray,frozen)
    assert(session_reads==1,'Explicit enable reads the current session once')
    if subject_case=='valid'then assert(value==subject)
    else assert(value==nil and not required['src/steam_subject_native.lua'],'Reject unexpected session return slots before native creation')end
   end
   created=true;return runtime
  end}end
  if path=='src/steam_capture.lua'then return camera_service end
  if path=='src/steam_overlay.lua'then return decorative end
  if path=='src/composition.lua'then return composition end
  if path=='src/assets/logo_art.lua'then return art end
  if path=='src/assets/helldiver_crest.lua'then return crest end
  if path=='src/assets/steam_subject_poses.lua'then return bank end
  if path=='src/steam_subject_native.lua'then return{new=function(sr,policy)
   assert(sr==stingray and policy.session==avatar_session and policy.qualified==true and
    policy.contract=='unit-pose-sync-v1'and policy.qualification=='R34-unit-pose12-private-roundtrip-20261020-v1')
   return subject
  end}end
  if path=='src/steam_subject.lua'then return{new=function(native,poses,frozen)
   assert(native==subject and poses==bank and type(frozen)=='function');return subject
  end}end
  return{}
 end}
 local entry=dofile('freecam/steam51.lua');entry.on_enable()
 assert(created and DBF_PHOTO_MODE_OWNER==runtime)
 assert((required['src/steam_capture.lua']==true)==expected,'Do not load capture on unavailable services')
 entry.on_update();assert(entry.on_disable()and disposed and DBF_PHOTO_MODE_OWNER==nil)
 assert(ffi_imports==0,'Entry imported cffi or ffi')
 for name,pair in pairs(saved)do package.preload[name],package.loaded[name]=pair[1],pair[2]end
end
trial(nil,false);trial(false,false);trial(nil,false,nil,nil,true)
local valid,caps=service();trial(valid,true)
trial(valid,true,{native_ffi=false,revision='R34-steam-lua51-preview.1'})
for _,case in ipairs({'valid','trailing_nil','two','missing','wrong_type'})do
 trial(valid,true,{native_ffi=false,revision='R34-steam-lua51-preview.1'},case)
end
for _,revision in ipairs({'R33-steam-screenshots-candidate','R31-steam-lua51-candidate','R34-steam-lua51-preview.2','R34', '',1,false})do
 trial(valid,false,{native_ffi=false,revision=revision})
end
trial(valid,false,{native_ffi=false})
trial(valid,true,setmetatable({},{__index={native_ffi=false,revision=qualified_revision},__metatable=false,
 __newindex=function()error('readonly')end}))
-- LLL exposes read-only proxy capabilities through ordinary indexing.
valid.capabilities=setmetatable({},{__index=caps,__metatable=false,
 __newindex=function()error('readonly')end})
assert(next(valid.capabilities)==nil);trial(valid,true)
for _,field in ipairs({'async','game_window','format','color_space','max_jobs'})do
 local backend,values=service();values[field]=nil;trial(backend,false)
end
for _,field in ipairs({'new_job_token','request','status','cancel'})do
 local backend=service();backend[field]=nil;trial(backend,false)
end
for _,version in ipairs({0,2,'1'})do local backend=service();backend.version=version;trial(backend,false)end
for _,directory in ipairs({'',false,1})do local backend=service();backend.output_directory=directory;trial(backend,false)end
local backend=service();backend.capabilities=false;trial(backend,false)
-- Boot Mod Loader hands in an engine host: no LLL global, engine keys, same-build Subject admission.
do
 local input_service,bindings={},{window='HD2 Mod Setting GUI'};local created,policy,subject,hosted
 LiveLuaLoader,DBF_PHOTO_MODE_OWNER,stingray=nil,nil,{}
 mod={log=function()end,host_loader={engine_input=true,input_service=input_service,bindings=bindings,capabilities={revision='boot-mod-loader-host.1'}},
  require=function(path)
   if path=='src/steam_runtime.lua'then return{new=function(host,sr,deps,input)
    assert(input==input_service and deps.capture_backend==nil,'Engine host input, no capture service')
    policy,subject,hosted,created=deps.input_policy,deps.load_subject,deps.hosted_bindings,true
    return{tick=function()end,dispose=function()return true end}
   end}end
   return{}
  end}
 local entry=dofile('freecam/steam51.lua');entry.on_enable()
 assert(created and policy.require_keyboard==false and type(subject)=='function','Engine host: engine keys and Subject admission')
 assert(hosted and hosted.api==bindings and hosted.window=='HD2 Mod Setting GUI','Engine host hands in its bindings helper')
 assert(entry.on_disable()and DBF_PHOTO_MODE_OWNER==nil)
end
mod,stingray,LiveLuaLoader,DBF_PHOTO_MODE_OWNER=globals.mod,globals.stingray,globals.loader,globals.owner
print('Steam entry: no FFI imports or AI, engine host, capture gates, lazy R34 Subject admission, exact session return slots and older-loader camera fallback passed')

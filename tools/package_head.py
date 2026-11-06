"""The head of the one War Journalist package: one resource that runs under Boot Mod Loader,
LLL or Chef Shared Loader and picks its host from the loader's argument (a table is Chef's
helpers; nil, from Boot Mod Loader's xpcall, or the mod's name, from LLL, is not).
compose() writes the whole Lua text; build_package.py packs and proves it."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = 'mods/goose/war_journalist'
ID = 'dbf_freecam_lua51'
TITLE = 'War Journalist'
MINIMUM_CHEF = '1.4.0'
# Chef 1.5.1 never runs a Lua resource over 4 MiB (MAX_LUA); keep clear of it.
MAX_BYTES = 3_800_000
# HD2 Arsenal: the entry 1.3.x players already have, one option with the assets.
GUID = '7020a1c8-01ed-4a9d-874f-f778916eb067'
OPTION = 'War Journalist'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
# The 1.3.0 assets, unchanged since.
ASSETS_SHA256 = {
    '9ba626afa44a3aa3.patch_0': 'de5e7ace103a5f7121c57acaa3b4b323c60955309a31b04175bdc6f05028c8b2',
    '9ba626afa44a3aa3.patch_0.gpu_resources': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    '9ba626afa44a3aa3.patch_0.stream': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'ee6b1ba7e22d71ed.patch_0': 'adc229713e0573007e8b34dd7a7fb69a8de8cd92a0a75aa0e1bbfa46777de2be',
    'ee6b1ba7e22d71ed.patch_0.gpu_resources': 'feed3eb14f8c3becd21698c1f73a7f116a532f54ce22009c3f992052f76e2f5d',
    'ee6b1ba7e22d71ed.patch_0.stream': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
}


def long_string(text):
    """Lua long bracket holding text exactly (no CR; first newline is skipped by Lua)."""
    assert '\r' not in text, 'CR would be normalized inside a long string'
    level = 0
    while True:
        close = ']' + '=' * level + ']'
        if (text + close).find(close) == len(text):
            return '[' + '=' * level + '[\n' + text + close
        level += 1


def build_id():
    """Shown under Photo Mode: the UTC build time and source commit, '+' when the tree has
    uncommitted changes."""
    import datetime, subprocess
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d.%H%M')
    git = lambda *a: subprocess.run(['git', *a], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    commit = git('rev-parse', '--short=7', 'HEAD') or 'nogit'
    return stamp + '-' + commit + ('+' if git('status', '--porcelain') else '')

# One module loader for every host: each module compiled once, on first use, in the mod's scope.
REQUIRER = r'''
local function requirer(mod,scope)
 local cache,loading={},{}
 function mod.require(path,...)
  if cache[path]~=nil then return cache[path]end
  assert(not loading[path],'Circular module import: '..path)
  local source=assert(SOURCES[path],'Module not declared in this project: '..path)
  local chunk=assert(loadstring(source,'@'..ID..'/'..path));setfenv(chunk,scope);SOURCES[path]=nil
  loading[path]=true;local called,value=pcall(chunk,...);loading[path]=nil
  if not called then error(value,2)end
  if value==nil then value=true end;cache[path]=value;return value
 end
 return mod.require
end
'''

# Boot Mod Loader drives the entry itself; LLL takes the entry back and drives it.
BOOT_HOST = r'''
local function boot_host()
 local function env(name)local value=os.getenv(name);return value and value:gsub('\\','/'):gsub('/+$','')end
 local function writable(dir)local probe=dir..'/.wj-probe';local f=io.open(probe,'wb');if not f then return false end;f:close();os.remove(probe);return true end
 local game=assert(env('APPDATA'),'APPDATA unavailable')..'/Arrowhead/Helldivers2'
 local lll=env('LOCALAPPDATA')and env('LOCALAPPDATA')..'/LLL/Helldivers2'
 -- The project surface LLL gives folder mods. LLL's folders when they exist, else the
 -- game's own settings folder, which every install has.
 local mod={id=ID,name=TITLE,version=VERSION,build=BUILD,release_mode=RELEASE_MODE,native_dir=lll and writable(lll..'/Native')and lll..'/Native'or game,
  config_dir=lll and writable(lll..'/Settings/'..ID)and lll..'/Settings/'..ID or game}
 local LOG=game..'/war_journalist_lua51.log'
 local log_mode='ab'
 local probe=io.open(LOG,'rb')
 if probe then local size=probe:seek('end');probe:close();if size and size>4194304 then log_mode='wb'end end
 function mod.log(message)
  print('['..TITLE..'] '..tostring(message))
  local f=io.open(LOG,log_mode);log_mode='ab';if f then f:write(os.date('%Y-%m-%d %H:%M:%S '),tostring(message),'\n');f:close()end
 end
 -- Windows refuses unsigned in-process DLLs (error 577), so no bridge is written or loaded
 -- on any host, under Proton too: it behaves as it does on Windows.
 mod.native_libraries=false
 requirer(mod,setmetatable({mod=mod},{__index=_G}))
 local dev_module,dev_pinned
 if not mod.release_mode and not rawget(_G,'LiveLuaLoader')then
  local probe=io.open(game..'/wj-dev-reload.enabled','rb')
  local armed=probe and probe:read(65);if probe then probe:close()end
  if armed=='wjl-dev-reload-v1\n'then
   dev_pinned={}
   for _,name in ipairs({'windows_dev_reload.lua','windows_input_service.lua','engine_input.lua','vendor/wjl_transport.lua','vendor/wjl_capture.lua','vendor/wjl_input_service.lua','wjl_helper_payload.lua','wjl_helper_startup.lua'})do
    local path='src/'..name;dev_pinned[path]=assert(SOURCES[path])
   end
   dev_module=mod.require('src/windows_dev_reload.lua')
  end
 end
 -- 1.3.x was mods/goose/war_journalist_lua51, and Boot Mod Loader names its key file after the
 -- mod; it reads the file when the first key registers (on_enable). Copy the old one across once.
 do
  local new=io.open(game..'/mbm_war_journalist_settings.txt','rb')
  if new then new:close()else
   local old=io.open(game..'/mbm_war_journalist_lua51_settings.txt','rb')
   if old then
    local data=old:read('*a');old:close()
    local f=data and io.open(game..'/mbm_war_journalist_settings.txt','wb')
    if f then f:write(data);f:close();mod.log('Keys carried over from mbm_war_journalist_lua51_settings.txt')end
   end
  end
 end
 mod.log('War Journalist '..VERSION..' ('..BUILD..') session started')
 local entry=mod.require('main.lua')
 -- Live Lua Loader runs archive entries itself (LLL API 1).
 if rawget(_G,'LiveLuaLoader')then return entry end
 -- Boot Mod Loader only runs this file: hand in an engine host and drive the entry from
 -- the game's update and shutdown, as LLL would.
 local bindings=rawget(_G,'ModBindingsMenu')
 if not(type(bindings)=='table'and type(bindings.register_binding)=='function'and type(bindings.is_down)=='function'and type(bindings.binding)=='function')then bindings=nil end
 if dev_module then bindings=dev_module.bindings(bindings)end
 local function clock()local ok,t=pcall(function()return stingray.Application.time_since_launch()end);return ok and type(t)=='number'and t or os.clock()end
 -- WJL starts beside the game: the game never waits on it, here or on any later frame.
 -- Photo Mode starts once the helper answers, or without it once it is known unavailable.
 local input_service,input_driver,input_pending
 local function without_helper(why)
  mod.log('Input helper unavailable: '..tostring(why))
  return mod.require('src/engine_input.lua').new(stingray,mod.log)
 end
 local launched,why=pcall(function()input_pending=mod.require('src/windows_input_service.lua').start(mod,stingray,clock)end)
 if not launched then input_service=without_helper(why)end
 mod.host_loader={engine_input=true,allow_shared_keys=true,require_keyboard=true,input_service=input_service,bindings=bindings,capabilities={revision='boot-mod-loader-r34-input.1'}}
 local state='waiting'
 -- Read-only native diagnostics at start and twice later, while subject/hover fail here.
 local diagnose_at,started_at=RELEASE_MODE and{}or{0,30,120}
 local hud_probe,hud_probe_at=nil,0
 if RELEASE_MODE then hud_probe=false end
 local dev_reload=dev_module and dev_module.new(mod,entry,clock,os.clock,nil,{directory=game,pinned=dev_pinned})
 if dev_reload then mod.log('Dev reload enabled: Lua-only, explicit file requests; resident input helper retained')end
 local function stop(reason)
  if state~='running'then return end
  state='stopped';if reason then mod.log(reason)end
  local ok,why=pcall(entry.on_disable);if not ok then mod.log('Photo Mode cleanup failed: '..tostring(why))end
 end
 local function frame(dt,...)
  -- An explicit development replacement must remain reachable after a runtime
  -- error. Never resume the failed entry; only a fully enabled new generation.
  if state~='waiting'and dev_reload then
   if input_driver then input_driver.begin_frame()end
   local previous=entry
   local paused=dev_reload.tick();entry=dev_reload.entry()
   if entry~=previous and dev_reload.status()=='idle'then
    state='running';started_at=clock();mod.log('Photo Mode resumed after explicit Lua reload')
   end
   if paused then return ... end
  end
  if state=='waiting'then
   if input_pending then
    local ok,service,driver,screenshots=pcall(input_pending)
    if ok and service==nil then return ... end
    input_pending=nil
    if ok then input_service,input_driver=service,driver else input_service=without_helper(service)end
    mod.host_loader.input_service,mod.host_loader.helper_screenshots=input_service,ok and screenshots or nil
   end
   mod.host_loader.require_keyboard=input_driver~=nil
   local ok,why=pcall(entry.on_enable)
   if ok then state='running';started_at=clock();mod.log('Photo Mode started on Boot Mod Loader')else state='failed';mod.log('Photo Mode did not start: '..tostring(why))end
  elseif state=='running'then
   if input_driver and not dev_reload then input_driver.begin_frame()end
   local ok,why=pcall(entry.on_update,dt);if not ok then stop('Photo Mode stopped after an error: '..tostring(why))end
   if diagnose_at[1]and clock()-started_at>=diagnose_at[1]then
    local label=diagnose_at[1]..' s';table.remove(diagnose_at,1)
    local done,why=pcall(function()mod.require('src/native_diagnostics.lua').run(stingray,mod.require('src/host_native.lua'),mod.log,label)end)
    if not done then mod.log('Native diagnostics failed: '..tostring(why))end
   end
   -- The gameplay HUD's state twice a second, logged when it changes (the game's Toggle HUD key).
   if hud_probe~=false and clock()>=hud_probe_at then
    hud_probe_at=clock()+.5
    local done,line=pcall(function()return mod.require('src/native_diagnostics.lua').hud(mod.require('src/host_native.lua').open())end)
    if not done then hud_probe=false;mod.log('HUD probe stopped: '..tostring(line))
    elseif line~=hud_probe then hud_probe=line;mod.log('HUD probe: '..line)end
   end
  end
  return ...
 end
 local game_update,game_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
 rawset(_G,'update',function(dt,...)if game_update then return frame(dt,game_update(dt,...))end;return frame(dt)end)
 rawset(_G,'shutdown',function(...)stop();if input_driver then local ok,why=input_driver.close();if not ok then mod.log('Input restoration pending: '..tostring(why))end end;if game_shutdown then return game_shutdown(...)end end)
 return entry
end
'''

# Chef Shared Loader hands in its helpers. It calls the addon's own hooks, never the game's.
CHEF_HOST = r'''
local function chef_host(chef)
 -- Chef 1.4.0 or newer, by number parts in order ('1.10.0' is newer than '1.4.0'; a suffix
 -- such as '-test1' is ignored). No version is too old.
 local function at_least(have,need)
  if type(have)~='string'then return false end
  local parts={};for n in(have:match('^[%d%.]+')or''):gmatch('%d+')do parts[#parts+1]=tonumber(n)end
  local i=0
  for n in need:gmatch('%d+')do
   i=i+1;local part=parts[i]or 0
   if part~=tonumber(n)then return part>tonumber(n)end
  end
  return true
 end
 if not at_least(chef.loader_version,''' + json.dumps(MINIMUM_CHEF) + r''')then
  if type(chef.log)=='function'then chef.log('%s','War Journalist needs Chef Shared Loader ''' + MINIMUM_CHEF + r''' or newer')end
  return{version=VERSION,update=function()end,render=function()end,shutdown=function()end,on_stop=function()end}
 end
 if type(chef.title)=='function'then chef.title(TITLE)end
 assert(type(chef.log)=='function'and type(chef.log_directory)=='string','War Journalist for Chef needs Chef Shared Loader')
 local game=chef.log_directory:gsub('\\','/'):gsub('/+$','')
 -- Settings live in the game's settings folder, same as under Boot Mod Loader, so they carry over.
 -- Always release mode here, as every Chef build was: no dev inventories or probe requests (their
 -- probe files need os.remove, which Chef refuses).
 local mod={id=ID,name=TITLE,version=VERSION,build=BUILD,release_mode=true,native_dir=game,config_dir=game,native_libraries=false}
 local LOG=game..'/war_journalist_chef.log'
 local log_mode='ab'
 do -- Appended across launches; past 4 MB it starts fresh.
  local f=io.open(LOG,'ab');if f then local size=f:seek('end');f:close();if type(size)=='number'and size>4194304 then log_mode='wb'end end
 end
 function mod.log(message)
  local f=io.open(LOG,log_mode);log_mode='ab'
  if f then f:write(os.date('%Y-%m-%d %H:%M:%S '),tostring(message),'\n');f:close()end
 end
 local scope=setmetatable({mod=mod},{__index=_G})
 requirer(mod,scope)
 local host=mod.require('src/chef_host.lua')
 -- No os.rename or os.remove under Chef: saves go through host.files.
 scope.io,scope.os=host.scope(io,os,host.files(io.open))
 -- Chef never calls the global render. addon.render does it.
 local render=host.render(_G,mod.log)
 local entry=mod.require('main.lua')
 local bindings=rawget(_G,'ModBindingsMenu')
 if not(type(bindings)=='table'and type(bindings.register_binding)=='function'and type(bindings.is_down)=='function'and type(bindings.binding)=='function')then bindings=nil end
 local input_service=host.input(chef,stingray,mod.log,mod.require('src/engine_input.lua'))
 local capture=host.capture(chef,game)
 -- Depth through chef.capture('depth'): Chef 1.4.2 on; nil on older loaders.
 local depth=host.depth(chef,game)
 -- Keys reach the game too.
 -- Scene effects: colour bound on the GPU, formats from the contract. The CPU depth read for focus
 -- comes from the loader's depth capture. Depth shaders are out; depth of field is the game's own.
 local function scene_resources(sr)
  return mod.require('src/chef_scene_resources.lua').new(sr,mod,mod.require('src/engine_scene_registry.lua'),
   mod.require('src/engine_render_contract.lua'),mod.require('src/engine_scene_resources.lua').inspect,depth)
 end
 mod.host_loader={engine_input=true,require_keyboard=false,input_service=input_service,bindings=bindings,capture_service=capture,
  scene_resources=scene_resources,focus_capture=depth,capabilities={revision='chef-shared-loader-host.3'}}
 -- Arrow keys move the camera and the panel.
 mod.arrow_keys=true
 mod.log('War Journalist '..VERSION..' ('..BUILD..') on Chef Shared Loader '..tostring(chef.loader_version)..
  (capture and', screenshots through chef.capture'or', no screenshots')..(depth and', depth through chef.capture'or''))
 local state='waiting'
 local function stop(reason)
  if state~='running'then return end
  state='stopped';if reason then mod.log(reason)end
  local ok,why=pcall(entry.on_disable);if not ok then mod.log('Photo Mode cleanup failed: '..tostring(why))end
  input_service.dispose()
 end
 local addon={version=VERSION}
 function addon.update(dt)
  if state=='waiting'then
   mod.host_loader.require_keyboard=input_driver~=nil
   local ok,why=pcall(entry.on_enable)
   if ok then state='running';mod.log('Photo Mode started on Chef Shared Loader')
   else state='failed';mod.log('Photo Mode did not start: '..tostring(why));chef.log('%s','War Journalist did not start: '..tostring(why))end
  elseif state=='running'then
   local ok,why=pcall(entry.on_update,dt)
   if not ok then stop('Photo Mode stopped after an error: '..tostring(why));chef.log('%s','War Journalist stopped after an error: '..tostring(why))end
  end
 end
 function addon.render()if state=='running'then return render()end end
 function addon.shutdown()stop()end
 function addon.on_stop()stop('Stopped by Chef Shared Loader')end
 return addon
end
'''

# A table is Chef's helpers. Boot Mod Loader passes nothing, LLL the mod's name.
PICK = r'''
if type(loader)=='table'then return chef_host(loader)end
return boot_host()
'''


def compose(sources, version, build, release):
    """The package's whole Lua text. sources: 'main.lua' and 'src/<module>' to their text."""
    head = ('-- HD2-Addon: ' + RESOURCE + '\n'
            '-- War Journalist ' + version + ': one package for Boot Mod Loader and Chef Shared Loader.\n'
            '-- Generated by tools/build_package.py; edit freecam/ and tools/package_head.py instead.\n'
            'local loader=...\n'
            'local ID,TITLE=' + json.dumps(ID) + ',' + json.dumps(TITLE) + '\n'
            'local RELEASE_MODE=' + ('true' if release else 'false') + '\n'
            'local VERSION,BUILD=' + json.dumps(version) + ',' + json.dumps(build) + '\n')
    source_block = 'local SOURCES={}\n' + ''.join(
        'SOURCES[' + json.dumps(path) + ']=' + long_string(text) + '\n' for path, text in sources.items())
    return head + source_block + REQUIRER.lstrip('\n') + BOOT_HOST.lstrip('\n') + CHEF_HOST.lstrip('\n') + PICK.lstrip('\n')


def check_size(text, limit=MAX_BYTES):
    """The text's size in bytes; past the limit Chef would never run it, so the build stops."""
    size = len(text.encode('utf-8'))
    if size > limit:
        raise AssertionError(f'Bundle is {size} bytes, over the {limit}-byte cap (Chef 1.5.1 reads at most 4 MiB)')
    return size

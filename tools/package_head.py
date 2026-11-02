"""The head of the one War Journalist package: one resource that runs under Boot Mod Loader,
LLL or Chef Shared Loader and picks its host from the loader's argument (a table is Chef's
helpers; nil, from Boot Mod Loader's xpcall, or the mod's name, from LLL, is not).
compose() writes the whole Lua text; build_package.py packs and proves it."""
import json

from build_steam_archive import long_string

RESOURCE = 'mods/goose/war_journalist'
ID = 'dbf_freecam_lua51'
TITLE = 'War Journalist'
MINIMUM_CHEF = '1.4.0'
# Chef 1.5.1 never runs a Lua resource over 4 MiB (MAX_LUA); keep clear of it.
MAX_BYTES = 3_800_000

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
 function mod.log(message)
  print('['..TITLE..'] '..tostring(message))
  local f=io.open(game..'/war_journalist_lua51.log','ab');if f then f:write(os.date('%Y-%m-%d %H:%M:%S '),tostring(message),'\n');f:close()end
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
 mod.host_loader={engine_input=true,require_keyboard=true,input_service=input_service,bindings=bindings,capabilities={revision='boot-mod-loader-r34-input.1'}}
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

PICK = r'''
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
    return head + source_block + REQUIRER.lstrip('\n') + BOOT_HOST.lstrip('\n') + PICK.lstrip('\n')


def check_size(text, limit=MAX_BYTES):
    """The text's size in bytes; past the limit Chef would never run it, so the build stops."""
    size = len(text.encode('utf-8'))
    if size > limit:
        raise AssertionError(f"Bundle over Chef's 4 MiB reading limit: {size} bytes > {limit}")
    return size

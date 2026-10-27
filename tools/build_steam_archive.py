"""Bundle the audited dbf_freecam_lua51 candidate and the War Journalist assets as one HD2
Arsenal mod: an `-- HD2-Addon:` archive for Boot Mod Loader (which it drives itself) or LLL.
Builds under dist/review only; never registers, deploys or installs."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import tempfile

from build_steam_candidate import FFI, MOD_ID, ROOT
from photo_assets import LUA, archive_rows, hash64, read_archive

RESOURCE = 'mods/goose/war_journalist_lua51'
GUID = '7020a1c8-01ed-4a9d-874f-f778916eb067'
TITLE = 'War Journalist (Lua 5.1)'
OPTION = 'War Journalist'
ASSETS = Path.home() / '.config/hd2arsenal/mods/War-Journalist-1.2.0-Assets_AR297988/Assets'
ARCHIVE = '9ba626afa44a3aa3.patch_0'

RUNTIME = r'''
local function env(name)local value=os.getenv(name);return value and value:gsub('\\','/'):gsub('/+$','')end
local function writable(dir)local probe=dir..'/.wj-probe';local f=io.open(probe,'wb');if not f then return false end;f:close();os.remove(probe);return true end
local game=assert(env('APPDATA'),'APPDATA unavailable')..'/Arrowhead/Helldivers2'
local lll=env('LOCALAPPDATA')and env('LOCALAPPDATA')..'/LLL/Helldivers2'
-- The project surface LLL gives folder mods. LLL's folders when they exist, else the
-- game's own settings folder, which every install has.
local mod={id=ID,name=TITLE,release_mode=RELEASE_MODE,native_dir=lll and writable(lll..'/Native')and lll..'/Native'or game,
 config_dir=lll and writable(lll..'/Settings/'..ID)and lll..'/Settings/'..ID or game}
function mod.log(message)
 print('['..TITLE..'] '..tostring(message))
 local f=io.open(game..'/war_journalist_lua51.log','ab');if f then f:write(os.date('%Y-%m-%d %H:%M:%S '),tostring(message),'\n');f:close()end
end
-- Boot Mod Loader runs the Windows build. Windows refuses unsigned in-process DLLs (error 577),
-- so under it no bridge is written or loaded, under Proton too: it behaves as it does on Windows.
mod.native_libraries=rawget(_G,'LiveLuaLoader')~=nil
-- Bridges are content-addressed: install a missing one, refuse one whose size differs.
local function size_of(path)local f=io.open(path,'rb');if not f then return nil end;local size=f:seek('end');f:close();return size end
for _,library in ipairs(mod.native_libraries and LIBRARIES or{})do
 local path=mod.native_dir..'/'..library.name;local size=size_of(path)
 if size==nil then
  local data=library.hex:gsub('%x%x',function(h)return string.char(tonumber(h,16))end)
  assert(#data==library.size,'Embedded bridge damaged: '..library.name)
  local temp=path..'.tmp';local f=assert(io.open(temp,'wb'));local ok,why=f:write(data);f:close();assert(ok,why)
  assert(os.rename(temp,path));size=size_of(path);mod.log('Installed native bridge '..library.name)
 end
 assert(size==library.size,'Native bridge differs from this build: '..path)
end
local scope=setmetatable({mod=mod},{__index=_G})
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
local input_service,input_driver
local connected,why=pcall(function()input_service,input_driver=mod.require('src/windows_input_service.lua').connect(mod,stingray)end)
if not connected then
 mod.log('Input helper unavailable: '..tostring(why))
 input_service=mod.require('src/engine_input.lua').new(stingray,mod.log)
end
mod.host_loader={engine_input=true,require_keyboard=true,input_service=input_service,bindings=bindings,capabilities={revision='boot-mod-loader-r34-input.1'}}
local state='waiting'
-- Read-only native diagnostics at start and twice later, while subject/hover fail here.
local diagnose_at,started_at=RELEASE_MODE and{}or{0,30,120}
local hud_probe,hud_probe_at=nil,0
if RELEASE_MODE then hud_probe=false end
local function clock()local ok,t=pcall(function()return stingray.Application.time_since_launch()end);return ok and type(t)=='number'and t or os.clock()end
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
'''


def long_string(text):
    """Lua long bracket holding text exactly (no CR; first newline is skipped by Lua)."""
    assert '\r' not in text, 'CR would be normalized inside a long string'
    level = 0
    while True:
        close = ']' + '=' * level + ']'
        if (text + close).find(close) == len(text):
            return '[' + '=' * level + '[\n' + text + close
        level += 1


def bundle(candidate):
    manifest = json.loads((candidate / 'manifest.json').read_text())
    assert manifest['id'] == MOD_ID
    spec = manifest['lll']
    paths = [spec['entry'], *spec['modules']]
    sources = {}
    for path in paths:
        text = (candidate / path).read_text(encoding='utf-8')
        assert not FFI.search(text), path + ' uses FFI'
        sources['main.lua' if path == spec['entry'] else path] = text
    libraries = [(Path(name).name, (candidate / name).read_bytes()) for name in manifest['native_libraries']]
    head = ('-- HD2-Addon: ' + RESOURCE + '\n'
            '-- ' + TITLE + ' ' + manifest['version'] + ': LLL project ' + MOD_ID + ' packed as one archive addon.\n'
            '-- Generated by tools/build_steam_archive.py from the audited candidate; edit freecam/ instead.\n'
            'local ID,TITLE=' + json.dumps(MOD_ID) + ',' + json.dumps(TITLE) + '\n'
            'local RELEASE_MODE=' + ('true' if manifest.get('public_release') else 'false') + '\n')
    source_block = 'local SOURCES={}\n' + ''.join(
        'SOURCES[' + json.dumps(path) + ']=' + long_string(text) + '\n' for path, text in sources.items())
    library_block = 'local LIBRARIES={\n' + ''.join(
        ' {name=' + json.dumps(name) + ',size=' + str(len(data)) + ',hex="' + data.hex() + '"},\n'
        for name, data in libraries) + '}\n'
    return manifest, sources, dict(libraries), head, source_block, library_block, head + source_block + library_block + RUNTIME.lstrip('\n')


def verify(text, head, source_block, library_block, sources, libraries):
    from lupa.lua51 import LuaRuntime, lua_type
    lua = LuaRuntime()
    assert lua.eval('_VERSION') == 'Lua 5.1' and lua.eval('jit==nil')
    compile_lua = lua.eval('function(s,n) local f,e=loadstring(s,n);assert(f,e);return f end')
    compile_lua(text, '@' + RESOURCE)
    # Every embedded module and bridge must read back byte for byte.
    got = compile_lua(head + source_block + 'return SOURCES', '=sources')()
    assert sorted(got.keys()) == sorted(sources), 'Module list differs'
    for path, body in sources.items():
        assert got[path] == body, 'Module differs after packing: ' + path
    rows = compile_lua(library_block + 'return LIBRARIES', '=libraries')()
    assert {row['name']: bytes.fromhex(row['hex']) for row in rows.values()} == libraries
    run = 'function(s) return assert(loadstring(s,"@archive"))() end'
    # Boot Mod Loader: no LLL global; the addon wraps the game's update and shutdown.
    host = """
local text=...
local nop=function()end
package.loadlib=function()return nil,'fixture native backend unavailable'end
calls,shut=0,false
registered={}
ModBindingsMenu={window='HD2 Mod Setting GUI',is_down=function()return false end,binding=function()return{}end,
 register_binding=function(id,label,slot,options)registered[#registered+1]=id..'='..options.default.button;return true end}
update=function(dt)calls=calls+1;return 'game',dt end
shutdown=function()shut=true end
stingray={Gui={resolution=function()return 1920,1080 end},
 Unit={alive=function()return false end,world=nop,resource_name=nop,num_scene_graph_items=nop,
  local_pose=nop,set_local_pose=nop,animation_bone_mode=nop,set_animation_bone_mode=nop,has_node=nop,node=nop},
 World={update_unit=nop},
 Application={time_since_launch=function()return os.clock()end,render_setting=function()return false end,save_render_target=nop},
 Window={mouse_focus=function()return true end,show_cursor=function()return false end,clip_cursor=function()return true end,
  set_mouse_focus=nop,set_show_cursor=nop,set_clip_cursor=nop,has_focus=function()return true end},
 Mouse={axis_id=function(n)return({mouse=0,wheel=1,cursor=2})[n]end,button_id=function()return 0 end,axis=nop,button=function()return 0 end},
 Keyboard={button_id=function()return 0 end,button=function()return 0 end}}
local entry=assert(loadstring(text,'@archive'))()
local a,b=update(.5);for _=1,5 do update(1/60)end;shutdown()
return entry,a,b,calls,shut,table.concat(registered,'|')
"""
    with tempfile.TemporaryDirectory() as temp:
        game = Path(temp) / 'Roaming/Arrowhead/Helldivers2'
        lll = Path(temp) / 'Local/LLL/Helldivers2'
        game.mkdir(parents=True)
        previous = {name: os.environ.get(name) for name in ('APPDATA', 'LOCALAPPDATA', 'USERPROFILE')}
        os.environ['APPDATA'], os.environ['LOCALAPPDATA'] = str(Path(temp) / 'Roaming'), str(Path(temp) / 'Local')
        os.environ['USERPROFILE'] = str(Path(temp) / 'Profile')
        try:
            # Boot Mod Loader: the Windows build, with no bridges.
            entry, a, b, calls, shut, keys = LuaRuntime().execute(host, text)
            assert entry['live_lua_api'] == 1 and (a, b, calls, shut) == ('game', 0.5, 6, True), 'Update/shutdown wrapping'
            # The Windows build never writes or loads an in-process bridge.
            for name in libraries:
                assert not (game / name).exists(), 'Boot Mod Loader wrote a bridge: ' + name
            log = (game / 'war_journalist_lua51.log').read_text()
            assert 'In-process native libraries are not used by the Windows build' in log, 'A bridge load was attempted, not refused'
            # Boot Mod Loader's Mod Bindings Menu holds the keys once Photo Mode starts.
            hosted = dict(item.split('=', 1) for item in keys.split('|'))
            assert all(k.startswith('war_journalist.') for k in hosted) and hosted.get('war_journalist.toggle_key') == 'p' and len(hosted) >= 13, keys
            # On a bare engine the runtime starts with its native features reported unavailable.
            assert 'Photo Mode started on Boot Mod Loader' in log and 'stopped after an error' not in log and 'cleanup failed' not in log, log
            public_release = 'local RELEASE_MODE=true' in head
            if public_release:
                assert 'Native diagnostics (' not in log and 'Windows engine namespaces:' not in log, 'Public startup must not run development inventories'
            else:
                assert 'Native diagnostics (0 s)' in log and 'Native diagnostics failed' not in log, 'The start-up native diagnostic runs'
            # No bridge on a bare engine: the HUD probe stops once, saying why.
            assert log.count('HUD probe stopped: ') == (0 if public_release else 1), log
            # No LLL and no Linux worker: the engine writes DDS into the game's settings folder.
            assert 'Engine DDS capture selected: ' + str(game).replace('\\', '/') in log, log
            # Private reload: retain the game wrapper/input host, retire and replace
            # the complete real module graph twice without restarting the Lua VM.
            (game / 'wj-dev-reload.enabled').write_bytes(b'wjl-dev-reload-v1\n')
            rows = [(name, body.encode('utf-8')) for name, body in sources.items()]
            packed = f'WJL-LUA-1\n{len(rows)}\n'.encode() + b''.join(
                f'{name}\n{len(body)}\n'.encode() + body for name, body in rows)
            (game / 'wj-dev-fixture.lua-pack').write_bytes(packed)
            reload_host = host.replace('local text=...', 'local text=...;local test_clock=0')
            reload_host = reload_host.replace('time_since_launch=function()return os.clock()end',
                                             'time_since_launch=function()return test_clock end')
            reload_host = reload_host.replace("local a,b=update(.5);for _=1,5 do update(1/60)end;shutdown()", r'''
local a,b=update(.5)
local path=os.getenv('APPDATA')..'/Arrowhead/Helldivers2/wj-dev-reload.request'
local failures=0
entry.on_update=function()failures=failures+1;error('fixture failed generation')end
for _=1,11 do test_clock=test_clock+1/60;update(1/60)end
assert(failures==1,'A failed generation must not update again before replacement')
for _,token in ipairs({'fixture','fixture2'})do
 local f=assert(io.open(path,'wb'));f:write(token..'\n');f:close()
 for _=1,160 do test_clock=test_clock+1/60;update(1/60)end
end
shutdown()
''')
            (game / 'wj-dev-fixture2.lua-pack').write_bytes(packed)
            if public_release:
                before_log = (game / 'war_journalist_lua51.log').read_text()
                (game / 'wj-native-dof-selftest.request').write_text('native-dof-override-v1\n')
                LuaRuntime().execute(host, text)
                public_log = (game / 'war_journalist_lua51.log').read_text()[len(before_log):]
                assert 'Dev reload enabled' not in public_log and 'self-test' not in public_log
                assert (game / 'wj-native-dof-selftest.request').is_file(), 'Public mode must ignore old dev markers'
                (game / 'wj-native-dof-selftest.request').unlink()
            private_text = text.replace('local RELEASE_MODE=true', 'local RELEASE_MODE=false', 1)
            _, a, b, reload_calls, shut, keys = LuaRuntime().execute(reload_host, private_text)
            assert (a, b, reload_calls, shut) == ('game', .5, 332, True)
            reload_log = (game / 'war_journalist_lua51.log').read_text()
            assert 'Dev reload: loaded fixture;' in reload_log and 'Dev reload: loaded fixture2;' in reload_log, reload_log
            assert 'fixture failed generation' in reload_log and 'Photo Mode resumed after explicit Lua reload' in reload_log, reload_log
            assert len(keys.split('|')) == len(hosted), 'Reload duplicated hosted bindings'
            (game / 'wj-dev-reload.enabled').unlink()
            # LLL: its folders, and the entry handed back for LLL to drive.
            (lll / 'Native').mkdir(parents=True)
            (lll / 'Settings' / MOD_ID).mkdir(parents=True)
            for attempt in range(2):
                lua_lll = LuaRuntime()
                lua_lll.execute('LiveLuaLoader={}')
                entry = lua_lll.eval(run)(text)
                assert entry['live_lua_api'] == 1 and entry['name'] == 'War Journalist'
                for name in ('on_enable', 'on_update', 'on_disable', 'on_cleanup_poll'):
                    assert lua_type(entry[name]) == 'function', name
                for name, data in libraries.items():
                    assert (lll / 'Native' / name).read_bytes() == data, name
            name, data = next(iter(libraries.items()))
            (lll / 'Native' / name).write_bytes(data[:-1])
            try:
                # Only LLL installs bridges; it refuses one that differs from this build.
                lua_lll = LuaRuntime()
                lua_lll.execute('LiveLuaLoader={}')
                lua_lll.eval(run)(text)
            except Exception as error:
                assert 'Native bridge differs' in str(error), error
            else:
                raise AssertionError('A differing bridge must be refused')
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value


def build(candidate, output):
    candidate, output = candidate.resolve(), output.resolve()
    assert output.is_relative_to(ROOT / 'dist/review'), 'Archive packages stay in dist/review'
    manifest, sources, libraries, head, source_block, library_block, text = bundle(candidate)
    verify(text, head, source_block, library_block, sources, libraries)
    data = text.encode('utf-8')
    key = hash64(RESOURCE)
    assert re.match(r'-- HD2-Addon: (mods/[A-Za-z0-9_/]+)\n', text).group(1) == RESOURCE
    envelope = struct.pack('<II', len(data), 2) + data
    body, gpu = archive_rows([(key, LUA, envelope, b'')])
    assert read_archive(body, gpu) == [(key, LUA, envelope, b'')] and gpu == b''
    folder = output / ('War-Journalist-Lua51-' + manifest['version'])
    if folder.exists():
        shutil.rmtree(folder)
    payload = folder / OPTION
    payload.mkdir(parents=True)
    (payload / ARCHIVE).write_bytes(body)
    for suffix in ('.stream', '.gpu_resources'):
        (payload / (ARCHIVE + suffix)).write_bytes(b'')
    (payload / f'{key:016x}.lua').write_bytes(data)
    for name in manifest['license_files']:
        shutil.copyfile(candidate / name, folder / name)
    assets = folder / 'Assets'
    shutil.copytree(ASSETS, assets)
    description = ('War Journalist Photo Mode for Boot Mod Loader on the Lua 5.1 game, with its assets. No FFI, so no '
                   'Enemy behavior. Its keys are set in HD2 Mod Setting GUI or the Photo panel. Under Boot Mod Loader it is the '
                   'Windows build on Windows and Proton alike: the bundled WJL helper starts automatically for Photo Mode '
                   'input capture, with no separate helper setup, Python or PowerShell, and no in-process native bridge is '
                   'written or loaded, as Windows refuses them. Under LLL its native bridges install into LLL\'s Native '
                   'folder. Windows '
                   'DoF and scene effects are renderer-checked test candidates awaiting visual verification. Screenshots '
                   'are PNG through the War Journalist Linux capture worker where it runs, else DDS from the engine. Settings '
                   'live in LLL/Helldivers2/Settings/' + MOD_ID + ' when that folder exists, else in the game\'s settings '
                   'folder. Also runs as an LLL archive mod. Use one War Journalist at a time.')
    if manifest.get('public_release'):
        description = 'War Journalist 1.3.1: Windows and Proton input fix for the Lua rewrite for Boot Mod Loader. Native DoF, Handycam and automatic WJL startup. AI control and depth shaders are unavailable. Cape, subject selection, equipment hiding and hoverpack limitations remain; see release notes.'
    arsenal = {'Version': 1, 'Guid': GUID, 'Name': TITLE + ' ' + manifest['version'], 'Description': description,
               'Options': [{'Name': TITLE, 'Description': 'Photo Mode and its assets.', 'Include': [OPTION, 'Assets']}]}
    (folder / 'manifest.json').write_text(json.dumps(arsenal, indent=2, ensure_ascii=False) + '\n')
    digest = lambda b: hashlib.sha256(b).hexdigest()
    provenance = {'version': manifest['version'], 'runtime': 'Lua 5.1', 'ffi': 'none', 'resource': RESOURCE,
                  'resource_key': f'{key:016x}', 'addon_sha256': digest(data), 'archive_sha256': digest(body),
                  'candidate_files_sha256': digest((candidate / 'FILES-SHA256.txt').read_bytes()),
                  'modules': len(sources) - 1, 'native_bridges': {name: digest(b) for name, b in libraries.items()},
                  'assets': {p.relative_to(assets).as_posix(): digest(p.read_bytes()) for p in sorted(assets.iterdir())},
                  'verified': ['modules and bridges read back exactly', 'Boot Mod Loader: wraps update/shutdown, passes the game results through, starts, ticks and cleans up on a bare engine, registers its keys with ModBindingsMenu, selects engine DDS capture without LLL or the Linux worker',
                               'Boot Mod Loader (the Windows build): no bridge written or loaded, as Windows refuses them', 'LLL: returns the API 1 entry, uses LLL folders',
                               'installs missing bridges', 'refuses a differing bridge'],
                  'registered': False, 'deployed': False, 'live_acceptance': 'pending'}
    (folder / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    return folder, provenance


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    default = ROOT / 'dist/review/steam-lua51-noffi/package'
    parser.add_argument('--candidate', type=Path, default=default / 'candidate' / MOD_ID)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/review/steam-lua51-noffi/arsenal')
    parser.add_argument('--assets', type=Path, default=ASSETS)
    args = parser.parse_args()
    ASSETS = args.assets
    folder, provenance = build(args.candidate, args.output)
    print(json.dumps({'folder': str(folder), **{k: provenance[k] for k in ('resource', 'resource_key', 'addon_sha256', 'modules')}}, indent=2))

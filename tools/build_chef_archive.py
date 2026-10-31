"""Pack the War Journalist 1.3.3 runtime (the Boot Mod Loader build's modules and its own
Photo panel) as a Chef Shared Loader addon, with the War Journalist assets, for HD2 Arsenal.
Runs the packed addon inside Chef's real sandbox.lua before writing anything. Builds under
dist/review only; never registers, deploys or installs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct
import zipfile

from build_steam_archive import build_id, long_string
from build_steam_candidate import DEV_ONLY, FFI, MOD_ID, MODULES, ROOT
from photo_assets import LUA, archive_rows, hash64, read_archive
from test_chef_port import SANDBOX_BLOBS, sandbox_text

# Chef's TRUSTED table grants screenshots to this resource name.
RESOURCE = 'mods/goose/war_journalist'
# The Chef track's Arsenal entry (the earlier Chef Lite builds); its one option keeps its name.
GUID = '7b18fc08-a506-4cd3-a506-dbed18445576'
TITLE = 'War Journalist'
OPTION = 'War Journalist (core)'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
MINIMUM_CHEF = '1.4.0'
# The assets ship exactly as in the published 1.3.3 Boot Mod Loader zip (its Assets/ folder).
RELEASE_ZIP = Path.home() / 'Worktrees/linux-hd2/wj-release-1.3.3/dist/releases/1.3.3/War-Journalist-1.3.3-BML.zip'
RELEASE_ZIP_SHA256 = '4d8d8bb8e73fdb00a490fffc243c59b5dde1e118e35e57a6c4c355bea97442b8'
# Started only by the Boot Mod Loader boot script (WJL helper, live reload); Chef blocks
# io.popen and os.rename, so they are left out rather than refused at run time.
BOOT_ONLY = ('windows_input_service.lua', 'vendor/wjl_transport.lua', 'vendor/wjl_capture.lua',
             'vendor/wjl_input_service.lua', 'wjl_helper_payload.lua', 'wjl_helper_startup.lua', 'windows_dev_reload.lua')
CHEF_MODULES = tuple(name for name in MODULES if name not in BOOT_ONLY and name not in DEV_ONLY) + ('chef_host.lua',)

RUNTIME = r'''
local chef=CHEF
assert(type(chef)=='table'and type(chef.log)=='function'and type(chef.log_directory)=='string','War Journalist for Chef needs Chef Shared Loader')
if type(chef.title)=='function'then chef.title(TITLE)end
local game=chef.log_directory:gsub('\\','/'):gsub('/+$','')
-- Settings stay where the Boot Mod Loader build keeps them without LLL (the game's settings
-- folder, which is also Chef's), so the same .ini files carry over between the two.
local mod={id=ID,name=TITLE,version=VERSION,build=BUILD,release_mode=RELEASE_MODE,native_dir=game,config_dir=game,native_libraries=false}
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
local host=mod.require('src/chef_host.lua')
-- Chef has no os.rename or os.remove: the modules' saves go through host.files.
scope.io,scope.os=host.scope(io,os,host.files(io.open))
local entry=mod.require('main.lua')
local bindings=rawget(_G,'ModBindingsMenu')
if not(type(bindings)=='table'and type(bindings.register_binding)=='function'and type(bindings.is_down)=='function'and type(bindings.binding)=='function')then bindings=nil end
local input_service=host.input(chef,stingray,mod.log,mod.require('src/engine_input.lua'))
local capture=host.capture(chef,game)
-- No keyboard isolation under Chef: keys reach the game, as under Boot Mod Loader without WJL.
mod.host_loader={engine_input=true,require_keyboard=false,input_service=input_service,bindings=bindings,capture_service=capture,
 capabilities={revision='chef-shared-loader-host.1'}}
mod.log('War Journalist '..VERSION..' ('..BUILD..') on Chef Shared Loader '..tostring(chef.loader_version)..
 (capture and', screenshots through chef.capture'or', no screenshots'))
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
  local ok,why=pcall(entry.on_enable)
  if ok then state='running';mod.log('Photo Mode started on Chef Shared Loader')
  else state='failed';mod.log('Photo Mode did not start: '..tostring(why));chef.log('%s','War Journalist did not start: '..tostring(why))end
 elseif state=='running'then
  local ok,why=pcall(entry.on_update,dt)
  if not ok then stop('Photo Mode stopped after an error: '..tostring(why));chef.log('%s','War Journalist stopped after an error: '..tostring(why))end
 end
end
function addon.shutdown()stop()end
function addon.on_stop()stop('Stopped by Chef Shared Loader')end
return addon
'''

# Inside Chef's own sandbox.lua, as the loader runs an addon: its io/os, its file rules and a
# bare engine. Starts, ticks, opens the panel key's binding, saves settings and stops.
FIXTURE = r'''
local SANDBOX,TEXT=...
local files,blocked,logs,holds,captures={}, {}, {}, {}, 0
local function vopen(path,mode)
 mode=mode or'r'
 if mode:find('[wa]')then
  local parts={};if mode:find('a')and files[path]then parts[1]=files[path]end
  local h={};function h.write(_,...)for i=1,select('#',...)do parts[#parts+1]=tostring((select(i,...)))end;return h end
  function h.seek()return #table.concat(parts)end;function h.close()files[path]=table.concat(parts);return true end
  function h.setvbuf()return true end;function h.flush()return true end
  return h
 end
 local data=files[path];if not data then return nil,path..': No such file or directory'end
 local at=0;local h={}
 function h.read(_,n)if at>=#data then return nil end;if n=='*a'then n=#data end;n=tonumber(n)or#data;local p=data:sub(at+1,at+n);at=at+#p;return p end
 function h.seek(_,w,o)o=o or 0;if w=='end'then at=#data+o elseif w=='set'then at=o end;return at end
 function h.close()return true end
 return h
end
local nop=function()end
stingray={Gui={resolution=function()return 1920,1080 end},
 Unit={alive=function()return false end,world=nop,resource_name=nop,num_scene_graph_items=nop,
  local_pose=nop,set_local_pose=nop,animation_bone_mode=nop,set_animation_bone_mode=nop,has_node=nop,node=nop},
 World={update_unit=nop},
 Application={time_since_launch=function()return os.clock()end,render_setting=function()return false end,process_id=function()return 4242 end},
 Window={mouse_focus=function()return true end,show_cursor=function()return false end,has_focus=function()return true end},
 Mouse={axis_id=function(n)return({mouse=0,wheel=1,cursor=2})[n]end,button_id=function()return 0 end,axis=function()return{x=0,y=0}end,button=function()return 0 end},
 Keyboard={button_id=function()return 0 end,button=function()return 0 end},
 Network={game_session=nop}}
for k,v in pairs(stingray)do _G[k]=v end
local sandbox=assert(loadstring(SANDBOX))().install({G=_G,io={open=vopen,type=function()return nil end},
 os={clock=os.clock,time=os.time,date=os.date,difftime=os.difftime,getenv=function(n)return({APPDATA='C:\\Users\\p\\AppData\\Roaming',LOCALAPPDATA='C:\\Users\\p\\AppData\\Local'})[n]end},
 debug=debug,DIR='C:\\game\\',GAME_DIR='C:\\game\\',log=function(s)blocked[#blocked+1]=s end})
local env=sandbox.env('mods/goose/war_journalist')
local registered,down={},{}
env.ModBindingsMenu=setmetatable({},{__newindex=function()error('read-only ModBindingsMenu')end,__index={window='Chef Shared Loader options menu',register_binding=function(id,label,slot,options)registered[id]=options.default.button;return true end,
 is_down=function(id)return down[id]==true end,binding=function()return{}end,poll=nop,set_binding=function()return true end}})
local chef={api=3,loader_version='1.4.1',name='mods/goose/war_journalist',log_directory='C:\\game',
 log=function(fmt,...)logs[#logs+1]=string.format(fmt,...)end,title=nop,has=function()return true end,
 hold_mouse=function(on)holds[#holds+1]=on;return true end,mouse_held=function()return false end,mouse_delta=function()return 0,0 end,
 menu_open=function()return false end,capture=function()captures=captures+1;return'capture.dds'end}
local chunk=assert(loadstring(TEXT,'=war_journalist'));setfenv(chunk,env)
local addon=chunk(chef)
assert(type(addon)=='table'and type(addon.update)=='function'and addon.version,'The addon returns its hooks')
for _=1,30 do addon.update(1/60)end
local started=files['C:/game/war_journalist_chef.log']or''
local keys=0;for _ in pairs(registered)do keys=keys+1 end
addon.shutdown()
local log=files['C:/game/war_journalist_chef.log']or''
local names={};for path in pairs(files)do names[#names+1]=path end;table.sort(names)
return log,table.concat(blocked,'\n'),table.concat(logs,'\n'),keys,registered['war_journalist.toggle_key'],table.concat(names,'|'),env.DBF_PHOTO_MODE_OWNER==nil
'''


def bundle():
    sources = {'main.lua': (ROOT / 'freecam/steam51.lua').read_text(encoding='utf-8')}
    for name in CHEF_MODULES:
        sources['src/' + name] = (ROOT / 'freecam' / name).read_text(encoding='utf-8')
    for path, text in sources.items():
        assert not FFI.search(text), path + ' uses FFI'
        assert '\r' not in text, path + ' has CR line ends'
    version = (ROOT / 'VERSION').read_text().strip() + '-chef-dev.1'
    head = ('-- HD2-Addon: ' + RESOURCE + '\n'
            '-- HD2-Requires: chef-shared-loader >= ' + MINIMUM_CHEF + '\n'
            '-- ' + TITLE + ' ' + version + ': the Boot Mod Loader runtime and its own Photo panel, hosted by Chef Shared Loader.\n'
            '-- Generated by tools/build_chef_archive.py; edit freecam/ instead.\n'
            'local CHEF=...\n'
            'local ID,TITLE=' + json.dumps(MOD_ID) + ',' + json.dumps(TITLE) + '\n'
            # As the shipped 1.3.3: no development inventories or probe requests.
            'local RELEASE_MODE=true\n'
            'local VERSION,BUILD=' + json.dumps(version) + ',' + json.dumps(build_id()) + '\n')
    source_block = 'local SOURCES={}\n' + ''.join(
        'SOURCES[' + json.dumps(path) + ']=' + long_string(text) + '\n' for path, text in sources.items())
    return version, sources, head, source_block, head + source_block + RUNTIME.lstrip('\n')


def verify(text, head, source_block, sources, sandboxes):
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime()
    compile_lua = lua.eval('function(s,n) local f,e=loadstring(s,n);assert(f,e);return f end')
    compile_lua(text, '=war_journalist')
    got = compile_lua(head.replace('local CHEF=...\n', '') + source_block + 'return SOURCES', '=sources')()
    assert sorted(got.keys()) == sorted(sources), 'Module list differs'
    for path, body in sources.items():
        assert got[path] == body, 'Module differs after packing: ' + path
    # chef_host.lua on its own (plain Lua 5.1).
    host = LuaRuntime()
    host.execute((ROOT / 'freecam/chef_host_tests.lua').read_text(encoding='utf-8'))
    results = []
    for sandbox in sandboxes:
        sb_text, blob = sandbox_text(sandbox)
        log, blocked, chef_log, keys, toggle, names, released = LuaRuntime().execute(FIXTURE, sb_text, text)
        assert 'on Chef Shared Loader 1.4.1, screenshots through chef.capture' in log, log
        assert 'Photo Mode started on Chef Shared Loader' in log, log
        assert 'Photo Mode ready on Lua 5.1' in log and 'Windows engine API' not in log, log
        assert 'stopped after an error' not in log and 'cleanup failed' not in log and 'did not start' not in log, log
        assert keys >= 13 and toggle == 'p', (keys, toggle)
        assert released, 'Photo Mode owner left behind'
        assert not chef_log, chef_log
        refused = [line for line in blocked.split('\n') if line.startswith('blocked:')]
        assert not refused, 'Chef refused a call: ' + '\n'.join(refused)
        assert names == 'C:/game/war_journalist_chef.log', names
        results.append({'sandbox_git_blob': blob, 'chef_versions': SANDBOX_BLOBS[blob], 'started': True, 'keys': keys,
                        'refused_calls': 0, 'files_written': names.split('|')})
    return results


def build(output, sandboxes):
    output = output.resolve()
    assert output.is_relative_to(ROOT / 'dist/review'), 'Archive packages stay in dist/review'
    version, sources, head, source_block, text = bundle()
    tests = verify(text, head, source_block, sources, sandboxes)
    data = text.encode('utf-8')
    key = hash64(RESOURCE)
    assert re.match(r'-- HD2-Addon: (mods/[A-Za-z0-9_/]+)\n', text).group(1) == RESOURCE
    envelope = struct.pack('<II', len(data), 2) + data
    body, gpu = archive_rows([(key, LUA, envelope, b'')])
    assert read_archive(body, gpu) == [(key, LUA, envelope, b'')] and gpu == b''
    name = 'War-Journalist-' + version
    folder = output / name
    if folder.exists():
        shutil.rmtree(folder)
    payload = folder / OPTION
    payload.mkdir(parents=True)
    (payload / ARCHIVE).write_bytes(body)
    for suffix in ('.stream', '.gpu_resources'):
        (payload / (ARCHIVE + suffix)).write_bytes(b'')
    # The addon's source beside its archive, as the 1.3.3 package has it (Arsenal's Lua detection).
    (payload / f'{key:016x}.lua').write_bytes(data)
    for label in ('LICENSE-Link.txt', 'LICENSE-Bingus.txt'):
        shutil.copyfile(ROOT / 'freecam/vendor' / label, folder / label)
    shutil.copyfile(ROOT / 'tools/chef-LICENSE.txt', folder / 'Chef-LICENSE.txt')
    assets = folder / 'Assets'
    assets.mkdir()
    release = RELEASE_ZIP.read_bytes()
    assert hashlib.sha256(release).hexdigest() == RELEASE_ZIP_SHA256, 'Not the published 1.3.3 zip: ' + str(RELEASE_ZIP)
    with zipfile.ZipFile(RELEASE_ZIP) as shipped:
        for entry in shipped.namelist():
            if entry.startswith('Assets/') and not entry.endswith('/'):
                assert '/' not in entry[len('Assets/'):], entry
                (assets / entry[len('Assets/'):]).write_bytes(shipped.read(entry))
    assert len(list(assets.iterdir())) == 6, 'Expected the six 1.3.3 asset files'
    description = ('War Journalist ' + version + ' for Chef Shared Loader ' + MINIMUM_CHEF + ' or newer: the 1.3.3 Photo Mode with '
                   'its own Photo panel and virtual cursor, and its assets. Keys are rebound in F9 > War Journalist. '
                   'Screenshots are DDS files that Chef Shared Loader saves in the game\'s settings folder. No native '
                   'bridges, keyboard isolation or WJL under Chef: native DoF, Handycam and hover pause stay off, and '
                   'keys and clicks also reach the game. Development build: not yet tested in game. Use one War '
                   'Journalist at a time.')
    arsenal = {'Version': 1, 'Guid': GUID, 'Name': TITLE + ' ' + version, 'Description': description,
               'Options': [{'Name': OPTION, 'Description': 'Photo Mode, its panel and its assets.', 'Include': [OPTION, 'Assets']}]}
    (folder / 'manifest.json').write_text(json.dumps(arsenal, indent=2, ensure_ascii=False) + '\n')
    digest = lambda b: hashlib.sha256(b).hexdigest()
    provenance = {'version': version, 'runtime': 'Lua 5.1', 'ffi': 'none', 'host': 'Chef Shared Loader >= ' + MINIMUM_CHEF,
                  'resource': RESOURCE, 'resource_key': f'{key:016x}', 'addon_sha256': digest(data),
                  'archive_sha256': digest(body), 'modules': len(sources) - 1,
                  'left_out': list(BOOT_ONLY),
                  'assets_from': RELEASE_ZIP.name + ' ' + RELEASE_ZIP_SHA256,
                  'assets': {p.relative_to(assets).as_posix(): digest(p.read_bytes()) for p in sorted(assets.iterdir())},
                  'sandbox_tests': tests,
                  'verified': ['modules read back exactly', 'chef_host.lua unit tests (staged settings writes, chef.capture jobs, held mouse)',
                               "starts, ticks and stops inside Chef's own sandbox.lua with no refused call, registers its keys "
                               'with the ModBindingsMenu look-alike, writes only its log'],
                  'registered': False, 'deployed': False, 'live_acceptance': 'pending'}
    (folder / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    package = output / (name + '.zip')
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(folder).as_posix())
    provenance['zip'] = str(package)
    provenance['zip_sha256'] = digest(package.read_bytes())
    return folder, provenance


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/review/chef-runtime')
    parser.add_argument('--sandbox', type=Path, required=True, action='append',
                        help="Chef src/chef_loader/sandbox.lua (1.4.0 or 1.4.1); repeat for each version")
    parser.add_argument('--release-zip', type=Path, default=RELEASE_ZIP, help='the published War-Journalist-1.3.3-BML.zip')
    args = parser.parse_args()
    RELEASE_ZIP = args.release_zip
    folder, provenance = build(args.output, args.sandbox)
    print(json.dumps({'folder': str(folder), **{k: provenance[k] for k in ('resource', 'addon_sha256', 'modules', 'zip', 'zip_sha256', 'sandbox_tests')}}, indent=2))

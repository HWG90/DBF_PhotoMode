"""Offline proofs for the one War Journalist package: the generated text on each host that can
run it. Lua 5.1 through lupa; fakes only, never the game. Used by test_package.py and
build_package.py."""
from contextlib import contextmanager
from pathlib import Path
import os
import re
import tempfile

from build_steam_candidate import DEV_ONLY, FFI, MODULES, ROOT
from package_head import ID, MINIMUM_CHEF, RESOURCE, TITLE


def current_sources(release):
    """The package's modules from this tree: main.lua is steam51.lua, the rest src/<module>."""
    sources = {'main.lua': (ROOT / 'freecam/steam51.lua').read_text(encoding='utf-8')}
    for name in MODULES:
        if not (release and name in DEV_ONLY):
            sources['src/' + name] = (ROOT / 'freecam' / name).read_text(encoding='utf-8')
    for path, text in sources.items():
        assert not FFI.search(text), path + ' uses FFI'
    return sources


def packed_sources(text):
    """The SOURCES table the generated text carries, read back by Lua itself."""
    from lupa.lua51 import LuaRuntime
    cut = text.index('\nlocal function requirer(')
    got = LuaRuntime().eval('function(s) return assert(loadstring(s,"=sources"))() end')(text[:cut] + '\nreturn SOURCES')
    return {path: got[path] for path in got.keys()}


@contextmanager
def boot_env():
    """A throwaway Windows profile: APPDATA, LOCALAPPDATA and USERPROFILE point into a temp
    tree; yields the game's settings folder <APPDATA>/Arrowhead/Helldivers2."""
    previous = {name: os.environ.get(name) for name in ('APPDATA', 'LOCALAPPDATA', 'USERPROFILE')}
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        game = temp / 'Roaming/Arrowhead/Helldivers2'
        game.mkdir(parents=True)
        (temp / 'Local/WJL/Helldivers2/Steam').mkdir(parents=True)
        os.environ['APPDATA'], os.environ['LOCALAPPDATA'] = str(temp / 'Roaming'), str(temp / 'Local')
        os.environ['USERPROFILE'] = str(temp / 'Profile')
        try:
            yield game
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value


# Boot Mod Loader: no LLL global, no argument (it runs the chunk through xpcall), the chunk
# named after the resource; the addon wraps the game's update and shutdown.
HOST = """
local text=...
local nop=function()end
package.loadlib=function()return nil,'fixture native backend unavailable'end
calls,shut=0,false
registered={}
ModBindingsMenu={window='HD2 Mod Setting GUI',is_down=function()return false end,binding=function()return{}end,
 register_binding=function(id,label,slot,options)registered[#registered+1]=id..'='..options.default.button;return true end}
update=function(dt)calls=calls+1;return 'game',dt end
shutdown=function()shut=true end
-- The WJL launcher: recorded, never run. Its helper refuses this (fake) game at once, as
-- on an unsupported build. Closing the handle would wait for cmd.exe; the game never may.
launches,closes={},0
-- No helper pipes here. On Linux, opening a pipe name to write would create a stray file.
local file_open=io.open
io.open=function(path,mode)
 if type(path)=='string'and path:sub(1,9)=='\\\\\\\\.\\\\pipe\\\\'then return nil,'pipe not found'end
 return file_open(path,mode)
end
io.popen=function(command,mode)
 launches[#launches+1]=command
 local log=assert(io.open(os.getenv('LOCALAPPDATA')..'/WJL/Helldivers2/Steam/service.log','wb'))
 log:write('Refused: installed game hashes do not match the build War Journalist names\\n');log:close()
 return{close=function()closes=closes+1;return true end}
end
stingray={Gui={resolution=function()return 1920,1080 end},
 Unit={alive=function()return false end,world=nop,resource_name=nop,num_scene_graph_items=nop,
  local_pose=nop,set_local_pose=nop,animation_bone_mode=nop,set_animation_bone_mode=nop,has_node=nop,node=nop},
 World={update_unit=nop},
 Application={time_since_launch=function()return os.clock()end,render_setting=function()return false end,save_render_target=nop,
  process_id=function()return 4242 end},
 Window={mouse_focus=function()return true end,show_cursor=function()return false end,clip_cursor=function()return true end,
  set_mouse_focus=nop,set_show_cursor=nop,set_clip_cursor=nop,has_focus=function()return true end},
 Mouse={axis_id=function(n)return({mouse=0,wheel=1,cursor=2})[n]end,button_id=function()return 0 end,axis=nop,button=function()return 0 end},
 Keyboard={button_id=function()return 0 end,button=function()return 0 end}}
local entry=assert(loadstring(text,'@""" + RESOURCE + """'))()
local a,b=update(.5);for _=1,5 do update(1/60)end;shutdown()
return entry,a,b,calls,shut,table.concat(registered,'|'),table.concat(launches,'\\n'),closes
"""

# A helper that answers: its pipes appear two frames after the launch, as on a PC where it
# takes a moment. Photo Mode waits for it, then PNGs through it.
ANSWERING = HOST.replace("io.popen=function(command,mode)", r"""
local pipes,frames_after_launch={},nil
local real_open=io.open
local function le(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function word(s,i)local a,b,c,d=s:byte(i,i+3);return a+b*256+c*65536+d*16777216 end
local queue=''
io.open=function(path,mode)
 if type(path)~='string'or path:sub(1,9)~='\\\\.\\pipe\\'then return real_open(path,mode)end
 if not frames_after_launch or frames_after_launch<2 then return nil,'pipe not found'end
 if path:match('_request$')then
  local buffer=''
  return{setvbuf=function()end,flush=function()return true end,close=function()end,write=function(_,...)
   buffer=buffer..table.concat({...})
   while #buffer>=4 and #buffer>=4+word(buffer,1)do
    local size=word(buffer,1);local frame=buffer:sub(5,4+size);buffer=buffer:sub(5+size)
    local seq,op=word(frame,1),word(frame,5)
    local reply=op==0 and le(0)..le(0)..le(4242)..le(1)..'x'..le(6)..'C:/hd2'or le(seq)..le(0)..string.rep(le(0),16)
    queue=queue..le(#reply)..reply
   end
   return true end}
 end
 return{setvbuf=function()end,close=function()end,read=function(_,count)
  local part=queue:sub(1,count);queue=queue:sub(count+1);return part end}
end
local game_update=update
update=function(dt)if frames_after_launch then frames_after_launch=frames_after_launch+1 end;return game_update(dt)end
io.popen=function(command,mode)
 frames_after_launch=0
 launches[#launches+1]=command
 return{close=function()closes=closes+1;return true end}
end
local unused_popen=function(command,mode)""", 1)

# Private reload: retain the game wrapper/input host, retire and replace the complete real
# module graph twice without restarting the Lua VM.
RELOAD = HOST.replace('local text=...', 'local text=...;local test_clock=0').replace(
    'time_since_launch=function()return os.clock()end', 'time_since_launch=function()return test_clock end').replace(
    "local a,b=update(.5);for _=1,5 do update(1/60)end;shutdown()", r'''
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


def _boot(script, text):
    from lupa.lua51 import LuaRuntime
    entry, a, b, calls, shut, keys, launches, closes = LuaRuntime().execute(script, text)
    return {'entry': entry, 'first': (a, b), 'calls': calls, 'shut': shut,
            'keys': dict(item.split('=', 1) for item in keys.split('|')) if keys else {},
            'launches': launches.split('\n') if launches else [], 'closes': closes}


def run_boot(text, answering=False):
    """Run the text as Boot Mod Loader does, inside boot_env(): one .5 s update, five more,
    shutdown. The WJL helper refuses at once, or answers two frames after its launch."""
    return _boot(ANSWERING if answering else HOST, text)


def verify_shape(text):
    first, head = text.split('\n', 1)[0], text[:1200]
    assert first == '-- HD2-Addon: ' + RESOURCE, first
    assert 'HD2-Requires' not in head, 'A requirement line would send the package to Chef only'
    assert '\nlocal loader=...\n' in head, 'The head reads its loader as local loader=...'
    assert not re.search(r'(^|\n)local\s+chef\s*=\s*\.\.\.', head), 'LLL would take a local chef=... head for a Chef addon'
    assert 'local LIBRARIES' not in text, 'No in-process bridges in the package'
    # The menu shows this version and build at its bottom right.
    assert re.search(r'\nlocal VERSION,BUILD="\d+\.\d+\.\d+[^"]*","\d{8}\.\d{4}-[0-9a-f]{7}\+?"\n', head), 'Version and build stamp missing'
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime()
    assert lua.eval('_VERSION') == 'Lua 5.1' and lua.eval('jit==nil')
    lua.eval('function(s,n) local f,e=loadstring(s,n);assert(f,e);return f end')(text, '@' + RESOURCE)


def verify_boot(text, release):
    """Every Boot Mod Loader proof of the old Lua 5.1 archive, on the one package."""
    assert ('\nlocal RELEASE_MODE=true\n' in text) == bool(release), 'Release mode differs from the build asked for'
    with boot_env() as game:
        log_path = game / 'war_journalist_lua51.log'
        run = run_boot(text, answering=True)
        assert (run['first'], run['calls'], run['shut']) == (('game', 0.5), 6, True), 'Update/shutdown wrapping with a helper'
        assert run['launches'][0].startswith('""') and run['closes'] == 1, ('The launcher is closed once, after the helper answered', run['closes'])
        log = log_path.read_text()
        assert 'WJL helper ready' in log and 'Input: WJL keyboard service connected' in log, log
        assert 'WJL PNG screenshots selected (engine DDS converted by WJL): ' + str(game).replace('\\', '/') in log, log
        assert 'Photo Mode started on Boot Mod Loader' in log and 'Input helper unavailable' not in log, log
        log_path.unlink()
        # Boot Mod Loader: the Windows build, with no bridges.
        run = run_boot(text)
        assert run['entry']['live_lua_api'] == 1 and (run['first'], run['calls'], run['shut']) == (('game', 0.5), 6, True), 'Update/shutdown wrapping'
        # WJL starts once through cmd.exe itself (never start), and the game never waits on it.
        launches = run['launches']
        assert len(launches) == 1 and launches[0].startswith('""') and '--launch' in launches[0], launches
        assert 'start "' not in launches[0] and 'powershell' not in launches[0].lower() and run['closes'] == 0, (launches, run['closes'])
        # The Windows build never writes or loads an in-process bridge.
        for name in os.listdir(game):
            assert not name.endswith('.dll'), 'Boot Mod Loader wrote a bridge: ' + name
        log = log_path.read_text()
        assert 'In-process native libraries are not used by the Windows build' in log, 'A bridge load was attempted, not refused'
        # Boot Mod Loader's Mod Bindings Menu holds the keys once Photo Mode starts.
        hosted = run['keys']
        assert all(k.startswith('war_journalist.') for k in hosted) and hosted.get('war_journalist.toggle_key') == 'p' and len(hosted) >= 13, hosted
        # On a bare engine the runtime starts with its native features reported unavailable.
        assert 'Photo Mode started on Boot Mod Loader' in log and 'stopped after an error' not in log and 'cleanup failed' not in log, log
        # A refusing helper hands Photo Mode the engine input on the first frame.
        assert 'Input helper unavailable: Refused: installed game hashes do not match' in log, log
        if release:
            assert 'Native diagnostics (' not in log and 'Windows engine namespaces:' not in log, 'Public startup must not run development inventories'
        else:
            assert 'Native diagnostics (0 s)' in log and 'Native diagnostics failed' not in log, 'The start-up native diagnostic runs'
        # No bridge on a bare engine: the HUD probe stops once, saying why.
        assert log.count('HUD probe stopped: ') == (0 if release else 1), log
        # No LLL and no Linux worker: the engine writes DDS into the game's settings folder.
        assert 'Engine DDS capture selected: ' + str(game).replace('\\', '/') in log, log
        sources = packed_sources(text)
        (game / 'wj-dev-reload.enabled').write_bytes(b'wjl-dev-reload-v1\n')
        rows = [(name, body.encode('utf-8')) for name, body in sources.items()]
        packed = f'WJL-LUA-1\n{len(rows)}\n'.encode() + b''.join(f'{name}\n{len(body)}\n'.encode() + body for name, body in rows)
        (game / 'wj-dev-fixture.lua-pack').write_bytes(packed)
        (game / 'wj-dev-fixture2.lua-pack').write_bytes(packed)
        if release:
            # Live reload is a development tool: public packages carry no reload module at
            # all, and an armed marker left from a dev build changes nothing.
            assert not any(name.endswith('windows_dev_reload.lua') for name in sources), 'Public packages must not carry live reload'
            before_log = log_path.read_text()
            (game / 'wj-native-dof-selftest.request').write_text('native-dof-override-v1\n')
            run_boot(text)
            public_log = log_path.read_text()[len(before_log):]
            assert 'Dev reload enabled' not in public_log and 'self-test' not in public_log
            assert (game / 'wj-native-dof-selftest.request').is_file(), 'Public mode must ignore old dev markers'
            dev_reload = 'absent'
        else:
            # Development builds reload their Lua live; prove it on this exact text.
            reload = _boot(RELOAD, text)
            assert (reload['first'], reload['calls'], reload['shut']) == (('game', .5), 332, True)
            reload_log = log_path.read_text()
            assert 'Dev reload enabled' in reload_log, reload_log
            assert 'Dev reload: loaded fixture;' in reload_log and 'Dev reload: loaded fixture2;' in reload_log, reload_log
            assert 'fixture failed generation' in reload_log and 'Photo Mode resumed after explicit Lua reload' in reload_log, reload_log
            assert len(reload['keys']) == len(hosted), 'Reload duplicated hosted bindings'
            dev_reload = 'two generations'
    return {'hosted_keys': len(hosted), 'launch': 'cmd.exe once', 'dev_reload': dev_reload}


def verify_lll(text):
    """LLL runs the chunk with the mod's name as its argument and drives the entry itself."""
    from lupa.lua51 import LuaRuntime, lua_type
    with boot_env() as game:
        lll = Path(os.environ['LOCALAPPDATA']) / 'LLL/Helldivers2'
        (lll / 'Native').mkdir(parents=True)
        (lll / 'Settings' / ID).mkdir(parents=True)
        lua = LuaRuntime()
        lua.execute('LiveLuaLoader={}')
        entry = lua.eval('function(s,name) return assert(loadstring(s,"@"..name))(name) end')(text, RESOURCE)
        assert entry['live_lua_api'] == 1 and entry['name'] == TITLE
        for name in ('on_enable', 'on_update', 'on_disable', 'on_cleanup_poll'):
            assert lua_type(entry[name]) == 'function', name
        assert not any((lll / 'Native').iterdir()), 'LLL got a bridge: ' + ', '.join(p.name for p in (lll / 'Native').iterdir())


# Boot Mod Loader only: the WJL helper and its pipes, and live reload. Never compiled under Chef.
BOOT_ONLY = ('windows_input_service.lua', 'vendor/wjl_transport.lua', 'vendor/wjl_capture.lua',
             'vendor/wjl_input_service.lua', 'wjl_helper_payload.lua', 'wjl_helper_startup.lua', 'windows_dev_reload.lua')

# Run the package inside Chef's real sandbox.lua: start, tick, open the panel, save, stop.
# Every chunk the package compiles is recorded by name.
CHEF_FIXTURE = r'''
local SANDBOX,TEXT,CHEF_VERSION=...
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
local compiled={}
local real_loadstring=env.loadstring
rawset(env,'loadstring',function(s,n)compiled[#compiled+1]=tostring(n);return real_loadstring(s,n)end)
local registered,down={},{}
env.ModBindingsMenu=setmetatable({},{__newindex=function()error('read-only ModBindingsMenu')end,__index={window='Chef Shared Loader options menu',register_binding=function(id,label,slot,options)registered[id]=options.default.button;return true end,
 is_down=function(id)return down[id]==true end,binding=function()return{}end,poll=nop,set_binding=function()return true end}})
local chef={api=3,loader_version=CHEF_VERSION,name='mods/goose/war_journalist',log_directory='C:\\game',
 log=function(fmt,...)logs[#logs+1]=string.format(fmt,...)end,title=nop,has=function()return true end,
 hold_mouse=function(on)holds[#holds+1]=on;return true end,mouse_held=function()return false end,mouse_delta=function()return 0,0 end,
 menu_open=function()return false end,
 capture=function(what)captures=captures+1;if what=='depth'then return'goose_war_journalist_depth_01.dds'end;return'capture.dds'end}
local chunk=assert(loadstring(TEXT,'=war_journalist'));setfenv(chunk,env)
local addon=chunk(chef)
assert(type(addon)=='table'and type(addon.update)=='function'and addon.version,'The addon returns its hooks')
for _=1,30 do addon.update(1/60)end
local keys=0;for _ in pairs(registered)do keys=keys+1 end
-- Chef calls only addon.render.
local drawn=0
local base=assert(rawget(env,'render'),'No render global for Photo Mode to wrap')
assert(type(addon.render)=='function','The addon has a render hook');addon.render();assert(drawn==0)
rawset(env,'render',function(...)drawn=drawn+1;return base(...)end);addon.render();addon.render()
rawset(env,'render',base);addon.render()
addon.shutdown()
local log=files['C:/game/war_journalist_chef.log']or''
local names={};for path in pairs(files)do names[#names+1]=path end;table.sort(names)
return log,table.concat(blocked,'\n'),table.concat(logs,'\n'),keys,registered['war_journalist.toggle_key'],table.concat(names,'|'),env.DBF_PHOTO_MODE_OWNER==nil,drawn,registered['war_journalist.forward_key']..' '..registered['war_journalist.back_key']..' '..registered['war_journalist.left_key']..' '..registered['war_journalist.right_key'],table.concat(compiled,'\n')
'''


def numbers(version):
    """A version's leading number parts, as Chef's gate reads them ('1.4.2-test1' is 1.4.2)."""
    match = re.match(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?', version)
    assert match, 'Not a version: ' + version
    return tuple(int(part or 0) for part in match.groups())


def verify_chef(text, sandbox, chef_version):
    """The package in one of Chef's real sandboxes, the loader reporting chef_version."""
    from lupa.lua51 import LuaRuntime
    from test_chef_port import SANDBOX_BLOBS, sandbox_text
    sb_text, blob = sandbox_text(Path(sandbox))
    log, blocked, chef_log, keys, toggle, names, released, drawn, movement, compiled = LuaRuntime().execute(
        CHEF_FIXTURE, sb_text, text, chef_version)
    depth = numbers(chef_version) >= (1, 4, 2)
    assert ('on Chef Shared Loader ' + chef_version + ', screenshots through chef.capture'
            + (', depth through chef.capture' if depth else '') + '\n') in log, log
    assert 'Photo Mode started on Chef Shared Loader' in log, log
    assert 'Photo Mode ready on Lua 5.1' in log and 'Windows engine API' not in log, log
    assert 'stopped after an error' not in log and 'cleanup failed' not in log and 'did not start' not in log, log
    assert keys >= 13 and toggle == 'p', (keys, toggle)
    assert movement == 'up down left right', 'Movement keys: ' + movement
    assert released, 'Photo Mode owner left behind'
    assert drawn == 2 and "draws through the loader's render hook" in log, ('Photo Mode render not reached', drawn)
    assert not chef_log, chef_log
    refused = [line for line in blocked.split('\n') if line.startswith('blocked:')]
    assert not refused, 'Chef refused a call: ' + '\n'.join(refused)
    assert names == 'C:/game/war_journalist_chef.log', names
    compiled = compiled.split('\n') if compiled else []
    assert not any(name.endswith(tuple('/src/' + m for m in BOOT_ONLY)) for name in compiled), compiled
    assert '@' + ID + '/src/chef_host.lua' in compiled, compiled
    return {'sandbox_git_blob': blob, 'chef_version': chef_version, 'sandbox': SANDBOX_BLOBS[blob], 'keys': keys,
            'render_hook_forwards': drawn, 'movement_keys': movement, 'refused_calls': 0,
            'files_written': names.split('|'), 'compiled': len(compiled)}


GATE = r'''
local TEXT,VERSION,NO_FOLDER=...
local touched=function(name)return setmetatable({},{__index=function(_,k)error(name..'.'..tostring(k)..' touched below the minimum Chef')end})end
local env=setmetatable({io=touched('io'),os=touched('os'),stingray={}},{__index=_G})
local lines={}
local chef={loader_version=VERSION,log_directory=not NO_FOLDER and'C:\\game'or nil,title=function()end,log=function(fmt,...)lines[#lines+1]=string.format(fmt,...)end}
local chunk=assert(loadstring(TEXT,'=war_journalist'));setfenv(chunk,env)
local addon=chunk(chef)
assert(type(addon)=='table','The gate returns hooks')
for _=1,3 do addon.update(1/60)end;addon.render();addon.shutdown();addon.on_stop()
return table.concat(lines,'\n'),#lines
'''


def verify_chef_gate(text):
    """Below Chef 1.4.0 (or with no version) the package says so once and stays off. A loader
    that passes no log folder is not Chef: the package stops with a message saying so."""
    from lupa.lua51 import LuaError, LuaRuntime
    for version in ('1.3.9', None, '1.3.1'):
        lines, count = LuaRuntime().execute(GATE, text, version)
        assert count == 1 and lines == 'War Journalist needs Chef Shared Loader ' + MINIMUM_CHEF + ' or newer', (version, lines)
    try:
        LuaRuntime().execute(GATE, text, '1.5.1', True)
    except LuaError as error:
        assert 'War Journalist for Chef needs Chef Shared Loader' in str(error), error
    else:
        raise AssertionError('A Chef table without a log folder was accepted')


def verify_key_carry_over(text):
    """1.3.x was mods/goose/war_journalist_lua51, so Boot Mod Loader kept its keys in
    mbm_war_journalist_lua51_settings.txt; the package copies them to its new name once."""
    old_bytes = b'war_journalist_toggle_key=f8\r\n#end\r\n'
    with boot_env() as game:  # old only: copied byte for byte, old kept
        (game / 'mbm_war_journalist_lua51_settings.txt').write_bytes(old_bytes)
        run_boot(text)
        assert (game / 'mbm_war_journalist_settings.txt').read_bytes() == old_bytes
        assert (game / 'mbm_war_journalist_lua51_settings.txt').read_bytes() == old_bytes
        assert 'Keys carried over from mbm_war_journalist_lua51_settings.txt' in (game / 'war_journalist_lua51.log').read_text()
    with boot_env() as game:  # new already there, even empty: untouched
        (game / 'mbm_war_journalist_lua51_settings.txt').write_bytes(old_bytes)
        (game / 'mbm_war_journalist_settings.txt').write_bytes(b'')
        run_boot(text)
        assert (game / 'mbm_war_journalist_settings.txt').read_bytes() == b''
        assert 'Keys carried over' not in (game / 'war_journalist_lua51.log').read_text()
    with boot_env() as game:  # neither: nothing made
        run_boot(text)
        assert not (game / 'mbm_war_journalist_settings.txt').exists()


def verify_loaders(text):
    """Boot Mod Loader 0.13.4 starts the package itself; LLL does not take it for a Chef addon."""
    from bml_loader_checks import bml_starts, lll_chef_style
    assert bml_starts(text) == (True, 'starts'), bml_starts(text)
    assert not lll_chef_style(text)
    # for_chef reads the whole file. Today a module line local chef=... would be read in scope
    # only because a type(chef) test happens to exist somewhere; keep the line out altogether.
    assert not re.search(r'\nlocal\s+chef\s*=\s*\.\.\.', text), 'A line local chef=... in the package'
    add = '-- HD2-Addon: mods/a/b\n'
    assert bml_starts(add + '-- HD2-Requires: chef-shared-loader\nreturn 1\n') == (False, 'for chef')
    assert bml_starts(add + 'local chef = ...\nchef.log("x")\n') == (False, 'for chef')
    assert bml_starts(add + 'local chef = ...\nif type(chef)~="table" then return end\nchef.log("x")\n') == (True, 'starts')
    assert bml_starts('return 1\n') == (False, 'no HD2-Addon line')
    assert lll_chef_style(add + 'local chef = ...\n')
    return {'bml_0.13.4': 'starts', 'lll': 'not chef-style'}


# The one ZIP: the War Journalist payload, the 1.3.0 assets, and the texts beside them.
NAMES = ({f'Assets/{a}{s}' for a in ('9ba626afa44a3aa3.patch_0', 'ee6b1ba7e22d71ed.patch_0') for s in ('', '.gpu_resources', '.stream')}
         | {f'War Journalist/9ba626afa44a3aa3.patch_0{s}' for s in ('', '.gpu_resources', '.stream')}
         | {'War Journalist/b42c756875139ce2.lua', 'manifest.json', 'PROVENANCE.json', 'INSTALL.txt', 'KNOWN-ISSUES.md',
            'LICENSE-Link.txt', 'LICENSE-Bingus.txt', 'Chef-LICENSE.txt', 'FILES-SHA256.txt'})
# The WJL helper (war_journalist_helper.exe) the Boot Mod Loader host starts.
HELPER_SHA256 = 'a6f5f3f6aede55b22627911b0c4429169e98d4378b7ca934cced0e7fa67723ef'


def zip_mode(addon, release):
    """Whether a built addon is a release. release=None reads it from the addon; True or False
    must agree with it."""
    built = 'local RELEASE_MODE=true\n' in addon
    assert ('SOURCES["src/windows_dev_reload.lua"]' in addon) == (not built), 'Live reload only in dev builds'
    if release is not None and release != built:
        raise AssertionError('This ZIP is ' + ('a release, but --release was not given' if built else
                                               'a development build, but --release was given'))
    return built


def verify_zip(path, release=None):
    """The built ZIP: its exact files and sums, the Arsenal manifest, the addon, the assets.
    release=None reads the build kind from the ZIP."""
    import hashlib
    import json
    import zipfile
    from package_head import ASSETS_SHA256, GUID, OPTION, check_size
    sha256 = lambda data: hashlib.sha256(data).hexdigest()
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        addon = z.read('War Journalist/b42c756875139ce2.lua').decode()
        release = zip_mode(addon, release)
        assert names - {'RELEASE-NOTES.md'} == NAMES and (not release or 'RELEASE-NOTES.md' in names), names ^ NAMES
        assert z.testzip() is None
        for line in z.read('FILES-SHA256.txt').decode().splitlines():
            digest, name = line.split('  ', 1)
            assert sha256(z.read(name)) == digest, name
        m = json.loads(z.read('manifest.json'))
        assert m['Guid'] == GUID and m['Name'].startswith('War Journalist '), m
        assert m['Options'] == [{'Name': OPTION, 'Description': 'Photo Mode and its assets.', 'Include': [OPTION, 'Assets']}], m['Options']
        verify_shape(addon)
        check_size(addon)
        assert HELPER_SHA256 in addon, 'The committed WJL helper ships'
        for name, digest in ASSETS_SHA256.items():
            assert sha256(z.read('Assets/' + name)) == digest, name
        return {'release': release, 'files': len(names), 'addon_bytes': len(addon.encode())}

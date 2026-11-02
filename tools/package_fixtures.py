"""Offline proofs for the one War Journalist package: the generated text on each host that can
run it. Lua 5.1 through lupa; fakes only, never the game. Used by test_package.py and
build_package.py."""
from contextlib import contextmanager
from pathlib import Path
import os
import re
import tempfile

from build_steam_candidate import DEV_ONLY, FFI, MODULES, ROOT
from package_head import ID, RESOURCE, TITLE


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

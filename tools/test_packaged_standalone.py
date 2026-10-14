"""Execute immutable BSL/MDL/LLL packages with no source checkout or optional mods.

Uses the installed LuaJIT in a separate test process, never the game process.
Engine drawing is mocked; packaged private services and native DLLs are real.
No input hook is installed and no game memory is read or written.
"""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import struct
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import run_lua
import lua_archive
import photo_assets
from verify_release import embedded_payload


def lua_string(value):
    marker = '='
    while ']' + marker + ']' in value:
        marker += '='
    return '[' + marker + '[' + value + ']' + marker + ']'


def pe_imports(body):
    """Read PE import and delay-import tables without external tools."""
    assert body[:2] == b'MZ'
    pe = struct.unpack_from('<I', body, 60)[0]
    assert body[pe:pe + 4] == b'PE\0\0'
    machine, sections, _, _, _, optional_size = struct.unpack_from('<HHIIIH', body, pe + 4)
    assert machine == 0x8664, 'Native DLL must be AMD64'
    optional = pe + 24
    assert struct.unpack_from('<H', body, optional)[0] == 0x20B
    image_base = struct.unpack_from('<Q', body, optional + 24)[0]
    table = optional + optional_size

    def offset(rva):
        for at in range(table, table + sections * 40, 40):
            virtual_size, virtual, raw_size, raw = struct.unpack_from('<IIII', body, at + 8)
            if virtual <= rva < virtual + max(virtual_size, raw_size):
                return raw + rva - virtual
        raise AssertionError('PE RVA outside section')

    imports = set()
    for index, stride, name_field in ((1, 20, 12), (13, 32, 4)):
        rva, size = struct.unpack_from('<II', body, optional + 112 + index * 8)
        if not rva:
            continue
        start = offset(rva)
        for at in range(start, start + size, stride):
            entry = body[at:at + stride]
            if not any(entry):
                break
            name_rva = struct.unpack_from('<I', entry, name_field)[0]
            if index == 13 and not struct.unpack_from('<I', entry)[0] & 1:
                name_rva -= image_base
            name = offset(name_rva)
            imports.add(body[name:body.index(b'\0', name)].decode('ascii').lower())
    return sorted(imports)


def payload(archive):
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
        files = {}
        for name in zipped.namelist():
            entry = PurePosixPath(name)
            assert not entry.is_absolute() and '..' not in entry.parts and '\\' not in name
            if not name.endswith('/'):
                files[name] = zipped.read(name)
    if 'Addon/9ba626afa44a3aa3.patch_0' in files:
        prefix = 'Addon/9ba626afa44a3aa3.patch_0'
        resources = photo_assets.read_archive(files[prefix], files.get(prefix + '.gpu_resources', b''), files.get(prefix + '.stream', b''))
        entries = [cpu for name, kind, cpu, _ in resources
                   if name == lua_archive.hash_name('mods/dbf_photomode/startup') and kind == lua_archive.LUA_TYPE]
        assert len(entries) == 1, 'Exactly one packaged Lua startup required'
        body = entries[0]
        startup = body[8:].rstrip(b'\0').decode()
        return 'BSL', startup, embedded_payload(startup)
    prefix = 'dbf_freecam/'
    assert all(name.startswith((prefix, 'GameData/', 'Arsenal/')) or name in ('manifest.json', 'INSTALL.txt', 'FILES-SHA256.txt') for name in files)
    files = {name[len(prefix):]: body for name, body in files.items() if name.startswith(prefix)}
    if 'main.lua' in files:
        manifest=json.loads(files['manifest.json'])
        assert manifest['lll']['entry']=='main.lua' and manifest['lll']['restart_only'] and manifest['lll']['retain_until_exit']
        return 'LLL', files['main.lua'].decode(), files
    return 'MDL', files['mod.lua'].decode(), files


MOCK = r'''
local real_open,real_remove,real_rename=io.open,os.remove,os.rename
local function local_path(path)
 assert(type(path)=='string','Non-string file path')
 local norm=path:gsub('\\','/'):lower()
 assert(not norm:find('/../',1,true)and not norm:match('^%.%./'),'Traversal rejected')
 if not norm:match('^%a:/')then norm=TEST_ROOT:lower()..'/'..norm end
 assert(norm:sub(1,#TEST_ROOT+1)==TEST_ROOT:lower()..'/','File IO escaped isolated package: '..path)
 return path
end
io.open=function(path,...)return real_open(local_path(path),...)end
os.remove=function(path)return real_remove(local_path(path))end
os.rename=function(a,b)return real_rename(local_path(a),local_path(b))end
os.getenv=function(name)assert(name=='LOCALAPPDATA','Unexpected environment dependency: '..name);return TEST_APPDATA end
os.execute=function()error('Shell execution forbidden')end
package.path='';package.cpath='';package.loadlib=function()error('Lua native source fallback forbidden')end
local builtin_require=require
require=function(name)
 assert(name=='ffi'or name=='bit'or name=='jit.util','Unexpected external Lua prerequisite: '..name)
 return builtin_require(name)
end
loadfile=function(path)
 local f=assert(io.open(local_path(path),'rb'));local body=f:read('*a');f:close();return loadstring(body,'@'..path)
end
dofile=function(path)return assert(loadfile(path))()end
local ffi=require('ffi');local real_load=ffi.load
local dll_loads={}
ffi.load=function(path,...)
 local name=tostring(path):lower()
 if not(name=='kernel32'or name=='user32'or name=='bcrypt')then local_path(path)end
 dll_loads[#dll_loads+1]=name;return real_load(path,...)
end
local prior_updates,prior_renders=0,0
update=function()prior_updates=prior_updates+1 end
render=function()prior_renders=prior_renders+1 end
shutdown=function()end
local world={};local created,destroyed,primitives=0,0,0
local function vec(x,y,z,w)return {x=x or 0,y=y or 0,z=z or 0,w=w or 0}end
local v3=setmetatable({x=function(v)return v.x end,y=function(v)return v.y end,z=function(v)return v.z end},{__call=function(_,...)return vec(...)end})
local function primitive()primitives=primitives+1;return primitives end
local focus,cursor,clip=true,false,true
stingray={Vector3=v3,Vector2=vec,Vector4=vec,Color=function(...)return {...}end,Matrix4x4={},Quaternion={},Camera={},Unit={},
 Window={mouse_focus=function()return focus end,show_cursor=function()return cursor end,clip_cursor=function()return clip end,
 set_mouse_focus=function(v)focus=v end,set_show_cursor=function(v)cursor=v end,set_clip_cursor=function(v)clip=v end},
 Application={worlds=function()return {world}end,main_world=function()return world end},
 World={units=function()return {}end,create_screen_gui=function()created=created+1;return {}end,destroy_gui=function()destroyed=destroyed+1 end},
 Gui={resolution=function()return 1920,1080 end,rect=primitive,text=primitive,triangle=primitive,
 destroy_rect=function()end,destroy_text=function()end,destroy_triangle=function()end,
 text_extents=function(_,text,_,size)return vec(0,0),vec(#text*size*.62,size)end}}
assert(DBFMCM==nil and package.loaded['mods/actioncam/actioncam']==nil)
local logs,cleanup={},{}
local function log(message)logs[#logs+1]=tostring(message)end
'''

CHECK = r'''
if TEST_LOADER~='LLL'then
 assert(DBF_PHOTO_MODE_OWNER and DBF_PHOTO_MODE_OWNER.started and not DBF_PHOTO_MODE_OWNER.failed,'Packaged startup failed: '..table.concat(logs,' | '))
 assert(DBF_PHOTO_MODE_STARTED,'Packaged startup marker missing')
end
assert(DBF_PHOTO_STANDALONE_API,'Private standalone API missing')
assert(DBFMCM==nil,'Standalone package must not publish MCM')
update(.016);render();render()
local api=DBF_PHOTO_STANDALONE_API
assert(api.photo_standalone and api.camera_input.api==2 and type(api.camera_input.set_focus)=='function')
assert(api.mods.dbf_freecam and #api.mods.dbf_freecam.pages>=5,'Full Photo Mode settings failed registration')
local controls=0
for _,page in ipairs(api.mods.dbf_freecam.pages)do for _ in ipairs(page.controls)do controls=controls+1 end end
assert(controls>60,'Incomplete settings payload')
assert(api.set('dbf_freecam','speed',4.5),'Private settings persistence failed')
assert(api.get('dbf_freecam','speed')==4.5,'Private settings readback failed')
local config=assert(io.open(TEST_APPDATA..'/DBF/PhotoMode/settings/dbf_freecam.ini','rb'),'Private config escaped PhotoMode settings directory')
assert(config:read('*a'):find('speed=4.5',1,true),'Private settings file value mismatch');config:close()
assert(type(api.camera_input.now())=='number','Private native clock unavailable')
assert(api.camera_input.release(),'Inactive native input release failed')
local view=api.create_photo_view();assert(view and type(view.draw)=='function')
view.draw({{type='rect',x=2,y=2,w=20,h=10,c={255,255,255},a=1},{type='text',text='Photo Mode',x=2,y=2,size=12,c={255,255,255},a=1}})
assert(primitives>=2 and created>=1,'Packaged private view failed drawing')
view.release();assert(destroyed>=1,'Private view failed cleanup')
assert(focus==true and cursor==false and clip==true,'Fixture must not acquire native/game input')
assert(prior_updates>=1 and prior_renders==2,'Loader hooks lost previous callbacks')
for _,message in ipairs(logs)do assert(not message:lower():find('startup failed',1,true),message)end
'''


def verify(archive):
    loader, startup, files = payload(archive)
    native_name = files['standalone-library.txt'].decode().strip()
    capture_names = [name for name in files if name.startswith('PhotoCapture') and name.endswith('.dll')]
    assert len(capture_names)==1, 'Exactly one active packaged screenshot DLL required'
    capture_name=capture_names[0]
    libraries = {native_name: files[native_name], capture_name: files[capture_name]}
    if 'hover-library.txt' in files:
        hover_name=files['hover-library.txt'].decode().strip()
        assert hover_name.startswith('PhotoHoverGuard_') and hover_name.endswith('.dll')
        libraries[hover_name]=files[hover_name]
    imports = {}
    with tempfile.TemporaryDirectory(prefix='photo-standalone-') as scratch:
        isolated = Path(scratch)
        package = isolated / 'package'
        appdata = isolated / 'appdata'
        (appdata / 'CowboyBingus/Helldivers2/Logs').mkdir(parents=True)
        (appdata / 'DBF/PhotoMode/settings').mkdir(parents=True)
        package.mkdir()
        for name, body in files.items():
            destination = package / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(body)
        # The search explicitly excludes PATH and installed redistributables.
        system32 = Path(os.environ['SystemRoot']) / 'System32'
        for name, body in libraries.items():
            imports[name] = pe_imports(body)
            for dependency in imports[name]:
                assert not dependency.startswith(('vcruntime', 'msvcp', 'concrt')), 'VC++ redistributable prerequisite: ' + dependency
                assert dependency.startswith(('api-ms-win-', 'ext-ms-win-')) or (system32 / dependency).is_file() or dependency in libraries, 'Unbundled native dependency: ' + dependency
            handle = ctypes.WinDLL(str(package / name), winmode=0x100 | 0x800)
            free = ctypes.windll.kernel32.FreeLibrary
            free.argtypes = [ctypes.c_void_p]
            assert free(handle._handle), 'Native test library unload failed'
        source = ('TEST_ROOT=' + lua_string(isolated.as_posix()) + '\nTEST_APPDATA=' + lua_string(appdata.as_posix()) + '\nTEST_LOADER='+lua_string(loader)+'\n').encode() + MOCK.encode()
        if loader == 'BSL':
            source += ('\nassert(loadstring(' + lua_string(startup) + ',"@immutable-BSL-package"))()\nupdate(.016)\n').encode()
        elif loader == 'LLL':
            declared = json.loads(files['manifest.json'])['lll']['modules']
            actual = sorted(name for name in files if name.startswith('src/') and name.endswith('.lua'))
            assert declared == actual, 'LLL module declarations differ from packaged source'
            allowed = '{' + ','.join('[ ' + lua_string(name) + ' ]=true' for name in declared) + '}'
            source += ('\nmod={dir='+lua_string(package.as_posix())+',config_dir=TEST_APPDATA.."/DBF/PhotoMode/settings",log=log}\n'
                       'mod.read=function(name)local f=assert(io.open(mod.dir.."/"..name,"rb"));local body=f:read("*a");f:close();return body end\n'
                       'local declared='+allowed+';local cache={}\n'
                       'mod.require=function(name)assert(declared[name],"Module not declared in this project: "..name);if cache[name]~=nil then return cache[name]end;local value=assert(loadstring(mod.read(name),"@"..mod.dir.."/"..name))();if value==nil then value=true end;cache[name]=value;return value end\n'
                       'local adapter=assert(loadstring('+lua_string(startup)+',"@immutable-LLL-package"))()\n'
                       'assert(adapter.live_lua_api==1);adapter.on_enable();adapter.on_update(.016)\n').encode()
        else:
            source += ('\nlocal real_globals=_G;local proxy=setmetatable({},{__index=function(_,key)return real_globals[key]end,__newindex=function()error("MDL sandbox proxy mutated")end})\n'
                       'local env=setmetatable({_G=proxy,rawget=function(tbl,key)if tbl==proxy then return proxy[key]end;return rawget(tbl,key)end},{__index=_G})\n'
                       'local entry=assert(loadstring(' + lua_string(startup) + ',"@immutable-MDL-package"));setfenv(entry,env);local adapter=entry()\n'
                       'local ctx={api=2,dir=' + lua_string(package.as_posix()) + ',log=log,on_cleanup=function(fn)cleanup[#cleanup+1]=fn end}\n'
                       'adapter.on_enable(ctx);adapter.on_update(ctx,.016)\n').encode()
        source += CHECK.encode()
        if loader == 'MDL':
            source += b'\nadapter.on_disable(ctx);for _,fn in ipairs(cleanup)do fn()end;assert(DBF_PHOTO_MODE_OWNER.stopped)\n'
        elif loader == 'LLL':
            source += b'\nlocal allowed,reason=adapter.on_disable();assert(allowed==false and reason:find("normal restart",1,true),"LLL must retain camera hooks until process exit");shutdown();assert(api.camera_input.release());assert(DBF_PHOTO_STANDALONE_API==api,"LLL retained service must survive until exit");print("Packaged LLL standalone bootstrap, full settings, private view and restart retention passed")\n'
        else:
            source += b'\nshutdown()\n'
        if loader != 'LLL':
            source += b"assert(DBF_PHOTO_STANDALONE_API==nil,'Private API leaked after shutdown');print('Packaged standalone bootstrap, full settings, private view and owned cleanup passed')\n"
        previous = Path.cwd()
        try:
            os.chdir(isolated)
            run_lua.run(source, 'immutable-' + loader + '-standalone')
        except RuntimeError as error:
            startup_log = appdata / 'DBF/PhotoMode/PhotoMode-startup.log'
            detail = startup_log.read_text(errors='replace')[-2000:] if startup_log.is_file() else ''
            raise RuntimeError(str(error) + ('\nBSL startup log:\n' + detail if detail else '')) from error
        finally:
            os.chdir(previous)
    return {'archive': archive.name, 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'loader': loader, 'passed': True, 'native_imports': imports,
            'native_search': 'Package directory and Windows System32 only; no PATH',
            'optional_mods_present': False, 'repository_source_fallback': False,
            'private_settings_persisted': 'LocalAppData/DBF/PhotoMode/settings/dbf_freecam.ini',
            'engine_drawing': 'controlled mocks; actual packaged private renderer module',
            'shutdown_behavior': 'Restart retention after camera-hook startup verified' if loader == 'LLL' else 'Owned shutdown cleanup verified',
            'game_process_accessed': False, 'native_input_hook_installed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, nargs='+')
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    results = [verify(archive.resolve()) for archive in args.archive]
    receipt = {'passed': True, 'checked_at_utc': datetime.now(timezone.utc).isoformat(), 'results': results,
               'limits': 'Does not prove native input acquisition, engine screenshots, camera discovery, material/shader registration or visual DoF.'}
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()

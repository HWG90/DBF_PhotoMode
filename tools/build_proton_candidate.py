"""Build the Proton (LuaJIT under LLL) War Journalist folder candidate; never installs.

The same source tree also builds the Boot Mod Loader package (build_steam_candidate),
which refuses FFI. This build keeps everything the LLL host can run on Proton:
LuaJIT FFI enemy behavior, the native bridges and LLL's capture/input services.
It packages exactly the private require-closure of the entry, so engine-host
(Boot Mod Loader / native Windows) payloads stay out unless something imports them.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import zipfile

from verify_installed_modules import audit, IMPORT
from test_steam_port import run
# Game build 26251122. One bridge serves memory, lens, HUD, keyboard, hover and pointer clip; the
# scene bridge binds depth. The Boot Mod Loader list (build_steam_candidate) loads none in game.
NATIVE_LIBRARIES=('port51/hd2_nativeinfo_c1578203689e39b9.dll','port51/hd2_nativeinfo_8db3d96f8c3cbb24.dll')
from build_steam_archive import build_id

ROOT=Path(__file__).resolve().parents[1]
MOD_ID='dbf_freecam'

def digest(data):return hashlib.sha256(data).hexdigest()

def closure(entry_source):
    """Every src/ module reachable by literal mod.require from the entry."""
    seen,queue=set(),list(IMPORT.findall(entry_source))
    while queue:
        name=queue.pop()
        if name in seen:continue
        seen.add(name)
        path=ROOT/'freecam'/name[len('src/'):]
        assert path.is_file(),'Missing private module '+name
        queue.extend(IMPORT.findall(path.read_text(encoding='utf-8')))
    return sorted(seen)

def build(output):
    from lupa.luajit21 import LuaRuntime as LuaJIT
    from lupa.lua51 import LuaRuntime as Lua51
    output=output.resolve()
    assert output.is_relative_to(ROOT/'dist/review'),'Development builds stay in dist/review'
    output.mkdir(parents=True,exist_ok=True)
    fixture=run()
    version=(ROOT/'VERSION').read_text().strip()+'-proton'
    entry=(ROOT/'freecam/steam51.lua').read_text(encoding='utf-8')
    modules=closure(entry)
    manifest={'id':MOD_ID,'name':'War Journalist','version':version,'author':'Goose',
              'lll':{'entry':'main.lua','defaults':'config/defaults.cfg','modules':modules,
                     'restart_only':False,'retain_until_exit':False},
              'license_files':['LICENSE-Link.txt','LICENSE-Bingus.txt'],
              'native_libraries':list(NATIVE_LIBRARIES)}
    # LLL's mod table carries no version; the Photo menu shows the one stamped here.
    build=build_id()
    stamp=('-- Stamped by build_proton_candidate.py: the version and build the Photo menu shows.\n'
           'if type(mod)=="table"then mod.version=mod.version or '+json.dumps(version)+';mod.build=mod.build or '+json.dumps(build)+' end\n')
    files={'main.lua':(stamp+entry).encode('utf-8'),'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),
           'config/defaults.cfg':b'{}\n'}
    for name in NATIVE_LIBRARIES:files[name]=(ROOT/'freecam/native'/name).read_bytes()
    for label in manifest['license_files']:files[label]=(ROOT/'freecam/vendor'/label).read_bytes()
    for name in modules:files[name]=(ROOT/'freecam'/name[len('src/'):]).read_bytes()
    # Both VMs must load every chunk: LLL on Proton runs LuaJIT, its fallback PUC 5.1.
    compilers=[runtime().eval('function(s,n) return assert(loadstring(s,n)) end')for runtime in (LuaJIT,Lua51)]
    for name,body in files.items():
        if name.endswith('.lua'):
            source=body.decode('utf-8')
            # LLL refuses a script with a literal ffi/bit require on non-FFI hosts.
            assert not re.search(r"\brequire\s*\(\s*['\"](?:ffi|bit)['\"]",source),name+': pass ffi/bit through a variable'
            for compile_lua in compilers:compile_lua(source,'@'+name)
    provenance={'version':version,'build':build,'runtime':'LuaJIT 2.1 under LLL (Proton); Lua 5.1 compatible','candidate_only':True,
                'publication_performed':False,'source_sha256':{name:digest(body)for name,body in files.items()},
                'ffi':'optional; enemy behavior only, through cffi or LuaJIT ffi',
                'native_bridges':list(NATIVE_LIBRARIES),'modules':len(modules)}
    files['PROVENANCE.json']=(json.dumps(provenance,indent=2)+'\n').encode()
    files['FILES-SHA256.txt']=''.join(digest(body)+'  '+name+'\n'for name,body in sorted(files.items())).encode()
    package=output/('War-Journalist-'+version+'-LLL.zip')
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,body in files.items():archive.writestr(MOD_ID+'/'+name,body)
    unpacked=output/'candidate'
    if unpacked.exists():
        assert unpacked.resolve().is_relative_to(ROOT/'dist/review')
        shutil.rmtree(unpacked)
    with zipfile.ZipFile(package)as archive:archive.extractall(unpacked)
    directory=unpacked/MOD_ID
    for name,body in files.items():assert (directory/name).read_bytes()==body,name
    report=audit(directory);assert report['passed'],report['errors']
    receipt={'package':str(package),'sha256':digest(package.read_bytes()),'candidate':str(directory),
             'modules':modules,'fixtures':fixture,'module_audit':report,'installed':False,'live_acceptance':'pending'}
    (output/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'dist/review/proton/package')
    args=parser.parse_args()
    result=build(args.output)
    print(json.dumps({'package':result['package'],'sha256':result['sha256'],'candidate':result['candidate'],
                      'modules':len(result['modules']),'installed':False},indent=2))

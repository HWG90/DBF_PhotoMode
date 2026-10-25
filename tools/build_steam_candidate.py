"""Build and validate the modular Steam Lua 5.1 development port; never installs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import zipfile

from verify_installed_modules import audit
from test_steam_port import run

ROOT=Path(__file__).resolve().parents[1]
# Own LLL folder/id so it installs beside the FFI build (dbf_freecam); the
# runtime's internal 'dbf_freecam' ids stay, so only one can run at a time.
MOD_ID='dbf_freecam_lua51'
MODULES=('steam_overlay.lua', 'steam_camera.lua', 'steam_input.lua', 'steam_path.lua', 'steam_runtime.lua', 'steam_capture.lua', 'steam_lighting.lua', 'photo_lights.lua', 'photo_light_presets.lua', 'photo_light_gizmos.lua', 'photo_options.lua', 'photo_menu.lua', 'control_legend.lua', 'composition.lua', 'look.lua', 'lens.lua', 'vendor/core.lua', 'vendor/store.lua', 'vendor/view.lua', 'assets/logo_art.lua', 'assets/helldiver_crest.lua', 'steam_bookmark.lua', 'host_native.lua', 'subject_backend.lua', 'subject_visibility.lua', 'input_cleanup.lua', 'vendor/font.lua', 'director.lua', 'steam_subject.lua', 'steam_subject_native.lua', 'subject_poses.lua', 'assets/steam_subject_poses.lua', 'steam_hud.lua', 'linux_capture.lua', 'steam_handycam.lua', 'ragdoll_pause.lua', 'steam_lens_model.lua', 'steam_native_lens.lua', 'hover_pause.lua', 'steam_hover_backend.lua', 'steam_hover_pause.lua', 'steam_update_clock.lua', 'steam_scene_resources.lua', 'steam_scene_overlay.lua', 'steam_focus_sampler.lua', 'steam_scene.lua', 'steam_pick.lua', 'engine_input.lua', 'steam_bindings.lua', 'native_diagnostics.lua', 'engine_capture.lua')
# Plain Lua 5.1 only: no cffi/ffi imports, ffi calls, cdef blocks or PORT51 adapters.
FFI=re.compile(r"['\"]c?ffi['\"]|\bffi\s*\.|\bcdef\b|\bPORT51\b|luaopen_hd2_cffi")
NATIVE_LIBRARIES=('port51/hd2_nativeinfo_f6d3465944c1aea1.dll', 'port51/hd2_nativeinfo_3139cc5f8ecb4078.dll', 'port51/hd2_nativeinfo_78b314de6177433d.dll', 'port51/hd2_nativeinfo_4aab2adfbc4090d6.dll', 'port51/hd2_nativeinfo_5e39eeeeb76b863a.dll')

def digest(data):return hashlib.sha256(data).hexdigest()
def build(output,release=False):
    from lupa.lua51 import LuaRuntime
    output=output.resolve()
    assert output.is_relative_to(ROOT/'dist/review'),'Development port must stay in dist/review'
    output.mkdir(parents=True,exist_ok=True)
    fixture=run()
    # A public build carries the plain version; everything else stays marked as a candidate.
    version=(ROOT/'VERSION').read_text().strip()+(''if release else'-steam51-dev')
    manifest={'id':MOD_ID,'name':'War Journalist (Lua 5.1)','version':version,'author':'Goose',
              'lll':{'entry':'main.lua','defaults':'config/defaults.cfg','modules':['src/'+name for name in MODULES],
                     'restart_only':False,'retain_until_exit':False}}
    manifest['license_files']=['LICENSE-Link.txt','LICENSE-Bingus.txt']
    manifest['native_libraries']=list(NATIVE_LIBRARIES)
    files={'main.lua':(ROOT/'freecam/steam51.lua').read_bytes(),'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),
           'config/defaults.cfg':b'{}\n'}
    for name in NATIVE_LIBRARIES:files[name]=(ROOT/'freecam/native'/name).read_bytes()
    for label in manifest['license_files']:files[label]=(ROOT/'freecam/vendor'/label).read_bytes()
    for name in MODULES:files['src/'+name]=(ROOT/'freecam'/name).read_bytes()
    compile_lua=LuaRuntime().eval('function(s) return assert(loadstring(s)) end')
    for name,body in files.items():
        if name.endswith('.lua'):
            source=body.decode('utf-8')
            assert not re.search(r"\brequire\s*\(\s*['\"](?:ffi|bit|jit(?:\.[^'\"]+)?)['\"]",source),name
            assert not FFI.search(source),name+' uses FFI'
            compile_lua(source)
    provenance={'version':version,'runtime':'Lua 5.1','ffi':'none; FFI enemy behavior omitted','candidate_only':not release,'publication_performed':False,
                'source_sha256':{name:digest(body)for name,body in files.items()},
                'native_features':'Still being ported; full parity is not verified',
                'minimum_input_service':1,'requires_relative_mouse':True,
                'optional_keyboard_capture':'Shared service canonical mask, owned generation and physical-key snapshot',
                'optional_capture_service':1,'capture_format':'PNG SDR game client only; HDR outputs refused',
                'development_subject_adapter':{'contract':'unit-pose-sync-v1','revision':'R34-steam-lua51-preview.1',
                    'private_unit_matrix12_roundtrip':'verified','visible_subject_pose':'pending',
                    'activation':'explicit session preview and subject selection; owned true-zero required'},
                'qualified_capture_revisions':['R33-steam-screenshots-factoryfix-candidate','R34-steam-lua51-preview.1']}
    files['PROVENANCE.json']=(json.dumps(provenance,indent=2)+'\n').encode()
    files['FILES-SHA256.txt']=''.join(digest(body)+'  '+name+'\n'for name,body in sorted(files.items())).encode()
    package=output/('War-Journalist-'+version+'-LLL.zip')
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,body in files.items():archive.writestr(MOD_ID+'/'+name,body)
    # Reconstruct only our fixed candidate directory, then audit actual bytes.
    unpacked=output/'candidate'
    if unpacked.exists():
        assert unpacked.resolve().is_relative_to(ROOT/'dist/review')
        shutil.rmtree(unpacked)
    with zipfile.ZipFile(package)as archive:archive.extractall(unpacked)
    directory=unpacked/MOD_ID
    for name,body in files.items():assert (directory/name).read_bytes()==body,name
    report=audit(directory);assert report['passed'],report['errors']
    receipt={'package':str(package),'sha256':digest(package.read_bytes()),'candidate':str(directory),'fixtures':fixture,
             'module_audit':report,'installed':False,'live_acceptance':'pending','full_feature_parity':'pending'}
    (output/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'dist/review/steam-lua51/package')
    parser.add_argument('--release',action='store_true',help='public build: plain VERSION, candidate_only false')
    args=parser.parse_args()
    result=build(args.output,args.release)
    print(json.dumps({k:result[k]for k in ('package','sha256','candidate','installed','live_acceptance')},indent=2))

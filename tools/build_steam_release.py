"""Build the public Steam Lua 5.1 package from the user-accepted installed boundary; never installs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import zipfile

from verify_installed_modules import audit
import photo_light_assets

ROOT=Path(__file__).resolve().parents[1]
# The 21-module graph accepted in game on October 20 (r34-keyboard-deployment-v1).
# Subject/pose work and its time-policy changes are excluded until live-accepted.
ACCEPTED={
 'src/steam_overlay.lua':'b28177520a20ca0ab63684604536d9c52f417ccf9cdba3e916a35b5b5ff129e4',
 'src/steam_camera.lua':'898da82fbcdf5ba96f2e8b57055068ded40eb4cee9e84752b21e19d6d6f873ab',
 'src/steam_input.lua':'c33a42d239966e1636aeb09c09196019068b939afeeb7c6aab000550950d0393',
 'src/steam_path.lua':'754fd105771f3967d9ffa589e4bd405ea4f9d6767f5c6e55cd8e749f6bd22623',
 'src/steam_runtime.lua':'71949376e038a4893fc13965a9cdad09c8413d3dac4ede5c503387179a4fe095',
 'src/steam_capture.lua':'62ab31a96beacbf1fde9a77852ad1cd2a39261247ab6085415e9c60858fb9f29',
 'src/steam_lighting.lua':'ba301d25287ddcdaced20ccc666c92b07141758678ce4ecd131cb445945c6ba8',
 'src/photo_lights.lua':'3cde3080971f0a8b63bd48ed5341245d0cb51ad89534402a2b9abfd6c66754a4',
 'src/photo_light_presets.lua':'308595fe0a3d7cd1b37722a44e14f73d4ab6af6cbe020a2c8226e8dec1a8677e',
 'src/photo_light_gizmos.lua':'8c8bd5321f31ad8bce1cbd64d66753acaf2cff464decd31169df82e53ead7d7c',
 'src/photo_options.lua':'7f1ed3b3472279ea0dd82ec636b94acf218c150dc3fb7b3b5bf06d9b5bb64697',
 'src/photo_menu.lua':'e1515784507e69ec6b4b4eb0ea89fbf9989d252dc84b57dcc1d655d1a24a94fb',
 'src/control_legend.lua':'8799cd4a8bf5a5d576ae662c6f1edc7ea1a7e576c3f7bf7b21525dd1e382bd48',
 'src/composition.lua':'3396b4b22148254ea12a642c5c8c576b44af2b78f4e6f01cdad901dd129d1074',
 'src/look.lua':'76e91cbda87a55a413358224a5380436355613429aa1f31a4fecfadc92acabe0',
 'src/lens.lua':'034773da6ea35aa4052e0cc444780cbda68a8a04ce4a25800582a43362a81fec',
 'src/vendor/core.lua':'c008876010ae194e61aea0fa7441a25af607f4b6a80fcf5aa0941aab091b88a6',
 'src/vendor/store.lua':'3bc9a632382be9591a6119c576d9c0b2f33bd0fef9db8103de00c0cff87f4382',
 'src/vendor/view.lua':'aa7ac65c1dafff5027fe1055b62f9bfe7d1a9770112603b063c16fa8bd386a40',
 'src/assets/logo_art.lua':'c0b4fe56822059ae231f9d2a96bfb34715c72640ed4b27aa88858a37292bcd55',
 'src/assets/helldiver_crest.lua':'9b0f15b912e806c2b7dda81bc7f56948b49b79357826879110106269cf668e1b'}
# Accepted entry with only its display name and ready log relabelled.
ENTRY_SHA256='ca190c051e6d734b4c2673972d64a36d0c8e8a2e495c500040e7b39aa10bd924'
LIGHT_ARCHIVE='9ba626afa44a3aa3.patch_1'
LLL_REVISION='R34-steam-lua51-preview.1'
INSTALL='''War Journalist {version} (Helldivers 2 Steam, Live Lua Loader Lua 5.1)

Requires Live Lua Loader Steam preview {lll} with its shared input and
screenshot services. Older loaders keep the camera working with Screenshot
disabled.

1. Close Helldivers 2.
2. Copy dbf_freecam into %LOCALAPPDATA%\\LLL\\Helldivers2\\Mods\\, replacing
   the runtime files. Existing settings, presets and Screenshots are kept.
3. Copy the three GameData files into Helldivers 2\\data\\. If another mod
   already provides 9ba626afa44a3aa3.patch_1, do not overwrite it; lights will
   report the backend unavailable instead.
4. Start the game normally.

Screenshot saves SDR PNGs only: turn Windows HDR off for the game display.
Not yet restored on Steam: Passive AI, Subject poses/visibility/cape,
Handycam, HUD hiding, numeric depth of field, exposure/contrast/saturation.
'''

def digest(data):return hashlib.sha256(data).hexdigest()
def source(name):
    if name=='src/steam_runtime.lua':return ROOT/'freecam/steam_release/steam_runtime.lua'
    return ROOT/'freecam'/name[4:]

def build(output):
    from lupa.lua51 import LuaRuntime
    output=output.resolve()
    assert output.is_relative_to(ROOT/'dist/releases'),'Release packages belong in dist/releases'
    version=(ROOT/'VERSION').read_text().strip()
    entry=(ROOT/'freecam/steam_release/main.lua').read_bytes()
    accepted_entry=entry.replace(b"name='War Journalist',",b"name='War Journalist \xe2\x80\x94 Lua 5.1 development port',")\
        .replace(b"'Lua 5.1 runtime ready'",b"'Lua 5.1 camera/menu candidate ready; native feature ports remain in progress'")
    assert digest(accepted_entry)==ENTRY_SHA256,'Entry differs from the accepted boundary beyond its label'
    manifest={'id':'dbf_freecam','name':'War Journalist','version':version,'author':'Goose',
              'lll':{'entry':'main.lua','defaults':'config/defaults.cfg','modules':list(ACCEPTED),
                     'restart_only':False,'retain_until_exit':False}}
    files={'main.lua':entry,'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'config/defaults.cfg':b'{}\n'}
    for name,expected in ACCEPTED.items():
        body=source(name).read_bytes();assert digest(body)==expected,'Not the accepted bytes: '+name
        files[name]=body
    compile_lua=LuaRuntime().eval('function(s) return assert(loadstring(s)) end')
    for name,body in files.items():
        if name.endswith('.lua'):
            text=body.decode('utf-8')
            assert not re.search(r"\brequire\s*\(\s*['\"](?:ffi|bit|jit(?:\.[^'\"]+)?)['\"]",text),name
            compile_lua(text)
    provenance={'version':version,'runtime':'Lua 5.1','candidate_only':False,'publication_performed':False,
                'accepted_boundary':'dist/review/steam-lua51/r34-keyboard-deployment-v1/INSTALLED-VERIFIED.json',
                'source_sha256':{name:digest(body)for name,body in files.items()},
                'required_loader_revision':LLL_REVISION,'minimum_input_service':1,'requires_relative_mouse':True,
                'optional_capture_service':1,'capture_format':'PNG SDR game client only; HDR outputs refused',
                'not_restored':['Passive AI','Subject poses/visibility/cape','Handycam','HUD hiding',
                                'numeric depth of field','exposure/contrast/saturation','HDR screenshots'],
                'decorative_shader_assets':'not included; overlay picker reports them unavailable'}
    files['PROVENANCE.json']=(json.dumps(provenance,indent=2)+'\n').encode()
    files['FILES-SHA256.txt']=''.join(digest(body)+'  '+name+'\n'for name,body in sorted(files.items())).encode()
    # The owned light unit, rebuilt deterministically from source.
    light_dir=output/'light-asset'
    if light_dir.exists():shutil.rmtree(light_dir)
    photo_light_assets.package(light_dir,LIGHT_ARCHIVE)
    game={name:(light_dir/'Assets'/name).read_bytes()for name in (LIGHT_ARCHIVE,LIGHT_ARCHIVE+'.gpu_resources',LIGHT_ARCHIVE+'.stream')}
    top={'INSTALL.txt':INSTALL.format(version=version,lll=LLL_REVISION).replace('\n','\r\n').encode()}
    for name,body in game.items():top['GameData/'+name]=body
    for name,body in files.items():top['dbf_freecam/'+name]=body
    top['SHA256SUMS.txt']=''.join(digest(body)+'  '+name+'\n'for name,body in sorted(top.items())).encode()
    package=output/('War-Journalist-'+version+'-Steam-LLL.zip')
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,body in top.items():archive.writestr(name,body)
    # Reconstruct from the archive and audit the actual extracted bytes.
    unpacked=output/'candidate'
    if unpacked.exists():shutil.rmtree(unpacked)
    with zipfile.ZipFile(package)as archive:
        assert archive.testzip() is None;archive.extractall(unpacked)
    for name,body in top.items():assert (unpacked/name).read_bytes()==body,name
    report=audit(unpacked/'dbf_freecam');assert report['passed'],report['errors']
    assert report['declared_modules']==21
    receipt={'package':str(package),'sha256':digest(package.read_bytes()),'module_audit':report,
             'game_data_sha256':{name:digest(body)for name,body in game.items()},
             'installed':False,'published':False}
    (output/'RELEASE-BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    version=(ROOT/'VERSION').read_text().strip()
    result=build(args.output or ROOT/'dist/releases'/(version+'-steam'))
    print(json.dumps({k:result[k]for k in ('package','sha256','game_data_sha256','installed','published')},indent=2))

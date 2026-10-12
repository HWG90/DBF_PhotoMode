"""Package the generated stable camera for MDL API 2. Never installs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile

ROOT=Path(__file__).resolve().parents[1]


def package(output):
    specification=importlib.util.spec_from_file_location('photo_build',ROOT/'freecam/build.py')
    build=importlib.util.module_from_spec(specification);specification.loader.exec_module(build)
    files=build.payload_files(output);version=(ROOT/'VERSION').read_text().strip()
    source=files['src/actioncam.lua'].decode()
    # MDL teardown cannot remove camera wrappers safely. Keep those wrappers
    # inert after owned cleanup, without calling another provider's shutdown.
    for signature in ('local function bindings_step()','local function step(dt)'):
        assert source.count(signature)==1,'Camera lifecycle source contract changed'
        source=source.replace(signature,signature+"\n  local owner=rawget(_G,'DBF_PHOTO_MODE_OWNER');if owner and owner.stopped then return end",1)
    source+="\nreturn {stop=function()local ok,why=DBF_FREECAM.close();if ok==false then return false,why end;drop_all('shutdown');return true end}\n"
    files['src/actioncam.lua']=source.encode()
    bootstrap=(ROOT/'freecam/mdl.lua').read_text().replace('__VERSION__',version).encode()
    files['mod.lua']=bootstrap
    files['INSTALL.txt']=(ROOT/'freecam/README.md').read_bytes()+b'\nMDL ALTERNATIVE - INSTALL BOTH INCLUDED PARTS\nRequires MDL API 2 (2.0.8 source contract). Copy dbf_freecam into %LOCALAPPDATA%/MDL/Helldivers2/Mods. Install the included GameData assets as described above, then enable War Journalist in MDL. All assets are included in this ZIP; no HUD, MCM or ActionCam download is required. Choose one Photo Mode package and restart normally. Screenshots are saved in dbf_freecam/Screenshots. MCM is optional.\n'
    files['manifest.json']=(json.dumps({'id':'dbf_freecam','name':'War Journalist','version':version,'author':'Goose','loader':'MDL','api':2,'restart_required':True},indent=2)+'\n').encode()
    for filename in ('README.md','KNOWN-ISSUES.md'):
        path=ROOT/filename if filename=='README.md' else ROOT/'docs'/filename
        if path.is_file():files[filename]=path.read_bytes()
    notes=ROOT/'docs'/('RELEASE-'+version+'.md')
    if notes.is_file():files['RELEASE-NOTES.md']=notes.read_bytes()
    for name,body in files.items():
        if name.endswith('.lua'):build.compile_lua(body,'WarJournalist-MDL-'+name)
    import sys;sys.path.insert(0,str(ROOT/'tools'));import photo_assets
    assets,gpu=photo_assets.archive_rows(photo_assets.load_resources())
    registry,registry_gpu=photo_assets.archive_rows([photo_assets.registry_resource()]);assert not registry_gpu
    audit=photo_assets.validate_archive(assets,gpu)
    files['ASSET-MANIFEST.json']=(json.dumps(audit,indent=2)+'\n').encode()
    package={'dbf_freecam/'+name:body for name,body in files.items()}
    for base,cpu,external in [('9ba626afa44a3aa3',assets,gpu),('ee6b1ba7e22d71ed',registry,b'')]:
        package['GameData/'+base+'.patch_0']=cpu;package['GameData/'+base+'.patch_0.gpu_resources']=external;package['GameData/'+base+'.patch_0.stream']=b''
    package['INSTALL.txt']=files['INSTALL.txt']
    package['FILES-SHA256.txt']=''.join(hashlib.sha256(body).hexdigest()+'  '+name+'\n'for name,body in sorted(package.items())).encode()
    target=output/('War-Journalist-'+version+'-MDL.zip')
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,body in sorted(package.items()):archive.writestr(name,body)
    with zipfile.ZipFile(target)as archive:assert archive.testzip()is None and len(archive.namelist())==len(set(archive.namelist()))
    (output/'MDL-BUILD-RECEIPT.json').write_text(json.dumps({'version':version,'artifact':target.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
        'asset_audit':audit,'validation':'All Lua payloads compiled; native asset closure, shader registrations, ZIP CRC and exact path uniqueness passed','loader':'MDL API 2','deployment':'not installed','live_validation':False},indent=2)+'\n')
    print(target);return target


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args();package(args.output)

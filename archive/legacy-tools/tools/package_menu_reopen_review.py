"""Build complete menu-reopen LLL/BSL reviews using the exact corrected assets."""
from pathlib import Path
import hashlib
import importlib.util
import json
import struct
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/releases/photo-menu-reopen-review'
LIVE=(Path.home() / 'AppData/Local/LLL/Helldivers2/Mods/dbf_freecam')
ASSET=ROOT/'dist/releases/photo-bokeh-color-corrected-review/War-Journalist-Fullres-Bokeh-Candidate-Assets.zip'
sha=lambda body:hashlib.sha256(body).hexdigest()
def write(path,body):path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)
def package(path,files):
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED)as archive:
  for name,body in sorted(files.items()):archive.writestr(name,body)
 with zipfile.ZipFile(path)as archive:
  assert archive.testzip()is None and len(archive.namelist())==len(files)==len(set(archive.namelist()))
  for name,body in files.items():assert archive.read(name)==body
def sums(files):return ''.join(sha(body)+'  '+name+'\n'for name,body in sorted(files.items())).encode()

def main():
 assert not OUT.exists(),'Preserve an existing review output'
 sys.path.insert(0,str(ROOT/'tools'));import photo_assets,lua_archive
 spec=importlib.util.spec_from_file_location('reopen_photo_build',ROOT/'freecam/build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
 validation=ROOT/'dist/validation/photo-menu-reopen-fixtures.json';checks=json.loads(validation.read_text());assert checks['passed']
 asset_body=ASSET.read_bytes();assert sha(asset_body)=='55dc61ebb6cb264aaae3138ebd047f174e12e398f1e2acb81867354758241aed'
 with zipfile.ZipFile(ASSET)as archive:
  assert archive.testzip()is None;assets={name:archive.read(name)for name in archive.namelist()}
 core=photo_assets.read_archive(assets['Assets/ee6b1ba7e22d71ed.patch_0'],assets['Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'])
 shared=photo_assets.read_archive(assets['Assets/9ba626afa44a3aa3.patch_0'],assets['Assets/9ba626afa44a3aa3.patch_0.gpu_resources'])
 assert len(core)==42 and len(shared)==41
 dof=next(row for row in core if row[0]==photo_assets.hash64('mods/dbf_photo/shaders/dof_local_depth_v1'))
 group=next(row for row in core if row[1]==photo_assets.GROUP);assert len(photo_assets.registry_ids(group[2]))==316
 foundation=(ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_bytes();identity=json.loads((ROOT/'freecam/vendor/PROVENANCE.json').read_text())
 assert sha(foundation)==identity['actioncam_source_sha256']
 generated=build.patch(foundation.decode(),dof_candidate=True).encode();build.compile_lua(generated,'menu-reopen-runtime')
 write(OUT/'ActionCam-Freecam.lua',generated)
 provenance={'review':True,'menu_reopen_fix':True,'runtime_sha256':sha(generated),'controller_sha256':sha((ROOT/'freecam/controller.lua').read_bytes()),
  'capture_library':build.capture_library_name(),'capture_sha256':identity['runtime_sha256'][build.capture_library_name()],
  'asset_zip_sha256':sha(asset_body),'shader_gpu_sha256':sha(dof[3]),'asset_registry_count':316,
  'reproduced':'Persisted hidden controls prevent visible P reopening; standalone enabled=false makes its settings inaccessible.',
  'behavior':'P reveals an active hidden session; fresh entry is visible without rewriting preferences. Disabled standalone P opens Controls without activating/pausing; shared MCM disable remains guarded.',
  'source_fixture_groups':len(checks['results']),'fixture_receipt_sha256':sha(validation.read_bytes()),
  'alt_tab_crash_fixed':False,'native_numeric_focus_verified':False,'full_resolution_blur_input_claimed':False,'live_reopen_verified':False,'deployment':'not installed'}
 write(OUT/'PROVENANCE.json',(json.dumps(provenance,indent=2)+'\n').encode())
 runtime=build.payload_files(OUT)
 prior=(LIVE/'src/standalone.lua').read_bytes()
 if runtime['src/standalone.lua'].replace(b'\r\n',b'\n')==prior.replace(b'\r\n',b'\n'):runtime['src/standalone.lua']=prior
 install=b'''WAR JOURNALIST - MENU REOPEN REVIEW
P reveals controls hidden by the mouse Hide button. Every new Photo session opens
visibly while preserving saved preferences. If standalone freecam is disabled,
P opens Controls without moving/pausing/enabling the camera. Click Enable freecam,
then P, to start normally. MCM users can keep deliberate disable and use MCM settings.
Mouse Exit releases input and Photo Mode; P can reopen afterward.
This review includes all 40 decorative overlays, the exact corrected bokeh assets,
Native/Shader selector and hash-named HDR-aware screenshot DLL. Shader blur uses the
native processed quarter-resolution source; focused full-resolution original pixels
are preserved. Native numeric focus and any unrelated alt-tab crash are not fixed
or claimed here. Reopening was verified in isolated real-menu fixtures; live check pending.
Choose one Photo Mode provider. MCM is optional. Preserve saved settings/screenshots.
A normal game restart is needed after replacing camera-hook packages; no hot reload.
'''
 manifest=json.loads((LIVE/'manifest.json').read_text());manifest['version']='0.6-menu-reopen-review'
 manifest['lll']['modules']=sorted(name for name in runtime if name.startswith('src/')and name.endswith('.lua'))
 runtime['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode();runtime['main.lua']=(LIVE/'main.lua').read_bytes()
 runtime['config/defaults.cfg']=b'{}\n';runtime['INSTALL.txt']=install;runtime['SOURCE-PROVENANCE.json']=runtime['PROVENANCE.json']
 for name,body in runtime.items():
  if name.endswith('.lua'):build.compile_lua(body,'reopen-'+name)
 runtime['FILES-SHA256.txt']=sums(runtime)
 mapping={}
 for name,body in runtime.items():
  path=LIVE/name;before=path.read_bytes()if path.is_file()else None
  mapping[name]={'source':'Runtime/dbf_freecam/'+name,'target':str(path),'before_sha256':sha(before)if before is not None else None,'after_sha256':sha(body),'changed':before!=body}
  write(OUT/'Runtime/dbf_freecam'/name,body)
 write(OUT/ASSET.name,asset_body)
 lll={'dbf_freecam/'+name:body for name,body in runtime.items()};lll['Arsenal/'+ASSET.name]=asset_body;lll['INSTALL.txt']=install
 lll['FILES-SHA256.txt']=sums(lll);lll_path=OUT/'War-Journalist-Menu-Reopen-LLL.zip';package(lll_path,lll)
 # Embed the same complete private services, including the correct active capture DLL.
 embedded=[]
 for name,body in sorted(runtime.items()):
  if name.endswith('.dll'):value='{hex='+build.lua_bytes(body.hex().encode())+'}'
  elif name.startswith('src/')or name=='standalone-library.txt':value=build.lua_bytes(body)
  else:continue
  embedded.append('['+build.lua_bytes(name.encode())+']='+value+',')
 startup=(ROOT/'freecam/bsl_startup.lua').read_text().replace('-- __EMBEDDED_FILES__','\n'.join(embedded)).replace('__VERSION__','0.6-menu-reopen-review').replace('__CAPTURE_LIBRARY__',build.capture_library_name()).encode()
 assert b'__CAPTURE_LIBRARY__'not in startup;build.compile_lua(startup,'menu-reopen-BSL-startup')
 entry='mods/dbf_photomode/startup';envelope=struct.pack('<II',len(startup),2)+startup
 shared_cpu,shared_gpu=photo_assets.archive_rows(shared+[(lua_archive.hash_name(entry),lua_archive.LUA_TYPE,envelope,b'')])
 actual=photo_assets.read_archive(shared_cpu,shared_gpu)
 assert next(row[2]for row in actual if row[1]==lua_archive.LUA_TYPE)==envelope
 assert sorted(row for row in actual if row[1]!=lua_archive.LUA_TYPE)==sorted(shared)
 bsl_manifest={'Version':1,'Guid':'0a1f063d-d880-4282-a5c3-89f9efc52b21','Name':'War Journalist - Menu Reopen Review',
  'Description':'Complete menu reopen review with private input/menu, PNG capture and current corrected assets. Requires Bingus Shared Loader v15+ / API1. MCM optional.',
  'Options':[{'Name':'War Journalist 0.6','Include':['Addon']}]}
 bsl={'manifest.json':(json.dumps(bsl_manifest,indent=2)+'\n').encode(),'INSTALL.txt':install,'PROVENANCE.json':runtime['PROVENANCE.json'],
  'VENDOR-PROVENANCE.json':runtime['VENDOR-PROVENANCE.json'],'LICENSE-Bingus.txt':runtime['LICENSE-Bingus.txt'],
  'Addon/9ba626afa44a3aa3.patch_0':shared_cpu,'Addon/9ba626afa44a3aa3.patch_0.gpu_resources':shared_gpu,'Addon/9ba626afa44a3aa3.patch_0.stream':b'',
  'Addon/ee6b1ba7e22d71ed.patch_0':assets['Assets/ee6b1ba7e22d71ed.patch_0'],
  'Addon/ee6b1ba7e22d71ed.patch_0.gpu_resources':assets['Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'],'Addon/ee6b1ba7e22d71ed.patch_0.stream':b''}
 for name,body in runtime.items():
  if name.startswith('assets/'):bsl[name]=body
 bsl['FILES-SHA256.txt']=sums(bsl);bsl_path=OUT/'War-Journalist-Menu-Reopen-BSL.zip';package(bsl_path,bsl)
 write(OUT/'War-Journalist-BSL-startup.lua',startup)
 write(OUT/'INSTALL-MAP.json',(json.dumps({'runtime_target':str(LIVE),'files':mapping,'shader_assets_unchanged':True,'saved_preferences_modified':False,'normal_restart_required':True},indent=2)+'\n').encode())
 receipt={'runtime_sha256':sha(generated),'shader_gpu_sha256':sha(dof[3]),'asset_zip_sha256':sha(asset_body),'source_fixture_groups_passed':len(checks['results']),
  'lll_zip':lll_path.name,'lll_sha256':sha(lll_path.read_bytes()),'bsl_zip':bsl_path.name,'bsl_sha256':sha(bsl_path.read_bytes()),
  'all_lua_compiled':True,'zip_crc_and_exact_entries':True,'bsl_asset_closure':{'core_resources':len(core),'shared_materials':len(shared),'startup_resources':1,'registry_ids':316},
  'capture_library':build.capture_library_name(),'installed':False,'live_reopen_verified':False,'normal_restart_required':True}
 write(OUT/'PACKAGE-RECEIPT.json',(json.dumps(receipt,indent=2)+'\n').encode());print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()

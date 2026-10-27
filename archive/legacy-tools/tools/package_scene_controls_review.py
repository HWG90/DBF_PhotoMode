"""Build complete menu-reopen LLL/BSL reviews using the exact corrected assets."""
from pathlib import Path
import hashlib
import importlib.util
import json
import struct
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/releases/photo-scene-controls-review'
LIVE=(Path.home() / 'AppData/Local/LLL/Helldivers2/Mods/dbf_freecam')
ASSET=ROOT/'dist/releases/photo-scene-depth-review/War-Journalist-Scene-Depth-Candidate-Assets.zip'
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
 validation=ROOT/'dist/validation/photo-scene-controls-fixtures.json';checks=json.loads(validation.read_text());assert checks['passed']
 asset_body=ASSET.read_bytes();assert sha(asset_body)=='be8b821b545a8146d8c340aa552a3c6dc02b70c39376d3e8bc9e054391ebc866'
 with zipfile.ZipFile(ASSET)as archive:
  assert archive.testzip()is None;assets={name:archive.read(name)for name in archive.namelist()}
 core=photo_assets.read_archive(assets['Assets/ee6b1ba7e22d71ed.patch_0'],assets['Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'])
 shared=photo_assets.read_archive(assets['Assets/9ba626afa44a3aa3.patch_0'],assets['Assets/9ba626afa44a3aa3.patch_0.gpu_resources'])
 assert len(core)==43 and len(shared)==42
 dof=next(row for row in core if row[0]==photo_assets.hash64('mods/dbf_photo/shaders/dof_local_depth_v1'))
 group=next(row for row in core if row[1]==photo_assets.GROUP);assert len(photo_assets.registry_ids(group[2]))==317
 foundation=(ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_bytes();identity=json.loads((ROOT/'freecam/vendor/PROVENANCE.json').read_text())
 assert sha(foundation)==identity['actioncam_source_sha256']
 generated=build.patch(foundation.decode(),dof_candidate=True,scene_candidate=True).encode();build.compile_lua(generated,'menu-reopen-runtime')
 write(OUT/'ActionCam-Freecam.lua',generated)
 provenance={'review':True,'menu_reopen_fix':True,'wasd_navigation':True,'scene_depth_color_candidate':True,'runtime_sha256':sha(generated),'controller_sha256':sha((ROOT/'freecam/controller.lua').read_bytes()),
  'capture_library':build.capture_library_name(),'capture_sha256':identity['runtime_sha256'][build.capture_library_name()],
  'asset_zip_sha256':sha(asset_body),'shader_gpu_sha256':sha(dof[3]),'asset_registry_count':317,
  'reproduced':'Keyboard adjustment required entering a hovered slider; scene color/depth effects were disabled.',
  'behavior':'W/S navigates rows; A/D adjusts selected values and cycles choices. Scene preview adds inversion, fog, depth and color controls. Existing menu recovery and blur commit are preserved.',
  'source_fixture_groups':len(checks['results']),'fixture_receipt_sha256':sha(validation.read_bytes()),
  'alt_tab_crash_fixed':False,'native_numeric_focus_verified':False,'full_resolution_blur_input_claimed':False,'live_reopen_verified':True,'deployment':'not installed'}
 write(OUT/'PROVENANCE.json',(json.dumps(provenance,indent=2)+'\n').encode())
 runtime=build.payload_files(OUT)
 prior=(LIVE/'src/standalone.lua').read_bytes()
 if runtime['src/standalone.lua'].replace(b'\r\n',b'\n')==prior.replace(b'\r\n',b'\n'):runtime['src/standalone.lua']=prior
 install=b'''WAR JOURNALIST - COMPLETE BSL SCENE/CONTROLS TEST
Import War-Journalist-Scene-Controls-BSL.zip in Arsenal and enable its included
War Journalist 0.6 option. This package includes runtime, private menu/input,
HDR-aware PNG capture DLL, 42 shader libraries, 42 materials and 317 registrations.
Bingus Shared Loader v15+ / API1 is required; MCM is optional.
Disable the LLL dbf_freecam addon, original ActionCam, and older Photo Mode BSL
packages before testing this BSL build. Disable the separate War Journalist DoF
asset candidate too: this BSL package now includes those assets completely.
Deploy with Arsenal and launch/restart the game normally. P opens Photo Mode.

W/S navigates rows. A/D adjusts the selected value without mouse hover, cycles
choices, or sets a toggle left OFF/right ON. Shift+A/D gives 0.001 m focus steps.
Valid typed values commit when leaving the field; Escape cancels. Mouse Exit then
P reopens the menu. Saved settings and screenshots are not packaged or overwritten.

For scene tests choose Native camera DoF or turn DoF OFF. Under Effects select
Negative, Monochrome, Posterize, Duotone, Solarize, Inverted depth, Thermal depth,
Depth contours or Depth fog. Color offers exposure, contrast and saturation.
Scene controls are gated while Shader DoF is ON because the passes do not yet
share color grading. Scene color currently uses a 960x540 display source and is a
preview; neutral controls preserve the original image. Scene visual tests pending.

Shader preview supports working focus/aperture, 32/64 samples and round/hex bokeh.
Its blur source is 960x540; focused original full-resolution pixels are preserved.
Native DoF toggle is live-confirmed. Manual native focus/aperture remain disabled
while their setter is investigated. No unrelated alt-tab crash fix is claimed.
'''
 manifest=json.loads((LIVE/'manifest.json').read_text());manifest['version']='0.6-scene-controls-review'
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
 lll['FILES-SHA256.txt']=sums(lll);lll_path=OUT/'War-Journalist-Scene-Controls-LLL.zip';package(lll_path,lll)
 # Embed the same complete private services, including the correct active capture DLL.
 embedded=[]
 for name,body in sorted(runtime.items()):
  if name.endswith('.dll'):value='{hex='+build.lua_bytes(body.hex().encode())+'}'
  elif name.startswith('src/')or name=='standalone-library.txt':value=build.lua_bytes(body)
  else:continue
  embedded.append('['+build.lua_bytes(name.encode())+']='+value+',')
 startup=(ROOT/'freecam/bsl_startup.lua').read_text().replace('-- __EMBEDDED_FILES__','\n'.join(embedded)).replace('__VERSION__','0.6-scene-controls-review').replace('__CAPTURE_LIBRARY__',build.capture_library_name()).encode()
 assert b'__CAPTURE_LIBRARY__'not in startup;build.compile_lua(startup,'menu-reopen-BSL-startup')
 entry='mods/dbf_photomode/startup';envelope=struct.pack('<II',len(startup),2)+startup
 shared_cpu,shared_gpu=photo_assets.archive_rows(shared+[(lua_archive.hash_name(entry),lua_archive.LUA_TYPE,envelope,b'')])
 actual=photo_assets.read_archive(shared_cpu,shared_gpu)
 assert next(row[2]for row in actual if row[1]==lua_archive.LUA_TYPE)==envelope
 assert sorted(row for row in actual if row[1]!=lua_archive.LUA_TYPE)==sorted(shared)
 bsl_manifest={'Version':1,'Guid':'0a1f063d-d880-4282-a5c3-89f9efc52b21','Name':'War Journalist - Scene and Controls Test',
  'Description':'Complete scene and WASD controls test with private input/menu, HDR-aware PNG capture and all shader assets. Requires Bingus Shared Loader v15+ / API1. MCM optional.',
  'Options':[{'Name':'War Journalist 0.6','Include':['Addon']}]}
 bsl={'manifest.json':(json.dumps(bsl_manifest,indent=2)+'\n').encode(),'INSTALL.txt':install,'PROVENANCE.json':runtime['PROVENANCE.json'],
  'VENDOR-PROVENANCE.json':runtime['VENDOR-PROVENANCE.json'],'LICENSE-Bingus.txt':runtime['LICENSE-Bingus.txt'],
  'Addon/9ba626afa44a3aa3.patch_0':shared_cpu,'Addon/9ba626afa44a3aa3.patch_0.gpu_resources':shared_gpu,'Addon/9ba626afa44a3aa3.patch_0.stream':b'',
  'Addon/ee6b1ba7e22d71ed.patch_0':assets['Assets/ee6b1ba7e22d71ed.patch_0'],
  'Addon/ee6b1ba7e22d71ed.patch_0.gpu_resources':assets['Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'],'Addon/ee6b1ba7e22d71ed.patch_0.stream':b''}
 for name,body in runtime.items():
  if name.startswith('assets/'):bsl[name]=body
 bsl['FILES-SHA256.txt']=sums(bsl);bsl_path=OUT/'War-Journalist-Scene-Controls-BSL.zip';package(bsl_path,bsl)
 write(OUT/'War-Journalist-BSL-startup.lua',startup)
 write(OUT/'INSTALL-MAP.json',(json.dumps({'runtime_target':str(LIVE),'files':mapping,'shader_assets_unchanged':True,'saved_preferences_modified':False,'normal_restart_required':True},indent=2)+'\n').encode())
 receipt={'runtime_sha256':sha(generated),'shader_gpu_sha256':sha(dof[3]),'asset_zip_sha256':sha(asset_body),'source_fixture_groups_passed':len(checks['results']),
  'lll_zip':lll_path.name,'lll_sha256':sha(lll_path.read_bytes()),'bsl_zip':bsl_path.name,'bsl_sha256':sha(bsl_path.read_bytes()),
  'all_lua_compiled':True,'zip_crc_and_exact_entries':True,'bsl_asset_closure':{'core_resources':len(core),'shared_materials':len(shared),'startup_resources':1,'registry_ids':317},
  'capture_library':build.capture_library_name(),'installed':False,'live_reopen_verified':True,'normal_restart_required':True}
 write(OUT/'PACKAGE-RECEIPT.json',(json.dumps(receipt,indent=2)+'\n').encode());print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()

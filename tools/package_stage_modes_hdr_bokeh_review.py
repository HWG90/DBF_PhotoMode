"""Package/stage the authorized combined test, without reloads or config writes."""
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/releases/photo-modes-hdr-bokeh-review'
LIVE=Path('C:/Users/david/AppData/Local/LLL/Helldivers2/Mods/dbf_freecam')
ARSENAL=Path('C:/Users/david/AppData/Local/hd2arsenal/mods/War-Journalist-DoF-Assets-Candidate_AR595142')
GAME=Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data')
ASSET=ROOT/'dist/releases/photo-dof-bokeh-fullres-review/War-Journalist-Fullres-Bokeh-Candidate-Assets.zip'
sha=lambda body:hashlib.sha256(body).hexdigest()

def write(path,body):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)

def zipped(path,expected=None):
 body=path.read_bytes()
 if expected:assert sha(body)==expected,'ZIP identity changed'
 with zipfile.ZipFile(path)as archive:
  assert archive.testzip()is None and len(archive.namelist())==len(set(archive.namelist()))
  result={name:archive.read(name)for name in archive.namelist()}
  for name in result:
   p=PurePosixPath(name);assert not p.is_absolute()and'..'not in p.parts and'\\'not in name
 return result

def atomic(path,body):
 temporary=path.with_name('.'+path.name+'.combined-'+uuid.uuid4().hex+'.tmp')
 try:
  with temporary.open('xb')as stream:stream.write(body);stream.flush();os.fsync(stream.fileno())
  assert temporary.read_bytes()==body;os.replace(temporary,path)
 finally:
  if temporary.exists():temporary.unlink()

def main():
 assert not OUT.exists(),'Preserve the named combined review output'
 validation=ROOT/'dist/validation/photo-modes-hdr-bokeh-review.json'
 checks=json.loads(validation.read_text());assert checks['passed']
 sys.path.insert(0,str(ROOT/'tools'))
 spec=importlib.util.spec_from_file_location('combined_photo_build',ROOT/'freecam/build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
 vendor=json.loads((ROOT/'freecam/vendor/PROVENANCE.json').read_text())
 source=(ROOT/'freecam/vendor/actioncam-2.3.1.lua').read_bytes();assert sha(source)==vendor['actioncam_source_sha256']
 generated=build.patch(source.decode(),dof_candidate=True).encode();build.compile_lua(generated,'combined-modes-HDR-bokeh-runtime')
 before_runtime=(LIVE/'src/actioncam.lua').read_bytes();assert sha(before_runtime)=='fdc755143ef35a2772afa3c7ef794287494e32de1582fc15c836e480169a96db'
 assets=zipped(ASSET,'79c04bae59eec4b5ef25618be82b3610085b82d253535c685f1a15d56e424081')
 asset_manifest=json.loads(assets['manifest.json']);existing_manifest=json.loads((ARSENAL/'manifest.json').read_text())
 for manifest in(asset_manifest,existing_manifest):
  assert manifest['Guid']=='fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
  assert manifest['Options']==[{'Name':'DoF shader assets and registry','Include':['Assets']}]
 write(OUT/'ActionCam-Freecam.lua',generated)
 names=('controller.lua','photo_options.lua','photo_menu.lua','photo_runtime.lua','dof_overlay.lua','depth_resource.lua','shader_template_guard.lua','camera_profile.lua','render_profile.lua','postfx.lua','screenshot.lua','screenshot_backend.lua')
 provenance={'candidate':True,'completed_fix':False,'native_focus_live_verified':False,'fullres_bokeh_live_verified':False,
  'source_head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'source_modules_sha256':{name:sha((ROOT/'freecam'/name).read_bytes())for name in names},
  'runtime_before_sha256':sha(before_runtime),'runtime_after_sha256':sha(generated),
  'capture_library':build.capture_library_name(),'capture_sha256':vendor['runtime_sha256'][build.capture_library_name()],
  'bokeh_shader_gpu_sha256':'d216f43dc866c4bff368853c337e4e0bda886c63784962315eb1c999376dffbc',
  'dof_candidate_preview':True,'ordinary_source_custom_dof_default':False,'native_mode_default':1,
  'validation_receipt_sha256':sha(validation.read_bytes()),'precision_blur_commit_included':True,
  'deployment':'not installed','normal_restart_required':True}
 write(OUT/'PROVENANCE.json',(json.dumps(provenance,indent=2)+'\n').encode())
 runtime=build.payload_files(OUT)
 prior_standalone=(LIVE/'src/standalone.lua').read_bytes()
 if runtime['src/standalone.lua'].replace(b'\r\n',b'\n')==prior_standalone.replace(b'\r\n',b'\n'):runtime['src/standalone.lua']=prior_standalone
 runtime['main.lua']=(LIVE/'main.lua').read_bytes();runtime['config/defaults.cfg']=b'{}\n'
 manifest=json.loads((LIVE/'manifest.json').read_text());manifest['version']='0.6-modes-hdr-bokeh-review'
 manifest['lll']['modules']=sorted(name for name in runtime if name.startswith('src/')and name.endswith('.lua'))
 assert manifest['lll']['restart_only']and manifest['lll']['retain_until_exit']
 runtime['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
 runtime['SOURCE-PROVENANCE.json']=runtime['PROVENANCE.json']
 runtime['INSTALL.txt']=b'''WAR JOURNALIST - NATIVE/SHADER, HDR SCREENSHOT AND BOKEH TEST
Copy the included dbf_freecam package to the existing LLL Mods folder. Import the
included Arsenal asset ZIP using its unchanged GUID and selected option; restart
the game normally after deployment. Preserve saved settings and screenshots.
Native camera mode is the default and remains under test; native numeric focus
is not claimed. To test bokeh, enable DoF and select Shader (preview), then choose
Standard/Smoother quality and Round/Hexagonal shape. Full-resolution color binding,
GUI color stage, edges, bokeh quality and performance require live capture proof.
Focus supports 0.01 m steps and Shift+A/D 0.001 m adjustments inside the editor.
Valid typed numeric values commit on leaving the field; Escape cancels.
PNG export uses the new hash-named color-aware capture DLL; the old loaded DLL
is retained. The new code/assets load after one normal restart. MCM is optional.
This review is not a completed high-quality/native numeric DoF fix.
'''
 for name,body in runtime.items():
  if name.endswith('.lua'):build.compile_lua(body,'combined-'+name)
 runtime['FILES-SHA256.txt']=''.join(sha(body)+'  '+name+'\n'for name,body in sorted(runtime.items())).encode()
 for name,body in runtime.items():write(OUT/'Runtime/dbf_freecam'/name,body)
 write(OUT/ASSET.name,ASSET.read_bytes())
 for name,body in assets.items():write(OUT/'Asset-Package'/name,body)
 package={'dbf_freecam/'+name:body for name,body in runtime.items()}
 package['Arsenal/'+ASSET.name]=ASSET.read_bytes();package['INSTALL.txt']=runtime['INSTALL.txt']
 package['SOURCE-PROVENANCE.json']=runtime['SOURCE-PROVENANCE.json']
 package['FILES-SHA256.txt']=''.join(sha(body)+'  '+name+'\n'for name,body in sorted(package.items())).encode()
 artifact=OUT/'War-Journalist-Modes-HDR-Bokeh-LLL-Review.zip'
 with zipfile.ZipFile(artifact,'w',zipfile.ZIP_DEFLATED)as archive:
  for name,body in sorted(package.items()):archive.writestr(name,body)
 assert zipped(artifact)==package
 # Freeze and guard the known successful composition asset prehashes.
 baseline=zipped(ROOT/'dist/releases/photo-dof-runtime-review/War-Journalist-DoF-Assets-Self-Contained-Core-Order-Review.zip',
  'ae688bb81171aee538934490252c39f0e4efb732c6e67908224fbdfe1cd21d59')
 changes=[];protected=[]
 def add(area,name,target,body,expected=None,require_existing=False):
  target=target.resolve();folder={'runtime':LIVE,'arsenal':ARSENAL,'game':GAME}[area].resolve()
  assert target.is_relative_to(folder)and target!=folder
  previous=target.read_bytes()if target.is_file()else None
  if require_existing:assert previous is not None
  if expected is not None:assert previous==expected,'Asset prehash/mapping changed: '+str(target)
  record={'area':area,'name':name,'target':str(target),'before_sha256':sha(previous)if previous is not None else None,'after_sha256':sha(body),'before':previous,'after':body}
  if previous!=body:changes.append(record)
  else:protected.append((target,sha(body)))
 precision_map=json.loads((ROOT/'dist/releases/photo-focus-precision-review/INSTALL-MAP.json').read_text())
 for name,item in precision_map['all_runtime_files'].items():
  target=(LIVE/name).resolve();assert target.is_file()and sha(target.read_bytes())==item['after_sha256'],'Staged precision runtime drift: '+name
 for name,body in runtime.items():add('runtime',name,LIVE/name,body)
 # Existing loaded DLL stays present; only the new hash-name is added.
 for path in LIVE.glob('*.dll'):
  if path.name not in runtime:protected.append((path,sha(path.read_bytes())))
 for base,game_name in [('ee6b1ba7e22d71ed.patch_0','ee6b1ba7e22d71ed.patch_1'),('9ba626afa44a3aa3.patch_0','9ba626afa44a3aa3.patch_62')]:
  for suffix in('','.gpu_resources','.stream'):
   name='Assets/'+base+suffix;expected=baseline[name];body=assets[name]
   add('arsenal',name,ARSENAL/name,body,expected,True);add('game',game_name+suffix,GAME/(game_name+suffix),body,expected,True)
 for name,body in assets.items():
  if not name.startswith('Assets/'):add('arsenal',name,ARSENAL/name,body)
 stamp=datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S');backup=ROOT/'dist/deployment-backups'/('photo-modes-hdr-bokeh-'+stamp);backup.mkdir(parents=True)
 records=[]
 for item in changes:
  path=backup/'before'/item['area']/item['name']
  if item['before']is not None:write(path,item['before']);assert path.read_bytes()==item['before']
  records.append({key:value for key,value in item.items()if key not in('before','after')})
 receipt={'status':'prepared','artifact':str(artifact),'artifact_sha256':sha(artifact.read_bytes()),'asset_zip_sha256':sha(ASSET.read_bytes()),
  'runtime_sha256':sha(generated),'capture_library':build.capture_library_name(),'capture_sha256':provenance['capture_sha256'],
  'shader_gpu_sha256':provenance['bokeh_shader_gpu_sha256'],'asset_guid':asset_manifest['Guid'],'asset_option':asset_manifest['Options'][0]['Name'],
  'files':records,'skipped_identical_files':len(protected),'atomic_writes':True,'rollback_on_failure':True,
  'zip_crc_and_exact_entries':True,'source_validation_receipt':str(validation),'preferences_modified':False,'arsenal_config_modified':False,
  'game_restarted':False,'reload_requested':False,'live_adoption_verified':False,'normal_restart_required':True}
 receipt_path=backup/'INSTALL-RECEIPT.json';receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
 applied=[]
 try:
  for item in changes:
   p=Path(item['target']);assert (p.read_bytes()if p.is_file()else None)==item['before'],'Target changed after preparation'
  for item in changes:
   applied.append(item);atomic(Path(item['target']),item['after']);assert Path(item['target']).read_bytes()==item['after']
  for path,digest in protected:assert sha(path.read_bytes())==digest,'Protected file changed: '+str(path)
 except Exception as error:
  failures=[]
  for item in reversed(applied):
   try:
    p=Path(item['target'])
    if item['before']is None:p.unlink(missing_ok=True)
    else:atomic(p,item['before'])
    assert (p.read_bytes()if p.is_file()else None)==item['before']
   except Exception as rollback_error:failures.append({'target':item['target'],'error':str(rollback_error)})
  receipt.update(status='rolled back'if not failures else'rollback needs attention',error=str(error),rollback_failures=failures)
  receipt_path.write_text(json.dumps(receipt,indent=2)+'\n');raise
 receipt.update(status='installed on disk; ready for one normal restart',installed_bytes_verified=True,verified_changed_files=len(changes))
 receipt_path.write_text(json.dumps(receipt,indent=2)+'\n');write(OUT/'INSTALL-RECEIPT.json',receipt_path.read_bytes())
 print(json.dumps({key:receipt[key]for key in('status','artifact_sha256','runtime_sha256','capture_library','capture_sha256','shader_gpu_sha256','verified_changed_files','skipped_identical_files','asset_guid','arsenal_config_modified','game_restarted','reload_requested')},indent=2))
 print('BACKUP',backup)

if __name__=='__main__':main()

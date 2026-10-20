"""Separate shared-archive asset loading from the winning shader registry."""
from pathlib import Path
import hashlib,json,struct,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'DBF-HUD/tools'))
from build_scene_depth_probe import archive_rows
from build_depth_state_test import hash64
review=ROOT/'dist/releases/photo-dof-local-depth-review'
source=review/'ee6b1ba7e22d71ed.patch_2';cpu=source.read_bytes();gpu=Path(str(source)+'.gpu_resources').read_bytes()
t,n=struct.unpack_from('<II',cpu,4);rows=list(struct.iter_unpack('<7Q6I',cpu[72+t*32:72+t*32+n*80]));assert n==3
assets=[];registry=[]
for row in rows:
 resource=(row[0],row[1],cpu[row[2]:row[2]+row[7]],gpu[row[4]:row[4]+row[9]]if row[9]else b'')
 (registry if row[1]==hash64('shader_library_group')else assets).append(resource)
assert len(assets)==2 and len(registry)==1
out=review/'split-archive-candidate';out.mkdir(exist_ok=True)
files={}
for name,resources in (('9ba626afa44a3aa3.patch_85',assets),('ee6b1ba7e22d71ed.patch_2',registry)):
 body,external=archive_rows(resources)
 types,count=struct.unpack_from('<II',body,4);table=list(struct.iter_unpack('<7Q6I',body[72+types*32:72+types*32+count*80]))
 for wanted,kind,data,ext in resources:
  row=next(r for r in table if r[:2]==(wanted,kind));assert body[row[2]:row[2]+row[7]]==data
  if ext:assert external[row[4]:row[4]+row[9]]==ext
 for suffix,contents in (('',body),('.gpu_resources',external),('.stream',b'')):
  target=out/(name+suffix);target.write_bytes(contents);files[target.name]={'sha256':hashlib.sha256(contents).hexdigest(),'bytes':len(contents)}
receipt={'installed':False,'live_verified':False,'assets_archive':'9ba626afa44a3aa3.patch_85','registry_archive':'ee6b1ba7e22d71ed.patch_2','asset_payloads_identical_to_review_candidate':True,'registry_payload_identical':True,'files':files}
(out/'PACKAGE-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))

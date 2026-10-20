"""Create a deployable Arsenal asset package for the LLL Photo Mode candidate."""
from pathlib import Path
import hashlib,json,struct,sys,zipfile
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'DBF-HUD/tools'))
from build_scene_depth_probe import archive_rows
from build_depth_state_test import hash64
OUT=ROOT/'dist/releases/photo-dof-local-depth-review'
split=OUT/'split-archive-candidate'
base=Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data/ee6b1ba7e22d71ed.patch_0')
body=base.read_bytes();t,n=struct.unpack_from('<II',body,4)
rows=list(struct.iter_unpack('<7Q6I',body[72+t*32:72+t*32+n*80]))
group_name='core/stingray_renderer/shader_libraries/default_shaders'
row=next(r for r in rows if r[:2]==(hash64(group_name),hash64('shader_library_group')))
original=body[row[2]:row[2]+row[7]];number=struct.unpack_from('<I',original,16)[0]
assert number==315 and len(original)==24+number*8
shader='mods/dbf_photo/shaders/dof_local_depth_v1'
ids=list(struct.unpack_from('<315Q',original,24));assert hash64(shader)not in ids
ids.append(hash64(shader));group=bytearray(original[:24]);struct.pack_into('<I',group,16,316);group+=struct.pack('<316Q',*ids)
registry,external=archive_rows([(hash64(group_name),hash64('shader_library_group'),bytes(group),b'')]);assert not external
manifest={'Version':1,'Guid':'fd8637c5-b38f-488a-91e5-b3ba5f27a7df','Name':'War Journalist DoF Assets - Candidate 1',
'Description':'Shader assets for the LLL Photo Mode development candidate. This package supplies assets only; focus/aperture integration and visual verification remain in progress.',
'Options':[{'Name':'DoF shader assets and registry','Include':['Assets']}]}
files={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),
'Assets/ee6b1ba7e22d71ed.patch_0':registry,'Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources':b'','Assets/ee6b1ba7e22d71ed.patch_0.stream':b''}
for suffix in ('','.gpu_resources','.stream'):
 files['Assets/9ba626afa44a3aa3.patch_0'+suffix]=(split/('9ba626afa44a3aa3.patch_85'+suffix)).read_bytes()
files['INSTALL.txt']=b'''WAR JOURNALIST DOF ASSETS - DEVELOPMENT CANDIDATE

Import this ZIP into HD2 Arsenal. Enable its DoF shader assets option and deploy.
This is the asset package; the Photo Mode Lua addon continues to run through LLL.
Keep the existing War Journalist LLL addon enabled. Do not enable original ActionCam.
A normal game restart is required after asset deployment.

STATUS
The running game reports the native-binding shader and material available from
the equivalent directly installed asset payload. This ZIP preserves those exact
shader/material bytes and registers only the original 315 shaders plus this one.
The existing stable LLL runtime still disables focus/aperture. Runtime integration
and visual verification are incomplete. This ZIP is not a completed DoF fix.

The package contains no saved settings, screenshots, logs, game executables, or
unrelated HUD artwork. Disable this asset package and redeploy to remove it.
'''
files['CANDIDATE-STATUS.json']=(json.dumps({'candidate':True,'completed_fix':False,'shader_group_count':316,
'shader_and_material_payload_identity':'Identical to directly installed shared-archive candidate',
'availability_api_verified':True,'visual_verified':False,'focus_aperture_runtime_integrated':False},indent=2)+'\n').encode()
files['FILES-SHA256.txt']=''.join(hashlib.sha256(value).hexdigest()+'  '+name+'\n'for name,value in sorted(files.items())).encode()
target=OUT/'War-Journalist-DoF-Assets-Candidate-1.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED)as z:
 for name,value in sorted(files.items()):z.writestr(name,value)
with zipfile.ZipFile(target)as z:
 assert z.testzip()is None and len(z.namelist())==len(files)
 for name,value in files.items():assert z.read(name)==value
print(target);print('SHA256',hashlib.sha256(target.read_bytes()).hexdigest());print('ZIP CRC and exact entry bytes passed')

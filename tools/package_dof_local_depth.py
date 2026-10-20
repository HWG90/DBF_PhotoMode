"""Package the native-ABI DoF candidate as a small additive archive patch."""
from pathlib import Path
import hashlib,json,struct,sys
ROOT=Path(__file__).resolve().parents[1];HUD=ROOT.parent/'DBF-HUD'
sys.path.insert(0,str(HUD/'tools'))
from build_depth_state_test import hash64
from build_scene_depth_probe import archive_rows
OUT=ROOT/'dist/releases/photo-dof-local-depth-review'
shader='mods/dbf_photo/shaders/dof_local_depth_v1'
material='mods/dbf_photo/materials/dof_local_depth_v1'
group_name='core/stingray_renderer/shader_libraries/default_shaders'
base=Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data/ee6b1ba7e22d71ed.patch_1')
body=base.read_bytes();types,count=struct.unpack_from('<II',body,4)
rows=list(struct.iter_unpack('<7Q6I',body[72+types*32:72+types*32+count*80]))
row=next(r for r in rows if r[:2]==(hash64(group_name),hash64('shader_library_group')))
original=body[row[2]:row[2]+row[7]];number=struct.unpack_from('<I',original,16)[0]
assert number==318 and len(original)==24+number*8
ids=list(struct.unpack_from('<'+str(number)+'Q',original,24));assert hash64(shader)not in ids
ids.append(hash64(shader));group=bytearray(original[:24]);struct.pack_into('<I',group,16,len(ids));group+=struct.pack('<'+str(len(ids))+'Q',*ids)
mat=bytearray((HUD/'assets/depth-state-test/source.bin').read_bytes());assert len(mat)==144
struct.pack_into('<I',mat,128,hash64(shader)>>32)
resources=[(hash64(shader),hash64('shader_library'),struct.pack('<I',4),(OUT/'dof_local_depth.gpu').read_bytes()),
(hash64(material),hash64('material'),bytes(mat),b''),
(hash64(group_name),hash64('shader_library_group'),bytes(group),b'')]
cpu,gpu=archive_rows(resources)
stem=OUT/'ee6b1ba7e22d71ed.patch_2';stem.write_bytes(cpu);Path(str(stem)+'.gpu_resources').write_bytes(gpu);Path(str(stem)+'.stream').write_bytes(b'')
t,n=struct.unpack_from('<II',cpu,4);actual=list(struct.iter_unpack('<7Q6I',cpu[72+t*32:72+t*32+n*80]));assert n==3
for name,kind,data,external in resources:
 r=next(r for r in actual if r[:2]==(name,kind))
 assert cpu[r[2]:r[2]+r[7]]==data
 if external:assert gpu[r[4]:r[4]+r[9]]==external
assert group[24:24+318*8]==original[24:]
receipt={'candidate':True,'installed':False,'shader':shader,'material':material,'shader_group_count':319,'previous_318_ids_preserved':True,
'archive_cpu_bytes':len(cpu),'archive_gpu_bytes':len(gpu),'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in (stem,Path(str(stem)+'.gpu_resources'),Path(str(stem)+'.stream'))},
'validation':'Three exact resource roundtrips; prior group entries unchanged; native ABI checks in BUILD-RECEIPT.json',
'required_next_check':'Read-only availability after normal restart; never request an unavailable material','live_verified':False}
(OUT/'PACKAGE-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))

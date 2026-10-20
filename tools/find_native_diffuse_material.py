"""Locate the native diffuse GUI material in installed archive tables, read-only."""
from pathlib import Path
import json,struct,sys
ROOT=Path(__file__).resolve().parents[1]
HUD=ROOT.parent/'DBF-HUD'
sys.path.insert(0,str(HUD/'tools'))
from build_depth_state_test import hash64
variant=struct.unpack_from('<I',(HUD/'assets/scene-depth-probe/source-diffuse-blur.gpu').read_bytes(),0xe0)[0]
data=Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data')
matches=[];checked=0
for path in data.iterdir():
 if not path.is_file()or path.suffix in ('.stream','.gpu_resources'):continue
 with path.open('rb') as f:
  header=f.read(72)
  if len(header)!=72 or struct.unpack_from('<I',header)[0]!=0xf0000011:continue
  types,count=struct.unpack_from('<II',header,4)
  if not(0<types<=128 and 0<count<=1000000):continue
  f.seek(72+types*32);table=f.read(count*80)
  if len(table)!=count*80:continue
  checked+=1
  for row in struct.iter_unpack('<7Q6I',table):
   if row[1]!=hash64('material')or not 132<=row[7]<=65536:continue
   f.seek(row[2]);body=f.read(row[7])
   if len(body)!=row[7]:continue
   offsets=[i for i in range(0,len(body)-3,4)if struct.unpack_from('<I',body,i)[0]==variant]
   if offsets:
    matches.append({'archive':str(path),'name_hash':hex(row[0]),'cpu_offset':row[2],'bytes':row[7],'variant_offsets':offsets})
report={'native_shader_variant':hex(variant),'archives_checked':checked,'matches':matches,'read_only':True}
out=ROOT/'dist/dof-investigation-20261011/NATIVE-DIFFUSE-MATERIAL-ARCHIVE-MATCHES.json'
out.write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))

"""Build a separate full-resolution bokeh candidate; no live writes or imports from HUD."""
from pathlib import Path
import ctypes
import hashlib
import json
import struct
import zipfile
import argparse
import photo_assets

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'freecam/assets/shaders'
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,default=ROOT/'dist/releases/photo-dof-bokeh-fullres-review')
OUT=parser.parse_args().output.resolve()
sha=lambda body:hashlib.sha256(body).hexdigest()
source=(FOLDER/'dof_bokeh_fullres_candidate.hlsl').read_bytes()
original=(FOLDER/'dof_library_template.gpu').read_bytes()
assert len(original)==16592 and sha(original)=='6729d404ca524fc4dd20a986fdab5bd65f54b9fca126fccda96b4c42afb492b7'
assert not OUT.exists(),'Preserve an existing named candidate output'
dll=ctypes.WinDLL('d3dcompiler_47.dll')

def blob(pointer):
 table=ctypes.cast(pointer,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
 address=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(table[3])(pointer)
 size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(table[4])(pointer)
 body=ctypes.string_at(address,size)
 ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(table[2])(pointer)
 return body

compile_code=dll.D3DCompile
compile_code.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_void_p)]
compile_code.restype=ctypes.c_long
buffer=ctypes.create_string_buffer(source);compiled,error=ctypes.c_void_p(),ctypes.c_void_p()
result=compile_code(buffer,len(source),b'dof_bokeh_fullres_candidate.hlsl',None,None,b'photo_dof',b'ps_5_0',1<<15,0,ctypes.byref(compiled),ctypes.byref(error))
message=blob(error).decode(errors='replace')if error else ''
assert result>=0,message
code=blob(compiled);assert len(code)<7152,'Bokeh pixel shader exceeds proven native window'
disassemble=dll.D3DDisassemble
disassemble.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];disassemble.restype=ctypes.c_long
def listing(body):
 data=ctypes.create_string_buffer(body);output=ctypes.c_void_p()
 assert disassemble(data,len(body),0,None,ctypes.byref(output))>=0
 return blob(output).decode(errors='replace')
assembly=listing(code)
assert all(name in assembly for name in ['__tex_diffuse_map','__tex_hdr0','CB0[49]','CB2[4]'])
set_part=dll.D3DSetBlobPart
set_part.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_uint,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];set_part.restype=ctypes.c_long
def with_private(size):
 data=ctypes.create_string_buffer(code);private=ctypes.create_string_buffer(size);output=ctypes.c_void_p()
 assert set_part(data,len(code),10,0,private,size,ctypes.byref(output))>=0
 return blob(output)
first=with_private(4);padded=with_private(7152-len(first)+4)
assert len(padded)==7152 and struct.unpack_from('<I',padded,24)[0]==7152
listing(padded)
body=bytearray(original);body[0x2468:0x2468+7152]=padded
old=new=photo_assets.hash64('hdr0_div4_fullres')>>32
offsets=(0x5f8,0xf38,0x40a0,0x40bc)
assert [at for at in range(0,len(original)-3,4)if struct.unpack_from('<I',original,at)[0]==old]==list(offsets)
for at in offsets:assert struct.unpack_from('<I',original,at)[0]==old;struct.pack_into('<I',body,at,new)
allowed=set(range(0x2468,0x2468+7152))
for at in offsets:allowed.update(range(at,at+4))
assert all(at in allowed for at,(a,b)in enumerate(zip(original,body))if a!=b)
assert body[0xff0:0xff0+5160]==original[0xff0:0xff0+5160]
assert body[0xf30:0xf38]==original[0xf30:0xf38]and body[0xf3c:0xf48]==original[0xf3c:0xf48]
assert body[0x40a4:0x40b0]==original[0x40a4:0x40b0]and body[0x40c0:]==original[0x40c0:]
OUT.mkdir(parents=True)
(OUT/'dof_local_depth.gpu').write_bytes(body);(OUT/'dof_bokeh_fullres_candidate.hlsl').write_bytes(source);(OUT/'dof_bokeh_fullres_candidate.asm.txt').write_text(assembly)
shader='mods/dbf_photo/shaders/dof_local_depth_v1';material='mods/dbf_photo/materials/dof_local_depth_v1'
inputs=json.loads((FOLDER/'dof-source-inputs.json').read_text())
for name,identity in inputs['files'].items():assert sha((FOLDER/name).read_bytes())==identity['sha256']
base=(FOLDER/'dof_registry_base.bin').read_bytes();ids=list(photo_assets.registry_ids(base));assert len(ids)==315
assert photo_assets.hash64(shader)not in ids;ids.append(photo_assets.hash64(shader));group=bytearray(base[:24]);struct.pack_into('<I',group,16,316);group+=struct.pack('<316Q',*ids)
owned=photo_assets.load_resources();libraries=[r for r in owned if r[1]==photo_assets.SHADER];materials=[r for r in owned if r[1]==photo_assets.MATERIAL]
assert len(libraries)==len(materials)==40 and all(r[0]in ids for r in libraries)
core=libraries+[(photo_assets.hash64(shader),photo_assets.SHADER,struct.pack('<I',4),bytes(body)),(photo_assets.hash64(photo_assets.GROUP_NAME),photo_assets.GROUP,bytes(group),b'')]
shared=materials+[(photo_assets.hash64(material),photo_assets.MATERIAL,(FOLDER/'dof_local_depth.material.bin').read_bytes(),b'')]
receipt={'candidate':True,'completed_dof_fix':False,'high_quality_live_verified':False,'shader':shader,'shader_gpu_sha256':sha(body),'hlsl_sha256':sha(source),
 'pixel_bytes':len(code),'pixel_window_bytes':7152,'native_vertex_byte_identity':True,'binding_category_and_slots_preserved':True,
 'global_color_name':'hdr0','global_color_hash':hex(new),'four_name_hash_offsets':[hex(x)for x in offsets],
 'depth_binding':'Existing local diffuse_map, t0/s0, still supplied verified scene linear_depth',
 'color_binding':'Existing GUI global category4 t1/s1; four quarter-resolution name hashes replaced by proven existing hdr0 name',
 'positive_control':'Native core library0x91cfcd06c82956f7 reads hdr0 as float4 Texture2D t4; exact metadata differs from GUI category4',
 'asset_counts':{'core_libraries':41,'core_registry':1,'shared_materials':41,'registry_ids':316},
 'quality':{'taps':[32,64],'default_taps':32,'quality_uniform':'atlas_scissor.w=0 for32,1 for64','aperture_uniform':'atlas_scissor.z=0 circle,6 hexagon (3-9 blades)',
  'highlight_uniform':'Existing desaturate scalar: positive0-4 sets highlight weight,0 uses default.5','sampling':'Deterministic best-candidate Poisson disk; signed CoC/depth gates reject crossing foreground/background; no early RGB clamp'},
 'residual_checks':['Actual GUI category4 hdr0 binding and normal registration','Native GUI draw target must differ from hdr0 sampled target','HDR0 pass/color encoding at GUI composition; candidate outputs untonemapped linear HDR without guessing a transform','Sharp focus, background blur, edges, highlight aperture shape and32/64 noise/performance in game'],
 'replaces_same_library_only_in_new_package':True,'old_preview_inputs_preserved':True,'installed':False,'live_verified':False}
manifest={'Version':1,'Guid':'fd8637c5-b38f-488a-91e5-b3ba5f27a7df','Name':'War Journalist Full-Resolution Bokeh - Candidate',
 'Description':'Explicit candidate replacing only the old preview library/color binding. Native DoF remains available separately. Full-resolution binding, color stage and image quality require in-game verification.',
 'Options':[{'Name':'DoF shader assets and registry','Include':['Assets']}]}
files={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'CANDIDATE-RECEIPT.json':(json.dumps(receipt,indent=2)+'\n').encode(),
 'INSTALL.txt':b'''WAR JOURNALIST FULL-RESOLUTION BOKEH CANDIDATE
This package is for the explicitly selected shader mode. Native DoF remains separate.
It replaces the same existing preview material/library IDs in this NEW package only.
Preserve the previous asset ZIP for rollback; do not enable both packages together.
The existing Arsenal GUID and DoF shader assets option are preserved.
A normal restart is required after deployment. No deployment is performed by this build.
This is not a completed high-quality DoF fix. Full-resolution binding, GUI color stage,
sharp focus, edge behavior, aperture-shaped highlights and performance await live proof.
'''}
for name,rows in [('ee6b1ba7e22d71ed.patch_0',core),('9ba626afa44a3aa3.patch_0',shared)]:
 cpu,gpu=photo_assets.archive_rows(rows);assert sorted(photo_assets.read_archive(cpu,gpu))==sorted(rows)
 for suffix,data in [('',cpu),('.gpu_resources',gpu),('.stream',b'')]:files['Assets/'+name+suffix]=data
files['FILES-SHA256.txt']=''.join(sha(data)+'  '+name+'\n'for name,data in sorted(files.items())).encode()
target=OUT/'War-Journalist-Fullres-Bokeh-Candidate-Assets.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED)as zipped:
 for name,data in sorted(files.items()):zipped.writestr(name,data)
with zipfile.ZipFile(target)as zipped:
 assert zipped.testzip()is None and len(zipped.namelist())==len(files)==len(set(zipped.namelist()))
 for name,data in files.items():assert zipped.read(name)==data
receipt['zip']=target.name;receipt['zip_sha256']=sha(target.read_bytes());receipt['zip_crc_and_exact_entries']=True
receipt['archive_files']={name:{'sha256':sha(data),'bytes':len(data)}for name,data in files.items()if name.startswith('Assets/')}
(OUT/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({name:receipt[name]for name in ['shader_gpu_sha256','pixel_bytes','zip','zip_sha256','asset_counts','installed']},indent=2))

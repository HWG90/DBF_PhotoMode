"""Compile Photo-owned DoF composition without changing the proven native ABI."""
from pathlib import Path
import argparse,ctypes,hashlib,json,struct
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'freecam/assets/shaders/dof_local_depth.hlsl'
BASE=ROOT/'freecam/assets/shaders/dof_library_template.gpu'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=ROOT/'dist/releases/photo-dof-composition-review')
OUT=parser.parse_args().output
sha=lambda data:hashlib.sha256(data).hexdigest()
original=BASE.read_bytes()
assert sha(original)=='6729d404ca524fc4dd20a986fdab5bd65f54b9fca126fccda96b4c42afb492b7'
identity=json.loads((BASE.parent/'dof-source-inputs.json').read_text())
assert sha(original)==identity['files'][BASE.name]['sha256']and len(original)==identity['files'][BASE.name]['bytes']
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
source=SOURCE.read_bytes();buffer=ctypes.create_string_buffer(source)
compiled,error=ctypes.c_void_p(),ctypes.c_void_p()
result=compile_code(buffer,len(source),SOURCE.name.encode(),None,None,b'photo_dof',b'ps_5_0',1<<15,0,ctypes.byref(compiled),ctypes.byref(error))
message=blob(error).decode(errors='replace')if error else ''
assert result>=0,message
code=blob(compiled);assert len(code)<7152
disassemble=dll.D3DDisassemble
disassemble.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];disassemble.restype=ctypes.c_long
def listing(body):
 buffer=ctypes.create_string_buffer(body);output=ctypes.c_void_p()
 assert disassemble(buffer,len(body),0,None,ctypes.byref(output))>=0
 return blob(output).decode(errors='replace')
assembly=listing(code)
assert all(name in assembly for name in ['__tex_diffuse_map','__tex_hdr0_div4_fullres','CB0[49]','CB2[3]'])
set_part=dll.D3DSetBlobPart
set_part.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_uint,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];set_part.restype=ctypes.c_long
def with_private(size):
 buffer=ctypes.create_string_buffer(code);private=ctypes.create_string_buffer(size);output=ctypes.c_void_p()
 assert set_part(buffer,len(code),10,0,private,size,ctypes.byref(output))>=0
 return blob(output)
first=with_private(4);padded=with_private(7152-len(first)+4)
assert len(padded)==7152 and struct.unpack_from('<I',padded,24)[0]==7152
listing(padded)
body=bytearray(original);body[0x2468:0x2468+7152]=padded
assert body[:0x2468]==original[:0x2468]and body[0x2468+7152:]==original[0x2468+7152:]
assert body[0xff0:0xff0+5160]==original[0xff0:0xff0+5160]
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'dof_local_depth.gpu').write_bytes(body)
(OUT/'dof_local_depth.hlsl').write_bytes(source)
(OUT/'dof_local_depth.asm.txt').write_text(assembly)
receipt={'shader':'mods/dbf_photo/shaders/dof_local_depth_v1','sha256':sha(body),'pixel_bytes':len(code),'pixel_window_bytes':7152,'native_vertex_byte_identity':True,'all_native_metadata_byte_identity':True,'original_candidate_sha256':sha(original),'owned_template':str(BASE.relative_to(ROOT)),'hlsl_sha256':sha(source),'composition':'Transparent at the focus plane; depth-dependent alpha blends defocused pixels over the original scene.','installed':False,'live_verified':False}
(OUT/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))

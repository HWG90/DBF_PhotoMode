"""Build an offline DoF library preserving the native two-texture binding ABI."""
from pathlib import Path
import hashlib,json,struct,sys
ROOT=Path(__file__).resolve().parents[1]
HUD=ROOT.parent/'DBF-HUD'
DBF=ROOT.parent/'DBF-Suite/DBF'
sys.path.insert(0,str(DBF/'freecam'))
sys.path.insert(0,str(HUD/'tools'))
from scene_effects import compile_shader
from build_depth_state_test import hash64
from build_scene_hud import padded
out=ROOT/'dist/releases/photo-dof-local-depth-review'
out.mkdir(parents=True,exist_ok=True)
original=(HUD/'assets/scene-depth-probe/source-diffuse-blur.gpu').read_bytes()
assert len(original)==16592
source=(ROOT/'dist/dof-investigation-20261011/ee6-registered-scene-candidate/production-scene-dof.hlsl').read_text()
source=source.replace('__tex_hdr0_div4_fullres : register(t0)','__tex_hdr0_div4_fullres : register(t1)').replace('__samp_hdr0_div4_fullres : register(s0)','__samp_hdr0_div4_fullres : register(s1)')
source=source.replace('__tex_linear_depth','__tex_diffuse_map').replace('__samp_linear_depth','__samp_diffuse_map').replace('__tex_diffuse_map : register(t1)','__tex_diffuse_map : register(t0)').replace('__samp_diffuse_map : register(s1)','__samp_diffuse_map : register(s0)')
source=source.replace('// Photo-only depth-aware blur using two existing renderer-global bindings.','// Native local diffuse_map holds scene depth; native global HDR slot is unchanged.')
hlsl=out/'dof_local_depth.hlsl';hlsl.write_text(source)
code,listing=compile_shader(hlsl,'photo_dof')
assert len(code)<7152 and '__tex_diffuse_map' in listing and '__tex_hdr0_div4_fullres' in listing
name='mods/dbf_photo/shaders/dof_local_depth_v1'
result=bytearray(original);result[0x2468:0x2468+7152]=padded(code,7152)
replacements={struct.unpack_from('<I',original,0x88)[0]:hash64(name+':default:PLATFORM_WIN32:RENDERER_D3D11')>>32,
struct.unpack_from('<I',original,0xe0)[0]:hash64(name)>>32,
struct.unpack_from('<I',original,0xbec)[0]:hash64(name+':pixel')>>32}
counts={key:0 for key in replacements};allowed=set(range(0x2468,0x2468+7152))
for offset in range(0,len(original)-3,4):
 if 0xff0<=offset<0xff0+5160 or 0x2468<=offset<0x2468+7152:continue
 value=struct.unpack_from('<I',original,offset)[0]
 if value in replacements:
  struct.pack_into('<I',result,offset,replacements[value]);counts[value]+=1;allowed.update(range(offset,offset+4))
assert sorted(counts.values())==[1,2,2]
assert all(i in allowed for i,(a,b)in enumerate(zip(original,result))if a!=b)
assert result[0xff0:0xff0+5160]==original[0xff0:0xff0+5160]
for begin,end in ((0x5ec,0x600),(0xf18,0xf48),(0x4090,0x40c8)):
 assert result[begin:end]==original[begin:end],'Native binding ABI changed'
(out/'dof_local_depth.gpu').write_bytes(result)
(out/'dof_local_depth.asm.txt').write_text(listing)
receipt={'shader':name,'sha256':hashlib.sha256(result).hexdigest(),'pixel_bytes':len(code),'native_vertex_byte_identity':True,'native_binding_records_byte_identity':True,'installed':False,'live_verified':False,
'required_runtime_binding':'Material.set_resource(handle, diffuse_map, verified existing linear_depth renderer resource)',
'scope':'Shader library candidate only; material loading, depth resource lookup and visual focus/aperture response remain unverified'}
(out/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))

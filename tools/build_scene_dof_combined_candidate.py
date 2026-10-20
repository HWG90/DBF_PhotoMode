"""Compile an isolated combined scene/bokeh shader; never deploy or replace assets."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import struct
import photo_assets

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'freecam/assets/shaders/scene_dof_combined_candidate.hlsl'
TEMPLATE=SOURCE.parent/'dof_library_template.gpu'
SHADER='mods/dbf_photo/shaders/scene_dof_combined_v1'
MATERIAL='mods/dbf_photo/materials/scene_dof_combined_v1'
WINDOW=7152
sha=lambda b:hashlib.sha256(b).hexdigest()

def build(output,color_name):
    output=Path(output);assert not output.exists(),'Preserve existing named candidates'
    original=TEMPLATE.read_bytes();assert sha(original)=='6729d404ca524fc4dd20a986fdab5bd65f54b9fca126fccda96b4c42afb492b7'
    dll=ctypes.WinDLL('d3dcompiler_47.dll')
    def blob(pointer):
        table=ctypes.cast(pointer,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        address=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(table[3])(pointer)
        size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(table[4])(pointer)
        result=ctypes.string_at(address,size)
        ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(table[2])(pointer)
        return result
    compile_code=dll.D3DCompile
    compile_code.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_void_p)]
    compile_code.restype=ctypes.c_long
    source=SOURCE.read_bytes();buffer=ctypes.create_string_buffer(source);compiled,error=ctypes.c_void_p(),ctypes.c_void_p()
    status=compile_code(buffer,len(source),SOURCE.name.encode(),None,None,b'photo_combined',b'ps_5_0',1<<15,0,ctypes.byref(compiled),ctypes.byref(error))
    message=blob(error).decode(errors='replace')if error else ''
    assert status>=0,message
    code=blob(compiled)
    disassemble=dll.D3DDisassemble
    disassemble.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];disassemble.restype=ctypes.c_long
    def listing(data):
        buffer=ctypes.create_string_buffer(data);result=ctypes.c_void_p()
        assert disassemble(buffer,len(data),0,None,ctypes.byref(result))>=0
        return blob(result).decode(errors='replace')
    assembly=listing(code)
    assert all(name in assembly for name in ['__tex_diffuse_map','__tex_photo_color','CB0[49]','CB2[9]'])
    vertex_assembly=listing(original[0xff0:0xff0+5160])
    assert 'cbuffer c_per_object'in vertex_assembly and 'dcl_constantbuffer CB2[5]'in vertex_assembly
    assert 'cbuffer c0'not in vertex_assembly and 'clip_box'not in vertex_assembly and 'scissor_mode'not in vertex_assembly
    strip=dll.D3DStripShader
    strip.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p)];strip.restype=ctypes.c_long
    buffer=ctypes.create_string_buffer(code);result=ctypes.c_void_p()
    assert strip(buffer,len(code),3,ctypes.byref(result))>=0
    stripped=blob(result);listing(stripped)
    output.mkdir(parents=True)
    (output/'scene_dof_combined.hlsl').write_bytes(source)
    (output/'scene_dof_combined.asm.txt').write_text(assembly)
    (output/'native_vertex_preserved.asm.txt').write_text(vertex_assembly)
    (output/'scene_dof_combined.ps.dxbc').write_bytes(stripped)
    receipt={'candidate':True,'installed':False,'live_verified':False,'shader':SHADER,'material':MATERIAL,
        'pixel_bytes_unstripped':len(code),'pixel_bytes_stripped':len(stripped),'pixel_window_bytes':WINDOW,
        'stripped_comparison_only':True,'vertex_uniform_separation':{'vertex_b2':'c_per_object transform/flag buffer','pixel_b2':'c0 material buffer','vertex_has_clip_box_or_scissor_mode':False},
        'color_resource_name':color_name,'color_resource_hash':f'{photo_assets.hash64(color_name)>>32:08x}',
        'color_resource_live_binding_verified':False,'color_space':'display encoded sRGB assumed by retained DoF decode/encode; verify selected resource',
        'uniforms':{'scissor_rect':['focus_m','aperture_fstop','fov_radians','blur_pixels_0_disables_dof'],
            'atlas_scissor':['scene_depth_range_m','calibration','blades_0_circle_6_hex','quality_0_32_1_64'],
            'scissor_mode':'effect_0_to_9','threshold_fade':'effect_strength','desaturate':'fog_half_density_m',
            'clip_box':['exposure_EV','contrast','saturation','fog_maximum_opacity']},
        'composition':'Gather bokeh, blend focused pixels using full-resolution source, then transform color and depth once. Independent GUI layer outputs are not chained.',
        'shader_fits_preserved_pixel_window':len(stripped)<=WINDOW-12,'hlsl_sha256':sha(source)}
    if code:
        setpart=dll.D3DSetBlobPart
        setpart.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_uint,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];setpart.restype=ctypes.c_long
        def pad(size):
            buffer=ctypes.create_string_buffer(code);private=ctypes.create_string_buffer(size);result=ctypes.c_void_p()
            assert setpart(buffer,len(code),10,0,private,size,ctypes.byref(result))>=0
            return blob(result)
        first=pad(4)
        window=max(WINDOW,((len(first)+15)//16)*16)
        padded=pad(window-len(first)+4)
        assert len(padded)==window and struct.unpack_from('<I',padded,24)[0]==window
        listing(padded)
        # The on-disk GPU library serializes bytecode lengths in the stage
        # descriptors and then the DXBC blobs plus each stage's binding records. The trailing
        # program/binding records contain names/categories/slots, not pointers.
        assert len(original)==0x40d0
        assert struct.unpack_from('<I',original,0xaa8)[0]==5160
        assert struct.unpack_from('<I',original,0xbe8)[0]==WINDOW
        assert photo_assets._dxbc_windows(original)==[(0xff0,5160),(0x2468,WINDOW)]
        assert 0xff0+5160+80==0x2468 and 0x2468+WINDOW==0x4058
        assert len(original[0x4058:])==120
        # Neither the prefix nor tail has a serialized absolute bytecode/tail
        # offset or total-length field to relocate. Reject any format drift.
        for old_offset in (0xff0,0x2468,0x4058,len(original)):
            assert not any(struct.unpack_from('<I',original,at)[0]==old_offset
                for at in list(range(0,0xff0,4))+list(range(0x4058,len(original)-3,4)))
        body=bytearray(original)
        allowed=set()
        replacements={struct.unpack_from('<I',original,0x88)[0]:photo_assets.hash64(SHADER+':default:PLATFORM_WIN32:RENDERER_D3D11')>>32,
            struct.unpack_from('<I',original,0xe0)[0]:photo_assets.hash64(SHADER)>>32,
            struct.unpack_from('<I',original,0xbec)[0]:photo_assets.hash64(SHADER+':pixel')>>32}
        counts={key:0 for key in replacements}
        for at in range(0,len(original)-3,4):
            if 0xff0<=at<0xff0+5160 or 0x2468<=at<0x2468+WINDOW:continue
            value=struct.unpack_from('<I',original,at)[0]
            if value in replacements:
                struct.pack_into('<I',body,at,replacements[value]);counts[value]+=1;allowed.update(range(at,at+4))
        assert sorted(counts.values())==[1,2,2]
        old=photo_assets.hash64('hdr0_div4_fullres')>>32
        offsets=(0x5f8,0xf38,0x40a0,0x40bc)
        assert [at for at in range(0,len(original)-3,4)if struct.unpack_from('<I',original,at)[0]==old]==list(offsets)
        for at in offsets:
            struct.pack_into('<I',body,at,photo_assets.hash64(color_name)>>32);allowed.update(range(at,at+4))
        assert all(at in allowed for at,(a,b)in enumerate(zip(original,body))if a!=b)
        metadata=bytes(body)
        struct.pack_into('<I',body,0xbe8,window)
        body[0x2468:0x4058]=padded
        delta=window-WINDOW;tail=0x4058+delta
        assert len(body)==len(original)+delta and delta%16==0
        assert photo_assets._dxbc_windows(body)==[(0xff0,5160),(0x2468,window)]
        assert body[0xff0:0xff0+5160]==original[0xff0:0xff0+5160]
        assert body[tail:]==metadata[0x4058:],'All serialized tail bindings must move intact'
        # Inverting only the recorded splice/length must recover the fully
        # retargeted original; changing metadata/padding incidentally is forbidden.
        roundtrip=bytearray(body);roundtrip[0x2468:0x2468+window]=metadata[0x2468:0x4058]
        struct.pack_into('<I',roundtrip,0xbe8,WINDOW)
        assert bytes(roundtrip)==metadata
        material=bytearray((SOURCE.parent/'dof_local_depth.material.bin').read_bytes());struct.pack_into('<I',material,128,photo_assets.hash64(SHADER)>>32)
        (output/'scene_dof_combined.gpu').write_bytes(body)
        (output/'scene_dof_combined.material.bin').write_bytes(material)
        receipt.update(shader_gpu_sha256=sha(body),material_sha256=sha(material),native_vertex_byte_identity=True,native_parameter_and_binding_abi_preserved=True,
            emitted_pixel_window_bytes=window,emitted_full_reflection=True,library_expansion_bytes=delta,
            stage_length_field={'offset':'0xbe8','original':WINDOW,'candidate':window},
            serialized_tail_relocation={'old_offset':'0x4058','new_offset':hex(tail),'bytes':120,'byte_identity':True},
            reverse_splice_roundtrip=True,expanded_library_live_load_verified=False)
    (output/'BUILD-RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--color-name',default='hdr1')
    args=parser.parse_args();print(json.dumps(build(args.output.resolve(),args.color_name),indent=2))

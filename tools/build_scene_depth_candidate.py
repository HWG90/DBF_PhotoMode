"""Build complete Photo scene assets from owned templates and the corrected DoF ZIP.

No deployment or game access. The previous 40 decorations, DoF bytes, and all
316 registrations are preserved. Scene shader/library IDs are independent.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import photo_assets

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'freecam/assets/shaders'
SHADER='mods/dbf_photo/shaders/scene_depth_color_v1'
MATERIAL='mods/dbf_photo/materials/scene_depth_color_v1'
BASE=ROOT/'dist/releases/photo-bokeh-color-corrected-review/War-Journalist-Fullres-Bokeh-Candidate-Assets.zip'
DOF_SHA='a1147750dfdb4a7cad87713af1740e5c23b34605506978ba9a97620034108c9a'
sha=lambda body:hashlib.sha256(body).hexdigest()


def blob(pointer):
    table=ctypes.cast(pointer,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    address=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(table[3])(pointer)
    size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(table[4])(pointer)
    body=ctypes.string_at(address,size)
    ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(table[2])(pointer)
    return body


def compile_scene(source):
    dll=ctypes.WinDLL('d3dcompiler_47.dll')
    compile_code=dll.D3DCompile
    compile_code.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_void_p)]
    compile_code.restype=ctypes.c_long
    data=ctypes.create_string_buffer(source);compiled,error=ctypes.c_void_p(),ctypes.c_void_p()
    result=compile_code(data,len(source),b'scene_depth_color_candidate.hlsl',None,None,b'photo_scene',b'ps_5_0',1<<15,0,ctypes.byref(compiled),ctypes.byref(error))
    message=blob(error).decode(errors='replace')if error else ''
    assert result>=0,message
    code=blob(compiled);assert len(code)<7152,'Scene pixel shader exceeds the proven native window'
    disassemble=dll.D3DDisassemble
    disassemble.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];disassemble.restype=ctypes.c_long
    def listing(body):
        data=ctypes.create_string_buffer(body);output=ctypes.c_void_p()
        assert disassemble(data,len(body),0,None,ctypes.byref(output))>=0
        return blob(output).decode(errors='replace')
    assembly=listing(code)
    assert all(name in assembly for name in ['__tex_diffuse_map','__tex_hdr0_div4_fullres','CB0[49]','CB2[3]'])
    set_part=dll.D3DSetBlobPart
    set_part.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_uint,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];set_part.restype=ctypes.c_long
    def with_private(size):
        data=ctypes.create_string_buffer(code);private=ctypes.create_string_buffer(size);output=ctypes.c_void_p()
        assert set_part(data,len(code),10,0,private,size,ctypes.byref(output))>=0
        return blob(output)
    first=with_private(4);padded=with_private(7152-len(first)+4)
    assert len(padded)==7152 and struct.unpack_from('<I',padded,24)[0]==7152
    listing(padded)
    return code,padded,assembly


def scene_library(output):
    source=(FOLDER/'scene_depth_color_candidate.hlsl').read_bytes()
    template=(FOLDER/'dof_library_template.gpu').read_bytes()
    assert len(template)==16592 and sha(template)=='6729d404ca524fc4dd20a986fdab5bd65f54b9fca126fccda96b4c42afb492b7'
    code,padded,assembly=compile_scene(source)
    result=bytearray(template);result[0x2468:0x2468+7152]=padded
    replacements={
        struct.unpack_from('<I',template,0x88)[0]:photo_assets.hash64(SHADER+':default:PLATFORM_WIN32:RENDERER_D3D11')>>32,
        struct.unpack_from('<I',template,0xe0)[0]:photo_assets.hash64(SHADER)>>32,
        struct.unpack_from('<I',template,0xbec)[0]:photo_assets.hash64(SHADER+':pixel')>>32,
    }
    counts={key:0 for key in replacements};allowed=set(range(0x2468,0x2468+7152))
    for at in range(0,len(template)-3,4):
        if 0xff0<=at<0xff0+5160 or 0x2468<=at<0x2468+7152:continue
        value=struct.unpack_from('<I',template,at)[0]
        if value in replacements:
            struct.pack_into('<I',result,at,replacements[value]);counts[value]+=1;allowed.update(range(at,at+4))
    assert sorted(counts.values())==[1,2,2],'Native identity relocation count changed'
    assert all(at in allowed for at,(a,b)in enumerate(zip(template,result))if a!=b)
    assert result[0xff0:0xff0+5160]==template[0xff0:0xff0+5160]
    for begin,end in ((0x5ec,0x600),(0xf18,0xf48),(0x4090,0x40c8)):
        assert result[begin:end]==template[begin:end],'Native texture binding ABI changed'
    material=bytearray((FOLDER/'dof_local_depth.material.bin').read_bytes())
    assert sha(material)=='79a8ece6ebbe03f6fb2f366afa08df658d46723877257e5890180ced7620c23d'and len(material)==144
    struct.pack_into('<I',material,128,photo_assets.hash64(SHADER)>>32)
    output.mkdir(parents=True)
    (output/'scene_depth_color.gpu').write_bytes(result)
    (output/'scene_depth_color.material.bin').write_bytes(material)
    (output/'scene_depth_color_candidate.hlsl').write_bytes(source)
    (output/'scene_depth_color_candidate.asm.txt').write_text(assembly)
    return bytes(result),bytes(material),{'shader':SHADER,'material':MATERIAL,
        'variant':f'{photo_assets.hash64(SHADER)>>32:08x}',
        'program':f'{photo_assets.hash64(SHADER+":default:PLATFORM_WIN32:RENDERER_D3D11")>>32:08x}',
        'shader_gpu_sha256':sha(result),'material_sha256':sha(material),'hlsl_sha256':sha(source),
        'pixel_bytes':len(code),'pixel_window_bytes':7152,'native_vertex_byte_identity':True,
        'native_texture_binding_records_byte_identity':True}


def resources(output,base_assets=BASE):
    output=Path(output);assert not output.exists(),'Preserve an existing named candidate output'
    base_assets=Path(base_assets)
    with zipfile.ZipFile(base_assets)as archive:
        assert archive.testzip()is None
        assert len(archive.namelist())==len(set(archive.namelist()))
        core=photo_assets.read_archive(archive.read('Assets/ee6b1ba7e22d71ed.patch_0'),archive.read('Assets/ee6b1ba7e22d71ed.patch_0.gpu_resources'))
        shared=photo_assets.read_archive(archive.read('Assets/9ba626afa44a3aa3.patch_0'),archive.read('Assets/9ba626afa44a3aa3.patch_0.gpu_resources'))
        for name in ['Assets/ee6b1ba7e22d71ed.patch_0.stream','Assets/9ba626afa44a3aa3.patch_0.stream']:assert archive.read(name)==b''
    assert len(core)==42 and len(shared)==41
    assert sum(row[1]==photo_assets.SHADER for row in core)==41
    assert all(row[1]==photo_assets.MATERIAL for row in shared)
    originals={row[:2]:row for row in core+shared}
    assert all(originals.get(row[:2])==row for row in photo_assets.load_resources()),'All 40 decorative pairs must remain exact'
    dof_id=photo_assets.hash64('mods/dbf_photo/shaders/dof_local_depth_v1')
    assert sha(originals[dof_id,photo_assets.SHADER][3])==DOF_SHA,'Only the corrected DoF baseline may be merged'
    group_key=photo_assets.hash64(photo_assets.GROUP_NAME),photo_assets.GROUP
    original_group=originals[group_key][2];ids=list(photo_assets.registry_ids(original_group));assert len(ids)==316 and dof_id in ids
    shader_id=photo_assets.hash64(SHADER);material_id=photo_assets.hash64(MATERIAL)
    assert shader_id not in ids and (shader_id,photo_assets.SHADER)not in originals and (material_id,photo_assets.MATERIAL)not in originals
    gpu,material,compiled=scene_library(output)
    ids.append(shader_id);group=bytearray(original_group[:24]);struct.pack_into('<I',group,16,len(ids));group+=struct.pack('<317Q',*ids)
    core=[row for row in core if row[:2]!=group_key]+[(shader_id,photo_assets.SHADER,struct.pack('<I',4),gpu),(group_key[0],group_key[1],bytes(group),b'')]
    shared=shared+[(material_id,photo_assets.MATERIAL,material,b'')]
    for row in core+shared:
        if row[:2]in originals and row[:2]!=group_key:assert row==originals[row[:2]],'Existing asset bytes changed'
    audit={'candidate':True,'installed':False,'live_verified':False,'compiled':compiled,
        'base_zip_sha256':sha(base_assets.read_bytes()),'base_dof_gpu_sha256':DOF_SHA,
        'asset_counts':{'core_libraries':42,'core_registry':1,'shared_materials':42,'registry_ids':317},
        'previous_316_registrations_preserved':True,'previous_40_decorative_pairs_and_corrected_dof_preserved':True,
        'color_source':{'name':'hdr0_div4_fullres','hash':'f0e28536','verified_dimensions':[960,540],
            'limitation':'Active scene grading replaces pixels using this quarter-resolution display source. Neutral controls draw nothing. Full-resolution ldr0/ldr1 exist but GUI-safe sampling and composition stage remain unproved.'},
        'ordering':{'scene_layer':87,'custom_dof_layer':88,'decorations_layer':90,'guides_layer':100,
            'shader_dof_combination':'Gate until the same scene transform is applied to bokeh samples; current bokeh bytes are preserved.'},
        'uniforms':{'scissor_rect':['effect_index_0_to_9','strength_0_to_1','fog_distance_metres','fog_density_0_to_1'],
            'atlas_scissor':['exposure_EV','contrast_multiplier','saturation_multiplier','depth_range_metres']},
        'effects':['None','Negative','Monochrome','Posterize','Field-report duotone','Solarize','Inverted depth','Thermal depth','Depth contours','Depth fog'],
        'residual_checks':['Startup registry/material availability','Negative and fog visual response','Exposure/contrast/saturation brightness and color','Native DoF coexistence/source stage','Neutral pixel preservation and exit cleanup']}
    return core,shared,audit


def package(output,base_assets=BASE):
    output=Path(output);core,shared,audit=resources(output,base_assets)
    manifest={'Version':1,'Guid':'fd8637c5-b38f-488a-91e5-b3ba5f27a7df','Name':'War Journalist Scene Depth and DoF - Candidate',
        'Description':'Complete Photo assets: 40 decorations, preserved corrected bokeh DoF, and separate scene color/depth preview. Scene grading uses a quarter-resolution display source; visual verification is pending.',
        'Options':[{'Name':'DoF shader assets and registry','Include':['Assets']}]}
    files={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'CANDIDATE-RECEIPT.json':(json.dumps(audit,indent=2)+'\n').encode()}
    for name,rows in [('ee6b1ba7e22d71ed.patch_0',core),('9ba626afa44a3aa3.patch_0',shared)]:
        cpu,gpu=photo_assets.archive_rows(rows);assert sorted(photo_assets.read_archive(cpu,gpu))==sorted(rows)
        for suffix,data in [('',cpu),('.gpu_resources',gpu),('.stream',b'')]:files['Assets/'+name+suffix]=data
    files['FILES-SHA256.txt']=''.join(sha(data)+'  '+name+'\n'for name,data in sorted(files.items())).encode()
    target=output/'War-Journalist-Scene-Depth-Candidate-Assets.zip'
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED)as archive:
        for name,data in sorted(files.items()):archive.writestr(name,data)
    with zipfile.ZipFile(target)as archive:
        assert archive.testzip()is None and len(archive.namelist())==len(files)==len(set(archive.namelist()))
        assert all(archive.read(name)==data for name,data in files.items())
    audit.update(zip=target.name,zip_sha256=sha(target.read_bytes()),zip_crc_and_exact_entries=True,
        archive_files={name:{'sha256':sha(data),'bytes':len(data)}for name,data in files.items()if name.startswith('Assets/')})
    (output/'BUILD-RECEIPT.json').write_text(json.dumps(audit,indent=2)+'\n')
    return target,audit


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'dist/releases/photo-scene-depth-review')
    parser.add_argument('--base-assets',type=Path,default=BASE)
    args=parser.parse_args();target,audit=package(args.output.resolve(),args.base_assets.resolve())
    print(json.dumps({'zip':str(target),'zip_sha256':audit['zip_sha256'],'compiled':audit['compiled'],'asset_counts':audit['asset_counts'],'installed':False},indent=2))

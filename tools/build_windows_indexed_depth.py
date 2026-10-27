"""Offline candidate: preserve declaration indices while selecting global depth.

Never deploys. Uses the unchanged portable.4 GPU programs. The withdrawn
portable.5 converter changed a declaration index as though it were a type.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import photo_assets as assets
from build_windows_global_depth import build

SHA=lambda b:hashlib.sha256(b).hexdigest()

def verify_texture_declarations(gpu, table, count, records):
    declarations=[struct.unpack_from('<III',gpu,table+i*12) for i in range(count)]
    result=[]
    for at in records:
        name,index,slot,used=struct.unpack_from('<IIII',gpu,at)
        assert index<len(declarations),'Binding index outside declarations'
        declared,kind,offset=declarations[index]
        assert declared==name,'Binding index references a different resource'
        assert kind==4 and used==1,'Expected one texture binding'
        result.append({'name':f'{name:08x}','declaration_index':index,'slot':slot,'variable_offset':offset})
    return result

def convert(gpu, material, suffix):
    original=bytes(gpu);body=bytearray(gpu);tail=len(body)-120
    u=lambda at:struct.unpack_from('<I',original,at)[0]
    windows=assets._dxbc_windows(body)
    assert windows[0]==(0xff0,5160) and windows[1][0]==0x2468
    assert windows[1][0]+windows[1][1]==tail
    local=assets.hash64('diffuse_map')>>32
    color=assets.hash64('output_target')>>32
    depth=assets.hash64('linear_depth')>>32
    assert (u(0xf18),u(0xf20),u(0xf28))==(6,local,0)
    assert (u(0xf30),u(0xf38),u(0xf40))==(5,color,1)
    before=verify_texture_declarations(original,0x5c8,6,[tail+56,tail+72])
    assert [r['declaration_index'] for r in before]==[3,4]
    offsets=(0x5ec,0xf20,tail+56,tail+88)
    assert all(u(at)==local for at in offsets)
    identity=SHA(original+b':indexed-global-linear-depth-v2')[:16]
    shader='mods/dbf_photo/shaders/windows_indexed_depth_'+identity
    material_name='mods/dbf_photo/materials/windows_indexed_depth_'+identity
    allowed=set()
    def put(at,value):
        struct.pack_into('<I',body,at,value);allowed.update(range(at,at+4))
    for at in offsets:put(at,depth)
    # Only the native parameter category changes. The footer's second field
    # indexes the declaration table; depth retains 3 and color retains 4.
    put(0xf18,5)
    identities={u(0x88):assets.hash64(shader+':default:PLATFORM_WIN32:RENDERER_D3D11')>>32,
                u(0xe0):assets.hash64(shader)>>32,u(0xbec):assets.hash64(shader+':pixel')>>32}
    counts={key:0 for key in identities}
    for at in range(0,len(body)-3,4):
        if any(start<=at<start+size for start,size in windows):continue
        if u(at) in identities:
            put(at,identities[u(at)]);counts[u(at)]+=1
    assert sorted(counts.values())==[1,2,2]
    assert all(at in allowed for at,(a,b) in enumerate(zip(original,body)) if a!=b)
    assert all(body[start:start+size]==original[start:start+size] for start,size in windows)
    after=verify_texture_declarations(body,0x5c8,6,[tail+56,tail+72])
    assert [r['declaration_index'] for r in after]==[3,4]
    assert [r['slot'] for r in after]==[0,1]
    mat=bytearray(material);assert struct.unpack_from('<I',mat,128)[0]==u(0xe0)
    struct.pack_into('<I',mat,128,identities[u(0xe0)])
    return shader,material_name,bytes(body),bytes(mat),{
        'source_suffix':suffix,'source_gpu_sha256':SHA(original),'shader':shader,'material':material_name,
        'gpu_sha256':SHA(body),'native_parameter_category_change':[6,5],
        'bindings':after,'both_dxbc_stages_unchanged':True,'live_verified':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    parser.error('Withdrawn after portable.8 menu-open crash; corrected metadata did not qualify global depth for GUI use')
    receipt=build(args.source,args.output,converter=convert)
    (args.output.parent/'INDEXED-DEPTH.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:v for k,v in receipt.items() if k!='registry'},indent=2))

"""Compile additive decorative material replacements; never deploys to the game."""
import argparse,hashlib,json,os,struct,subprocess
from pathlib import Path
import photo_assets as a
from generate_decorative_v2 import generate,ROOT,FOLDER
sha=lambda b:hashlib.sha256(b).hexdigest()
def build(args):
 out=args.output.resolve();assert not out.exists(),'Preserve existing candidates';out.mkdir(parents=True)
 names=generate();old={r[:2]:r for r in a.load_resources()};lookup={};replacements=[]
 def invoke(mode,src,dst,err):
  win=lambda p:'Z:'+str(p.resolve()).replace('/','\\')
  env=dict(os.environ,WINEPREFIX=str(args.compiler.resolve().parent/'prefix'),WINEDEBUG='-all')
  subprocess.run(['wine',str(args.compiler.resolve()),win(args.dll),mode,win(src),win(dst),win(err)],env=env,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=45)
 def compile(source,remainder):
  key=sha(source);src=out/(key+'.hlsl');dst=out/(key+'.dxbc');err=out/(key+'.txt');src.write_bytes(source.replace(b'hud_fill(',b'photo_resolved_v2('))
  invoke('compile',src,dst,err)
  padded=out/(key+'.padded.dxbc');invoke('pad'+str(remainder),dst,padded,err)
  code=padded.read_bytes();assert code[:4]==b'DXBC'and struct.unpack_from('<I',code,24)[0]==len(code)
  assert len(code)%16==remainder
  return code
 for name in names:
  source=(FOLDER/(name+'.hlsl')).read_bytes();content=sha(source+b':aligned-v2')[:16]
  shader='mods/dbf_photo/shaders/decorative_'+name+'_'+content;material='mods/dbf_photo/materials/decorative_'+name+'_'+content
  original=old[a.hash64('mods/dbf_hud/shaders/mapped_'+name),a.SHADER][3];windows=a._dxbc_windows(original);assert len(windows)==2
  va,vs=windows[0];pa,ps=windows[1];assert pa==va+vs+76
  code=compile(source,ps%16);assert (len(code)-ps)%16==0
  # Native stage records precede their DXBC payloads. Change only IDs,
  # pixel stage size and pixel bytes; retain native vertex and binding tail.
  size_at=0xbe0;pixel_at=0xbe4
  assert struct.unpack_from('<I',original,size_at)[0]==ps
  body=bytearray(original);old_variant=a.hash64('mods/dbf_hud/shaders/mapped_'+name)>>32
  ids={struct.unpack_from('<I',body,0x88)[0]:a.hash64(shader+':default:PLATFORM_WIN32:RENDERER_D3D11')>>32,old_variant:a.hash64(shader)>>32,struct.unpack_from('<I',body,pixel_at)[0]:a.hash64(shader+':pixel')>>32}
  counts={k:0 for k in ids}
  for at in list(range(0,va,4))+list(range(pa+ps,len(body)-3,4)):
   value=struct.unpack_from('<I',body,at)[0]
   if value in ids:struct.pack_into('<I',body,at,ids[value]);counts[value]+=1
  assert sorted(counts.values())==[1,2,2],counts
  struct.pack_into('<I',body,size_at,len(code));tail=bytes(body[pa+ps:]);body[pa:pa+ps]=code
  assert bytes(body[va:va+vs])==original[va:va+vs]and bytes(body[pa+len(code):])==tail
  assert (len(body)-len(original))%16==0,'Native serialized tail alignment changed'
  assert a._dxbc_windows(body)==[(va,vs),(pa,len(code))]
  mat=bytearray(old[a.hash64('mods/dbf_hud/materials/mapped_'+name),a.MATERIAL][2]);struct.pack_into('<I',mat,128,a.hash64(shader)>>32)
  replacements.extend([(a.hash64(shader),a.SHADER,struct.pack('<I',4),bytes(body)),(a.hash64(material),a.MATERIAL,bytes(mat),b'')])
  lookup[name]=material
 corepath=args.base_assets/'ee6b1ba7e22d71ed.patch_0';sharedpath=args.base_assets/'9ba626afa44a3aa3.patch_0'
 def rows(p):return a.read_archive(p.read_bytes(),Path(str(p)+'.gpu_resources').read_bytes())
 core,shared=rows(corepath),rows(sharedpath);before={r[:2]:r for r in core+shared}
 for r in replacements:assert r[:2]not in before;(core if r[1]==a.SHADER else shared).append(r)
 shaderids=[r[0]for r in replacements if r[1]==a.SHADER]
 for i,r in enumerate(core):
  if r[1]==a.GROUP:
   ids=list(a.registry_ids(r[2]));assert not set(ids)&set(shaderids);ids+=shaderids
   b=bytearray(r[2][:24]);struct.pack_into('<I',b,16,len(ids));b+=struct.pack('<%dQ'%len(ids),*ids);core[i]=(r[0],r[1],bytes(b),r[3])
 assets=out/'Assets';assets.mkdir()
 for label,rs in [('ee6b1ba7e22d71ed',core),('9ba626afa44a3aa3',shared)]:
  for r in rs:
   if r[:2]in before and r[1]!=a.GROUP:assert r==before[r[:2]]
  cpu,gpu=a.archive_rows(rs);assert sorted(a.read_archive(cpu,gpu))==sorted(rs)
  p=assets/(label+'.patch_0');p.write_bytes(cpu);Path(str(p)+'.gpu_resources').write_bytes(gpu);Path(str(p)+'.stream').write_bytes(b'')
 receipt={'installed':False,'live_verified':False,'materials':lookup,'existing_nonregistry_resources_preserved':len(before)-1,'added_resources':len(replacements),'restart_required':True,'serialization_alignment':16,'candidate_status':'OFFLINE ONLY; first-draw crash investigation; do not enable automatically'}
 (out/'DECORATIVE-CANDIDATE.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps(receipt,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['output','base-assets','compiler','dll']:p.add_argument('--'+name,type=Path,required=True)
 build(p.parse_args())

"""Build registry-only compatibility controls from immutable 0.9.8 ZIPs.

All runtime Lua, native DLLs, materials, lights and GPU programs stay byte-identical.
Never installs, publishes or replaces frozen release artifacts.
"""
import argparse, hashlib, io, json, struct, zipfile
from pathlib import Path
import photo_assets

ROOT=Path(__file__).resolve().parents[1]
FROZEN=ROOT/'dist/releases/War-Journalist-0.9.8'
HASHES={'BSL':'347d55f57cb7b5d16eddd86da43c097d70e32e5acbaa6e9ca567b3bf7cd73207',
 'MDL':'78cc20b1d9817deb7c947499cf2c72626473dd2834b9431c155fb91a4601c6fe',
 'LLL':'2450ff3607155c7e1532247fb41ab56313655787508ce5027c60a3dac7b1ac7f'}
TEST='''War Journalist 0.9.8 - Registry compatibility test

This complete test package changes shader registration only. Runtime Lua, native
DLLs, shader GPU programs, materials, artwork and the dedicated light are unchanged.
It removes 198 shader IDs that were not in vanilla or this package. All 44 bundled
shader libraries remain registered. This is a candidate, not a confirmed AMD fix.

Replace the existing War Journalist entry with this complete package. Use only one
War Journalist runtime loader. Follow INSTALL.txt for your loader, deploy and restart.
Test with War Journalist and its loader before adding other mods.

First, BEFORE opening Photo Mode: Alt-Tab away/back, then change fullscreen, bloom
and DoF one at a time. Record which action still crashes. Next open Photo Mode and
repeat. Do not change several settings at once. Report GPU/driver, loader and stage.
For BSL, startup notes are in LocalAppData/DBF/PhotoMode/PhotoMode-startup.log.
Keep the original package available for comparison. No saved settings are bundled.
'''.encode()

def sha(body):return hashlib.sha256(body).hexdigest()
def jb(value):return(json.dumps(value,indent=2)+'\n').encode()
def unpack(body):
 with zipfile.ZipFile(io.BytesIO(body)) as z:
  assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
  return {n:z.read(n) for n in z.namelist()}
def checks(files,prefix=''):
 name=prefix+'FILES-SHA256.txt'
 if name in files:
  files[name]=''.join(sha(b)+'  '+n[len(prefix):]+'\n' for n,b in sorted(files.items())
   if n.startswith(prefix) and n!=name).encode()
def pack(files):
 checks(files,'dbf_freecam/');checks(files)
 target=io.BytesIO()
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for name,body in sorted(files.items()):
   info=zipfile.ZipInfo(name,(2026,10,14,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
   z.writestr(info,body)
 return target.getvalue()

def repair(files,prefix):
 path=prefix+'ee6b1ba7e22d71ed.patch_0';gpu=files[path+'.gpu_resources']
 rows=photo_assets.read_archive(files[path],gpu,files[path+'.stream'])
 stock=(ROOT/'freecam/assets/shaders/original-default-shaders.bin').read_bytes()
 assert sha(stock)=='f62a82b5fc095c42958a1f30fe6a1f7846107d197960b3e5beb72bda18b86040'
 native=list(photo_assets.registry_ids(stock));assert len(native)==77
 libraries=[r[0] for r in rows if r[1]==photo_assets.SHADER];assert len(libraries)==44
 old=next(r for r in rows if r[1]==photo_assets.GROUP)
 prior=photo_assets.registry_ids(old[2]);assert len(prior)==319
 assert not set(native)&set(libraries) and set(native+libraries)<=set(prior)
 # Preserve the existing order of shipped additions; drop only unowned IDs.
 ids=native+[n for n in prior if n in set(libraries)]
 assert len(ids)==len(set(ids))==121
 header=bytearray(stock[:24]);struct.pack_into('<I',header,16,len(ids))
 registry=bytes(header)+struct.pack('<121Q',*ids)
 fixed=[(r[0],r[1],registry,r[3]) if r[1]==photo_assets.GROUP else r for r in rows]
 cpu,new_gpu=photo_assets.archive_rows(fixed);assert new_gpu==gpu,'GPU companion changed'
 actual=photo_assets.read_archive(cpu,new_gpu)
 assert sorted(r for r in actual if r[1]!=photo_assets.GROUP)==sorted(r for r in rows if r[1]!=photo_assets.GROUP)
 files[path]=cpu
 return {'registry_ids':121,'removed_unbundled_ids':198,'registry_sha256':sha(registry),
  'core_before_sha256':sha(photo_assets.archive_rows(rows)[0]),'core_after_sha256':sha(cpu),
  'gpu_companion_unchanged':True,'shader_libraries':44}

def build(output,loader):
 source=FROZEN/f'War-Journalist-0.9.8-{loader}.zip';body=source.read_bytes()
 assert sha(body)==HASHES[loader],'Frozen release identity changed'
 files=unpack(body);before=dict(files);prefix='Addon/' if loader=='BSL' else 'GameData/'
 audit=repair(files,prefix)
 for name in ['ASSET-MANIFEST.json','dbf_freecam/ASSET-MANIFEST.json']:
  if name in files:
   metadata=json.loads(files[name]);metadata['registry_ids']=121
   metadata['registry_compatibility_test']=audit;files[name]=jb(metadata)
 if loader=='LLL':
  name='Arsenal/War-Journalist-0.9.8-Assets.zip';nested=unpack(files[name]);repair(nested,'Assets/')
  metadata=json.loads(nested['ASSET-MANIFEST.json']);metadata['registry_ids']=121
  metadata['registry_compatibility_test']=audit;nested['ASSET-MANIFEST.json']=jb(metadata)
  nested['COMPATIBILITY-TEST.txt']=TEST;files[name]=pack(nested)
 doc='COMPATIBILITY-TEST.txt' if loader=='BSL' else 'dbf_freecam/COMPATIBILITY-TEST.txt'
 files[doc]=TEST
 if 'manifest.json' in files:
  manifest=json.loads(files['manifest.json']);manifest['Description']+=' Registry-only compatibility candidate; AMD crash status unverified.'
  files['manifest.json']=jb(manifest)
 # The entire BSL startup envelope is in shared CPU and remains untouched.
 assert files[prefix+'9ba626afa44a3aa3.patch_0']==before[prefix+'9ba626afa44a3aa3.patch_0']
 for name,value in before.items():
  if name.endswith(('.lua','.dll','.gpu_resources','.stream')):assert files[name]==value,name
 archive=pack(files);target=output/f'War-Journalist-0.9.8-Registry-Test-{loader}.zip'
 if target.exists():assert target.read_bytes()==archive,'Existing candidate differs'
 else:target.write_bytes(archive)
 return {'loader':loader,'path':str(target),'sha256':sha(archive),'bytes':len(archive),
  'frozen_source_sha256':sha(body),'runtime_and_shader_programs_unchanged':True,**audit}

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--output',type=Path,default=ROOT/'dist/review/amd-compatibility-20261014/registry-only')
 args=p.parse_args();args.output.mkdir(parents=True,exist_ok=True)
 results=[build(args.output,loader) for loader in HASHES]
 (args.output/'BUILD-RECEIPT.json').write_bytes(jb({'candidate':True,'amd_visual_validation':False,'results':results}))
 (args.output/'SHA256SUMS.txt').write_text(''.join(r['sha256']+'  '+Path(r['path']).name+'\n' for r in results))
 print(json.dumps(results,indent=2))
if __name__=='__main__':main()

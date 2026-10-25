"""Build additive SDR resource archives for review. Never installs or deploys."""
from pathlib import Path
import sys,json,struct,hashlib,zipfile
import argparse
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'));import photo_assets as a
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-assets',type=Path,required=True,help='Original Assets directory, never modified')
parser.add_argument('--shader-dir',type=Path,required=True,help='Reviewed compiled shader and BUILD-RECEIPT directory')
parser.add_argument('--manifest',type=Path,required=True,help='Existing asset mod manifest to preserve identity')
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();asset=args.base_assets;candidate=args.shader_dir
receipt=json.loads((candidate/'BUILD-RECEIPT.json').read_text());out=args.output;out.mkdir(parents=True,exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest()
corepath=asset/'ee6b1ba7e22d71ed.patch_0';sharedpath=asset/'9ba626afa44a3aa3.patch_0'
core=a.read_archive(corepath.read_bytes(),Path(str(corepath)+'.gpu_resources').read_bytes());shared=a.read_archive(sharedpath.read_bytes(),Path(str(sharedpath)+'.gpu_resources').read_bytes());before={(r[0],r[1]):r for r in core+shared}
sid=a.hash64(receipt['shader']);mid=a.hash64(receipt['material']);assert (sid,a.SHADER)not in before and(mid,a.MATERIAL)not in before
core.append((sid,a.SHADER,struct.pack('<I',4),(candidate/'scene_dof_combined.gpu').read_bytes()));shared.append((mid,a.MATERIAL,(candidate/'scene_dof_combined.material.bin').read_bytes(),b''))
for i,r in enumerate(core):
 if r[1]==a.GROUP:
  ids=list(a.registry_ids(r[2]));assert sid not in ids;ids.append(sid);body=bytearray(r[2][:24]);struct.pack_into('<I',body,16,len(ids));body+=struct.pack('<%dQ'%len(ids),*ids);core[i]=(r[0],r[1],bytes(body),r[3])
files={};checks=[]
for base,rows in [('ee6b1ba7e22d71ed',core),('9ba626afa44a3aa3',shared)]:
 cpu,gpu=a.archive_rows(rows);assert sorted(a.read_archive(cpu,gpu))==sorted(rows)
 for r in rows:
  if r[:2]in before and r[1]!=a.GROUP:assert r==before[r[:2]],'Existing owned resource changed'
 files['Assets/'+base+'.patch_0']=cpu;files['Assets/'+base+'.patch_0.gpu_resources']=gpu;files['Assets/'+base+'.patch_0.stream']=b'';checks.append({'archive':base,'resources':len(rows)})
manifest=json.loads(args.manifest.read_text());manifest['Description']='Existing complete Photo assets plus an isolated SDR compositor correction candidate; visual validation pending.';files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
report={'installed':False,'deployed':False,'live_verified':False,'existing_nonregistry_resources_preserved':len(before)-1,'archives':checks,'shader':receipt['shader'],'sdr_template':hex(sid>>32),'shader_gpu_sha256':receipt['shader_gpu_sha256'],'runtime_requires_negative_ui_white':True,'restart_required_for_asset_registration':True}
files['SDR-CANDIDATE.json']=(json.dumps(report,indent=2)+'\n').encode()
for name,body in files.items():p=out/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
with zipfile.ZipFile(out/'War-Journalist-SDR-Assets-Candidate.zip','w',zipfile.ZIP_DEFLATED)as z:
 for name,body in files.items():z.writestr(name,body)
print(json.dumps(report,indent=2))

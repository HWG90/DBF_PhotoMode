"""End-to-end check of the bundled WJL helper's start-up, under wine, without a game.

Runs the exact launcher wjl_helper_startup.lua builds through _popen, as io.popen does
against a stand-in game process whose image is <fake root>/bin/helldivers2.exe. Once that
process is running its file is swapped for a link to the real executable, so the helper's
stock-hash check sees the real game. The game never waits on the launcher; here _pclose
times how long cmd.exe runs it. Checks: readiness through --launch, the game root
resolved from --game-pid, the renderer-contract proof (valid, changed bundle, overriding
patch, valid again), the first pipe exchange the Lua side makes once the pipes exist, a
refused game (the Refused line the game's poll reads), and a helper EXE removed after it
was written, as antivirus does (cmd.exe returns; no dialog).
Needs wine and x86_64-w64-mingw32-gcc (test stand-ins only), lupa, and an installed
Helldivers 2 of the build the helper pins. Replaces the PowerShell-era
test_engine_render_contract.py."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,struct,subprocess,tempfile,time
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--game',type=Path,required=True,help='Helldivers 2 installation folder')
 parser.add_argument('--wine-prefix',type=Path,required=True,help='a disposable WINEPREFIX')
 args=parser.parse_args()
 env=dict(os.environ,WINEPREFIX=str(args.wine_prefix.resolve()),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
 wine=lambda *a,**k:subprocess.run(['wine',*a],env=env,capture_output=True,text=True,**k)
 drive_c=args.wine_prefix.resolve()/'drive_c'
 def unix(path):
  path=path.replace('\\','/')
  assert path[:2].upper()=='C:',path
  return str(drive_c)+path[2:]
 appdata=wine('cmd','/c','echo %APPDATA%').stdout.strip();localdata=wine('cmd','/c','echo %LOCALAPPDATA%').stdout.strip()
 assert appdata.upper().startswith('C:')and localdata.upper().startswith('C:'),(appdata,localdata)
 settings=Path(unix(appdata))/'Arrowhead/Helldivers2';settings.mkdir(parents=True,exist_ok=True)
 service_log=Path(unix(localdata))/'WJL/Helldivers2/Steam/service.log'
 results=[]
 with tempfile.TemporaryDirectory(prefix='wjl-launch-')as temporary:
  temporary=Path(temporary);probe=temporary/'probe.exe'
  subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-o',str(probe),str(ROOT/'tools/wjl_helper_probe/probe.c')],check=True)
  def fake_root(name,real):
   root=temporary/name;(root/'bin').mkdir(parents=True);(root/'data/game').mkdir(parents=True)
   shutil.copyfile(probe,root/'bin/helldivers2.exe')
   os.symlink(args.game/'data/game/game.dll',root/'data/game/game.dll')
   pid_file=temporary/(name+'.pid')
   process=subprocess.Popen(['wine',str(root/'bin/helldivers2.exe'),'sleep','Z:'+str(pid_file).replace('/','\\')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   for _ in range(200):
    if pid_file.exists()and pid_file.read_text():break
    time.sleep(.05)
   pid=int(pid_file.read_text())
   if real:(root/'bin/helldivers2.exe').unlink();os.symlink(args.game/'bin/helldivers2.exe',root/'bin/helldivers2.exe')
   return root,pid,process
  good,good_pid,good_process=fake_root('good',True)
  refused,refused_pid,refused_process=fake_root('refused',False)
  # Stock bundles and patches the contract reads; noise the scan must ignore.
  data=good/'data';index=b'index-v1';chunk=b'payload-v1'
  (data/'bundles.00.nxa').write_bytes(b'abc'+chunk)
  def patch(entries):return struct.pack('<III',0xf0000011,1,len(entries))+bytes(60)+bytes(32)+b''.join(struct.pack('<QQ',n,t)+bytes(64)for n,t in entries)
  (data/'9ba626afa44a3aa3.patch_0').write_bytes(patch([(0x9ba626afa44a3aa3,0xa14e8dfa2cd117e2)]))
  (data/'ee6b1ba7e22d71ed.patch_0.stream').write_bytes(b'not a patch header')
  lua=LuaRuntime(unpack_returned_tuples=True);g=lua.globals()
  old_open,old_remove=g.io.open,g.os.remove
  mapped=lambda path:unix(path)if isinstance(path,str)and path[:2].upper()=='C:'else path
  g.io.open=lambda path,mode='r':old_open(mapped(path),mode)
  g.os.remove=lambda path:old_remove(mapped(path))
  g.os.getenv=lambda name:{'APPDATA':appdata,'LOCALAPPDATA':localdata}.get(name)
  startup=lua.execute((ROOT/'freecam/wjl_helper_startup.lua').read_text())
  payload=lua.execute((ROOT/'freecam/wjl_helper_payload.lua').read_text())
  contract={'id':'b'*64,'resource':'ee6b1ba7e22d71ed','resource_type':'27862fe24795319c',
            'checks':[{'file':'bundles.nxa','offset':0,'size':len(index),'sha256':hashlib.sha256(index).hexdigest()},
                      {'file':'bundles.00.nxa','offset':3,'size':len(chunk),'sha256':hashlib.sha256(chunk).hexdigest()}]}
  def launch(pid):
   current=contract if not isinstance(contract,dict)else lua.table_from(contract,recursive=True)
   mod=lua.table_from({'require':lambda name:current if name=='src/engine_render_contract.lua'else payload})
   config=startup['config'](mod,lua.table_from({'Application':lua.table_from({'process_id':lambda:pid})}))
   assert 'powershell'not in config['launcher'].lower()
   command=temporary/'launcher.txt';command.write_bytes(config['launcher'].encode())
   outcome=temporary/'launcher.out'
   if outcome.exists():outcome.unlink()
   # The service outlives the launch and inherits wine's stdio, so never wait on a pipe.
   began=time.monotonic()
   subprocess.run(['wine',str(probe),'popen','Z:'+str(command).replace('/','\\'),'Z:'+str(outcome).replace('/','\\')],
                  env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
   return config,int(outcome.read_text()),time.monotonic()-began
  def finish(config):
   # The pipes appear once the service is ready; the game polls for them once a frame.
   reply=wine(str(probe),'client',config['pipe'],timeout=60)
   proof=bool(config['contract_ready']())
   for _ in range(200):
    if service_log.exists()and'service stopped'in service_log.read_text(errors='replace'):break
    time.sleep(.05)
   return json.loads(reply.stdout.strip().splitlines()[-1]),proof
  def logged(text,seconds=30):
   for _ in range(int(seconds/.05)):
    if service_log.exists()and text in service_log.read_text(errors='replace'):return True
    time.sleep(.05)
   return False
  windows_root='Z:'+str(good).replace('/','\\')
  for scenario in ['valid','changed-index','renderer-override','valid-again']:
   (data/'bundles.nxa').write_bytes(index if scenario!='changed-index'else b'changed!')
   override=data/'ee6b1ba7e22d71ed.patch_99'
   if override.exists():override.unlink()
   if scenario=='renderer-override':override.write_bytes(patch([(0xee6b1ba7e22d71ed,0x27862fe24795319c)]))
   config,code,elapsed=launch(good_pid)
   reply,proof=finish(config)
   log=service_log.read_text(errors='replace')
   assert proof==(scenario in('valid','valid-again')),(scenario,log)
   assert reply['connected']and reply['nonce']==0 and reply['status']==0,(scenario,reply,log)
   assert reply['root'].lower()==windows_root.replace('\\','/').lower(),(reply['root'],windows_root)
   assert reply['exe'].lower().endswith('/bin/helldivers2.exe')
   results.append({'scenario':scenario,'ready':True,'renderer_proof':proof,'launch_seconds':round(elapsed,3),'root_resolved':reply['root']})
  # The shipped contract against the real installation (its bundles and deployed patches),
  # compared with the PowerShell check this replaces, ported line for line.
  real=lua.execute((ROOT/'freecam/engine_render_contract.lua').read_text())
  def powershell_verdict(data):
   for row in real['checks'].values():
    path=data/row['file']
    if not path.is_file()or row['offset']+row['size']>path.stat().st_size:return False
    with open(path,'rb')as f:f.seek(int(row['offset']));body=f.read(int(row['size']))
    if hashlib.sha256(body).hexdigest()!=row['sha256']:return False
   import re
   patches=[p for p in data.glob('*.patch_*')if re.fullmatch(r'[a-fA-F0-9]{16}\.patch_\d+',p.name)]
   if len(patches)>128:return False
   total=0
   for p in patches:
    with open(p,'rb')as f:
     head=f.read(72)
     if len(head)!=72 or struct.unpack_from('<I',head)[0]!=0xf0000011:return False
     types,entries=struct.unpack_from('<II',head,4);total+=entries
     if types>128 or entries>4096 or total>8192 or 72+32*types+80*entries>p.stat().st_size:return False
     f.seek(72+32*types)
     for _ in range(entries):
      name,kind=struct.unpack('<QQ',f.read(16));f.read(64)
      if name==int(real['resource'],16)and kind==int(real['resource_type'],16):return False
   return True
  stock=temporary/'stock';(stock/'bin').mkdir(parents=True);os.symlink(args.game/'data',stock/'data')
  shutil.copyfile(probe,stock/'bin/helldivers2.exe');pid_file=temporary/'stock.pid'
  stock_process=subprocess.Popen(['wine',str(stock/'bin/helldivers2.exe'),'sleep','Z:'+str(pid_file).replace('/','\\')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  for _ in range(200):
   if pid_file.exists()and pid_file.read_text():break
   time.sleep(.05)
  (stock/'bin/helldivers2.exe').unlink();os.symlink(args.game/'bin/helldivers2.exe',stock/'bin/helldivers2.exe')
  contract=real
  config,code,elapsed=launch(int(pid_file.read_text()))
  reply,proof=finish(config);expected=powershell_verdict(args.game/'data')
  assert reply['status']==0 and proof==expected,(code,proof,expected,service_log.read_text(errors='replace'))
  results.append({'scenario':'stock-install','ready':True,'renderer_proof':proof,'matches_powershell_check':True,'launch_seconds':round(elapsed,3)})
  stock_process.kill();stock_process.wait()
  # A game whose executable differs from the pinned build: cmd.exe returns and the helper's
  # log says Refused, which is what the game's poll reads to stop waiting.
  config,code,elapsed=launch(refused_pid)
  assert logged('Refused: installed game hashes do not match'),service_log.read_text(errors='replace')if service_log.exists()else'no log'
  log=service_log.read_text(errors='replace')
  assert not config['contract_ready']()and config['failure']().startswith('Refused'),config['failure']()
  results.append({'scenario':'unsupported-game','ready':False,'launch_seconds':round(elapsed,3),'reported':log.strip().splitlines()[-1]})
  # PNG screenshots: the engine's DDS, written beside the requested PNG, converted by the
  # helper's screenshot job (SDR BGRA8 and HDR10 RGB10A2), as Photo Mode asks for it.
  shots_dir=Path(unix(localdata))/'WJL/Helldivers2/Screenshots';windows_shots=localdata+'\\WJL\\Helldivers2\\Screenshots'
  exe=good/'bin/helldivers2.exe'
  def dds(width,height,fmt,pixels):
   head=bytearray(148);struct.pack_into('<4sIIIIIII',head,0,b'DDS ',124,0x100f,height,width,width*4,0,1)
   struct.pack_into('<II4s',head,76,32,4,b'DX10');struct.pack_into('<I',head,108,0x1000)
   struct.pack_into('<IIIII',head,128,fmt,3,0,1,0)
   return bytes(head)+b''.join(struct.pack('<I',p)for p in pixels)
  def png_pixels(data):
   import zlib
   assert data[:8]==b'\x89PNG\r\n\x1a\n';at,idat,ihdr=8,b'',None
   while at<len(data):
    size,kind=struct.unpack('>I4s',data[at:at+8]);body=data[at+8:at+8+size];at+=12+size
    if kind==b'IHDR':ihdr=struct.unpack('>IIBBBBB',body)
    elif kind==b'IDAT':idat+=body
   width,height,depth,color=ihdr[:4];assert depth==8 and color in(2,6),ihdr
   step=4 if color==6 else 3;raw=zlib.decompress(idat);rows,previous=[],bytearray(width*step);pos=0
   for _ in range(height):
    kind=raw[pos];line=bytearray(raw[pos+1:pos+1+width*step]);pos+=1+width*step
    for i in range(len(line)):
     a=line[i-step]if i>=step else 0;b=previous[i];c=previous[i-step]if i>=step else 0
     p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
     line[i]=(line[i]+(0,a,b,(a+b)//2,a if pa<=pb and pa<=pc else b if pb<=pc else c)[kind])&255
    rows.append([tuple(line[i:i+3])for i in range(0,len(line),step)]);previous=line
   return width,height,rows
  def pq(code):
   m1,m2,c1,c2,c3=2610/16384,2523/32,3424/4096,2413/128,2392/128;p=(code/1023)**(1/m2)
   return 10000*(max(p-c1,0)/(c2-c3*p))**(1/m1)
  def native_sdr(r,g,b):
   mul=lambda m,v:[m[i][0]*v[0]+m[i][1]*v[1]+m[i][2]*v[2]for i in range(3)]
   pre=[[0.9599400162696838,0.010470000095665455,0.007029999978840351],[0.0016199999954551458,0.9996899962425232,0.0014900000533089042],[0.005289999768137932,0.023830000311136246,1.0501600503921509]]
   xyz=[[0.6624541878700256,0.13400420546531677,0.15618768334388733],[0.2722287178039551,0.6740817427635193,0.053689517080783844],[-0.005574649665504694,0.00406073359772563,1.0103391408920288]]
   adapt=[[1.6410233974456787,-0.32480329275131226,-0.23642469942569733],[-0.663662850856781,1.6153316497802734,0.016756348311901093],[0.011721894145011902,-0.008284442126750946,0.9883948564529419]]
   rgb=[[3.2409698963165283,-1.5373831987380981,-0.4986107647418976],[-0.9692436456680298,1.8759675025939941,0.04155505821108818],[0.05563008040189743,-0.20397695899009705,1.056971549987793]]
   v=[(x-0.001)*0.0036363769322633743 for x in mul(pre,[r,g,b])];v=mul(xyz,v);s=max(sum(v),0.0001);x,y=v[0]/s,v[1]/s
   lum=min(max(v[1],0),65504)**0.9811000227928162;ratio=lum/max(y,0.0001)
   v=mul(rgb,mul(xyz,mul(adapt,[ratio*x,lum,ratio*(1-x-y)])))
   return tuple(int(min(max(c,0),1)**0.4544999897480011*255+0.5)for c in v)
  sdr=[0xff102030,0xff405060,0xffffffff,0xff000000,0x80ff0000,0xff00ff00,0xff0000ff,0xff7f7f7f]
  hdr=[(r|g<<10|b<<20|3<<30)for r,g,b in((0,0,0),(512,512,512),(768,300,100),(1023,1023,1023),(400,600,200),(100,100,900),(520,520,520),(650,0,0))]
  for name,fmt,pixels,expect in(('sdr',87,sdr,lambda p:((p>>16)&255,(p>>8)&255,p&255)),
                               ('hdr10',24,hdr,lambda p:native_sdr(pq(p&1023),pq((p>>10)&1023),pq((p>>20)&1023)))):
   if not exe.is_symlink():exe.unlink();os.symlink(args.game/'bin/helldivers2.exe',exe)
   config,code,elapsed=launch(good_pid)
   assert logged('awaiting local Lua filesystem client'),service_log.read_text(errors='replace')
   assert shots_dir.is_dir(),'The helper creates its Screenshots folder at start'
   stem='War-Journalist-20261027-200000-1-'+name
   (shots_dir/(stem+'.dds')).write_bytes(dds(4,2,fmt,pixels))
   # The job admits only the game's own process: the client runs from the game's path.
   exe.unlink();shutil.copyfile(probe,exe)
   out=wine(str(exe),'shot',config['pipe'],windows_shots+'\\'+stem+'.png',timeout=60)
   job=json.loads(out.stdout.strip().splitlines()[-1])
   assert job.get('state')==2 and job['error']==0 and(job['width'],job['height'])==(4,2),(name,job,service_log.read_text(errors='replace'))
   width,height,rows=png_pixels((shots_dir/(stem+'.png')).read_bytes())
   got=[px for row in rows for px in row];want=[expect(p)for p in pixels]
   assert(width,height)==(4,2)and all(abs(a-b)<=1 for g,w in zip(got,want)for a,b in zip(g,w)),(name,got,want)
   assert(shots_dir/(stem+'.dds')).is_file(),'The helper leaves the DDS to Photo Mode'
   results.append({'scenario':'png-from-'+name,'state':'succeeded','elapsed_ms':job['elapsed_ms'],'pixels_match':True})
   for _ in range(200):
    if'service stopped'in service_log.read_text(errors='replace'):break
    time.sleep(.05)
  if not exe.is_symlink():exe.unlink();os.symlink(args.game/'bin/helldivers2.exe',exe)
  # The helper EXE removed after it was written (as antivirus does): cmd.exe prints an
  # error and returns. start would have shown a dialog and waited on it.
  def missing_launch():
   current=lua.table_from(contract,recursive=True)if isinstance(contract,dict)else contract
   mod=lua.table_from({'require':lambda name:current if name=='src/engine_render_contract.lua'else payload})
   made=startup['config'](mod,lua.table_from({'Application':lua.table_from({'process_id':lambda:good_pid})}))
   (settings/payload['name']).unlink()
   command=temporary/'launcher.txt';command.write_bytes(made['launcher'].encode())
   outcome=temporary/'launcher.out'
   if outcome.exists():outcome.unlink()
   began=time.monotonic()
   subprocess.run(['wine',str(probe),'popen','Z:'+str(command).replace('/','\\'),'Z:'+str(outcome).replace('/','\\')],
                  env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
   return made,int(outcome.read_text()),time.monotonic()-began
  config,code,elapsed=missing_launch()
  assert code!=0 and not service_log.exists()and config['failure']()=='No WJL helper log written',(code,config['failure']())
  results.append({'scenario':'helper-removed','ready':False,'cmd_exit':code,'launch_seconds':round(elapsed,3)})
  for process in(good_process,refused_process):process.kill();process.wait()
 return {'passed':True,'helper':lua.execute((ROOT/'freecam/wjl_helper_payload.lua').read_text())['name'],'cases':results,'powershell':False}

if __name__=='__main__':
 r=main();out=ROOT/'dist/review/windows-wjl-helper/LAUNCH-TESTS.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

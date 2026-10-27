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

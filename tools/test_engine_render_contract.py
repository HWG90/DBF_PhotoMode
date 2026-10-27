"""Windows-only integration checks for WJL's read-only stock graph witness."""
from pathlib import Path
import base64,hashlib,json,os,struct,subprocess,tempfile
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

def literal(value):return "'"+str(value).replace("'","''")+"'"
def run():
 with tempfile.TemporaryDirectory(prefix='wjl-render-contract-')as temporary:
  root=Path(temporary);user=root/'user';settings=user/'Arrowhead/Helldivers2';settings.mkdir(parents=True);data=root/'data';data.mkdir()
  index=b'index-v1';chunk=b'payload-v1';(data/'bundles.nxa').write_bytes(index);(data/'bundles.00.nxa').write_bytes(b'abc'+chunk)
  contract={'id':'b'*64,'checks':[{'file':'bundles.nxa','offset':0,'size':len(index),'sha256':hashlib.sha256(index).hexdigest()},{'file':'bundles.00.nxa','offset':3,'size':len(chunk),'sha256':hashlib.sha256(chunk).hexdigest()}]}
  lua=LuaRuntime();lua.globals().os.getenv=lambda name:str(user)if name=='APPDATA'else os.environ.get(name)
  module=lua.execute((ROOT/'freecam/wjl_helper_startup.lua').read_text())
  payload={'name':'wjl_steam_service_0123456789abcdef.exe','sha256':'a'*64,'hex':'4d5a0102'}
  def require(name):return lua.table_from(contract if name=='src/engine_render_contract.lua'else payload,recursive=True)
  mod=lua.table_from({'require':require});sr=lua.table_from({'Application':lua.table_from({'process_id':lambda:1234})})
  results=[]
  for scenario in ['valid','changed-index','renderer-override','valid-again']:
   (data/'bundles.nxa').write_bytes(index if scenario!='changed-index'else b'changed!')
   override=data/'ee6b1ba7e22d71ed.patch_99'
   if override.exists():override.unlink()
   if scenario=='renderer-override':
    head=struct.pack('<III',0xf0000011,1,1)+bytes(60)
    override.write_bytes(head+bytes(32)+struct.pack('<QQ',0xee6b1ba7e22d71ed,0x27862fe24795319c)+bytes(64))
   config=module['config'](mod,sr);script=Path(config['startup_script']).read_text();begin=script.index(' try {\n  $proof=');end=script.index(' $arguments=')
   block=script[begin:end];assert 'Start-Process'not in block and 'save_render_target'not in block
   prefix="$ErrorActionPreference='Stop';$env:PSModulePath=[IO.Path]::Combine($PSHOME,'Modules')+';'+$env:PSModulePath; $root="+literal(root)+"; $env:APPDATA="+literal(user)+"; $log="+literal(root/'probe.log')+"\n"
   command=base64.b64encode((prefix+block).encode('utf-16le')).decode()
   result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-EncodedCommand',command],capture_output=True,text=True,timeout=20)
   assert result.returncode==0,result.stderr
   witness=settings/'wjl-render-contract-1234.txt';present=witness.exists()
   assert present==(scenario in ['valid','valid-again']),(scenario,(root/'probe.log').read_text())
   if present:assert witness.read_text()==contract['id']+'|'+config['pipe']
   results.append({'scenario':scenario,'witness_written':present,'exit_code':result.returncode})
   Path(config['startup_script']).unlink()
  # Exercise the exact short _popen bootstrap with an owned harmless script.
  config=module['config'](mod,sr);assert len(config['launcher'])<4096
  marker=root/'bootstrap-ok.txt';Path(config['startup_script']).write_text('[IO.File]::WriteAllText('+literal(marker)+",'ok');exit 0")
  previous=os.environ.get('APPDATA');os.environ['APPDATA']=str(user)
  try:
   lua.globals().launcher=config['launcher'];lua.execute("local p=assert(io.popen(launcher,'r'));p:close()")
  finally:
   if previous is None:os.environ.pop('APPDATA',None)
   else:os.environ['APPDATA']=previous
  assert marker.read_text()=='ok'and not Path(config['startup_script']).exists(),'Bootstrap must run and remove its generated script'
  return {'passed':True,'cases':results,'short_popen_bootstrap':True,'command_chars':len(config['launcher']),'game_process_or_gpu_touched':False}
if __name__=='__main__':
 r=run();out=ROOT/'dist/review/windows-color-contract/INTEGRATION-TESTS.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

"""Start the pinned external WJL input helper for the BML adapter; match an elevated Steam launch when requested."""
import ctypes,hashlib,json,os,subprocess,time,uuid
from pathlib import Path
from ctypes import wintypes

def start(elevated=False):
    base=Path(os.environ['LOCALAPPDATA'])/'WJL/Helldivers2/Service'
    owner=json.loads((base/'game-root.json').read_text(encoding='utf-8-sig'))
    helper=Path(os.environ['LOCALAPPDATA'])/'WJL/Helldivers2/Service'/'wjl_steam_service_28af6b376f6afcb8.exe'
    expected='28af6b376f6afcb89c5edc480ef0bbb5019cdd425bffde929509680a2397c292'
    assert hashlib.sha256(helper.read_bytes()).hexdigest()==expected,'External helper hash mismatch'
    root=Path(owner['game_root']).resolve(strict=True)
    assert (root/'bin/helldivers2.exe').is_file()
    token='wjl_input_'+uuid.uuid4().hex
    arguments=[str(helper),'--game',str(root),'--pipe',token]
    if elevated:
        # Windows presents UAC; no credential or integrity-policy changes.
        import base64
        def literal(value):return "'"+value.replace("'","''")+"'"
        command="$ErrorActionPreference='Stop'; $p=Start-Process -FilePath "+literal(str(helper))+" -ArgumentList "+literal(subprocess.list2cmdline(arguments[1:]))+" -Verb RunAs -WindowStyle Hidden -PassThru; $p.Id"
        encoded=base64.b64encode(command.encode('utf-16le')).decode('ascii')
        launched=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-EncodedCommand',encoded],creationflags=subprocess.CREATE_NO_WINDOW,capture_output=True,text=True,check=True,timeout=120)
        pid=int(launched.stdout.strip())
        class ElevatedChild:
            def __init__(self,pid):
                self.pid=pid
                self.api=ctypes.WinDLL('kernel32',use_last_error=True)
                self.api.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];self.api.OpenProcess.restype=wintypes.HANDLE
                self.api.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD]
                self.api.CloseHandle.argtypes=[wintypes.HANDLE]
                self.handle=self.api.OpenProcess(0x101000,False,pid)
                if not self.handle:raise ctypes.WinError(ctypes.get_last_error())
            def poll(self):return None if self.api.WaitForSingleObject(self.handle,0)==258 else 1
            def terminate(self):pass # Retain elevated child ownership; startup timeout is bounded in the helper.
            def wait(self,timeout=None):return self.poll()
            def __del__(self):
                if getattr(self,'handle',None):self.api.CloseHandle(self.handle)
        proc=ElevatedChild(pid)
    else:
        proc=subprocess.Popen(arguments,creationflags=subprocess.CREATE_NO_WINDOW,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.OpenEventW.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.LPCWSTR];kernel.OpenEventW.restype=wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD];kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    ready=False
    # Startup-only bound: service owns the event; no pipe client impersonation/probing.
    for _ in range(100):
        if proc.poll() is not None:break
        event=kernel.OpenEventW(0x100000,False,'Local\\WJL_Steam_Ready_'+token)
        if event:
            ready=kernel.WaitForSingleObject(event,0)==0;kernel.CloseHandle(event)
            if ready:break
        time.sleep(.1)
    if not ready:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=5)
        raise RuntimeError('Input service did not signal readiness; inspect WJL/Helldivers2/Steam/service.log or existing service ownership')
    folder=Path(os.environ['APPDATA'])/'Arrowhead/Helldivers2'
    config=folder/'war-journalist-input.pipe'
    temporary=config.with_suffix('.tmp');temporary.write_text(token,encoding='ascii');temporary.replace(config)
    return {'pid':proc.pid,'pipe':token,'helper':str(helper),'sha256':expected,'game_root':str(root),'ready':True,'elevated_requested':elevated,'gameplay_verified':False}
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--elevated',action='store_true');args=parser.parse_args()
    print(json.dumps(start(elevated=args.elevated),indent=2))

"""Rebuild the typed Lua5.1 scene/depth bridge with Zig; emits a hashed local DLL."""
from pathlib import Path
import subprocess,shutil,argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--zig',default=shutil.which('zig'));p.add_argument('--output',type=Path,default=ROOT/'dist/review/native-scene');a=p.parse_args();assert a.zig,'Pass --zig /path/to/zig'
src=ROOT/'freecam/native/port51_src';a.output.mkdir(parents=True,exist_ok=True);dll=a.output/'hd2_nativeinfo.dll'
subprocess.run([a.zig,'c++','-target','x86_64-windows-gnu','-shared','-O2','-std=c++14','-fno-exceptions','-fno-rtti','-I'+str(src),str(src/'scene_nativeinfo.cc'),'-lbcrypt','-o',str(dll)],check=True)
h=hashlib.sha256(dll.read_bytes()).hexdigest();out=a.output/('hd2_nativeinfo_'+h[:16]+'.dll');out.write_bytes(dll.read_bytes());print(json.dumps({'file':str(out),'sha256':h,'deployed':False},indent=2))

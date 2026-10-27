-- One-shot helper extraction/startup. Child inherits the game's integrity level.
local M={}
local launch_sequence=0
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(s)
 local out={}
 for i=1,#s,3 do
  local a,b,c=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or'=')..(c and alphabet:sub(n%64+1,n%64+1)or'=')
 end
 return table.concat(out)
end
function M.config(mod,sr)
 local payload=mod.require('src/wjl_helper_payload.lua')
 assert(payload.name:match('^wjl_steam_service_%x+%.exe$')and payload.sha256:match('^%x+$')and #payload.sha256==64)
 local directory=assert(os.getenv('APPDATA'))..'/Arrowhead/Helldivers2/'
 local path=directory..payload.name
 local bytes=payload.hex:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
 local existing=io.open(path,'rb')
 if existing then local body=existing:read('*a');existing:close();assert(body==bytes,'Bundled WJL helper cache differs; refusing to execute')
 else local file=assert(io.open(path,'wb'));assert(file:write(bytes));assert(file:close())end
 local pid=sr.Application.process_id();assert(type(pid)=='number'and pid>0 and pid==math.floor(pid))
 launch_sequence=launch_sequence+1
 local token='wjl_input_'..pid..'_'..os.time()..'_'..launch_sequence
 local contract=mod.require('src/engine_render_contract.lua')
 assert(type(contract.id)=='string'and #contract.id==64 and contract.id:match('^%x+$'),'Invalid render contract identity')
 assert(type(contract.checks)=='table'and #contract.checks>0 and #contract.checks<=32,'Invalid render contract checks')
 local checks,total={},0
 for _,row in ipairs(contract.checks)do
  assert(type(row.file)=='string'and(row.file=='bundles.nxa'or row.file:match('^bundles%.%d+%.nxa$')),'Invalid stock witness path')
  assert(type(row.offset)=='number'and row.offset>=0 and row.offset==math.floor(row.offset)and row.offset<2^53,'Invalid stock witness offset')
  assert(type(row.size)=='number'and row.size>0 and row.size==math.floor(row.size)and row.size<=16*1024*1024,'Invalid stock witness size')
  assert(type(row.sha256)=='string'and #row.sha256==64 and row.sha256:match('^%x+$'),'Invalid stock witness hash')
  total=total+row.size
  checks[#checks+1]="@{file='"..row.file.."';offset=[int64]"..string.format('%.0f',row.offset)..";size="..row.size..";hash='"..row.sha256.."'}"
 end
 assert(total<=16*1024*1024,'Stock renderer verification exceeds its read budget')
 local witness=contract.id..'|'..token
 local script=[[$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; $ready=$null
$env:PSModulePath=[IO.Path]::Combine($PSHOME,'Modules')+';'+$env:PSModulePath
$log=Join-Path $env:APPDATA 'Arrowhead\Helldivers2\wjl_startup.log'
[IO.File]::WriteAllText($log,'WJL automatic startup'+[Environment]::NewLine)
try {
 $service=Join-Path $env:APPDATA 'Arrowhead\Helldivers2\HELPER_NAME'
 $algorithm=[Security.Cryptography.SHA256]::Create()
 $stream=[IO.File]::OpenRead($service)
 try {$hash=[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}
 finally {$stream.Dispose();$algorithm.Dispose()}
 if($hash -ne 'HELPER_HASH'){throw 'WJL helper hash mismatch'}
 Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WjlGamePath {
 [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint size);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 public static string Read(uint pid) {
  IntPtr h=OpenProcess(0x1000,false,pid);
  if(h==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  try {uint size=32768;var text=new StringBuilder((int)size);
   if(!QueryFullProcessImageName(h,0,text,ref size))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   return text.ToString();
  }finally{CloseHandle(h);}
 }
}
'@
 $game=[WjlGamePath]::Read(GAME_PID)
 if(-not $game){throw 'Game executable path unavailable'}
 [IO.File]::AppendAllText($log,'Game path resolved with query-only access'+[Environment]::NewLine)
 $root=Split-Path (Split-Path $game -Parent) -Parent
 try {
  $proof=[IO.Path]::Combine($env:APPDATA,'Arrowhead\Helldivers2\wjl-render-contract-GAME_PID.txt')
  if([IO.File]::Exists($proof)){[IO.File]::Delete($proof)}
  $data=[IO.Path]::Combine($root,'data')
  $checks=@(CONTRACT_CHECKS)
  foreach($check in $checks){
   $file=[IO.File]::OpenRead([IO.Path]::Combine($data,$check.file))
   try {
    if($check.offset+$check.size -gt $file.Length){throw 'Renderer witness range differs'}
    [void]$file.Seek($check.offset,[IO.SeekOrigin]::Begin)
    $reader=[IO.BinaryReader]::new($file)
    $bytes=$reader.ReadBytes($check.size)
    if($bytes.Length -ne $check.size){throw 'Renderer witness truncated'}
    $hash=[Security.Cryptography.SHA256]::Create()
    try {$actual=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
    if($actual -ne $check.hash){throw 'Stock renderer data differs'}
   } finally {$file.Dispose()}
  }
  $patches=@([IO.Directory]::GetFiles($data,'*.patch_*') | Where-Object {[IO.Path]::GetFileName($_) -match '^[a-f0-9]{16}\.patch_\d+$'})
  if($patches.Count -gt 128){throw 'Patch inventory exceeds renderer verification budget'}
  $totalEntries=0
  foreach($patch in $patches){
   $file=[IO.File]::OpenRead($patch)
   try {
    $reader=[IO.BinaryReader]::new($file)
    $head=$reader.ReadBytes(72)
    if($head.Length -ne 72 -or [BitConverter]::ToUInt32($head,0) -ne [Convert]::ToUInt32('f0000011',16)){throw 'Patch header unavailable'}
    $types=[BitConverter]::ToUInt32($head,4);$entries=[BitConverter]::ToUInt32($head,8);$totalEntries+=$entries
    if($types -gt 128 -or $entries -gt 4096 -or $totalEntries -gt 8192){throw 'Patch table exceeds renderer verification budget'}
    if(72+32*$types+80*$entries -gt $file.Length){throw 'Patch resource table truncated'}
    [void]$file.Seek(72+32*$types,[IO.SeekOrigin]::Begin)
    for($i=0;$i -lt $entries;$i++){
     $name=$reader.ReadUInt64();$type=$reader.ReadUInt64()
     if($name -eq [Convert]::ToUInt64('ee6b1ba7e22d71ed',16) -and $type -eq [Convert]::ToUInt64('27862fe24795319c',16)){throw 'Another patch overrides the stock renderer'}
     [void]$file.Seek(64,[IO.SeekOrigin]::Current)
    }
   } finally {$file.Dispose()}
  }
  [IO.File]::WriteAllText($proof,'CONTRACT_WITNESS')
  [IO.File]::AppendAllText($log,'Stock renderer contract verified without GPU readback'+[Environment]::NewLine)
 } catch {[IO.File]::AppendAllText($log,'Scene backend unavailable: '+$_+[Environment]::NewLine)}
 $arguments='--game "'+$root+'" --pipe PIPE_TOKEN'
 $child=Start-Process -FilePath $service -ArgumentList $arguments -WindowStyle Hidden -PassThru
 $timer=[Diagnostics.Stopwatch]::StartNew()
 while($timer.ElapsedMilliseconds -lt 8000){
  if($child.HasExited){throw 'WJL helper exited during startup'}
  try {$ready=[Threading.EventWaitHandle]::OpenExisting('Local\WJL_Steam_Ready_PIPE_TOKEN')}catch{}
  if($ready -and $ready.WaitOne(0)){[IO.File]::AppendAllText($log,'Helper ready; pid='+$child.Id+[Environment]::NewLine);exit 0}
  Start-Sleep -Milliseconds 50
 }
 throw 'WJL helper readiness timeout'
} catch {[IO.File]::AppendAllText($log,($_|Out-String));exit 1} finally {if($ready){$ready.Dispose()}}
]]
 script=script:gsub('CONTRACT_CHECKS',function()return table.concat(checks,',')end):gsub('CONTRACT_WITNESS',witness)
 script=script:gsub('HELPER_NAME',payload.name):gsub('HELPER_HASH',payload.sha256):gsub('GAME_PID',tostring(pid)):gsub('PIPE_TOKEN',token)
 -- _popen uses cmd.exe, whose command-line limit is smaller than CreateProcess.
 -- Keep only a short bootstrap on that command line; the generated local script
 -- is consumed and removed by the startup process. No execution policy changes.
 local leaf='wjl-startup-'..pid..'-'..launch_sequence..'.ps1'
 local script_path=directory..leaf
 local file=assert(io.open(script_path,'wb'));assert(file:write(script));assert(file:close())
 local bootstrap="$p=[IO.Path]::Combine($env:APPDATA,'Arrowhead\\Helldivers2\\"..leaf.."');try {& ([ScriptBlock]::Create([IO.File]::ReadAllText($p)))} finally {[IO.File]::Delete($p)}"
 local encoded=base64((bootstrap:gsub('.',function(c)return c..'\0'end)))
 return {pipe=token,contract_id=contract.id,startup_script=script_path,launcher='powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -EncodedCommand '..encoded,
  contract_ready=function()local f=io.open(directory..'wjl-render-contract-'..pid..'.txt','rb');if not f then return false end;local body=f:read(256);f:close();return body==witness end,
  failure=function()local f=io.open(directory..'wjl_startup.log','rb');if not f then return 'No startup log written'end;local body=f:read(4096);f:close();return body end}
end
return M

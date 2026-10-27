-- Screenshots on the Windows build: PNGs from WJL while it can make them, else the
-- engine's own DDS. WJL captures the game window with Windows Graphics Capture and writes
-- the PNG outside the game. That capture is SDR only (it refuses an HDR display), needs
-- Windows 10 1903 or later, and is missing under Wine. The format is chosen per shot
-- through `extension`, which the runtime reads when it names the file. HDR at start, a
-- refusal that will not change, or two failed PNGs in a row switch the session to DDS.
local M={}
-- Window errors that may pass: geometry changed (ERROR_RETRY), timed out, cancelled, the
-- window lost or not foreground. Any other failure will not pass by retrying.
M.transient={[1237]=true,[1460]=true,[1223]=true,[1400]=true}
function M.new(png,dds,hdr,log)
 assert(type(png)=='table'and type(dds)=='table'and png.output_directory:lower()==dds.output_directory:lower(),'PNG and DDS share one folder')
 local self={version=1,output_directory=dds.output_directory,extension='png',
  capabilities={async=true,game_window=true,format='png',color_space='sdr',max_jobs=1}}
 local failures=0
 local function use_dds(why)
  if self.extension=='dds'then return end
  self.extension='dds'
  if log then log('PNG screenshots unavailable ('..tostring(why)..'); saving DDS from now on')end
 end
 if hdr then use_dds('HDR is on')end
 local serial,issued,current=0,nil,nil
 -- One outcome per PNG job: success clears the count; a failure that will not pass, or
 -- the second in a row, switches to DDS.
 local function outcome(state,why)
  if current.counted or current.backend~=png then return end
  if state=='succeeded'then current.counted=true;failures=0;return end
  if state~='failed'then return end
  current.counted=true;failures=failures+1
  local code=tonumber(tostring(why or''):match('0x(%x+)')or'',16)
  if not(code and M.transient[code])or failures>=2 then use_dds(why)end
 end
 local function outer(record)
  if type(record)~='table'then return record end
  local copy={};for k,v in pairs(record)do copy[k]=v end
  if copy.job_token==current.inner then copy.job_token=current.job end
  if not copy.uncertain then outcome(copy.state,copy.reason)end
  return copy
 end
 function self.new_job_token()serial=serial+1;issued='windows-shot:'..serial;return issued end
 function self.request(intent)
  if type(intent)~='table'or not issued or intent.job_token~=issued then return nil,'Latest unused screenshot token required'end
  issued=nil
  local name=type(intent.output_token)=='string'and intent.output_token:lower()or''
  local backend=name:match('%.png$')and png or name:match('%.dds$')and dds
  if not backend then return nil,'Screenshot format unavailable'end
  local inner,why=backend.new_job_token();if not inner then return nil,why end
  local copy={};for k,v in pairs(intent)do copy[k]=v end;copy.job_token=inner
  current={backend=backend,job=intent.job_token,inner=inner}
  local record;record,why=backend.request(copy)
  if not record then
   outcome('failed',why)
   current=nil;return record,why
  end
  return outer(record)
 end
 function self.status(job,output_token)
  assert(current and current.job==job,'Screenshot job identity differs')
  return outer(current.backend.status(current.inner,output_token))
 end
 function self.cancel(job,output_token)
  assert(current and current.job==job,'Screenshot job identity differs')
  local done,record,why=current.backend.cancel(current.inner,output_token)
  return done,outer(record),why
 end
 return self
end
return M

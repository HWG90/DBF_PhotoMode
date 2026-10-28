-- Screenshots on the Windows build: the engine writes its own DDS, which works on every PC,
-- and WJL converts it to a PNG outside the game, SDR and HDR10 alike (DBF_PhotoMode's 0.9.x
-- converter, now inside the helper). WJL's jobs accept only its own Screenshots folder, so
-- the DDS is written there and the finished PNG is moved to the screenshot folder. An SDR
-- DDS is then removed; an HDR10 one is kept beside its PNG. A shot WJL cannot convert keeps
-- its DDS in the screenshot folder instead, and the log says why.
local M={}
local function le32(s,o)local a,b,c,d=s:byte(o+1,o+4);if not d then return nil end;return a+b*256+c*65536+d*16777216 end
-- engine: an engine_capture writing into staging. platform: the WJL adapter (now,
-- screenshot_request/status/cancel). staging: WJL's Screenshots folder, as Windows spells it.
function M.new(engine,platform,staging,output,log,fs)
 fs=fs or{open=io.open,rename=os.rename,remove=os.remove}
 output=output:gsub('[/\\]+$','');staging=staging:gsub('/','\\'):gsub('\\+$','')
 local self={version=1,output_directory=output,extension='png',
  capabilities={async=true,game_window=false,format='png',color_space='sdr',max_jobs=1}}
 local serial,issued,current=0,nil,nil
 local function record(state,reason)
  current.state,current.reason=state,reason
  return{job_token=current.job_token,output_token=current.output_token,output_path=current.output_path,state=state,reason=reason}
 end
 local function exists(path)local f=fs.open(path,'rb');if f then f:close();return true end;return false end
 -- Rename, or copy then remove across volumes. Never replaces a file.
 local function move(from,to)
  if exists(to)then return false end
  if fs.rename(from,to)then return true end
  local input=fs.open(from,'rb');if not input then return false end
  local body=input:read('*a');input:close()
  local out=fs.open(to,'wb');if not out then return false end
  local written=out:write(body);out:close()
  if not written then fs.remove(to);return false end
  fs.remove(from);return true
 end
 -- The shot WJL could not convert: its DDS goes where the PNG would have.
 local function keep_dds(state,why)
  local kept=output..'/'..current.stem..'.dds'
  local moved=move(current.staged_dds,kept)
  local reason=tostring(why)..(moved and'; DDS saved: '..kept or'; DDS left in '..staging)
  if log then log('PNG screenshot unavailable: '..reason)end
  return record(state,reason)
 end
 local function finish(reply)
  if reply.state=='pending'then return record('pending')end
  if reply.state~='succeeded'then
   return keep_dds(reply.state=='cancelled'and'cancelled'or'failed',string.format('PNG conversion %s (0x%08x)',reply.state,reply.error or 0))
  end
  if not move(current.staged_png,current.output_path)then
   if log then log('PNG screenshot could not be moved from '..staging)end
   return record('failed','PNG written but not moved: '..current.staged_png)
  end
  if current.hdr then move(current.staged_dds,output..'/'..current.stem..'.dds')else fs.remove(current.staged_dds)end
  return record('succeeded')
 end
 function self.new_job_token()serial=serial+1;issued='windows-shot:'..serial;return issued end
 function self.request(intent)
  if type(intent)~='table'or not issued or intent.job_token~=issued then return nil,'Latest unused screenshot token required'end
  local name=intent.output_token
  if type(name)~='string'or#name>128 or not name:match('^War%-Journalist%-%w[%w_-]*%.png$')or intent.output_path~=output..'/'..name then
   return nil,'Screenshot output identity differs'
  end
  if exists(intent.output_path)then return nil,'Screenshot output already exists'end
  issued=nil
  local stem=name:sub(1,-5)
  current={job_token=intent.job_token,output_token=name,output_path=intent.output_path,stem=stem,
   staged_dds=staging..'\\'..stem..'.dds',staged_png=staging..'\\'..stem..'.png'}
  -- The engine writes now, on the clean frame the coordinator waited for.
  local inner,why=engine.new_job_token();if not inner then return record('failed',why)end
  local written;written,why=engine.request({job_token=inner,output_token=stem..'.dds',output_path=engine.output_directory..'/'..stem..'.dds'})
  if not written then return record('failed',why)end
  if written.state~='succeeded'then return record('failed',written.reason)end
  local file=fs.open(current.staged_dds,'rb')
  if file then file:seek('set',128);current.hdr=le32(file:read(4)or'',0)==24;file:close()end
  local called,reply;called,reply,why=pcall(platform.screenshot_request,current.staged_png)
  if not called or not reply then return keep_dds('failed','PNG conversion refused: '..tostring(called and why or reply))end
  current.id,current.next_poll=reply.id,platform.now()+.1
  return finish(reply)
 end
 function self.status(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Screenshot job identity differs')
  if current.state~='pending'then return record(current.state,current.reason)end
  local now=platform.now()
  if now<current.next_poll then return record('pending')end
  current.next_poll=now+.1
  local called,reply=pcall(platform.screenshot_status,current.id)
  if not called or not reply then return record('pending')end
  return finish(reply)
 end
 function self.cancel(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Screenshot job identity differs')
  if current.state~='pending'then return true,record(current.state,current.reason)end
  local called,reply=pcall(platform.screenshot_cancel,current.id)
  if not called or not reply then return false,record('pending')end
  local final=finish(reply)
  return final.state~='pending',final
 end
 return self
end
return M

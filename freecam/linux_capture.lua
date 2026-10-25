-- Optional host-side XWayland game-window capture. Native Windows keeps the
-- existing WGC service. No shell, helper launch or idle polling runs in Lua.
local M={}
local function read(path,limit)
 local f=io.open(path,'rb');if not f then return end
 local s=f:read(limit+1);f:close();if not s or#s>limit then return end;return s
end
local function write(path,data)
 local temp=path..'.lua-tmp';local f,why=io.open(temp,'wb');if not f then return false,why end
 local ok,reason=f:write(data);local closed=f:close()
 if not ok or not closed then os.remove(temp);return false,reason or'Capture request close failed'end
 local moved,problem=os.rename(temp,path);if not moved then os.remove(temp);return false,problem end;return true
end
function M.new(root,output,issue,fs)
 fs=fs or{read=read,write=write,time=os.time}
 if type(root)~='string'or type(output)~='string'or type(issue)~='function'or fs.read(root..'/protocol',32)~='WJCAP1\n' then return nil end
 output=output:gsub('[/\\]+$','')
 local self={version=1,output_directory=output,capabilities={async=true,game_window=true,format='png',color_space='sdr',max_jobs=1}}
 local issued,nonce,current
 local function heartbeat()
  local s=fs.read(root..'/heartbeat',160)
  local n,p,t
  if s then n,p,t=s:match('^WJCAP1\n(%x+)\n(%d+)\n(%d+)\n$')end
  local age=t and fs.time()-tonumber(t)
  if not n or#n~=32 or not age or age<0 or age>3 then return nil,'Linux screenshot helper is not ready'end
  return n
 end
 local function record(state,why)
  return{job_token=current.job_token,output_token=current.output_token,output_path=current.output_path,state=state,reason=why}
 end
 function self.new_job_token()
  if current and current.pending then return nil,'Screenshot already pending'end
  local n,why=heartbeat();if not n then return nil,why end
  local token,problem=issue()
  if type(token)~='string'or#token>128 or not token:match('^lll%-shot:[a-z0-9_]+:%d+$')then return nil,problem or'Unsupported screenshot token'end
  issued,nonce=token,n;return token
 end
 function self.request(intent)
  if type(intent)~='table'or intent.job_token~=issued or not issued or(current and current.pending)then return nil,'Latest unused screenshot token required'end
  local name=intent.output_token
  if type(name)~='string'or#name>128 or not name:match('^War%-Journalist%-%w[%w_-]*%.png$')or intent.output_path~=output..'/'..name then return nil,'Screenshot output identity differs'end
  local n,why=heartbeat();if n~=nonce then return nil,why or'Capture helper session changed'end
  local id=issued:gsub(':','_')
  local ok,problem=fs.write(root..'/requests/'..id..'.request','WJCAP1\n'..nonce..'\n'..issued..'\n'..name..'\n')
  if not ok then return nil,problem end
  current={job_token=issued,output_token=name,output_path=intent.output_path,id=id,pending=true};issued=nil
  return record('pending')
 end
 function self.status(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Screenshot job identity differs')
  local s=fs.read(root..'/results/'..current.id..'.result',1024)
  if not s then return record('pending')end
  local n,j,o,state,reason=s:match('^WJCAP1\n(%x+)\n([^\n]+)\n([^\n]+)\n([a-z]+)\n([^\n]*)\n$')
  -- A restarted helper can reuse a job filename from its previous session.
  -- Its old acknowledgement is pending, never a failure or current result.
  if n and n~=nonce then return record('pending')end
  if n~=nonce or j~=job or o~=output_token or(state~='succeeded'and state~='failed'and state~='cancelled')then error('Screenshot acknowledgement identity differs')end
  current.pending=false;current.state=state;current.reason=reason~=''and reason or nil
  return record(state,current.reason)
 end
 function self.cancel(job,output_token)
  local r=self.status(job,output_token)
  if r.state~='pending'then return true,r end
  local ok,why=fs.write(root..'/cancel/'..current.id..'.cancel','cancel\n')
  if not ok then error(why)end
  return false,r
 end
 return self
end
return M

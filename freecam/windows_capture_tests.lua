local capture=dofile('freecam/windows_capture.lua')
-- An in-memory filesystem (paths compared with / and \ alike), a fake engine writer and a
-- fake WJL whose jobs the test finishes.
local files={}
local function key(path)return(path:gsub('\\','/'))end
local renames_fail=false
local fs={open=function(path,mode)
  local k=key(path)
  if mode=='rb'then
   local body=files[k];if not body then return nil end
   local at=0
   return{read=function(_,n)if n=='*a'then return body end;local part=body:sub(at+1,at+n);at=at+n;return part end,
    seek=function(_,_,offset)at=offset or 0;return at end,close=function()end}
  end
  assert(mode=='wb');local chunks={}
  return{write=function(_,s)chunks[#chunks+1]=s;return true end,close=function()files[k]=table.concat(chunks)end}
 end,
 rename=function(from,to)if renames_fail then return nil,'cross-device'end;local a,b=key(from),key(to);if not files[a]or files[b]then return nil end;files[b],files[a]=files[a],nil;return true end,
 remove=function(path)files[key(path)]=nil;return true end}
local staging='C:\\Users\\Some One\\AppData\\Local\\WJL\\Helldivers2\\Screenshots'
local output='C:/Users/Some One/Pictures'
local format=87
local function header(f)return'DDS '..string.rep('\0',124)..string.char(f%256,0,0,0)..string.rep('\0',16)end
local engine_fails
local engine={output_directory=(staging:gsub('\\','/'))}
do local serial,issued=0,nil
 function engine.new_job_token()serial=serial+1;issued='engine:'..serial;return issued end
 function engine.request(intent)
  assert(intent.job_token==issued and intent.output_path==engine.output_directory..'/'..intent.output_token and intent.output_token:match('%.dds$'))
  if engine_fails then return{job_token=issued,output_token=intent.output_token,output_path=intent.output_path,state='failed',reason=engine_fails}end
  files[key(intent.output_path)]=header(format)..'pixels'
  return{job_token=issued,output_token=intent.output_token,output_path=intent.output_path,state='succeeded'}
 end
end
local clock,requests,job,refuse=0,{},nil,nil
local platform={now=function()return clock end}
function platform.screenshot_request(path)
 requests[#requests+1]=path
 if refuse then return nil,refuse end
 job={id=string.rep('c',32),path=path,state='pending'}
 return{state='pending',id=job.id,output_path=path,error=0,width=0,height=0,elapsed_ms=0}
end
local polls=0
function platform.screenshot_status(id)
 assert(id==job.id);polls=polls+1
 if job.state=='succeeded'then files[key(job.path)]='\137PNG\r\n\26\n'end
 return{state=job.state,id=id,output_path=job.path,error=job.error or 0,width=4,height=2,elapsed_ms=1}
end
function platform.screenshot_cancel(id)assert(id==job.id);job.state='cancelled';return platform.screenshot_status(id)end
local logged={}
local c=capture.new(engine,platform,staging,output,function(m)logged[#logged+1]=m end,fs)
assert(c.version==1 and c.extension=='png'and c.output_directory==output and c.capabilities.format=='png'and c.capabilities.async)
local n=0
local function begin()
 n=n+1;local name='War-Journalist-20261027-200000-1-'..n..'.png'
 local token=c.new_job_token()
 return c.request({job_token=token,output_token=name,output_path=output..'/'..name}),token,name
end
local function stem(name)return name:sub(1,-5)end
-- SDR: the engine writes the DDS into WJL's folder, WJL converts it, the PNG is moved and
-- the DDS removed. Status polls WJL at most 10 times a second.
local record,token,name=begin()
assert(record.state=='pending'and record.job_token==token and record.output_path==output..'/'..name)
assert(requests[1]==staging..'\\'..stem(name)..'.png','WJL is asked for the PNG beside the staged DDS')
assert(files[key(staging..'/'..stem(name)..'.dds')],'The engine wrote the DDS into WJL\'s folder')
assert(c.status(token,name).state=='pending'and polls==0)
clock=.2;job.state='succeeded'
record=c.status(token,name)
assert(record.state=='succeeded'and record.output_path==output..'/'..name and files[key(output..'/'..name)]=='\137PNG\r\n\26\n')
assert(not files[key(staging..'/'..stem(name)..'.dds')]and not files[key(staging..'/'..stem(name)..'.png')]and not files[key(output..'/'..stem(name)..'.dds')],'SDR keeps only the PNG')
assert(c.status(token,name).state=='succeeded'and polls==1,'A finished job is not polled again')
-- HDR10: the DDS is kept beside the PNG. A rename across volumes falls back to a copy.
format=24;renames_fail=true
record,token,name=begin();clock=clock+.2;job.state='succeeded'
assert(c.status(token,name).state=='succeeded')
assert(files[key(output..'/'..name)]and files[key(output..'/'..stem(name)..'.dds')]and not files[key(staging..'/'..stem(name)..'.dds')],'HDR keeps its DDS')
format,renames_fail=87,false
-- WJL refuses: the DDS goes to the screenshot folder and the log says why.
refuse='Screenshot request refused (0x0000007b)'
record,token,name=begin()
assert(record.state=='failed'and record.reason:find('0x0000007b',1,true)and record.reason:find('DDS saved',1,true))
assert(files[key(output..'/'..stem(name)..'.dds')]and logged[#logged]:find('PNG screenshot unavailable',1,true))
refuse=nil
-- Conversion fails: the same.
record,token,name=begin();clock=clock+.2;job.state,job.error='failed',0x32
record=c.status(token,name)
assert(record.state=='failed'and record.reason:find('0x00000032',1,true)and files[key(output..'/'..stem(name)..'.dds')])
-- The engine cannot write: no WJL request.
local before=#requests;engine_fails='The engine did not write the screenshot'
record=begin();assert(record.state=='failed'and record.reason==engine_fails and #requests==before)
engine_fails=nil
-- Cancelled while converting (Photo Mode closed): the DDS is kept, the record cancelled.
record,token,name=begin()
local done,final=c.cancel(token,name)
assert(done and final.state=='cancelled'and files[key(output..'/'..stem(name)..'.dds')])
-- Identity: latest token only, the screenshot folder only, never an existing file.
assert(not c.request({job_token='windows-shot:1',output_token='War-Journalist-x.png',output_path=output..'/War-Journalist-x.png'}))
token=c.new_job_token()
assert(not c.request({job_token=token,output_token='War-Journalist-x.png',output_path='D:/Elsewhere/War-Journalist-x.png'}))
files[key(output..'/War-Journalist-y.png')]='old'
assert(not c.request({job_token=token,output_token='War-Journalist-y.png',output_path=output..'/War-Journalist-y.png'}),'Never replaces a file')
print('Windows capture: engine DDS converted to PNG by WJL, moved to the screenshot folder; SDR DDS removed, HDR kept; DDS kept on refusal, failure or cancel passed')

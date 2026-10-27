local capture=dofile('freecam/windows_capture.lua')
-- Fake PNG (WJL) and DDS (engine) backends with the facade contract: their own tokens,
-- records naming them, and an outcome chosen by the test.
local function backend(name,folder)
 local self={output_directory=folder,calls={}}
 local serial,issued,current=0,nil,nil
 self.next_state,self.next_reason='succeeded',nil
 function self.new_job_token()serial=serial+1;issued=name..':'..serial;return issued end
 function self.request(intent)
  assert(intent.job_token==issued,'Inner token required');issued=nil
  self.calls[#self.calls+1]=intent.output_token
  if self.reject then return nil,self.reject end
  current={job_token=intent.job_token,output_token=intent.output_token,output_path=intent.output_path,state='pending'}
  return{job_token=current.job_token,output_token=current.output_token,output_path=current.output_path,state='pending'}
 end
 function self.status(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Inner identity')
  current.state,current.reason=self.next_state,self.next_reason
  return{job_token=job,output_token=output_token,output_path=current.output_path,state=current.state,reason=current.reason}
 end
 function self.cancel(job,output_token)
  assert(current and current.job_token==job)
  current.state='cancelled'
  return true,{job_token=job,output_token=output_token,output_path=current.output_path,state='cancelled'}
 end
 return self
end
local folder='C:/Users/Some One/Pictures'
local logged={}
local png,dds=backend('png',folder),backend('dds',folder)
local c=capture.new(png,dds,false,function(m)logged[#logged+1]=m end)
assert(c.version==1 and c.output_directory==folder and c.extension=='png')
assert(c.capabilities.game_window==true and c.capabilities.format=='png'and c.capabilities.color_space=='sdr'and c.capabilities.max_jobs==1)
local n=0
local function shot(extension)
 n=n+1
 local name='War-Journalist-20261027-180000-1-'..n..'.'..extension
 local token=c.new_job_token()
 local record,why=c.request({job_token=token,output_token=name,output_path=folder..'/'..name})
 if not record then return nil,why end
 assert(record.job_token==token and record.state=='pending','Records carry the outer token')
 return c.status(token,name),token,name
end
-- PNG by default; a success keeps PNG.
local done=shot(c.extension);assert(done.state=='succeeded'and #png.calls==1 and c.extension=='png')
assert(not pcall(c.status,'windows-shot:0',done.output_token),'A stale token is refused')
assert(not c.request({job_token='windows-shot:99',output_token='x.png',output_path=folder..'/x.png'}),'Only the latest token')
-- A passing failure (the window moved) keeps PNG once; a second in a row switches to DDS.
png.next_state,png.next_reason='failed','Screenshot error 0x000004d5'
assert(shot(c.extension).state=='failed'and c.extension=='png'and #logged==0)
png.next_reason='Screenshot error 0x000005b4'
assert(shot(c.extension).state=='failed'and c.extension=='dds','Two failed PNGs in a row switch to DDS')
assert(#logged==1 and logged[1]:find('saving DDS',1,true))
-- DDS from then on, through the engine backend with its own token.
done=shot(c.extension);assert(done.state=='succeeded'and done.output_token:match('%.dds$')and #dds.calls==1 and #png.calls==3)
-- A refusal that will not pass (HDR display: ERROR_NOT_SUPPORTED) switches at once.
png,dds,logged=backend('png',folder),backend('dds',folder),{}
c=capture.new(png,dds,false,function(m)logged[#logged+1]=m end)
png.next_state,png.next_reason='failed','Screenshot error 0x00000032'
assert(shot('png').state=='failed'and c.extension=='dds'and #logged==1)
-- A request the helper rejects counts the same way.
png,dds,logged=backend('png',folder),backend('dds',folder),{}
c=capture.new(png,dds,false,function(m)logged[#logged+1]=m end)
png.reject='Screenshot request refused (0x80040154)'
local record,why=shot('png');assert(record==nil and why==png.reject and c.extension=='dds')
-- A success between failures resets the count.
png,dds=backend('png',folder),backend('dds',folder)
c=capture.new(png,dds,false)
png.next_state,png.next_reason='failed','Screenshot error 0x000004d5';shot('png')
png.next_state,png.next_reason='succeeded',nil;shot('png')
png.next_state,png.next_reason='failed','Screenshot error 0x000004d5'
local _,token,name=shot('png')
assert(c.extension=='png','Failures must be in a row')
-- Polling the same failed job again does not count it twice.
assert(c.status(token,name).state=='failed'and c.status(token,name).state=='failed'and c.extension=='png')
-- HDR at start: DDS from the first shot.
png,dds,logged=backend('png',folder),backend('dds',folder),{}
c=capture.new(png,dds,true,function(m)logged[#logged+1]=m end)
assert(c.extension=='dds'and logged[1]:find('HDR is on',1,true))
-- Cancellation reaches the job's own backend and returns the outer token.
png,dds=backend('png',folder),backend('dds',folder)
c=capture.new(png,dds,false)
token=c.new_job_token();name='War-Journalist-x.png'
assert(c.request({job_token=token,output_token=name,output_path=folder..'/'..name}))
local cancelled,final=c.cancel(token,name);assert(cancelled and final.state=='cancelled'and final.job_token==token and c.extension=='png')
assert(not pcall(capture.new,png,backend('dds','D:/Other'),false),'One folder for both formats')
print('Windows capture: WJL PNG by default, engine DDS after a lasting refusal, HDR or two failures in a row, outer tokens and cancellation passed')

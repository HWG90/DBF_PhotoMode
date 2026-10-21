local M=dofile('freecam/steam_capture.lua')
local function fixture(timeout)
 local f={time=0,clock_reads=0,issued=0,requests=0,statuses=0,cancels=0,session={},scene={},frame=100}
 function f.context()return{session=f.session,scene=f.scene,focused=f.focused~=false,frame_id=f.frame}end
 function f.intent()return{output_token='out-1',output_path='C:/captures/exact.png'}end
 function f.reply(state)return{state=state or 'pending',job_token=f.job_token,output_token=f.output_token,
  output_path=f.output_path}end
 f.backend={new_job_token=function()
  f.issued=f.issued+1;if f.issue then return f.issue()end
  f.latest='session:job-'..f.issued;return f.latest
 end,request=function(intent)
  assert(intent.job_token==f.latest and f.last_used~=intent.job_token,'Request needs latest unused facade token')
  f.last_used=intent.job_token
  f.requests=f.requests+1;f.job_token,f.output_token,f.output_path=intent.job_token,intent.output_token,intent.output_path
  if f.request then return f.request(intent)end;return f.reply()
 end,status=function(job,output)
  f.statuses=f.statuses+1;assert(job==f.job_token and output==f.output_token)
  if f.status then return f.status()end;return f.reply()
 end,cancel=function(job,output)
  f.cancels=f.cancels+1;assert(job==f.job_token and output==f.output_token)
  if f.cancel then return f.cancel()end;return true,f.reply('cancelled')
 end}
 f.c=M.new(f.backend,function()f.clock_reads=f.clock_reads+1;return f.time end,{timeout=timeout or 5})
 function f.begin(token)assert(f.c.begin(f.intent(token),f.context()))end
 function f.render(n)
  for _=1,n do f.frame=f.frame+1;assert(f.c.rendered(f.frame,true,true,f.context()))end
 end
 function f.dispatch()local before=f.requests;f.render(12);assert(f.requests==before);assert(f.c.tick(f.context()));assert(f.requests==before+1)end
 return f
end
do
 local f=fixture()
 for _=1,500 do assert(not f.c.tick(nil));assert(not f.c.rendered(1,true,true,nil));assert(not f.c.active())end
 assert(f.clock_reads==0 and f.issued==0 and f.requests==0 and f.statuses==0 and f.cancels==0,'Idle must not read clock/context/backend or issue tokens')
 f.begin();local baseline=f.frame
 assert(not f.c.rendered(baseline,true,true,f.context()),'Do not accept a pre-begin frame')
 assert(not f.c.rendered(baseline+1,true,false,f.context()))
 assert(not f.c.rendered(baseline+1,true,true,f.context()),'Failed frame cannot later become a distinct success')
 for _=1,20 do assert(not f.c.rendered(baseline+1,true,true,f.context()))end
 assert(not f.c.rendered(baseline+2,false,true,f.context()))
 assert(not f.c.rendered(baseline+2,true,true,f.context()),'A visible completed frame cannot be relabelled hidden')
 f.frame=baseline+2;f.render(11);assert(f.c.state()=='waiting_frames'and f.requests==0)
 f.render(1);assert(f.c.state()=='ready');assert(not f.c.begin(f.intent('busy'),f.context()))
 assert(f.c.tick(f.context())and f.requests==1 and f.c.active())
 for _=1,500 do assert(f.c.tick(f.context()))end
 assert(f.statuses==0,'Do not poll again at unchanged application time')
 f.time=.1;assert(f.c.tick(f.context())and f.statuses==1)
 f.time=.19;assert(f.c.tick(f.context())and f.statuses==1)
 f.status=function()return f.reply('succeeded')end;f.time=.2
 assert(f.c.tick(f.context())and not f.c.active()and not f.c.busy())
 local result=f.c.result();assert(result.state=='succeeded'and result.output_path=='C:/captures/exact.png')
 result.output_path='mutated';assert(f.c.result().output_path=='C:/captures/exact.png')
 local reads=f.clock_reads;for _=1,500 do f.c.tick(nil)end;assert(f.clock_reads==reads and f.statuses==2)
 assert(f.c.begin(f.intent(),f.context())and f.issued==2,'New jobs obtain fresh facade tokens')
 assert(f.c.cancel())
end
do
 local f=fixture();f.cancel=function()return false,f.reply()end;f.begin();f.dispatch()
 assert(not f.c.close('close')and not f.c.active()and f.c.busy()and f.c.state()=='cleanup_pending')
 assert(f.c.result().state=='cleanup_pending'and not f.c.begin(f.intent(),f.context())and f.issued==1)
 for _=1,200 do f.c.close();f.c.dispose();f.c.invalidate();f.c.rendered(1000,true,true,nil);f.c.tick(nil)end
 assert(f.cancels==1 and f.statuses==0,'Repeated lifecycle cleanup does not resubmit cancellation')
 f.status=function()local r=f.reply('succeeded');r.job_token='retired-other-job';return r end
 f.time=.1;assert(not f.c.tick(nil)and f.c.busy(),'Late other-job status cannot retire pending cleanup')
 f.time=.19;f.c.tick(nil);assert(f.statuses==1,'Cleanup status is bounded to 10Hz')
 f.status=function()return f.reply()end;f.time=.2;assert(f.c.tick(nil)and f.statuses==2 and not f.c.active())
 f.status=function()return f.reply('succeeded')end;f.time=.31
 assert(f.c.tick(nil)and not f.c.busy()and f.c.result().state=='succeeded'and f.c.result().cancel_confirmed)
 assert(f.c.result().output_path=='C:/captures/exact.png','Preserve actual publication after cancellation')
 local reads,issued=f.clock_reads,f.issued
 for _=1,200 do f.c.tick(nil);f.c.close();f.c.dispose()end
 assert(f.clock_reads==reads and f.issued==issued and f.cancels==1 and f.statuses==3,'Retired cleanup is fully idle')
end
do
 local f=fixture();f.begin();f.dispatch();f.cancel=function()return true,f.reply('succeeded')end
 assert(f.c.dispose('disabled')and not f.c.active()and not f.c.busy())
 assert(f.c.result().state=='succeeded'and f.c.result().output_path=='C:/captures/exact.png'and f.statuses==0,
  'Cancel acknowledgement may already contain the actual terminal success')
end
for _,bad in ipairs({'job','output','path','missing path','true pending','false terminal','invalid ack'})do
 local f=fixture();f.begin();f.dispatch()
 f.cancel=function()
  local r=f.reply('cancelled');local ack=true
  if bad=='job'then r.job_token='foreign'
  elseif bad=='output'then r.output_token='foreign'
  elseif bad=='path'then r.output_path='C:/foreign.png'
  elseif bad=='missing path'then r.output_path=nil
  elseif bad=='true pending'then r.state='pending'
  elseif bad=='false terminal'then ack=false
  else ack='true'end
  return ack,r
 end
 assert(not f.c.close()and not f.c.active()and f.c.busy()and f.c.state()=='cleanup_blocked',bad)
 local reads=f.clock_reads
 for _=1,100 do f.c.tick(nil);f.c.close();f.c.dispose();f.c.invalidate()end
 assert(f.clock_reads==reads and f.cancels==1 and f.statuses==0,'Invalid cancel record blocks without idle work')
 f.cancel=function()return true,f.reply('cancelled')end
 assert(f.c.cancel('explicit retry')and not f.c.busy()and f.c.result().state=='cancelled')
end
do
 local f=fixture();f.begin();f.dispatch();f.cancel=function()return false,f.reply()end
 assert(not f.c.close());f.time=.1;assert(f.c.tick(nil)and f.statuses==1)
 f.time=2;assert(not f.c.tick(nil)and f.c.state()=='cleanup_blocked'and f.statuses==1 and f.cancels==1)
 local reads=f.clock_reads
 for _=1,200 do f.c.tick(nil);f.c.dispose()end
 assert(f.clock_reads==reads and f.cancels==1,'Expired cleanup grace has zero idle work')
 f.time=3;assert(not f.c.cancel('explicit retry')and f.c.state()=='cleanup_pending'and f.cancels==2)
 f.status=function()return f.reply('failed')end;f.time=3.1
 assert(not f.c.tick(nil)and not f.c.busy()and f.c.result().state=='failed'and f.c.result().cancel_confirmed)
end
for _,change in ipairs({'focus','session','scene','timeout','clock'})do
 local f=fixture();f.begin();f.dispatch();f.cancel=function()return false,f.reply()end
 if change=='focus'then f.focused=false elseif change=='session'then f.session={}elseif change=='scene'then f.scene={}
 elseif change=='timeout'then f.time=5 else f.time=-1 end
 assert(not f.c.tick(f.context())and not f.c.active()and f.c.busy()and f.cancels==1,change)
 if change=='clock'then
  assert(f.c.state()=='cleanup_blocked','Cannot bound cleanup using a backwards clock')
  f.time=0;assert(not f.c.cancel('clock recovered')and f.cancels==2)
 end
 f.status=function()return f.reply('cancelled')end;f.time=f.time+.11
 assert(not f.c.tick(nil)and not f.c.busy()and f.c.result().state=='cancelled',change)
end
do
 local f=fixture();f.begin();f.dispatch();f.cancel=function()return false,f.reply()end;assert(not f.c.close())
 f.time=-1;assert(not f.c.tick(nil)and f.c.state()=='cleanup_blocked'and f.cancels==1 and f.statuses==0)
 f.time=0;f.cancel=function()return true,f.reply('cancelled')end;assert(f.c.cancel('clock recovered'))
end
do
 local f=fixture();local intent=f.intent();intent.output_token=''
 assert(not f.c.begin(intent,f.context())and f.issued==0)
 f.focused=false;assert(not f.c.begin(f.intent(),f.context())and f.issued==0)
 f.focused=true;f.issue=function()return nil end
 assert(not f.c.begin(f.intent(),f.context())and f.issued==1 and not f.c.busy()and f.requests==0)
end
for _,phase in ipairs({'request','status','cleanup status'})do
 for _,state in ipairs({'pending','succeeded','failed','cancelled'})do
  for _,path in ipairs({'missing','wrong'})do
   local f=fixture();f.begin()
   local function invalid()
    local r=f.reply(state);r.output_path=path=='wrong'and 'C:/foreign.png'or nil;return r
   end
   if phase=='request'then
    f.request=invalid;f.render(12);assert(not f.c.tick(f.context()))
   else
    f.dispatch();f.status=invalid
    if phase=='cleanup status'then
     f.cancel=function()return false,f.reply()end
     assert(not f.c.close()and f.c.state()=='cleanup_pending')
    end
    f.time=.1;assert(not f.c.tick(phase=='status'and f.context()or nil))
   end
   local label=phase..' '..state..' '..path..' path'
   assert(f.cancels==1 and not f.c.active(),label)
   if phase=='cleanup status'then
    assert(f.c.busy()and f.c.state()=='cleanup_blocked'and not f.c.result().cancel_confirmed,
     label..' must not clear cleanup ownership')
    f.cancel=function()return true,f.reply('cancelled')end
    assert(f.c.cancel('explicit validated retirement')and not f.c.busy(),label)
   else
    assert(not f.c.busy()and f.c.result().state=='cancelled',label..' requires validated cancellation')
   end
  end
 end
end
do
 local f=fixture();f.begin();f.render(6)
 f.frame=f.frame+1;assert(not f.c.rendered(f.frame,false,true,f.context()))
 f.render(6);assert(f.c.tick(f.context())and f.requests==0 and f.c.state()=='waiting_frames',
  'Six clean frames, one visible, six clean frames cannot dispatch')
 f.frame=f.frame+1;assert(not f.c.rendered(f.frame,true,false,f.context()))
 assert(not f.c.rendered(f.frame,true,true,f.context()),'Duplicate success cannot relabel failed frame')
 f.render(11);assert(f.c.tick(f.context())and f.requests==0)
 f.render(1);assert(f.c.state()=='ready')
 f.frame=f.frame+1;assert(not f.c.rendered(f.frame,false,true,f.context()))
 assert(f.c.tick(f.context())and f.requests==0 and f.c.state()=='waiting_frames','Visible frame revokes undispatched ready state')
 f.render(12);assert(f.c.state()=='ready')
 f.frame=f.frame+1;assert(not f.c.rendered(f.frame,true,false,f.context()))
 assert(f.c.tick(f.context())and f.requests==0 and f.c.state()=='waiting_frames','Failed frame revokes undispatched ready state')
 assert(not f.c.rendered(f.frame,true,true,f.context()))
 f.render(12);assert(f.c.tick(f.context())and f.requests==1);assert(f.c.cancel())
end
do
 local f=fixture();local intent=f.intent();assert(f.c.begin(intent,f.context()))
 intent.job_token='retarget';intent.output_token='retarget';intent.output_path='C:/wrong.png'
 f.request=function(request)local reply=f.reply();request.job_token='mutated';request.output_path='C:/also-wrong.png';return reply end
 f.dispatch();assert(f.job_token=='session:job-1'and f.output_token=='out-1'and f.output_path=='C:/captures/exact.png')
 f.status=function()return{state='succeeded',job_token='old-job',output_token='out-1',output_path='C:/old.png'}end
 f.time=.1;assert(not f.c.tick(f.context())and f.c.active()and f.cancels==0,'Ignore late other-job completion')
 f.status=function()return{state='succeeded',job_token=f.job_token,output_token='old-out',output_path='C:/old.png'}end
 f.time=.2;assert(not f.c.tick(f.context())and f.c.active(),'Ignore late other-output completion')
 f.status=function()return f.reply('succeeded')end;f.time=.31
 assert(f.c.tick(f.context())and f.c.result().state=='succeeded')
end
for _,change in ipairs({'focus','session','scene'})do
 local f=fixture();f.begin();f.dispatch()
 if change=='focus'then f.focused=false elseif change=='session'then f.session={}else f.scene={}end
 assert(not f.c.tick(f.context())and not f.c.active()and not f.c.busy()and f.cancels==1)
 assert(f.c.result().state=='cancelled'and f.statuses==0)
 for _=1,30 do f.c.tick(f.context())end;assert(f.cancels==1,'No repeated invalidation cleanup')
end
do
 local f=fixture();f.begin();f.render(11);assert(f.c.cancel('close')and not f.c.active()and f.requests==0 and f.cancels==0)
 f.begin('next');f.time=5;assert(not f.c.tick(f.context())and f.cancels==0 and f.requests==0,'Frame wait uses application deadline')
 f.time=6;f.begin('submitted');f.dispatch();f.time=11
 assert(not f.c.tick(f.context())and f.cancels==1 and f.statuses==0 and f.c.result().state=='cancelled')
end
do
 local f=fixture();f.request=function()return nil,'helper unavailable'end;f.begin();f.render(12)
 assert(not f.c.tick(f.context())and not f.c.active()and f.cancels==0 and f.c.result().reason=='helper unavailable')
 f.request=function()error('transport lost')end;f.begin('uncertain');f.render(12)
 assert(not f.c.tick(f.context())and f.cancels==1 and not f.c.busy(),'Request exception cancels uncertain submission')
end
for _,bad in ipairs({'status error','missing identity','missing path','wrong path','wrong state'})do
 local f=fixture();f.begin();f.dispatch()
 f.status=function()
  if bad=='status error'then error('status transport lost')end
  if bad=='missing identity'then return{state='pending'}end
  local r=f.reply('succeeded')
  if bad=='missing path'then r.output_path=nil elseif bad=='wrong path'then r.output_path='C:/other.png'else r.state='unknown'end
  return r
 end
 f.time=.1;assert(not f.c.tick(f.context())and not f.c.active()and f.cancels==1 and f.c.result().state=='cancelled',bad)
end
for _,state in ipairs({'failed','cancelled'})do
 local f=fixture();f.begin();f.dispatch();f.status=function()return f.reply(state)end;f.time=.1
 assert(not f.c.tick(f.context())and not f.c.busy()and f.cancels==0 and f.c.result().state==state)
end
do
 local f=fixture();f.begin();f.dispatch();f.cancel=function()error('cancel transport lost')end
 assert(not f.c.cancel('disabled')and not f.c.active()and f.c.busy()and f.c.state()=='cleanup_blocked')
 assert(not f.c.begin(f.intent('too soon'),f.context()))
 local reads=f.clock_reads;for _=1,500 do f.c.tick(nil)end
 assert(f.cancels==1 and f.statuses==0 and f.clock_reads==reads,'Unacknowledged cleanup never retries while idle')
 f.cancel=function()return false end;assert(not f.c.cancel('explicit retry')and f.cancels==2)
 f.cancel=function()return true,f.reply('cancelled')end;local recovered,why=f.c.cancel('explicit retry')
 assert(recovered and why==nil and f.cancels==3 and not f.c.busy())
 assert(f.c.result().cancel_confirmed and not f.c.result().cleanup_blocked)
 f.begin('recovered');assert(f.c.active());assert(f.c.cancel())
end
do
 local f=fixture();f.begin();f.dispatch();f.time=-1
 assert(not f.c.tick(f.context())and f.cancels==1 and f.c.result().reason=='application clock invalid')
 f.time=0;f.begin('large jump');f.dispatch();f.time=4;assert(f.c.tick(f.context())and f.statuses==1,'One poll after a large time jump, no catch-up loop')
end
do
 local f=fixture()
 for _=1,2048 do f.begin();assert(f.c.cancel())end
 assert(f.issued==2048 and not f.c.busy()and f.requests==0 and f.statuses==0 and f.cancels==0,
  'Facade issuance has no coordinator history cap and pre-dispatch retirement makes no request')
end
print('Steam capture: facade identity, 12 consecutive hidden frames, bounded capture/cleanup, invalidation, stale results and explicit cleanup retry passed')

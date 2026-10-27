assert(_VERSION=='Lua 5.1')
local Probe=dofile('freecam/windows_freeze_bone_probe.lua')
local function fixture()
 local f={reads=0,holds=0,resets=0,time=0,logs={}}
 f.status={selected='one'};f.frame={identity='one',position={1,2,3},head={1,2,5},yaw=0}
 f.subject={hold_bone_transfer=function()end,status=function()return f.status end,tracking_frame=function()
  f.reads=f.reads+1;if f.read_error then error('Retired frame')end;return f.frame
 end}
 f.action=function(method)
  if method=='hold_bone_transfer'then f.holds=f.holds+1;if f.refuse then return false,'Unavailable'end;f.status.pose='freeze-bone-trial'
  else assert(method=='reset');f.resets=f.resets+1;f.status.pose=nil;if f.reset_error then return false,'Cleanup pending'end end
  return true
 end
 f.probe=Probe.new(function(s)f.logs[#f.logs+1]=s end,function()return f.time end)
 function f.start(t)return f.probe.start(f.subject,t or 0,f.action)end
 return f
end
do
 local f=fixture();for i=1,100 do f.probe.tick(false,i)end;assert(f.reads==0 and f.holds==0)
 assert(f.start());assert(not f.start())
 for i=1,49 do f.probe.tick(true,i*.01)end;assert(f.reads==1)
 f.frame.position[1]=2;f.frame.head[1]=2;f.probe.tick(true,.5)
 assert(f.logs[2]:find('root_m=1.000000',1,true),'Baseline must own copied scalars')
 f.probe.tick(true,2);f.probe.tick(true,4)
 for i=1,199 do f.probe.tick(true,4+i*.01)end
 assert(f.reads==4 and f.resets==0 and f.holds==1,'Exactly three observations, no repeated writes')
 f.probe.tick(true,6);assert(f.resets==1 and not f.probe.active())
 for i=1,100 do f.probe.tick(true,6+i)end;assert(f.reads==4 and f.resets==1)
 assert(f.start(10));f.probe.tick(false,10.1);assert(f.resets==2)
 assert(f.start(20));f.probe.tick(true,26);assert(not f.start(30)and f.holds==3,'Three trials per armed generation')
end
do
 local f=fixture();assert(f.start());f.status.pose='user-pose';f.probe.tick(true,.1)
 assert(f.resets==0 and not f.probe.active(),'User pose supersedes the diagnostic')
end
do
 local f=fixture();assert(f.start());f.status.selected='another';f.probe.tick(true,.1)
 assert(f.resets==0 and not f.probe.active(),'Never reset a replacement subject')
end
do
 local f=fixture();f.refuse=true;assert(not f.start()and not f.probe.active()and f.resets==0)
 f.refuse=nil;assert(f.start());f.read_error=true;f.probe.tick(true,.5)
 assert(f.resets==1 and not f.probe.active())
end
do
 local f=fixture();assert(f.start());f.reset_error=true;f.probe.tick(true,6)
 assert(f.logs[#f.logs]:find('restored=false',1,true)and not f.probe.active(),'Failed cleanup stays in subject ledger, never falsely acknowledged')
end
print('Freeze bone probe: three bounded trials, mode-only ownership, copied diagnostics, lifecycle cancellation, timed restoration and idle passed')

local M=dofile('freecam/linux_capture.lua')
local files={};local now=100;local serial=0
local fs={read=function(p,n)local s=files[p];return s and#s<=n and s or nil end,
 write=function(p,s)files[p]=s;return true end,time=function()return now end}
local base='bridge';local output='C:/shots';local nonce=string.rep('a',32)
local function issue()serial=serial+1;return'lll-shot:test:'..serial end
assert(M.new(base,output,issue,fs)==nil)
files['bridge/protocol']='WJCAP1\n';files['bridge/heartbeat']='WJCAP1\n'..nonce..'\n1\n100\n'
local b=assert(M.new(base,output,issue,fs));local token=assert(b.new_job_token())
assert(b.request({job_token=token,output_token='../bad.png',output_path=output..'/../bad.png'})==nil)
local name='War-Journalist-20261023-1234-1.png';local path=output..'/'..name
local r=assert(b.request({job_token=token,output_token=name,output_path=path}));assert(r.state=='pending'and r.output_path==path)
assert(b.new_job_token()==nil);assert(files['bridge/requests/lll-shot_test_1.request'])
assert(b.status(token,name).state=='pending')
files['bridge/results/lll-shot_test_1.result']='WJCAP1\n'..string.rep('b',32)..'\n'..token..'\n'..name..'\nsucceeded\n\n'
assert(b.status(token,name).state=='pending','Prior helper result must not restore UI during a new capture')
files['bridge/results/lll-shot_test_1.result']=nil
local retired,waiting=b.cancel(token,name);assert(retired==false and waiting.state=='pending'and files['bridge/cancel/lll-shot_test_1.cancel'])
local result='bridge/results/lll-shot_test_1.result'
files[result]='WJCAP1\n'..nonce..'\n'..token..'\n'..name..'\ncancelled\nuser cancelled\n'
retired,r=b.cancel(token,name);assert(retired and r.state=='cancelled')
local next_token=assert(b.new_job_token());assert(next_token~=token)
assert(b.request({job_token=next_token,output_token=name,output_path=path}))
files['bridge/results/lll-shot_test_2.result']='WJCAP1\n'..nonce..'\nWRONG\n'..name..'\nsucceeded\n\n'
assert(not pcall(b.status,next_token,name),'A different job must never be acknowledged')
now=110;local fresh=assert(M.new(base,output,issue,fs));assert(fresh.new_job_token()==nil,'Stale host heartbeat must refuse entry')
print('PASS Linux capture facade identity, fixed output, pending ownership, cancellation and stale helper')

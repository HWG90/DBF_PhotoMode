local adapter=dofile('freecam/windows_input_service.lua')
local function n(x)return string.char(x%256,math.floor(x/256)%256,math.floor(x/65536)%256,math.floor(x/16777216)%256)end
local function u(s,i)local a,b,c,d=s:byte(i,i+3);return a+b*256+c*65536+d*16777216 end
local operations,release_refused={},false
local mask=('00331f08ffe1ff03feffff27fffffff7ff0003003f0000fc010000f804000000'):gsub('%x%x',function(x)return string.char(tonumber(x,16))end)
local transport={exchange=function(bytes)
 local seq,op=u(bytes,1),u(bytes,5);operations[#operations+1]=op
 local prefix=n(seq)..n(0)
 if op==0 then return prefix..n(17)..n(1)..'x'..n(7)..'C:/game'end
 if op==16 then return prefix..n(1)..n(1)..n(7)..n(2)..mask end
 if op==17 then return prefix..n(1)..n(10)..n(20)..n(1920)..n(1080)..n(0)..n(0)..n(2)..n(3)..n(1)..n(7)..n(2)..string.rep('\0',32)end
 if op==18 then if release_refused then return n(seq)..n(5)end;return prefix..n(1)..n(1)..n(7)end
 if op==11 then return prefix end
 error(op)
end}
local sr={Application={process_id=function()return 17 end,time_since_launch=function()return 1 end}}
assert(not pcall(adapter.new,{Application={process_id=function()return 18 end}},transport,function()end),'Wrong process must refuse')
local platform=adapter.new(sr,transport,function()end)
local focus,cursor,clip=true,false,true
local writes=0
local window={has_focus=function()return true end,mouse_focus=function()return focus end,show_cursor=function()return cursor end,clip_cursor=function()return clip end,
 set_mouse_focus=function(v)focus=v;writes=writes+1 end,set_show_cursor=function(v)cursor=v;writes=writes+1 end,set_clip_cursor=function(v)clip=v;writes=writes+1 end}
local capture=dofile('freecam/vendor/wjl_capture.lua').new(platform,window,function()end)
local service,driver=dofile('freecam/vendor/wjl_input_service.lua').new(platform,window,capture)
local count=#operations;for i=1,20 do driver.begin_frame()end;assert(#operations==count and writes==0,'Closed service must stay idle')
local token,why=service.acquire('dbf_freecam','menu',nil,{keyboard=true});assert(token,why)
assert(not focus and cursor,'Accepted cursor/mouse-focus context')
driver.begin_frame();local a=service.snapshot(token);assert(a.keyboard_active and a.keyboard_generation==7)
local before=#operations;service.snapshot(token);assert(#operations==before,'One helper exchange per frame')
assert(service.set_mode(token,'camera'));assert(not cursor and not focus)
release_refused=true;assert(not service.release(token),'Unacknowledged release must retain authority');assert(service.status().pending_restore and service.status().owner=='dbf_freecam')
release_refused=false;assert(service.release(token));assert(focus and not cursor and clip,'Original cursor state restored')
count=#operations;for i=1,20 do driver.begin_frame()end;assert(#operations==count,'Restored service must stay idle')
assert(driver.close())
print('Windows R34 input adapter: process proof, strict lease, one sample/frame, mode switch, uncertain release, exact restore and idle passed')

-- The game never waits on the helper: start() only spawns the launcher, and poll() is nil
-- until the helper's pipe opens. The launcher is closed (which waits for cmd.exe) only
-- once the service answered; a refused or silent helper's launcher is never closed.
-- A rejected render graph must not make keyboard/menu startup fail.
sr.Window=window;transport.close=function()end
local report,ready_after,opens='No WJL helper log written',3,0
local spawned,closed={},0
local mod={log=function()end,require=function(name)
 if name=='src/wjl_helper_startup.lua'then return{config=function()return{pipe='fixture_input_pipe',launcher='""C:\\wjl.exe" --launch"',
  contract_ready=function()return false end,failure=function()return report end}end}end
 if name=='src/steam_input.lua'then return dofile('freecam/steam_input.lua')end
 if name=='src/vendor/wjl_transport.lua'then return function(config)
  assert(config.pipe=='fixture_input_pipe'and config.launcher==nil,'The transport never launches')
  opens=opens+1;if opens<ready_after then error('WJL input service not ready')end;return transport end end
 if name=='src/vendor/wjl_capture.lua'then return dofile('freecam/vendor/wjl_capture.lua')end
 if name=='src/vendor/wjl_input_service.lua'then return dofile('freecam/vendor/wjl_input_service.lua')end
 error(name)
end}
local old_popen=io.popen
io.popen=function(command,mode)
 assert(mode=='r');spawned[#spawned+1]=command
 return{close=function()closed=closed+1;return true end,read=function()error('The launcher output is never read')end}
end
local now=0;local function clock()return now end
local poll=adapter.start(mod,sr,clock)
assert(#spawned==1 and spawned[1]=='""C:\\wjl.exe" --launch"'and closed==0,'Launch spawns cmd.exe and returns at once')
assert(poll()==nil and poll()==nil and closed==0,'Pending frames return nil without waiting')
local isolated,runner=poll()
assert(isolated and closed==1,'The launcher is closed once the service answered')
assert(mod.game_root=='C:/game'and mod.render_contract_verified==false)
local held=assert(isolated.acquire('dbf_freecam','menu',nil,{keyboard=true}))
runner.begin_frame();assert(isolated.snapshot(held).keyboard_active)
assert(isolated.release(held));assert(runner.close())
assert(not pcall(poll),'A finished start is not polled again')
-- A refusal in the helper's log ends the start within a second, without closing the launcher.
opens,ready_after,closed=0,math.huge,0
poll=adapter.start(mod,sr,clock)
assert(poll()==nil);report='Refused: installed game hashes do not match this service build'
now=now+.5;assert(poll()==nil,'The helper log is read once a second')
now=now+.6;local ok,why=pcall(poll)
assert(not ok and why==report and closed==0,'Refusal reported; launcher left open')
-- A helper that never answers: the start ends after start_seconds, launcher left open.
report,opens,closed='No WJL helper log written',0,0
poll=adapter.start(mod,sr,clock)
local frames=0
while true do
 local done,value=pcall(poll);frames=frames+1
 if not done then why=value;break end
 assert(value==nil);now=now+1/60
end
assert(why:find('not ready '..adapter.start_seconds..' s after launch: No WJL helper log written',1,true)and closed==0,why)
assert(frames>=adapter.start_seconds*60,'Each frame polls once')
io.popen=old_popen
print('Windows WJL start: launcher spawned without waiting, per-frame pipe poll, close after ready, refusal and timeout without waiting passed')

-- Saved Toggle HUD bindings are excluded at acquisition; unrelated keys stay isolated.
do
 local names=dofile('freecam/steam_input.lua').key_names
 local function has(m,k)return math.floor(m:byte(math.floor(k/8)+1)/2^(k%8))%2==1 end
 local config='Misc = { ToggleHudVisibility = [ { device_type = "Keyboard" input = "slash" } ] }'
 local narrowed,count=adapter.hud_keyboard_mask(mask,config,names)
 local _,_,label,warning=adapter.hud_keyboard_mask(mask,config,names);assert(label=='/'and warning==nil)
 local _,_,unbound,message=adapter.hud_keyboard_mask(mask,'Misc={ToggleHudVisibility=[]}',names);assert(unbound=='Unbound'and message:find('unbound',1,true))
 assert(count==1 and not has(narrowed,191)and has(narrowed,87),'Only the saved HUD key passes through')
 local alternate=adapter.hud_keyboard_mask(mask,config:gsub('slash','f10'),names)
 assert(has(alternate,191)and not has(alternate,121),'A rebound HUD action replaces its exemption')
 assert(adapter.hud_keyboard_mask(mask,'// '..config,names)==mask,'Commented actions do not exempt keys')
 assert(adapter.hud_keyboard_mask(mask,config:gsub('Keyboard','Mouse'),names)==mask,'Mouse binding leaves keyboard unchanged')
 assert(adapter.hud_keyboard_mask(mask,config:gsub('slash','unknown key'),names)==mask,'Unknown keys never broaden capture exemptions')
 assert(adapter.hud_keyboard_mask(mask,nil,names)==mask)
 local files={['C:/Steam/config/loginusers.vdf']='"users" { "76561197968617275" { } }',
  ['C:/Steam/userdata/8351547/553850/remote/input_settings.config']=config}
 local reads=0
 local function open(path)
  reads=reads+1;local value=files[path];if not value then return end
  return{read=function()return value end,close=function()end}
 end
 assert(adapter.hud_config('C:/Steam/steamapps/common/Helldivers 2',open)==config and reads==2)
 files['C:/Steam/config/loginusers.vdf']='"users" { "76561197968617275" { } "76561197968617276" { } }'
 assert(adapter.hud_config('C:/Steam/steamapps/common/Helldivers 2',open)==nil,'Ambiguous accounts are not guessed')
 local current_config=config
 local requested_mask
 local t={exchange=function(bytes)
  local op=u(bytes,5)
  if op==16 then requested_mask=bytes:sub(-32);return n(u(bytes,1))..n(0)..n(1)..n(u(bytes,17+u(bytes,9)))..n(7)..n(2)..requested_mask end
  if op==18 then return n(u(bytes,1))..n(0)..n(1)..n(u(bytes,13+u(bytes,9)))..n(7)end
  return transport.exchange(bytes)
 end}
 local platform=adapter.new(sr,t,function()end,function()return current_config end,names)
 local service,driver=dofile('freecam/vendor/wjl_input_service.lua').new(platform,window,dofile('freecam/vendor/wjl_capture.lua').new(platform,window,function()end))
 local token=assert(service.acquire('dbf_freecam','menu',nil,{keyboard=true}))
 assert(requested_mask==narrowed and service.capabilities.keyboard_mask==narrowed)
 assert(service.set_mode(token,'camera')and service.capabilities.keyboard_mask==narrowed,'Menu/camera transitions retain passthrough')
 assert(service.release(token));current_config=config:gsub('slash','f10')
 token=assert(service.acquire('dbf_freecam','camera',nil,{keyboard=true}))
 assert(requested_mask==alternate and service.capabilities.keyboard_mask==alternate,'Next activation refreshes the saved binding')
 assert(service.release(token)and driver.close())
 print('HUD key passthrough: saved binding discovery, ambiguity, narrow masks, menu/camera and rebind lifecycle passed')
end

-- PNG screenshot jobs: the helper's reply layout (operations 13-15) through LLL's facade.
do
 local id=string.rep('ab',16)
 local state,seen=1,{}
 local function reply(seq,path,error_code,width,height)
  return n(seq)..n(0)..n(state)..n(error_code or 0)..n(width or 0)..n(height or 0)..n(40)..n(32)..id..n(#path)..path
 end
 local helper_path
 local t={exchange=function(bytes)
  local seq,op,len=u(bytes,1),u(bytes,5),u(bytes,9)
  local path=bytes:sub(13,12+len)
  if op==13 then seen[#seen+1]='request';helper_path=path:gsub('/','\\');return reply(seq,helper_path)end
  if op==14 then assert(path==id);seen[#seen+1]='status';return reply(seq,helper_path,0,3840,2160)end
  if op==15 then assert(path==id);seen[#seen+1]='cancel';state=4;return reply(seq,helper_path)end
  return transport.exchange(bytes)
 end}
 local clock=0
 local p=adapter.new({Application={process_id=function()return 17 end,time_since_launch=function()return clock end}},t,function()end)
 local folder='C:/Users/Some One/Pictures'
 local shots=dofile('freecam/vendor/wjl_screenshots.lua').new({screenshot_directory=folder,screenshot_session='wjl_input_17_1_1',now=p.now,
  screenshot_request=p.screenshot_request,screenshot_status=p.screenshot_status,screenshot_cancel=p.screenshot_cancel})
 assert(shots.capabilities.format=='png'and shots.capabilities.game_window==true)
 local token=assert(shots.new_job_token());local name='War-Journalist-20261027-180000-1-1.png'
 local record=assert(shots.request({job_token=token,output_token=name,output_path=folder..'/'..name}))
 assert(record.state=='pending'and not record.uncertain and seen[1]=='request',record.reason)
 assert(shots.status(token,name).state=='pending'and #seen==1,'Status polls at most 10 times a second')
 clock=clock+.2;state=2
 record=shots.status(token,name)
 assert(record.state=='succeeded'and record.width==3840 and record.height==2160 and record.output_path==folder..'/'..name and seen[2]=='status')
 -- A refused request: no job, the helper's code in the reason.
 local refused={exchange=function(bytes)return n(u(bytes,1))..n(0x32)end}
 local q=adapter.new({Application={process_id=function()return 17 end,time_since_launch=function()return clock end}},
  {exchange=function(bytes)if u(bytes,5)==13 then return refused.exchange(bytes)end;return transport.exchange(bytes)end},function()end)
 local value,why=q.screenshot_request(folder..'/x.png');assert(value==nil and why=='Screenshot request refused (0x00000032)')
 print('WJL PNG screenshots: request/status/cancel reply layout, facade identity, 10 Hz polling and refused requests passed')
end

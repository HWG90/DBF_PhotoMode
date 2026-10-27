-- Isolated runtime integration: no loader, filesystem, native capture or game calls.
local function module(name)return dofile('freecam/'..name..'.lua')end
local function clone(values)local out={};for k,v in pairs(values)do out[k]=v end;return out end
local function pack(...)return{n=select('#',...),...}end
local function equal(a,b,message)
 for k,v in pairs(a)do assert(b[k]==v,message or k)end
 for k,v in pairs(b)do assert(a[k]==v,message or k)end
end
local function role(commands,name)
 for _,command in ipairs(commands or{})do if command.fixture_role==name then return true end end
 return false
end
local function fixture(available,configure)
 local f={time=0,foreground=true,world={},generation=1,session={},pressed={},key_names={},key_ids={},
  saves=0,clock_reads=0,issues=0,requests=0,statuses=0,cancels=0,camera_writes=0,rate=1,
  saved={frame=2,grid=2,logo=2,show_legend=true,hide_controls=false,clean_view=false,freeze_player=true}}
 local raw={x=100,y=100,width=1920,height=1080,buttons=0,wheel=0,dx=0,dy=0}
 f.pointer=raw
 local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true},
  acquire=function(owner)assert(owner=='dbf_freecam'and not f.lease);f.lease={};return f.lease end,
  owns=function(token)return f.lease~=nil and token==f.lease end,
  status=function()return{owner=f.lease and'dbf_freecam'or nil,pending_restore=false}end,
  release=function(token)assert(token==f.lease);f.lease=nil;return true end,
  snapshot=function(token)assert(token==f.lease);return raw end}
 local sr={Application={time_since_launch=function()f.clock_reads=f.clock_reads+1;return f.time end,
   main_world=function()return f.world end,set_time_step_policy=function(key,value)
    assert(key=='external_multiplier');f.rate=value end},
  Network={game_session=function()return f.session end},GameSession={peers=function()return{'local'}end},
  Window={has_focus=function()return f.foreground end},Gui={resolution=function()return 1920,1080 end},
  Keyboard={button_id=function(name)
   if not f.key_ids[name]then local id=#f.key_names+1;f.key_names[id]=name;f.key_ids[name]=id end
   return f.key_ids[name]
  end,button=function(id)return f.pressed[f.key_names[id]]and 1 or 0 end}}
 local camera={open=function()assert(not f.camera_open);f.camera_open=true;return true end,
  close=function()f.camera_open=false;return true end,
  scene=function()return f.world,f.generation end,
  frame=function()return{position={0,0,0},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}end,
  write_view=function()assert(f.camera_open);f.camera_writes=f.camera_writes+1;return true end}
 local lighting={status='fixture lighting',open=function()return true end,close=function()return true end,
  revision=function()return 0 end,selected=function()return nil,0,0 end,tick=function()return true end,
  markers=function()return{{fixture=true}}end,scene=function()return f.world,f.generation end}
 local view={new=function(_,overlay)
  local is_grain=overlay and f.overlay~=nil
  local item={last={},draws=0,releases=0}
  function item.draw(commands)
   if f.view_error and not overlay or f.overlay_error and overlay and not is_grain or f.grain_error and is_grain then error('fixture UI renderer failed')end
   item.draws=item.draws+1
   if overlay and not is_grain and f.overlay_refuse or is_grain and f.grain_refuse or not overlay and f.empty_draw_refuse and #commands==0 then return false end
   item.last=commands;return true
  end
  function item.release()
   item.releases=item.releases+1
   if not overlay and f.release_error then error('fixture UI release failed')end
   if is_grain and f.grain_release_error then error('fixture grain release failed')end
   if is_grain and f.grain_release_refuse then return false,'fixture grain release refused'end
   if not overlay and f.release_refuse then return false end
   item.last={};return true
  end
  if is_grain then f.grain=item elseif overlay then f.overlay=item else f.panel=item end;return item
 end}
 local menu={new=function(panel,actions)
  local item={actions=actions};f.menu=item
  function item.bind(handle,pages)
   item.handle,item.pages=handle,pages;f.controls={}
   for _,page in ipairs(pages)do for _,control in ipairs(page.controls or{})do f.controls[control.id]=control end end
  end
  local capture_cleared=false
  function item.close()capture_cleared=false;if item.light_gizmos then item.light_gizmos.cancel()end;panel.release()end
  function item.suspend()capture_cleared=false;if item.light_gizmos then item.light_gizmos.cancel()end;panel.draw({})end
  function item.hide_for_capture()
   if capture_cleared then return true end
   if item.light_gizmos then item.light_gizmos.cancel()end
   if panel.release()==false then return false end
   capture_cleared=true;f.last_hidden=true;return true
  end
  function item.draw(w,h,focused,hidden)
   capture_cleared=false
   f.last_hidden=hidden
   if item.prepare_light_gizmos then item.prepare_light_gizmos(w,h,focused,hidden)end
   if hidden then if item.light_gizmos then item.light_gizmos.cancel()end;panel.draw({});return end
   local commands={{fixture_role='panel'}}
   if item.handle.get('show_legend')then commands[#commands+1]={fixture_role='legend'}end
   if f.gizmo_visible then commands[#commands+1]={fixture_role='gizmo'}end
   panel.draw(commands)
  end
  function item.draw_cinema(_,_,_,hidden)
   capture_cleared=false
   f.last_hidden=hidden;if item.light_gizmos then item.light_gizmos.cancel()end
   panel.draw(hidden and{}or{{fixture_role='cinema'}})
  end
  function item.tick()end
  function item.scene_tick()return false end
  function item.editing_key()return false end
  function item.editing_text()return false end
  function item.dismiss()return false end
  function item.blur()return true end
  return item
 end}
 local composition=module('composition')
 composition.layout_static=function(_,_,options)
  f.composition_options=clone(options)
  local commands={}
  if options.frame>1 then commands[#commands+1]={kind='rect',fixture_role='frame'}end
  if options.grid>1 and not options.clean_view then commands[#commands+1]={kind='rect',fixture_role='grid'}end
  if options.logo>1 and not options.clean_view then commands[#commands+1]={kind='rect',fixture_role='logo'}end
  return commands
 end
 local backend={version=1,output_directory='C:/captures'};f.backend=backend
 function f.reply(state)
  assert(f.intent,'No requested job');return{state=state or'pending',job_token=f.intent.job_token,
   output_token=f.intent.output_token,output_path=f.intent.output_path}
 end
 function backend.new_job_token()f.issues=f.issues+1;f.latest='capture-session:job-'..f.issues;return f.latest end
 function backend.request(intent)
  assert(intent.job_token==f.latest and intent.job_token~=f.used,'Latest unused service token required')
  assert(type(intent.output_token)=='string'and #intent.output_token>0,'Immutable output token required')
  local basename=intent.output_path:match('^C:/captures/([^/\\]+)$')
  assert(basename and #basename<=128 and basename:match('^[%w_.%-]+%.png$'),'Exact safe PNG child path required')
  f.used=intent.job_token;f.intent=clone(intent);f.requests=f.requests+1
  if f.request_error then error('fixture request transport lost')end
  if f.request_reject then return nil,'fixture helper unavailable'end
  return f.reply()
 end
 function backend.status(job,output)
  assert(f.intent and job==f.intent.job_token and output==f.intent.output_token,'Status identity changed')
  f.statuses=f.statuses+1;return f.reply(f.status_state)
 end
 function backend.cancel(job,output)
  assert(f.intent and job==f.intent.job_token and output==f.intent.output_token,'Cancel identity changed')
  f.cancels=f.cancels+1
  if f.cancel_error then error('fixture cancellation transport lost')end
  if f.cancel_pending then return false,f.reply()end
  return true,f.reply(f.cancel_state or'cancelled')
 end
 local deps={camera={new=function()return camera end},input=module('steam_input'),core=module('vendor/core'),
  store={new=function()return{load=function()return clone(f.saved)end,save=function(_,values)
   f.saves=f.saves+1;f.saved=clone(values);return true end}end},view=view,menu=menu,
  options=module('photo_options'),legend=module('control_legend'),composition=composition,
  look=module('look'),lens=module('lens'),capture=module('steam_capture'),
  capture_backend=available~=false and backend or nil,lighting={new=function()return lighting end},lights={},
  gizmos={new=function()return{update=function(_,_,_,_,_,visible)f.gizmo_visible=visible==true end,
   cancel=function()f.gizmo_visible=false end}end}}
 f.native_render=function(...)
  f.native_args=pack(...);if f.native_error then error('fixture native renderer failed')end
  local results={n=f.native_args.n+4,[1]='native',[3]=f.native_args.n}
  for i=1,f.native_args.n do results[i+3]=f.native_args[i]end
  return unpack(results,1,results.n)
 end
 render=f.native_render
 if configure then configure(f,deps,sr)end
 f.runtime=module('steam_runtime').new({config_dir='unused-capture-fixture',log=function(message)if f.log then f.log(message)end end},sr,deps,service)
 function f.step(seconds,renders)
  f.time=f.time+(seconds or.016);f.runtime.tick()
  for _=1,renders or 0 do render()end
 end
 function f.open()
  assert(f.runtime.open(),'Fixture Photo entry failed');f.step(0,1)
  assert(f.controls.screenshot and f.controls.screenshot_key,'Screenshot controls must be registered')
 end
 function f.capture()assert(f.runtime.capture,'Expose the coordinator as runtime.capture for integration diagnostics');return f.runtime.capture end
 function f.start()
  assert(type(f.runtime.screenshot)=='function','Runtime must expose screenshot()')
  assert(f.runtime.screenshot(),'Active screenshot should begin');assert(f.capture().active())
 end
 function f.dispatch()
  f.start();local before=f.requests
  for _=1,12 do f.step(.016,1);assert(f.requests==before,'Do not dispatch before completed hidden renders')end
  f.step(0);assert(f.requests==before+1,'Dispatch on the tick after 12 completed hidden renders')
 end
 function f.visible()
  assert(role(f.panel.last,'panel')and role(f.panel.last,'legend')and role(f.panel.last,'gizmo'),'Restore panel, legend and gizmos')
  assert(role(f.overlay.last,'frame')and role(f.overlay.last,'logo')and role(f.overlay.last,'grid'),'Restore composition guides')
 end
 function f.finish()
  f.native_error,f.view_error,f.cancel_error,f.cancel_pending=false,false,false,false
  f.overlay_error,f.overlay_refuse,f.release_error,f.release_refuse,f.empty_draw_refuse=false,false,false,false,false
  f.grain_error,f.grain_refuse,f.grain_release_error,f.grain_release_refuse=false,false,false,false
  if f.runtime.capture and f.runtime.capture.busy()then f.runtime.capture.cancel('fixture cleanup')end
  assert(f.runtime.dispose(),'Fixture runtime cleanup failed');assert(render==f.native_render,'Restore prior render callback')
 end
 return f
end

if rawget(_G,'DBF_PHOTO_CAPTURE_FIXTURE_ONLY')then return fixture end

do
 local f=fixture(false)
 assert(type(f.runtime.screenshot)=='function'and not f.runtime.screenshot(),'Closed runtime cannot capture')
 f.open();assert(f.controls.screenshot.disabled and f.controls.screenshot_key.disabled,'Absent service keeps controls gated')
 assert(not f.runtime.screenshot()and f.issues==0 and f.requests==0);f.finish()
end
do
 local f=fixture();local reads=f.clock_reads
 for _=1,200 do f.step(.016)end
 assert(f.clock_reads==reads and f.issues==0 and f.requests==0 and f.statuses==0 and f.cancels==0,'Closed capture is fully idle')
 assert(not f.runtime.screenshot()and f.issues==0,'Closed screenshot must not issue a token')
 f.open();assert(not f.controls.screenshot.disabled and not f.controls.screenshot_key.disabled,'Qualified backend enables controls')
 f.visible();local saved,saves,rate=clone(f.saved),f.saves,f.rate
 local args={n=4,[2]='argument',[4]=42};local results=pack(render(unpack(args,1,args.n)))
 assert(results.n==8 and results[1]=='native'and results[2]==nil and results[3]==4 and results[4]==nil and results[5]=='argument'and results[6]==nil and results[7]==42 and results[8]==nil,'Preserve render varargs and nil return slots')
 equal(f.native_args,args,'Preserve native render arguments exactly')
 f.start();assert(not f.runtime.screenshot()and f.issues==1,'A busy capture cannot allocate another job')
 local release_baseline=f.panel.releases
 -- Many render invocations inside one tick count as one completed frame.
 f.step(.016,25);assert(f.requests==0)
 assert(not role(f.panel.last,'panel')and not role(f.panel.last,'legend')and not role(f.panel.last,'gizmo')and not f.gizmo_visible,'Hide all Photo UI during capture')
 assert(role(f.overlay.last,'frame')and role(f.overlay.last,'logo')and not role(f.overlay.last,'grid'),'Keep frame/logo while suppressing composition grid')
 equal(f.saved,saved,'Capture must preserve saved preferences');assert(f.saves==saves and f.rate==rate,'Capture must not save settings or modify world time')
 for _=1,10 do f.step(.016,1);assert(f.requests==0)end
 f.step(.016,1);assert(f.requests==0);f.step(0);assert(f.requests==1)
 assert(f.panel.releases==release_baseline+1,'Acknowledged UI hide releases owned planes once per capture')
 local before=f.statuses;for _=1,50 do f.step(0)end;assert(f.statuses==before,'No status poll at unchanged time')
 f.step(.099);assert(f.statuses==before);f.step(.002);assert(f.statuses==before+1,'Active status polls at most 10Hz')
 f.status_state='succeeded';f.step(.101,1);assert(not f.capture().busy()and f.capture().result().state=='succeeded');f.visible()
 equal(f.saved,saved,'Completion must preserve saved preferences');assert(f.saves==saves and f.rate==rate)
 local statuses,issues=f.statuses,f.issues;for _=1,100 do f.step(.016,1)end
 assert(f.statuses==statuses and f.issues==issues,'Completed capture performs zero idle service work')
 local first=clone(f.intent);f.dispatch();assert(f.intent.job_token~=first.job_token and f.intent.output_token~=first.output_token and f.intent.output_path~=first.output_path,'New captures need fresh job and output identities')
 f.finish()
end
for _,refusal in ipairs({'release','overlay','grain'})do
 local f=fixture();f.open();local release_baseline=f.panel.releases
 if refusal=='release'then f.empty_draw_refuse,f.release_refuse=true,true
 elseif refusal=='grain'then assert(f.runtime.handle.set('grain',50));f.grain_refuse=true
 else f.overlay_refuse=true end
 f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==0 and f.capture().active(),refusal..' refusal must never acknowledge clean frames')
 if refusal=='release'then assert(role(f.panel.last,'panel'),'Refused empty draw/release leaves retained UI visible')end
 f.empty_draw_refuse,f.release_refuse,f.overlay_refuse,f.grain_refuse=false,false,false,false
 for _=1,12 do f.step(.016,1);assert(f.requests==0,'Require a full clean-frame wait after refusal')end
 f.step(0);assert(f.requests==1,refusal..' recovery must permit capture after 12 acknowledged frames')
 local expected_releases=refusal=='release'and 13 or 1
 assert(f.panel.releases==release_baseline+expected_releases,'Cache only successful UI retirement acknowledgement')
 f.finish()
end

do
 local f=fixture();f.open();assert(f.runtime.handle.set('grain',50));f.step(.016,1)
 local grain=f.grain;assert(grain and #grain.last==96 and grain.last[1].layer==101)
 f.dispatch();assert(#grain.last==96 and not role(f.panel.last,'panel'),
  'Capture keeps film grain while hiding Photo controls')
 f.status_state='succeeded';f.step(.101,1);f.visible()
 assert(f.runtime.handle.set('grain',0));f.step(.016,1);local released=grain.releases
 for _=1,100 do f.step(.016,1)end
 assert(released==1 and grain.releases==released,'Disabled grain must retire once')
 assert(f.runtime.handle.set('grain',50));f.step(.016,1);grain=f.grain
 f.grain_release_refuse=true
 assert(not f.runtime.close(true)and f.runtime.state=='closing'and not f.lease,
  'A grain teardown refusal retains GUI cleanup without holding gameplay input')
 assert(not f.runtime.open(),'Do not reopen while grain retirement is pending')
 f.grain_release_refuse=false;assert(f.runtime.close(true)and f.runtime.state=='closed')
 f.finish()
end
do
 local f=fixture();f.open();assert(f.runtime.handle.get('screenshot_key')==19,'Default screenshot key is VK19')
 f.pressed.pause=true;f.step(.016,1);assert(f.issues==1 and f.capture().active(),'Pause key must start capture through the input adapter')
 for _=1,30 do f.step(.016)end;assert(f.issues==1 and f.requests==0,'Held screenshot key cannot retrigger or substitute for rendered frames')
 f.pressed.pause=false
 for _=1,11 do f.step(.016,1)end;assert(f.requests==0);f.step(0);assert(f.requests==1)
 f.finish()
end
for _,change in ipairs({'close','focus','scene'})do
 local f=fixture();f.open();f.dispatch();f.cancel_pending=true
 if change=='close'then f.runtime.close()
 elseif change=='focus'then f.foreground=false;f.lease=nil;f.step(.016)
 else f.generation=f.generation+1;f.step(.016)end
 assert(f.cancels==1 and not f.capture().active()and f.capture().busy(),change..' must cancel once and restore visibility before retirement')
 assert(not f.runtime.screenshot(),'Pending retirement refuses another capture')
 if f.runtime.active then f.step(0,1);f.visible()end
 local before=f.statuses
 for _=1,20 do f.runtime.close();f.step(0)end
 assert(f.cancels==1 and f.statuses==before,'Repeated lifecycle cleanup never repeats cancellation')
 f.status_state='cancelled';f.step(.101)
 assert(not f.capture().busy()and f.cancels==1 and f.statuses==before+1,'Retirement continues while Photo is closed')
 local statuses=f.statuses;for _=1,100 do f.step(.016)end;assert(f.statuses==statuses,'Retired cleanup returns to zero service work')
 f.finish()
end
do
 local f=fixture();f.open();f.dispatch();f.cancel_pending=true;f.runtime.close();f.step(2.1)
 assert(f.capture().state()=='cleanup_blocked'and not f.capture().active(),'Cleanup grace must end in a blocked, visible state')
 local statuses,cancels=f.statuses,f.cancels
 f.runtime.close(true);assert(not f.runtime.active)
 for _=1,100 do f.step(.016);assert(not f.runtime.dispose(),'Disposal must wait for retirement acknowledgement')end
 assert(f.statuses==statuses and f.cancels==cancels and f.issues==1,'Ordinary repeated disposal cannot retry blocked cleanup or issue a new job')
 f.cancel_pending=false
 assert(f.runtime.screenshot()and not f.capture().busy(),'Explicit Screenshot recovers terminal worker cleanup while Photo is closed and disabled')
 assert(f.cancels==cancels+1 and f.issues==1 and f.requests==1,'Explicit recovery retries retirement without a replacement capture')
 assert(f.runtime.dispose()and render==f.native_render,'Acknowledged recovery must permit disposal')
end
do
 local f=fixture();f.open();f.request_error=true;f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==1 and f.cancels==1 and not f.capture().busy(),'Uncertain request exception must retire through cancellation')
 if f.runtime.active then f.step(0,1);f.visible()end
 f.finish()
end
do
 local f=fixture();f.open();f.request_error,f.cancel_pending=true,true;f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==1 and f.cancels==1 and not f.capture().active()and f.capture().busy(),'Uncertain request must retain pending retirement ownership')
 f.step(0,1);f.visible();assert(not f.runtime.screenshot()and f.issues==1,'Uncertain creation cannot issue a replacement token')
 f.status_state='cancelled';f.step(.101)
 assert(not f.capture().busy()and f.cancels==1,'Uncertain creation retires only through the service acknowledgement')
 f.finish()
end
do
 local f=fixture();f.open();f.request_reject=true;f.start()
 for _=1,12 do f.step(.016,1)end;f.step(0)
 assert(f.requests==1 and f.cancels==0 and not f.capture().busy()and f.capture().result().state=='failed','Certain rejection must not invent worker cleanup')
 f.step(0,1);f.visible();f.finish()
end
do
 local f=fixture();f.open();f.start();for _=1,6 do f.step(.016,1)end
 f.native_error=true;local ok=pcall(render)
 assert(not ok and f.requests==0 and f.cancels==0 and not f.capture().busy(),'Native render failure during the frame wait must retire the unsubmitted request')
 f.native_error=false;f.finish()
end
do
 local f=fixture();f.open();f.dispatch();f.native_error=true
 local ok,why=pcall(render,nil,'native failure',nil)
 assert(not ok and tostring(why):find('fixture native renderer failed',1,true),'Preserve native renderer failure')
 assert(f.cancels==1 and not f.capture().active()and not f.capture().busy(),'Failed completed render must cancel the outstanding capture')
 f.native_error=false;f.finish()
end
do
 local f=fixture();f.open();f.dispatch();f.overlay_error=true;render()
 assert(f.cancels==1 and not f.capture().active()and not f.capture().busy(),'Photo renderer failure must cancel the outstanding capture')
 f.overlay_error=false;f.finish()
end
do
 local f=fixture();f.open();f.start();f.release_error=true;pcall(render)
 assert(f.requests==0 and not f.capture().active()and not f.capture().busy(),'Throwing UI release cannot acknowledge or submit a clean capture')
 f.release_error=false;f.finish()
end
print('Steam capture runtime: optional controls, clean completed frames, identity, render returns, time/preferences, bounded polling and lifecycle retirement passed')

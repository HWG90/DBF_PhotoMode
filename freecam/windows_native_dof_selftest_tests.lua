local factory=dofile('freecam/windows_native_dof_selftest.lua')
do
 local open,rename=io.open,os.rename
 io.open=function()return{read=function()return'selection-depth-v1\n'end,close=function()end}end
 os.rename=function()return false end;assert(not factory.consume('fixture',12))
 os.rename=function()return true end;assert(factory.consume('fixture',12)=='selection-depth-v1')
 io.open,os.rename=open,rename
 local now,count,closed,saved=0,0,0,0
 local engine={Application={time_since_launch=function()return now end,main_world=function()return 1 end},Network={game_session=function()return newproxy()end}}
 local test=factory.new(engine,function()end,'selection-depth-v1')
 local store=test.store({new=function()return{load=function()return{}end,save=function()saved=saved+1 end}end}).new('fixture')
 local settings=store.load('dbf_freecam');assert(settings.freeze_player and not settings.dof and settings.scene_shader==1)
 local game={active=false,state='closed'}
 game.open=function()game.active=true;game.state='active';return true end
 game.close=function()closed=closed+1;game.active=false;game.state='closed';return true end
 game.selection_probe=function(u,v)
  count=count+1;assert(u>=.35 and u<=.65 and v>=.35 and v<=.65)
  if count==1 then return nil,'settling',{pending=true,retry_at=102}end
  return{depth=.708,selected=true,label='Fixture',readback_ms=30,sample_ms=31,pick_ms=1}
 end
 now=60;test.tick(game);now=100;test.tick(game);assert(count==1)
 for i=1,100 do test.tick(game)end;assert(count==1,'Pending test must not resample before the returned retry time')
 for i=0,5 do now=102+8*i;test.tick(game)end
 assert(count==7 and closed==0 and game.active,'Keep the final result visible for window capture')
 now=149.99;test.tick(game);assert(count==7 and closed==0,'Final capture window performs no extra selection')
 now=150;test.tick(game)
 assert(closed==1 and not game.active,'Six fixed points followed by owned cleanup')
 assert(test.tick(game),'Reconstruct normal runtime only after cleanup')
 store.save('dbf_freecam',settings);assert(saved==0,'Selection test never writes user settings')
end
local time,opens,closes,sessions,writes=0,0,0,0,0
local sr={Application={time_since_launch=function()return time end,main_world=function()return{}end},
 Network={game_session=function()sessions=sessions+1;return newproxy()end}}
local logs={};local probe=factory.new(sr,function(s)logs[#logs+1]=s end)
local persisted={dof=false,dof_mode=2,scene_shader=4,freeze_player=true}
local store=probe.store({new=function()return{load=function()local t={};for k,v in pairs(persisted)do t[k]=v end;return t end,
 save=function()writes=writes+1;return true end}end}).new('fixture')
local values=store.load('dbf_freecam');assert(values.dof and values.dof_mode==1 and values.scene_shader==1 and not values.freeze_player)
assert(store.save('dbf_freecam',values)and writes==0 and persisted.dof_mode==2)
local runtime={state='closed',handle={set=function(k,v)assert(k=='dof');values[k]=v;return true end}}
runtime.open=function()opens=opens+1;runtime.active=true;runtime.state='active';return true end
runtime.close=function(clear)assert(clear);closes=closes+1;runtime.active=false;runtime.state='closing';return false end
for i=1,500 do probe.tick(runtime)end
assert(opens==0 and sessions==0,'Startup delay performs no session queries')
time=60;assert(not probe.tick(runtime));assert(opens==1 and runtime.active)
time=100;probe.tick(runtime);assert(values.dof==false)
time=130;probe.tick(runtime);assert(values.dof==true)
time=160;probe.tick(runtime);assert(closes==1)
assert(not probe.tick(runtime),'Do not reconstruct while cleanup is pending')
runtime.state='closed';assert(probe.tick(runtime));assert(writes==0,'Never persist diagnostic settings')
for i=1,500 do assert(not probe.tick(runtime))end
time=161;assert(probe.tick(runtime),'Retirement refusal can retry after one second')
time=191;assert(not probe.tick(runtime),'Retirement refusal must stop at the cleanup deadline')
local old_time=sr.Application.time_since_launch
sr.Application.time_since_launch=function()error('Stopped self-test must perform no clock reads')end
assert(not probe.tick(runtime));sr.Application.time_since_launch=old_time
time=0;probe=factory.new(sr,function()end);sr.Network.game_session=function()sessions=sessions+1;return nil end
local baseline=sessions
for i=0,1800 do time=i/10;probe.tick(runtime)end
assert(sessions-baseline==12,'Session wait must be bounded to twelve attempts')
runtime.state='closing';time=220;probe.tick(runtime);local queries=sessions
for i=1,200 do assert(not probe.tick(runtime))end
assert(sessions==queries,'Stopped diagnostic stays idle')
-- Marker format is fixed, consumed before activation, and never evaluated.
local old_io,old_rename=io.open,os.rename;local renamed=0
io.open=function()return{read=function()return'native-dof-v1\n'end,close=function()end}end
os.rename=function(a,b)assert(a=='fixture/wj-native-dof-selftest.request'and b==a..'.claimed.12');renamed=renamed+1;return true end
assert(factory.consume('fixture',12)and renamed==1)
io.open=function()return{read=function()return'return evil()'end,close=function()end}end
assert(not factory.consume('fixture',12)and renamed==1)
io.open,os.rename=old_io,old_rename
time=0;probe=factory.new(sr,function(s)logs[#logs+1]=s end)
runtime.active=true;runtime.state='active';local open_count=opens
runtime.handle.get=function(key)if key=='dof_mode'then return 1 else return true end end
assert(not probe.tick(runtime)and opens==open_count,'Adopt a manual opening without acquiring input twice')
time=40;probe.tick(runtime);assert(values.dof==false,'Continue the ON/OFF sequence from a manual opening')
runtime.active=false;runtime.state='closed';probe.tick(runtime)
print('Native DoF self-test: fixed one-shot marker, delayed bounded session checks, ON/OFF/ON, cleanup barrier and zero settings writes passed')

-- Exercise the real Photo runtime and render-flag ownership with no key events.
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local integration
local f=fixture(false,function(f,deps,sr)
 f.session=newproxy();f.saved.dof=false;f.saved.dof_mode=2;f.saved.scene_shader=4
 f.flags={dof_enabled=false,bloom_enabled=true}
 sr.Application.render_setting=function(key)return f.flags[key]end
 sr.Application.set_render_setting=function(key,value)f.flags[key]=value=='true'end
 integration=factory.new(sr,function()end);deps.store=integration.store(deps.store)
end)
local saved={};for k,v in pairs(f.saved)do saved[k]=v end
local saves=f.saves
local function step(seconds)
 f.step(seconds,1);return integration.tick(f.runtime)
end
assert(f.runtime.handle.get('dof_mode')==1 and f.runtime.handle.get('dof'))
step(60);assert(f.runtime.active and f.lease and f.camera_open,'Open through runtime, without virtual keys')
for i=1,4 do step(.3)end
assert(f.flags.dof_enabled and f.rate==1,'Native flag enabled without freezing gameplay')
step(40);for i=1,4 do step(.3)end;assert(not f.flags.dof_enabled)
step(30);for i=1,4 do step(.3)end;assert(f.flags.dof_enabled)
step(30);for i=1,4 do step(.3)end
assert(f.runtime.state=='closed'and not f.lease and not f.camera_open,'Retire camera and input')
assert(not f.flags.dof_enabled,'Restore pre-test native render flag')
assert(f.saves==saves,'No diagnostic settings writes through the real core')
for k,v in pairs(saved)do assert(f.saved[k]==v,'Saved preference changed: '..k)end
f.finish()
print('Native DoF self-test integration: real runtime open, native flag transitions, baseline restoration, input/camera cleanup, no synthetic keys or persistence passed')

-- The private-depth marker uses fixed numeric states, never arbitrary commands.
do
 local open_before,rename_before=io.open,os.rename
 io.open=function()return{read=function()return'private-depth-v1\n'end,close=function()end}end
 os.rename=function()return true end
 assert(factory.consume('fixture',12)=='private-depth-v1')
 io.open=function()return{read=function()return'native-dof-entity-v1\n'end,close=function()end}end
 assert(factory.consume('fixture',12)=='entity-getter-v1')
 io.open=function()return{read=function()return'native-dof-owner-v1\n'end,close=function()end}end
 assert(factory.consume('fixture',12)=='entity-owner-v1')
 io.open=function()return{read=function()return'native-dof-override-v1\n'end,close=function()end}end
 assert(factory.consume('fixture',12)=='native-override-v1')
 os.rename=function()return false end
 assert(not factory.consume('fixture',12),'An unclaimed request cannot activate')
 io.open,os.rename=open_before,rename_before
 local now=0;local saved=0;local open_count=0;local events={}
 local engine={Application={time_since_launch=function()return now end,main_world=function()return 1 end},Network={game_session=function()return newproxy()end}}
 local test=factory.new(engine,function(s)events[#events+1]=s end,'private-depth-v1')
 local store=test.store({new=function()return{load=function()return{}end,save=function()saved=saved+1 end}end}).new('fixture')
 local settings=store.load('dbf_freecam')
 assert(not settings.dof and settings.dof_mode==2 and settings.scene_shader==7 and settings.scene_depth_range==10)
 local game={state='closed',active=false,handle={set=function(k,v)settings[k]=v;return true end}}
 game.open=function()open_count=open_count+1;game.active=true;game.state='active';return true end
 game.close=function()game.active=false;game.state='closed';return true end
 now=60;test.tick(game);assert(open_count==1)
 now=100;test.tick(game);assert(settings.dof and settings.scene_shader==1 and settings.focus_distance==.7 and settings.aperture==1.2)
 now=130;test.tick(game);assert(settings.focus_distance==20 and settings.aperture==1.2)
 now=160;test.tick(game);assert(settings.focus_distance==20 and settings.aperture==22)
 now=190;test.tick(game);assert(not game.active and test.tick(game))
 assert(store.save('dbf_freecam',settings)and saved==0)
 assert(table.concat(events,'\n'):find('Depth shader self-test',1,true))
 assert(not pcall(factory.new,engine,function()end,'arbitrary'),'Reject unknown test modes')
end
print('Private depth test: consumed fixed marker, inverted depth, near/far focus, aperture, bounded close and no settings writes passed')

do
 local now,world,profiles,starts,steps,opens=0,{},0,0,0,0
 local engine={Application={time_since_launch=function()return now end,main_world=function()return world end},Network={game_session=function()return newproxy()end}}
 local game={active=false,close=function()end,open=function()opens=opens+1;return true end}
 local probe=factory.new(engine,function()end,'entity-owner-v1',function()
  starts=starts+1;local reader={done=false,profile_count=0};local n=0
  reader.tick=function(_,_,frame)assert(frame.world==world);steps=steps+1;n=n+1;if n==2 then reader.done=true;reader.profile_count=profiles end end
  reader.release=function()reader.done=false;reader.profile_count=0 end
  return reader
 end)
 now=60;probe.tick(game);probe.tick(game);probe.tick(game)
 assert(opens==0 and starts==1 and steps==2,'Intro session userdata cannot open Photo Mode without a lens')
 for i=1,100 do probe.tick(game)end
 assert(starts==1 and steps==2,'Empty scene retry remains idle for ten seconds')
 now=70;probe.tick(game);world={};probe.tick(game)
 assert(opens==0 and steps==2,'A world transition discards the pending readiness scan')
 now=80;profiles=6;probe.tick(game);probe.tick(game);probe.tick(game)
 assert(opens==1 and starts==3,'Readable profiles admit exactly one open')
end
print('Lens readiness: rejects intro session, bounded incremental scan, idle retry interval and world transition invalidation passed')

do
 local now,settings=0,{}
 local engine={Application={time_since_launch=function()return now end,main_world=function()return 1 end},Network={game_session=function()return newproxy()end}}
 local test=factory.new(engine,function()end,'native-override-v1')
 local store=test.store({new=function()return{load=function()return{}end,save=function()error('Must not save test settings')end}end}).new('fixture')
 settings=store.load('dbf_freecam');assert(settings.dof and settings.dof_mode==1 and settings.focus_distance==.7 and settings.aperture==1.2)
 local game={active=false,state='closed',handle={set=function(k,v)settings[k]=v;return true end}}
 game.open=function()game.active=true;game.state='active';return true end
 game.close=function()game.active=false;game.state='closed';return true end
 now=60;test.tick(game);now=100;test.tick(game);assert(settings.focus_distance==20 and settings.aperture==1.2)
 now=130;test.tick(game);assert(settings.aperture==22)
 now=160;test.tick(game);assert(not game.active and test.tick(game));assert(store.save('dbf_freecam',settings))
end
print('Native override self-test: fixed token, native mode, near/far/aperture phases, close and no settings persistence passed')

-- Fixed local binding control uses known color/depth handles with identical assets.
for _,mode in ipairs({'local-depth-control-v1','local-texture-control-v1','local-world-control-v1'})do
 local texture_control=mode=='local-texture-control-v1'
 local world_control=mode=='local-world-control-v1'
 local before_open,before_rename=io.open,os.rename
 io.open=function()return{read=function()return mode..'\n'end,close=function()end}end
 os.rename=function()return true end
 assert(factory.consume('fixture',12)==mode)
 io.open,os.rename=before_open,before_rename
 local now,settings=0,{}
 local engine={Application={time_since_launch=function()return now end,main_world=function()return 1 end},Network={game_session=function()return newproxy()end}}
 local test=factory.new(engine,function()end,mode)
 local store=test.store({new=function()return{load=function()return{}end,save=function()error('Must not save test settings')end}end}).new('fixture')
 settings=store.load('dbf_freecam')
 assert(not settings.dof and settings.scene_shader==7 and settings.scene_depth_range==(world_control and 10 or 1) and test.local_binding_probe.source==(world_control and 'linear_depth' or texture_control and 'atlas-string' or 'output_target'))
 local game={active=false,state='closed',handle={set=function(k,v)settings[k]=v;return true end}}
 game.open=function()game.active=true;game.state='active';return true end
 game.close=function()game.active=false;game.state='closed';return true end
 now=60;test.tick(game);now=100;test.tick(game)
 assert(test.local_binding_probe.source==(world_control and 'linear_depth' or texture_control and 'atlas-id' or 'linear_depth')and settings.scene_depth_range==(texture_control and 1 or 10))
 if world_control then assert(test.local_binding_probe.gui_world=='main')end
 now=130;test.tick(game);assert(test.local_binding_probe.source==(world_control and 'linear_depth' or texture_control and 'depth-id' or 'output_target')and settings.scene_depth_range==((texture_control or world_control)and 10 or 1))
 if world_control then assert(test.local_binding_probe.gui_world=='ui')end
 now=160;test.tick(game);assert(not game.active and test.tick(game));assert(store.save('dbf_freecam',settings))
end
assert(not pcall(factory.new,{},function()end,'local-copy-control-v1'),'Withdrawn copy test cannot construct')
print('Local binding control: fixed marker, color/depth/color transitions, no native lens activation or saved settings changes passed')

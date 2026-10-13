local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Backend=dofile(root..'input_release_backend.lua');local Release=dofile(root..'input_release.lua');local ffi=require('ffi')
local function fixture()
 local f={time=0,foreground=10,pid=41,valid=true,inside=true,physical={},events={},queued={},captured=false,ignore=false,counts={Keyboard=4,Mouse=5}}
 local labels={Keyboard={'w','space','left shift','unknown'},Mouse={'left','right','middle','x1','x2'}}
 local values={Keyboard={},Mouse={}}
 local api={}
 function api.current_pid()return 41 end;function api.now()return f.time end
 function api.foreground()if f.owner_error then error('owner read failed')end;return f.foreground end
 function api.valid_window()return f.valid end;function api.pid()return f.pid end
 function api.down(k)if f.key_error then error('physical read failed')end;return f.physical[k]==true end
 function api.mouse_inside()return f.inside end
 function api.send(keys)
  if f.before_send then f.before_send()end
  local accepted=f.refuse and 0 or(f.partial or #keys)
  for i=1,accepted do local k=keys[i];f.events[#f.events+1]=k;f.queued[#f.queued+1]=k end
  if f.switch_after_batch then f.foreground=99;f.pid=99 end
  return accepted
 end
 local sr={}
 for _,device in ipairs({'Keyboard','Mouse'})do
  local name=device;local d={};sr[name]=d
  function d.active()return not f.inactive end
  function d.num_buttons()return f.counts[name]end
  function d.button(i)if f.sdk_error then error('SDK read failed')end;assert(i>=0 and i<f.counts[name]);return values[name][i]or 0 end
  function d.button_name(i)return labels[name][i+1]end
 end
 function f.hold(device,index,physical)local name=labels[device][index+1];values[device][index]=1;if physical~=false then local k=Backend.key_for(device,name);if k then f.physical[k]=true end end end
 function f.drop(device,index)local k=Backend.key_for(device,labels[device][index+1]);if k then f.physical[k]=nil end;if not f.captured then values[device][index]=0 end end
 function f.advance(dt)
  f.time=f.time+(dt or .016)
  for _,k in ipairs(f.queued)do f.physical[k]=nil;if not f.captured and not f.ignore then for name,buttons in pairs(labels)do for i,label in ipairs(buttons)do if Backend.key_for(name,label)==k then values[name][i-1]=0 end end end end end
  f.queued={}
 end
 local backend=Backend.new(sr,api);local logs={};local control=Release.new(backend,function(s)logs[#logs+1]=s end)
 return f,backend,control,sr,values,logs
end
-- Encoder ABI and flags: UP-only for normal/extended keys and all mouse buttons.
do
 local events,size=Backend.encode(ffi,{87,163,19,1,2,4,5,6},function(k)return k==87 and 0x11 or k==163 and 0xE01D or k==19 and 0xE145 or 0 end)
 assert(size==(ffi.abi('64bit')and 40 or 28),'Win32 INPUT ABI changed')
 assert(events[0].type==1 and events[0].ki.wVk==0 and events[0].ki.wScan==0x11 and events[0].ki.dwFlags==10)
 assert(events[1].ki.wScan==0x1D and events[1].ki.dwFlags==11)
 assert(events[2].ki.wVk==19 and events[2].ki.dwFlags==2,'E1 key uses virtual-key UP fallback')
 for i,flags in ipairs({4,16,64,256,256})do local e=events[i+2];assert(e.type==0 and e.mi.dx==0 and e.mi.dy==0 and e.mi.dwFlags==flags)end
 assert(events[6].mi.mouseData==1 and events[7].mi.mouseData==2)
 assert(Backend.key_for('Keyboard','Left Ctrl')==162 and Backend.key_for('Keyboard','F24')==135 and Backend.key_for('Mouse','x2')==6)
 assert(Backend.key_for('Keyboard','unknown')==nil and Backend.key_for('Mouse','wheel')==nil)
 local list=Backend.keys_sorted({[16]=true,[160]=true,[161]=true,[87]=true});assert(#list==3 and list[1]==87)
end
-- W held on entry, physically released while captured: one UP before acquire and
-- one after restore; ONLY engine readback on later updates can verify release.
do
 local f,b,c,sr,v=fixture();f.hold('Keyboard',0);assert(c.begin());assert(#f.events==1 and f.events[1]==87 and not c.verified)
 assert(c.entry_ready()==false,'Same-frame SendInput acceptance is not engine proof');f.advance();assert(c.entry_ready())
 f.captured=true;f.hold('Keyboard',0);f.advance(.06);assert(c.observe());f.drop('Keyboard',0);assert(v.Keyboard[0]==1)
 assert(c.finish());f.advance();assert(not c.tick(false)and c.pending,'Restoration ordering is required; capture still discards UP')
 -- The caller must restore the gate first. A fresh session tests that order.
 f.captured=false;f.ignore=true;for i=1,12 do f.advance();c.tick(false)end;assert(not c.pending and not c.verified and #f.events==2,'No repeated release injection')
end
do
 local f,b,c,sr,v=fixture();f.hold('Keyboard',0);assert(c.begin());f.advance();assert(c.entry_ready());f.captured=true
 f.hold('Keyboard',1);f.hold('Mouse',0);f.advance(.06);c.observe();f.drop('Keyboard',1);f.drop('Mouse',0)
 f.captured=false;assert(c.finish());local n=#f.events;f.advance();assert(c.tick(false)and c.verified and not c.pending)
 assert(n==4 and f.events[2]==32 and f.events[3]==87 and f.events[4]==1,'Release union includes entry and captured buttons')
 assert(c.finish()and #f.events==n,'Repeated cleanup never injects again')
 assert(not c.state().pad_supported,'Pads have no verified reset path')
end
-- SDK-latched key with no physical down state still maps to a release; unknown
-- names cannot silently become verified just because no known VK was released.
do
 local f,b,c=fixture();f.hold('Keyboard',0,false);assert(c.begin()and f.events[1]==87);f.advance();assert(c.entry_ready());c.finish();f.advance();c.tick(false)
 local f2,b2,c2=fixture();f2.hold('Keyboard',3,false);assert(c2.begin()and #f2.events==0);for i=1,12 do f2.advance();c2.entry_ready()end;assert(not c2.verified and not c2.pending)
end
-- Focus loss, another PID, retired/replaced HWND, and read errors never cause a
-- release to another application. No deferred post-Photo background injection.
for _,kind in ipairs({'foreign','none','retired','replacement'})do
 local f,b,c=fixture();f.hold('Keyboard',0);assert(c.begin());f.advance();c.entry_ready();local n=#f.events
 if kind=='foreign'then f.pid=99 elseif kind=='none'then f.foreground=0 elseif kind=='retired'then f.valid=false else f.foreground=11 end
 assert(not c.finish()and #f.events==n and not c.pending);f.pid=41;f.foreground=10;f.valid=true;f.advance();c.tick(false);assert(#f.events==n)
end
do
 local f,b,c=fixture();f.pid=99;f.hold('Keyboard',0);assert(not c.begin()and #f.events==0)
 local f2,b2,c2=fixture();f2.key_error=true;assert(not c2.begin()and #f2.events==0)
 local f3,b3,c3=fixture();f3.hold('Keyboard',0);c3.begin();f3.owner_error=true;assert(not c3.finish()and #f3.events==1);f3.owner_error=false;assert(c3.finish()and #f3.events==2)
end
-- Read-only observations are throttled and never inject; buttons pressed while
-- another app has focus do not join the Photo cache.
do
 local f,b,c=fixture();c.begin();local n=#f.events;f.hold('Keyboard',1);c.observe();assert(#c.state().keys==0)
 f.pid=99;f.advance(.06);assert(not c.observe()and #c.state().keys==0);f.pid=41;f.advance(.06);assert(c.observe()and #c.state().keys==1 and #f.events==n)
end
-- Native acceptance/refusal/partial batches are separate from engine proof.
do
 local f,b,c=fixture();f.refuse=true;f.hold('Keyboard',0);assert(not c.begin()and not c.verified);f.advance();assert(not c.entry_ready())
 local f2,b2,c2=fixture();for k=65,80 do f2.physical[k]=true end;f2.partial=3;assert(not c2.begin()and #f2.events==3)
 local f3,b3,c3=fixture();for k=65,80 do f3.physical[k]=true end;f3.switch_after_batch=true;assert(not c3.begin()and #f3.events==8,'Each bounded batch rechecks foreground ownership')
 local f4,b4,c4=fixture();f4.hold('Keyboard',0);f4.hold('Mouse',0);f4.inside=false;assert(not c4.begin()and #f4.events==1 and f4.events[1]==87,'Outside-client mouse UP is skipped; keyboard UP is still sent')
end
-- Inactive, missing, changed, or failing SDK bindings cannot fabricate readback.
do
 local f,b,c,sr,v=fixture();f.inactive=true;f.physical[87]=true;assert(c.begin());f.inactive=false;f.advance();assert(not c.entry_ready());assert(c.finish());f.advance();assert(c.tick(false),'Fresh restored snapshot can recover device availability')
 local f2,b2,c2,sr2=fixture();sr2.Mouse=nil;assert(c2.begin());for i=1,12 do f2.advance();c2.entry_ready()end;assert(not c2.verified)
 local f3,b3,c3,sr3=fixture();f3.hold('Keyboard',0);c3.begin();sr3.Keyboard.button_name=function()return 's'end;f3.advance();assert(not c3.entry_ready())
 local f4,b4,c4=fixture();f4.hold('Keyboard',0);c4.begin();f4.sdk_error=true;f4.advance();assert(not c4.entry_ready())
 local f5,b5,c5=fixture();f5.counts.Keyboard=999999;assert(c5.begin());f5.advance();assert(not c5.entry_ready(),'Invalid SDK button counts are bounded')
end
-- State snapshots expose copies, so external diagnostics cannot mutate caches.
do local f,b,c=fixture();f.hold('Keyboard',0);c.begin();local s=c.state();s.keys[1]=65;s.buttons[1].name='s';assert(c.state().keys[1]==87 and c.state().buttons[1].name=='w')end
print('Photo input release: ownership, UP encoding, held union, async SDK readback, failure bounds, and focus safety passed')

-- Real controller lifecycle, with actual input_release manager and fake OS/SDK.
-- An update epoch is distinct from render ticks: repeated renders cannot start
-- a pause while the engine has not consumed the queued gameplay release.
local Controller=dofile(root..'controller.lua')
local function lifecycle(hover)
 local f,b,release,sr,values,logs=fixture();local photo={};local keys={};local epoch=0;local acquired,released,paused=0,0,0;local rate=1;local valid=true;local chat=false;local open=false;local order={};local spec;local control_values;local unregister=0;local release_failed=false
 local input={down=function(k)return keys[k]or false end,focused=function()return f.foreground==10 and f.pid==41 and f.valid end,chat_active=function()return chat end,pause_allowed=function()return true end,
  acquire=function()order[#order+1]='acquire';assert(release.verified and epoch>0,'Capture requires post-update engine readback');acquired=acquired+1;f.captured=true;return{}end,
  release=function()order[#order+1]='restore';if release_failed then return false,'Provider restoration pending'end;released=released+1;f.captured=false;return true end,
  sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
 local api={camera_input=input,is_open=function()return open end,close=function()open=false;return true end,
  register=function(def)spec=def;control_values={};for _,page in ipairs(def.pages)do for _,c in ipairs(page.controls)do control_values[c.id]=c.default end end
   return{get=function(k)return control_values[k]end,set=function(k,v)control_values[k]=v;return true end,unregister=function()unregister=unregister+1 end}
  end}
 local hover_owned=false;local restore_epoch
 local freeze={start=function()order[#order+1]='freeze';assert(f.captured and release.verified);if hover then assert(hover_owned and hover.ready,'Hover control must be ready before freezing')end;paused=paused+1;rate=0;return true end,
  release=function()order[#order+1]='unpause';if hover and hover.fail_resume then return false,'Time restoration pending'end;rate=1;if hover_owned then restore_epoch=restore_epoch or epoch end;return true end,hold=function()return true end}
 if hover then
  function freeze.prepare()
   order[#order+1]='prepare';assert(order[#order-1]=='UP','Input releases must precede the hover override')
   if hover.fail_prepare then return false,'Hover input unsupported'end
   assert(not restore_epoch);hover_owned=true;return true
  end
  function freeze.ready()return hover.ready==true,'Hover controls are still nonzero'end
  function freeze.needs_input_capture()return hover_owned and rate==0 end
  function freeze.cleanup_pending()return restore_epoch~=nil end
 end
 local orig_send=b.send;b.send=function(owner,cached)order[#order+1]=f.captured and'BAD_CAPTURED_UP'or'UP';return orig_send(owner,cached)end
 DBFMCM=api;DBF_PHOTO_STANDALONE_API=nil
 local c=Controller.new(photo,{},function()return valid end,function(s)logs[#logs+1]=s end,freeze,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,release,function()return epoch end)
 local function tick(engine)
  f.advance();if engine then assert(rate>0,'Deferred entry must leave gameplay unpaused');epoch=epoch+1;if restore_epoch and epoch>restore_epoch then hover_owned=false;restore_epoch=nil;order[#order+1]='height_restore'end end;c.tick(.016)
 end
 local function press(k,engine)keys[k]=true;tick(engine);keys[k]=false end
 tick()
 return{f=f,b=b,c=c,release=release,photo=photo,keys=keys,values=values,logs=logs,order=order,tick=tick,press=press,
  counts=function()return acquired,released,paused,unregister end,rate=function()return rate end,hover_owned=function()return hover_owned,restore_epoch~=nil end,
  chat=function(v)chat=v end,valid=function(v)valid=v end,menu=function(v)open=v end,provider_fail=function(v)release_failed=v end,
  disable=function()control_values.enabled=false;for _,entry in ipairs(spec.pages[1].controls)do if entry.id=='enabled'then entry.on_change(false)end end end,
  swap_input=function()local other={};for k,v in pairs(api.camera_input)do other[k]=v end;api.camera_input=other end,
  button=function()for _,entry in ipairs(spec.pages[1].controls)do if entry.id=='toggle'then return entry.on_activate end end end}
end
do
 local s=lifecycle();s.f.hold('Keyboard',0);s.press(80);assert(s.c.entry_pending()and not s.photo.active and s.rate()==1)
 local a,r,p=s.counts();assert(a==0 and p==0)
 s.tick();s.tick();assert(s.c.entry_pending()and not s.photo.active,'Render-only frames must not acquire/pause')
 s.tick(true);a,r,p=s.counts();assert(s.photo.active and a==1 and p==1 and not s.c.entry_pending())
 assert(s.order[#s.order-1]=='acquire'and s.order[#s.order]=='freeze')
 -- A held Space released physically during capture remains in the SDK cache.
 s.f.hold('Keyboard',1);s.f.advance(.06);s.c.tick(.016);s.f.drop('Keyboard',1);local n=#s.f.events
 local before_order=#s.order;s.press(80);assert(not s.photo.active and s.release.pending and #s.f.events>n)
 local restore,up;for i=before_order+1,#s.order do if s.order[i]=='restore'then restore=i elseif s.order[i]=='UP'then up=i end;assert(s.order[i]~='BAD_CAPTURED_UP')end
 assert(restore and up and restore<up,'Exit UP must follow provider/Window restoration')
 s.tick();assert(s.release.verified and not s.release.pending and s.values.Keyboard[1]==0)
 assert(s.c.close());DBFMCM=nil
end
-- Pending entry cancels cleanly for a fresh P edge, Escape, chat, focus/world
-- loss, disabled preference, provider replacement, and explicit shutdown.
for _,kind in ipairs({'toggle','escape','chat','focus','scene','disabled','provider','input-provider','close'})do
 local s=lifecycle();s.f.hold('Keyboard',0);s.press(80);s.tick();assert(s.c.entry_pending())
 if kind=='toggle'then s.press(80)
 elseif kind=='escape'then s.press(27)
 elseif kind=='chat'then s.chat(true);s.tick(true)
 elseif kind=='focus'then s.f.pid=99;s.tick()
 elseif kind=='scene'then s.valid(false);s.tick(true)
 elseif kind=='disabled'then s.disable();s.tick()
 elseif kind=='provider'then DBFMCM=nil;s.tick()
 elseif kind=='input-provider'then s.swap_input();s.tick()
 else assert(not s.c.close(),'Pending cleanup must remain retryable until later SDK readback')end
 assert(not s.c.entry_pending()and not s.photo.active);local a,r,p=s.counts();assert(a==0 and p==0,'Cancellation must never capture or freeze: '..kind)
 s.f.pid=41;s.tick();s.c.close();DBFMCM=nil
end
-- An exhausted SDK readback or missing game update cancels entry, keeps gameplay
-- running, and consumes the activation edge rather than reopening on held P.
do
 local s=lifecycle();s.f.ignore=true;s.f.hold('Keyboard',0);s.keys[80]=true;s.tick();for _=1,15 do s.tick(true)end
 local a,r,p=s.counts();assert(not s.photo.active and not s.c.entry_pending()and a==0 and p==0 and s.rate()==1)
 local n=#s.f.events;s.tick(true);assert(#s.f.events==n,'Held activation cannot retry a failed entry automatically');s.c.stop();DBFMCM=nil
 local stalled=lifecycle();stalled.press(80);for _=1,40 do stalled.tick()end;assert(not stalled.c.entry_pending()and not stalled.photo.active and stalled.rate()==1);stalled.tick();stalled.c.close();DBFMCM=nil
end
-- A failed provider restoration retains ownership and emits no exit UP until
-- its retry succeeds. Existing MCM button closing/opening behavior is preserved.
do
 local s=lifecycle();s.f.hold('Keyboard',0);s.menu(true);s.button()();assert(s.c.entry_pending()and not s.photo.active);s.tick(true);assert(s.photo.active)
 local n=#s.f.events;s.provider_fail(true);assert(not s.c.stop()and #s.f.events==n and s.f.captured)
 s.provider_fail(false);assert(s.c.stop()and #s.f.events>n and not s.f.captured);assert(not s.c.close());s.tick();assert(s.c.close());DBFMCM=nil
end
print('Photo input controller: deferred unpaused update, SDK proof, post-restoration exit, cancellation, bounded failure, held activation and cleanup retries passed')

-- SDK button release and hover readiness are separate requirements. Capture
-- cannot begin while automatic hover still generated a nonzero control vector.
do
 local hover={ready=false};local s=lifecycle(hover);s.f.hold('Keyboard',1);s.press(80)
 assert(s.c.entry_pending()and s.hover_owned()and not s.photo.active and s.rate()==1)
 s.tick(true);local a,_,p=s.counts();assert(a==0 and p==0 and s.release.verified and s.c.entry_pending())
 s.tick();assert(s.c.entry_pending()and not s.photo.active)
 hover.ready=true;s.tick(true);a,_,p=s.counts();assert(s.photo.active and a==1 and p==1)
 assert(s.order[#s.order-1]=='acquire'and s.order[#s.order]=='freeze')
 local begin=#s.order;s.menu(true);s.tick();assert(not s.photo.active and s.rate()==1 and not s.f.captured)
 local unpause,restore;for i=begin+1,#s.order do if s.order[i]=='unpause'then unpause=unpause or i elseif s.order[i]=='restore'then restore=i end end
 assert(unpause and restore and unpause<restore,'MCM handoff must resume before dropping hover input suppression')
 local owned,pending=s.hover_owned();assert(owned and pending,'Data restoration must wait for resumed engine progress')
 s.menu(false);s.tick(true);assert(not s.hover_owned());s.c.close();DBFMCM=nil
end
for _,kind in ipairs({'cancel','timeout','unsupported'})do
 local hover={ready=false,fail_prepare=kind=='unsupported'};local s=lifecycle(hover);s.press(80)
 if kind=='cancel'then s.tick();s.press(80)
 elseif kind=='timeout'then for _=1,40 do s.tick(true)end end
 assert(not s.c.entry_pending()and not s.photo.active and s.rate()==1)
 local a,_,p=s.counts();assert(a==0 and p==0,'Unqualified hover entry must never capture or freeze')
 s.tick(true);assert(not s.hover_owned(),'Cancelled hover preparation must restore its override')
 s.c.close();DBFMCM=nil
end
do
 local hover={ready=true};local s=lifecycle(hover);s.press(80);s.tick(true)
 local begin=#s.order;s.f.pid=99;s.tick()
 assert(not s.photo.active and s.rate()==1 and not s.f.captured)
 local unpause,restore;for i=begin+1,#s.order do if s.order[i]=='unpause'then unpause=unpause or i elseif s.order[i]=='restore'then restore=i end end
 assert(unpause and restore and unpause<restore,'Focus-loss handling must resume before explicit provider release')
 s.f.pid=41;s.tick(true);s.c.close();DBFMCM=nil
end
do
 local hover={ready=true};local s=lifecycle(hover);s.press(80);s.tick(true)
 hover.fail_resume=true;local n=#s.f.events
 assert(not s.c.stop()and s.rate()==0 and s.f.captured and #s.f.events==n,'Failed world resume must retain gameplay input suppression')
 hover.fail_resume=false;assert(s.c.stop()and s.rate()==1 and not s.f.captured)
 assert(not s.c.close(),'Module shutdown must retain a pending hover restore until positive engine progress')
 s.tick(true);assert(not s.hover_owned()and s.c.close());DBFMCM=nil
end
print('Photo hover entry: neutralization gate, capture order, cancel/timeout restoration, unsupported input and focus/MCM resume order passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Controller=dofile(root..'controller.lua')

-- The former blanket-release manager remains deliberately hostile here:
-- opening, rendering and closing Photo Mode must never call it.
local function lifecycle(hover)
 local photo={};local keys={};local epoch=0;local acquired,released,paused=0,0,0
 local rate=1;local valid=true;local chat=false;local open=false;local focused=true
 local order={};local spec;local values;local captured=false;local provider_failed=false
 local gameplay={ads=1,move=1,jump=1};local synthetic=0;local logs={}
 local legacy={begin=function()synthetic=synthetic+1;error('Synthetic entry release')end,
  entry_ready=function()synthetic=synthetic+1;error('Synthetic release readback')end,
  finish=function()synthetic=synthetic+1;error('Synthetic exit release')end,
  tick=function()synthetic=synthetic+1;error('Synthetic release tick')end,pending=true}
 local input={down=function(k)return keys[k]or false end,focused=function()return focused end,
  chat_active=function()return chat end,pause_allowed=function()return true end,
  acquire=function()
   order[#order+1]='acquire';if hover then assert(hover.ready and epoch>0,'Hover capture needs real neutral engine progress')end
   acquired=acquired+1;captured=true;return{}
  end,
  release=function()
   order[#order+1]='restore';if provider_failed then return false,'Provider restoration pending'end
   released=released+1;captured=false;return true
  end,
  sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
 local api={camera_input=input,is_open=function()return open end,close=function()open=false;return true end,
  register=function(def)
   spec=def;values={};for _,page in ipairs(def.pages)do for _,c in ipairs(page.controls)do values[c.id]=c.default end end
   return{get=function(k)return values[k]end,set=function(k,v)values[k]=v;return true end,unregister=function()end}
  end}
 local owned=false;local restore_epoch
 local freeze={start=function()
   order[#order+1]='freeze';assert(captured);if hover then assert(owned and hover.ready)end
   paused=paused+1;rate=0;return true
  end,
  release=function()
   order[#order+1]='unpause';if hover and hover.fail_resume then return false,'Time restoration pending'end
   rate=1;if owned then restore_epoch=restore_epoch or epoch end;return true
  end,hold=function()return true end}
 if hover then
  function freeze.prepare()
   order[#order+1]='prepare';if hover.fail_prepare then return false,'Hover input unsupported'end
   assert(not restore_epoch);owned=true;return true
  end
  function freeze.input_release_required()return owned end
  function freeze.ready()return hover.ready==true,'Hover controls are still nonzero'end
  function freeze.needs_input_capture()return owned and rate==0 end
  function freeze.cleanup_pending()return restore_epoch~=nil end
 end
 DBFMCM=api;DBF_PHOTO_STANDALONE_API=nil
 local c=Controller.new(photo,{},function()return valid end,function(s)logs[#logs+1]=s end,
  freeze,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,legacy,function()return epoch end)
 local function tick(engine)
  if engine then
   assert(rate>0,'Deferred hover entry must leave gameplay unpaused');epoch=epoch+1
   if restore_epoch and epoch>restore_epoch then owned=false;restore_epoch=nil;order[#order+1]='height_restore'end
  end
  c.tick(.016)
 end
 local function press(k,engine)keys[k]=true;tick(engine);keys[k]=false end
 tick()
 return{c=c,photo=photo,gameplay=gameplay,keys=keys,logs=logs,order=order,tick=tick,press=press,
  counts=function()return acquired,released,paused,synthetic end,rate=function()return rate end,
  captured=function()return captured end,owned=function()return owned,restore_epoch~=nil end,
  real_release=function(action)gameplay[action]=0 end,
  chat=function(v)chat=v end,valid=function(v)valid=v end,menu=function(v)open=v end,
  focus=function(v)focused=v end,provider_fail=function(v)provider_failed=v end,
  disable=function()values.enabled=false;for _,entry in ipairs(spec.pages[1].controls)do if entry.id=='enabled'then entry.on_change(false)end end end,
  swap_input=function()local other={};for k,v in pairs(api.camera_input)do other[k]=v end;api.camera_input=other end,
  button=function()for _,entry in ipairs(spec.pages[1].controls)do if entry.id=='toggle'then return entry.on_activate end end end}
end

do
 local s=lifecycle();s.press(80);local a,r,p,n=s.counts()
 assert(s.photo.active and not s.c.entry_pending()and a==1 and p==1 and n==0,'Normal entry should preserve inputs without release/readback delay')
 assert(s.gameplay.ads==1 and s.gameplay.move==1 and s.gameplay.jump==1,'Entry discarded held gameplay actions')
 s.tick();assert(s.gameplay.ads==1,'Camera render discarded held ADS')
 -- Native capture may forward the actual release of a button held at entry.
 s.real_release('jump');assert(s.gameplay.jump==0 and s.gameplay.ads==1)
 s.press(80);a,r,p,n=s.counts()
 assert(not s.photo.active and not s.captured()and r==1 and n==0 and s.gameplay.ads==1 and s.gameplay.move==1,'Exit discarded held actions')
 assert(s.c.close(),'An unused legacy manager must not block shutdown');DBFMCM=nil
end
do
 local s=lifecycle();s.menu(true);s.button()();assert(s.photo.active and s.gameplay.ads==1)
 s.provider_fail(true);assert(not s.c.stop()and s.captured()and s.gameplay.ads==1)
 s.provider_fail(false);assert(s.c.stop()and not s.captured()and s.gameplay.ads==1)
 local _,_,_,n=s.counts();assert(n==0 and s.c.close());DBFMCM=nil
end
print('Photo input preservation: held ADS/actions survive immediate entry, render and exit; real release and provider cleanup remain intact')

-- The data-only hover guard still waits for a genuine positive engine update
-- and neutral movement/jump. It never manufactures KEYUP/mouseUP or clears ADS.
do
 local hover={ready=false};local s=lifecycle(hover);s.press(80)
 assert(s.c.entry_pending()and s.owned()and not s.photo.active and s.rate()==1)
 s.tick();s.tick();assert(s.c.entry_pending(),'Render-only frames cannot qualify the hover guard')
 s.tick(true);local a,_,p,n=s.counts();assert(a==0 and p==0 and n==0 and s.c.entry_pending())
 assert(s.gameplay.ads==1 and s.gameplay.move==1 and s.gameplay.jump==1,'Hover preparation synthesized releases')
 hover.ready=true;s.tick();assert(s.photo.active and s.rate()==0 and s.gameplay.ads==1)
 local begin=#s.order;s.menu(true);s.tick();assert(not s.photo.active and s.rate()==1 and not s.captured())
 local unpause,restore;for i=begin+1,#s.order do if s.order[i]=='unpause'then unpause=unpause or i elseif s.order[i]=='restore'then restore=i end end
 assert(unpause and restore and unpause<restore,'Hover handoff must resume before dropping input capture')
 local owned,pending=s.owned();assert(owned and pending)
 s.menu(false);s.tick(true);assert(not s.owned()and s.c.close());DBFMCM=nil
end
for _,kind in ipairs({'toggle','escape','chat','focus','scene','disabled','provider','input-provider','close','timeout','unsupported'})do
 local hover={ready=false,fail_prepare=kind=='unsupported'};local s=lifecycle(hover);s.press(80)
 if kind=='toggle'then s.tick();s.press(80)
 elseif kind=='escape'then s.press(27)
 elseif kind=='chat'then s.chat(true);s.tick(true)
 elseif kind=='focus'then s.focus(false);s.tick()
 elseif kind=='scene'then s.valid(false);s.tick(true)
 elseif kind=='disabled'then s.disable();s.tick()
 elseif kind=='provider'then DBFMCM=nil;s.tick()
 elseif kind=='input-provider'then s.swap_input();s.tick()
 elseif kind=='close'then s.c.close()
 elseif kind=='timeout'then for _=1,40 do s.tick(true)end end
 local a,_,p,n=s.counts();assert(not s.c.entry_pending()and not s.photo.active and s.rate()==1 and a==0 and p==0 and n==0,'Unsafe hover cancellation captured, paused or released inputs: '..kind)
 assert(s.gameplay.ads==1 and s.gameplay.move==1 and s.gameplay.jump==1)
 s.focus(true);s.tick(true);assert(not s.owned());s.c.close();DBFMCM=nil
end
do
 local hover={ready=true};local s=lifecycle(hover);s.press(80);s.tick(true)
 hover.fail_resume=true;assert(not s.c.stop()and s.rate()==0 and s.captured(),'Failed world resume must retain hover input suppression')
 hover.fail_resume=false;assert(s.c.stop()and s.rate()==1 and not s.captured())
 assert(not s.c.close(),'Hover cleanup must wait for resumed engine progress')
 s.tick(true);assert(not s.owned()and s.c.close());local _,_,_,n=s.counts();assert(n==0);DBFMCM=nil
end
print('Photo hover input preservation: neutral engine gate, cancellation/timeout, and deferred time/data restoration remain safe without synthetic releases')

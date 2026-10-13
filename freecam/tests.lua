local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'controller.lua')
local active,focus,menu,held=false,true,false,false
local sample={wheel=0};local values;local spec
local provider={down=function(k)return k==80 and held end,focused=function()return focus end,
    acquire=function()if menu or not focus then return nil,'busy' end;active=true;return {} end,
    release=function()active=false;return true end,sample=function()return active and focus and not menu and sample or nil end}
DBFMCM={camera_input=provider,is_open=function()return menu end,close=function()menu=false;return true end,
    register=function(def)
        spec=def;values={};for _,c in ipairs(def.pages[1].controls)do values[c.id]=c.default end
        return {get=function(k)return values[k]end,set=function(k,v)values[k]=v;return true end,unregister=function()end}
    end}
local photo={active=false,input={}};local cfg={};local valid=true
local c=module.new(photo,cfg,function()return valid end,function()end)
c.tick(0.016);held=true;c.tick(0.016);assert(photo.active and active)
sample={wheel=120,forward=true};c.tick(0.016);assert(values.speed==3.6 and photo.input.forward and cfg.PHOTO_SPEED==3.6)
sample.wheel=120000;c.tick(0.016);assert(values.speed==50)
sample.wheel=-120000;c.tick(0.016);assert(values.speed==0.1)
sample.escape=true;c.tick(0.016);assert(not photo.active and not active)
held=false;c.tick(0.016);held=true;sample={wheel=0};c.tick(0.016);assert(active)
focus=false;c.tick(0.016);assert(photo.active and not active)
focus=true;c.tick(0.016);assert(photo.active and active);assert(c.stop())
focus=true;held=false;c.tick(0.016);held=true;c.tick(0.016);assert(active)
valid=false;c.tick(0.016);assert(not active)
valid=true;menu=true;spec.pages[1].controls[5].on_activate();assert(active and not menu)
DBFMCM=nil;c.tick(0.016);assert(not active and not photo.active)
assert(c.close())
-- Register against the real MCM schema and exercise its authoritative handle.
local core=dofile('src/core.lua')
DBFMCM=core.new(nil,function()end)
DBFMCM.camera_input=provider;DBFMCM.is_open=function()return menu end;DBFMCM.close=function()menu=false;return true end
held=false;focus=true;menu=false;valid=true;sample={wheel=0}
local real=module.new(photo,cfg,function()return valid end,function()end)
real.tick(0.016)
local h=assert(DBFMCM.mods.dbf_freecam).handle
assert(h.get('toggle_key')==80);assert(h.get('up_key')==16);assert(h.get('slowmo_key')==220);assert(h.set('forward_key',73));
assert(h.activate('toggle'));assert(active)
sample.wheel=120;real.tick(0.016);assert(math.abs(h.get('speed')-3.6)<1e-6)
assert(h.set('enabled',false));assert(not active and not photo.active)
assert(real.close());assert(not DBFMCM.mods.dbf_freecam)
local attempts=0;provider.pause_allowed=function()return false end
local freeze={start=function()attempts=attempts+1;return true end,hold=function()return true end,release=function()return true end}
local multiplayer=module.new(photo,cfg,function()return true end,function()end,freeze)
held=false;multiplayer.tick(0.016);held=true;multiplayer.tick(0.016)
assert(photo.active and active and attempts==0);assert(multiplayer.close())
-- Defaults never migrate or overwrite the user's saved activation/movement keys.
local persisted={toggle_key=78,forward_key=73,slowmo_key=84}
DBFMCM=core.new({load=function(id)return id=='dbf_freecam'and persisted or {}end,save=function()error('Registration must not write saved settings')end},function()end)
DBFMCM.camera_input=provider;DBFMCM.is_open=function()return false end;held=false
local retained=module.new({}, {},function()return true end,function()end);retained.tick(.016)
local saved_mod=DBFMCM.mods.dbf_freecam;assert(saved_mod.controls.slowmo_key.default==220)
assert(saved_mod.handle.get('toggle_key')==78 and saved_mod.handle.get('forward_key')==73 and saved_mod.handle.get('slowmo_key')==84)
assert(retained.close())
print('Freecam: key edges, wheel bounds, Escape/scene exit and focus retention, MCM button and provider replacement passed')
-- An authoritative game chat reader suppresses only hotkeys that open photo
-- controls. The held edge is still consumed, so closing chat cannot activate P.
do
 local options=dofile(root..'photo_options.lua');local pressed={};local chat=true;local acquired,released,mode,queries=0,0,0,0
 local input={down=function(key)return pressed[key]or false end,focused=function()return true end,
  chat_active=function()queries=queries+1;return chat end,
  acquire=function()acquired=acquired+1;mode=3;return{}end,release=function()released=released+1;mode=0;return true end,
  set_focus=function(menu)mode=menu and 1 or 3;return true end,
  sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()return{click=false,wheel=0,dt=.016}end}
 local service=core.new(nil,function()end);service.camera_input=input;service.is_open=function()return false end;service.close=function()return true end
 service.photo_standalone=true;service.photo_resolution=function()return 1920,1080 end;service.create_photo_view=function()return{}end
 local pane={};local factory={new=function()return{bind=function(_,pages)pane.pages=pages end,close=function()end,draw=function()end,tick=function()end,
  editing_key=function()return false end,editing_text=function()return false end,blur=function()return true end,dismiss=function()return false end}end}
 DBFMCM=service;local state={};local adapter=module.new(state,{},function()return true end,function()end,nil,options,nil,factory)
 local function tick()adapter.tick(.016)end
 local function press(key)pressed[key]=true;tick();pressed[key]=false;tick()end
 tick();local handle=service.mods.dbf_freecam.handle
 pressed[80]=true;tick();tick();assert(not state.active and acquired==0 and queries==1,'Typing P in active game chat must neither acquire input nor open Photo Mode')
 chat=false;tick();assert(not state.active and acquired==0,'Closing chat with P held must not open Photo Mode later')
 pressed[80]=false;tick();press(80);assert(state.active and acquired==1 and mode==3,'A fresh P edge after leaving chat must work normally')
 chat=true;press(9);assert(state.active and mode==3,'Chat must retain Tab rather than give the menu cursor focus')
 chat=false;press(9);assert(mode==1);chat=true;press(9);assert(mode==3,'Returning to camera from existing menu focus must remain available')
 press(72);assert(handle.get('hide_controls')==true and state.active,'Chat must not prevent hiding existing photo controls')
 press(72);assert(handle.get('hide_controls')==true,'Chat must suppress the show-controls hotkey')
 press(80);assert(state.active and handle.get('hide_controls')==true,'Chat must suppress P revealing a hidden active menu')
 chat=false;press(72);assert(handle.get('hide_controls')==false);chat=true;press(80);assert(not state.active and mode==0,'Chat must not trap the normal visible Photo Mode exit hotkey')
 handle.set('enabled',false);press(80);assert(acquired==1,'Chat must not open the disabled standalone recovery menu')
 handle.set('enabled',true);handle.set('toggle_key',82);press(82);assert(not state.active and acquired==1,'The chat gate must follow a rebound photo hotkey')
 input.chat_active=function()return nil end;press(82);assert(state.active,'An unavailable reader must not permanently block every photo opening')
 press(82);input.chat_active=function()error('Reader retired')end;press(82);assert(state.active,'A retired reader must not crash input polling or lock the menu')
 assert(adapter.close());DBFMCM=nil
end
print('Photo chat activation: authoritative callback gate, no input acquisition, held/rebound edges, Tab/show-only suppression, existing exit/hide controls, standalone recovery and unavailable-reader safety passed')
do
 local options=dofile(root..'photo_options.lua');local capture_factory=dofile(root..'screenshot.lua');local keys={};local chat,editing,rebind,mcm,focused=false,false,false,false,true
 local photo={};local visible=false;local requested,captured,mode=0,0,0;local acquired_bindings
 local files={};local real_open,real_remove=io.open,os.remove
 io.open=function(path,how)
  if how=='rb'then local value=files[path];if not value then return end;return{read=function(n)return value:sub(1,n)end,close=function()end}end
  return real_open(path,how)
 end
 os.remove=function(path)files[path]=nil;return true end
 local screenshots=capture_factory.new({capture=function(path)captured=captured+1;assert(not visible and photo.options.hide_hud==true,'Key capture must use clean hidden-GUI frames');files[path]='DDS stub';return true end},
  function(_,png)files[png]='\137PNG\r\n\26\n';return true end,'test-shot-folder',function()end)
 local original_request=screenshots.request;screenshots.request=function()requested=requested+1;return original_request()end
 local input={down=function(key)return keys[key]or false end,focused=function()return focused end,chat_active=function()return chat end,
  acquire=function(bindings)acquired_bindings=bindings;mode=3;return{}end,release=function()mode=0;return true end,set_focus=function(menu)mode=menu and 1 or 3;return true end,
  sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()return{click=false,wheel=0,dt=.016}end}
 local api=core.new(nil,function()end);api.camera_input=input;api.is_open=function()return mcm end;api.close=function()mcm=false;return true end
 api.photo_resolution=function()return 1920,1080 end;api.create_photo_view=function()return{}end
 local panel={bind=function()end,close=function()visible=false end,draw=function(_,_,_,hidden)visible=not hidden end,tick=function()end,
  editing_key=function()return rebind end,editing_text=function()return editing end,blur=function()editing=false;return true end,dismiss=function()return false end}
 DBFMCM=api;local adapter=module.new(photo,{},function()return true end,function()end,nil,options,nil,{new=function()return panel end},nil,nil,screenshots)
 local function tick(count)for _=1,count or 1 do adapter.tick(.016)end end
 local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
 tick();local handle=api.mods.dbf_freecam.handle;assert(handle.get('screenshot_key')==19)
 press(19);assert(requested==0,'Screenshot key must be Photo Mode only')
 keys[19]=true;press(80);assert(photo.active and acquired_bindings.screenshot==19 and requested==0,'Entering Photo Mode with Pause held must not trigger a delayed screenshot')
 keys[19]=false;tick();handle.set('hide_hud',false)
 keys[19]=true;tick(20);assert(requested==1 and captured==1 and visible and not screenshots.active()and handle.get('hide_hud')==false,'Holding Pause must capture once, then restore visible controls and saved HUD preference')
 keys[19]=false;tick();press(19);tick(15);assert(requested==2 and captured==2,'A second Pause edge must start a new clean capture')
 for _,kind in ipairs({'text','binding','chat','mcm','focus'})do
  if kind=='text'then editing=true elseif kind=='binding'then rebind=true elseif kind=='chat'then chat=true elseif kind=='mcm'then mcm=true else focused=false end
  local before=requested;keys[19]=true;tick();editing,rebind,chat,mcm,focused=false,false,false,false,true;tick();assert(requested==before,'Unsafe context or held completion must not capture: '..kind)
  keys[19]=false;tick()
 end
 handle.set('hide_controls',true);tick();press(19);tick(15)
 assert(captured==3 and not visible and handle.get('hide_controls')==true,'A key screenshot must retain previously hidden controls')
 handle.set('hide_controls',false);handle.set('screenshot_key',44);press(19);assert(requested==3,'Old Pause binding must stop taking screenshots after rebinding')
 press(44);tick(15);assert(captured==4 and visible,'A chosen Print Screen binding must use the same capture path (OS interception is a separate capability)')
 press(80);assert(not photo.active);assert(adapter.close());DBFMCM=nil;io.open,os.remove=real_open,real_remove
end
print('Photo screenshot key: Pause default/capture bindings, active-only edges, held/rebound keys, clean-frame capture, text/key/chat/MCM/focus suppression and visible/hidden GUI restoration passed')

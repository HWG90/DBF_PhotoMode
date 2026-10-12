-- Real menu mouse actions + P reopening, using persisted private/shared settings.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local controller=dofile(root..'controller.lua');local menu=dofile(root..'photo_menu.lua')
local options=dofile(root..'photo_options.lua')
local function copy(values)local result={};for key,value in pairs(values)do result[key]=value end;return result end
for _,standalone in ipairs({true,false})do
 local core=standalone and dofile(root..'vendor/core.lua')or dofile('src/core.lua')
 local saved={enabled=true,toggle_key=80,focus_key=9,hide_controls_key=72,speed=4.5,hide_controls=false,focus_distance=1.405,aperture=2,hide_hud=false}
 local function launch()
  local keys={};local mouse={};local commands={};local owned=false;local input_mode=0;local pauses=0
  local store={load=function(id)return id=='dbf_freecam'and copy(saved)or{}end,
   save=function(id,values)if id=='dbf_freecam'then saved=copy(values)end;return true end}
  local api=core.new(store,function()end);api.photo_standalone=standalone
  api.is_open=function()return false end;api.close=function()return true end
  api.photo_resolution=function()return 1920,1080 end
  api.create_photo_view=function()return {draw=function(value)commands=value end,release=function()commands={}end}end
  api.camera_input={down=function(key)return keys[key]or false end,focused=function()return true end,
   acquire=function()assert(not owned,'Input was stranded after closing');owned=true;input_mode=3;return{}end,
   release=function()owned=false;input_mode=0;return true end,set_focus=function(focus)assert(owned);input_mode=focus and 1 or 3;return true end,
   sample=function()assert(owned and input_mode==3);return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,
   menu_sample=function()assert(owned and input_mode==1);return{x=mouse.x,y=mouse.y,click=mouse.click or false,wheel=0,dt=.016}end}
  if standalone then DBFMCM=nil;DBF_PHOTO_STANDALONE_API=api else DBFMCM=api;DBF_PHOTO_STANDALONE_API=nil end
  local freeze={start=function()pauses=pauses+1;return true end,hold=function()return true end,release=function()return true end}
  local photo={};local adapter=controller.new(photo,{},function()return true end,function()end,freeze,options,nil,menu)
  local function tick()adapter.tick(.016)end
  local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
  local function click(which)
   local target;for _,command in ipairs(commands)do
    if(command.ui_key==which and command.ui_role=='button')or(which:sub(1,8)=='control:'and command.control_id==which:sub(9)and command.ui_role=='field')then target=command;break end
   end
   assert(target,'Button is not visible: '..which)
   mouse={x=target.x+target.w*.5,y=target.y+target.h*.5,click=true};tick();mouse.click=false;tick()
  end
  tick()
  return {photo=photo,api=api,adapter=adapter,tick=tick,press=press,click=click,
   visible=function()return #commands>0 end,owned=function()return owned end,pauses=function()return pauses end}
 end
 local session=launch();session.press(80)
 assert(session.photo.active and session.visible()and session.owned())
 session.press(9);session.click('exit')
 assert(not session.photo.active and not session.owned()and not session.visible(),'Mouse Exit must release photo input and view')
 session.press(80);assert(session.photo.active and session.visible()and session.owned(),'P must reopen after mouse Exit')
 session.press(9);session.click('hide')
 assert(session.photo.active and not session.visible()and saved.hide_controls==true,'Fixture must reproduce the persisted mouse-hidden state')
 session.press(80)
 assert(session.photo.active and session.visible()and session.owned(),'P must reveal the mouse-hidden active session')
 assert(saved.hide_controls==true,'Session visibility recovery must preserve the stored hidden preference')
 assert(saved.enabled==true and saved.toggle_key==80 and saved.speed==4.5 and saved.focus_distance==1.405 and saved.aperture==2 and saved.hide_hud==false,'Reopening changed unrelated preferences')
 -- Persist hidden UI again, close/restart the complete registration, and reopen.
 session.api.mods.dbf_freecam.handle.set('hide_controls',true);session.tick();assert(not session.visible())
 assert(session.adapter.close()and not session.owned());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
 assert(saved.hide_controls==true)
 session=launch();session.press(80)
 assert(session.photo.active and session.visible()and session.owned(),'Saved hidden controls must not survive fresh P entry invisibly')
 assert(saved.hide_controls==true,'Fresh entry must not rewrite saved visibility while recovering the session')
 session.press(80);assert(not session.photo.active and not session.owned(),'Visible P toggle must still exit Photo Mode')
 assert(session.adapter.close());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
 -- Standalone recovers settings without activating/enabling the camera. Shared
 -- MCM keeps its disabled guard because its separate settings host is reachable.
 saved.enabled=false;session=launch();session.press(80)
 assert(not session.photo.active and saved.enabled==false and session.pauses()==0,'Disabled recovery must not enable/move/pause the camera')
 if standalone then
  assert(session.owned()and session.visible(),'Standalone P must recover its otherwise unreachable Controls panel')
  session.click('exit');assert(not session.owned()and saved.enabled==false,'Recovery mouse Exit must preserve disabled state and release input')
  session.press(80);assert(session.visible()and session.owned()and saved.enabled==false)
  session.click('control:enabled');assert(saved.enabled==true and not session.photo.active,'Only explicit Enable click may change preference')
  session.press(80);assert(session.photo.active and session.visible()and session.owned()and session.pauses()==1,'P must start normally after enabling in recovered Controls')
 else assert(not session.owned()and not session.visible(),'Shared disabled state must remain guarded')end
 assert(session.adapter.close());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
end
print('Photo mouse reopen: real Exit/release/P, Hide/P reveal, saved hidden state across restart, standalone/MCM, preferences and disabled-state guards passed')

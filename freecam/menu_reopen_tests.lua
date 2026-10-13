-- Real menu mouse actions + P reopening, using persisted private/shared settings.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local controller=dofile(root..'controller.lua');local menu=dofile(root..'photo_menu.lua')
local options=dofile(root..'photo_options.lua')
local function copy(values)local result={};for key,value in pairs(values)do result[key]=value end;return result end
for _,standalone in ipairs({true,false})do
 local core=standalone and dofile(root..'vendor/core.lua')or dofile('src/core.lua')
 local saved={enabled=true,toggle_key=80,focus_key=9,hide_controls_key=72,speed=4.5,hide_controls=true,focus_distance=1.405,aperture=2,hide_hud=false,
  dof=true,dof_mode=2,exposure=1.5,contrast=110,saturation=80,scene_shader=3,scene_strength=45,
  show_legend=false,legend_open=false,legend_docked=false,legend_tab_y=22,legend_columns=1,legend_x=72,legend_y=58,legend_size=64,
  menu_x=.73,menu_y=.54,menu_scale=.85}
 local expected_layout={menu_x=saved.menu_x,menu_y=saved.menu_y,menu_scale=saved.menu_scale}
 local menu_keys={'hide_controls','show_legend','legend_open','legend_docked','legend_tab_y','legend_columns','legend_x','legend_y','legend_size'}
 local function check_menu_defaults()for _,key in ipairs(menu_keys)do assert(saved[key]==options.defaults[key],'Startup must reset only menu layout: '..key)end end
 local function check_photo_values()
  assert(saved.enabled==true and saved.toggle_key==80 and saved.focus_key==9 and saved.hide_controls_key==72 and saved.speed==4.5 and saved.focus_distance==1.405 and saved.aperture==2 and saved.hide_hud==false,'Menu restart changed camera preferences or bindings')
  assert(saved.dof==true and saved.dof_mode==2 and saved.exposure==1.5 and saved.contrast==110 and saved.saturation==80 and saved.scene_shader==3 and saved.scene_strength==45,'Menu restart changed scene or lens adjustments')
  for key,value in pairs(expected_layout)do assert(math.abs(saved[key]-value)<1e-9,'Main menu geometry must survive restart: '..key)end
 end
 local function launch()
  local keys={};local mouse={};local commands={};local owned=false;local input_mode=0;local pauses=0;local current_panel;local saves=0
  local store={load=function(id)return id=='dbf_freecam'and copy(saved)or{}end,
   save=function(id,values)if id=='dbf_freecam'then saves=saves+1;saved=copy(values)end;return true end}
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
  local factory={new=function(view,actions)current_panel=menu.new(view,actions);return current_panel end}
  local photo={};local adapter=controller.new(photo,{},function()return true end,function()end,freeze,options,nil,factory)
  local function tick()adapter.tick(.016)end
  local function rebind()
   DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil;tick()
   if standalone then DBF_PHOTO_STANDALONE_API=api else DBFMCM=api end;tick()
  end
  local function press(key)keys[key]=true;tick();keys[key]=false;tick()end
  local function click(which)
   local target;for _,command in ipairs(commands)do
    if(command.ui_key==which and command.ui_role=='button')or(which:sub(1,8)=='control:'and command.control_id==which:sub(9)and command.ui_role=='field')then target=command;break end
   end
   assert(target,'Button is not visible: '..which)
   mouse={x=target.x+target.w*.5,y=target.y+target.h*.5,click=true};tick();mouse.click=false;tick()
  end
  local function gesture(role,dx,dy)
   local target;for _,command in ipairs(commands)do if command.ui_role==role then target=command;break end end;assert(target)
   local before=saves;mouse={x=target.x+target.w*.25,y=target.y+target.h*.5,click=true};tick()
   mouse.x,mouse.y=mouse.x+dx,mouse.y+dy;tick();tick();assert(saves==before,'Holding a layout gesture must not write settings per frame')
   mouse.click=false;tick();tick();assert(saves==before+1,'Releasing one gesture must atomically save the layout once')
  end
  local function drag(dx,dy)gesture('move_handle',dx,dy)end
  local function resize(ratio)
   local bounds;for _,command in ipairs(commands)do if command.ui_role=='photo_panel'then bounds=command;break end end;assert(bounds)
   gesture('resize_grip',-bounds.w*(ratio-1),bounds.h*(ratio-1))
  end
  tick()
  return {photo=photo,api=api,adapter=adapter,tick=tick,press=press,click=click,drag=drag,resize=resize,rebind=rebind,panel=function()return current_panel end,
   visible=function()return #commands>0 end,owned=function()return owned end,pauses=function()return pauses end}
 end
 local session=launch();check_menu_defaults();check_photo_values()
 assert(session.panel().page==1 and session.panel().selection==1 and session.panel().scroll==0 and session.panel().size_scale==saved.menu_scale and session.panel().panel_x==saved.menu_x and session.panel().panel_y==saved.menu_y and not session.panel().editing_key()and not session.panel().editing_text(),'Fresh menu must reset navigation while restoring saved position/size')
 session.api.mods.dbf_freecam.handle.set_many({legend_open=false,legend_docked=false,legend_tab_y=31,legend_x=67,legend_y=53,legend_size=49})
 session.press(80)
 assert(session.photo.active and session.visible()and session.owned())
 session.press(9);session.drag(-120,80);session.resize(.9)
 assert(math.abs(saved.menu_scale-.765)<1e-9 and saved.menu_x~=.73 and saved.menu_y~=.54,'Dragging and resizing must reach the real stored schema')
 for key in pairs(expected_layout)do expected_layout[key]=saved[key]end
 assert(session.api.mods.dbf_freecam.controls.menu_x.page.id=='composition'and options.defaults.menu_x==nil,'Geometry must use registered Composition storage and stay outside photo resets')
 session.click('exit')
 assert(not session.photo.active and not session.owned()and not session.visible(),'Mouse Exit must release photo input and view')
 session.rebind()
 assert(saved.legend_open==false and saved.legend_docked==false and saved.legend_tab_y==31 and saved.legend_x==67 and saved.legend_y==53 and saved.legend_size==49,'API rebind must not repeat the startup reset')
 session.press(80);assert(session.photo.active and session.visible()and session.owned(),'P must reopen after mouse Exit')
 assert(saved.legend_x==67 and saved.legend_size==49,'Open/close must retain drawer movement within the current runtime')
 session.press(9);session.click('hide')
 assert(session.photo.active and not session.visible()and saved.hide_controls==true,'Fixture must reproduce the persisted mouse-hidden state')
 session.press(80)
 assert(session.photo.active and session.visible()and session.owned(),'P must reveal the mouse-hidden active session')
 assert(saved.hide_controls==true,'Session visibility recovery must preserve the stored hidden preference')
 assert(saved.enabled==true and saved.toggle_key==80 and saved.speed==4.5 and saved.focus_distance==1.405 and saved.aperture==2 and saved.hide_hud==false,'Reopening changed unrelated preferences')
 -- Persist hidden UI again, close/restart the complete registration, and reopen.
 session.api.mods.dbf_freecam.handle.set('hide_controls',true);session.tick();assert(not session.visible())
 session.panel().page=3;session.panel().selection=4;session.panel().scroll=2;session.panel().size_scale=.7
 assert(session.adapter.close()and not session.owned());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
 assert(saved.hide_controls==true)
 session=launch();check_menu_defaults();check_photo_values()
 assert(session.panel().page==1 and session.panel().selection==1 and session.panel().scroll==0 and session.panel().size_scale==saved.menu_scale and session.panel().panel_x==saved.menu_x and session.panel().panel_y==saved.menu_y,'Restart must reset navigation while retaining last menu position and size')
 session.press(80)
 assert(session.photo.active and session.visible()and session.owned(),'Saved hidden controls must not survive fresh P entry invisibly')
 assert(saved.hide_controls==false,'Startup must clear persisted hidden UI once')
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
print('Photo menu startup: main position/size survive real shared/private Core restart, exact-once drag/resize saves, navigation/drawer reset, photo values/bindings retained, mouse Exit/Hide/P and standalone disabled recovery passed')

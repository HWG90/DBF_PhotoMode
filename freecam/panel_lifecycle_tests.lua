local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua');local options=dofile(root..'photo_options.lua');local panel=dofile(root..'photo_menu.lua');local controller=dofile(root..'controller.lua')
local keys={};local focused=true;local main_menu=false;local mode=0;local rate=1;local commands
local input={down=function(k)return keys[k]or false end,focused=function()return focused end,pause_allowed=function()return true end,
 acquire=function()mode=3;return {}end,release=function()mode=0;return true end,set_focus=function(v)mode=v and 1 or 3;return true end,
 sample=function()assert(mode==3);return {wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()assert(mode==1);return {click=false,wheel=0}end}
local api=core.new(nil,function()end);api.camera_input=input;api.is_open=function()return main_menu end;api.close=function()main_menu=false;return true end
api.photo_resolution=function()return 1920,1080 end;api.create_photo_view=function()return {draw=function(c)commands=c end,release=function()commands={}end}end
DBFMCM=api
local freeze={start=function(v)rate=v or 0;return true end,release=function()rate=1;return true end,hold=function()return true end,rate=function()return rate end}
local effects={parameters={},shader_status='Shader unavailable: fixture material',release=function()return true end}
local photo={};local c=controller.new(photo,{},function()return true end,function()end,freeze,options,effects,panel)
c.tick(.016);keys[80]=true;c.tick(.016);assert(photo.active and rate==0 and mode==3 and #commands>0);keys[80]=false
local status;for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id=='shader_status'then status=control end end end
assert(status and status.label==effects.shader_status,'Runtime status must update registered text controls, outside MCM stored-value index')
effects.shader_status='';c.tick(.016);assert(status.label=='')
keys[9]=true;c.tick(.016);assert(mode==1 and photo.input.dt==0 and rate==0);keys[9]=false
keys[69]=true;c.tick(.016);keys[69]=false;c.tick(.016) -- Lens follows Camera actions.
keys[13]=true;c.tick(.016);keys[13]=false;c.tick(.016);keys[80]=true;c.tick(.016);assert(photo.active and rate==0,'Numeric editing owns the photo-toggle shortcut');keys[80]=false
keys[27]=true;c.tick(.016);keys[27]=false;c.tick(.016);assert(mode==1 and photo.active,'Escape cancels numeric entry before leaving menu')
keys[72]=true;c.tick(.016);assert(mode==3 and #commands==0 and rate==0);keys[72]=false
keys[9]=true;c.tick(.016);assert(mode==1 and #commands>0);keys[9]=false
focused=false;c.tick(.016);assert(mode==0 and photo.active and rate==0)
focused=true;c.tick(.016);assert(mode==1 and photo.active and rate==0)
main_menu=true;c.tick(.016);assert(mode==0 and photo.active and rate==0)
main_menu=false;c.tick(.016);assert(mode==1)
assert(api.mods.dbf_freecam.handle.get('slowmo_key')==220)
keys[84]=true;c.tick(.016);assert(rate==0,'T must no longer be the default slow-motion key');keys[84]=false;c.tick(.016)
keys[220]=true;c.tick(.016);assert(rate==0 and c.slowmo_active,'Selecting slow motion must retain Freeze Action');keys[220]=false;c.tick(.016);keys[220]=true;c.tick(.016);assert(rate==0 and not c.slowmo_active);keys[220]=false
keys[80]=true;c.tick(.016);assert(not photo.active and mode==0 and rate==1);assert(c.close());DBFMCM=nil
local runtime=dofile(root..'photo_runtime.lua')
local sr={Application={worlds=function()return{1}end},Gui={resolution=function()return 1920,1080 end},World={create_screen_gui=function()return {}end,destroy_gui=function()end}}
local fx=runtime.new(sr,{new=function()return {apply=function()return .9 end,release=function()return true end}end}, {layout=function()return {}end,shaders={''}},
 {new=function()return {apply=function()error('Renderer flag readback mismatch')end,release=function()return true end}end},function()end)
assert(fx.apply(1,2,3,{0,1,0},{1,0,0},options.defaults,.016)==false);assert(fx.lens_status:find('camera and pause retained',1,true));assert(fx.release())
print('Photo panel: menu/camera focus, hide/show, focus-loss pause, MCM handoff, slow motion, exit restore and effect-error containment passed')

-- Hide the whole bindings/Controls page only when MCM owns configuration.
for _,standalone in ipairs({false,true})do
 local a=core.new(nil,function()end);a.camera_input=input;a.is_open=function()return false end;a.photo_standalone=standalone;a.create_photo_view=function()return {}end
 local visible;local factory={new=function()return {bind=function(_,pages)visible=pages end,close=function()end,editing_key=function()return false end}end}
 if standalone then DBFMCM=nil;DBF_PHOTO_STANDALONE_API=a else DBFMCM=a;DBF_PHOTO_STANDALONE_API=nil end
 keys={};local ctrl=controller.new({}, {},function()return true end,function()end,nil,options,nil,factory);ctrl.tick(.016)
 assert(visible and (#visible==(standalone and 9 or 8)));assert(visible[1].id=='camera_tools'and visible[2].id=='lens');assert((visible[#visible].id=='camera')==standalone)
 local owners={};for _,page in ipairs(a.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do assert(not owners[control.id],'Control duplicated while moving Camera actions: '..control.id);owners[control.id]=page.id end end
 for _,id in ipairs({'screenshot','lock_camera','save_camera','clear_saved_camera','recenter','speed','wheel_step','look_sensitivity','roll_speed','freeze_player','slowmo_speed'})do assert(owners[id]=='camera_tools','Camera action missing: '..id)end
 for _,id in ipairs({'fov','roll','dof','dof_mode','focus_mode','focus_distance','aperture','dof_quality','bokeh_shape'})do assert(owners[id]=='lens','Photographic control must be separate: '..id)end
 for _,id in ipairs({'light_add','light_selected','light_enabled','light_kind','light_intensity','light_color','light_range','light_cone','light_right','light_forward','light_up','light_follow','light_place','light_remove','light_clear'})do assert(owners[id]=='lighting','Light control must stay on its own page: '..id)end
 assert(visible[1].controls[1].id=='screenshot'and visible[1].controls[2].id=='lock_camera','Common Camera actions must appear first')
 local expected={'Camera','Lens','Color','Effects','Lighting','Composition','Director','Subject'};if standalone then expected[#expected+1]='Controls'end
 for index,name in ipairs(expected)do assert(visible[index].name==name,'Unexpected photo navigation order')end
 local layout_commands;local layout_keys={}
 local layout=panel.new({draw=function(value)layout_commands=value end,release=function()end},{focus=function()end,hide=function()end,hud=function()end,exit=function()end})
 layout.bind(a.mods.dbf_freecam.handle,visible)
 local viewport_w,viewport_h=1920,1080
 local function draw_layout()layout.draw(viewport_w,viewport_h,true,false,{focus='TAB',hide='H',slowmo='\\'})end
 local function tab_press(key)layout_keys[key]=true;layout.tick({click=false,dt=.016},function(k)return layout_keys[k]or false end);draw_layout();layout_keys[key]=false;layout.tick({click=false,dt=.016},function(k)return layout_keys[k]or false end);draw_layout()end
 local function check_layout()
  local tabs={};local backing;local strip
  for _,command in ipairs(layout_commands)do
   if command.ui_role=='photo_panel'then backing=command elseif command.ui_role=='photo_controls_strip'then strip=command end
   if command.ui_key and command.ui_key:match('^tab:')and command.ui_role=='button'then tabs[#tabs+1]=command end
   if command.type=='rect'then assert(command.x>=0 and command.y>=0 and command.x+command.w<=viewport_w+.001 and command.y+command.h<=viewport_h+.001,'Compact photo surface escaped viewport')end
  end
  assert(backing and backing.x>viewport_w/2 and backing.y>viewport_h/5 and backing.h<viewport_h/3 and backing.a<.6,'Photo panel must be shallow, translucent and clear of the ship HUD')
  assert(strip and strip.y+strip.h<backing.y and layout.contains_pointer(strip.x+strip.w/2,strip.y+strip.h/2),'Persistent footer must own its pointer surface')
  assert(#tabs==#visible,'Every category must stay reachable')
  for index,tab in ipairs(tabs)do
   local found=false
   for _,command in ipairs(layout_commands)do local bounds=command.text_bounds
    if bounds and command.full_text==visible[index].name and bounds.x>=tab.x and bounds.x+bounds.w<=tab.x+tab.w+.001 and bounds.y==tab.y then found=true;assert(command.text==command.full_text,'Category name truncated')end
   end
   assert(found,'Missing readable category label')
   for other=index+1,#tabs do local b=tabs[other];assert(tab.x+tab.w<=b.x or b.x+b.w<=tab.x or tab.y+tab.h<=b.y or b.y+b.h<=tab.y,'Category tabs overlapped')end
  end
 end
 for _,resolution in ipairs({{1920,1080},{3840,2160}})do viewport_w,viewport_h=unpack(resolution)
  for index in ipairs(visible)do layout.page=index;layout.scroll=0;layout.selection=1;draw_layout();check_layout()end
 end
 layout.page=1;draw_layout();layout.tick({click=false,dt=.016},function()return false end)
 for index=2,#visible do tab_press(69);assert(layout.page==index,'E must navigate to every grouped category')end
 tab_press(69);assert(layout.page==1,'E must wrap to Camera');tab_press(81);assert(layout.page==#visible,'Q must wrap to the last category')
 -- Future subject controls can extend the same compact horizontal navigation.
 visible[#visible+1]={id='subject',name='Subject',controls={}};layout.bind(a.mods.dbf_freecam.handle,visible);draw_layout();check_layout();layout.close()
 assert(a.mods.dbf_freecam.name=='Photo Mode');assert(ctrl.close());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
end
print('Photo pages: first Camera actions / separate Lens, exact-once IDs, shared/standalone Controls, translucent bottom-right 1920/4K bounds, readable six/seven tabs and Q/E wrapping passed')

-- Tab and the visible focus action commit through blur; Escape still cancels.
do
 local pressed={};local text_editing=false;local binding=false;local allow_blur=false
 local blur_calls,cancel_calls,input_mode=0,0,0;local callbacks
 local service=core.new(nil,function()end)
 service.is_open=function()return false end;service.close=function()return true end
 service.create_photo_view=function()return {}end;service.photo_resolution=function()return 1920,1080 end
 service.camera_input={down=function(key)return pressed[key]or false end,focused=function()return true end,
  acquire=function()input_mode=3;return {}end,release=function()input_mode=0;return true end,
  set_focus=function(menu)input_mode=menu and 1 or 3;return true end,
  sample=function()return {wheel=0,mouse_x=0,mouse_y=0,dt=.016}end,menu_sample=function()return {click=false,wheel=0,dt=.016}end}
 local fake_menu={new=function(_,actions)
  callbacks=actions
  return {bind=function()end,draw=function()end,tick=function()end,close=function()end,
   editing_key=function()return binding end,editing_text=function()return text_editing end,
   blur=function()blur_calls=blur_calls+1;if not allow_blur then return false end;text_editing=false;return true end,
   dismiss=function()cancel_calls=cancel_calls+1;text_editing=false;return true end}
 end}
 DBFMCM=service
 local state={};local adapter=controller.new(state,{},function()return true end,function()end,nil,options,nil,fake_menu)
 local function tick()adapter.tick(.016)end
 local function press(key)pressed[key]=true;tick();pressed[key]=false;tick()end
 tick();press(80);assert(state.active and input_mode==3)
 press(9);assert(input_mode==1 and blur_calls==0)
 text_editing=true;press(9);assert(input_mode==1 and blur_calls==1 and text_editing,'Invalid pending text must block Tab focus transfer')
 allow_blur=true;press(9);assert(input_mode==3 and blur_calls==2 and not text_editing,'Tab must commit pending text through blur')
 binding=true;press(9);assert(input_mode==3 and blur_calls==2,'Key capture must retain the focus shortcut')
 binding=false;press(9);assert(input_mode==1)
 text_editing=true;callbacks.focus();assert(input_mode==3 and blur_calls==3 and not text_editing,'Visible focus action must share the commit path')
 press(9);text_editing=true;press(27)
 assert(input_mode==1 and cancel_calls==1 and blur_calls==3 and not text_editing,'Escape must cancel editing rather than commit')
 assert(adapter.close()and input_mode==0);DBFMCM=nil
end
print('Photo focus transfer: Tab/button blur commits, invalid text refusal, binding suppression and Escape cancellation passed')

-- Native Escape/options relinquishes camera ownership without releasing ADS.
do
 local pressed={[2]=true};local native_open=false;local reader_error=false;local focused=true;local settings_open=false
 local input_mode=0;local rate=1;local acquired,released,handoffs,samples,menu_samples,menu_ticks,suspended,shots,forced_release=0,0,0,0,0,0,0,0,0
 local refuse_handoff=false;local hover=false;local events={}
 local service=core.new(nil,function()end)
 service.is_open=function()return settings_open end;service.close=function()settings_open=false;return true end
 service.create_photo_view=function()return {}end;service.photo_resolution=function()return 1920,1080 end
 service.camera_input={down=function(key)return pressed[key]or false end,focused=function()return focused end,
  native_menu_active=function()if reader_error then error('Native UI changed')end;return native_open end,
  acquire=function()acquired=acquired+1;input_mode=3;return {}end,
  release=function()released=released+1;events[#events+1]='release';input_mode=0;return true end,
  native_menu_handoff=function()handoffs=handoffs+1;events[#events+1]='handoff';if refuse_handoff then return false,'Capture restore pending'end;input_mode=0;return true end,
  set_focus=function(menu)input_mode=menu and 1 or 3;return true end,
  sample=function()assert(input_mode==3);samples=samples+1;return {forward=pressed[87],escape=pressed[27],mouse_x=12,mouse_y=4,wheel=0,dt=.016}end,
  menu_sample=function()assert(input_mode==1);menu_samples=menu_samples+1;return {click=false,wheel=0,dt=.016}end}
 local factory={new=function()return {bind=function()end,draw=function()end,tick=function()menu_ticks=menu_ticks+1 end,close=function()end,
  suspend=function()suspended=suspended+1 end,editing_key=function()return false end,editing_text=function()return false end,dismiss=function()return false end}end}
 local pause={start=function(value)rate=value or 0;return true end,release=function()events[#events+1]='resume';rate=1;return true end,
  hold=function()return true end,rate=function()return rate end,needs_input_capture=function()return hover and rate==0 end}
 local capture={active=function()return false end,request=function()shots=shots+1;return true end,cancel=function()end,tick=function()end}
 DBFMCM=service
 local state={};local adapter=controller.new(state,{},function()return true end,function()end,pause,options,nil,factory,nil,nil,capture,nil,nil,nil,nil,
  {release=function()forced_release=forced_release+1;return true end})
 local function tick(dt)adapter.tick(dt or .016)end
 local function press(key)pressed[key]=true;tick();pressed[key]=nil;tick()end
 tick();press(80);assert(state.active and rate==0 and input_mode==3 and not adapter.camera_suspended())
 local handle=service.mods.dbf_freecam.handle
 pressed[87]=true;tick();assert(state.input.forward and state.input.mouse_x==12,'Camera movement must work before native-menu handoff')
 -- Escape must first yield the captured key so the native stack can open.
 local position,view={3,4,5},{0,1,0};state.pos=position;state.view=view
 pressed[27]=true;local before_release=released;local before_samples=samples;tick()
 assert(state.active and state.pos==position and state.view==view and rate==0 and input_mode==0 and released==before_release+1,'Escape must relinquish capture before native UI opens while retaining the composed Photo camera')
 assert(adapter.camera_suspended()and not adapter.native_menu_blocked()and state.input.dt==0 and state.input.mouse_x==0 and not state.input.forward,'The native-open handoff window must suspend camera sampling immediately')
 pressed[27]=nil;tick();assert(input_mode==0 and samples==before_samples+1,'The handoff window must not recapture before native UI is observed')
 native_open=true;tick();assert(state.active and state.pos==position and state.view==view and rate==0 and input_mode==0 and samples==before_samples+1,'An observed native menu must hold the same composed camera without sampling inputs')
 native_open=false;tick();assert(state.active and input_mode==3 and state.pos==position and state.view==view and state.input.forward and pressed[2]and forced_release==0,'Closing observed native UI with Escape released must resume the composed camera and preserved held inputs')
 -- If native UI never opens, the bounded yield resumes camera input safely.
 pressed[27]=true;tick();pressed[27]=nil;tick()
 for _=1,7 do tick(.1)end
 assert(state.active and input_mode==0 and adapter.camera_suspended(),'An unobserved native menu must retain capture yield for its bounded wait')
 tick(.1);assert(state.active and input_mode==3 and not adapter.camera_suspended()and state.input.forward and state.pos==position and state.view==view,'An unobserved native menu must resume after the bounded timeout without abandoning camera composition')
 local before_acquire=acquired
 native_open=true;local before_samples,before_menu=samples,menu_ticks
 assert(adapter.native_menu_blocked()and adapter.camera_suspended(),'Native menu must suspend render/input immediately, before the next controller tick')
 for _,key in ipairs({80,9,72,76,220,19,27})do pressed[key]=true end
 tick()
 assert(state.active and rate==0 and input_mode==0 and handoffs==1,'Ordinary native menu handoff must retain Photo Mode and zero-time pause')
 assert(state.input.dt==0 and state.input.mouse_x==0 and state.input.mouse_y==0 and state.input.wheel==0 and not state.input.forward,'Native menu must discard the old camera sample')
 assert(samples==before_samples and menu_ticks==before_menu and shots==0 and not handle.get('lock_camera'),'All photo shortcuts and menu input must be suppressed while native menu owns input')
 assert(adapter.request_screenshot()==false and shots==0,'The screenshot button/API must also refuse capture during a native menu')
 assert(pressed[2]and pressed[87]and forced_release==0,'Native-menu handoff must preserve physical ADS and held gameplay actions')
 native_open=false;tick()
 assert(state.active and rate==0 and input_mode==3 and acquired==before_acquire+1 and not adapter.camera_suspended(),'Closing Escape/options must reacquire camera ownership')
 assert(shots==0 and not handle.get('lock_camera')and state.input.forward,'Keys held through the native menu must not synthesize photo shortcut edges')
 for _,key in ipairs({80,9,72,76,220,19,27,87})do pressed[key]=nil end;tick()
 native_open=nil;before_samples=samples;tick()
 assert(state.active and rate==0 and adapter.native_menu_blocked()and adapter.camera_suspended()and samples==before_samples,'An unavailable native reader must block stale camera sampling')
 reader_error=true;tick();assert(adapter.native_menu_blocked()and samples==before_samples,'Native reader exceptions must block input and render ownership')
 reader_error=false;native_open=false;tick();assert(input_mode==3)
 press(9);assert(input_mode==1);before_menu=menu_ticks;local before_menu_samples=menu_samples
 native_open=true;refuse_handoff=true;tick()
 assert(input_mode==1 and state.active and rate==0 and menu_ticks==before_menu and menu_samples==before_menu_samples,'A refused handoff must retain its lease without processing the photo menu')
 local attempts=handoffs;tick();assert(handoffs==attempts+1,'Refused input handoff must retry on later ticks')
 refuse_handoff=false;tick();assert(input_mode==0)
 native_open=false;tick();assert(input_mode==1 and menu_ticks>before_menu,'Native menu closure must restore prior photo menu focus')
 focused=false;tick();assert(adapter.camera_suspended()and input_mode==0 and state.active and rate==0)
 focused=true;tick();settings_open=true;tick();assert(adapter.camera_suspended()and input_mode==0 and state.active and rate==0)
 settings_open=false;tick();assert(input_mode==1)
 -- Providers exposing only a native reader still use their normal lease release.
 service.camera_input.native_menu_handoff=nil;native_open=true;local before_release=released;tick()
 assert(released==before_release+1 and input_mode==0 and state.active,'Foreign/legacy native readers must retain a regular release fallback')
 native_open=false;tick();press(9);assert(input_mode==3)
 -- Hover protection cannot survive releasing input capture: resume first.
 hover=true;native_open=true;events={};tick()
 assert(not state.active and rate==1 and input_mode==0,'A hover pause must stop and restore simulation before native-menu handoff')
 assert(table.concat(events,',')=='resume,release','Hover world time must resume before its input capture lease is released')
 assert(pressed[2]and forced_release==0,'Hover cleanup must not inject an ADS release')
 press(80);press(220);assert(not state.active and rate==1 and input_mode==0,'Native menu must refuse Photo Mode and slow-motion activation while the camera is closed')
 native_open=false;press(80);assert(state.active and rate==0 and input_mode==3)
 events={};pressed[27]=true;tick()
 assert(not state.active and rate==1 and input_mode==0 and table.concat(events,',')=='resume,release','Hover Escape must stop Photo Mode and resume world time before releasing capture instead of retaining an unsafe pause')
 pressed[27]=nil
 native_open=false;assert(adapter.close());DBFMCM=nil
end
print('Native menu lifecycle: Escape camera retention/yield timeout, shortcut/menu/render suspension, zeroed camera samples, capture-only handoff/retry, ADS preservation, focus recovery and hover resume ordering passed')

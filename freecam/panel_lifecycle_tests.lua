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
keys[220]=true;c.tick(.016);assert(rate==.2);keys[220]=false;c.tick(.016);keys[220]=true;c.tick(.016);assert(rate==0);keys[220]=false
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

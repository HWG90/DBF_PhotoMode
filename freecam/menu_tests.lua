local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua').new(nil,function()end);local options=dofile(root..'photo_options.lua')
local h=core.register({id='test_photo',name='Photo',pages=options.pages(function()end,function()end)})
local commands;local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end},{focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(h,core.mods.test_photo.pages);menu.page=2;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'});assert(#commands>15)
for _,command in ipairs(commands)do assert(command.x>=0 and command.y>=0 and command.x<=1920 and command.y<=1080)end
local bar;for _,c in ipairs(commands)do if c.ui_role=='slider_track'and c.control_id=='fov'then bar=c;break end end
assert(bar and bar.type=='rect');menu.tick({x=bar.x+bar.w,y=bar.y+bar.h/2,click=true,wheel=0},function()return false end);assert(h.get('fov')==120)
menu.tick({click=false,wheel=0},function()return false end)
menu.draw(1280,720,false,false,{focus='TAB',hide='H',slowmo='\\'});assert(#commands>15)
menu.page=3;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local choice;for i,c in ipairs(commands)do if c.type=='text'and c.text=='Filter'then choice=commands[i+1];break end end
assert(choice);menu.tick({x=choice.x+20,y=choice.y+choice.h/2,click=true,wheel=0},function()return false end)
assert(h.get('filter')==1,'Opening dropdown must not cycle value')
menu.tick({click=false,wheel=0},function()return false end);menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local option;for _,c in ipairs(commands)do if c.type=='text'and c.text=='  Warm film'then option=c;break end end
assert(option);menu.tick({x=option.x+10,y=option.y,click=true,wheel=0},function()return false end);assert(h.get('filter')==2)
menu.draw(1920,1080,false,true,{focus='TAB',hide='H',slowmo='\\'});assert(#commands==0)
menu.close();print('On-screen photo menu: real MCM schema, two viewport sizes, hidden interface and cleanup passed')

-- Popup commands use the renderer's popup surface and layers, with opaque backing.
menu.page=3;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
menu.tick({click=false,wheel=0},function()return false end)
menu.tick({x=choice.x+20,y=choice.y+choice.h/2,click=true,wheel=0},function()return false end)
menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local backing;for _,c in ipairs(commands)do if c.ui_role=='dropdown_panel'then backing=c end end
assert(backing and backing.a==1 and backing.layer==900)
menu.dismiss();menu.close()
-- Neutral shader status is omitted; useful failure text appears when supplied.
menu.page=4;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
for _,c in ipairs(commands)do assert(c.full_text~='Shader overlay: none')end
local shader_status;for _,page in ipairs(core.mods.test_photo.pages)do for _,control in ipairs(page.controls)do if control.id=='shader_status'then shader_status=control end end end
shader_status.label='Shader unavailable: fixture';menu.scroll=999;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local shown=false;for _,c in ipairs(commands)do if c.full_text=='Shader unavailable: fixture'then shown=true end end;assert(shown);shader_status.label='';menu.close()
local keys={};local function draw()menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})end
local function tick()menu.tick({click=false,wheel=0,dt=.016},function(k)return keys[k]or false end);draw()end
local function press(k)keys[k]=true;tick();keys[k]=false;tick()end
menu.page=1;menu.selection=1;draw();tick();press(69);assert(menu.page==2);press(81);assert(menu.page==1)
menu.page=2;menu.selection=1;menu.scroll=0;draw();tick()
press(83);assert(menu.selection==2);press(87);assert(menu.selection==1)
h.set('fov',90);local unedited=h.get('fov');press(68);assert(menu.selection==1 and h.get('fov')==unedited+1);press(65);assert(menu.selection==1 and h.get('fov')==unedited)
press(13);assert(menu.editing_value);local before=h.get('fov');press(65);assert(h.get('fov')==before-1)
press(13);assert(not menu.editing_value)
print('Menu keyboard: Q/E tabs, W/S rows, A/D selected values, Enter slider editing, popup layers and opacity passed')

-- Section captions decorate the same flat MCM rows. They never add selectable
-- entries, swallow actions, or push a keyboard-selected control off screen.
local grouped=dofile('src/core.lua').new(nil,function()end)
local section_actions=0;local lens_edits=0
local grouped_handle=grouped.register({id='grouped_photo',name='Photo',pages=options.pages(function()end,function()section_actions=section_actions+1 end,nil,
 {lens_change=function()lens_edits=lens_edits+1 end,camera_controls={{id='slowmo_speed',type='slider',label='Simulation speed',default=.2,min=.05,max=1,step=.05}}})})
local grouped_pages=grouped.mods.grouped_photo.pages
for _,page in ipairs(grouped_pages)do for _,control in ipairs(page.controls)do control.disabled=false end end
local section_commands;local section_keys={}
local grouped_menu=dofile(root..'photo_menu.lua').new({draw=function(c)section_commands=c end,release=function()end},
 {focus=function()end,hud=function()end,hide=function()end,exit=function()end,slowmo=function()end})
grouped_menu.bind(grouped_handle,grouped_pages)
local function section_draw(w,h)grouped_menu.draw(w or 1920,h or 1080,true,false,{focus='TAB',hide='H'})end
local function section_tick(input)grouped_menu.tick(input or{click=false,dt=.016},function(key)return section_keys[key]or false end)end
for _,resolution in ipairs({{640,480},{1920,1080},{3840,2160}})do
 for index,page in ipairs(grouped_pages)do
  grouped_menu.page=index;grouped_menu.selection=1;grouped_menu.scroll=0;section_draw(unpack(resolution))
  local labels,dividers=0,0
  for _,command in ipairs(section_commands)do
   if command.ui_role=='photo_section_label'then labels=labels+1;local b=command.text_bounds
    assert(b.x>=0 and b.y>=0 and b.x+b.w<=resolution[1]+.001 and b.y+b.h<=resolution[2]+.001,'Section caption escaped the viewport')
    local before=grouped_menu.selection;section_tick({x=b.x+b.w/2,y=b.y+b.h/2,click=true});section_tick({click=false})
    assert(grouped_menu.selection==before and section_actions==0 and lens_edits==0,'Section caption changed a setting or action')
   elseif command.ui_role=='photo_section_divider'then dividers=dividers+1 end
  end
  assert(labels>0 and labels==dividers,'Every tab should have visible, noncollapsible section dividers')
 end
end
grouped_menu.page=2;grouped_menu.selection=1;grouped_menu.scroll=0;section_draw();section_tick()
local focus_visible,aperture_visible=false,false
for _,command in ipairs(section_commands)do if command.type=='text'then
 if command.control_id=='focus_distance'then focus_visible=true elseif command.control_id=='aperture'then aperture_visible=true end
end end
assert(focus_visible and aperture_visible,'Common focus and aperture settings should fit in the default Lens viewport')
grouped_handle.set('fov',90);assert(lens_edits==1,'Reordering detached the original lens callback')
grouped_menu.page=5;grouped_menu.selection=1;grouped_menu.scroll=0;section_draw();section_tick()
for _=1,#grouped_pages[5].controls+2 do
 section_keys[83]=true;section_tick();section_draw();section_keys[83]=false;section_tick();section_draw()
 local highlighted=false;for _,command in ipairs(section_commands)do if command.ui_role=='setting_row'and command.a==.12 then highlighted=true end end
 assert(highlighted,'Section spacing hid the keyboard-selected light control')
end
grouped_menu.close()
print('Flat photo sections: real MCM registration/callbacks, noninteractive captions/dividers, 640/1080/4K bounds, visible focus/aperture and section-aware keyboard scrolling passed')

-- Global AI edits the same authoritative MCM value, independent of the open
-- tab. Unknown factions have no invented emblem; verified artwork is optional.
local ai_core=dofile('src/core.lua').new(nil,function()end);local ai_changes=0
local ai_handle=ai_core.register({id='ai_toolbar',name='Photo',pages=options.pages(function()end,function()end,nil,
 {ai_change=function()ai_changes=ai_changes+1 end,camera_controls={{id='slowmo_speed',type='slider',label='Simulation speed',default=.2,min=.05,max=1,step=.05}}})})
local ai_mod=ai_core.mods.ai_toolbar;ai_mod.controls.ai_behavior.disabled=false
local ai_commands;local ai_keys={};local ai_ready=true;local faction
local ai_menu=dofile(root..'photo_menu.lua').new({draw=function(c)ai_commands=c end,release=function()end},
 {focus=function()end,hud=function()end,hide=function()end,exit=function()end,freeze=function()end,freeze_state=function()return false,true end,
  slowmo=function()end,slowmo_state=function()return false,true end,ai=function()return{available=ai_ready,status='Solo mission behavior'}end,faction=function()return faction end})
ai_menu.bind(ai_handle,ai_mod.pages)
local ai_w,ai_h=1920,1080
local function ai_draw(focused)ai_menu.draw(ai_w,ai_h,focused~=false,false,{focus='TAB',hide='H'})end
local function ai_tick(input)ai_menu.tick(input or{click=false,dt=.016},function(key)return ai_keys[key]or false end)end
local function ai_find(predicate)for _,command in ipairs(ai_commands)do if predicate(command)then return command end end;error('Missing global AI draw command')end
local function ai_click(bounds)ai_tick({x=bounds.x+bounds.w/2,y=bounds.y+bounds.h/2,click=true});ai_tick({click=false});ai_draw()end
for _,resolution in ipairs({{640,480},{800,600},{1920,1080},{3840,2160}})do
 ai_w,ai_h=unpack(resolution)
 for page in ipairs(ai_mod.pages)do
  ai_menu.page=page;ai_menu.scroll=0;ai_menu.selection=1;ai_draw()
  local strip=ai_find(function(c)return c.ui_role=='photo_global_controls_strip'end)
  local freeze=ai_find(function(c)return c.ui_key=='freeze_action'end);local field=ai_find(function(c)return c.ui_key=='ai_behavior_action'end)
  local slow=ai_find(function(c)return c.ui_key=='slowmo_action'end);local rate=ai_find(function(c)return c.ui_key=='slowmo_speed'end);local lock=ai_find(function(c)return c.ui_key=='lock_camera_action'end)
  assert(freeze.x+freeze.w<field.x and freeze.y==field.y,'AI must be immediately after Freeze/Resume')
  assert((slow.y==field.y and slow.x>=field.x+field.w)or slow.y+slow.h<field.y,'Responsive wrapping changed toolbar order')
  assert(slow.x+slow.w<rate.x and rate.x+rate.w<lock.x and slow.y==lock.y,'Slow Motion/rate/Lock order changed')
  for _,control in ipairs({freeze,field,slow,rate,lock})do assert(control.x>=strip.x and control.x+control.w<=strip.x+strip.w+.001 and control.y>=strip.y and control.y+control.h<=strip.y+strip.h+.001,'Global AI toolbar escaped its backdrop')end
  for _,command in ipairs(ai_commands)do
   assert(command.ui_role~='ai_faction_icon','Unknown faction invented an emblem')
   if command.type=='text'and(command.full_text=='Freeze Action'or command.full_text=='AI: Normal'or command.full_text=='Slow Motion: OFF'or command.full_text=='Lock Camera: OFF')then assert(command.text==command.full_text and command.size>=9,'Global tools became clipped or illegible')end
   assert(not(command.ui_role=='field'and(command.control_id=='ai_reset'or command.control_id=='ai_status')),'AI rows remained in scrolling tabs')
  end
 end
end
ai_w,ai_h=1920,1080;ai_menu.page=7;ai_menu.scroll=0;ai_draw();ai_tick()
local function choose_ai(name)
 ai_click(ai_find(function(c)return c.ui_key=='ai_behavior_action'end))
 local option=ai_find(function(c)return c.popup and c.full_text=='  '..name end)
 ai_click(option.text_bounds)
end
choose_ai('Passive');assert(ai_handle.get('ai_behavior')==2 and ai_changes==1,'Global AI detached the Passive callback')
choose_ai('Dummy');assert(ai_handle.get('ai_behavior')==3 and ai_changes==2)
choose_ai('Normal');assert(ai_handle.get('ai_behavior')==1 and ai_changes==3,'Normal did not restore the original AI callback')
ai_handle.set('ai_behavior',3);ai_draw();local field=ai_find(function(c)return c.ui_key=='ai_behavior_action'end)
ai_keys[2]=true;ai_tick({x=field.x+field.w/2,y=field.y+field.h/2,click=false});ai_keys[2]=false;ai_tick();ai_draw();assert(ai_handle.get('ai_behavior')==1,'Right-click did not reset global AI')
ai_ready=false;ai_draw();ai_click(ai_find(function(c)return c.ui_key=='ai_behavior_action'end));for _,c in ipairs(ai_commands)do assert(not c.popup,'Unavailable AI opened a dropdown')end
ai_ready=true;ai_mod.controls.ai_behavior.disabled=true;ai_draw();ai_click(ai_find(function(c)return c.ui_key=='ai_behavior_action'end));for _,c in ipairs(ai_commands)do assert(not c.popup,'Multiplayer/solo gate was bypassed')end
ai_mod.controls.ai_behavior.disabled=false;faction={name='Fixture faction',triangles={{0,0,1,0,.5,1}},color={100,150,200}};ai_draw()
local emblem=ai_find(function(c)return c.ui_role=='ai_faction_icon'end);assert(emblem.type=='triangle'and emblem.points[1]>=field.x and emblem.c[2]==150,'Verified faction artwork was not retained')
faction={name='Unavailable artwork'};ai_draw();for _,c in ipairs(ai_commands)do assert(c.ui_role~='ai_faction_icon','Missing artwork produced an invented symbol')end
ai_menu.close();print('Global AI toolbar: authoritative callbacks/Normal/reset/solo gates, tab independence, measured one/two-row layout, readable labels and verified-only faction emblem passed')

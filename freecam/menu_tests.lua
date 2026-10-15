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

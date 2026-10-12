local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua').new(nil,function()end);local options=dofile(root..'photo_options.lua')
local h=core.register({id='test_photo',name='Photo',pages=options.pages(function()end,function()end)})
local commands;local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end},{focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(h,core.mods.test_photo.pages);menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'});assert(#commands>15)
for _,command in ipairs(commands)do assert(command.x>=0 and command.y>=0 and command.x<=1920 and command.y<=1080)end
local bar;for _,c in ipairs(commands)do if c.ui_role=='slider_track'and c.control_id=='fov'then bar=c;break end end
assert(bar and bar.type=='rect');menu.tick({x=bar.x+bar.w,y=bar.y+bar.h/2,click=true,wheel=0},function()return false end);assert(h.get('fov')==120)
menu.tick({click=false,wheel=0},function()return false end)
menu.draw(1280,720,false,false,{focus='TAB',hide='H',slowmo='\\'});assert(#commands>15)
menu.page=2;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local choice;for i,c in ipairs(commands)do if c.type=='text'and c.text=='Filter'then choice=commands[i+1];break end end
assert(choice);menu.tick({x=choice.x+20,y=choice.y+choice.h/2,click=true,wheel=0},function()return false end)
assert(h.get('filter')==1,'Opening dropdown must not cycle value')
menu.tick({click=false,wheel=0},function()return false end);menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local option;for _,c in ipairs(commands)do if c.type=='text'and c.text=='  Warm film'then option=c;break end end
assert(option);menu.tick({x=option.x+10,y=option.y,click=true,wheel=0},function()return false end);assert(h.get('filter')==2)
menu.draw(1920,1080,false,true,{focus='TAB',hide='H',slowmo='\\'});assert(#commands==0)
menu.close();print('On-screen photo menu: real MCM schema, two viewport sizes, hidden interface and cleanup passed')

-- Popup commands use the renderer's popup surface and layers, with opaque backing.
menu.page=2;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
menu.tick({click=false,wheel=0},function()return false end)
menu.tick({x=choice.x+20,y=choice.y+choice.h/2,click=true,wheel=0},function()return false end)
menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local backing;for _,c in ipairs(commands)do if c.ui_role=='dropdown_panel'then backing=c end end
assert(backing and backing.a==1 and backing.layer==900)
menu.dismiss();menu.close()
-- Neutral shader status is omitted; useful failure text appears when supplied.
menu.page=3;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
for _,c in ipairs(commands)do assert(c.full_text~='Shader overlay: none')end
local shader_status;for _,page in ipairs(core.mods.test_photo.pages)do for _,control in ipairs(page.controls)do if control.id=='shader_status'then shader_status=control end end end
shader_status.label='Shader unavailable: fixture';menu.scroll=999;menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})
local shown=false;for _,c in ipairs(commands)do if c.full_text=='Shader unavailable: fixture'then shown=true end end;assert(shown);shader_status.label='';menu.close()
local keys={};local function draw()menu.draw(1920,1080,true,false,{focus='TAB',hide='H',slowmo='\\'})end
local function tick()menu.tick({click=false,wheel=0,dt=.016},function(k)return keys[k]or false end);draw()end
local function press(k)keys[k]=true;tick();keys[k]=false;tick()end
menu.page=1;menu.selection=1;draw();tick();press(69);assert(menu.page==2);press(81);assert(menu.page==1)
press(83);assert(menu.selection==2);press(87);assert(menu.selection==1)
press(68);assert(menu.selection==2);press(65);assert(menu.selection==1)
press(13);assert(menu.editing_value);local before=h.get('fov');press(65);assert(h.get('fov')==before-1)
press(13);assert(not menu.editing_value)
print('Menu keyboard: Q/E tabs, WASD selector, Enter slider editing, popup layers and opacity passed')

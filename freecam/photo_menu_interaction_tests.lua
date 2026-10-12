local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local values={speed=3,filter=1,locked=8,bind=80};local commands;local keys={};local invoked=0;local hud_calls=0;local measure_calls=0;local refresh_calls=0
local function measure(label,size)local n=0;for _ in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;measure_calls=measure_calls+1;return n*size*.8 end
local choices={};for i=1,24 do choices[i]='Filter '..i end
local controls={{id='speed',type='slider',label='Movement speed with a deliberately long label',min=.1,max=50,step=.1},
 {id='filter',type='choice',label='Filter',choices=choices},{id='locked',type='slider',label='Unavailable scene parameter',min=0,max=10,step=1,disabled=true},
 {id='action',type='button',label='Save Camera Position'},{id='bind',type='keybind',label='Photo mode shortcut'}}
for i=6,25 do values['item'..i]=i;controls[i]={id='item'..i,type='slider',label='Control '..i,min=0,max=50,step=1}end
local handle={get=function(id)return values[id]end,set=function(id,v)values[id]=v end,activate=function()invoked=invoked+1 end}
local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end,measure=measure,
 text_metrics=function(size)return {min_y=-size*.2,max_y=size*.8,optical_y=0}end,refresh_font=function()refresh_calls=refresh_calls+1 end},
 {focus=function()end,hud=function()hud_calls=hud_calls+1 end,hide=function()end,exit=function()end})
menu.bind(handle,{{name='Camera',controls=controls},{name='Effects',controls={controls[2]}}})
local function draw(w,h)menu.draw(w or 1920,h or 1080,true,false,{focus='TAB',hide='H'})end
local function tick(input)menu.tick(input or {click=false,dt=.016},function(k)return keys[k]or false end)end
local function find(predicate)for _,c in ipairs(commands)do if predicate(c)then return c end end;error('Missing command')end
local function field(id)return find(function(c)return c.ui_role=='field'and c.control_id==id end)end
local function pointer(b,click)tick({x=b.x+b.w/2,y=b.y+b.h/2,click=click,dt=.016});draw()end
local function press(k)keys[k]=true;tick();draw();keys[k]=false;tick();draw()end
draw();tick();local label=find(function(c)return c.type=='text'and c.control_id=='speed'end)
assert(label.text~=label.full_text and measure(label.text,label.size)<=label.text_width,'Labels must fit whole native-measured glyphs')
assert(measure_calls>0 and refresh_calls>0)
pointer(field('filter'),false);assert(field('filter').hovered and values.filter==1,'Hover must not edit settings')
pointer(field('filter'),true);assert(values.filter==1,'Opening a dropdown must not edit settings');tick({click=false});draw()
local option=find(function(c)return c.popup and c.full_text=='  Filter 2'end);local option_bounds=option.text_bounds
pointer(option_bounds,false);assert(values.filter==1);assert(find(function(c)return c.popup and c.full_text=='  Filter 2'end).hovered)
pointer(option_bounds,true);assert(values.filter==2);assert(find(function(c)return c.popup and c.full_text=='> Filter 2'end).pressed,'Selection should remain visible while pressed')
tick({click=false});draw();for _,c in ipairs(commands)do assert(not c.popup,'Release closes the selected dropdown')end
pointer(field('filter'),true);tick({click=false});draw()
local hud=find(function(c)return c.ui_key=='hud'end);pointer(hud,true);assert(hud_calls==0,'Open popup owns covered toolbar input');tick({click=false});draw()
pointer(field('locked'),true);assert(values.locked==8 and not field('locked').pressed and not field('locked').hovered,'Disabled controls remain noninteractive');tick({click=false})
draw();pointer(field('speed'),true);assert(field('speed').pressed);tick({click=false});draw();assert(not field('speed').pressed)
-- Keyboard selection skips disabled controls, exposes the selected row when scrolling, and edits that row only.
menu.selection=2;draw();press(83);assert(menu.selection==4);press(13);assert(invoked==1)
for _=1,18 do press(83)end;assert(menu.selection>20 and menu.scroll>0);assert(field(controls[menu.selection].id))
local selected_id=controls[menu.selection].id;local before=values[selected_id];press(13);press(68);assert(values[selected_id]==before+1);press(13)
press(32);assert(menu.editing_value);press(65);assert(values[selected_id]==before);press(32);assert(not menu.editing_value)
menu.selection=4;menu.scroll=0;draw();press(32);assert(invoked==2,'Space chooses the selected action')
-- Q/E dismisses a dropdown when changing tabs; re-entering does not capture held keys.
menu.page=2;menu.selection=1;menu.scroll=0;draw();press(32);assert(find(function(c)return c.ui_role=='dropdown_panel'end));press(83);press(32);assert(values.filter==3,'Space chooses the highlighted dropdown option')
press(13);assert(find(function(c)return c.ui_role=='dropdown_panel'end));press(81);assert(menu.page==1)
for _,c in ipairs(commands)do assert(not c.popup)end
menu.selection=4;menu.scroll=0;menu.draw(1920,1080,false,false,{focus='TAB',hide='H'});keys[32]=true;tick();keys[32]=false;tick();assert(invoked==2,'Camera focus must never choose menu controls')
draw(800,600);for _,c in ipairs(commands)do if c.type=='text'then assert(measure(c.text,c.size)<=c.text_width+.001);local b=c.text_bounds;assert(b.x>=0 and b.y>=0 and b.x+b.w<=800.001 and b.y+b.h<=600.001)end end
menu.close();print('Photo panel interaction: native label fitting, hover/press, modal pointer ownership, disabled controls, keyboard reveal and tab transitions passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local values={speed=3,filter=1,locked=8,bind=80,slowmo_speed=.2};local commands;local keys={};local invoked=0;local hud_calls=0;local measure_calls=0;local refresh_calls=0
local freeze_frozen,freeze_enabled,freeze_calls=false,true,0
local slowmo_active,slowmo_enabled,slowmo_calls=false,true,0
local function measure(label,size)local n=0;for _ in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;measure_calls=measure_calls+1;return n*size*.8 end
local choices={};for i=1,24 do choices[i]='Filter '..i end
local controls={{id='speed',type='slider',label='Movement speed with a deliberately long label',min=.1,max=50,step=.1,fine_step=.01},
 {id='filter',type='choice',label='Filter',choices=choices},{id='locked',type='slider',label='Unavailable scene parameter',min=0,max=10,step=1,disabled=true},
 {id='action',type='button',label='Save Camera Position'},{id='bind',type='keybind',label='Photo mode shortcut'}}
for i=6,25 do values['item'..i]=i;controls[i]={id='item'..i,type='slider',label='Control '..i,min=0,max=50,step=1}end
values.enabled=false;controls[26]={id='enabled',type='toggle',label='Enabled'}
local handle={get=function(id)return values[id]end,set=function(id,v)values[id]=v end,activate=function()invoked=invoked+1 end}
local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end,measure=measure,
 text_metrics=function(size)return {min_y=-size*.2,max_y=size*.8,optical_y=0}end,refresh_font=function()refresh_calls=refresh_calls+1 end},
 {focus=function()end,hud=function()hud_calls=hud_calls+1 end,hide=function()end,exit=function()end,
 freeze=function()freeze_calls=freeze_calls+1;freeze_frozen=not freeze_frozen end,freeze_state=function()return freeze_frozen,freeze_enabled,.2 end,
 slowmo=function()slowmo_calls=slowmo_calls+1;slowmo_active=not slowmo_active end,slowmo_state=function()return slowmo_active,slowmo_enabled end})
values.light_color='#406080'
menu.bind(handle,{{name='Camera',controls=controls},{name='Effects',controls={controls[2]}},{name='Lighting',controls={{id='light_color',type='color',label='Light color'}}}})
local function draw(w,h)menu.draw(w or 1920,h or 1080,true,false,{focus='TAB',hide='H'})end
local function tick(input)menu.tick(input or {click=false,dt=.016},function(k)return keys[k]or false end)end
local function find(predicate)for _,c in ipairs(commands)do if predicate(c)then return c end end;error('Missing command')end
local function field(id)return find(function(c)return c.ui_role=='field'and c.control_id==id end)end
local function pointer(b,click)tick({x=b.x+b.w/2,y=b.y+b.h/2,click=click,dt=.016});draw()end
local function press(k)keys[k]=true;tick();draw();keys[k]=false;tick();draw()end
draw();tick();local label=find(function(c)return c.type=='text'and c.control_id=='speed'end)
local shown_rows=0;for _,c in ipairs(commands)do if c.ui_role=='setting_row'then shown_rows=shown_rows+1 end end
assert(shown_rows>=10,'Default panel should show at least ten option rows alongside the fixed global controls')
assert(label.text~=label.full_text and measure(label.text,label.size)<=label.text_width,'Labels must fit whole native-measured glyphs')
assert(measure_calls>0 and refresh_calls>0)
pointer(field('filter'),false);assert(field('filter').hovered and values.filter==1,'Hover must not edit settings')
press(68);assert(menu.selection==1 and math.abs(values.speed-3.1)<1e-9 and values.filter==1,'A/D must edit the selected row while the pointer stays over another field')
keys[16]=true;press(65);keys[16]=false;assert(math.abs(values.speed-3.09)<1e-9,'Shift+A/D must finely step a selected slider without entering its numeric editor')
press(83);assert(menu.selection==2);press(68);assert(values.filter==2 and menu.selection==2,'Closed choices must cycle directly with A/D')
press(65);press(65);assert(values.filter==24,'Choice cycling wraps backwards');press(68);assert(values.filter==1,'Choice cycling wraps forwards')
pointer(field('filter'),true);assert(values.filter==1,'Opening a dropdown must not edit settings');tick({click=false});draw()
local option=find(function(c)return c.popup and c.full_text=='  Filter 2'end);local option_bounds=option.text_bounds
pointer(option_bounds,false);assert(values.filter==1);assert(find(function(c)return c.popup and c.full_text=='  Filter 2'end).hovered)
pointer(option_bounds,true);assert(values.filter==2);assert(find(function(c)return c.popup and c.full_text=='> Filter 2'end).pressed,'Selection should remain visible while pressed')
tick({click=false});draw();for _,c in ipairs(commands)do assert(not c.popup,'Release closes the selected dropdown')end
pointer(field('filter'),true);tick({click=false});draw()
local hud=find(function(c)return c.ui_key=='hud'end);pointer(hud,true);assert(hud_calls==0,'Open popup owns covered toolbar input');tick({click=false});draw()
pointer(field('locked'),true);assert(values.locked==8 and not field('locked').pressed and not field('locked').hovered,'Disabled controls remain noninteractive');tick({click=false})
draw();pointer(field('speed'),true);assert(field('speed').pressed);tick({click=false});draw();assert(not field('speed').pressed)
-- A/D cycles an open dropdown immediately; W/S returns to row navigation without stealing the value.
menu.selection=2;draw();press(13);press(68);assert(values.filter==3 and menu.selection==2)
assert(find(function(c)return c.popup and c.full_text=='> Filter 3'end),'An open dropdown reflects the applied A/D choice')
press(83);assert(menu.selection==4 and values.filter==3,'W/S must dismiss a dropdown and navigate rows, skipping disabled controls')
for _,c in ipairs(commands)do assert(not c.popup,'Row navigation must close a dropdown')end
-- Keyboard selection skips disabled controls, exposes the selected row when scrolling, and edits that row only.
menu.selection=2;draw();press(83);assert(menu.selection==4);press(13);assert(invoked==1)
for _=1,18 do press(83)end;assert(menu.selection>20 and menu.scroll>0);assert(field(controls[menu.selection].id))
local selected_id=controls[menu.selection].id;local before=values[selected_id];press(13);press(68);assert(values[selected_id]==before+1);press(13)
press(32);assert(menu.editing_value);press(65);assert(values[selected_id]==before);press(32);assert(not menu.editing_value)
menu.selection=4;menu.scroll=0;draw();press(32);assert(invoked==2,'Space chooses the selected action')
menu.selection=26;draw();press(68);assert(values.enabled==true and menu.selection==26 and menu.scroll>0,'D enables a selected toggle and scrolls it into view')
press(68);assert(values.enabled==true,'Holding the right direction must not toggle back off');press(65);assert(values.enabled==false,'A disables a selected toggle')
menu.selection=1;draw();values.speed=50;press(68);assert(values.speed==50,'Slider upper bounds remain enforced');values.speed=.1;press(65);assert(values.speed==.1,'Slider lower bounds remain enforced')
-- Q/E dismisses a dropdown when changing tabs; re-entering does not capture held keys.
menu.page=2;menu.selection=1;menu.scroll=0;draw();press(32);assert(find(function(c)return c.ui_role=='dropdown_panel'end));press(68);press(32);assert(values.filter==4,'A/D applies a dropdown option and Space closes it')
press(13);assert(find(function(c)return c.ui_role=='dropdown_panel'end));press(81);assert(menu.page==1)
for _,c in ipairs(commands)do assert(not c.popup)end
menu.selection=4;menu.scroll=0;menu.draw(1920,1080,false,false,{focus='TAB',hide='H'});keys[32]=true;tick();keys[32]=false;tick();assert(invoked==2,'Camera focus must never choose menu controls')
-- Apply is a visible, pointer-accessible way out of the live color picker.
for _,size in ipairs({{1920,1080},{800,600},{640,480}})do
 menu.page=3;menu.selection=1;menu.scroll=0;draw(size[1],size[2]);tick();pointer(field('light_color'),true);tick({click=false});draw(size[1],size[2])
 local channel=find(function(c)return c.ui_key=='channel:1'end);pointer(channel,true);tick({click=false});draw(size[1],size[2]);local edited=values.light_color
 assert(edited:sub(4)=='6080','Color edit changed an untouched channel')
 local apply=find(function(c)return c.ui_key=='color:apply'end);assert(apply.x>=0 and apply.y>=0 and apply.x+apply.w<=size[1]and apply.y+apply.h<=size[2],'Apply is outside the viewport')
 assert(find(function(c)return c.full_text=='Apply'end),'Color editor lacks a visible Apply label')
 local function check_preview()
  local swatch=find(function(c)return c.ui_role=='color_preview'and c.control_id=='light_color'end)
  local hex=find(function(c)return c.ui_role=='color_hex'and c.control_id=='light_color'end)
  assert(swatch.a==1 and swatch.c[1]==tonumber(values.light_color:sub(2,3),16)and swatch.c[2]==tonumber(values.light_color:sub(4,5),16)and swatch.c[3]==tonumber(values.light_color:sub(6,7),16),'Live swatch differs from current RGB value')
  assert(hex.text==values.light_color and hex.text==hex.full_text,'Current HEX value is missing or clipped')
  local hb=hex.text_bounds
  assert(swatch.x>=0 and swatch.y>=0 and swatch.x+swatch.w<=size[1]and swatch.y+swatch.h<=size[2],'Swatch is outside the viewport')
  assert(swatch.x+swatch.w<hb.x and hb.x+hb.w<apply.x,'Color preview or HEX overlaps Apply')
 end
 check_preview()
 channel=find(function(c)return c.ui_key=='channel:1'end)
 tick({x=channel.x+channel.w*.2,y=channel.y+channel.h/2,click=true});draw(size[1],size[2]);check_preview()
 tick({x=channel.x+channel.w*.8,y=channel.y+channel.h/2,click=true});draw(size[1],size[2]);check_preview()
 tick({click=false});draw(size[1],size[2]);edited=values.light_color
 pointer(apply,true);tick({click=false});draw(size[1],size[2]);assert(values.light_color==edited,'Apply changed the selected color')
 for _,c in ipairs(commands)do assert(c.ui_key~='color:apply'and c.ui_key~='channel:1'and c.ui_role~='color_preview'and c.ui_role~='color_hex','Apply did not close the color editor')end
end
draw(800,600);for _,c in ipairs(commands)do if c.type=='text'then assert(measure(c.text,c.size)<=c.text_width+.001);local b=c.text_bounds;assert(b.x>=0 and b.y>=0 and b.x+b.w<=800.001 and b.y+b.h<=600.001)end end
-- Time controls remain in the fixed toolbar on every tab and at either end of
-- long lists, with the actual paused state and authority reflected in the button.
menu.pages[3].controls[#menu.pages[3].controls+1]={id='freeze_player',type='toggle',label='Pause entire action'}
menu.pages[3].controls[#menu.pages[3].controls+1]={id='slowmo_speed',type='slider',label='Slow motion speed',min=.05,max=1,step=.05,fine_step=.01}
menu.bind(handle,menu.pages)
for _,size in ipairs({{1920,1080},{3840,2160},{800,600},{640,480}})do
 for page=1,#menu.pages do
  menu.page=page;menu.scroll=0;freeze_frozen=false;freeze_enabled=true;draw(size[1],size[2]);tick()
  local b=find(function(c)return c.ui_key=='freeze_action'end)
  assert(b.x>=0 and b.y>=0 and b.x+b.w<=size[1]and b.y+b.h<=size[2],'Freeze Action is outside the viewport')
  local opacity=find(function(c)return c.ui_role=='menu_opacity_track'end)
  local exit=find(function(c)return c.ui_key=='exit'end)
  assert(b.y>=exit.y+exit.h and b.y>=opacity.y+opacity.h,'Time row overlaps ordinary toolbar controls')
  local slow=find(function(c)return c.ui_key=='slowmo_action'end)
  local rate=find(function(c)return c.ui_key=='slowmo_speed'end)
  local strip=find(function(c)return c.ui_role=='photo_global_controls_strip'end)
  local panel=find(function(c)return c.ui_role=='photo_panel'end)
  assert(strip.a>panel.a and strip.a>=.7,'Global controls need a distinctly more opaque backdrop')
  for _,key in ipairs({'freeze_action','slowmo_action','slowmo_speed','lock_camera_action'})do
   local control=find(function(c)return c.ui_key==key end)
   assert(control.x>=strip.x and control.x+control.w<=strip.x+strip.w+.001 and control.y>=strip.y and control.y+control.h<=strip.y+strip.h+.001,'Global control escaped its backdrop')
  end
  for _,c in ipairs(commands)do
   if c.ui_role=='setting_row'then assert(c.y+c.h<=strip.y,'Options overlap the global controls')
   elseif c.ui_key and c.ui_key:match('^tab:')then assert(c.y>=strip.y+strip.h,'Tabs overlap the global controls')end
  end
  assert(b.x+b.w<slow.x and slow.x+slow.w<rate.x,'Adjacent time tools overlap')
  local lock=find(function(c)return c.ui_key=='lock_camera_action'end)
  assert(rate.x+rate.w<lock.x,'Speed slider overlaps Lock Camera')
  local was=values.lock_camera;pointer(lock,true);tick({click=false});draw(size[1],size[2]);assert(values.lock_camera==not was,'Fixed Lock Camera did not toggle')
  local bx,by=b.x,b.y;menu.scroll=999;draw(size[1],size[2]);b=find(function(c)return c.ui_key=='freeze_action'end)
  assert(b.x==bx and b.y==by,'Scrolling moves the Freeze Action button')
  for _,c in ipairs(commands)do assert(c.control_id~='freeze_player','Freeze toggle remained in the scrolling controls');assert(not(c.ui_role=='slider_track'and c.control_id=='slowmo_speed'),'Slow motion slider remained in the scrolling controls')end
  local n=freeze_calls;pointer(b,true);tick({click=false});draw(size[1],size[2]);assert(freeze_calls==n+1 and freeze_frozen,'Toolbar did not freeze exactly once')
  assert(find(function(c)return c.full_text=='Resume Action'end),'Paused action lacks Resume label')
  b=find(function(c)return c.ui_key=='freeze_action'end);pointer(b,true);tick({click=false});draw(size[1],size[2]);assert(freeze_calls==n+2 and not freeze_frozen,'Toolbar did not resume exactly once')
  freeze_enabled=false;draw(size[1],size[2]);b=find(function(c)return c.ui_key=='freeze_action'end);pointer(b,true);tick({click=false});assert(freeze_calls==n+2,'Unavailable time control accepted a click')
  freeze_enabled=true;menu.draw(size[1],size[2],false,false,{focus='TAB',hide='H'});b=find(function(c)return c.ui_key=='freeze_action'end)
  tick({x=b.x+b.w/2,y=b.y+b.h/2,click=true});tick({click=false});assert(freeze_calls==n+2,'Camera focus accepted a toolbar click')
 end
end
-- Slow Motion can remain selected while frozen; adjusting the adjacent slider
-- changes its retained rate, and Shift scrubbing stays relative and precise.
menu.page=2;freeze_frozen=true;slowmo_active=false;slowmo_enabled=true;values.slowmo_speed=.2;draw();tick()
local slow=find(function(c)return c.ui_key=='slowmo_action'end);local n=slowmo_calls
pointer(slow,true);tick({click=false});draw();assert(slowmo_calls==n+1 and slowmo_active and freeze_frozen,'Slow Motion selection incorrectly unfreezes time')
assert(find(function(c)return c.full_text=='Slow Motion: ON'end))
local rate=find(function(c)return c.ui_role=='slowmo_speed_track'end)
keys[16]=true;tick({x=rate.x+rate.w*.8,y=rate.y+1,click=true});assert(values.slowmo_speed==.2,'Shift slider press jumped to the pointer value')
tick({x=rate.x+rate.w,y=rate.y+1,click=true});assert(values.slowmo_speed>.2 and values.slowmo_speed<.25,'Fine toolbar scrubbing did not slow pointer movement')
tick({click=false});keys[16]=false;draw();local retained=values.slowmo_speed
assert(find(function(c)return c.full_text==string.format('%.0f%%',retained*100)end),'Toolbar percentage does not reflect retained rate')
slowmo_enabled=false;draw();rate=find(function(c)return c.ui_role=='slowmo_speed_track'end)
tick({x=rate.x+rate.w,y=rate.y+1,click=true});tick({click=false});assert(values.slowmo_speed==retained,'Unavailable toolbar slider accepted edits')
menu.close();print('Photo panel interaction: fixed Freeze/Resume toolbar on every tab and viewport, actual state/authority, hidden scrolling toggle, native label fitting, modal pointer ownership, keyboard values and tab transitions passed')

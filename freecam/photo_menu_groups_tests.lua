local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'photo_menu.lua')
local values={focus=3,disabled=8,advanced=2,light_color='#406080',shortcut=80,
 menu_x=.35,menu_y=.4,menu_scale=1,menu_opacity=38,slowmo_speed=.2,lock_camera=false}
local writes,commands,keys={}, {},{}
local function slider(id,label,section,collapsed,extra)
 local c={id=id,type='slider',label=label,min=0,max=10,step=1,fine_step=.1,photo_section=section,photo_section_label=section=='common'and'Focus'or'Advanced',photo_section_collapsed=collapsed==true}
 for k,v in pairs(extra or{})do c[k]=v end;return c
end
local focus=slider('focus','Focus distance','common',false,{commit_on_blur=true})
local locked=slider('disabled','Unavailable parameter','common',false,{disabled=true})
local advanced=slider('advanced','Advanced amount','advanced',true)
local pages={
 {id='lens',name='Lens',controls={focus,locked,{id='status',type='text',label='Native camera is ready',status_only=true,photo_section='common',photo_section_label='Focus'},advanced,{id='tail',type='button',label='Tail action'}}},
 {id='camera',name='Settings',controls={
  slider('menu_x','Horizontal placement','common',false,{min=-1,max=1,step=.1,layout_storage=true}),
  slider('menu_y','Vertical placement','common',false,{min=-1,max=1,step=.1,layout_storage=true}),
  slider('menu_scale','Menu scale','common',false,{min=.35,max=3,step=.1,layout_storage=true})}},
 {id='composition',name='Composition',controls={{id='menu_x',type='slider',label='Legacy hidden layout',min=-1,max=1,step=.1,layout_storage=true},{id='tail',type='button',label='Composition action'}}},
 {id='lighting',name='Lighting',controls={{id='light_color',type='color',label='Light color',photo_section='common',photo_section_label='Edit light'},
  {id='shortcut',type='keybind',label='Shortcut',photo_section='advanced',photo_section_label='Advanced',photo_section_collapsed=true}}}}
local signatures={};for p,page in ipairs(pages)do signatures[p]={};for i,c in ipairs(page.controls)do signatures[p][i]={control=c,id=c.id,type=c.type,label=c.label,section=c.photo_section,collapsed=c.photo_section_collapsed}end end
local actions={focus=function()end,hud=function()end,hide=function()end,exit=function()end,
 freeze=function()end,freeze_state=function()return false,true end,slowmo=function()end,slowmo_state=function()return false,true end}
local handle={get=function(id)return values[id]end,set=function(id,v)writes[#writes+1]={id=id,value=v};values[id]=v end,activate=function()end}
local function make(existing)
 local m=factory.new({draw=function(c)commands=c end,release=function()commands={}end},actions,existing);m.bind(handle,pages);return m
end
local menu=make();local width,height,focused=1920,1080,true
local function draw()menu.draw(width,height,focused,false,{focus='TAB',hide='H'})end
local function tick(input)menu.tick(input or{click=false,dt=.016},function(k)return keys[k]or false end)end
local function press(k)keys[k]=true;tick();draw();keys[k]=false;tick();draw()end
local function find(fn)for _,c in ipairs(commands)do if fn(c)then return c end end end
local function required(fn)return assert(find(fn),'Missing menu command')end
local function field(id)return required(function(c)return c.ui_role=='field'and c.control_id==id end)end
local function group(id)return required(function(c)return c.ui_role=='group_label'and c.group_id==id end)end
local function header(id)local label=group(id);return required(function(c)return c.ui_key=='group:'..#label.page_id..':'..label.page_id..':'..id end)end
local function click(b)tick({x=b.x+b.w/2,y=b.y+b.h/2,click=true,dt=.016});draw();tick({click=false,dt=.016});draw()end
local function has_field(id)return find(function(c)return c.ui_role=='field'and c.control_id==id end)~=nil end
draw();tick();assert(group('common').expanded and not group('advanced').expanded and has_field('focus')and not has_field('advanced'),'Default group state must show common controls and collapse advanced controls')
assert(required(function(c)return c.full_text=='Native camera is ready'end),'Grouping discarded capability status')
local frozen=required(function(c)return c.ui_key=='freeze_action'end);local toolbar={x=frozen.x,y=frozen.y,w=frozen.w,h=frozen.h}
click(header('advanced'));assert(group('advanced').expanded and has_field('advanced'),'Pointer expansion failed')
click(header('advanced'));assert(not group('advanced').expanded and not has_field('advanced'),'Pointer collapse failed')
local n=#writes;click(field('disabled'));assert(#writes==n and values.disabled==8,'Grouped disabled field accepted input')
menu.selection=1;menu.scroll=0;draw();press(65);assert(not group('common').expanded and not has_field('focus'),'A must collapse the selected group')
press(68);assert(group('common').expanded and has_field('focus'),'D must expand the selected group')
press(13);assert(not group('common').expanded,'Enter must collapse a group');press(13);assert(group('common').expanded,'Enter must expand a group')
press(83);assert(menu.selection==2,'W/S must navigate from a header into its first enabled field')
press(83);assert(menu.selection==5,'W/S must skip disabled fields and text, reaching the next group')
press(87);assert(menu.selection==2,'Reverse navigation must skip noninteractive rows')
-- Valid focus text saves exactly once before collapsing; invalid drafts retain
-- the section and editor so a hidden field can never silently lose typed focus.
press(13);press(55);n=#writes;click(header('common'))
assert(values.focus==7 and #writes==n+1 and not menu.editing_text()and not group('common').expanded,'Group collapse did not commit focus exactly once')
click(header('common'));menu.selection=2;draw();press(13);press(190);n=#writes;click(header('common'))
assert(menu.editing_text()and group('common').expanded and #writes==n,'Invalid numeric draft must block collapse')
assert(menu.dismiss());click(header('common'));assert(not menu.editing_text()and not group('common').expanded)
-- Numeric editors without commit-on-blur cancel on section close.
click(header('advanced'));menu.selection=3;draw();press(13);assert(menu.editing_text());press(56);n=#writes;click(header('advanced'))
assert(values.advanced==2 and #writes==n and not menu.editing_text()and not group('advanced').expanded,'Noncommitting draft leaked from a collapsed section')
-- Identical section IDs in separate pages keep independent session state.
menu.page=2;menu.selection=1;menu.scroll=0;draw();assert(group('common').expanded and has_field('menu_x'),'Settings group inherited Lens collapse state')
click(header('common'));assert(not group('common').expanded)
menu.page=1;menu.selection=1;menu.scroll=0;draw();assert(not group('common').expanded)
menu.close();draw();tick();assert(not group('common').expanded,'Close/open reset session expansion choices')
menu=make(menu);draw();tick();assert(not group('common').expanded,'Same-object migration lost expansion state')
local fresh=make();fresh.draw(width,height,true,false,{focus='TAB',hide='H'});assert(group('common').expanded and not group('advanced').expanded,'Fresh startup did not restore section defaults')
draw();tick()
-- Layout controls are deliberately exposed under Settings and apply immediately;
-- the same legacy storage controls stay hidden in Composition.
menu.page=2;menu.scroll=0;menu.selection=1;draw();click(header('common'))
local before=required(function(c)return c.ui_role=='photo_panel'end);local bx,by,bw=before.x,before.y,before.w
menu.selection=2;draw();press(68);local panel=required(function(c)return c.ui_role=='photo_panel'end);assert(panel.x>bx,'Settings horizontal value did not move the menu immediately')
menu.selection=3;draw();press(68);panel=required(function(c)return c.ui_role=='photo_panel'end);assert(panel.y>by,'Settings vertical value did not move the menu immediately')
menu.selection=4;draw();press(68);panel=required(function(c)return c.ui_role=='photo_panel'end);assert(panel.w>bw,'Settings scale did not resize the menu immediately')
values.menu_x=-1;values.menu_y=-1;draw();assert(menu.panel_x==nil and menu.panel_y==nil,'Automatic placement sentinels must clear stored manual placement')
menu.page=3;menu.scroll=0;menu.selection=1;draw();assert(not has_field('menu_x')and required(function(c)return c.full_text=='Composition action'end),'Composition legacy layout exclusion changed')
-- Collapsing a live color section dismisses its channel capture without changing
-- color. Shortcut sections remain navigable after releasing the editor.
menu.page=4;menu.scroll=0;menu.selection=1;draw();click(field('light_color'));assert(menu.scene_input_blocked())
local color=values.light_color;click(header('common'));assert(not menu.scene_input_blocked()and values.light_color==color and not group('common').expanded,'Color capture survived section collapse')
click(header('advanced'));menu.selection=3;draw();press(13);assert(menu.editing_key());press(27);assert(not menu.editing_key()and values.shortcut==80,'Shortcut cancellation changed its stored binding')
-- Groups scroll only the settings body. Toolbar/footer remain fixed on every
-- viewport, all group headers and text stay in the panel/viewport, and camera
-- focus cannot activate the menu.
values.menu_scale=1;values.menu_x=.35;values.menu_y=.4
for _,size in ipairs({{1920,1080},{3840,2160},{800,600},{640,480}})do
 width,height=size[1],size[2];menu.page=1;menu.scroll=0;menu.selection=1;draw();tick()
 local f=required(function(c)return c.ui_key=='freeze_action'end);local slow=required(function(c)return c.ui_key=='slowmo_action'end);local lock=required(function(c)return c.ui_key=='lock_camera_action'end)
 local exit=required(function(c)return c.ui_key=='exit'end);local fx,fy,ex,ey=f.x,f.y,exit.x,exit.y
 assert(f.y>exit.y+exit.h and f.x+f.w<slow.x and slow.x+slow.w<lock.x,'Fixed tools overlap')
 click(header('advanced'));menu.scroll=999;draw();f=required(function(c)return c.ui_key=='freeze_action'end);exit=required(function(c)return c.ui_key=='exit'end)
 assert(f.x==fx and f.y==fy and exit.x==ex and exit.y==ey,'Group expansion/scroll moved the fixed toolbar or footer')
 for _,c in ipairs(commands)do if c.type=='text'then local b=c.text_bounds;assert(b.x>=0 and b.y>=0 and b.x+b.w<=width+.001 and b.y+b.h<=height+.001,'Grouped text escaped viewport')end end
 menu.scroll=0;menu.selection=1;draw();local state=group('common').expanded;local b=header('common');focused=false;draw();click(b);assert(group('common').expanded==state,'Camera focus activated a group header');focused=true;draw();tick()
end
-- Rendering and grouping must never register synthetic IDs or mutate the flat
-- page schema, callback references, disabled flags or metadata.
for p,page in ipairs(pages)do assert(#page.controls==#signatures[p]);for i,c in ipairs(page.controls)do local old=signatures[p][i]
 assert(c==old.control and c.id==old.id and c.type==old.type and c.label==old.label and c.photo_section==old.section and c.photo_section_collapsed==old.collapsed,'Grouping mutated the registered schema')
end end
for _,write in ipairs(writes)do assert(not write.id:match('^group:'),'Synthetic group header wrote a registered control value')end
menu.close();print('PASS Photo collapsible groups: pointer/keyboard navigation, page/session state, exact numeric blur/cancel, disabled/modal ownership, live Settings geometry, flat schema and fixed toolbar/footer bounds')

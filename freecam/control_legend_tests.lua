local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'control_legend.lua');local options=dofile(root..'photo_options.lua')
local values={};for k,v in pairs(options.defaults)do values[k]=v end
values.legend_docked=false
values.forward_key=73;values.back_key=75;values.left_key=74;values.right_key=76;values.up_key=33;values.down_key=34
values.roll_left_key=90;values.roll_right_key=88;values.toggle_key=112;values.focus_key=113;values.hide_controls_key=114;values.lock_camera_key=115;values.slowmo_key=116
local writes=0;local handle={get=function(k)return values[k]end,set=function(k,v)values[k]=v;writes=writes+1;return true end}
local view={measure=function(t,s)return #t*s*.55 end};local legend=factory.new(view);legend.bind(handle);local commands
local function find(role)for _,c in ipairs(commands)do if c.ui_role==role then return c end end end
local function draw(w,h,focus,hide)commands={};legend.draw(commands,w or 1920,h or 1080,focus~=false,hide);return find('control_legend')end
local function bounds(w,h)
 for _,c in ipairs(commands)do
  if c.type=='rect'then assert(c.x>=-.001 and c.y>=-.001 and c.x+c.w<=w+.001 and c.y+c.h<=h+.001)
  elseif c.type=='triangle'then for i=1,6,2 do assert(c.points[i]>=-.001 and c.points[i]<=w+.001 and c.points[i+1]>=-.001 and c.points[i+1]<=h+.001)end end
 end
end
local b=draw();assert(b.x<100 and b.y<100 and b.w==b.h);bounds(1920,1080)
local hazards,keys,columns=0,{},{}
for _,c in ipairs(commands)do
 if c.ui_role=='legend_hazard'then hazards=hazards+1;assert(c.w==b.w and c.h<b.h/10)end
 if c.text_role=='legend_key'then keys[c.full_text]=true;columns[c.x]=true end
end
assert(hazards==2);local n=0;for _ in pairs(columns)do n=n+1 end;assert(n==3)
for _,label in ipairs({'F1','F2','F3','W / S','A / D','Q / E','SHIFT + A / D','RIGHT CLICK','ENTER / SPACE','ESC'})do assert(keys[label],label)end
assert(not keys['I / K']and not keys.F4 and not keys.F5,'Menu focus must omit camera movement, lock and slow motion')
local function labels()
 local result={};for _,c in ipairs(commands)do if c.type=='text'then result[c.full_text]=true end end;return result
end
assert(labels()['MENU CONTROLS']and labels()['Return to camera']and not labels()['CAMERA CONTROLS'])
local function rgb(c,r,g,b)return c.c[1]==r and c.c[2]==g and c.c[3]==b end
local grip=find('legend_resize');local scale=b.w/410
assert(rgb(grip,19,21,23)and grip.a==1 and grip.w==20*scale and grip.h==20*scale,'Legend grip must copy the main panel dark 20x20 grip')
local dots={};for _,c in ipairs(commands)do if c.ui_role=='legend_resize_dot'then dots[#dots+1]=c;assert(rgb(c,154,159,159)and c.w==3*scale and c.h==3*scale)end end
assert(#dots==3 and dots[1].x>dots[2].x and dots[1].y<dots[2].y,'Main grip must be horizontally mirrored')
legend.tick({x=grip.x+grip.w/2,y=grip.y+grip.h/2,click=false});draw();assert(rgb(find('legend_resize'),39,42,45),'Grip hover must match main field-hover fill')
legend.tick({x=grip.x+grip.w/2,y=grip.y+grip.h/2,click=true});draw();assert(rgb(find('legend_resize'),56,51,31),'Grip pressed fill must match main panel')
legend.tick({click=false})
draw(nil,nil,false);local camera=labels()
for _,label in ipairs({'CAMERA CONTROLS','I / K','J / L','PG UP / PG DN','Z / X','F1','F2','F3','F4','F5','MOUSE','WHEEL','Movement speed','Exit photo mode','Edit photo menu'})do assert(camera[label],label)end
for _,label in ipairs({'MENU CONTROLS','Menu up / down','Value / option','Fine focus step','RIGHT CLICK','ENTER / SPACE','Cancel / return'})do assert(not camera[label],'Camera focus retained menu-only control: '..label)end
draw()
local px,py=b.x+50,b.y+b.h-25
assert(legend.tick({x=px,y=py,click=true}));assert(legend.tick({x=px+150,y=py+80,click=true}));assert(legend.tick({click=false}))
b=draw();assert(b.x>150 and b.y>80 and values.legend_x>2 and values.legend_y>2)
local remembered={x=b.x,y=b.y};local size=b.w
local rx,ry=b.x+b.w-10,b.y+20
assert(legend.tick({x=rx,y=ry,click=true}));assert(legend.tick({x=rx+60,y=ry-60,click=true}));legend.tick({click=false});b=draw();assert(b.w>size and b.w==b.h)
legend.clear();b=draw();assert(b.x>=0 and b.y>=0,'Normalized size and position must survive clear')
local before=writes;draw(nil,nil,false);assert(not legend.tick({x=px,y=py,click=true}));assert(writes==before,'Camera focus must never edit geometry')
draw(nil,nil,true,true);assert(#commands==0 and not legend.tick({x=px,y=py,click=true}))
values.show_legend=false;draw();assert(#commands==0);values.show_legend=true
values.legend_x=100;values.legend_y=100;values.legend_size=70;values.legend_columns=1;draw(800,600);bounds(800,600)
columns={};for _,c in ipairs(commands)do if c.text_role=='legend_key'then columns[c.x]=true end end;n=0;for _ in pairs(columns)do n=n+1 end;assert(n==2)
assert(factory.key_label(16)=='SHIFT'and factory.key_label(17)=='CTRL'and factory.key_label(220)=='\\')
-- Flyout anchors to the left screen edge, collapses independently, and can
-- be undocked, moved, snapped back, or explicitly docked without losing size.
do
 local flyout=factory.new(view);flyout.bind(handle)
 local parent={x=1290,y=100,w=600,h=940,scale=1}
 values.legend_docked=true;values.legend_open=true;values.legend_columns=2;values.legend_size=38
 local function paint(p,w,h,focus,hide)commands={};flyout.draw(commands,w or 1920,h or 1080,focus~=false,hide,p or parent);return find('control_legend')end
 local function click(c)assert(flyout.tick({x=c.x+c.w/2,y=c.y+c.h/2,click=true}));flyout.tick({click=false})end
 local square=paint();assert(square.x==0,'Flyout must dock at left screen edge')
 bounds(1920,1080);click(find('legend_flyout_toggle'));paint();assert(not find('control_legend')and find('legend_flyout_toggle')and not values.legend_open,'Collapse must retain only the adjacent opener')
 local closed_writes=writes;paint(nil,nil,nil,false);assert(not flyout.tick({x=find('legend_flyout_toggle').x+5,y=find('legend_flyout_toggle').y+5,click=true})and writes==closed_writes,'Camera focus must not activate flyout buttons')
 paint();click(find('legend_flyout_toggle'));square=paint();assert(values.legend_open and square)
 local tab=find('legend_flyout_toggle');local tab_y=tab.y;local tab_height=values.legend_tab_y
 flyout.tick({x=tab.x+5,y=tab.y+5,click=true});flyout.tick({x=tab.x+5,y=tab.y-95,click=true});flyout.tick({click=false});square=paint()
 assert(values.legend_open and values.legend_tab_y<tab_height and find('legend_flyout_toggle').y<tab_y,'Dragging dock tab must move vertically without collapsing the drawer')
 local remembered_tab=values.legend_tab_y;flyout.clear();paint();assert(values.legend_tab_y==remembered_tab,'Dock tab position must survive clear/reopen')
 click(find('legend_dock_button'));square=paint();assert(values.legend_docked==false,'Explicit undock must preserve current placement')
 local px,py=square.x+25,square.y+square.h-25
 flyout.tick({x=px,y=py,click=true});flyout.tick({x=px+300,y=py-100,click=true});flyout.tick({click=false});square=paint();assert(square.x>250 and not values.legend_docked,'Floating title drag must move the flyout')
 click(find('legend_dock_button'));square=paint();assert(values.legend_docked and square.x==0)
 -- A title drag undocks only after movement; a small release near the dock
 -- screen edge snaps back, rather than permanently detaching on a title click.
 px,py=square.x+25,square.y+square.h-25
 flyout.tick({x=px,y=py,click=true});flyout.tick({x=px+100,y=py-30,click=true});square=paint();assert(not values.legend_docked)
 flyout.tick({x=px+5,y=py,click=true});flyout.tick({click=false});square=paint();assert(values.legend_docked,'Release near left screen edge must snap back into the dock')
 parent={x=650,y=70,w=350,h=500,scale=.7};square=paint(parent,1000,600);bounds(1000,600);assert(square.x==0 and math.abs(find('legend_flyout_toggle').y/(600-find('legend_flyout_toggle').h)*100-remembered_tab)<.0001,'Viewport change must preserve normalized tab height')
 paint(parent,1000,600,true,true);assert(#commands==0,'Hidden controls must hide flyout and opener')
 parent={x=12,y=24,w=376,h=750,scale=.65};paint(parent,400,800);bounds(400,800)
 flyout.clear()
end
-- Integrated panel owns legend interactions and its lifecycle, retaining WASD selection.
local panel_factory=dofile(root..'photo_menu.lua');panel_factory.legend_factory=factory
values.legend_x=2;values.legend_y=2;values.legend_size=38;values.legend_columns=2;values.legend_open=true;values.legend_docked=true;values.fov=60
local panel=panel_factory.new({draw=function(c)commands=c end,release=function()commands={}end,measure=view.measure},{})
panel.bind(handle,{{name='Camera',controls={{id='fov',type='slider',label='FOV',min=0,max=120,step=1,commit_on_blur=true}}}})
local downkeys={};local function tick(v)panel.tick(v or{click=false},function(k)return downkeys[k]or false end)end
local function paint(hidden)panel.draw(1920,1080,true,hidden,{focus='F2',hide='F3'})end
paint();b=find('control_legend');assert(b);tick();downkeys[68]=true;tick();assert(values.fov==61);downkeys[68]=false;tick()
local baseline=values.fov
tick({x=b.x+50,y=b.y+b.h-25,click=true});downkeys[68]=true;tick({x=b.x+90,y=b.y+b.h-10,click=true});assert(values.fov==baseline,'Dragging companion must not adjust selected row')
downkeys[68]=false;tick({click=false});paint();panel.suspend();assert(#commands==0);paint();assert(find('control_legend'))
paint(true);assert(#commands==0);paint();assert(find('control_legend'));panel.close();assert(#commands==0);paint();assert(find('control_legend'))
print('Controls legend: menu/camera context switching, exact configured keys, square 3/2 columns, clipped hazards, persisted drag/resize, focus/hide/exit lifecycle and WASD ownership passed')

-- Run the actual retained view, including native triangle marshalling, through
-- focus transitions. Tab must retain the existing GUI and fixed panel IDs.
do
 local created,destroyed,next_id=0,0,0;local natives={};local retired={};local triangles=0
 local function allocate(kind,metadata)next_id=next_id+1;natives[next_id]={kind=kind,metadata=metadata};return next_id end
 local function destroy(_,id)retired[id]=true end
 local sr={Application={main_world=function()return 1 end,worlds=function()return {1}end},
  World={create_screen_gui=function()created=created+1;return created end,destroy_gui=function()destroyed=destroyed+1 end},
  Gui={resolution=function()return 1920,1080 end,rect=function(_,pos,size,color)return allocate('rect',{pos=pos,size=size,color=color})end,
   text=function(_,text,_,size,_,pos,color)return allocate('text',{text=text,pos=pos,size=size,color=color})end,
   triangle=function(_,a,b,c,z,color)
    assert(a.y==0 and b.y==0 and c.y==0 and z==332 and color[1]==255,'Hazard triangles must marshal X/Z positions with explicit layer and opacity')
    triangles=triangles+1;return allocate('triangle',{})
   end,destroy_rect=destroy,destroy_text=destroy,destroy_triangle=destroy},
  Vector3=function(x,y,z)return {x=x,y=y,z=z}end,Vector2=function(x,y)return{x=x,y=y}end,Color=function(...)return{...}end}
 local retained=dofile(root..'vendor/view.lua').new(sr)
 local live_panel=panel_factory.new(retained,{})
 live_panel.bind(handle,{{name='Camera',controls={{id='fov',type='slider',label='FOV',min=0,max=120,step=1}}}})
 local function paint_native(focus,hide)live_panel.draw(1920,1080,focus,hide,{focus='F2',hide='F3'})end
 paint_native(false,false);assert(created==1 and destroyed==0 and triangles>0)
 local background=1;local title;for id,p in pairs(natives)do if p.kind=='text'and p.metadata.text=='WAR JOURNALIST'then title=id;break end end
 assert(title)
 for _,focus in ipairs({true,false,true,false})do paint_native(focus,false);assert(created==1 and destroyed==0 and not retired[background]and not retired[title],'Tab recreated native menu GUI or stable panel/title IDs')end
 live_panel.suspend();assert(destroyed==1 and retired[background]and retired[title],'Actual focus loss must still release native view')
 paint_native(true,false);assert(created==2 and destroyed==1)
 paint_native(true,true);assert(destroyed==2,'Hide/screenshot frame must still release native view')
 paint_native(true,false);live_panel.close();assert(created==3 and destroyed==3,'Photo exit must release native view')
end
print('Retained photo view: Tab preserves GUI and stable IDs; suspend/hide/exit releases; mirrored grip colors and native hazard triangles passed')

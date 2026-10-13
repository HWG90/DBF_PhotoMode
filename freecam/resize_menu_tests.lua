local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local values={fov=60,filter=1};local commands
local handle={get=function(id)return values[id]end,set=function(id,v)values[id]=v end}
local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end},{focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(handle,{{name='Camera',controls={{id='fov',type='slider',label='Field of view',min=20,max=120,step=1},{id='filter',type='choice',label='Filter',choices={'Original','Warm film','Cool film'}}}}})
local keys={focus='TAB',hide='H',slowmo='\\'}
local function draw(w,h,focused)menu.draw(w or 1920,h or 1080,focused~=false,false,keys)end
local function tick(input)menu.tick(input,function()return false end)end
local function find(predicate)for _,c in ipairs(commands)do if predicate(c)then return c end end;error('Missing draw command')end
local function title()return find(function(c)return c.text=='WAR JOURNALIST'end)end
local function corner()return find(function(c)return c.resize end)end
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' differs from '..tostring(b))end
local function resize_to(ratio)
 local b=corner();local start_x,start_y=b.x+b.w/2,b.y+b.h/2;local initial=commands[1]
 tick({x=start_x,y=start_y,click=true});tick({x=start_x-initial.w*(ratio-1),y=start_y+initial.h*(ratio-1),click=true});draw();tick({click=false})
end
draw();local initial_panel=commands[1];local initial_font=title().size
resize_to(.8);local smaller=commands[1]
near(smaller.w/initial_panel.w,.8);near(smaller.h/initial_panel.h,.8);near(title().size/initial_font,.8)
local remembered=smaller.w;menu.close();draw();near(commands[1].w,remembered)
-- Controls and dropdown geometry use the resized scale, and still accept pointer edits.
local bar=find(function(c)return c.ui_role=='slider_track'and c.control_id=='fov'end)
tick({x=bar.x+bar.w,y=bar.y+bar.h/2,click=true});tick({click=false});assert(values.fov==120)
draw();local choice=find(function(c)return c.ui_role=='field'and c.control_id=='filter'end)
tick({x=choice.x+choice.w/2,y=choice.y+choice.h/2,click=true});tick({click=false});draw()
local backing=find(function(c)return c.ui_role=='dropdown_panel'end);assert(backing.w>=choice.w and backing.a==1 and backing.layer==900)
menu.dismiss();draw();resize_to(10)
for _,c in ipairs(commands)do if c.type=='rect'then assert(c.x>=0 and c.y>=0 and c.x+c.w<=1920.001 and c.y+c.h<=1080.001)end end
resize_to(.01);near(title().size/initial_font,.65)
-- Camera focus never starts a resize, and a viewport change keeps the panel on screen.
draw(nil,nil,false);local before=menu.size_scale;local b=corner()
tick({x=b.x+b.w/2,y=b.y+b.h/2,click=true});tick({x=100,y=100,click=true});tick({click=false});near(menu.size_scale,before)
draw(800,600,true)
for _,c in ipairs(commands)do if c.type=='rect'then assert(c.x>=0 and c.y>=0 and c.x+c.w<=800.001 and c.y+c.h<=600.001)end end
menu.close()
local factory=dofile(root..'photo_menu.lua');local actions={focus=function()end,hud=function()end,hide=function()end,exit=function()end}
for _,resolution in ipairs({{1920,1080},{3840,2160}})do
 local w,h=unpack(resolution);local moved_commands
 local view={draw=function(value)moved_commands=value end,release=function()moved_commands={}end}
 local moving=factory.new(view,actions);moving.bind(handle,menu.pages)
 local function redraw(focused)moving.draw(w,h,focused~=false,false,keys)end
 local function role(id)for _,command in ipairs(moved_commands)do if command.ui_role==id then return command end end;error('Missing '..id)end
 local function drag_by(dx,dy)
  local grip=role('move_handle');local sx,sy=grip.x+grip.w*.25,grip.y+grip.h*.5
  moving.tick({x=sx,y=sy,click=true},function()return false end)
  moving.tick({x=sx+dx,y=sy+dy,click=true},function()return false end);redraw()
  moving.tick({click=false},function()return false end);redraw()
 end
 redraw();local original=role('photo_panel');local original_strip=role('photo_controls_strip');local scale=w/1920
 assert(original_strip.y>=180*scale,'Default footer must clear the ship chat/dispatch HUD')
 local fov,filter=values.fov,values.filter;drag_by(-180*scale,120*scale)
 local moved=role('photo_panel');local moved_strip=role('photo_controls_strip')
 near(moved.x,original.x-180*scale);near(moved.y,original.y+120*scale)
 near(moved_strip.x,original_strip.x-180*scale);near(moved_strip.y,original_strip.y+120*scale)
 near(moved.w,original.w);assert(values.fov==fov and values.filter==filter,'Moving the title must not edit camera values')
 moving.close();redraw();near(role('photo_panel').x,moved.x);near(role('photo_panel').y,moved.y)
 assert(factory.new(view,actions,moving)==moving,'Live layout migration must keep the existing panel object')
 redraw();near(role('photo_panel').x,moved.x);near(role('photo_panel').y,moved.y)
 redraw(false);local b=role('move_handle');moving.tick({x=b.x+10,y=b.y+10,click=true},function()return false end);moving.tick({x=0,y=h,click=true},function()return false end);redraw(false)
 near(role('photo_panel').x,moved.x);near(role('photo_panel').y,moved.y)
 redraw();drag_by(-w*10,h*10)
 for _,command in ipairs(moved_commands)do if command.type=='rect'then assert(command.x>=0 and command.y>=0 and command.x+command.w<=w+.001 and command.y+command.h<=h+.001,'Dragged menu escaped viewport')end end
 local fresh=factory.new(view,actions);fresh.bind(handle,menu.pages);fresh.draw(w,h,true,false,keys)
 near(role('photo_panel').x,original.x);near(role('photo_panel').y,original.y);fresh.close();moving.close()
end
print('Photo menu resize: proportional controls/fonts, session size, viewport bounds, focus ownership, slider and opaque dropdown passed')
print('Photo menu movement: ship HUD clearance, real title drag of panel/footer at 1920/4K, unchanged values, camera-focus guard, close/open retention, same-object live migration, viewport clamp and fresh startup defaults passed')

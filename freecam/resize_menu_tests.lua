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
 local b=corner();local start_x,start_y=b.x+b.w/2,b.y+b.h/2;local initial=title().size/24
 tick({x=start_x,y=start_y,click=true});tick({x=start_x-520*initial*(ratio-1),y=start_y-820*initial*(ratio-1),click=true});draw();tick({click=false})
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
print('Photo menu resize: proportional controls/fonts, session size, viewport bounds, focus ownership, slider and opaque dropdown passed')

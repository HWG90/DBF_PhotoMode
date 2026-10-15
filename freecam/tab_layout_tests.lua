local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua').new(nil,function()end)
local options=dofile(root..'photo_options.lua')
local pages=options.pages(function()end,function()end)
pages[#pages+1]={id='camera',name='Controls',controls={{id='test_binding',type='keybind',label='Photo key',default=80}}}
local handle=core.register({id='tab_layout_fixture',name='Photo',pages=pages})
local commands
local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()end,
 measure=function(label,size)return #label*size*.8 end},
 {focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(handle,core.mods.tab_layout_fixture.pages)
local keys={focus='TAB',hide='H'}
local function tabs()
 local result={}
 for _,c in ipairs(commands)do if c.ui_role=='photo_tab_label'then result[#result+1]=c end end
 return result
end
for _,resolution in ipairs({{1280,720},{1920,1080},{3840,2160}})do
 handle.set('tab_layout',1);menu.draw(resolution[1],resolution[2],true,false,keys)
 local slim=tabs();assert(#slim==9,'Slim lost a tab')
 for i,c in ipairs(slim)do
  assert(c.text==c.full_text,'Slim truncated a full tab label with wide BSL glyph metrics')
  local b=c.text_bounds;assert(b.y==slim[1].text_bounds.y,'Slim wrapped the tab row')
  assert(b.x>=0 and b.x+b.w<=resolution[1]and b.w>0,'Slim tab escaped viewport')
  if i>1 then assert(b.x>=slim[i-1].text_bounds.x+slim[i-1].text_bounds.w,'Slim tab labels overlap')end
  menu.tick({click=false},function()return false end)
  menu.tick({x=b.x+b.w/2,y=b.y+b.h/2,click=true},function()return false end)
  assert(menu.page==i,'Slim click selected the wrong tab')
 end
 handle.set('tab_layout',2);menu.draw(resolution[1],resolution[2],true,false,keys)
 local stacked=tabs();assert(#stacked==9 and stacked[1].text_bounds.y==stacked[5].text_bounds.y)
 assert(stacked[6].text_bounds.y==stacked[9].text_bounds.y and stacked[6].text_bounds.y<stacked[1].text_bounds.y,'Stacked did not retain two tab rows')
 local camera,subject,director,director_details=0,0,0,0
 for _,c in ipairs(commands)do if c.ui_role=='tab_icon'then
  if c.icon_id=='camera'then camera=camera+1 elseif c.icon_id=='subject'then subject=subject+1 elseif c.icon_id=='director'then director=director+1 end
 elseif c.ui_role=='tab_icon_cutout'and c.icon_id=='director'then director_details=director_details+1 end end
 assert(camera==2,'Controls must retain its cross')
 assert(subject>2 and director>=2 and director_details>0,'Subject and Director still use cross placeholders')
end
menu.close()
print('Slim/Stacked: nine full tab labels, real-width fitting, row geometry, every click and distinct subject/director icons passed')

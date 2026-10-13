local root=assert(DBF_PHOTO_TEST_ROOT)
local composition=dofile(root..'composition.lua')
local crest=dofile(root..'assets/helldiver_crest.lua');composition.logo_art={[2]=crest}
local o={};for k,v in pairs(dofile(root..'photo_options.lua').defaults)do o[k]=v end
o.logo=2
local commands=composition.layout(1920,1080,o,0)
assert(#commands==451 and #commands==#crest.triangles)
for _,c in ipairs(commands)do
 assert(c.type=='triangle'and #c.points==6 and c.x>=0 and c.y>=0 and c.x+c.w<=1920 and c.y+c.h<=1080)
end
local made,removed,gui_closed=0,0,0
local sr={Application={main_world=function()return 1 end,worlds=function()return {1,2}end},
 World={create_screen_gui=function(w)assert(w==2);return 10 end,destroy_gui=function(w,g)assert(w==2 and g==10);gui_closed=gui_closed+1 end},
 Gui={resolution=function()return 1920,1080 end,
 triangle=function(g,a,b,c,z,color)
  assert(g==10 and a[2]==0 and b[2]==0 and c[2]==0 and z==100 and color[1]==216)
  made=made+1;return made
 end,destroy_triangle=function(g,id)assert(g==10 and id>0);removed=removed+1 end},
 Vector3=function(...)return {...}end,Vector2=function(...)return {...}end,Color=function(...)return {...}end}
local lens={new=function()return {apply=function()return 1 end,release=function()return true end}end}
local postfx={new=function()return {parameters={},apply=function()return true,'fixture'end,release=function()return true end}end}
local runtime=dofile(root..'photo_runtime.lua').new(sr,lens,composition,postfx,function()end)
local function draw()assert(runtime.apply(3,4,1,{0,1,0},{1,0,0},o,0))end
draw();assert(made==451);draw();assert(made==451 and removed==0,'Unchanged crest must retain geometry')
o.logo_color='#F4CA35';draw();assert(made==902 and removed==451,'Tint change must replace exactly the owned triangles')
assert(runtime.release()and gui_closed==1)
print('Actual crest: 451 bounded triangles, native X/Z/layer/alpha marshalling, retained geometry, tint replacement and owned GUI cleanup passed')

-- All release logos use the same retained native geometry path. Their artwork
-- must be embedded, stay inside the selected frame and preserve saved indices.
local options=dofile(root..'photo_options.lua')
composition.logo_art=dofile(root..'assets/logo_art.lua');composition.logo_art[2]=crest
local names
for _,tab in ipairs(options.pages())do
 if tab.id=='composition'then for _,control in ipairs(tab.controls)do if control.id=='logo'then names=control.choices end end end
end
assert(names and #names==13 and names[2]=='Helldiver crest'and names[4]=='Super Earth crest'and names[5]=='Helldivers 2'and names[6]=='Arrowhead')
local seen={}
for _,name in ipairs(names)do
 assert(not seen[name],'Logo choice names must be unique');seen[name]=true
 local lower=name:lower();assert(not lower:find('beddivers',1,true)and not lower:find('brasildivers',1,true)and not lower:find('shafts',1,true))
end
for _,index in ipairs({4,7,8,9,10,11,12,13})do
 local art=assert(composition.logo_art[index]);assert(#art.triangles>0 and #art.triangles<=2500,'Bounded retained logo geometry')
 for _,edge in ipairs({0,100})do
  o.logo=index;o.logo_x=edge;o.logo_y=edge;o.logo_size=400;o.frame=5;o.logo_color='#F4CA35'
  local items=composition.layout(1920,1080,o,0);local count=0
  for _,item in ipairs(items)do if item.type=='triangle'then
   count=count+1
   assert(item.x>=528-.001 and item.x+item.w<=1392+.001 and item.y>=-.001 and item.y+item.h<=1080+.001,'Logo leaves portrait frame')
   assert(item.c[1]==244 and item.c[2]==202 and item.c[3]==53,'Logo tint was not preserved')
  end end
  assert(count==#art.triangles,'Logo mesh must be drawn completely')
 end
end
o.frame=1;o.clean_view=true
assert(#composition.layout(1920,1080,o,0)==0,'Clean view must hide every logo')
print('Release logo picker: 13 stable unique choices; Super Earth plus seven curated additions are embedded, tintable, bounded and hidden by clean view')

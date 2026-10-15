-- Exercise the saved layout choice through both actual registration services.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local options=dofile(root..'photo_options.lua')
local function copy(values)local out={};for key,value in pairs(values)do out[key]=value end;return out end
local function near(a,b)return math.abs(a-b)<1e-8 end
for _,standalone in ipairs({false,true})do
 local Core=dofile(standalone and root..'vendor/core.lua'or'src/core.lua')
 local saved={};local saves=0
 local store={load=function(id)return id=='layout_fixture'and copy(saved)or{}end,
  save=function(id,values)assert(id=='layout_fixture');saved=copy(values);saves=saves+1;return true end}
 local function launch()
  local api=Core.new(store,function()end)
  local handle=api.register({id='layout_fixture',name='Photo',pages=options.pages(function()end,function()end)})
  return handle,api.mods.layout_fixture
 end
 local handle,mod=launch();local control=mod.controls.tab_layout
 assert(control and control.type=='choice'and control.label=='Tab layout'and control.default==1)
 assert(control.choices[1]=='Slim'and control.choices[2]=='Stacked'and #control.choices==2)
 assert(control.page.id=='composition'and control.photo_section=='Menu layout'and not control.layout_storage,'The saved choice must remain visible in Composition / Menu layout')
 assert(handle.get('tab_layout')==1 and options.menu_layout_defaults.tab_layout==1 and options.defaults.tab_layout==nil,'Fresh installs default to Slim independently of photo-adjustment resets')
 assert(handle.set_many({menu_x=.42,menu_y=.77,menu_scale=.8,menu_opacity=65}))
 local before=saves;assert(handle.set('tab_layout',2)and saves==before+1 and saved.tab_layout==2,'Selecting Stacked must save through the real Core store')
 assert(options.reset_menu(handle)and handle.get('tab_layout')==2,'Startup visibility recovery changed the chosen tab layout')
 handle.unregister();handle,mod=launch()
 assert(handle.get('tab_layout')==2,'A fresh registration did not restore Stacked from persisted settings')
 options.reset(handle,mod.controls)
 assert(handle.get('tab_layout')==2 and near(handle.get('menu_x'),.42)and near(handle.get('menu_y'),.77)and near(handle.get('menu_scale'),.8)and handle.get('menu_opacity')==65,'Reset photo adjustments discarded menu preferences')
 before=saves;local accepted=pcall(handle.set,'tab_layout',3)
 assert(not accepted and saves==before and saved.tab_layout==2,'An invalid layout choice was persisted')
 assert(handle.set('tab_layout',1));handle.unregister();handle=launch()
 assert(handle.get('tab_layout')==1,'Returning to Slim did not survive registration restart')
 handle.unregister();saved.tab_layout=0;handle=launch()
 assert(handle.get('tab_layout')==1,'Invalid older settings must normalize to Slim')
 handle.unregister()
end
print('Tab layout schema: visible Slim/Stacked choice, default Slim, real shared/private persistence/restart, photo-reset/layout isolation and invalid-value recovery passed')

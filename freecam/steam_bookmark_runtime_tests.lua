local function load(name)return assert(loadfile('freecam/'..name..'.lua'))()end
local core_module=load('vendor/core');local core
local camera={open=function()return true end,close=function()return true end,
 frame=function()return{position={0,0,0},forward={1,0,0},right={0,-1,0},fov=1}end,
 bookmark_context=function()return{world=1,unit=2,position={0,0,0}}end}
local input={set_mode=function()return true end,release=function()return true end}
local deps={bookmark=load('steam_bookmark'),look=load('look'),camera={new=function()return camera end},input={new=function()return input end},
 core={new=function(...)core=core_module.new(...);return core end},
 store={new=function()return{load=function()return{}end,save=function()return true end}end},
 view={new=function()return{release=function()return true end}end},
 options=load('photo_options'),menu={new=function()return{bind=function()end,close=function()return true end}end},
 composition={}}
local sr={Application={time_since_launch=function()return 1 end}}
_G.render=function()end
local runtime=load('steam_runtime').new({config_dir='unused',log=function()end},sr,deps,{})
local rows=core.mods.dbf_freecam.controls
assert(not rows.save_camera.disabled and not rows.clear_saved_camera.disabled)
assert(rows.save_camera.on_activate()==false) -- closed camera
assert(runtime.open());assert(rows.save_camera.on_activate())
local status
for _,page in ipairs(core.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do
 if c.id=='saved_camera_status'then status=c end
end end
assert(status.label:find('Saved camera: 0.0 m',1,true))
assert(runtime.close());assert(runtime.open())
assert(rows.clear_saved_camera.on_activate());assert(status.label=='Saved camera: none')
assert(runtime.dispose())

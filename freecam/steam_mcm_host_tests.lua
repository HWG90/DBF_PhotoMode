local function module(name)return dofile('freecam/'..name..'.lua')end
local stored={roll=30};local pressed={};local time=0;local foreground=true;local saves=0;local refuse_settings=false
local log_count=0;local function fixture_log()log_count=log_count+1 end
local wall_time=0;local native_clock=os.time;os.time=function()return wall_time end
local acquisitions,releases,snapshots,scans,writes,release_attempts=0,0,0,0,0,0
local token,lease;local foreign_owner=false;local refuse_release=false
local raw={x=100,y=100,width=1920,height=1080,buttons=0,wheel=0,dx=0,dy=0}
local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true},
 acquire=function(owner,mode)
  if foreign_owner then return nil,'Another menu owns input'end
  assert(not lease);assert(owner=='dbf_freecam');acquisitions=acquisitions+1;token={};lease=token;return token
 end,
 owns=function(t)return lease~=nil and lease==t end,
 status=function()return{owner=lease and'dbf_freecam'or nil,pending_restore=false}end,
 release=function(t)assert(t==lease);release_attempts=release_attempts+1;if refuse_release then return false,'restore pending'end;lease=nil;releases=releases+1;return true end,
 snapshot=function(t)assert(t==lease);snapshots=snapshots+1;return raw end}
local key_names,key_ids={},{}
local sr={Application={time_since_launch=function()return time end},Gui={resolution=function()return 1920,1080 end},
 Window={has_focus=function()return foreground end},Keyboard={button_id=function(s)
  if not key_ids[s]then key_names[#key_names+1]=s;key_ids[s]=#key_names end;return key_ids[s]
 end,button=function(id)return pressed[key_names[id]]and 1 or 0 end}}
local rate=1;local native_policy=function(key,value)assert(key=='external_multiplier');rate=value end
local game_session={}
local session_peers={'local'}
sr.Application.set_time_step_policy=native_policy
sr.Application.main_world=function()return'world'end
sr.Network={game_session=function()return game_session end}
sr.GameSession={peers=function()return session_peers end}
local camera_active=false;local last_position;local camera_changed=false;local guarded_writes=0
local camera={open=function()assert(not camera_active);camera_active=true;scans=scans+1;return true end,
 scene=function()assert(camera_active);return'world',scans end,
 frame=function()return{position={0,0,0},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}end,
 write_view=function(p,f,u,fov,guard)
  assert(camera_active and f and u and fov)
  if guard then guarded_writes=guarded_writes+1;if camera_changed then return false,'Rendered camera changed'end end
  writes=writes+1;last_position={unpack(p)};return true
 end,
 close=function()camera_active=false;return true end}
local draws=0;local overlay_commands;local composition_layouts=0
local static_view,grain_view;local grain_layouts=0
local deps={camera={new=function()return camera end},input=module('steam_input'),core=module('vendor/core'),
 path=module('steam_path'),
 store={new=function()return{load=function()return stored end,save=function(_,values)
  saves=saves+1;if refuse_settings then return false,'settings disk unavailable'end;stored=values;return true
 end}end},
 view={new=function(_,overlay)
  local item={releases=0}
  if not overlay then static_view,grain_view=nil,nil
  elseif not static_view then static_view=item else grain_view=item end
  item.draw=function(commands,token)
  draws=draws+1
  if overlay then
   assert(token==commands,'Immutable composition must use the retained draw path')
   item.last=commands
   if item==static_view then overlay_commands=commands end
  end
  end
  item.release=function()item.releases=item.releases+1 end
  return item
 end},
 options=module('photo_options'),menu=module('photo_menu'),legend=module('control_legend'),composition=module('composition'),look=module('look'),lens=module('lens')}
local composition_layout=deps.composition.layout_static
deps.composition.layout_static=function(...)
 composition_layouts=composition_layouts+1;return composition_layout(...)
end
local grain_layout=deps.composition.layout_grain
deps.composition.layout_grain=function(...)
 grain_layouts=grain_layouts+1;return grain_layout(...)
end
local native_render=function(...)return 'native',select('#',...),...end
local lighting_opens,lighting_closes,lighting_actions=0,0,0
local lighting_cleanup=true
local lighting={status='fixture light ready',open=function(w,g,f)
 assert(w=='world'and g==scans and f.position)
 local dot=0;for i=1,3 do dot=dot+f.right[i]*f.up[i]end
 assert(math.abs(dot)<.00001,'Rolled lighting basis must remain orthogonal')
 lighting_opens=lighting_opens+1;return true end,
 close=function()lighting_closes=lighting_closes+1;return lighting_cleanup,'cleanup pending'end,
 tick=function(f)assert(type(f)=='function');return true end,
 revision=function()return 0 end,selected=function()return nil,0,0 end,
 action=function(a)assert(a=='create');lighting_actions=lighting_actions+1;return true end,
 subject=function(action,frame,distance,name)
  assert((action=='aim'or action=='preset')and frame.position and distance==5 and name=='key_fill_rim')
  lighting_actions=lighting_actions+1;return true
 end,
 setup=function(action,presets,slot,frame,distance)
  assert((action=='save'or action=='recall'or action=='clear')and slot==1 and frame.position and distance==5 and presets)
  lighting_actions=lighting_actions+1;return true
 end,
 change=function()return true end}
lighting.markers=function()return nil end
lighting.scene=function()return'world',1 end
deps.lighting={new=function()return lighting end};deps.lights={}
deps.gizmos=module('photo_light_gizmos')
local menu;local native_menu_new=deps.menu.new
deps.menu.new=function(...)menu=native_menu_new(...);return menu end
deps.light_presets={new=function(path)assert(path=='unused/lighting-presets.ini');return{status='fixture setups',list=function()return{'Setup 1'}end}end}
render=native_render
-- MCM hosts War Journalist's pages when it is enabled (1.2.1 behaviour): all
-- pages, Controls included, register in MCM with this mod's own storage, and
-- the Photo panel leaves out the Controls page and every keybind row.
local mcm_core=dofile(os.getenv('MCM_CORE')or'freecam/vendor/core.lua')
local mcm=mcm_core.new(nil,function()end);deps.mcm=mcm
local runtime=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
local function tick()time=time+.016;runtime.tick()end
local function key(name)pressed[name]=true;tick();pressed[name]=false;tick()end
assert(runtime.settings_host=='MCM'and mcm.mods.dbf_freecam,'Register War Journalist in MCM')
local hosted={};for _,page in ipairs(mcm.mods.dbf_freecam.pages)do hosted[page.id]=page end
assert(hosted.camera and hosted.camera.name=='Controls','MCM shows the Controls page')
local keybinds=0;for _,c in ipairs(hosted.camera.controls)do if c.type=='keybind'then keybinds=keybinds+1 end end
assert(keybinds>=10,'MCM shows every War Journalist key')
assert(#menu.pages==#mcm.mods.dbf_freecam.pages-1,'The Photo panel drops only the Controls page')
for _,page in ipairs(menu.pages)do
 assert(page.id~='camera','No Controls tab in the Photo panel while MCM hosts it')
 for _,c in ipairs(page.controls)do assert(c.type~='keybind','No keybind rows in the Photo panel')end
end
local before=saves
assert(mcm.set('dbf_freecam','toggle_key',79),'MCM edits War Journalist keys')
assert(saves==before+1 and stored.toggle_key==79,'MCM saves through War Journalist storage')
for _=1,3 do tick()end
key('o');assert(runtime.active,'A key changed in MCM drives Photo Mode')
key('o');assert(not runtime.active)
assert(mcm.set('dbf_freecam','toggle_key',96))
key('numpad 0');assert(runtime.active,'A numpad key bound in MCM opens Photo Mode')
key('numpad 0');assert(not runtime.active)
assert(runtime.dispose()and mcm.mods.dbf_freecam==nil,'Dispose retires the MCM page')

-- A refused MCM registration keeps the old Photo panel layout.
local busy=mcm_core.new(nil,function()end);deps.mcm=busy
busy.register({id='dbf_freecam',name='Other',pages={{id='p',name='P',controls={{id='x',type='toggle',label='X',default=false}}}}})
local logged;local fallback=module('steam_runtime').new({config_dir='unused',log=function(m)logged=logged or(type(m)=='string'and m:find('MCM registration failed',1,true)and m)end},sr,deps,service)
assert(fallback.settings_host=='Photo panel'and logged,'Fall back to the Photo panel when MCM refuses')
local camera_tab=false;for _,page in ipairs(menu.pages)do if page.id=='camera'then camera_tab=true end end
assert(camera_tab,'The fallback Photo panel keeps its Controls tab')
assert(busy.mods.dbf_freecam.name=='Other','Never replace another owner')
assert(fallback.dispose())

-- An object that is not an MCM provider is ignored.
deps.mcm={register=function()error('not MCM')end,mods={}}
local plain=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
assert(plain.settings_host=='Photo panel');assert(plain.dispose())
os.time=native_clock
print('Steam MCM host: MCM hosts every page and key with War Journalist storage, Photo panel drops Controls, refused/foreign MCM falls back passed')

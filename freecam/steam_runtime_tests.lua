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
local runtime=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
local function tick()time=time+.016;runtime.tick()end
local function key(name)pressed[name]=true;tick();pressed[name]=false;tick()end
for i=1,100 do tick()end
assert(scans==0 and snapshots==0 and writes==0,'Closed runtime must be idle')
key('p');assert(runtime.active and runtime.mode=='menu'and acquisitions==1)
assert(rate==0,'Saved Freeze preference must pause on entry at true zero')
assert(runtime.handle.set('freeze_player',false)and rate==1,'Resume must restore normal speed')
assert(runtime.handle.set('freeze_player',true)and rate==0,'Freeze toggle must pause immediately')
assert(lighting_opens==1);assert(runtime.handle.activate('light_add'));assert(lighting_actions==1)
assert(runtime.handle.activate('light_aim'));assert(runtime.handle.activate('light_apply_preset'));assert(lighting_actions==3)
for _,id in ipairs({'light_setup_save','light_setup_recall','light_setup_clear'})do assert(runtime.handle.activate(id))end
assert(lighting_actions==6)
assert(runtime.handle.set('clean_view',true));key('h')
assert(not runtime.handle.get('clean_view')and not runtime.handle.get('hide_controls'),
 'Show controls must escape persisted clean view')
local a,b,c=render(nil);assert(a=='native'and b==1 and c==nil,'Preserve native render arguments/results')
local vignette_controls={}
for _,page in ipairs(menu.pages)do for _,control in ipairs(page.controls)do
 if control.id=='vignette'or control.id=='vignette_width'then vignette_controls[control.id]=control end
end end
assert(not vignette_controls.vignette.disabled and not vignette_controls.vignette_width.disabled,
 'Portable vignette controls must be available')
for _,page in ipairs(menu.pages)do for _,control in ipairs(page.controls)do
 assert(not(control.id and control.id:match('^ai_'))and not control.photo_global_ai,'The Lua 5.1 build has no FFI enemy behavior rows')
end end
assert(runtime.handle.set('vignette',60));assert(runtime.handle.set('vignette_width',20));render()
assert(#overlay_commands==48,'Vignette must draw its actual edge geometry')
local retained_commands=overlay_commands;local retained_layouts=composition_layouts
for _=1,200 do render()end
assert(overlay_commands==retained_commands and composition_layouts==retained_layouts,
 'Unchanged composition must retain geometry without layout work')
assert(runtime.handle.set('vignette_width',30));render()
assert(overlay_commands~=retained_commands and composition_layouts==retained_layouts+1,
 'Changed vignette settings must explicitly invalidate retained geometry')
assert(runtime.handle.set('vignette',0));render()
assert(runtime.handle.set('grain',50));assert(runtime.handle.set('grain_size',2));render()
assert(grain_view and #grain_view.last==96,'Film grain uses a bounded separate geometry plane')
local grain_commands=grain_view.last;local grain_before=grain_layouts
retained_commands,retained_layouts=overlay_commands,composition_layouts
local grain_saves=saves
for _=1,200 do render()end
assert(grain_view.last==grain_commands and grain_layouts==grain_before,
 'Unchanged grain phase must retain its geometry')
for _=1,15 do
 time=(math.floor(time*12)+1)/12+.0001;runtime.tick();render()
 assert(overlay_commands==retained_commands and composition_layouts==retained_layouts,
  'Animated grain must not rebuild static overlays')
end
assert(grain_layouts==grain_before+15 and saves==grain_saves and rate==0,
 'Grain follows application time while frozen, with no settings writes')
local retired_grain=grain_view
assert(runtime.handle.set('grain',0));render();grain_before=grain_layouts
for _=1,200 do render()end
assert(retired_grain.releases==1 and grain_layouts==grain_before,
 'Disabled grain releases once and performs no more refresh work')
key('tab');assert(runtime.active and runtime.mode=='camera'and acquisitions==2)
pressed.tab=true;tick();assert(runtime.mode=='menu');tick();assert(runtime.mode=='menu','Held Tab must not oscillate modes');pressed.tab=false;tick()
key('tab');assert(runtime.mode=='camera')
pressed.w=true;tick();render();pressed.w=false
assert(last_position[1]>0,'Movement must reach rendered camera')
local saved_before=saves;local roll_before=runtime.handle.get('roll');pressed.e=true
for i=1,30 do tick();render()end
assert(saves==saved_before,'Rolling must never persist settings each frame')
pressed.e=false;tick();assert(saves==saved_before+1,'Commit roll once on release')
assert(runtime.handle.get('roll')>roll_before,'E must roll right')
roll_before=runtime.handle.get('roll');key('q');assert(runtime.handle.get('roll')<roll_before,'Q must roll left')
assert(runtime.handle.set('path_duration',.1));assert(runtime.handle.activate('path_add'))
pressed.w=true;tick();render();pressed.w=false;local path_start=last_position[1]
assert(runtime.handle.activate('path_add'));assert(runtime.handle.activate('path_play'))
saved_before=saves
tick();render();assert(last_position[1]<path_start,'Path preview must drive the camera')
for i=1,10 do tick();render()end
assert(math.abs(last_position[1]-path_start)<1e-8,'Path must finish on last point')
assert(saves<=saved_before+1,'Path must not persist lens values every frame')
assert(runtime.handle.activate('path_play'));tick();key('tab');assert(runtime.mode=='menu','Tab must stop preview and return menu control')
assert(runtime.handle.activate('path_clear'));local activated,accepted=runtime.handle.activate('path_play')
assert(activated and accepted==false,'Cleared path cannot replay')
key('tab')
local before=scans;for i=1,100 do tick();render()end;assert(scans==before,'No steady camera discovery scans')
assert(runtime.toggle_slowmo())
lighting_cleanup=false;local previous_releases=releases
assert(not runtime.close());assert(runtime.active and releases==previous_releases and camera_active,
 'Keep camera and input ownership until native light cleanup succeeds')
assert(rate==.2)
session_peers={'local','remote'};wall_time=2;tick()
assert(rate==1,'Pending light cleanup must not starve time safety checks')
session_peers={'local'}
lighting_cleanup=true;assert(runtime.close());key('p')
key('p');assert(not runtime.active and lease==nil and render==native_render,'Restore input and render callback')
assert(runtime.handle.set('show_legend',false));assert(stored.show_legend==false,'Persist visibility preference')
key('p');assert(runtime.active)
-- Another mod may wrap our render callback. Closed wrappers must stay inert
-- even after a new Photo session is opened inside that other wrapper.
local old=render;local outer=function(...)return old(...)end;render=outer
key('p');assert(not runtime.active and render==outer)
key('p');before=writes;render();assert(writes==before+1,'Retained old wrapper must not double-render')
foreground=false;lease=nil;pressed.p=true;tick();time=time+2;tick();assert(runtime.active and runtime.focus_suspended and lease==nil and rate==0,'Focus loss must retain frozen Photo Mode and release input')
foreground=true;tick();tick();assert(runtime.active and not runtime.focus_suspended and lease~=nil,'Focus return and a held toggle key must not close or reopen Photo Mode');pressed.p=false;tick()
assert(runtime.handle.set('slowmo_speed',.25));assert(runtime.toggle_slowmo()and rate==0,
 'Enabling slow motion while frozen must leave world time zero')
key('p');assert(not runtime.active and rate==.25 and runtime.handle.get('freeze_player'),
 'Ordinary Photo exit resumes slow motion and preserves Freeze on entry')
key('backslash');assert(rate==1,'Slow-motion hotkey works with Photo Mode closed')
local idle_scans,idle_snapshots=scans,snapshots
local editing_key=menu.editing_key;menu.editing_key=function()return true end
key('backslash');assert(rate==1,'Binding Backslash must not also activate slow motion')
menu.editing_key=editing_key;menu.bound_key=220
key('backslash');assert(rate==1,'Suppress a newly bound shortcut until its key releases')
pressed.backslash=true;for i=1,30 do tick()end;pressed.backslash=false;tick()
assert(rate==.25 and scans==idle_scans and snapshots==idle_snapshots,
 'Held gameplay hotkey toggles once without camera discovery or pointer snapshots')
key('p');assert(runtime.active and rate==0,'Gameplay slow motion must preserve saved Freeze on Photo entry')
assert(runtime.handle.set('slowmo_speed',.4)and rate==0)
assert(runtime.handle.set('freeze_player',false)and rate==.4,'Resume uses latest cached speed')
assert(runtime.handle.set('freeze_player',true)and rate==0)
assert(runtime.handle.set('enabled',false));assert(not runtime.active,'Disabling Photo Mode must release ownership')
assert(runtime.dispose())
assert(rate==1 and sr.Application.set_time_step_policy==native_policy,'Disposal must restore normal time and native binding')
local next_runtime=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
assert(next_runtime.handle.get('show_legend')==false,'Retain preference through runtime reconstruction')
assert(next_runtime.handle.set('enabled',true));assert(next_runtime.handle.set('freeze_player',true))
session_peers={'local','remote'}
assert(next_runtime.open()and next_runtime.active and rate==1 and not next_runtime.handle.get('freeze_player'),
 'Unavailable solo pause must not block Photo Mode')
assert(next_runtime.close());session_peers={'local'};assert(next_runtime.handle.set('freeze_player',true))
assert(next_runtime.open()and rate==0)
assert(next_runtime.toggle_slowmo()and rate==0)
local policy_wrapper=sr.Application.set_time_step_policy
sr.Application.set_time_step_policy=function(...)return policy_wrapper(...)end
local logs_before=log_count
assert(not next_runtime.close(true));for i=1,100 do tick();time=time+.016;next_runtime.tick()end
assert(log_count==logs_before+1,'Pending restoration must not write duplicate logs every frame')
sr.Application.set_time_step_policy=policy_wrapper;next_runtime.tick()
assert(rate==1 and not next_runtime.active,'Restored binding must permit pending cleanup immediately')
assert(next_runtime.dispose())
-- Action shots hold the world camera while returning input to gameplay. They
-- retain lights and recorded points instead of reopening/scanning the camera.
assert(runtime.handle.get('enabled')==false)
local action=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
assert(action.handle.set('enabled',true));assert(action.handle.set('freeze_player',true))
assert(action.handle.set('action_camera_mode',1));assert(action.open());assert(rate==0)
local action_scans,action_lights=scans,lighting_opens
assert(action.toggle_slowmo());assert(action.handle.set('slowmo_speed',.3));assert(rate==0)
local invoked,began=action.handle.activate('cinema_begin')
assert(invoked and began and action.mode=='shot'and lease==nil and rate==.3,'The registered Begin action shot button must be available')
local action_snapshots,action_saves=snapshots,saves
local action_pos
for i=1,100 do
 time=time+.016;pressed.w=true;action.tick();render()
 action_pos=action_pos or{unpack(last_position)}
 assert(last_position[1]==action_pos[1],'Gameplay movement must not move the placed camera')
end
pressed.w=false
assert(guarded_writes>0 and snapshots==action_snapshots and scans==action_scans and lighting_opens==action_lights,
 'Shot must not capture gameplay pointer, rescan camera, or recreate lights')
assert(saves==action_saves and action.handle.get('freeze_player'),'Shot must preserve Freeze preference without repeated settings writes')
pressed.tab=true;action.tick();pressed.tab=false;action.tick()
assert(action.mode=='shot'and rate==.3 and lease==nil,'Gameplay Tab must not recapture placement input')
foreign_owner=true
assert(not action.reposition_shot()and action.mode=='shot'and lease==nil,'Never steal another menu input lease')
foreign_owner=false;assert(action.reposition_shot()and action.mode=='menu'and rate==0)
assert(scans==action_scans and lighting_opens==action_lights,'Returning to placement reuses camera and lights')
local live_status
for _,page in ipairs(menu.pages)do for _,c in ipairs(page.controls)do if c.id=='cinema_status'then live_status=c.label end end end
assert(live_status=='Place a camera, then begin an action shot','Status must update the registered row drawn by the menu')
local focused,repositioned=action.handle.activate('cinema_reposition')
assert(focused and repositioned and action.mode=='camera','Reposition button must give the placed camera focus')
assert(action.focus()and action.mode=='menu')
assert(action.handle.set('freeze_player',false)and rate==.3)
assert(action.begin_shot());assert(action.reposition_shot()and rate==.3,'Unfrozen entry must remain unfrozen on return')
assert(action.handle.set('freeze_player',true));assert(action.begin_shot())
local owned_policy=sr.Application.set_time_step_policy
owned_policy('external_multiplier',.6)
assert(action.reposition_shot()and rate==.6 and not action.handle.get('freeze_player'),
 'Foreign time owner must not be replaced by refreeze or leave a stale Freeze setting')
assert(action.handle.set('freeze_player',false));assert(action.handle.set('freeze_player',true)and rate==0)
assert(action.handle.set('path_duration',.1));assert(action.handle.activate('path_add'))
raw.dx=20
assert(action.focus());time=time+.016;action.tick();render();raw.dx=0
assert(action.handle.activate('path_add'))
local path_invoked,path_began=action.handle.activate('path_shot')
assert(path_invoked and path_began and action.mode=='shot'and rate==1,'Registered path action button must start gameplay playback')
time=time+.016;action.tick();render();assert(action.mode=='shot')
pressed.p=true;action.tick();pressed.p=false;action.tick()
assert(action.mode=='menu'and rate==0,'Photo key returns path action shot to frozen placement')
assert(action.begin_shot());camera_changed=true;render();camera_changed=false
assert(not action.active and rate==1 and lease==nil,'Changed rendered camera must close shot and release time')
assert(action.open()and rate==0);assert(action.begin_shot());foreground=false
action.tick();foreground=true;assert(action.active and action.focus_suspended and action.mode=='shot','Focus loss must retain the action shot')
action.tick();assert(action.active and not action.focus_suspended);assert(action.close(true));
assert(action.open()and rate==0);assert(action.begin_shot());game_session={};time=time+2;action.tick()
assert(not action.active and rate==1,'Session replacement must retire the action shot')
assert(action.open()and rate==0);refuse_release=true
assert(not action.begin_shot()and action.state=='closing','A failed gameplay handoff must retain cleanup state')
local blocked_releases=release_attempts;refuse_release=false
for _=1,10 do action.tick()end
assert(action.state=='closing'and lease~=nil and release_attempts==blocked_releases,
 'Automatic cleanup retains a refused input lease without repeated release calls')
assert(action.close(true,nil,true)and not action.active and lease==nil and rate==1 and release_attempts==blocked_releases+1,
 'An explicit cleanup action makes one acknowledged input-release retry')
assert(action.open())
local end_invoked,ended=action.handle.activate('cinema_end')
assert(end_invoked and ended and not action.active and lease==nil,'Registered gameplay-return button must close Photo camera')
assert(action.dispose())
-- Lens presets must reflect manual edits; readable status follows the applied
-- FOV only when it changes, including a new gameplay FOV after reopening.
local native_frame=camera.frame;local gameplay_fov=1
camera.frame=function()local value=native_frame();value.fov=gameplay_fov;return value end
local focal_length=deps.options.focal_length;local lens_reads=0
deps.options.focal_length=function(value)lens_reads=lens_reads+1;return focal_length(value)end
stored.fov=40;stored.focal_preset=4;stored.roll=12;stored.roll_preset=3
local optics=module('steam_runtime').new({config_dir='unused',log=fixture_log},sr,deps,service)
assert(optics.handle.set('enabled',true));assert(optics.handle.set('hide_controls',false));assert(optics.handle.set('clean_view',false))
local entry_saves=saves;refuse_settings=true;assert(optics.open());refuse_settings=false
assert(optics.handle.get('focal_preset')==1 and optics.handle.get('roll_preset')==1,
 'Reopening must present stale shortcuts as Custom even with read-only settings')
assert(optics.handle.get('fov')==40 and optics.handle.get('roll')==12)
assert(saves==entry_saves and stored.focal_preset==4 and stored.roll_preset==3,
 'Stale shortcut presentation must not rewrite saved files or block camera entry')
local function focal_status()
 for _,page in ipairs(menu.pages)do for _,c in ipairs(page.controls)do
  if c.id=='focal_length_status'then return c.label end
 end end;error('Registered focal length status missing')
end
local before_preset=saves
assert(optics.handle.set('focal_preset',4));assert(saves==before_preset+1,'Preset and FOV must persist atomically once');render()
assert(optics.handle.get('focal_preset')==4 and math.abs(optics.handle.get('fov')-deps.options.preset_fov(4))<.0011)
assert(focal_status()=='Focal length: 50.0 mm','Preset status must use the registered row and rendered FOV')
local before_reads=lens_reads;local before_saves=saves
for _=1,200 do render()end
assert(lens_reads==before_reads and saves==before_saves,'Unchanged lens status must do no conversion or settings writes')
assert(optics.handle.set('fov',40)and optics.handle.get('focal_preset')==1,'Manual FOV must clear the old preset')
assert(optics.handle.set('roll_preset',3)and optics.handle.get('roll')==90 and optics.handle.get('roll_preset')==3)
assert(optics.handle.set('roll',12)and optics.handle.get('roll_preset')==1,'Manual tilt must clear the old shortcut')
assert(optics.focus()and optics.mode=='camera');pressed.e=true;time=time+.016;optics.tick()
assert(optics.handle.set('roll',12));pressed.e=false;time=time+.016;optics.tick()
assert(optics.handle.get('roll')==12,'Pending keyboard roll must not overwrite a successful manual tilt')
assert(optics.focus()and optics.mode=='menu')
assert(optics.handle.set('focal_preset',4));assert(optics.handle.set('roll_preset',3))
local old_fov,old_roll=optics.handle.get('fov'),optics.handle.get('roll')
local stored_before=stored;refuse_settings=true
assert(not optics.handle.set('focal_preset',3));assert(not optics.handle.set('fov',60))
assert(not optics.handle.set('roll_preset',2));assert(not optics.handle.set('roll',12))
assert(stored==stored_before and optics.handle.get('focal_preset')==4 and optics.handle.get('fov')==old_fov and
 optics.handle.get('roll_preset')==3 and optics.handle.get('roll')==old_roll,'Refused saves must publish no partial lens state')
refuse_settings=false
local conflict_saves=saves
assert(not optics.handle.set_many({focal_preset=4,fov=40})and saves==conflict_saves,'Conflicting explicit lens batches must be rejected before persistence')
for _,bad in ipairs({0/0,math.huge,'50'})do
 assert(not optics.handle.set_many({focal_preset=4,fov=bad})and saves==conflict_saves,
  'Preset expansion must not hide an invalid explicitly supplied FOV')
end
assert(optics.handle.set('hide_controls',true));before_reads=lens_reads
assert(optics.handle.set('fov',60));render();assert(lens_reads==before_reads,'Hidden controls must not refresh lens text')
assert(optics.handle.set('hide_controls',false));render();assert(lens_reads==before_reads+1)
assert(optics.handle.set('fov',0));render()
local first_status=focal_status();assert(first_status:find('(gameplay)',1,true))
assert(optics.close());gameplay_fov=.8;assert(optics.open());render()
assert(focal_status()~=first_status and focal_status():find('(gameplay)',1,true),'New camera FOV must replace prior gameplay focal length')
assert(optics.focus()and optics.mode=='camera');pressed.e=true;time=time+.016;optics.tick();pressed.e=false
local before_disable=saves
assert(optics.handle.set_many({enabled=false,roll=12})and not optics.active)
assert(optics.handle.get('roll')==12 and stored.roll==12 and saves==before_disable+1,
 'Mixed disable/tilt batch must suppress superseded pending roll before close callbacks')
assert(optics.handle.set('enabled',true));assert(optics.open())
assert(optics.handle.set('path_duration',1));assert(optics.handle.activate('path_add'))
assert(optics.focus());pressed.w=true;time=time+.1;optics.tick();render();pressed.w=false
assert(optics.handle.activate('path_add'));assert(optics.handle.activate('path_play'))
time=time+.1;optics.tick();render();local preview_before=last_position[1]
refuse_settings=true;assert(not optics.handle.set('fov',60));refuse_settings=false
time=time+.1;optics.tick();render()
assert(last_position[1]~=preview_before,'Refused lens edits must leave preview playback running')
local before_path_close=saves
assert(optics.handle.set_many({enabled=false,fov=60})and not optics.active)
assert(optics.handle.get('fov')==60 and stored.fov==60 and saves==before_path_close+1,
 'Mixed disable/FOV batch must supersede path lens cleanup in the same commit')
assert(optics.dispose());camera.frame=native_frame;deps.options.focal_length=focal_length
-- A dead persistence transport must not own the camera/input restoration path.
-- Store faults and logger faults are independent of genuine native refusals.
do
 local make_store=deps.store.new
 local function cleanup_fixture(kind)
  local f={attempts=0,logs=0}
  deps.store.new=function()return{load=function()return stored end,save=function(_,values)
   f.attempts=f.attempts+1
   if f.failure=='throw'then error('fixture outgoing settings pipe write/flush failed')end
   if f.failure=='refuse'then return false,'fixture settings transport unavailable'end
   stored=values;return true
  end}end
  local prior_render=render
  f.runtime=module('steam_runtime').new({config_dir='unused',log=function()
   f.logs=f.logs+1;if f.log_error then error('fixture diagnostic transport unavailable')end
  end},sr,deps,service)
  local r=f.runtime
  assert(r.handle.set('enabled',true));assert(r.handle.set('freeze_player',true));assert(r.open()and rate==0)
  if kind=='roll'then
   assert(r.focus());pressed.e=true;time=time+.1;r.tick();pressed.e=false
  else
   assert(r.handle.set('fov',45));assert(r.handle.set('path_duration',1));assert(r.handle.activate('path_add'))
   assert(r.handle.set('fov',75));assert(r.handle.activate('path_add'));assert(r.handle.activate('path_play'))
   time=time+.2;r.tick();render()
  end
  f.attempts,f.logs=0,0;f.stored=stored
  function f.restored()
   assert(not r.active and r.state=='closed'and not camera_active and lease==nil and rate==1,
    'Persistence faults must not leak camera, time or input ownership')
   assert(render==prior_render,'Successful native cleanup restores the prior render callback')
   assert(stored==f.stored,'Rejected exit persistence cannot publish partial settings')
   assert(f.attempts==1,'Exit persistence is attempted once, including native cleanup retries')
  end
  return f
 end
 for _,kind in ipairs({'roll','path'})do for _,failure in ipairs({'throw','refuse'})do
  local f=cleanup_fixture(kind);f.failure=failure;f.log_error=kind=='path'and failure=='throw'
  local method=kind=='roll'and f.runtime.close or f.runtime.dispose
  local called,ok=pcall(method,true)
  assert(called and ok==true,kind..' '..failure..' persistence must permit close/dispose')
  f.restored();assert(f.logs>0 and f.runtime.reason:find('lens settings were not saved',1,true),
   'Unsaved lens notice survives a throwing diagnostic logger')
  assert(f.runtime.dispose());assert(f.attempts==1,'Repeated disposal must not retry an unsaved lens')
 end end
 for _,native in ipairs({'time','camera','input'})do for _,failure in ipairs({'throw','refuse'})do
  local camera_close,input_release=camera.close,service.release
  local pending=true
  local function refused()
   if failure=='throw'then error('fixture native '..native..' restore threw')end
   return false,'fixture native '..native..' restore refused'
  end
  if native=='time'then
   sr.Application.set_time_step_policy=function(key,value)
    if pending and value==1 then return refused()end
    return native_policy(key,value)
   end
  end
  local f=cleanup_fixture('roll');f.failure='throw';f.log_error=true
  if native=='camera'then camera.close=function()if pending then return refused()end;return camera_close()end end
  if native=='input'then service.release=function(t)if pending then return refused()end;return input_release(t)end end
  for _=1,2 do
   local called,ok=pcall(f.runtime.close,true)
   assert(called and ok==false and f.runtime.active and f.runtime.state=='closing',
    native..' '..failure..' must retain pending ownership without throwing')
   assert(lease~=nil,'Do not silently forget a pending input lease')
   assert(f.attempts<=1,'Pending native restoration cannot repeat persistence IO')
  end
  pending=false;wall_time=wall_time+1
  local called,ok=pcall(f.runtime.dispose)
  assert(called and ok==true,'Explicit disposal must recover once the native restore succeeds')
  f.restored();camera.close,service.release=camera_close,input_release
  sr.Application.set_time_step_policy=native_policy
 end end
 for _,finalizer in ipairs({'menu','overlay'})do for _,failure in ipairs({'throw','refuse'})do
  local make_view=deps.view.new;local owned_overlay
  deps.view.new=function(native,is_overlay,log)
   local view=make_view(native,is_overlay,log);if is_overlay then owned_overlay=view end;return view
  end
  local f=cleanup_fixture('path');deps.view.new=make_view
  f.failure='throw';f.log_error=true
  local target=finalizer=='menu'and menu or owned_overlay
  local key=finalizer=='menu'and 'close'or 'release'
  local original=target[key];local pending=true;local attempts=0
  target[key]=function(...)
   attempts=attempts+1
   if pending then
    if failure=='throw'then error('fixture '..finalizer..' teardown threw')end
    return false,'fixture '..finalizer..' teardown refused'
   end
   return original(...)
  end
  for attempt=1,2 do
   local called,ok=pcall(f.runtime.dispose)
   assert(called and ok==false and f.runtime.state=='closing',
    finalizer..' '..failure..' must retain pending GUI retirement without throwing')
   assert(not camera_active and lease==nil and rate==1,'GUI retirement failure must not retain native ownership')
   assert(f.attempts==1 and attempts==attempt,'GUI retirement retries cannot repeat failed lens persistence')
   local acquired=acquisitions
   assert(not f.runtime.open()and acquisitions==acquired,'Do not reopen or reacquire input before GUI retirement')
  end
  pending=false
  local called,ok=pcall(f.runtime.dispose)
  assert(called and ok==true,'Explicit disposal recovers after GUI retirement succeeds')
  f.restored();assert(attempts==3);target[key]=original
 end end
 deps.store.new=make_store
end
os.time=native_clock
print('Steam runtime: idle work, camera/action/path controls, Freeze/slow motion, ownership, lens presets/readout and saved visibility passed')

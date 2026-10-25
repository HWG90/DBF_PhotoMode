-- Keys hosted by a loader's Mod Bindings Menu: registration, held keys and our own edges,
-- the loader's focus/chat hold-back, labels, panel rows, and the unhosted path. Fakes only.
local function module(name)return dofile('freecam/'..name..'.lua')end
local B=module('steam_bindings');local names=module('steam_input').key_names
assert(B.spec(80,names).button=='p'and B.spec(80,names).trigger=='hold'and B.spec(16,names).button=='left shift')
assert(B.spec(4,names).device=='mouse'and B.spec(4,names).button=='middle'and B.spec(0,names).button=='','Mouse buttons and no key')
-- Boot Mod Loader's look-alike, reduced: held state per id, a guard, and the window's value.
local function helper()
 local api={window='HD2 Mod Setting GUI',registered={},order={},down={},values={},blocked=false,refuse={}}
 function api.register_binding(id,label,slot,options)
  if api.refuse[label]then return false,'binding already registered differently'end
  assert(slot==nil and options.category=='War Journalist'and options.default.trigger=='hold')
  api.registered[id]={label=label,default=options.default};api.order[#api.order+1]=id
  api.values[id]=options.default.button;return true
 end
 function api.is_down(id)return api.registered[id]~=nil and api.down[id]==true and not api.blocked end
 function api.binding(id)local v=api.values[id];if v==''then return{}end;return{{api.registered[id].default.device,v,modifiers={},trigger='hold'}}end
 function api.set_binding(id,spec)if not api.registered[id]then return false,'not an extended binding'end;api.values[id]=spec.button;return true end
 return api
end
do
 local api=helper();api.refuse['Roll left']=true;local lines={}
 local hosted=B.new(api,{{id='toggle_key',label='Photo mode toggle',default=80},{id='roll_left_key',label='Roll left',default=81},
  {id='up_key',label='Move up',default=16}},names,function(m)lines[#lines+1]=m end)
 assert(hosted.hosted('toggle_key')and hosted.hosted('up_key')and not hosted.hosted('roll_left_key'),'A refused key stays ours')
 assert(api.registered['war_journalist.toggle_key'].default.button=='p'and #lines==1 and lines[1]:find('Roll left',1,true))
 assert(not hosted.down('toggle_key'));api.down['war_journalist.toggle_key']=true;assert(hosted.down('toggle_key'))
 api.blocked=true;assert(not hosted.down('toggle_key'),'The loader holds keys back (no focus, chat open)');api.blocked=false
 assert(hosted.label('toggle_key')=='P'and hosted.label('up_key')=='LEFT SHIFT'and hosted.label('roll_left_key')==nil)
 api.values['war_journalist.toggle_key']='o';assert(hosted.label('toggle_key')=='O','A key set in the window shows')
 api.values['war_journalist.toggle_key']='';assert(hosted.label('toggle_key')=='NONE')
end
-- The runtime with a hosted helper: the minimal harness of steam_runtime_tests.
local function runtime_case(api,saved,virtual_cursor,extra,log)
 local pressed={};local time=0;local stored=saved or{}
 local token,lease
 local raw={x=100,y=100,width=1920,height=1080,buttons=0,wheel=0,dx=0,dy=0}
 local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true,virtual_cursor=virtual_cursor},
  acquire=function()assert(not lease);token={};lease=token;return token end,
  owns=function(t)return lease~=nil and lease==t end,
  status=function()return{owner=lease and'dbf_freecam'or nil,pending_restore=false}end,
  release=function(t)assert(t==lease);lease=nil;return true end,
  snapshot=function(t)assert(t==lease);return raw end}
 local key_names,key_ids={},{}
 local sr={Application={time_since_launch=function()return time end,main_world=function()return'world'end,
   set_time_step_policy=function()end},Gui={resolution=function()return 1920,1080 end},
  Window={has_focus=function()return true end},Keyboard={button_id=function(s)
   if not key_ids[s]then key_names[#key_names+1]=s;key_ids[s]=#key_names end;return key_ids[s]
  end,button=function(id)return pressed[key_names[id]]and 1 or 0 end},
  Network={game_session=function()return{}end},GameSession={peers=function()return{'local'}end}}
 local camera_active,last_position=false,nil
 local camera={open=function()camera_active=true;return true end,scene=function()return'world',1 end,
  frame=function()return{position={0,0,0},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}end,
  write_view=function(p)last_position={p[1],p[2],p[3]};return true end,close=function()camera_active=false;return true end}
 local deps={camera={new=function()return camera end},input=module('steam_input'),core=module('vendor/core'),
  store={new=function()return{load=function()return stored end,save=function(_,values)stored=values;return true end}end},
  view={new=function()return{draw=function(commands)for _,c in ipairs(commands or{})do if c.ui_role=='photo_pointer'then drawn_pointer=true end end end,release=function()end}end},
  options=module('photo_options'),menu=module('photo_menu'),legend=module('control_legend'),composition=module('composition'),
  look=module('look'),lens=module('lens'),hosted_bindings=api and{api=api,window=api.window,factory=B}}
 for k,v in pairs(extra or{})do deps[k]=v end
 local menu;local menu_new=deps.menu.new;deps.menu.new=function(...)menu=menu_new(...);return menu end
 render=function()return'native'end
 drawn_pointer=false
 local runtime=module('steam_runtime').new({config_dir='unused',log=log or function()end},sr,deps,service)
 -- The camera is written at render time, as in game.
 local function tick()time=time+.016;runtime.tick();render()end
 return runtime,deps,pressed,tick,function()return last_position end,function()return menu end
end
do
 local api=helper()
 local runtime,deps,pressed,tick,position,menu=runtime_case(api)
 local ids={};for _,id in ipairs(api.order)do ids[id]=true end
 for _,id in ipairs({'toggle_key','focus_key','hide_controls_key','lock_camera_key','forward_key','back_key','left_key','right_key','up_key','down_key','roll_left_key','roll_right_key','recover_input_key'})do
  assert(ids['war_journalist.'..id],'Hosted: '..id)
 end
 assert(not ids['war_journalist.screenshot_key'],'Disabled keys (no capture) are not offered')
 assert(api.registered['war_journalist.forward_key'].default.button=='w'and api.registered['war_journalist.up_key'].default.button=='left shift')
 local rows={}
 for _,page in ipairs(menu().pages)do for _,c in ipairs(page.controls)do rows[c.id]=c end end
 assert(rows.keys_status and rows.keys_status.label:find('shared with HD2 Mod Setting GUI',1,true),'The Controls page says the keys are shared')
 assert(not rows.toggle_key.disabled and rows.toggle_key.key_label()=='P','Hosted rows stay editable and show the hosted key')
 -- A key set in our panel is written through to the helper.
 assert(runtime.handle.set('toggle_key',79)and api.values['war_journalist.toggle_key']=='o'and rows.toggle_key.key_label()=='O','Panel edits reach the helper')
 assert(runtime.handle.set('focus_key',1)and api.values['war_journalist.focus_key']=='tab','Left mouse cannot be bound there; the helper keeps its key')
 assert(runtime.handle.set('toggle_key',80)and api.values['war_journalist.toggle_key']=='p')
 assert(rows.enabled==nil,'No Enable Photo Mode row: it could only be turned back on from the panel it closes')
 assert(deps.legend.binding_label('toggle_key',runtime.handle)=='P','Labels come from the helper')
 -- The engine key alone no longer opens Photo Mode; the helper's key does.
 pressed.p=true;tick();pressed.p=false;tick();assert(not runtime.active,'A hosted key ignores our stored virtual key')
 api.down['war_journalist.toggle_key']=true;tick();api.down['war_journalist.toggle_key']=false;tick()
 assert(runtime.active and runtime.mode=='menu','The hosted toggle opens Photo Mode')
 api.down['war_journalist.focus_key']=true;tick();api.down['war_journalist.focus_key']=false;tick()
 assert(runtime.mode=='camera','The hosted focus key switches to the camera')
 local before=position();api.down['war_journalist.forward_key']=true;for _=1,5 do tick()end;api.down['war_journalist.forward_key']=false
 local after=position();assert(before and after and after[1]>before[1],'A held hosted key moves the camera')
 -- Held keys repeat nothing: one press closes, the held frames after it do not reopen.
 api.blocked=true;api.down['war_journalist.toggle_key']=true;tick();assert(runtime.active,'Held back by the loader (chat open)')
 api.blocked=false;tick();assert(not runtime.active,'The press counts once the loader lets it through')
 tick();tick();assert(not runtime.active,'Holding the key does not toggle again')
 api.down['war_journalist.toggle_key']=false;tick()
 assert(runtime.dispose()and deps.legend.hosted_label==nil,'Dispose drops the legend hook')
end
do
 -- Without a helper the stored virtual keys work as before; a saved enabled=false from
 -- older builds no longer locks Photo Mode out.
 local runtime,deps,pressed,tick=runtime_case(nil,{enabled=false})
 assert(deps.legend.hosted_label==nil and deps.legend.binding_label('toggle_key',runtime.handle)=='P')
 pressed.p=true;tick();pressed.p=false;tick();assert(runtime.active,'Unhosted toggle opens Photo Mode')
 for _=1,3 do tick()end;assert(not drawn_pointer,'An OS-cursor host draws no pointer')
 assert(runtime.dispose())
end
do
 -- An engine host's virtual cursor is drawn by the Photo menu.
 local runtime,deps,pressed,tick=runtime_case(nil,nil,true)
 pressed.p=true;tick();pressed.p=false;for _=1,3 do tick()end
 assert(runtime.active and runtime.mode=='menu'and drawn_pointer,'The menu draws the virtual cursor')
 assert(runtime.dispose())
end
do
 -- Native features retried at each open: subject logs once it recovers; hover says once that
 -- it waits for its game code instead of repeating the read failure.
 local lines={};local subject_calls,hover_calls=0,0
 local function quiet(fields)return setmetatable(fields,{__index=function()return function()return true end end})end
 local extra={subject_backend={new=function()subject_calls=subject_calls+1
   if subject_calls==1 then error('Native binding is not executable')end
   return quiet({frame=function()return nil end,head_frame=function()return nil end,can_freeze=function()return false end})end},
  subject_visibility={new=function()return quiet({ready=function()return false end})end},
  load_hover=function()hover_calls=hover_calls+1
   if hover_calls<=2 then error('dbf_freecam_lua51/src/steam_hover_backend.lua:56: Protected native read failed')end
   return quiet({owned=function()return false end,status=function()return{available=true}end})end}
 local runtime,deps,pressed,tick=runtime_case(nil,nil,nil,extra,function(m)lines[#lines+1]=m end)
 local function count(text)local n=0;for _,m in ipairs(lines)do if m:find(text,1,true)then n=n+1 end end;return n end
 assert(count('Subject backend unavailable: ')==1 and count('Subject backend ready')==0,'Start-up failure logged once')
 for open=1,3 do
  pressed.p=true;tick();pressed.p=false;tick();assert(runtime.active,'Photo Mode opens with native features unavailable')
  runtime.close(true);tick()
 end
 assert(count('Subject backend ready (it was unavailable: ')==1,'Recovery after the first open is logged once')
 assert(count('Hover pause unavailable: waiting for its game code')==1 and count('Protected native read failed')==0,'Hover says once that it waits')
 assert(count('Hover pause ready')==1 and hover_calls==3,'Hover logs when it becomes ready')
 assert(runtime.dispose())
end
print('Hosted bindings: registration and defaults, refused keys stay ours, held keys and our edges, loader hold-back, labels, no Enable row, the drawn virtual cursor, native retry messages and the unhosted path passed')

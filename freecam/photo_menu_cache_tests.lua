local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Menu=dofile(root..'photo_menu.lua')
local function fixture(module,freeze_only,hud_binding,hide_unavailable)
 local f={values={speed=2,choice=1,enabled=true,slowmo_speed=.2,lock_camera=false,tab_layout=1},measure_calls=0,metric_calls=0,refresh_calls=0,width_factor=.75}
 local function count(label)local n=0;for _ in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;return n end
 f.measure=function(label,size)f.measure_calls=f.measure_calls+1;return count(label)*size*f.width_factor end
 f.metrics=function(size,label)f.metric_calls=f.metric_calls+1;return{min_y=-size*.2,max_y=size*.8,optical_y=0}end
 f.view={draw=function(commands,token)f.commands=commands;f.token=token end,release=function()end,measure=f.measure,text_metrics=f.metrics,font_key='stock',metric_key='stock|0',refresh_font=function()f.refresh_calls=f.refresh_calls+1;local changed=f.font_changed;f.font_changed=false;return changed end}
 f.controls={{id='speed',type='slider',label='A deliberately long focus distance label with UTF-8: éclair 日本語',min=.1,max=100,step=.1,fine_step=.01},
  {id='choice',type='choice',label='Method',choices={'Native camera','Shader preview'}},{id='enabled',type='toggle',label='Enabled'},
  {id='note',type='text',label='A long informational line with café and 日本語 that wraps cleanly across the available row width without splitting UTF-8 glyphs.'}}
 f.pages={};for i,name in ipairs({'Camera','Lens','Color','Effects','Lighting','Composition','Director','Subject','Controls'})do f.pages[i]={id=name:lower(),name=name,controls=f.controls}end
 f.nonvalue_reads=0
 f.handle={get=function(id)if id=='note'then f.nonvalue_reads=f.nonvalue_reads+1;error('Text is not a registered value')end;return f.values[id]end,set=function(id,value)f.values[id]=value;return true end,activate=function()end}
 local actions={focus=function()end,hud=function()end,hide=function()end,exit=function()end,freeze=function()end,freeze_state=function()return false,true,.2 end}
 if not freeze_only then actions.slowmo=function()end;actions.slowmo_state=function()return false,true end end
 actions.hud_binding=hud_binding;actions.hide_unavailable=hide_unavailable
 f.menu=module.new(f.view,actions)
 f.menu.bind(f.handle,f.pages)
 function f.draw(w,h)f.menu.draw(w or 1920,h or 1080,true,false,{focus='TAB',hide='H'})end
 function f.find(test)for _,c in ipairs(f.commands)do if test(c)then return c end end;error('Missing command')end
 return f
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local f=fixture(Menu);f.draw();local cold_measure,cold_metrics=f.measure_calls,f.metric_calls;local first=f.commands
local freeze_only=fixture(Menu,true);freeze_only.draw()
local freeze_button=freeze_only.find(function(c)return c.full_text=='Freeze Action'end)
local exit_button=freeze_only.find(function(c)return c.full_text=='Exit photo mode'end)
assert(freeze_button.y>exit_button.y+100,'Freeze-only backend must use the visible top toolbar')
assert(cold_measure>30 and cold_metrics>10,'Fixture must exercise long labels, tabs and metrics')
for _=1,40 do f.draw()end
assert(f.nonvalue_reads==0,'Static text must not allocate caught lookup errors on every frame')
assert(f.measure_calls==cold_measure and f.metric_calls==cold_metrics,'Warm static composition repeated text work')
assert(f.refresh_calls==41 and same(first,f.commands),'Cached layout changed draw commands or skipped font refresh')
assert(f.token==f.commands,'Unchanged panel must explicitly promise immutable retained commands')
local static_lighting=fixture(Menu);static_lighting.menu.page=5;static_lighting.draw()
local lighting_commands=static_lighting.commands;static_lighting.draw()
assert(static_lighting.commands==lighting_commands,'Lighting without scene gizmos must retain its unchanged panel')
static_lighting.menu.light_gizmos={revision=0,cancel=function()end,draw=function()end}
static_lighting.draw();lighting_commands=static_lighting.commands;static_lighting.draw()
assert(static_lighting.commands==lighting_commands,'Unchanged revisioned markers must not force recomposition')
static_lighting.menu.light_gizmos.revision=1;static_lighting.draw()
assert(static_lighting.commands~=lighting_commands,'Changed marker projection must invalidate retained panel commands')
-- The cache owns only text results; every frame must still read fresh values,
-- labels, disabled flags and page structure from the authoritative handles.
f.values.choice=2;f.values.enabled=false;f.controls[1].disabled=true;f.controls[1].label='New focus label';f.pages[1].name='Camera renamed';f.draw()
assert(f.find(function(c)return c.control_id=='speed'and c.type=='text'end).full_text=='New focus label')
assert(f.find(function(c)return c.ui_role=='field'and c.control_id=='speed'end).c[1]==19,'Disabled control remained enabled')
assert(f.find(function(c)return c.full_text=='Shader preview'end))
assert(f.find(function(c)return c.full_text=='OFF'end))
assert(f.find(function(c)return c.ui_role=='photo_tab_label'and c.full_text=='Camera renamed'end))
f.controls[#f.controls+1]={id='later',type='button',label='Added later',button_label='Run'};f.draw();assert(f.find(function(c)return c.full_text=='Added later'end))
local function invalidates(change,why)
 local n,m=f.measure_calls,f.metric_calls;change();f.draw();assert(f.measure_calls>n and f.metric_calls>m,why)
 n,m=f.measure_calls,f.metric_calls;f.draw();assert(f.measure_calls==n and f.metric_calls==m,'New text context did not become warm')
end
invalidates(function()f.view.font_key='hud' end,'Font identity did not invalidate')
invalidates(function()f.width_factor=1.3;f.view.metric_key='hud|1'end,'Metric generation did not invalidate')
invalidates(function()f.width_factor=.5;f.font_changed=true end,'Explicit font refresh did not invalidate')
local previous=f.commands
invalidates(function()local old=f.view.measure;f.view.measure=function(...)return old(...)*1.5 end end,'Measurement callback identity did not invalidate')
assert(not same(previous,f.commands),'A live replacement measurement callback did not change layout')
previous=f.commands
invalidates(function()f.view.text_metrics=function(size,label)f.metric_calls=f.metric_calls+1;return{min_y=0,max_y=size*.5,optical_y=2}end end,'Metrics callback identity did not invalidate')
assert(not same(previous,f.commands),'A live replacement font metrics callback did not change text baselines')
invalidates(function()f.menu.size_scale=.8 end,'Panel size did not invalidate')
invalidates(function()f.values.tab_layout=2 end,'Tab layout did not invalidate')
local n=f.measure_calls;f.draw(1280,720);assert(f.measure_calls>n,'Viewport change did not invalidate')
-- A second panel/view with different metrics cannot reuse another panel's face.
local other,twin=fixture(Menu),fixture(Menu);other.width_factor=1.8;other.draw(1280,720);twin.draw(1280,720)
assert(other.measure_calls>0 and not same(other.commands,twin.commands),'Text results leaked between views')
-- Failed providers stay retryable; no derived fit may freeze fallback geometry.
local retry=fixture(Menu);local calls=0;retry.view.measure=function(label,size)calls=calls+1;if calls<300 then error('font temporarily unavailable')end;return #label*size*.3 end
retry.draw();assert(retry.token==nil,'Transient layout must not promise immutable geometry')
local before=calls;retry.draw();assert(calls>before,'Failed measurement was retained as a valid fit')
retry.view.measure=retry.measure;retry.draw();local measured=retry.measure_calls;retry.draw();assert(retry.measure_calls==measured)
local retry_metrics=fixture(Menu);local metric_attempts=0;retry_metrics.view.text_metrics=function(size,label)metric_attempts=metric_attempts+1;if metric_attempts<100 then return nil end;return{min_y=-size*.1,max_y=size*.6}end
retry_metrics.draw();before=metric_attempts;retry_metrics.draw();assert(metric_attempts>before,'Invalid metrics were retained as valid font geometry')
-- Exceed the fixed capacity with changing text; an old result must be evicted,
-- and returning to stable content must settle without an unbounded history.
local bounded=fixture(Menu);bounded.draw();for i=1,1100 do bounded.controls[1].label='Changing label '..i;bounded.draw()end
bounded.controls[1].label='Stable label';bounded.draw();bounded.draw();local stable=bounded.measure_calls;for _=1,20 do bounded.draw()end;assert(bounded.measure_calls==stable,'Bounded cache failed to settle after churn')
-- Optional A/B mode loads an immutable git-show baseline. Compare actual
-- command trees before reporting allocation/call counts in the review receipt.
local baseline_path=rawget(_G,'PHOTO_MENU_CACHE_BASELINE')
if baseline_path then
 local Baseline=dofile(baseline_path)
 for _,size in ipairs({{640,480},{1280,720},{1920,1080},{3840,2160}})do
  for _,layout in ipairs({1,2})do
   local a,b=fixture(Baseline),fixture(Menu);a.values.tab_layout=layout;b.values.tab_layout=layout;a.draw(size[1],size[2]);b.draw(size[1],size[2]);assert(same(a.commands,b.commands),'Baseline/candidate drawing differs')
   a.values.choice=2;b.values.choice=2;a.controls[1].disabled=true;b.controls[1].disabled=true;a.draw(size[1],size[2]);b.draw(size[1],size[2]);assert(same(a.commands,b.commands),'Dynamic baseline/candidate drawing differs')
  end
 end
 local function benchmark(module)
  local v=fixture(module);for _=1,30 do v.draw()end
  collectgarbage('collect');collectgarbage('stop');local kb=collectgarbage('count');local n,m=v.measure_calls,v.metric_calls;local started=os.clock()
  for _=1,600 do v.draw()end
  local elapsed=os.clock()-started;local allocated=collectgarbage('count')-kb;collectgarbage('restart')
  return{allocated_kib=allocated,measure_calls=v.measure_calls-n,metric_calls=v.metric_calls-m,cpu_seconds=elapsed}
 end
 local a,b=benchmark(Baseline),benchmark(Menu)
 assert(b.measure_calls==0 and b.metric_calls==0 and b.allocated_kib<a.allocated_kib*.85,'Cache failed to reduce actual module allocation/work')
 print(string.format('MENU_CACHE_AB baseline_kib=%.3f candidate_kib=%.3f baseline_measure=%d candidate_measure=%d baseline_metrics=%d candidate_metrics=%d baseline_cpu=%.6f candidate_cpu=%.6f',a.allocated_kib,b.allocated_kib,a.measure_calls,b.measure_calls,a.metric_calls,b.metric_calls,a.cpu_seconds,b.cpu_seconds))
end
print('Photo menu cache: fresh control state, bounded warm layout, callback/font/generation/size/layout invalidation, transient retries and UTF-8 command parity passed')

-- Recreated equivalent choice arrays must not invalidate retained composition.
local retained=fixture(Menu);retained.draw();retained.draw();local commands=retained.commands
for _=1,20 do retained.controls[2].choices={'Native camera','Shader preview'};retained.draw();assert(retained.commands==commands,'Equivalent choice arrays forced panel rebuild')end
retained.controls[2].choices[1]='Changed native choice';retained.draw();assert(retained.commands~=commands,'Changed choice label did not invalidate panel')

-- Explicitly revisioned fixed catalogs must never enumerate their labels on
-- warm draws. Instrument the real iterator; text/geometry still use real lists.
local watched_lists,choice_iterations={},0
local instrumented_env=setmetatable({ipairs=function(t)
 local iterator,state,index=ipairs(t)
 if not watched_lists[t]then return iterator,state,index end
 return function(s,i)choice_iterations=choice_iterations+1;return iterator(s,i)end,state,index
end},{__index=_G})
local menu_chunk=assert(loadfile(root..'photo_menu.lua'));setfenv(menu_chunk,instrumented_env)
local catalog=fixture(menu_chunk());local items={}
for i=1,213 do items[i]='Pose '..i end
catalog.controls[2].choices=items;watched_lists[items]=true
catalog.draw();local legacy_iterations=choice_iterations;catalog.draw()
assert(choice_iterations>legacy_iterations,'Fixture must observe legacy choice enumeration')
catalog.controls[2].choices_revision=1;catalog.draw();local catalog_commands=catalog.commands
choice_iterations=0
for _=1,50 do catalog.draw();assert(catalog.commands==catalog_commands)end
assert(choice_iterations==0,'Unchanged revisioned catalog must not enumerate its labels')
items[1]='Revised pose';catalog.controls[2].choices_revision=2;catalog.draw()
assert(catalog.commands~=catalog_commands and catalog.find(function(c)return c.full_text=='Revised pose'end),
 'Published revision must refresh the selected choice text')
catalog_commands=catalog.commands
local replacement={};for i=1,213 do replacement[i]='Replacement '..i end
catalog.controls[2].choices=replacement;watched_lists[replacement]=true;catalog.draw()
assert(catalog.commands~=catalog_commands and catalog.find(function(c)return c.full_text=='Replacement 1'end),
 'Replacing a revisioned catalog must invalidate even with an unchanged revision')
catalog.controls[2].choices_revision=nil;catalog.draw();catalog_commands=catalog.commands
replacement[1]='Mutable again';catalog.draw()
assert(catalog.commands~=catalog_commands,'Removing the revision promise must restore mutable-list observation')

-- A capture must explicitly release owned UI even when empty draws refuse
-- before clearing stale planes (for example during failed font binding).
local capture=fixture(Menu);capture.draw();local visible=capture.commands
local releases=0;local refuse=true
capture.view.draw=function()return false end
capture.view.release=function()
 releases=releases+1;if refuse then return false end
 capture.commands={};return true
end
assert(not capture.menu.hide_for_capture()and capture.commands==visible and releases==1)
refuse=false;assert(capture.menu.hide_for_capture()and #capture.commands==0 and releases==2)
for _=1,100 do assert(capture.menu.hide_for_capture())end
assert(releases==2,'Unchanged hidden capture must not repeatedly release planes')
capture.menu.suspend();assert(capture.menu.hide_for_capture()and releases==3,'Suspension invalidates the clear acknowledgement')
capture.menu.draw_cinema(1920,1080,'P',true,0,false)
assert(capture.menu.hide_for_capture()and releases==4,'Ordinary render invalidates the clear acknowledgement')
capture.menu.suspend();capture.view.release=function()error('fixture release failed')end
assert(not pcall(capture.menu.hide_for_capture),'A throwing release cannot acknowledge a clean frame')

do
 local label,warning='/',nil
 local f=fixture(Menu,false,function()return label,warning end)
 f.draw();f.find(function(c)return c.text=='Toggle HUD [/]'end)
 for _,c in ipairs(f.commands)do assert(c.text~='Toggle HUD','Game binding display must replace the HUD button')end
 local commands=f.commands;f.draw();assert(f.commands==commands,'Unchanged HUD binding must retain geometry')
 label='Unbound';warning="Toggle HUD is unbound. Assign it in the game's key bindings."
 f.draw();assert(f.commands~=commands);f.find(function(c)return c.full_text=='Toggle HUD [Unbound]'end)
 f.find(function(c)return c.text==warning end)
 commands=f.commands;f.draw();assert(f.commands==commands,'Unbound warning stays idle')
 print('HUD binding menu: read-only label, unbound warning, invalidation and retained idle passed')
end

-- Blur follows each owned surface rather than covering the viewport or the
-- gap. Moving/scaling the panel invalidates geometry; steady state is retained.
do
 local f=fixture(Menu);f.view.menu_blur_material=function()return 'native-menu-blur'end
 local function check(w,h)
  f.draw(w,h)
  local panel=f.find(function(c)return c.ui_role=='photo_panel'end)
  local footer=f.find(function(c)return c.ui_role=='photo_controls_strip'end)
  local blur=f.find(function(c)return c.ui_role=='photo_menu_backdrop'end)
  local strip=f.find(function(c)return c.ui_role=='photo_footer_backdrop'end)
  for _,pair in ipairs({{blur,panel},{strip,footer}})do
   local a,b=pair[1],pair[2]
   assert(a.type=='bitmap'and a.native_material=='native-menu-blur')
   assert(a.x==b.x and a.y==b.y and a.w==b.w and a.h==b.h and a.layer<b.layer,'Blur must exactly match its owned surface')
   assert(a.w<w and a.h<h,'Blur cannot cover the viewport')
  end
  assert(strip.y+strip.h<blur.y,'Keep the footer gap unblurred')
  -- Live, with Exposure/Contrast/Saturation or a filter on, the scene grade covered every
  -- GUI layer up to 300 (the blur backdrop and the panel tint) while 301 and above stayed
  -- on top. The whole panel stays above that, and below the legend (330+) and pointer.
  for _,c in ipairs(f.commands)do
   if c.ui_role~='photo_pointer'and c.ui_role~='photo_pointer_outline'then
    assert(c.layer>301 and c.layer<330,'Panel layer '..tostring(c.layer)..' ('..tostring(c.ui_role)..') must sit above the scene grade and below the legend')
   end
  end
  local commands=f.commands;f.draw(w,h);assert(f.commands==commands,'Static decorated/blurred menu stays retained')
 end
 check(1920,1080);f.menu.panel_x=.1;f.menu.panel_y=.3;f.menu.size_scale=.8;check(1280,720)
 f.menu.draw(1280,720,true,true,{focus='TAB',hide='H'});assert(#f.commands==0,'Hidden controls cannot leave a blur quad behind')
end

-- User release omits unavailable rows, while registration and dynamic recovery
-- remain intact. Disabled-state changes already invalidate retained geometry.
do
 local f=fixture(Menu,nil,nil,true);f.controls[1].disabled=true;f.draw()
 for _,c in ipairs(f.commands)do assert(c.control_id~='speed','Disabled control leaked into the release menu')end
 local commands=f.commands;f.draw();assert(f.commands==commands,'Hidden unavailable rows stay retained')
 f.controls[1].disabled=false;f.draw();f.find(function(c)return c.control_id=='speed'and c.type=='text'end)
 assert(f.commands~=commands,'Recovered native control must become visible')
end
print('User menu: disabled rows hidden, registrations retained, available controls return and unchanged geometry stays cached passed')

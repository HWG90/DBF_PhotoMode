local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Menu=dofile(root..'photo_menu.lua')
local function fixture(module)
 local f={values={speed=2,choice=1,enabled=true,slowmo_speed=.2,lock_camera=false,tab_layout=1},measure_calls=0,metric_calls=0,refresh_calls=0,width_factor=.75}
 local function count(label)local n=0;for _ in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;return n end
 f.measure=function(label,size)f.measure_calls=f.measure_calls+1;return count(label)*size*f.width_factor end
 f.metrics=function(size,label)f.metric_calls=f.metric_calls+1;return{min_y=-size*.2,max_y=size*.8,optical_y=0}end
 f.view={draw=function(commands)f.commands=commands end,release=function()end,measure=f.measure,text_metrics=f.metrics,font_key='stock',metric_key='stock|0',refresh_font=function()f.refresh_calls=f.refresh_calls+1;local changed=f.font_changed;f.font_changed=false;return changed end}
 f.controls={{id='speed',type='slider',label='A deliberately long focus distance label with UTF-8: éclair 日本語',min=.1,max=100,step=.1,fine_step=.01},
  {id='choice',type='choice',label='Method',choices={'Native camera','Shader preview'}},{id='enabled',type='toggle',label='Enabled'},
  {id='note',type='text',label='A long informational line with café and 日本語 that wraps cleanly across the available row width without splitting UTF-8 glyphs.'}}
 f.pages={};for i,name in ipairs({'Camera','Lens','Color','Effects','Lighting','Composition','Director','Subject','Controls'})do f.pages[i]={id=name:lower(),name=name,controls=f.controls}end
 f.handle={get=function(id)return f.values[id]end,set=function(id,value)f.values[id]=value;return true end,activate=function()end}
 f.menu=module.new(f.view,{focus=function()end,hud=function()end,hide=function()end,exit=function()end,freeze=function()end,freeze_state=function()return false,true,.2 end,slowmo=function()end,slowmo_state=function()return false,true end})
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
assert(cold_measure>30 and cold_metrics>10,'Fixture must exercise long labels, tabs and metrics')
for _=1,40 do f.draw()end
assert(f.measure_calls==cold_measure and f.metric_calls==cold_metrics,'Warm static composition repeated text work')
assert(f.refresh_calls==41 and same(first,f.commands),'Cached layout changed draw commands or skipped font refresh')
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
retry.draw();local before=calls;retry.draw();assert(calls>before,'Failed measurement was retained as a valid fit')
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

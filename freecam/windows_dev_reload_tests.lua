local M=dofile('freecam/windows_dev_reload.lua')
local function pack(rows)
 local out={'WJL-LUA-1\n'..#rows..'\n'}
 for _,r in ipairs(rows)do out[#out+1]=r[1]..'\n'..#r[2]..'\n'..r[2]end
 return table.concat(out)
end
local main=[[return {live_lua_api=1,on_enable=function()mod.mark('enabled')end,on_update=function()end,on_disable=function()return true end,on_cleanup_poll=function()return true end}]]
local function rig(source,pinned)
 local t,reads,cleanups=0,0,0;local log,events={},{};local ready=true
 local files={['cfg/wj-dev-a.lua-pack']=source or pack({{'main.lua',main}})}
 local old={on_cleanup_poll=function()cleanups=cleanups+1;return ready,'pending'end}
 local m=M.new({config_dir='cfg',log=function(s)log[#log+1]=s end,mark=function(s)events[#events+1]=s end},old,function()return t end,function()return 0 end,
 {read=function(p)reads=reads+1;return files[p]end},{pinned=pinned})
 files['cfg/wj-dev-reload.request']='a\n';reads=0
 return {m=m,old=old,files=files,log=log,events=events,time=function(n)t=n end,ready=function(v)ready=v end,
 counts=function()return reads,cleanups end}
end
do
 local r=rig();assert(not r.m.tick());local reads=r.counts();assert(reads==2)
 assert(r.m.tick());assert(r.m.entry()==r.old);assert(select(2,r.counts())==0)
 r.ready(false);assert(r.m.tick());assert(#r.events==0)
 r.ready(true);assert(not r.m.tick());assert(r.m.entry()~=r.old and r.events[1]=='enabled')
 for i=1,100 do r.m.tick()end;assert(r.counts()==reads,'Idle must not read files every frame')
 r.time(2);r.m.tick();assert(r.counts()==reads+1,'Same request must not read payload or reload')
end
do
 local r=rig(pack({{'main.lua','this is not Lua'}}));r.m.tick();r.m.tick()
 assert(r.m.entry()==r.old and select(2,r.counts())==0 and r.m.status()=='idle')
end
do
 local r=rig(nil,{['src/pinned.lua']='resident'});r.m.tick()
 assert(select(2,r.counts())==0 and r.m.status()=='idle')
 assert(r.log[#r.log]:find('Resident module changed',1,true))
end
do
 local r=rig();r.m.tick();r.m.tick();r.ready(false);r.time(11);assert(r.m.tick())
 assert(r.m.status()=='halted'and #r.events==0,'Never start a new owner after failed cleanup')
end
do
 local r=rig(pack({{'main.lua',main:gsub("mod.mark%('enabled'%)","error('bad start')")}}));r.m.tick();r.m.tick();assert(r.m.tick());assert(r.m.status()=='failed-cleanup')
 assert(r.m.tick());assert(r.m.status()=='halted')
end
do
 local r=rig(pack({{'main.lua',"error('bad entry')"}}));r.m.tick();r.m.tick();assert(r.m.tick());assert(r.m.status()=='halted')
end
for _,blob in ipairs({pack({{'../main.lua',main}}),pack({{'main.lua',main},{'main.lua',main}}),pack({{'main.lua',main}})..'trailing','WJL-LUA-1\n999\n'})do assert(not pcall(M.parse,blob))end
do
 local registrations=0;local b=M.bindings({register_binding=function()registrations=registrations+1;return true end})
 assert(b.register_binding('key'));assert(b.register_binding('key'));assert(registrations==1)
end
do
 local rows=M.parse(pack({{'main.lua',[[local v=mod.require('src/value.lua');return {live_lua_api=1,on_enable=function()mod.mark(v)end,on_update=function()end,on_disable=function()return true end,on_cleanup_poll=function()return true end}]]},{'src/value.lua','return 42'}}))
 for _,r in ipairs(rows)do r.chunk=assert(loadstring(r.source))end
 local got;M.graph(rows,{mark=function(v)got=v end}).on_enable();assert(got==42)
end
print('windows_dev_reload_tests: PASS')

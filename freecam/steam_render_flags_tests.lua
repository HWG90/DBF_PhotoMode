local M=assert(loadfile('freecam/steam_runtime.lua'))()
local now,queue,values=0,{},{bloom_enabled=true,dof_enabled=true}
local function original(key,text)queue[#queue+1]={key,text=='true'}end
local A={time_since_launch=function()return now end,render_setting=function(key)return values[key]end,set_render_setting=original}
local function apply()
 for _,row in ipairs(queue)do values[row[1]]=row[2]end;queue={};now=now+.2
end
local function pair()
 return M.bloom_policy({Application=A}),M.render_flag_policy({Application=A},'dof_enabled','Depth of field')
end
for _,order in ipairs({1,2})do
 local bloom,dof=pair()
 assert(bloom.open(false));assert(dof.open(false));apply()
 assert(bloom.tick(now));assert(dof.tick(now))
 assert(bloom.state=='active'and dof.state=='active')
 assert(not values.bloom_enabled and not values.dof_enabled)
 local first,second=bloom,dof;if order==2 then first,second=dof,bloom end
 assert(first.close(true)==false);apply();assert(first.tick(now));assert(first.close(true))
 assert(second.tick(now));assert(second.state=='active')
 assert(second.close(true)==false);apply();assert(second.tick(now));assert(second.close(true))
 assert(A.set_render_setting==original,'Detached observers must leave the original function')
 assert(values.bloom_enabled and values.dof_enabled)
end
-- An external writer revokes only the flag that it changed.
local bloom,dof=pair();assert(bloom.open(false));assert(dof.open(false));apply();assert(bloom.tick(now));assert(dof.tick(now))
A.set_render_setting('bloom_enabled','true');apply()
assert(bloom.tick(now));assert(bloom.state=='foreign');assert(dof.tick(now));assert(dof.state=='active')
assert(bloom.close(true));assert(dof.close(true)==false);apply();assert(dof.tick(now));assert(dof.close(true))
assert(A.set_render_setting==original and values.bloom_enabled and values.dof_enabled)
-- A replacement setter is never overwritten during cleanup.
bloom,dof=pair();assert(bloom.open(true));assert(dof.open(true))
local replacement=function()end;A.set_render_setting=replacement
assert(bloom.tick(now));assert(dof.tick(now));assert(bloom.close(true));assert(dof.close(true))
assert(A.set_render_setting==replacement)

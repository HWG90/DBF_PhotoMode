local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'animation_state.lua')
local function pack(...)return{n=select('#',...),...}end
local alive=true;local graph=true;local calls=0;local graph_calls=0;local events={};local fail_alive=false;local fail_graph=false;local fail_get=false
local current={id=1,generation=1};local args;local states={};for i=1,31 do states[i]=i*10 end
local U={}
function U.alive(unit)events[#events+1]='alive';if fail_alive then error('alive lookup failed')end;return alive and unit==current end
function U.has_animation_state_machine(unit)graph_calls=graph_calls+1;events[#events+1]='graph';assert(unit==current);if fail_graph then error('graph lookup failed')end;return graph end
function U.animation_get_state(unit,...)
 calls=calls+1;events[#events+1]='get';assert(unit==current);args=pack(...);if fail_get then error('original Lua getter error')end
 return unpack(states,1,31)
end
local original=U.animation_get_state;local guarded=M.new({Unit=U})
assert(U.animation_get_state==original,'Guard replaced the global SDK getter')
local result=pack(pcall(guarded,current,'extra',nil,7,nil))
assert(result.n==32 and result[1]and result[2]==10 and result[32]==310,'31-state layout changed')
assert(args.n==4 and args[1]=='extra'and args[2]==nil and args[3]==7 and args[4]==nil,'Forwarded arguments/trailing nil changed')
assert(table.concat(events,',')=='alive,graph,get','Guard order changed')
states[4]=nil;states[31]=nil;result=pack(pcall(guarded,current))
assert(result.n==32 and result[1]and result[5]==nil and result[32]==nil and result[31]==300,'Internal or trailing state nil was dropped')
states[4]=40;states[31]=310
alive=false;local before=calls;local before_graph=graph_calls;result=pack(pcall(guarded,current))
assert(not result[1]and calls==before and graph_calls==before_graph,'Dead Unit reached animation graph/getter')
alive=true;graph=false;result=pack(pcall(guarded,current));assert(not result[1]and calls==before,'Missing graph reached native getter')
-- Same Unit can later acquire a graph; a previous failure is never memoized.
graph=true;result=pack(pcall(guarded,current));assert(result[1]and calls==before+1)
local retired=current;current={id=1,generation=2};before=calls;before_graph=graph_calls
assert(not pcall(guarded,retired)and calls==before and graph_calls==before_graph,'Retired generation reached graph/getter')
assert(pcall(guarded,current)and calls==before+1,'Fresh generation did not become readable')
for _,missing in ipairs({'alive','has_animation_state_machine','animation_get_state'})do
 local api={alive=U.alive,has_animation_state_machine=U.has_animation_state_machine,animation_get_state=U.animation_get_state};api[missing]=nil
 before=calls;assert(not pcall(M.new({Unit=api}),current)and calls==before,'Missing API reached original getter')
end
fail_alive=true;before=calls;before_graph=graph_calls;assert(not pcall(guarded,current)and calls==before and graph_calls==before_graph);fail_alive=false
fail_graph=true;before=calls;assert(not pcall(guarded,current)and calls==before);fail_graph=false
fail_get=true;local ok,why=pcall(guarded,current);assert(not ok and tostring(why):find('original Lua getter error',1,true),'Original getter error was swallowed');fail_get=false
-- Match the legacy status/layer indexing and failure branches at the callers.
local function legacy()
 local s={pcall(guarded,current)}
 return s,s[1]and#s>=32,s[1]and s[10],not s[1]or#s<32 or s[15]==103 or(s[6]==0 and s[23]==0)
end
states[9]=329;states[14]=36;states[5]=1;states[22]=6
local s,valid,hellpod,down=legacy();assert(valid and hellpod==329 and not down and s[15]==36 and s[23]==6,'Successful legacy layer branches shifted')
graph=false;before=calls;s,valid,hellpod,down=legacy();assert(s[1]==false and not valid and hellpod==false and down and calls==before,'Legacy failure branches consumed invalid states')
local profile={ok=true,seen=true,l4=99}
local function classify()
 local r={pcall(guarded,current)};profile.ok=r[1]and#r>=32;profile.l4=profile.ok and r[5]or nil
end
classify();assert(not profile.ok and profile.l4==nil,'Failed profile kept usable animation values')
graph=true;classify();assert(profile.ok and profile.l4==40,'Profile retry cached a missing graph')
print('Animation state guard: fresh live/generation and graph checks, no getter on rejection, exact 31-state/argument/nil preservation, propagated Lua errors, unchanged SDK namespace and legacy/profile retry branches passed')

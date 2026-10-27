local Backend=dofile('freecam/windows_hover_freeze.lua')
local pack,body,world={},{},{};local reads=0;local logs={};local writes=0
local sr={Application={main_world=function()return world end},IdString64={from_hex=function(s)return s end},
 World={units_by_resource=function()return{pack}end},Unit={
 alive=function(u)return u==pack or u==body end,world=function()return world end,
 has_animation_state_machine=function(u)reads=reads+1;return u==body end,
 animation_get_state=function(u)assert(u==body);reads=reads+1;return 12,34,56 end,
 animation_has_variable=function(u,name)assert(u==body);reads=reads+1;return name=='in_air'end,
 animation_find_variable=function(u,name)assert(u==body and name=='in_air');return 3 end,
 animation_get_variable=function(u,index)assert(u==body and index==3);return 1 end,
 set_animation_set_state=function()writes=writes+1;error('Unexpected write')end}}
local choose=Backend.new(sr,function(s)logs[#logs+1]=s end,true)
for i=1,6 do assert(choose({root_handle=body})==1e-14)end
assert(reads>0 and writes==0)
local found=false
for _,s in ipairs(logs)do if s:find('variables=in_air=1',1,true)then found=true end end
assert(found,'Probe must copy qualified variable values into the bounded receipt')
local n=reads
for i=1,100 do assert(choose({root_handle=body})==1e-14)end
assert(reads==n,'Finished six-capture animation probe performs no more native animation reads')
sr.Unit.animation_get_state=function()error('Transient state read refused')end
assert(pcall(Backend.activity_probe,sr,function(s)logs[#logs+1]=s end,{root_handle=body},pack,7))
assert(writes==0,'Refused diagnostics cannot mutate state')
print('Hover activity diagnostic: bounded guarded getters, copied numeric snapshots, missing state containment, six-capture limit and no setters passed')

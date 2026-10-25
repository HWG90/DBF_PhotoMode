-- Native diagnostics: page readability per probe, binding entries from the closure, the
-- bridge's own verdict, and nothing but reads. Fake bridge only.
local D=dofile('freecam/native_diagnostics.lua')
local exe,game=0x140000000,0x7ff800000000
local function le64(n)local t={};for i=1,8 do t[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(t)end
local function binding()return function()end end
local sr={Unit={set_mesh_visibility=binding()},World={units=binding()},Application={time_since_launch=binding(),save_render_target=binding()}}
local entries={[sr.Unit.set_mesh_visibility]=exe+0x3f4c80,[sr.World.units]=exe+0x123450,[sr.Application.time_since_launch]=0x7ff900001000}
local closures={}
for f,entry in pairs(entries)do closures[D.closure(f)+0x20]=le64(entry)end
local refused={[exe+0x3f4c80]=true,[game+0x9c6420]=true}
local reads=0
local bridge={module_base=function(n)return n=='helldivers2.exe'and exe or game end,
 read_memory=function(at,n)reads=reads+1;if closures[at]then return closures[at]end;if refused[at]then error('Protected native read failed')end;return string.rep('\0',n)end,
 function_address=function(f)if f==sr.Unit.set_mesh_visibility then error('Native binding is not executable')end;return entries[f]or 0 end}
local lines={}
D.run(sr,{open=function()return bridge end},function(m)lines[#lines+1]=m end,'0 s')
local all=table.concat(lines,'\n')
assert(#lines==1+#D.bindings,'One page line and one line per binding')
assert(lines[1]:find('exe 0x140000000',1,true)and lines[1]:find('exe.header=ok',1,true)and lines[1]:find('exe.set_mesh_visibility=refused',1,true)
 and lines[1]:find('game.hover_control=refused',1,true)and lines[1]:find('game.hover_jump=ok',1,true),'Page readability per probe')
assert(all:find('Unit.set_mesh_visibility: function, what=Lua',1,true)and all:find('entry=exe+0x3F4C80 (expected), entry page refused, function_address failed: ',1,true)
 and all:find('Native binding is not executable',1,true),'An expected entry on an unreadable page, with the bridge\'s verdict')
assert(all:find('World.units: function',1,true)and all:find('entry=exe+0x123450, entry page readable, function_address = 0x140123450',1,true))
assert(all:find('Application.time_since_launch',1,true)and all:find('entry=0x7FF900001000',1,true),'An entry outside the exe is shown as is')
assert(all:find('Application.save_render_target: function',1,true)and all:find('entry unreadable',1,true))
D.run(sr,{open=function()error('loadlib refused')end},function(m)lines[#lines+1]=m end,'30 s')
assert(lines[#lines]:find('Native diagnostics (30 s): bridge unavailable: ',1,true))
print('Native diagnostics: page readability, binding entries and bridge verdicts, read-only, bridge failure passed')

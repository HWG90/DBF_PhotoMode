local Gate=dofile('freecam/engine_cursor_gate.lua')
local visible,esc,clock=false,false,0;local reads,writes=0,0;local fail,unknown=false,false
local sr={Application={time_since_launch=function()return clock end},
 Keyboard={button_id=function()return 27 end,button=function()return esc and 1 or 0 end},
 Window={show_cursor=function()reads=reads+1;if unknown then error('unreadable')end;return visible end,
 set_show_cursor=function(value)writes=writes+1;visible=value;if fail and value then error('partial acquire')end end}}
local g=Gate.new(sr)
assert(g.acquire()and visible and g.pending());local n=writes
assert(not g.acquire()and writes==n,'Never replace an outstanding lease')
assert(g.release()and not visible and not g.pending())
n=writes;assert(g.release()and writes==n,'Retired state is idle')
visible=true;n=writes;assert(not g.acquire()and writes==n,'Do not take a pre-existing native menu cursor')
visible=false;fail=true;assert(not g.acquire()and not visible and not g.pending(),'Restore after a partially applied setter')
fail=false;assert(g.acquire());unknown=true;assert(not g.release()and g.pending());n=reads
for _=1,100 do assert(not g.release())end;assert(reads==n,'Unknown cleanup must back off')
unknown=false;clock=clock+.3;assert(g.release()and not visible)
assert(g.acquire());esc=true;n=writes
assert(g.release()and visible and writes==n and not g.pending(),'ESC must transfer the visible cursor to native UI')
esc=false;visible=false
local service=dofile('freecam/engine_input.lua').new({Window=sr.Window,Keyboard=sr.Keyboard,Application=sr.Application,
 Gui={resolution=function()return 1920,1080 end},Mouse={axis_id=function()return 0 end,button_id=function()return 0 end,axis=function()return{x=0,y=0}end,button=function()return 0 end}},nil,nil,g)
local token=assert(service.acquire('dbf_freecam','menu'));assert(service.status().cursor_candidate and not service.status().threshold_candidate)
n=writes;local old=reads
for _=1,100 do assert(service.snapshot(token));assert(service.set_mode(token,'camera'))end
assert(writes==n and reads==old,'Settled samples/mode changes must not poll or reapply cursor state')
assert(service.release(token)and not visible)
print('Cursor handler: owned acquisition, exact restoration, native ESC handoff, partial rollback, cleanup backoff and zero steady-state reads/writes passed; gameplay suppression needs live test')

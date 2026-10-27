local Gate=dofile('freecam/engine_input_gate.lua')
local values={Keyboard=.5,Mouse=.4};local writes,reads=0,0;local fail,unknown
local sr={}
for _,name in ipairs({'Keyboard','Mouse'})do
 sr[name]={down_threshold=function()reads=reads+1;if unknown==name then error('read lost')end;return values[name]end,
  set_down_threshold=function(value)writes=writes+1;values[name]=value;if fail==name then error('partial setter')end end}
end
local gate=Gate.new(sr)
assert(gate.acquire()and values.Keyboard==1 and values.Mouse==1)
assert(not gate.acquire(),'An existing lease cannot be overwritten')
local n=writes;assert(gate.pending()and gate.available()and writes==n)
assert(gate.release()and values.Keyboard==.5 and values.Mouse==.4 and writes==n+2)
assert(gate.release()and writes==n+2,'Idle release must not write')
assert(gate.acquire());values.Keyboard=.7
assert(gate.release()and values.Keyboard==.7 and values.Mouse==.4,'Preserve foreign device changes')
values.Keyboard=.5;fail='Mouse'
assert(not gate.acquire()and gate.pending(),'A partial setter failure retains restoration ownership')
fail=nil;assert(gate.release()and values.Keyboard==.5 and values.Mouse==.4)
assert(gate.acquire());unknown='Mouse';n=writes
assert(not gate.release()and gate.pending()and writes==n,'Unknown read must not restore blindly')
unknown=nil;assert(gate.release())
values.Mouse=1;n=writes
assert(not gate.acquire()and not gate.pending()and values.Keyboard==.5 and values.Mouse==1,'Roll back without changing another owner')
values.Mouse=.4
-- Real engine service: only the native-refused fallback uses thresholds;
-- a retained cleanup token prevents a second owner after partial failure.
sr.Gui={resolution=function()return 1920,1080 end}
sr.Mouse.axis_id=function()return 0 end;sr.Mouse.button_id=function()return 0 end
sr.Mouse.axis=function()return{x=0,y=0}end;sr.Mouse.button=function()return 0 end
local Service=dofile('freecam/engine_input.lua')
local service=Service.new(sr,nil,nil,gate)
local token=assert(service.acquire('dbf_freecam','menu'))
assert(service.status().threshold_candidate and values.Keyboard==1)
local before=writes
for _=1,100 do assert(service.snapshot(token));assert(service.set_mode(token,'camera'))end
assert(writes==before,'Samples and mode changes must not reapply thresholds')
assert(service.release(token)and values.Keyboard==.5 and values.Mouse==.4)
fail='Mouse';local refused,why,cleanup=service.acquire('dbf_freecam','menu')
assert(not refused and cleanup and service.status().pending_restore)
assert(not service.acquire('other','menu'))
fail=nil;assert(service.release(cleanup)and service.status().owner==nil)
local unavailable=Gate.new({});local ok,active=unavailable.acquire()
assert(ok and not active and not unavailable.pending(),'Missing APIs must never claim isolation')
print('Engine threshold candidate: partial rollback, exact restore, foreign ownership, pending tokens and zero settled writes passed; gameplay unverified')

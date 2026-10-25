local M=dofile('freecam/steam_ai.lua');local now=0;local calls=0;local writes=0;local fail_restore=false
local c={mode='normal',pending=false,status='Normal'};local requested
function c.ready()return true end
function c.queue(mode)requested=mode;c.pending=true;return true end
function c.flush()
 if requested then c.mode=requested;requested=nil;c.pending=false end
 if c.mode~='normal'then writes=writes+1 end
 return not fail_restore,'cleanup refused'
end
function c.count()return fail_restore and 1 or 0 end
local ai=M.new(function()calls=calls+1;return c end,function()return now end,function()end)
for i=1,100 do ai.tick()end;assert(calls==0 and writes==0,'Idle AI instantiated native backend')
assert(ai.select(2));assert(calls==1 and writes==0 and ai.state().pending)
assert(ai.tick());assert(ai.state().mode=='passive'and writes==1)
assert(ai.select(3));ai.tick();assert(calls==1 and ai.state().mode=='dummy')
fail_restore=true;assert(not ai.dispose(),'Unconfirmed cleanup accepted')
fail_restore=false;assert(ai.dispose()and ai.state().mode=='normal')
local disabled=M.new(nil,function()return now end,function()end)
assert(not disabled.state().available and not disabled.select(2));assert(disabled.dispose())
local broken=M.new(function()error('unavailable')end,function()return now end,function()end)
assert(not broken.select(2)and not broken.state().available);assert(broken.dispose())
print('FFI AI opt-in: no idle factory, queued mode changes, non-FFI refusal and cleanup retry passed')

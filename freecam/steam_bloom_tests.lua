-- Native renderer acknowledgement is simulated; this is not visual/live proof.
local Policy=dofile('freecam/steam_runtime.lua').bloom_policy
local function pack(...)return{n=select('#',...),...}end
local function fixture()
 local f={time=0,value=false,reads=0,clocks=0,calls={},queue={}}
 local sentinel={native_error=true}
 local A={time_since_launch=function()f.clocks=f.clocks+1;return f.time end,
  render_setting=function(...)
   assert(select('#',...)==1 and(...)=='bloom_enabled');f.reads=f.reads+1
   if f.read_error then error(sentinel,0)end
   if f.read_nil then return nil end;return f.value
  end}
 local native=function(...)
  local args=pack(...);f.calls[#f.calls+1]=args
  if args[1]=='bloom_enabled'then
   assert(args.n==2 and(args[2]=='true'or args[2]=='false'))
   if not f.drop then f.queue[#f.queue+1]={at=f.time+.15,value=args[2]=='true'}end
   if f.fail_call==#f.calls then
    if f.throw then error(sentinel,0)end
    return false,nil,'refused',nil
   end
  elseif args[1]=='error'then error(sentinel,0)end
  return nil,false,nil,'result',nil
 end
 A.set_render_setting=native;f.A,f.native,f.sentinel=A,native,sentinel
 f.policy=assert(Policy({Application=A}))
 function f.step(dt)f.time=f.time+(dt or .1)
  for i=#f.queue,1,-1 do if f.queue[i].at<=f.time then f.value=f.queue[i].value;table.remove(f.queue,i)end end
  return f.policy.tick()
 end
 function f.settled()
  for _=1,30 do if not f.policy.waiting()then return end;f.step()end
  assert(not f.policy.waiting())
 end
 function f.idle()
  local reads,clocks,writes=f.reads,f.clocks,#f.calls
  for _=1,100 do f.policy.tick()end
  assert(f.reads==reads and f.clocks==clocks and #f.calls==writes,'Settled/blocked policies perform zero native work')
 end
 return f
end
assert(Policy({Application={}})==nil,'Missing APIs must remain gated without native reads')
do
 local f=fixture();f.idle();assert(f.policy.open(false)and f.reads==1 and #f.calls==0)
 f.idle();assert(f.policy.close(true)and f.reads==1 and f.clocks==0)
 assert(f.policy.open(true));f.settled();assert(f.value and #f.calls==1);f.idle()
 assert(not f.policy.close(true));f.settled();assert(not f.value and #f.calls==2 and f.policy.close(false))
 assert(f.A.set_render_setting==f.native);f.idle()
end
do
 local f=fixture();assert(f.policy.open(true));assert(f.policy.request(false)and f.policy.request(true)and f.policy.request(false))
 assert(#f.calls==1,'Coalesced requests cannot submit before the prior acknowledgement')
 f.settled();assert(#f.calls==2 and not f.value and f.policy.state=='active')
 assert(f.policy.request(true));f.settled();assert(f.value and #f.calls==3)
 assert(not f.policy.close(true));f.settled();assert(not f.value and #f.calls==4 and f.policy.close(false),
  'A later acknowledged ownership change permits its own single baseline restoration')
end
for _,mode in ipairs({'false','throw','timeout'})do for _,delayed in ipairs({false,true})do
 local f=fixture();assert(f.policy.open(true));f.settled();f.drop=not delayed
 if mode~='timeout'then f.fail_call,f.throw=2,mode=='throw'end
 local accepted=f.policy.request(false)
 if mode=='timeout'then assert(accepted);if delayed then f.settled()else f.step(2.1)end
 else assert(not accepted)end
 f.step(.2)
 if not delayed then
  assert(not f.policy.close(true)and f.policy.state=='blocked'and f.value==true and #f.calls==2,
   'An unapplied baseline request preserves last acknowledged ownership instead of yielding as foreign')
  f.idle();f.value=false;f.step(.2)
 end
 assert(f.policy.close(true)and not f.value and #f.calls==2,
  'Delayed baseline acknowledgement retires ownership without repeating a failed/timed-out baseline setter')
end end
for _,throw in ipairs({false,true})do
 local f=fixture();f.fail_call,f.throw=1,throw;assert(not f.policy.open(true)and f.policy.state=='blocked')
 assert(f.policy.failures.apply.n==(throw and 2 or 5))
 if throw then assert(f.policy.failures.apply[2]==f.sentinel)else assert(f.policy.failures.apply[2]==false)end
 f.idle();assert(not f.policy.close(false));f.step(.2)
 assert(not f.policy.close(true));f.settled();assert(not f.value and #f.calls==2 and f.policy.close(false))
 assert(f.policy.failures.apply,'Cleanup must retain the original submission failure')
end
for _,throw in ipairs({false,true})do
 local f=fixture();assert(f.policy.open(true));f.settled();f.fail_call,f.throw=2,throw;f.step(.2)
 assert(not f.policy.close(true)and f.policy.state=='blocked');f.idle()
 for _=1,100 do assert(not f.policy.close(false))end;assert(#f.calls==2)
 f.step(.2);assert(f.policy.close(true)and not f.value and #f.calls==2)
 assert(f.policy.failures.restore,'A partially applied restore failure remains inspectable')
end
do
 local f=fixture();f.drop=true;assert(f.policy.open(true));f.step(2.1)
 assert(f.policy.state=='blocked');f.idle();assert(not f.policy.close(true)and #f.calls==1)
 f.value=true;f.drop=false;f.step(.2);assert(not f.policy.close(true));f.settled()
 assert(not f.value and #f.calls==2 and f.policy.close(false))
end
do
 local f=fixture();assert(f.policy.open(true));f.settled()
 local results=pack(f.A.set_render_setting('unrelated',nil,false,nil))
 assert(results.n==5 and results[1]==nil and results[2]==false and results[5]==nil)
 assert(f.calls[2].n==4 and f.calls[2][3]==false and f.calls[2][4]==nil)
 local ok,why=pcall(f.A.set_render_setting,'error');assert(not ok and why==f.sentinel)
 -- A foreign write of the selected value is adopted as the restore value; the
 -- held selection needs no extra write, and close then restores nothing.
 f.A.set_render_setting('bloom_enabled','true');local writes=#f.calls;f.policy.tick()
 assert(f.policy.state=='active'and f.policy.close(true)and #f.calls==writes)
end
do
 local f=fixture();assert(f.policy.open(true));f.settled();f.A.set_render_setting=function()end
 f.policy.tick();assert(f.policy.state=='foreign'and f.policy.close(true)and #f.calls==1)
end
do
 local f=fixture();assert(f.policy.open(true));f.settled()
 local old=f.A.set_render_setting;local successor=function(...)return old(...)end
 f.A.set_render_setting=successor;f.policy.tick();assert(f.policy.state=='foreign'and f.policy.close(true))
 assert(f.policy.open(false)and f.policy.waiting());f.policy.tick()
 assert(f.policy.waiting(),'Retired observers in a successor chain must never classify a later owned write as foreign')
 f.settled();assert(not f.value and f.policy.state=='active')
 assert(not f.policy.close(true));f.settled();assert(f.value and f.policy.close(false))
 assert(f.A.set_render_setting==successor,'Restore the actual successor binding, preserving its inert retained observer')
end
do
 local f=fixture();assert(f.policy.open(true));f.settled();f.value=false;f.step(.2)
 assert(f.policy.close(true)and #f.calls==1,'Fresh native value changes must be preserved')
end
for _,throw in ipairs({false,true})do
 local f=fixture();assert(f.policy.open(true));f.settled();f.drop=true;f.fail_call,f.throw=2,throw
 pcall(f.A.set_render_setting,'bloom_enabled','false')
 assert(f.policy.state=='blocked'and not f.policy.close(true));f.idle()
 f.A.set_render_setting=f.native;assert(f.policy.close(true)and #f.calls==2)
end
print('Steam Bloom: entry-only baseline, coalesced serialized writes, bounded ack, idle, ownership, partial-failure cleanup and exact observer returns passed')

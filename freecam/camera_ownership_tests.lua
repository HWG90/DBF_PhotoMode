local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'camera_ownership.lua')
local function pack(...)return{n=select('#',...),...}end
local function public(events,label)
 events=events or{};label=label or'public'
 local state={acquire=0,release=0,priority_sets=0,input_sets=0}
 local api={api=1}
 function api.acquire(owner)
  state.acquire=state.acquire+1;state.owner=owner;events[#events+1]=label..' acquire'
  if state.throw_acquire then error('acquire exception')end
  if state.reject then return false,'provider busy'end
  if state.bad_token~=nil then return state.bad_token end
  local token={};state.token=token;return token
 end
 function api.release(token)
  state.release=state.release+1;events[#events+1]=label..' release'
  assert(token==state.token,'An opaque token crossed camera providers')
  if state.throw_release then error('release exception')end
  if state.pending then return false,'restoring camera'end
  if state.bad_release~=nil then return state.bad_release end
  state.token=nil;return true
 end
 function api.set_priority(reader)state.priority=reader;state.priority_sets=state.priority_sets+1 end
 function api.set_input_blocked(reader)state.input=reader;state.input_sets=state.input_sets+1 end
 return api,state
end
local function legacy(events)
 events=events or{}
 local state={made=0,refresh=0,acquire=0,release=0,dispose=0}
 local adapter={count=1,available=true,held=false}
 function adapter.refresh()state.refresh=state.refresh+1;return not state.unavailable,'legacy unavailable'end
 function adapter.acquire()state.acquire=state.acquire+1;adapter.held=true;events[#events+1]='legacy acquire';if state.reject then return false,'legacy acquire pending'end;return true end
 function adapter.release()
  state.release=state.release+1;events[#events+1]='legacy release'
  if state.pending then return false,'legacy cleanup pending'end
  adapter.held=false;return true
 end
 function adapter.dispose()
  state.dispose=state.dispose+1;events[#events+1]='legacy dispose';assert(not adapter.held)
  if state.dispose_pending then return false,'legacy dispose pending'end
  state.disposed=true;return true
 end
 function adapter.set_priority(fn)state.priority=fn end
 function adapter.set_input_blocked(fn)state.input=fn end
 local function make()state.made=state.made+1;return adapter end
 return make,adapter,state
end
local function forbidden()error('Cooperative path touched a private compatibility adapter')end

-- Public API startup uses only its advertised methods. No callback introspection,
-- private fallback construction, or package/module discovery is allowed here.
local api,s=public();local G=setmetatable({ActionCamCamera=api},{__index=function(_,name)error('Unexpected global lookup: '..name)end})
local owner=factory.new(G,function()end,forbidden)
local priority,blocked=false,false
owner.set_priority(function()return priority end);owner.set_input_blocked(function()return blocked end)
assert(owner.refresh()and owner.available and owner.count==1 and s.acquire==0)
assert(owner.refresh()and s.priority_sets==1 and s.input_sets==1,'Public callback registration must be idempotent')
assert(not s.priority()and not s.input());priority=true;blocked=true;assert(s.priority()and s.input())
owner.set_input_blocked(function()error('reader unavailable')end);assert(s.input(),'Unavailable input readers must refuse input')
owner.set_input_blocked(function()return false end)
assert(owner.acquire()and owner.held and s.acquire==1 and type(s.owner)=='table')
local token=s.token;assert(owner.acquire()and s.token==token and s.acquire==1)
-- Releasing player input for Cinema is independent of the camera token.
blocked=false;priority=false;assert(owner.refresh()and owner.held and s.token==token and s.release==0)
assert(not owner.dispose(),'An active camera cannot be disposed')
s.pending=true;assert(not owner.release()and owner.held and owner.releasing and s.token==token)
assert(not owner.refresh()and not owner.acquire()and s.acquire==1,'A pending release cannot grant another Photo session')
s.pending=false;assert(owner.release()and not owner.held and not owner.releasing and s.token==nil)
assert(owner.release()and s.release==2,'A completed release must be idempotent')
assert(owner.dispose()and not s.priority()and not s.input(),'Disposed callbacks must stop influencing ActionCam')

-- Empty scenes require no ActionCam, native helper, or legacy adapter.
local empty=factory.new({});assert(empty.refresh()and empty.count==0);assert(empty.acquire()and empty.held)
assert(empty.release()and not empty.held);assert(empty.dispose());assert(not empty.acquire())
local missing=factory.new({package={loaded={['mods/actioncam/actioncam']=true}}})
assert(not missing.acquire(),'An advertised old ActionCam needs a supported adapter')

-- An advertised but invalid API never falls back to private mutation.
for _,advertisement in ipairs({false,true,{api=2},{api=1},{api=1,acquire=function()end,release=function()end,set_priority=true}})do
 local bad=factory.new({ActionCamCamera=advertisement},nil,forbidden)
 assert(not bad.refresh()and not bad.acquire()and not bad.held)
end
for _,bad_token in ipairs({true,123,'not-an-opaque-token'})do
 local a,st=public();st.bad_token=bad_token;local bad=factory.new({ActionCamCamera=a},nil,forbidden)
 assert(not bad.acquire()and not bad.held and st.release==0,'Non-token acknowledgments must be rejected')
end
do
 local a,st=public();st.reject=true;local bad=factory.new({ActionCamCamera=a},nil,forbidden)
 assert(not bad.acquire()and not bad.held);st.reject=false;assert(bad.acquire());assert(bad.release())
 st.throw_acquire=true;assert(not bad.acquire()and not bad.held)
 a.available='ready';assert(not bad.refresh());a.available=false;a.reason='camera loading';assert(not bad.refresh()and bad.reason=='camera loading')
 a.available=true;st.throw_acquire=false;assert(bad.acquire());st.bad_release=1
 assert(not bad.release()and bad.held,'Only exact true acknowledges public release')
 st.bad_release=nil;st.throw_release=true;assert(not bad.release()and bad.held)
 st.throw_release=false;assert(bad.release())
end
do
 local a=public();a.set_priority=function()return false,'binding ownership refused'end
 local bad=factory.new({ActionCamCamera=a},nil,forbidden)
 assert(not bad.refresh()and bad.reason=='binding ownership refused')
end

-- The public provider can load after a harmless standalone camera lease.
do
 local env={};local broker=factory.new(env,nil,forbidden)
 -- No fallback is supplied until a real legacy integration is desired.
 broker=factory.new(env);assert(broker.acquire()and broker.held)
 local a,st=public();env.ActionCamCamera=a;assert(broker.refresh()and broker.held and st.acquire==1)
 assert(broker.release()and st.release==1)
end

-- Legacy first, public API later: acquire the public token before removing the
-- old camera gate, then retire every private compatibility hook.
do
 local events={};local make,old,ls=legacy(events);local env={};local broker=factory.new(env,nil,{new=make})
 assert(broker.refresh()and ls.made==1);assert(broker.acquire()and old.held)
 local a,st=public(events);env.ActionCamCamera=a;local refreshed=ls.refresh
 assert(broker.refresh()and broker.held and not old.held and ls.disposed)
 assert(table.concat(events,'|')=='legacy acquire|public acquire|legacy release|legacy dispose')
 assert(ls.refresh==refreshed,'Cooperative migration must not continue private discovery')
 assert(broker.refresh()and st.acquire==1 and ls.made==1)
 assert(broker.release()and st.release==1)
end
-- Idle migration retires the old adapter without acquiring a public token.
do
 local make,_,ls=legacy();local env={};local broker=factory.new(env,nil,make);assert(broker.refresh())
 local a,st=public();env.ActionCamCamera=a;assert(broker.refresh()and ls.disposed and st.acquire==0)
 assert(broker.acquire()and st.acquire==1);assert(broker.release())
end
-- Failed takeover preserves legacy ownership. A successful public acquire with
-- pending legacy cleanup retains both gates until cleanup can finish.
do
 local make,old,ls=legacy();local env={};local broker=factory.new(env,nil,make);assert(broker.acquire())
 local a,st=public();st.reject=true;env.ActionCamCamera=a
 assert(not broker.refresh()and broker.held and old.held and ls.release==0)
 st.reject=false;ls.pending=true;assert(not broker.refresh()and broker.held and old.held and st.token)
 local token=st.token;assert(not broker.release()and broker.held and st.release==0)
 ls.pending=false;assert(broker.release()and not broker.held and not old.held and st.token==nil and st.release==1)
 assert(token~=nil)
end
-- An invalid late advertisement cannot turn into a private fallback retry.
do
 local make,old,ls=legacy();local env={};local broker=factory.new(env,nil,make);assert(broker.acquire())
 local reads=ls.refresh;env.ActionCamCamera={api=999}
 assert(not broker.refresh()and broker.held and old.held and ls.refresh==reads)
 assert(broker.release()and not old.held and not broker.held and ls.disposed and not broker.available)
end
do
 local make,old,ls=legacy();ls.reject=true;local broker=factory.new({},nil,make)
 assert(not broker.acquire()and broker.held and old.held)
 assert(not broker.acquire(),'A failed legacy acquire cannot become acknowledged merely because it held a partial gate')
 assert(broker.release()and not broker.held and not old.held)
 ls.reject=false;assert(broker.acquire());ls.pending=true;assert(not broker.release()and broker.held)
 ls.pending=false;assert(broker.release());ls.dispose_pending=true;assert(not broker.dispose())
 ls.dispose_pending=false;assert(broker.dispose())
end
do
 local make,old,ls=legacy();local refused=true
 old.set_input_blocked=function()if refused then return false,'legacy input unavailable'end end
 local broker=factory.new({},nil,make)
 assert(not broker.refresh()and not broker.refresh()and ls.refresh==0,'A failed legacy callback registration must not become silently ready')
 refused=false;assert(broker.refresh()and ls.made==1 and ls.refresh==1);assert(broker.dispose())
end

-- Replacements, version changes and provider removal cannot receive another
-- provider's token. The original release function stays usable during cleanup.
for _,replacement in ipairs({'new','removed','version','method'})do
 local a,st=public();local env={ActionCamCamera=a};local broker=factory.new(env,nil,forbidden);assert(broker.acquire())
 local other,other_state=public(nil,'replacement')
 if replacement=='new'then env.ActionCamCamera=other
 elseif replacement=='removed'then env.ActionCamCamera=nil
 elseif replacement=='version'then a.api=2
 else a.release=function()error('Replacement release must not receive an old token')end end
 assert(not broker.refresh()and broker.held)
 -- Removing an API permits legacy discovery only after the old token is safe.
 if replacement=='removed'then env.package={loaded={}}end
 assert(broker.release()and not broker.held and st.release==1 and other_state.release==0)
 if replacement=='new'then assert(not st.priority()and not st.input());assert(broker.acquire());assert(broker.release())end
end
-- A provider that changes during its own acquire is not allowed to start a
-- Photo session; its already-returned token still receives orderly cleanup.
do
 local a,st=public();local other,other_state=public();local env={ActionCamCamera=a}
 local original_acquire=a.acquire
 a.acquire=function(owner)local token=original_acquire(owner);env.ActionCamCamera=other;return token end
 local broker=factory.new(env,nil,forbidden)
 assert(not broker.acquire()and broker.held and broker.acquire_failed and other_state.acquire==0)
 assert(not broker.acquire());assert(broker.release()and st.release==1 and not broker.held)
 assert(broker.acquire()and other_state.acquire==1);assert(broker.release())
end

-- Global callback chaining and error identity survive the ownership layer.
do
 local a,st=public();local env={ActionCamCamera=a};local broker=factory.new(env,nil,forbidden)
 local calls=0;local wrapped=broker.wrap_update(function(...)calls=calls+1;return ... end)
 local values=pack(wrapped(1,nil,3,nil));assert(calls==1 and values.n==4 and values[1]==1 and values[2]==nil and values[3]==3)
 assert(broker.acquire());local cleanup=0;local problem={}
 wrapped=broker.wrap_update(function()error(problem)end,function()cleanup=cleanup+1;assert(broker.release())end)
 local ok,why=pcall(wrapped);assert(not ok and why==problem and cleanup==1 and not broker.held)
 assert(broker.dispose())
 local disabled=broker.wrap_update(function(...)calls=calls+1;return ... end,function()error('Disposed ownership must not notify')end)
 local output=pack(disabled(nil,false,'game'));assert(output.n==3 and output[1]==nil and output[2]==false and output[3]=='game'and calls==2)
end
print('Camera ownership: public API isolation, opaque tokens, both load orders, legacy migration, pending cleanup, replacement, disposal, Cinema lease retention and game callback preservation passed')

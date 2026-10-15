-- Public camera ownership first; exact-version private adapters are a legacy
-- fallback only. Cooperative providers expose ActionCamCamera.api == 1,
-- acquire(owner) -> opaque table/userdata token or false, reason, and
-- release(token) -> exact true or false, reason. A failed acquire must not
-- retain ownership without returning a token. Providers retain release-token
-- validity across scene changes/reload until their cleanup is acknowledged.
local M={}
function M.new(G,log,legacy_factory)
 G=G or _G;log=log or function()end
 local self={available=true,reason=nil,held=false,count=0}
 local owner={name='War Journalist',camera_ownership_api=1}
 local legacy,selected,lease;local legacy_configured=false;local priority,input_reader;local announced
 local function status(ok,why,count)
  self.available,self.reason=ok,why
  if count~=nil then self.count=count end
  if why and why~=announced then announced=why;pcall(log,why)end
  return ok,why
 end
 local function reader(fn)
  if self.disabled or not fn then return false end
  local ok,value=pcall(fn);return not ok or type(value)~='boolean'or value
 end
 local function priority_callback()return reader(priority)end
 local function input_callback()return reader(input_reader)end
 local function call(fn,...)
  local ok,value,why=pcall(fn,...)
  if not ok then return false,'Camera provider raised an error: '..tostring(value)end
  return true,value,why
 end
 local function inspect()
  local api=rawget(G,'ActionCamCamera')
  if api==nil then return nil end
  if type(api)~='table'or rawget(api,'api')~=1 then return false,'Unsupported ActionCam camera ownership API'end
  local acquire,release=rawget(api,'acquire'),rawget(api,'release')
  if type(acquire)~='function'or type(release)~='function'then return false,'Incomplete ActionCam camera ownership API'end
  for _,name in ipairs({'set_priority','set_input_blocked'})do
   local value=rawget(api,name)
   if value~=nil and type(value)~='function'then return false,'Invalid ActionCam camera ownership callback: '..name end
  end
  return {api=api,acquire=acquire,release=release}
 end
 local function same(a,b)return a and b and a.api==b.api and a.acquire==b.acquire and a.release==b.release end
 local function current(record)
  local advertised,why=inspect()
  if advertised==false then return false,why end
  if not same(record,advertised)then return false,'ActionCam camera provider changed during handoff'end
  return true
 end
 local function ready(record)
  local available=rawget(record.api,'available')
  if available~=nil and type(available)~='boolean'then return false,'Invalid ActionCam camera readiness acknowledgment'end
  if available==false then return false,tostring(rawget(record.api,'reason')or'ActionCam camera is not ready')end
  return true
 end
 local function configure(record)
  if not record.priority_callback then
   local function live()return same(record,selected)or lease and same(record,lease.provider)end
   record.priority_callback=function()return live()and priority_callback()or false end
   record.input_callback=function()return live()and input_callback()or false end
  end
  for _,setting in ipairs({{'set_priority',record.priority_callback},{'set_input_blocked',record.input_callback}})do
   local setter=rawget(record.api,setting[1]);local key='configured_'..setting[1]
   if setter and record[key]~=setter then
    local called,ok,why=call(setter,setting[2])
    if not called or ok==false then return false,called and(why or'ActionCam rejected camera input coordination')or ok end
    record[key]=setter
   end
  end
  return true
 end
 local function legacy_count()
  return legacy and type(legacy.count)=='number'and legacy.count or 0
 end
 local function legacy_held()return legacy and legacy.held==true end
 local function get_legacy()
  if not legacy then
   if not legacy_factory then
    local package_table=rawget(G,'package');local loaded=type(package_table)=='table'and rawget(package_table,'loaded')
    if type(loaded)=='table'and loaded['mods/actioncam/actioncam']then return false,'ActionCam has no supported camera ownership provider'end
    return nil
   end
   local factory=type(legacy_factory)=='table'and legacy_factory.new or legacy_factory
   if type(factory)~='function'then return false,'Legacy camera adapter factory is unavailable'end
   local called,value=call(factory,G,log)
   if not called then return false,value end
   if type(value)~='table'then return false,'Legacy camera adapter did not return an owner'end
   for _,name in ipairs({'refresh','acquire','release','dispose'})do
    if type(value[name])~='function'then return false,'Legacy camera adapter is missing '..name end
   end
   legacy=value
  end
  if not legacy_configured then
   for _,setting in ipairs({{'set_priority',priority_callback},{'set_input_blocked',input_callback}})do
    if type(legacy[setting[1]])=='function'then
     local called,ok,why=call(legacy[setting[1]],setting[2])
     if not called or ok==false then return false,called and(why or'Legacy camera input coordination was refused')or ok end
    end
   end
   legacy_configured=true
  end
  return legacy
 end
 local function release_legacy()
  if not legacy_held()then return true end
  local called,ok,why=call(legacy.release)
  if not called or ok~=true or legacy_held()then return false,called and(why or'Legacy camera cleanup has not acknowledged release')or ok end
  return true
 end
 local function dispose_legacy()
  if not legacy then return true end
  if legacy_held()then return false,'Legacy camera ownership must finish releasing'end
  local called,ok,why=call(legacy.dispose)
  if not called or ok~=true then return false,called and(why or'Legacy camera adapter cleanup is pending')or ok end
  legacy=nil;legacy_configured=false;return true
 end
 local function acquire_public(record)
  local called,token,why=call(record.acquire,owner)
  if not called then return false,token end
  if token==false or token==nil then return false,why or'ActionCam did not grant camera ownership'end
  if type(token)~='table'and type(token)~='userdata'then return false,'ActionCam must return an opaque table or userdata lease token'end
  lease={provider=record,token=token};self.held=true
  return true
 end
 function self.set_priority(fn)assert(fn==nil or type(fn)=='function');priority=fn end
 function self.set_input_blocked(fn)assert(fn==nil or type(fn)=='function');input_reader=fn end
 function self.refresh()
  if self.disabled then return true end
  if self.releasing or self.acquire_failed then return status(false,self.reason or'Previous camera handoff cleanup is pending')end
  local advertised,why=inspect()
  if advertised==false then return status(false,why)end
  if lease and not same(lease.provider,advertised)then return status(false,'ActionCam camera provider changed; release the current camera lease first')end
  if advertised then
   if not same(selected,advertised)then selected=advertised end
   local configured,problem=configure(selected)
   if not configured then return status(false,problem,1)end
   local unchanged,problem=current(selected)
   if not unchanged then return status(false,problem,1)end
   local available,reason=ready(selected)
   if not available then return status(false,reason,1)end
   if self.held and not lease then
    -- A provider arriving during a legacy/standalone lease must acknowledge
    -- ownership before the previous gate is released. Cinema keeps this token
    -- even when the caller separately releases player input.
    local acquired,reason=acquire_public(selected)
    if not acquired then return status(false,reason,1)end
    local unchanged,reason=current(selected)
    if not unchanged then return status(false,reason,1)end
   end
   local released,reason=release_legacy()
   if not released then return status(false,reason,1)end
   local disposed,problem=dispose_legacy()
   if not disposed then return status(false,problem,1)end
   return status(true,nil,1)
  end
  selected=nil
  local adapter,problem=get_legacy()
  if adapter==false then return status(false,problem)end
  if adapter then
   local called,ok,reason=call(adapter.refresh)
   if not called or ok~=true then return status(false,called and(reason or'Legacy camera owner is unavailable')or ok,legacy_count())end
  end
  return status(true,nil,legacy_count())
 end
 function self.acquire()
  local ok,why=self.refresh();if not ok then return false,why end
  if self.disabled then return false,'Camera ownership service has stopped'end
  if self.held then return true end
  if selected then
   local ok,why=acquire_public(selected)
   if not ok then return status(false,why,1)end
   local unchanged,why=current(selected)
   if not unchanged then self.acquire_failed=true;return status(false,why,1)end
   return true
  end
  if legacy then
   local called,ok,why=call(legacy.acquire)
   self.held=legacy_held()
   if not called or ok~=true or not self.held then self.acquire_failed=self.held;return status(false,called and(why or'Legacy camera ownership was not acknowledged')or ok,legacy_count())end
  else self.held=true end
  return true
 end
 function self.release()
  if not self.held and not lease and not legacy_held()then return true end
  self.releasing=true
  local released,why=release_legacy()
  if not released then self.held=true;return status(false,why)end
  if lease then
   -- Use the exact original provider and token even if the advertised API was
   -- removed, replaced, or hot-reloaded. Never pass an old token to a new owner.
   local called,ok,why=call(lease.provider.release,lease.token)
   if not called or ok~=true then self.held=true;return status(false,called and(why or'ActionCam camera cleanup is pending')or ok)end
   lease=nil
  end
  self.held=false;self.releasing=false;self.acquire_failed=nil
  local advertised=rawget(G,'ActionCamCamera')
  if advertised~=nil then
   local disposed,why=dispose_legacy()
   if not disposed then return status(false,why)end
  end
  -- Readiness of the next provider is separate from acknowledgment that the
  -- previous one released. A bad replacement cannot strand an old camera lease.
  self.refresh()
  return true
 end
 function self.dispose()
  if self.held or lease or legacy_held()then return false,'Photo camera cleanup must complete before disposing camera ownership'end
  local disposed,why=dispose_legacy();if not disposed then return status(false,why)end
  self.disabled=true;selected=nil;self.count=0
  self.available,self.reason=true,nil
  return true
 end
 function self.wrap_update(previous,on_conflict)
  assert(type(previous)=='function','Game update callback unavailable')
  local function pack(...)return{n=select('#',...),...}end
  local function notify(why)
   if not on_conflict then return end
   local ok,problem=pcall(on_conflict,why)
   if not ok then pcall(log,'Photo camera cleanup is pending: '..tostring(problem))end
  end
  return function(...)
   if self.disabled then return previous(...)end
   local ok,why=self.refresh();if not ok then notify(why)end
   local result=pack(pcall(previous,...))
   if not result[1]then notify(result[2]);error(result[2],0)end
   return unpack(result,2,result.n)
  end
 end
 return self
end
return M

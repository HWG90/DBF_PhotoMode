-- Private Lua-only development reload. Disabled unless explicitly armed at startup.
-- The BML wrapper and input driver remain resident. Never reload the archive itself.
local M={}
local LIMIT=8*1024*1024
local function read(path,limit)
 local f=io.open(path,'rb');if not f then return end
 local data=f:read(limit+1);f:close();assert(not data or #data<=limit,'Reload file exceeds budget')
 return data
end
function M.enabled(dir)return read(dir..'/wj-dev-reload.enabled',64)=='wjl-dev-reload-v1\n'end
function M.bindings(api)
 if not api then return end
 local registered={};local proxy=setmetatable({},{__index=api})
 function proxy.register_binding(id,...)
  if registered[id]then return true end
  local ok,why=api.register_binding(id,...);if ok then registered[id]=true end;return ok,why
 end
 return proxy
end
-- Length framing avoids executing a manifest and preserves exact module bytes.
function M.parse(data)
 assert(type(data)=='string'and #data<=LIMIT,'Invalid reload payload')
 local pos=1
 local function line()
  local finish=data:find('\n',pos,true);assert(finish and finish-pos<256,'Invalid reload header')
  local s=data:sub(pos,finish-1);pos=finish+1;return s
 end
 assert(line()=='WJL-LUA-1','Reload protocol mismatch')
 local count=tonumber(line());assert(count and count%1==0 and count>=1 and count<=128,'Reload module budget')
 local rows,paths={},{}
 for i=1,count do
  local path=line()
  assert(path=='main.lua'or(path:match('^src/[a-zA-Z0-9_/-]+%.lua$')and not path:find('//',1,true)),'Invalid module path')
  assert(not paths[path],'Duplicate reload module');paths[path]=true
  local size=tonumber(line());assert(size and size%1==0 and size>0 and size<=LIMIT and pos+size-1<=#data,'Invalid module length')
  rows[i]={path=path,source=data:sub(pos,pos+size-1)};pos=pos+size
 end
 assert(paths['main.lua']and pos==#data+1,'Incomplete reload graph');return rows
end
function M.graph(rows,base)
 local chunks={};for _,r in ipairs(rows)do chunks[r.path]=assert(r.chunk,'Module not compiled')end
 local mod={};for k,v in pairs(base)do if k~='require'then mod[k]=v end end
 local scope=setmetatable({mod=mod},{__index=_G});local cache,loading={},{}
 function mod.require(path,...)
  if cache[path]~=nil then return cache[path]end
  assert(not loading[path],'Circular module import: '..path)
  local chunk=assert(chunks[path],'Module missing from reload: '..path);setfenv(chunk,scope)
  loading[path]=true;local ok,value=pcall(chunk,...);loading[path]=nil
  if not ok then error(value,2)end
  if value==nil then value=true end;cache[path]=value;chunks[path]=nil;return value
 end
 local entry=mod.require('main.lua')
 assert(type(entry)=='table'and entry.live_lua_api==1,'Reload entry contract')
 for _,name in ipairs({'on_enable','on_update','on_disable','on_cleanup_poll'})do assert(type(entry[name])=='function','Reload entry missing '..name)end
 return entry
end
function M.new(mod,current,clock,measure,files,options)
 files=files or{read=read,remove=os.remove}
 options=options or{};local directory=options.directory or mod.config_dir
 local self={};local state='idle';local next_check=0;local last;local rows,index,token,deadline
 -- Never replay an old request merely because the game restarted.
 do local ok,value=pcall(files.read,directory..'/wj-dev-reload.request',96);if ok then last=value end end
 local peak=0;local cleanup_reason
 local function log(s)mod.log('Dev reload: '..s)end
 local function failed(why)
  log('rejected '..tostring(token)..': '..tostring(why)..'; current runtime unchanged')
  rows=nil;state='idle'
 end
 function self.tick()
  local start=measure();local now=clock()
  if state=='idle'then
   if now<next_check then return false end
   next_check=now+1 -- No BML file notification API; one tiny request read/second, opt-in only.
   local ok,value=pcall(files.read,directory..'/wj-dev-reload.request',96)
   if not ok then log('request read failed: '..tostring(value));return false end
   if not value or value==last then return false end
   last=value;token=value:match('^([a-zA-Z0-9_-]+)\n$')
   if not token then log('invalid request token');return false end
   local loaded,result=pcall(function()
    local parsed=M.parse(assert(files.read(directory..'/wj-dev-'..token..'.lua-pack',LIMIT),'Reload payload absent'))
    local present={};for _,row in ipairs(parsed)do present[row.path]=row.source end
    for path,source in pairs(options.pinned or{})do assert(present[path]==source,'Resident module changed; restart required: '..path)end
    return parsed
   end)
   if not loaded then failed(result);return false end
   rows=result;index=1;peak=0;state='compile';log('preparing '..token)
  elseif state=='compile'then
   -- Bound compile work between frames; a single compiler call cannot be preempted.
   local n=0
   while index<=#rows and n<4 and measure()-start<.002 do
    local row=rows[index];local chunk,why=loadstring(row.source,'@wj-dev/'..token..'/'..row.path)
    if not chunk then failed(why);return false end
    row.chunk=chunk;row.source=nil;index=index+1;n=n+1
   end
   if index>#rows then state='retire';deadline=now+10;log('compiled '..token..'; releasing Photo Mode')end
  elseif state=='retire'then
   local ok,done,why=pcall(current.on_cleanup_poll)
   if ok and done==true then
    local built,candidate=pcall(M.graph,rows,mod);rows=nil
    if not built then state='halted';log('entry failed after cleanup: '..tostring(candidate)..'; restart required');return true end
    current=candidate
    local enabled,reason=pcall(current.on_enable)
    if enabled then state='idle';peak=math.max(peak,measure()-start);log('loaded '..token..'; reopen Photo Mode; max_reload_step_ms='..string.format('%.3f',peak*1000))
    else state='failed-cleanup';deadline=now+10;cleanup_reason=tostring(reason);log('start failed: '..cleanup_reason)end
   elseif now>=deadline then state='halted';rows=nil;log('cleanup unconfirmed: '..tostring(ok and why or done)..'; restart required')end
  elseif state=='failed-cleanup'then
   local ok,done=pcall(current.on_cleanup_poll)
   if (ok and done==true)or now>=deadline then state='halted';log('failed generation retired='..tostring(ok and done==true)..'; restart required')end
  end
  peak=math.max(peak,measure()-start)
  return state=='retire'or state=='failed-cleanup'or state=='halted'
 end
 function self.entry()return current end
 function self.status()return state,peak end
 return self
end
return M

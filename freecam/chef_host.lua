-- Chef Shared Loader host bits for the 1.3.3 runtime. Plain Lua 5.1 in Chef's sandbox.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end

-- Files. Chef has no os.rename or os.remove, and the stores write a .tmp then rename it.
-- Here the .tmp stays in memory and the rename writes the file directly.
local STAGED={tmp=true,bak=true,['replace-backup']=true}
function M.files(open)
 assert(type(open)=='function','io.open required')
 local staged={};local fs={}
 local function key(path)return(tostring(path):gsub('\\','/'):lower())end
 local function temporary(path)local ext=tostring(path):match('%.([%w-]+)$');return ext~=nil and STAGED[ext:lower()]==true end
 function fs.open(path,mode)
  mode=mode or'r'
  if temporary(path)then
   if mode:find('[wa]')then
    local parts={}
    if mode:find('a')and staged[key(path)]then parts[1]=staged[key(path)]end
    local handle={}
    function handle.write(_,...)for i=1,select('#',...)do parts[#parts+1]=tostring((select(i,...)))end;return handle end
    function handle.close()staged[key(path)]=table.concat(parts);return true end
    function handle.flush()return true end
    function handle.setvbuf()return true end
    return handle
   end
   local data=staged[key(path)];if data==nil then return nil,'No such file'end
   local at=0;local handle={}
   function handle.read(_,count)
    if at>=#data then return nil end
    if count=='*a'then local part=data:sub(at+1);at=#data;return part end
    count=tonumber(count)or#data;local part=data:sub(at+1,at+count);at=at+#part;return part
   end
   function handle.seek(_,whence,offset)
    offset=offset or 0
    if whence=='end'then at=#data+offset elseif whence=='set'then at=offset else at=at+offset end
    return at
   end
   function handle.close()return true end
   return handle
  end
  return open(path,mode)
 end
 function fs.remove(path)staged[key(path)]=nil;return true end
 function fs.rename(from,to)
  local data=staged[key(from)]
  if data==nil then return true end
  local f,why=open(to,'wb');if not f then return nil,why end
  local wrote,err=f:write(data);local closed,close_err=f:close()
  staged[key(from)]=nil
  if not wrote or not closed then return nil,tostring(err or close_err or'Write failed: '..tostring(to))end
  return true
 end
 fs.replace=fs.rename
 function fs.staged()local n=0;for _ in pairs(staged)do n=n+1 end;return n end
 return fs
end
-- io and os with the file calls above swapped in.
function M.scope(io,os,fs)
 local i=setmetatable({open=fs.open},{__index=io})
 local o=setmetatable({rename=fs.rename,remove=fs.remove},{__index=os})
 return i,o
end

-- Screenshots through chef.capture. The loader names and writes the DDS; saved_name says what it wrote.
function M.capture(chef,folder)
 if type(chef)~='table'or type(chef.capture)~='function'or type(folder)~='string'or folder==''then return nil end
 folder=folder:gsub('[/\\]+$','')
 local self={version=1,output_directory=folder,extension='dds',
  capabilities={async=true,game_window=false,format='dds',color_space='game',max_jobs=1}}
 local issued,current,count,names=nil,nil,0,{}
 local function record()
  return{job_token=current.job_token,output_token=current.output_token,output_path=current.output_path,state=current.state,reason=current.reason}
 end
 function self.new_job_token()count=count+1;issued='chef-shot:'..count;return issued end
 function self.request(intent)
  if type(intent)~='table'or not issued or intent.job_token~=issued then return nil,'Latest unused screenshot token required'end
  if type(intent.output_token)~='string'or intent.output_path~=folder..'/'..intent.output_token then return nil,'Screenshot output identity differs'end
  current={job_token=issued,output_token=intent.output_token,output_path=intent.output_path};issued=nil
  local called,name,why=pcall(chef.capture)
  if not called then current.state,current.reason='failed',tostring(name)
  elseif type(name)~='string'or name==''then current.state,current.reason='failed',tostring(why or'Chef Shared Loader saved no picture')
  else current.state='succeeded';names[current.output_path]=name end
  return record()
 end
 function self.status(job,output_token)
  assert(current and current.job_token==job and current.output_token==output_token,'Screenshot job identity differs')
  return record()
 end
 function self.cancel(job,output_token)return true,self.status(job,output_token)end
 function self.saved_name(path)local name=names[path];return name and(folder..'/'..name)or path end
 return self
end

-- Depth through chef.capture('depth'), Chef 1.4.2 on. The loader writes linear_depth as a DDS over a
-- few frames; the caller waits until the file is whole. `last` is the newest file asked for, so the
-- scene check can prove the format from it without asking again. Older loaders would save a screenshot.
local function at_least(version,major,minor,patch)
 local a,b,c=tostring(version):match('^(%d+)%.(%d+)%.?(%d*)')
 if not a then return false end
 a,b,c=tonumber(a),tonumber(b),tonumber(c)or 0
 if a~=major then return a>major end
 if b~=minor then return b>minor end
 return c>=patch
end
function M.depth(chef,folder)
 if type(chef)~='table'or type(chef.capture)~='function'or type(folder)~='string'or folder==''then return nil end
 if not at_least(chef.loader_version,1,4,2)then return nil end
 folder=folder:gsub('[/\\]+$','')
 local self={async=true,wait=5}
 function self.request()
  local called,name,why=pcall(chef.capture,'depth')
  if not called then return nil,tostring(name)end
  if type(name)~='string'or name==''then return nil,tostring(why or'Chef Shared Loader saved no depth picture')end
  self.last=folder..'/'..name
  return self.last
 end
 return self
end

-- Input. The loader holds the mouse while Photo Mode owns it, so the aim stays put, and
-- chef.mouse_delta gives the movement. Nothing gets through while the loader's own menu is open.
function M.input(chef,sr,log,engine_input)
 local Mouse=sr.Mouse
 local held,mouse_axis,reason=false,nil,nil
 local hold=type(chef.hold_mouse)=='function'and type(chef.mouse_delta)=='function'
 local function note(text)if text~=reason then reason=text;if log then log('Chef input: '..text)end end end
 local function menu_open()
  if type(chef.menu_open)~='function'then return false end
  local ok,open=pcall(chef.menu_open);return ok and open==true
 end
 local proxy=setmetatable({},{__index=Mouse})
 local function axis_of(name)
  for _,field in ipairs({'axis_index','axis_id'})do
   local f=Mouse[field]
   if type(f)=='function'then local ok,id=pcall(f,name);if ok and type(id)=='number'then return id end end
  end
 end
 function proxy.axis(id)
  mouse_axis=mouse_axis or axis_of('mouse')
  if id==mouse_axis and(held or menu_open())then
   local dx,dy=0,0
   if held and not menu_open()then
    local ok,x,y=pcall(chef.mouse_delta)
    if ok and finite(x)and finite(y)then dx,dy=x,y end
   end
   return{x=dx,y=dy,z=0}
  end
  return Mouse.axis(id)
 end
 local host_sr=setmetatable({Mouse=proxy},{__index=sr})
 local service=engine_input.new(host_sr,log)
 local acquire,release,snapshot=service.acquire,service.release,service.snapshot
 local function let_go()
  if not held then return end
  held=false
  local ok,why=pcall(chef.hold_mouse,false)
  if not ok then note('mouse hold release failed: '..tostring(why))end
 end
 function service.acquire(...)
  local token,why,pending=acquire(...)
  if token and hold and not held then
   local called,ok,refusal=pcall(chef.hold_mouse,true)
   if called and ok==true then held=true;note('mouse held for Photo Mode')
   else note('mouse hold unavailable, the game camera may turn too: '..tostring(called and refusal or ok))end
  elseif token and not hold then note('this loader has no mouse hold; the game camera may turn too')end
  return token,why,pending
 end
 function service.release(token)
  local done,why=release(token)
  if done then let_go()end
  return done,why
 end
 function service.snapshot(token)
  local sample,why=snapshot(token)
  if sample and menu_open()then sample.buttons,sample.wheel,sample.dx,sample.dy=0,0,0,0 end
  return sample,why
 end
 function service.held()return held end
 -- Let go when the addon stops.
 function service.dispose()let_go()end
 return service
end

-- Drawing. Chef never calls the mod's global render, so addon.render() calls whatever Photo Mode put there.
function M.render(G,log)
 local base=rawget(G,'render')
 if type(base)~='function'then base=function()end;rawset(G,'render',base)end
 local told=false
 return function()
  local current=rawget(G,'render')
  if current==base or type(current)~='function'then return end
  if not told then told=true;if log then log("Chef render: Photo Mode draws through the loader's render hook")end end
  return current()
 end
end
return M

-- Scope camera ownership to verified original ActionCam Lua closures. Engine
-- namespaces, OS hooks and other mods' input readers are never replaced.
local signatures=__ACTIONCAM_SIGNATURES__
local expected={}
for version,record in pairs(signatures.supported or {[signatures.runtime_version]=signatures})do
 expected[version]={}
 for name,hex in pairs(record.closures)do
  expected[version][name]=hex:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end)
 end
end
local M={}
function M.new(G,log)
 G=G or _G;log=log or function()end
 local dbg=G.debug or debug
 local self={held=false,available=true,reason=nil,count=0}
 local records={};local roots;local priority;local input_reader;local announced
 local chain_names={previous=true,previous_update=true,original_update=true,prior=true,original=true,wrapped=true,callback=true,fn=true,base=true}
 local function up(fn,wanted)
  if type(fn)~='function'or not dbg or type(dbg.getupvalue)~='function'then return end
  for index=1,120 do
   local ok,name,value=pcall(dbg.getupvalue,fn,index)
   if not ok or not name then return end
   if name==wanted then return value,index end
  end
 end
 local function put(fn,name,value)
  local _,index=up(fn,name);assert(index,'ActionCam closure changed: '..name)
  assert(dbg.setupvalue(fn,index,value)==name,'ActionCam closure assignment failed: '..name)
 end
 local function same(fn,name,version)
  if type(fn)~='function'then return false end
  local ok,bytes=pcall(string.dump,fn,true)
  return ok and expected[version] and bytes==expected[version][name]
 end
 local function status(ok,why)
  self.available,self.reason=ok,why
  local message=ok and(self.count>0 and'ActionCam compatibility ready: gameplay camera yields only during Photo Mode'or nil)or why
  if message and message~=announced then announced=message;log(message)end
  return ok,why
 end
 local function original_source(fn)
  if not dbg or type(dbg.getinfo)~='function'then return false end
  local ok,info=pcall(dbg.getinfo,fn,'S');local source=ok and info and info.source or''
  source=source:lower():gsub('\\','/')
  return source:find('mods/actioncam/actioncam',1,true)~=nil
 end
 local function verify(fn)
  local step=up(fn,'step');local cfg=up(step,'CFG')
  if type(cfg)~='table'or cfg.LOG_NAME~='ActionCam.log'then return nil end
  local old=records[fn]
  if old then
   if step~=old.step_gate or up(old.hook,'apply')~=old.apply_gate or up(old.step,'bindings_step')~=old.binding_gate then
    return false,'ActionCam compatibility adapter was replaced; restart before enabling Photo Mode'
   end
   return old
  end
  local hook=up(step,'hook_render');local apply=up(hook,'apply');local bindings=up(step,'bindings_step')
  local restore=up(apply,'restore_fov');local drop=up(apply,'drop_all')
  local functions={update=fn,step=step,hook_render=hook,apply=apply,bindings_step=bindings,restore_fov=restore,drop_all=drop}
  if not expected[cfg.VERSION] then return false,'Unsupported ActionCam version; Photo Mode cannot safely share this camera'end
  for name,value in pairs(functions)do if not same(value,name,cfg.VERSION)then return false,'Unsupported ActionCam camera hooks; Photo Mode left its camera untouched'end end
  local photo=up(bindings,'PHOTO');local binds=up(bindings,'PHOTO_BINDS')
  if type(photo)~='table'or type(photo.input)~='table'or type(photo.was)~='table'or type(binds)~='table' then
   return false,'ActionCam binding ownership cannot be verified'
  end
  return {update=fn,step=step,hook=hook,apply=apply,bindings=bindings,restore=restore,drop=drop,photo=photo,binds=binds}
 end
 local function clear(record)
  -- Release First Person head/near ownership and FOV before Photo takes over.
  -- The original helpers retain settings, profiles and dead-body exclusions.
  local target=up(record.apply,'target')
  if target then
   local alive=up(record.apply,'world_alive');local sr=up(record.apply,'sr')
   local ok,live=pcall(alive,target.world)
   local unit_ok,unit_live=false,false
   if ok and live and sr and sr.Unit and type(sr.Unit.alive)=='function'then unit_ok,unit_live=pcall(sr.Unit.alive,target.unit)end
   if not(ok and live and unit_ok and unit_live)then put(record.apply,'target',nil)end
  end
  record.restore()
  record.drop('War Journalist camera handoff')
 end
 local function priority_down()
  if not priority then return false end
  local ok,pressed=pcall(priority);return not ok or pressed==true
 end
 local function input_blocked()
  if not input_reader then return false end
  local ok,blocked=pcall(input_reader)
  return not ok or type(blocked)~='boolean'or blocked
 end
 local function sync_edges(record)
  local env=getfenv(record.bindings);local menu=rawget(env._G or env,'ModBindingsMenu')
  local held=false
  for _,binding in ipairs(record.filtered)do
   local down=false
   if binding.ok and menu and type(menu.is_down)=='function'then local ok,value=pcall(menu.is_down,binding.id);down=ok and value==true end
   record.photo.input[binding.key]=down;record.photo.was[binding.key]=down
   held=held or down
  end
  return held
 end
 local function install(record)
  if records[record.update]then return end
  record.filtered={}
  for _,binding in ipairs(record.binds)do
   if not(type(binding.id)=='string'and binding.id:match('^actioncam%.photo_'))then record.filtered[#record.filtered+1]=binding end
  end
  record.binding_gate=function(...)
   if self.held or priority_down()or input_blocked()then sync_edges(record);record.drain=true;return end
   if record.drain then record.drain=sync_edges(record);return end
   return record.bindings(...)
  end
  record.step_gate=function(...)
   if self.held then return end
   return record.step(...)
  end
  record.apply_gate=function(...)
   if self.held or input_blocked()then return end
   return record.apply(...)
  end
  -- All contracts are checked first; rollback only our assignments if one fails.
  local ok,why=pcall(function()
   put(record.bindings,'PHOTO_BINDS',record.filtered)
   put(record.step,'bindings_step',record.binding_gate)
   put(record.hook,'apply',record.apply_gate)
   put(record.update,'step',record.step_gate)
  end)
  if not ok then
   pcall(put,record.bindings,'PHOTO_BINDS',record.binds)
   pcall(put,record.step,'bindings_step',record.bindings)
   pcall(put,record.hook,'apply',record.apply)
   pcall(put,record.update,'step',record.step)
   error(why)
  end
  records[record.update]=record
  if record.photo.active then clear(record)end
  -- Late loads must yield before their first render, even when Photo already owns it.
  if self.held then clear(record);record.drain=true end
 end
 function self.refresh()
  if self.disabled then return true end
  if not dbg or type(dbg.getupvalue)~='function'or type(dbg.setupvalue)~='function'then
   local loaded=G.package and G.package.loaded and G.package.loaded['mods/actioncam/actioncam']
   if loaded then return status(false,'ActionCam sharing requires the supported Lua closure API')end
   return status(true)
  end
  local update,render=rawget(G,'update'),rawget(G,'render')
  local loaded=G.package and G.package.loaded and G.package.loaded['mods/actioncam/actioncam']
  if roots and roots.update==update and roots.render==render and roots.loaded==loaded then
   for _,record in pairs(records)do
    if up(record.update,'step')~=record.step_gate or up(record.hook,'apply')~=record.apply_gate or up(record.step,'bindings_step')~=record.binding_gate then
     return status(false,'ActionCam ownership changed; Photo Mode must release its camera')
    end
   end
   -- The roots can stay unchanged while another owner temporarily replaces a
   -- gate. Once every exact gate is restored, clear the earlier conflict.
   return status(true)
  end
  local queue,deferred,seen,found,helpers={},{},{},{},{};local index=1;local inspected=0
  local function enqueue(fn,name)
   if type(fn)~='function'or seen[fn]or helpers[fn]then return end
   seen[fn]=true
   local lower=type(name)=='string'and name:lower()or''
   if chain_names[name]or name==''or lower:find('update',1,true)or lower:find('prev',1,true)or lower:find('render',1,true)then
    queue[#queue+1]=fn
   else deferred[#deferred+1]=fn end
  end
  -- Follow likely callback predecessors first, without requiring their names.
  -- Other function upvalues remain a bounded, read-only fallback. Tables and
  -- engine namespaces are never traversed or rewritten.
  enqueue(render,'render');enqueue(update,'update')
  while #queue>0 or index<=#deferred do
   local fn
   if #queue>0 then fn=table.remove(queue)else fn=deferred[index];index=index+1 end
   if not helpers[fn]then
    inspected=inspected+1
    if inspected>2048 then return status(false,'Camera callback chain cannot be verified')end
    local record=records[fn]
    local candidate,why
    if record then
     candidate=record
     if up(fn,'step')~=record.step_gate then return status(false,'ActionCam update ownership changed')end
    else candidate,why=verify(fn)end
    if candidate==false then return status(false,why)end
    if candidate then
     found[#found+1]=candidate
     -- All seven camera closures were fingerprinted above. Their private
     -- helper graphs are not additional callback owners; still inspect the
     -- update/render wrappers' external predecessor links for another camera.
     for _,name in ipairs({'step','apply','bindings','restore','drop'})do helpers[candidate[name]]=true end
    elseif original_source(fn)and up(fn,'step')then return status(false,'Unsupported ActionCam wrapper; Photo Mode cannot share it')end
    for i=1,120 do
     local read,name,value=pcall(dbg.getupvalue,fn,i)
     if not read then return status(false,'Camera callback chain cannot be inspected')end
     if not name then break end
     -- Generic discovery never authorizes installation: every candidate must
     -- still pass the exact versioned seven-closure signature contract.
     enqueue(value,name)
    end
   end
  end
  if loaded and #found==0 then return status(false,'ActionCam is loaded but its camera owner cannot be verified')end
  if #found>1 then return status(false,'Multiple ActionCam runtimes are active; keep one gameplay camera')end
  for _,record in ipairs(found)do
   local ok,why=pcall(install,record);if not ok then return status(false,'ActionCam handoff setup failed: '..tostring(why))end
  end
  self.count=#found;roots={update=update,render=rawget(G,'render'),loaded=loaded}
  return status(true)
 end
 function self.set_priority(reader)assert(reader==nil or type(reader)=='function');priority=reader end
 function self.set_input_blocked(reader)assert(reader==nil or type(reader)=='function');input_reader=reader end
 function self.acquire()
  local ok,why=self.refresh();if not ok then return false,why end
  if self.entry_failed then return false,'The previous ActionCam handoff must finish cancelling before Photo starts'end
  if self.held then return true end
  self.held=true
  for _,record in pairs(records)do
   local cleared,reason=pcall(clear,record)
   if not cleared then self.entry_failed=true;return false,'ActionCam camera cleanup is pending: '..tostring(reason)end
   record.drain=true
  end
  return true
 end
 function self.release()
  if not self.held then return true end
  -- Failed entry never started the Photo camera. The controller calls release
  -- only after cancelling its own input/time/effects, so ActionCam can resume
  -- with its original (possibly partially reset) private state on the next frame.
  if self.entry_failed then self.entry_failed=nil;self.held=false;return true end
  for _,record in pairs(records)do
   local ok,why=pcall(clear,record)
   if not ok then return false,'ActionCam resume is waiting for camera cleanup: '..tostring(why)end
   record.drain=true
  end
  self.held=false
  return true
 end
 function self.dispose()
  if self.held then return false,'Photo camera cleanup must complete before restoring ActionCam hooks'end
  for _,record in pairs(records)do
   if up(record.update,'step')~=record.step_gate or up(record.hook,'apply')~=record.apply_gate or up(record.step,'bindings_step')~=record.binding_gate or up(record.bindings,'PHOTO_BINDS')~=record.filtered then
    return false,'ActionCam callback ownership changed; its replacements were left untouched'
   end
  end
  for _,record in pairs(records)do
   put(record.update,'step',record.step)
   put(record.hook,'apply',record.apply)
   put(record.step,'bindings_step',record.bindings)
   put(record.bindings,'PHOTO_BINDS',record.binds)
  end
  records={};roots=nil;self.disabled=true;self.count=0
  return true
 end
 function self.wrap_update(previous,on_conflict)
  local function pack(...)return{n=select('#',...),...}end
  local function notify(why)
   if not on_conflict then return end
   local ok,problem=pcall(on_conflict,why)
   if not ok then log('Photo camera cleanup is pending: '..tostring(problem))end
  end
  return function(...)
   if self.disabled then return previous(...)end
   local ok,why=self.refresh()
   if not ok then notify(why)end
   local result=pack(pcall(previous,...))
   if not result[1]then notify(result[2]);error(result[2],0)end
   return unpack(result,2,result.n)
  end
 end
 return self
end
return M

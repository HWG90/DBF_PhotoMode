-- Finite read-only ESC comparison. No input reads that drain queues, setters,
-- native modules, retained native IDs, hooks, or writes to gameplay state.
local M={}
function M.new(sr,log)
 local self={};local started,armed,last,next_key,deadline,step,transition,held,closed
 local esc;local keys={};local reads=0
 local delays={0,.05,.2,.5}
 local function emit(message)pcall(log,'ESC state: '..message)end
 local function read(api,name,...)
  local fn=type(api)=='table'and api[name]
  if type(fn)~='function'then return 'unavailable'end
  reads=reads+1
  local ok,value=pcall(fn,...)
  if not ok then return 'error'end
  if type(value)=='boolean'or type(value)=='number'then return value end
  return type(value)
 end
 local function snapshot(label,now)
  local out={label,'t='..string.format('%.3f',now-started)}
  for _,name in ipairs({'has_focus','mouse_focus','show_cursor','clip_cursor'})do
   out[#out+1]='Window.'..name..'='..tostring(read(sr.Window,name))
  end
  for _,name in ipairs({'Keyboard','Mouse','Pad1'})do out[#out+1]=name..'.active='..tostring(read(sr[name],'active'))end
  for _,name in ipairs({'w','a','s','d','esc'})do
   local id=keys[name]
   out[#out+1]='key.'..name..'='..tostring(id~=nil and read(sr.Keyboard,'button',id)or'unavailable')
  end
  emit(table.concat(out,'; '))
 end
 function self.stop(reason)
  if closed then return end
  closed=true;deadline=nil;emit('stopped; '..reason..'; getter_calls='..reads)
 end
 function self.tick(photo_active)
  if closed then return end
  local ok,now=pcall(sr.Application.time_since_launch)
  if not ok or type(now)~='number'or now~=now or now==math.huge or now<0 then self.stop('clock unavailable');return end
  if last and now<last then self.stop('clock changed');return end;last=now
  if not started then
   started=now;transition=0
   local index=type(sr.Keyboard)=='table'and(sr.Keyboard.button_index or sr.Keyboard.button_id)
   if type(index)~='function'then self.stop('keyboard IDs unavailable');return end
   for _,name in ipairs({'w','a','s','d','esc'})do
    local found,value=pcall(index,name);if found and type(value)=='number'and value>=0 and value%1==0 then keys[name]=value end
   end
   esc=keys.esc;if esc==nil then self.stop('ESC ID unavailable');return end
   emit('waiting up to 180 seconds for ESC; then 90 seconds / 6 presses; read-only; cursor flags do not prove menu state')
   snapshot('baseline',now)
  end
  if not armed and now-started>=180 or armed and now-armed>=90 then self.stop('time limit');return end
  if photo_active then self.stop('Photo Mode opened; native ESC comparison requires Photo Mode closed');return end
  if deadline and now>=deadline+delays[step]then
   snapshot('press '..transition..' after '..delays[step]..'s',now);step=step+1
   if step>#delays then deadline=nil;if transition>=6 then self.stop('transition limit');return end end
  end
  if next_key and now<next_key then return end;next_key=now+.05
  local value=read(sr.Keyboard,'button',esc)
  if type(value)~='boolean'and type(value)~='number'then self.stop('ESC read failed');return end
  local down=value==true or type(value)=='number'and value>.5
  if down and not held then
   armed=armed or now
   transition=transition+1
   if transition>6 then self.stop('transition limit');return end
   deadline,step=now,2;snapshot('press '..transition..' immediate',now)
  end
  held=down
 end
 function self.done()return closed==true end
 return self
end
return M

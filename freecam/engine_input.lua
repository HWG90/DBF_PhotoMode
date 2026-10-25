-- Shared input service v1 from the engine's Mouse, for hosts without LLL's helper (Boot Mod
-- Loader). The game's Window flags stay as they are: with mouse focus off the engine stops
-- reporting the mouse. The menu gets a virtual cursor moved by the relative axis, which the
-- Photo menu draws (virtual_cursor). Keys reach the game unless a keyboard bridge is given:
-- then a {keyboard=true} lease reserves LLL's whitelist in-game (the bridge's keyboard_acquire,
-- RegisterHotKey on its own thread) and reports the held keys like LLL's service does.
local M={}
local function le32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
-- LLL's keyboard whitelist (lll/native/steam_keyboard.c), as the 32-byte canonical mask.
M.keyboard_mask=table.concat({le32(0x081f3300),le32(0x03ffe1ff),le32(0x27fffffe),le32(0xf7ffffff),le32(0x000300ff),le32(0xfc00003f),le32(0xf8000001),le32(0x00000004)})
-- Refusals that mean "this host cannot isolate the keyboard": the consumer then falls back to engine keys.
M.refused='Keyboard request refused (0x00000005)'
local function index(device,kind,name)
 for _,field in ipairs({kind..'_index',kind..'_id'})do
  local f=device[field]
  if type(f)=='function'then local ok,id=pcall(f,name);if ok and type(id)=='number'then return id end end
 end
end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
-- keyboard: optional function returning the bridge (keyboard_acquire/sample/release), loaded
-- at the first keyboard request.
function M.new(sr,log,keyboard)
 local Mouse=sr.Mouse
 local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true,keyboard=keyboard~=nil,keyboard_mask=keyboard and M.keyboard_mask or nil,
  virtual_cursor=true,coordinates='client-top-left'}}
 local lease,axis,buttons,x,y,bridge,bridge_fault;local seen={}
 local function note(what,detail)if not seen[what]then seen[what]=true;if log then log('Engine input: '..what..(detail and(' '..detail)or''))end end end
 -- The mouse can be missing in the first frames; it is looked up again until found.
 local function resolve()
  if axis and axis.mouse then return true end
  axis={mouse=index(Mouse,'axis','mouse'),wheel=index(Mouse,'axis','wheel')};buttons={}
  for mask,name in pairs({[1]='left',[2]='right',[4]='middle',[8]='extra_1',[16]='extra_2'})do buttons[mask]=index(Mouse,'button',name)end
  if axis.mouse then note('mouse found','(axis '..axis.mouse..', wheel '..tostring(axis.wheel)..', left '..tostring(buttons[1])..')')end
  return axis.mouse~=nil
 end
 local function keyboard_bridge()
  if bridge or bridge_fault then return bridge end
  local ok,value=pcall(keyboard)
  if ok and type(value)=='table'and type(value.keyboard_acquire)=='function'and type(value.keyboard_sample)=='function'and type(value.keyboard_release)=='function'then bridge=value
  else bridge_fault=tostring(ok and'Keyboard bridge API differs'or value);note('keyboard isolation unavailable:',bridge_fault)end
  return bridge
 end
 function service.acquire(owner,mode,_,options)
  if type(owner)~='string'or owner==''then return nil,'Invalid input owner'end
  if mode~='menu'and mode~='camera'then return nil,'Invalid input mode'end
  if lease then return nil,'Cursor lease already owned or restoring'end
  if not resolve()then return nil,'The engine mouse is not ready yet'end
  local generation
  if type(options)=='table'and options.keyboard==true then
   if not(keyboard and keyboard_bridge())then return nil,M.refused end
   local ok,value=pcall(bridge.keyboard_acquire,M.keyboard_mask)
   if not ok then return nil,'Keyboard isolation: '..tostring(value)end
   generation=value;note('keyboard lease requested')
  end
  lease={token={},owner=owner,mode=mode,keyboard=generation~=nil}
  return lease.token
 end
 function service.owns(token)return lease~=nil and token~=nil and lease.token==token and not lease.releasing end
 function service.status()return{owner=lease and lease.owner or nil,mode=lease and lease.mode or nil,pending_restore=lease~=nil and lease.releasing==true}end
 function service.set_mode(token,mode)
  if not service.owns(token)or(mode~='menu'and mode~='camera')then return false,'Photo input lease revoked'end
  lease.mode=mode;return true
 end
 -- The keyboard lease is released before the cursor lease; a worker still retiring keeps
 -- the lease pending, and the consumer retries.
 function service.release(token)
  if not lease or lease.token~=token then return true end
  if lease.keyboard then
   lease.releasing=true
   local called,done,why=pcall(bridge.keyboard_release)
   if not called or done~=true then return false,tostring(called and why or done)end
  end
  lease=nil;return true
 end
 function service.snapshot(token)
  if not service.owns(token)then return nil,'Photo input lease revoked'end
  local keys
  if lease.keyboard then
   local called,state,held,generation=pcall(bridge.keyboard_sample)
   if not called then return nil,'Keyboard sample failed: '..tostring(state)end
   if state==2 then note('keyboard isolated')end
   keys={keyboard_state=state,keyboard_active=state==2,keyboard_keys=held,keyboard_mask=M.keyboard_mask,keyboard_generation=generation}
  end
  local width,height=sr.Gui.resolution()
  if not x then x,y=width/2,height/2 end
  local motion=Mouse.axis(axis.mouse)
  local dx,dy=motion and motion.x or 0,motion and motion.y or 0 -- the engine counts y down
  if dx~=0 or dy~=0 then note('first mouse motion seen')end
  if lease.mode=='menu'then local k=height/1080;x=clamp(x+dx*k,0,width-1);y=clamp(y+dy*k,0,height-1)end
  local pressed=0
  for mask,id in pairs(buttons)do
   local value=Mouse.button(id);if value==true or type(value)=='number'and value>.5 then pressed=pressed+mask end
  end
  if pressed%2==1 then note('first left click seen')end
  local wheel=axis.wheel and Mouse.axis(axis.wheel)
  local sample={valid=true,x=x,y=y,width=width,height=height,buttons=pressed,wheel=wheel and wheel.y*120 or 0,dx=dx,dy=dy}
  if keys then for k,v in pairs(keys)do sample[k]=v end;sample.valid=keys.keyboard_active end
  return sample
 end
 return service
end
return M

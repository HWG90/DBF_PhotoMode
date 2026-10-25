-- Shared input service v1 from the engine's Mouse, for hosts without LLL's helper (Boot Mod
-- Loader). The game's Window flags stay as they are: with mouse focus off the engine stops
-- reporting the mouse. The menu gets a virtual cursor moved by the relative axis, which the
-- Photo menu draws (virtual_cursor). No keyboard capture: keys also reach the game.
local M={}
local function index(device,kind,name)
 for _,field in ipairs({kind..'_index',kind..'_id'})do
  local f=device[field]
  if type(f)=='function'then local ok,id=pcall(f,name);if ok and type(id)=='number'then return id end end
 end
end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
function M.new(sr,log)
 local Mouse=sr.Mouse
 local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true,keyboard=false,virtual_cursor=true,coordinates='client-top-left'}}
 local lease,axis,buttons,x,y;local seen={}
 local function note(what,detail)if not seen[what]then seen[what]=true;if log then log('Engine input: '..what..(detail and(' '..detail)or''))end end end
 -- The mouse can be missing in the first frames; it is looked up again until found.
 local function resolve()
  if axis and axis.mouse then return true end
  axis={mouse=index(Mouse,'axis','mouse'),wheel=index(Mouse,'axis','wheel')};buttons={}
  for mask,name in pairs({[1]='left',[2]='right',[4]='middle',[8]='extra_1',[16]='extra_2'})do buttons[mask]=index(Mouse,'button',name)end
  if axis.mouse then note('mouse found','(axis '..axis.mouse..', wheel '..tostring(axis.wheel)..', left '..tostring(buttons[1])..')')end
  return axis.mouse~=nil
 end
 function service.acquire(owner,mode)
  if type(owner)~='string'or owner==''then return nil,'Invalid input owner'end
  if mode~='menu'and mode~='camera'then return nil,'Invalid input mode'end
  if lease then return nil,'Cursor lease already owned or restoring'end
  if not resolve()then return nil,'The engine mouse is not ready yet'end
  lease={token={},owner=owner,mode=mode}
  return lease.token
 end
 function service.owns(token)return lease~=nil and token~=nil and lease.token==token end
 function service.status()return{owner=lease and lease.owner or nil,mode=lease and lease.mode or nil,pending_restore=false}end
 function service.release(token)if service.owns(token)then lease=nil end;return true end
 function service.snapshot(token)
  if not service.owns(token)then return nil,'Photo input lease revoked'end
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
  return{valid=true,x=x,y=y,width=width,height=height,buttons=pressed,wheel=wheel and wheel.y*120 or 0,dx=dx,dy=dy}
 end
 return service
end
return M

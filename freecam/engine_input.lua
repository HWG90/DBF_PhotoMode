-- Shared input service v1 over the engine's Window and Mouse, for hosts without LLL's
-- helper (Boot Mod Loader). The game stops reading the mouse while a lease is held;
-- there is no keyboard capture, so keys also reach the game (keyboard=false).
local M={}
-- Engine cursor and Gui share a bottom-left origin; the contract is client top-left.
-- Raw mouse motion is y-up in the engine and y-down in the contract.
function M.new(sr)
 local W,Mouse=sr.Window,sr.Mouse
 local axis={}
 for _,name in ipairs({'mouse','cursor','wheel'})do
  local ok,id=pcall(Mouse.axis_id,name);axis[name]=ok and type(id)=='number'and id or nil
 end
 local buttons={}
 for mask,name in pairs({[1]='left',[2]='right',[4]='middle',[8]='extra_1',[16]='extra_2'})do
  local ok,id=pcall(Mouse.button_id,name);if ok and type(id)=='number'then buttons[mask]=id end
 end
 local relative=axis.mouse~=nil and axis.cursor~=nil
 local service={version=1,capabilities={menu=axis.cursor~=nil,camera=relative,relative_mouse=relative,keyboard=false,coordinates='client-top-left'}}
 local lease,saved
 local function read()return{focus=W.mouse_focus(),cursor=W.show_cursor(),clip=W.clip_cursor()}end
 local function apply(focus,cursor,clip)
  W.set_mouse_focus(focus);W.set_show_cursor(cursor);W.set_clip_cursor(clip)
  return W.mouse_focus()==focus and W.show_cursor()==cursor and W.clip_cursor()==clip
 end
 function service.acquire(owner,mode)
  if type(owner)~='string'or owner==''then return nil,'Invalid input owner'end
  if mode~='menu'and mode~='camera'then return nil,'Invalid input mode'end
  if service.capabilities[mode]~=true then return nil,'Engine '..mode..' input is unavailable'end
  if lease then return nil,'Cursor lease already owned or restoring'end
  local ok,state=pcall(read);if not ok then return nil,'Window cursor flags unavailable'end
  local applied,good=pcall(apply,false,mode=='menu',true)
  if not applied or not good then pcall(apply,state.focus,state.cursor,state.clip);return nil,'Window refused Photo input flags'end
  saved=state;lease={token={},owner=owner,mode=mode}
  return lease.token
 end
 function service.owns(token)return lease~=nil and token~=nil and lease.token==token end
 function service.status()return{owner=lease and lease.owner or nil,mode=lease and lease.mode or nil,pending_restore=false}end
 function service.release(token)
  if not service.owns(token)then return true end
  local ok,good=pcall(apply,saved.focus,saved.cursor,saved.clip)
  if not ok or not good then return false,'Window cursor flags were not restored'end
  lease,saved=nil,nil
  return true
 end
 function service.snapshot(token)
  if not service.owns(token)then return nil,'Photo input lease revoked'end
  local width,height=sr.Gui.resolution()
  local cursor=Mouse.axis(axis.cursor)
  local wheel=axis.wheel and Mouse.axis(axis.wheel)
  local motion=axis.mouse and Mouse.axis(axis.mouse)
  local pressed=0
  for mask,id in pairs(buttons)do
   local value=Mouse.button(id);if value==true or type(value)=='number'and value>.5 then pressed=pressed+mask end
  end
  return{valid=cursor~=nil,x=cursor and cursor.x or 0,y=cursor and height-cursor.y or 0,width=width,height=height,
   buttons=pressed,wheel=wheel and wheel.y*120 or 0,dx=motion and motion.x or 0,dy=motion and-motion.y or 0}
 end
 return service
end
return M

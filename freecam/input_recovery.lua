-- Explicit recovery closes cooperating editors before repairing gameplay focus.
-- No synthetic key releases, process hooks, or unknown native gates are used.
local M={}
function M.new(deps)
 local self={};local pending=false;local held=false;local participants={};local seen={};local message
 local function report(value)
  if message~=value then message=value;if deps.log then deps.log('Input recovery: '..value)end end
 end
 local function call(fn,...)
  if type(fn)~='function'then return false,'Recovery interface unavailable'end
  local ok,value,why=pcall(fn,...)
  if not ok then return false,tostring(value)end
  if value~=true then return false,why or'Recovery acknowledgment pending'end
  return true
 end
 local function input()
  local ok,value=pcall(deps.input)
  if ok and type(value)=='table'then return value end
 end
 function self.status()return{active=pending,pending_restore=pending,reason=message}end
 function self.request()
  if not pending then pending=true;participants={};seen={};report('closing mod editors and Photo Mode')end
  return true
 end
 function self.step()
  if not pending then return true end
  local found,views=pcall(deps.views)
  if not found or type(views)~='table'then report('editor inventory unavailable');return false,message end
  for _,view in ipairs(views)do
   if not view.key then report('editor identity unavailable');return false,message end
   if not seen[view.key]then seen[view.key]=true;participants[#participants+1]=view end
  end
  -- Pin every observed frontend through acknowledgment, including an old
  -- provider that is replaced while its native release is still pending.
  for _,view in ipairs(participants)do
   local ok,why=call(view.close)
   if not ok then report(tostring(view.name)..': '..tostring(why));return false,message end
  end
  local stopped,why=call(deps.stop_photo)
  if not stopped then report('Photo Mode: '..tostring(why));return false,message end
  local camera=input()
  if not camera then report('Photo input service unavailable');return false,message end
  local focused,foreground=pcall(camera.focused)
  if not focused or foreground~=true then report('return focus to the game');return false,message end
  for _,reader in ipairs({'native_menu_active','chat_active'})do
   local ok,active=pcall(camera[reader]or function()return nil end)
   if not ok or active~=false then report('close the native menu and chat to finish');return false,message end
  end
  local read,state=pcall(camera.external_status or function()return nil end)
  if not read or type(state)~='table'or state.available~=true or state.open~=false or state.active~=false or state.pending_restore~=false or state.owner~=nil then
   report('another editor still owns input');return false,message
  end
  local released,reason=call(camera.recover_native)
  if not released then report(tostring(reason));return false,message end
  local status_ok,status=pcall(camera.status)
  if not status_ok or type(status)~='table'or status.active~=false or status.owned~=false or status.cleanup_pending~=false or status.native_mode~=0 then
   report('Photo native input release is not acknowledged');return false,message
  end
  -- Native menus and every known mod gate are now inactive. This is an
  -- explicitly requested repair, not restoration of a contaminated snapshot.
  local restored,problem=pcall(function()
   assert(deps.window.set_mouse_focus(true)~=false,'Gameplay focus repair refused')
   assert(deps.window.mouse_focus()==true,'Gameplay focus repair readback failed')
   assert(deps.window.set_show_cursor(false)~=false,'Gameplay cursor repair refused')
   assert(deps.window.show_cursor()==false,'Gameplay cursor repair readback failed')
  end)
  if not restored then report(tostring(problem));return false,message end
  pending=false;participants={};seen={};report('gameplay mouse restored');return true
 end
 function self.poll(key)
  local camera=input();local chord=false
  if camera then
   local ok,down=pcall(function()
    return camera.focused()==true and camera.down(17)==true and camera.down(16)==true and camera.down(key or 121)==true
   end)
   chord=ok and down
  end
  if chord and not held then self.request()end
  held=chord
  return self.step()
 end
 return self
end
return M

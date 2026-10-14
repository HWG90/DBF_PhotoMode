-- Confinement follows the existing Photo input lease; no hooks or cursor warp.
local M={}
function M.attach(camera,input,clip)
 assert(not camera.cursor_state,'Photo cursor confinement already attached')
 local cursor=input.menu_cursor;local release=camera.release;local mode
 input.menu_cursor=function(menu)
  local transition=mode~=menu
  if transition then local ok,why=clip.suspend();if not ok then return false,why end end
  local ok,why=cursor(menu);if not ok then return false,why end
  if transition then clip.resume()end
  local captured,reason=clip.tick(true)
  if captured then mode=menu end
  return captured,reason
 end
 camera.release=function()
  local ok,why=clip.release('Photo input released');if not ok then return false,why end
  mode=nil
  return release()
 end
 camera.cursor_state=clip.state
 return camera
end
return M

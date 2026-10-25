-- R35's explicit ACCESS_DENIED reply means the native acquire owns no
-- keyboard registrations. Its rollback mistakenly authenticates that rejected
-- request again, preventing cursor cleanup. Retire only this proven rejection;
-- accepted generations, lost replies and other clients remain untouched.
local M={}
local DENIED='Keyboard request refused (0x00000005)'
local function up(fn,wanted)
 if type(fn)~='function'then return end
 for i=1,80 do
  local name,value=debug.getupvalue(fn,i)
  if not name then break end
  if name==wanted then return value,i end
 end
end
function M.retire_denied(service,token)
 local loader=rawget(_G,'LiveLuaLoader')
 if not loader or not loader.capabilities then return false end
 local revision=loader.capabilities.revision
 -- Insert-fix.2 embeds the identical input service and keyboard broker; only
 -- the manager shortcut handling changed. Keep qualification explicit.
 if revision~='R35-26088801-cffi-dev.2'and revision~='R35-26088801-cffi-insert-fix.2'then return false end
 if type(service)~='table'or service.version~=1 or service~=loader.input_service then return false end
 local close=up(service.release,'close_lease')
 local lease=up(close,'lease');local platform=up(close,'platform')
 if not lease or lease.token~=token or lease.owner~='dbf_freecam'or lease.active~=false or not lease.keyboard or type(platform)~='table'then return false end
 local original=platform.keyboard_release
 local owner,index=up(original,'keyboard_owner')
 if not owner or owner.handle~=lease.keyboard or owner.attempted~=true or owner.accepted~=false or owner.generation~=0 or owner.reason~=DENIED then return false end
 -- Only the exact, explicitly rejected handle is eligible. Restore the API
 -- even if independent pointer/cursor cleanup fails and needs another retry.
 local handle=lease.keyboard
 platform.keyboard_release=function(value)
  if value~=handle then return original(value)end
  if up(original,'keyboard_owner')~=owner then return false,'Keyboard cleanup owner changed'end
  assert(debug.setupvalue(original,index,nil)=='keyboard_owner','Keyboard cleanup layout changed')
  return true
 end
 local called,ok,why=pcall(service.release,token)
 platform.keyboard_release=original
 if not called then return false,ok end
 return ok==true,why
end
return M

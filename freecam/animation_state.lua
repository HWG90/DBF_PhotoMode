-- Photo-only guard for live Units whose animation graph has not been created
-- yet, or has retired during death/respawn. Never cache graph presence/pointers.
local M={}
function M.new(sr)
 local U=sr and sr.Unit or{}
 local alive,has_machine,original=U.alive,U.has_animation_state_machine,U.animation_get_state
 return function(unit,...)
  if type(alive)~='function'then error('Photo animation read: Unit.alive unavailable',2)end
  if alive(unit)~=true then error('Photo animation read: Unit is not alive',2)end
  if type(has_machine)~='function'then error('Photo animation read: state-machine query unavailable',2)end
  if has_machine(unit)~=true then error('Photo animation read: animation state machine unavailable',2)end
  if type(original)~='function'then error('Photo animation read: original state getter unavailable',2)end
  -- Tail return preserves every layer, internal nil, and trailing nil. Existing
  -- {pcall(...)} callers retain their status at [1] and layer n at [n+1].
  -- Errors are ordinary Lua errors; this does not catch a native access violation.
  return original(unit,...)
 end
end
return M

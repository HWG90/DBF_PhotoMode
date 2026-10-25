-- Keys hosted by a loader's Mod Bindings Menu (Boot Mod Loader's look-alike of the v2.3
-- API). Players set them in its settings window or in our panel (written through with
-- set_binding), and the loader answers false while the game window has no focus or the
-- chat box is open. Registered as held keys: the runtime keeps computing its own edges.
local M={}
-- The helper binds keyboard keys and the three extra mouse buttons, never left/right
-- mouse or modifiers.
local mouse={[4]='middle',[5]='extra_1',[6]='extra_2'}
local mouse_labels={middle='MOUSE 3',extra_1='MOUSE 4',extra_2='MOUSE 5'}
-- A virtual key from our settings as the helper's default spec; no name means no key.
function M.spec(code,names)
 if mouse[code]then return{button=mouse[code],device='mouse',trigger='hold'}end
 return{button=names[code]or'',device='keyboard',trigger='hold'}
end
-- rows: {id=,label=,default=virtual key}. A row the helper refuses stays ours.
function M.new(api,rows,names,log)
 local self={};local ids={}
 for _,row in ipairs(rows)do
  local id='war_journalist.'..row.id
  local called,ok,why=pcall(api.register_binding,id,row.label,nil,{category='War Journalist',default=M.spec(row.default,names)})
  if called and ok then ids[row.id]=id elseif log then log('Key "'..row.label..'" stays in the Photo panel: '..tostring(called and why or ok))end
 end
 function self.hosted(id)return ids[id]~=nil end
 function self.down(id)local called,value=pcall(api.is_down,ids[id]);return called and value==true end
 -- A key chosen in our panel, as the helper's binding; left/right mouse cannot be bound there.
 function self.set(id,code)
  if not ids[id]then return false,'Key not hosted'end
  local spec=M.spec(code,names)
  if spec.button==''then return false,'That key cannot be bound in '..tostring(api.window or'the loader\'s settings window')end
  if type(api.set_binding)~='function'then return false,'The loader cannot change bindings'end
  local called,ok,why=pcall(api.set_binding,ids[id],spec)
  if called and ok then return true end
  return false,tostring(called and why or ok)
 end
 function self.label(id)
  if not ids[id]then return nil end
  local called,list=pcall(api.binding,ids[id]);local first=called and type(list)=='table'and list[1]
  if type(first)~='table'or type(first[2])~='string'or first[2]==''then return'NONE'end
  return first[1]=='mouse'and mouse_labels[first[2]]or string.upper(first[2])
 end
 return self
end
return M

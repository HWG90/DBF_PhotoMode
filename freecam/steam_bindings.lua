-- Keys hosted by a loader's Mod Bindings Menu (Boot Mod Loader's look-alike of the v2.3
-- API). Players set them in its settings window or in our panel (written through with
-- set_binding), and the loader answers false while the game window has no focus or the
-- chat box is open. Registered as held keys: the runtime keeps computing its own edges.
local M={}
-- The helper binds keyboard keys and the three extra mouse buttons, never left/right
-- mouse or modifiers.
local mouse={[4]='middle',[5]='extra_1',[6]='extra_2'}
local mouse_labels={middle='MOUSE 3',extra_1='MOUSE 4',extra_2='MOUSE 5'}
local mouse_codes={middle=4,extra_1=5,extra_2=6}
-- A virtual key from our settings as the helper's default spec; no name means no key.
function M.spec(code,names)
 if mouse[code]then return{button=mouse[code],device='mouse',trigger='hold'}end
 return{button=names[code]or'',device='keyboard',trigger='hold'}
end
-- rows: {id=,label=,default=virtual key}. A row the helper refuses stays ours.
function M.new(api,rows,names,log)
 local self={};local ids={};local codes={}
 for code,name in pairs(names)do codes[name]=code end
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
 -- The virtual key of a hosted binding, for reading it from an isolated keyboard (the engine,
 -- and so the helper, no longer sees reserved keys).
 function self.code(id)
  if not ids[id]then return nil end
  local called,list=pcall(api.binding,ids[id]);local first=called and type(list)=='table'and list[1]
  if type(first)~='table'or type(first[2])~='string'then return nil end
  if first[1]=='mouse'then return mouse_codes[first[2]]end
  return codes[first[2]]
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

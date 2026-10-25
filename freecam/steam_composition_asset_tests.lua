-- Actual Lua 5.1 entry wiring and portable logo geometry; no game or asset IO writes.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run this fixture in actual Lua 5.1')
local globals={'mod','stingray','LiveLuaLoader','DBF_PHOTO_MODE_OWNER'}
local previous={};for _,name in ipairs(globals)do previous[name]=rawget(_G,name)end
local function check()
 local loaded,requires,deps={},{},nil
 local runtime={tick=function()end,dispose=function()return true end}
 local composition=dofile('freecam/composition.lua')
 local function require_module(path)
  requires[path]=(requires[path]or 0)+1
  if path=='src/composition.lua'then return composition end
  if path=='src/assets/logo_art.lua'or path=='src/assets/helldiver_crest.lua'then
   local value=dofile('freecam/'..path:sub(5));loaded[path]=value;return value
  end
  if path=='src/steam_runtime.lua'then return{new=function(_,_,modules)deps=modules;return runtime end}end
  return{}
 end
 rawset(_G,'mod',{require=require_module,log=function()end})
 rawset(_G,'stingray',{})
 rawset(_G,'LiveLuaLoader',{capabilities={native_ffi=false},input_service={version=1}})
 rawset(_G,'DBF_PHOTO_MODE_OWNER',nil)
 local entry=dofile('freecam/steam51.lua');entry.on_enable()
 assert(deps==nil,'The runtime starts on the first update, after MCM is enabled');entry.on_update()
 local art=assert(loaded['src/assets/logo_art.lua'],'Load the curated logo geometry at entry')
 local crest=assert(loaded['src/assets/helldiver_crest.lua'],'Load the Helldiver crest at entry')
 assert(deps.composition==composition and composition.logo_art==art and art[2]==crest,'Match legacy composition asset assignment')
 assert(#crest.triangles==451,'Keep the actual Helldiver crest at picker index 2')
 assert(not deps.capture and not deps.capture_backend,'Asset loading must preserve the optional capture gate')
 local names
 local options=dofile('freecam/photo_options.lua')
 for _,page in ipairs(options.pages())do if page.id=='composition'then
  for _,control in ipairs(page.controls)do if control.id=='logo'then names=control.choices end end
 end end
 local expected={'None','Helldiver crest','DBF','Super Earth crest','Helldivers 2','Arrowhead',
  'Helldivers 2 — wide','Helldivers 2 — compact','Helldivers II crest','Super Citizen Edition',
  'Omens of Tyranny','Heart of Democracy','Into the Unjust'}
 assert(names and #names==#expected,'Preserve the complete saved logo picker')
 for index,name in ipairs(expected)do assert(names[index]==name,'Preserve saved logo index '..index)end
 local values={};for key,value in pairs(options.defaults)do values[key]=value end
 local seen={}
 for _,index in ipairs({2,4,5,6,7,8,9,10,11,12,13})do
  local mesh=assert(art[index],'Curated choice must have an actual asset: '..names[index])
  local expected_count=#(mesh.rects or{})+#(mesh.triangles or{})
  assert(expected_count>0,'Curated asset geometry is empty')
  values.logo=index;values.logo_color='#F4CA35'
  local commands=composition.layout(1920,1080,values,0)
  assert(#commands==expected_count,'Curated choice used fallback or dropped geometry: '..names[index])
  local signature={}
  for _,command in ipairs(commands)do
   assert(command.c[1]==244 and command.c[2]==202 and command.c[3]==53,'Curated geometry must retain tint controls')
   assert(command.x>=0 and command.y>=0 and command.x+command.w<=1920.001 and command.y+command.h<=1080.001,'Curated geometry left the frame')
   if command.type=='triangle'then
    assert(#command.points==6);signature[#signature+1]='triangle:'..table.concat(command.points,',')
   else signature[#signature+1]=table.concat({'rect',command.x,command.y,command.w,command.h},',')end
  end
  local key=table.concat(signature,'|')
  assert(not seen[key],'Named curated logos must have distinct geometry: '..names[index]);seen[key]=index
 end
 values.clean_view=true;values.logo=13
 assert(#composition.layout(1920,1080,values,0)==0,'Clean view still hides curated art')
 for _=1,200 do entry.on_update()end
 assert(entry.on_disable()and rawget(_G,'DBF_PHOTO_MODE_OWNER')==nil,'Release entry ownership normally')
 assert(requires['src/assets/logo_art.lua']==1 and requires['src/assets/helldiver_crest.lua']==1,'Unchanged updates must not reload or rebuild assets')
end
local ok,why=pcall(check)
for _,name in ipairs(globals)do rawset(_G,name,previous[name])end
assert(ok,why)
print('Steam composition assets: entry-only loading, legacy indices, 11 distinct actual logo meshes, tint and clean view passed')

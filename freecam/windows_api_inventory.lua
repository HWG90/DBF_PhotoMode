-- One bounded inventory per enable. Presence is not qualification to call an API.
local M={}
-- Names and function metadata only: never invoke an unknown native UI callback
-- or change the environment of the game's update function.
function M.hud_environment(globals,log,sr)
 local seen={};local tables,keys,hits=0,0,0
 local function scan(value,path,depth)
  if type(value)~='table'or seen[value]or tables>=64 or keys>=4096 then return end
  seen[value]=true;tables=tables+1
  for key,item in next,value do
   keys=keys+1;if keys>4096 then break end
   if type(key)=='string'and #key<=96 then
    local name=path..'.'..key
    if key:lower():find('hud',1,true)or path:lower():find('hud',1,true)then
     if hits<64 then log('HUD Lua binding candidate: '..name..' type='..type(item)..'; not invoked');hits=hits+1 end
     if depth<2 then scan(item,name,depth+1)end
    elseif depth==0 and type(item)=='table'then scan(item,name,depth+1)end
   end
  end
 end
 scan(globals,'_G',0)
 local update=rawget(globals,'update')
 if type(update)=='function'and type(getfenv)=='function'then
  local ok,environment=pcall(getfenv,update)
  if ok then
   log('HUD Lua update environment shares globals='..tostring(environment==globals))
   scan(environment,'update.env',0)
  end
 end
 -- A C binding may carry a different Lua 5.1 environment from a mod's
 -- sandbox. Inspect names once; never replace an environment or call a HUD setter.
 if sr and type(getfenv)=='function'then
  for _,entry in ipairs({{'Gui','set_visible'},{'Application','main_world'},{'Unit','camera'}})do
   local api=sr[entry[1]];local fn=api and api[entry[2]]
   if type(fn)=='function'then
    local ok,environment=pcall(getfenv,fn)
    if ok and type(environment)=='table'then
     log('HUD Lua native environment '..entry[1]..'.'..entry[2]..' shares globals='..tostring(environment==globals))
     scan(environment,entry[1]..'.'..entry[2]..'.env',0)
    end
   end
  end
 end
 log('HUD Lua binding inventory: tables='..tables..' keys='..keys..' candidates='..hits..'; names only; no HUD state changed')
 return tables,keys,hits
end
-- One names-only search, including global/native Lua environments outside
-- stingray. Never call an unknown query or HUD function merely by its name.
function M.aim_interfaces(globals,sr,log)
 local seen={};local queue={{globals,'_G',0},{sr,'stingray',0}};local cursor,keys,hits=1,0,0
 local started=os.clock();local clipped=false
 local function enqueue(value,path,depth)
  if type(value)=='table'and not seen[value]then
   if #queue<256 then queue[#queue+1]={value,path,depth}else clipped=true end
  end
 end
 local update=rawget(globals,'update')
 if type(update)=='function'and type(getfenv)=='function'then local ok,env=pcall(getfenv,update);if ok then enqueue(env,'update.env',0)end end
 for _,pair in ipairs({{'Application','main_world'},{'Unit','camera'}})do
  local api=sr[pair[1]];local fn=type(api)=='table'and api[pair[2]]
  if type(fn)=='function'and type(getfenv)=='function'then local ok,env=pcall(getfenv,fn);if ok then enqueue(env,pair[1]..'.env',0)end end
 end
 while cursor<=#queue and keys<16384 and os.clock()-started<.004 do
  local row=queue[cursor];cursor=cursor+1;local value,path,depth=unpack(row)
  if not seen[value]then
   seen[value]=true
   for key,item in next,value do
    keys=keys+1;if keys>16384 then break end
    if type(key)=='string'and #key<=96 then
     local lower=key:lower();local name=path..'.'..key
     if lower:find('raycast',1,true)or lower:find('ray_cast',1,true)or lower:find('muzzle',1,true)or lower:find('crosshair',1,true)or lower:find('reticle',1,true)then
      if hits<64 then log('Aim interface candidate: '..name..' type='..type(item)..'; not invoked');hits=hits+1 end
     end
     if depth<2 and key~='_G'then enqueue(item,name,depth+1)end
    end
   end
  end
 end
 log(string.format('Aim interface inventory: tables=%d keys=%d hits=%d complete=%s elapsed_ms=%.3f; engine_calls=0 writes=0',cursor-1,keys,hits,tostring(cursor>#queue and keys<16384 and not clipped),(os.clock()-started)*1000))
 return hits
end
function M.run(sr,log)
 M.aim_interfaces(_G,sr,log)
 M.hud_environment(_G,log,sr)
 local namespaces={};for key,value in pairs(sr)do if type(key)=='string'and type(value)=='table'then namespaces[#namespaces+1]=key end end
 table.sort(namespaces);log('Windows engine namespaces: '..table.concat(namespaces,','))
 for _,name in ipairs({'Application','Unit','Mesh','MeshComponent','Network','GameSession','UnitSynchronizer','Actor','PhysicsWorld','AnimationBlenderBoneMode','AnimationBlenderRootMode',
  'AnimationBlenderComponent','AnimationStateMachineComponent','SceneGraphComponent','TransformComponent','UnitComponent',
  'Window','Input','Keyboard','Mouse','Camera','ShadingEnvironment','ShadingEnvironmentBlendComponent',
  'RenderDataComponent','DataComponent','EntityManager','RenderBuffer','Viewport','World','Level','Renderer','Material','RenderResource','WorldParameter','WorldParameters','components','ConsoleHelp','Gui'})do
  local api=sr[name];local members={}
  if type(api)=='table'then for key,value in pairs(api)do
   if type(key)=='string'and #key<=96 and #members<512 then members[#members+1]=key..':'..type(value)end
  end end
  table.sort(members);log('Windows engine API '..name..' ('..type(api)..'): '..table.concat(members,','))
 end
end
return M

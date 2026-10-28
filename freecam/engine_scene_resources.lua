-- DLL-free resource admission. Only linear_depth is CPU-read. Color layout is
-- proved from stock render_config bytes before binding the engine GPU handle.
local M={};local sequence=0
local function u(s,i)local a,b,c,d=s:byte(i,i+3);assert(d,'Truncated DDS');return a+b*256+c*65536+d*16777216 end
function M.inspect(header,size)
 assert(#header>=148 and header:sub(1,4)=='DDS 'and u(header,5)==124 and header:sub(85,88)=='DX10','Expected a DX10 DDS')
 local h,w,format=u(header,13),u(header,17),u(header,129)
 assert(w>0 and h>0 and w<=16384 and h<=16384 and u(header,133)==3 and u(header,141)==1 and u(header,137)==0,'Invalid render target shape')
 assert(u(header,25)<=1 and u(header,29)<=1,'Render target must have one slice and mip')
 local bytes=format==10 and 8 or (format==41 or format==28 or format==87 or format==24 or format==0)and 4
 assert(bytes and size==148+w*h*bytes,'DDS target layout or size differs')
 return{width=w,height=h,dxgi=format,mips=1,array=1}
end
function M.new(sr,mod,registry,local_probe)
 assert(mod.render_contract_verified==true,'Stock renderer contract unavailable; scene effects remain disabled')
 assert(registry.depth_binding==nil or registry.depth_binding=='private-local-v1','Unknown or withdrawn depth binding contract')
 assert(not local_probe or registry.depth_binding=='private-local-v1','Local binding probe requires the private shader')
 local self={};local cache,registry_checked;local generation=0;local owned={};local handles={}
 local folder=assert(os.getenv('APPDATA')):gsub('\\','/')..'/Arrowhead/Helldivers2'
 local function cleanup()
  for path in pairs(owned)do
   local ok,why=os.remove(path);if not ok then local f=io.open(path,'rb');if f then f:close();return false,why end end
   owned[path]=nil
  end
  return true
 end
 local function capture(name)
  assert(name=='linear_depth','Only the qualified linear-depth readback is permitted')
  sequence=sequence+1;local path=folder..'/wjl-target-'..sr.Application.process_id()..'-'..os.time()..'-'..sequence..'.dds'
  local f=io.open(path,'rb');if f then f:close();error('Target probe file already exists')end
  owned[path]=true
  local started=os.clock()
  assert(sr.Application.save_render_target(name,path)~=false,'Render target readback refused')
  f=assert(io.open(path,'rb'),'Render target readback not written');local size=f:seek('end');f:seek('set',0);local header=f:read(148);f:close()
  local info=M.inspect(header,size);assert(cleanup())
  mod.log(string.format('Engine target %s: %dx%d DXGI=%d; probe_ms=%.3f',name,info.width,info.height,info.dxgi,(os.clock()-started)*1000))
  return info
 end
 local function assets()
  if registry_checked then return true end
  local root=assert(mod.game_root,'WJL game-root proof unavailable')
  local expected=registry.hex:gsub('%x%x',function(h)return string.char(tonumber(h,16))end)
  -- A mod manager numbers archives that share a name, so ours is not always patch_0
  -- beside other mods. Find the patch whose bytes are exactly ours (stopping 64 numbers
  -- past the last one present, as Boot Mod Loader does).
  local base=assert(registry.name:match('^(.-)%.patch_%d+$'),'Owned shader registry name invalid')
  local found,present,last=nil,false,-1
  for n=0,1024 do
   if n-last>64 then break end
   local f=io.open(root..'/data/'..base..'.patch_'..n,'rb')
   if f then
    present,last=true,n
    local body=f:read(#expected+1);f:close()
    if body==expected then found=n;break end
   end
  end
  assert(present,'Owned shader registry archive missing')
  assert(found,'Installed shader registry differs from the packaged registry')
  if found>0 then mod.log('Owned shader registry found at '..base..'.patch_'..found)end
  registry_checked=true;return true
 end
 function self.registered(requested)
  assets()
  local overlay=mod.require('src/steam_scene_overlay.lua')
  local shader,material,sdr_shader,sdr_material=overlay.paths(registry.depth_binding)
  if requested~=nil then
   assert(requested==0x49a73b4c,'Unknown scene shader registration')
   shader,material=sdr_shader,sdr_material
  end
  assert(sr.Application.can_get('shader_library',shader)and sr.Application.can_get('material',material),'Owned scene assets are not loaded')
  return true
 end
 local function verify()
  local w,h=sr.Gui.resolution();local world=sr.Application.main_world()
  local hdr=sr.Application.render_setting('hdr_enabled');assert(type(hdr)=='boolean','HDR setting unavailable')
  local signature=w..'x'..h..'|'..tostring(hdr)
  -- Engine worlds all stringify as [World]. Compare the actual owner; handles
  -- and display dimensions may also be reused across world lifetimes.
  if cache and cache.world==world and cache.signature==signature then return cache end
  handles={};cache=nil;assert(cleanup())
  assert(world,'Main world unavailable')
  local d=capture('linear_depth');assert(d.dxgi==41,'Depth must be R32_FLOAT')
  -- The startup witness proves both Windows branches declare output_target
  -- as a separate RGBA16F target, scaled 1:1 from the back buffer. No pixel
  -- readback, capture, copy or save operation is submitted for this target.
  local c={width=w,height=h,dxgi=10,mips=1,array=1}
  -- Depth is observed live; color existence/type comes from the verified stock
  -- graph plus rejection of patch overrides. Never look up guessed names.
  handles.depth=assert(sr.Renderer.resource('linear_depth'))
  handles.color=assert(sr.Renderer.resource('output_target'))
  assert(handles.depth~=handles.color,'Color and depth handles alias')
  local white=sr.Application.render_setting('ui_brightness');assert(type(white)=='number'and white>0 and white<=10000,'UI white setting unavailable')
  generation=generation+1
  cache={key=generation..'|'..signature,signature=signature,depth=d,color=c,hdr=hdr,white=white,world=world}
  mod.log('Engine color binding admitted from the verified stock graph; no color readback')
  return cache
 end
 -- The exact registry selects a private local parameter; global candidates
 -- are withdrawn after their menu-open crashes. No marker keeps the old path.
 self.depth={binding_contract=registry.depth_binding}
 function self.depth.render_world()
  local scope=local_probe and local_probe.gui_world or 'ui'
  assert(scope=='ui'or scope=='main','Unknown local GUI world scope')
  return scope
 end
 if local_probe then
  local applied_world,applied_scope
  function self.depth.world_applied(scope,world)
   if applied_world~=world or applied_scope~=scope then
    applied_world,applied_scope=world,scope
    mod.log('Local world probe: applied '..scope..' world='..tostring(world))
   end
  end
 end
 local function binding_source()
  if not local_probe then return 'linear_depth' end
  assert(local_probe.source=='linear_depth' or local_probe.source=='output_target' or
   local_probe.source=='atlas-string' or local_probe.source=='atlas-id' or local_probe.source=='depth-id','Unknown local binding probe source')
  return local_probe.source
 end
 function self.depth.available()local ok,value=pcall(verify);if not ok then cleanup()end;return ok,not ok and tostring(value)or nil end
 function self.depth.get()local c=verify();self.depth.binding_identity=c.key..'|'..tostring(handles.depth)..'|'..binding_source();return handles.depth end
 function self.depth.bind(material,slot,resource)
  assert(slot=='diffuse_map' and resource==handles.depth,'Depth binding identity differs')
  local parameter=registry.depth_binding=='private-local-v1'and'wjl_scene_depth'or slot
  local source=binding_source()
  local bind_resource=source=='output_target'and handles.color or resource
  if source=='atlas-id'or source=='depth-id'then
   -- 0x9c7af650 is the existing private shader's parameter ID, verified in
   -- its declaration records. Same boxed-slot representation as the live font.
   parameter=sr.IdString64.from_hex('9c7af65000000000')
  end
  local result
  if source=='atlas-string'or source=='atlas-id'then
   local atlas=sr.IdString64.from_hex('d1ebb991c79f934b')
   assert(sr.Application.can_get('texture',atlas),'Known HUD atlas unavailable')
   result=sr.Material.set_texture(material,parameter,atlas)~=false
  else result=sr.Material.set_resource(material,parameter,bind_resource)~=false end
  if local_probe then mod.log('Local resource probe: bound '..source..' to '..tostring(parameter)..'; accepted='..tostring(result))end
  return result
 end
 function self.color()
  local c=verify()
  return true,{format=19,width=c.color.width,height=c.color.height,mips=1,array=1,resource=handles.color,backing=c.key,id=tostring(handles.color),hdr_enabled=c.hdr,ui_brightness=c.white,proof='stock graph witness; depth DDS observed; GPU-only color binding'}
 end
 function self.focus_descriptor()
  local c=verify();return true,{format=1,kind=2,mips=1,array=1,width=c.depth.width,height=c.depth.height,identity=c.key..'|linear_depth',display_identity=c.key}
 end
 function self.release()
  -- Caller destroys all overlay primitives/materials before releasing resources.
  cache=nil;handles={};return cleanup()
 end
 return self
end
return M

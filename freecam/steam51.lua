-- Ordinary Lua 5.1 feature graph; no FFI. Enemy behavior needs FFI and is omitted.
local runtime
local function stop()
 if not runtime then return true end
 local ok,why=runtime.dispose();if not ok then return false,why end
 if rawget(_G,'DBF_PHOTO_MODE_OWNER')==runtime then rawset(_G,'DBF_PHOTO_MODE_OWNER',nil)end
 runtime=nil;return true
end
return {live_lua_api=1,name='War Journalist',
 on_enable=function()
  assert(_VERSION=='Lua 5.1','Unsupported Lua runtime')
  local loader=assert(rawget(_G,'LiveLuaLoader'),'Live Lua Loader is required')
  assert(not rawget(_G,'DBF_PHOTO_MODE_OWNER'),'Another Photo Mode runtime is already active')
  local deps={ragdoll=mod.require('src/ragdoll_pause.lua'),handycam=mod.require('src/steam_handycam.lua'),hud=mod.require('src/steam_hud.lua'),input_policy={require_keyboard=true},director=mod.require('src/director.lua'),bookmark=mod.require('src/steam_bookmark.lua'),subject_backend=mod.require('src/subject_backend.lua'),subject_visibility=mod.require('src/subject_visibility.lua'),input_cleanup=mod.require('src/input_cleanup.lua'),camera=mod.require('src/steam_camera.lua'),input=mod.require('src/steam_input.lua'),
   path=mod.require('src/steam_path.lua'),decorative_overlay=mod.require('src/steam_overlay.lua'),
   lighting=mod.require('src/steam_lighting.lua'),lights=mod.require('src/photo_lights.lua'),
   light_presets=mod.require('src/photo_light_presets.lua'),
   gizmos=mod.require('src/photo_light_gizmos.lua'),
   font=mod.require('src/vendor/font.lua'),core=mod.require('src/vendor/core.lua'),store=mod.require('src/vendor/store.lua'),view=mod.require('src/vendor/view.lua'),
   options=mod.require('src/photo_options.lua'),menu=mod.require('src/photo_menu.lua'),legend=mod.require('src/control_legend.lua'),
   composition=mod.require('src/composition.lua'),look=mod.require('src/look.lua'),lens=mod.require('src/lens.lua'),
   pick=mod.require('src/steam_pick.lua')}
  deps.load_scene=function(sr)
   local host_native=mod.require('src/host_native.lua');local memory=host_native.memory();local bridge=host_native.open()
   local open,why=package.loadlib(mod.dir..'/port51/hd2_nativeinfo_4aab2adfbc4090d6.dll','luaopen_hd2_nativeinfo');assert(open,why);local native=open()
   local resources=mod.require('src/steam_scene_resources.lua').new(sr,memory,bridge)
   resources.depth.bind=function(material,slot,resource)assert(slot=='diffuse_map');return native.depth_bind(material,resource)end
   local overlay=mod.require('src/steam_scene_overlay.lua').new(sr,resources.depth,true,{present=resources.registered},resources.color)
   local sampler,reason=mod.require('src/steam_focus_sampler.lua').new(sr,resources.depth,function()
    assert(memory.function_address(sr.Application.save_render_target)==memory.exe+0x3da140,'Depth readback binding differs')
    assert(memory.read(memory.exe+0x3da140,8)=='\072\139\209\233\104\247\255\255','Depth readback dispatch differs')
    local target=resources.target(0x9b8038e0);local display=resources.target(0x2b269c03)
    target.identity=table.concat({target.resource,target.backing,target.id},':');target.display_identity=table.concat({display.resource,display.backing,display.id,display.width,display.height},':')
    return true,target
   end,{now=sr.Application.time_since_launch,pid=native.focus_cache(),mkdir=function()native.focus_cache();return true end})
   assert(sampler,reason)
   return mod.require('src/steam_scene.lua').new(sr,resources,overlay,sampler,sr.Application.time_since_launch)
  end
  deps.load_hover=function(sr)
   local memory=mod.require('src/host_native.lua').memory()
   local clock=mod.require('src/steam_update_clock.lua').new(sr,memory.world_address)
   local backend=mod.require('src/steam_hover_backend.lua').new(sr,nil,clock.sample)
   return mod.require('src/steam_hover_pause.lua').new(backend,mod.require('src/hover_pause.lua'),clock,sr.Application.time_since_launch)
  end
  deps.load_native_lens=function(sr)
   return mod.require('src/steam_native_lens.lua').new(sr,mod.require('src/host_native.lua'),mod.require('src/steam_lens_model.lua'),deps.lens,'hd2_nativeinfo_3139cc5f8ecb4078.dll',mod.dir)
  end
  -- Pure retained geometry, loaded once at entry with the legacy picker indices.
  deps.composition.logo_art=mod.require('src/assets/logo_art.lua')
  deps.composition.logo_art[2]=mod.require('src/assets/helldiver_crest.lua')
  -- Optional documented shared API. Older loaders keep the working camera;
  -- they never fall back to an unqualified in-game capture or helper pipe.
  local capture=loader.capture_service
  local local_data=os.getenv('LOCALAPPDATA')
  if capture and type(capture.output_directory)=='string'and type(local_data)=='string'then
   local linux=mod.require('src/linux_capture.lua')
   if type(linux.new)=='function'then
    local backend=linux.new(local_data..'/LLL/Helldivers2/LinuxCapture',capture.output_directory,capture.new_job_token)
    if backend then capture=backend;mod.log('Linux game-window PNG capture selected')end
   end
  end
  local caps=type(capture)=='table'and capture.capabilities
  -- Development qualification is tied to the factory-lifetime repair. Do not
  -- silently re-enable the known-crashing API v1 helper after a loader rollback.
  local revision=loader.capabilities.revision
  local capture_revision=revision=='R33-steam-screenshots-factoryfix-candidate'or revision=='R34-steam-lua51-preview.1'or revision=='R35-26088801-cffi-dev.2'or revision=='R35-26088801-cffi-insert-fix.2'
  local ready=capture_revision and
   type(capture)=='table'and capture.version==1 and type(caps)=='table'and
   caps.async==true and caps.game_window==true and caps.format=='png'and caps.color_space=='sdr'and caps.max_jobs==1 and
   type(capture.output_directory)=='string'and #capture.output_directory>0
  for _,name in ipairs({'new_job_token','request','status','cancel'})do
   if not ready or type(capture[name])~='function'then ready=false;break end
  end
  if ready then deps.capture=mod.require('src/steam_capture.lua');deps.capture_backend=capture end
  -- Development admission: the R34 private Unit transform roundtrip restored
  -- all 12 numeric matrix elements exactly, including after update_unit.
  -- Subject appearance remains a separate visual test. Native modules and
  -- the catalog load only on explicit session enable, never on entry/tick.
  local subject_qualification=revision=='R34-steam-lua51-preview.1'and'R34-unit-pose12-private-roundtrip-20261020-v1'or'R35-unit-pose12-private-roundtrip-20261023-v1'
  if subject_qualification and(revision=='R34-steam-lua51-preview.1'or revision=='R35-26088801-cffi-insert-fix.2')then
   deps.load_subject=function(sr,is_frozen,subject_backend)
    local function pack(...)return{n=select('#',...),...}end
    local values=pack(sr.Network.game_session())
    if values.n~=1 or type(values[1])~='userdata'then return nil,'Subject session unavailable'end
    local native,why=mod.require('src/steam_subject_native.lua').new(sr,{qualified=true,contract='unit-pose-sync-v1',
     qualification=subject_qualification,session=values[1],
     cape_reader=subject_backend,cape_factory=subject_backend and mod.require('src/subject_poses.lua').capes})
    if not native then return nil,why end
    return mod.require('src/steam_subject.lua').new(native,mod.require('src/assets/steam_subject_poses.lua'),is_frozen)
   end
  end
  -- The engine clip flag alone does not retain Wine Wayland confinement
  -- when its mouse focus is yielded to our shared camera/menu lease.
  local pointer_native
  deps.input_policy.pointer_clip=function(active)
   if not pointer_native then
    if not active then return true end
    local open,why=package.loadlib(mod.dir..'/port51/hd2_nativeinfo_5e39eeeeb76b863a.dll','luaopen_hd2_nativeinfo');assert(open,why)
    pointer_native=assert(open());assert(type(pointer_native.pointer_clip)=='function','Pointer confinement bridge unavailable')
   end
   return pointer_native.pointer_clip(active and 1 or 0)
  end
  runtime=mod.require('src/steam_runtime.lua').new(mod,assert(stingray),deps,assert(loader.input_service,'Update LLL for its shared input service'))
  rawset(_G,'DBF_PHOTO_MODE_OWNER',runtime)
  mod.log('Photo Mode ready on '..tostring(rawget(_G,'jit')and jit.version or _VERSION))
 end,
 on_update=function()if runtime then runtime.tick()end end,
 on_disable=stop,
 on_cleanup_poll=stop}

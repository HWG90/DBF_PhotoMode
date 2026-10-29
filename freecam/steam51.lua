-- Ordinary Lua 5.1 feature graph; no FFI. Enemy behavior needs FFI and is omitted.
local runtime,selftest,entry,visibility_probe
local function stop()
 if runtime then
  local ok,why=runtime.dispose();if not ok then return false,why end
  if rawget(_G,'DBF_PHOTO_MODE_OWNER')==runtime then rawset(_G,'DBF_PHOTO_MODE_OWNER',nil)end
  runtime=nil;selftest=nil
 end
 if visibility_probe then
  local ok,why=visibility_probe.release();if not ok then return false,why end
  visibility_probe=nil
 end
 return true
end
entry={live_lua_api=1,name='War Journalist',
 on_enable=function()
  assert(_VERSION=='Lua 5.1','Unsupported Lua runtime')
  -- Archive hosts without LLL (Boot Mod Loader) hand in an engine host with the same fields.
  local loader=assert(mod.host_loader or rawget(_G,'LiveLuaLoader'),'Live Lua Loader or Boot Mod Loader is required')
  local engine_host=loader.engine_input==true
  assert(not rawget(_G,'DBF_PHOTO_MODE_OWNER'),'Another Photo Mode runtime is already active')
  local deps={ragdoll=mod.require('src/ragdoll_pause.lua'),handycam=mod.require('src/steam_handycam.lua'),hud=mod.require('src/steam_hud.lua'),input_policy={require_keyboard=not engine_host or loader.require_keyboard==true},director=mod.require('src/director.lua'),bookmark=mod.require('src/steam_bookmark.lua'),subject_backend=mod.require('src/subject_backend.lua'),subject_visibility=mod.require('src/subject_visibility.lua'),input_cleanup=mod.require('src/input_cleanup.lua'),camera=mod.require('src/steam_camera.lua'),input=mod.require('src/steam_input.lua'),
   path=mod.require('src/steam_path.lua'),decorative_overlay=mod.require('src/steam_overlay.lua'),
   lighting=mod.require('src/steam_lighting.lua'),lights=mod.require('src/photo_lights.lua'),
   light_presets=mod.require('src/photo_light_presets.lua'),
   gizmos=mod.require('src/photo_light_gizmos.lua'),
   font=mod.require('src/vendor/font.lua'),core=mod.require('src/vendor/core.lua'),store=mod.require('src/vendor/store.lua'),view=mod.require('src/vendor/view.lua'),
   options=mod.require('src/photo_options.lua'),menu=mod.require('src/photo_menu.lua'),legend=mod.require('src/control_legend.lua'),
   composition=mod.require('src/composition.lua'),look=mod.require('src/look.lua'),lens=mod.require('src/lens.lua'),
   pick=mod.require('src/steam_pick.lua')}
  deps.diagnostics=engine_host and not mod.release_mode
  deps.engine_time_only=engine_host
  if engine_host then deps.freeze_rate,deps.freeze_rate_sample=mod.require('src/windows_hover_freeze.lua').new(stingray,mod.log,true)end
  if engine_host then
   deps.subject_tracking=mod.require('src/windows_subject_tracking.lua')
   deps.pov_visibility=mod.require('src/windows_pov_visibility.lua')
   deps.mesh_visibility=mod.require('src/windows_mesh_visibility.lua')
  end
  -- Windows CRT clock advances within a Lua callback; the engine's launch
  -- time may be latched for that entire frame. Do not use POSIX CPU time.
  if engine_host and package.config and package.config:sub(1,1)=='\\'then deps.operation_clock=os.clock end
  if engine_host then
   local font_factory=deps.font
   deps.font={new=function()
    local source=font_factory.new(nil,nil,nil,true,mod.log);local resolve=source.resolve;local reported
    source.resolve=function(sr)
     local descriptor=resolve(sr)
     if descriptor and reported~=descriptor.font then reported=descriptor.font;mod.log('Game font resolved from stock resources: '..descriptor.font)end
     return descriptor
    end
    return source
   end}
  end
  -- A host's bindings helper (Boot Mod Loader's Mod Bindings Menu) holds our keys.
  if loader.bindings then deps.hosted_bindings={api=loader.bindings,window=loader.bindings.window,factory=mod.require('src/steam_bindings.lua')}end
  deps.load_scene=function(sr)
   if engine_host then
    local resources=mod.require('src/engine_scene_resources.lua').new(sr,mod,mod.require('src/engine_scene_registry.lua'),selftest and selftest.local_binding_probe)
    local overlay=mod.require('src/steam_scene_overlay.lua').new(sr,resources.depth,true,{present=resources.registered},resources.color)
    local folder=assert(os.getenv('APPDATA')):gsub('\\','/')..'/Arrowhead/Helldivers2'
    local sampler,why=mod.require('src/steam_focus_sampler.lua').new(sr,resources.depth,resources.focus_descriptor,
     {now=sr.Application.time_since_launch,measure=deps.operation_clock,pid=sr.Application.process_id(),directory=folder,mkdir=function(path)return path==folder end,
      auto_budget_ms=8,log=mod.log})
    assert(sampler,why)
    local scene=mod.require('src/steam_scene.lua').new(sr,resources,overlay,sampler,sr.Application.time_since_launch)
    local release=scene.release
    scene.release=function()local ok,why=release();if not ok then return false,why end;return resources.release()end
    return scene
   end
   local host_native=mod.require('src/host_native.lua');local memory=host_native.memory();local bridge=host_native.open()
   local open,why=package.loadlib(host_native.library('hd2_nativeinfo_4aab2adfbc4090d6.dll'),'luaopen_hd2_nativeinfo');assert(open,why);local native=open()
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
  if not engine_host then deps.load_hover=function(sr)
   local memory=mod.require('src/host_native.lua').memory()
   local clock=mod.require('src/steam_update_clock.lua').new(sr,memory.world_address)
   local backend=mod.require('src/steam_hover_backend.lua').new(sr,nil,clock.sample)
   return mod.require('src/steam_hover_pause.lua').new(backend,mod.require('src/hover_pause.lua'),clock,sr.Application.time_since_launch)
  end end
  if engine_host then deps.load_native_lens=function(sr)
   return mod.require('src/windows_dof_override.lua').new(sr,mod.log,deps.lens,mod.require('src/windows_native_dof.lua'))
  end
  else deps.load_native_lens=function(sr)
   return mod.require('src/steam_native_lens.lua').new(sr,mod.require('src/host_native.lua'),mod.require('src/steam_lens_model.lua'),deps.lens,'hd2_nativeinfo_3139cc5f8ecb4078.dll')
  end end
  if engine_host then deps.camera_signals=mod.require('src/windows_camera_signals.lua');deps.handycam_ads=mod.require('src/windows_handycam_ads.lua')end
  deps.engine_shader_lens=engine_host
  -- Pure retained geometry, loaded once at entry with the legacy picker indices.
  deps.composition.logo_art=mod.require('src/assets/logo_art.lua')
  deps.composition.logo_art[2]=mod.require('src/assets/helldiver_crest.lua')
  -- Optional documented shared API. Older loaders keep the working camera;
  -- they never fall back to an unqualified in-game capture or helper pipe.
  local capture=loader.capture_service
  local local_data=os.getenv('LOCALAPPDATA')
  -- Boot Mod Loader has no capture service. The addon's own path comes first, on Windows
  -- and Proton alike: the engine writes a DDS and WJL converts it to a PNG. Without WJL,
  -- the Linux host worker (the one LLL uses) where it runs, else the engine's DDS.
  if engine_host and not capture then
   local function writable(dir)
    if type(dir)~='string'then return false end
    local probe=dir..'/.wj-probe';local f=io.open(probe,'wb');if not f then return false end;f:close();os.remove(probe);return true
   end
   local lll=type(local_data)=='string'and local_data:gsub('\\','/')..'/LLL/Helldivers2'
   local issued=os.time()%1000000000
   local worker={output_directory=lll and lll..'/Screenshots',new_job_token=function()issued=issued+1;return'lll-shot:war_journalist:'..issued end}
   local profile=os.getenv('USERPROFILE');local game=os.getenv('APPDATA')
   profile=type(profile)=='string'and profile:gsub('\\','/')..'/Pictures';game=type(game)=='string'and game:gsub('\\','/')..'/Arrowhead/Helldivers2'
   local folder=writable(worker.output_directory)and worker.output_directory or writable(profile)and profile or writable(game)and game
   local made,png=false,nil
   if folder and type(loader.helper_screenshots)=='function'then made,png=pcall(loader.helper_screenshots,folder)end
   if made and png then
    capture=png;mod.log('WJL PNG screenshots selected (engine DDS converted by WJL): '..folder)
   else
    if png~=nil and not made then mod.log('WJL PNG screenshots unavailable: '..tostring(png))end
    local linux=lll and mod.require('src/linux_capture.lua')
    local backend=linux and type(linux.new)=='function'and linux.new(lll..'/LinuxCapture',worker.output_directory,worker.new_job_token)
    if backend then capture=backend;mod.log('Linux game-window PNG capture selected')
    else
     capture=folder and mod.require('src/engine_capture.lua').new(stingray,folder)or nil
     if capture then mod.log('Engine DDS capture selected: '..folder)end
    end
   end
  end
  if capture and not engine_host and type(capture.output_directory)=='string'and type(local_data)=='string'then
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
  local capture_revision=revision=='R33-steam-screenshots-factoryfix-candidate'or revision=='R34-steam-lua51-preview.1'or revision=='R35-26088801-cffi-dev.2'or revision=='R35-26088801-cffi-insert-fix.2'or engine_host
  local ready=capture_revision and
   type(capture)=='table'and capture.version==1 and type(caps)=='table'and
   caps.async==true and caps.max_jobs==1 and(caps.game_window==true and caps.format=='png'and caps.color_space=='sdr'or engine_host and(caps.format=='dds'or caps.format=='png'))and
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
  if subject_qualification and(revision=='R34-steam-lua51-preview.1'or revision=='R35-26088801-cffi-insert-fix.2'or engine_host)then
   deps.load_subject=function(sr,is_frozen,subject_backend)
    local function pack(...)return{n=select('#',...),...}end
    local values=pack(sr.Network.game_session())
    if values.n~=1 or type(values[1])~='userdata'then return nil,'Subject session unavailable'end
    local native,why=mod.require('src/steam_subject_native.lua').new(sr,{qualified=true,contract='unit-pose-sync-v1',
     qualification=subject_qualification,session=values[1],measure=deps.operation_clock,log=mod.log,
     cape_reader=subject_backend,cape_factory=subject_backend and mod.require('src/subject_poses.lua').capes,
     selected_cape=engine_host and mod.require('src/windows_freeze_cape.lua').new(sr,deps.pov_visibility.association(sr))or nil})
    if not native then return nil,why end
    return mod.require('src/steam_subject.lua').new(native,mod.require('src/assets/steam_subject_poses.lua'),is_frozen)
   end
  end
  -- The engine clip flag alone does not retain Wine Wayland confinement
  -- when its mouse focus is yielded to our shared camera/menu lease.
  -- Engine input moves a virtual cursor: nothing to confine, and native Windows refuses the DLL.
  local pointer_native
  if not engine_host then deps.input_policy.pointer_clip=function(active)
   if not pointer_native then
    if not active then return true end
    local open,why=package.loadlib(mod.require('src/host_native.lua').library('hd2_nativeinfo_5e39eeeeb76b863a.dll'),'luaopen_hd2_nativeinfo');assert(open,why)
    pointer_native=assert(open());assert(type(pointer_native.pointer_clip)=='function','Pointer confinement bridge unavailable')
   end
   return pointer_native.pointer_clip(active and 1 or 0)
  end end
  if engine_host and not mod.release_mode then
   local inventory=mod.require('src/windows_api_inventory.lua')
   if type(inventory.run)=='function'then inventory.run(stingray,mod.log)end
  end
  if engine_host and type(mod.config_dir)=='string'then
   local skeleton=mod.require('src/windows_freeze_pose_probe.lua')
   -- Pinning the animation (options.pin_animation) made a body frozen while running worse:
   -- the game reset it every frame and ~46 bones were fought per frame (live). Off.
   deps.freeze_pose_hold=skeleton.new(stingray,mod.log,deps.operation_clock or os.clock,
    {continuous=true,exclude_cape=true,claim_transfer=true})
   mod.log('Freeze skeleton hold: body-only coherent hold after game render; own ignore mode until Resume; cape bones and separate cape units untouched; hoverpack fallback retained')
   if not mod.release_mode then
   local physics_probe=mod.require('src/windows_freeze_physics_probe.lua')
   if physics_probe.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)then
    deps.freeze_physics_probe=physics_probe.new(stingray,mod.log,deps.operation_clock or os.clock)
    mod.log('Freeze physics probe armed: explicit six-second physics off/on button; two trials maximum; no transform writes')
   end
   local bone_probe=mod.require('src/windows_freeze_bone_probe.lua')
   if bone_probe.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)then
    deps.freeze_bone_probe=bone_probe.new(mod.log,deps.operation_clock or os.clock)
    mod.log('Freeze bone probe armed: explicit Subject test button; three trials maximum; no root transforms')
   end
   local movement=mod.require('src/windows_movement_probe.lua')
   if type(movement.consume)=='function'and movement.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)then
    deps.movement_probe=movement.new(stingray,mod.log,deps.operation_clock or os.clock)
    mod.log('Movement probe armed: one move_angle write per A/D/S trial; active unfrozen Handycam only; restoration and no reapply')
   end
   local visibility_test=mod.require('src/windows_visibility_probe.lua')
   local visibility_mode=type(visibility_test.consume)=='function'and visibility_test.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)
   if visibility_mode then
    visibility_probe=visibility_test.new(stingray,mod.log,deps.operation_clock or os.clock,visibility_mode,mod.require('src/windows_mesh_visibility.lua'))
   end
   -- Body-only skeleton hold; authored poses keep their separate solver.
   -- No cape correction or body-flip test.
   local observer=mod.require('src/windows_freeze_observer.lua')
   if type(observer.consume)=='function'and observer.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)then
    deps.freeze_observer=observer.new(stingray,stingray.Application.time_since_launch,deps.operation_clock or os.clock,mod.log,mod.require('src/windows_animation_source.lua'))
    mod.log('Freeze observer armed for four completed captures / sixteen manual Freeze attempts; read-only; no automatic menu or time changes')
   end
   local fog=mod.require('src/windows_native_fog_probe.lua')
   if type(fog.consume)=='function'and fog.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)then
    deps.fog_probe=fog.new(stingray,stingray.Application.time_since_launch,deps.operation_clock or os.clock,mod.log)
    mod.log('Native fog probe armed; one read-only inventory on manual Photo Mode entry; no rendering changes')
   end
   local probe=mod.require('src/windows_native_dof_selftest.lua')
   local test=probe.consume(mod.config_dir,type(stingray.Application.process_id)=='function'and stingray.Application.process_id()or 0)
   if test then
    deps.selection_probe=test=='selection-depth-v1'
    if test=='private-depth-v1'or test=='local-depth-control-v1'or test=='local-texture-control-v1'or test=='local-world-control-v1'then assert(mod.require('src/engine_scene_registry.lua').depth_binding=='private-local-v1','Private depth assets required for this test')end
    if test=='entity-getter-v1'or test=='entity-owner-v1'then deps.load_native_lens=function(sr)return mod.require('src/windows_native_dof.lua').new(sr,mod.log,test)end end
    if test=='native-override-v1'then deps.load_native_lens=function(sr)return mod.require('src/windows_dof_override.lua').new(sr,mod.log,deps.lens,mod.require('src/windows_native_dof.lua'))end end
    local readiness
    if test=='entity-owner-v1'or test=='native-override-v1'or test=='selection-depth-v1'or test=='local-depth-control-v1'or test=='local-texture-control-v1'or test=='local-world-control-v1'then readiness=function()return mod.require('src/windows_native_dof.lua').new(stingray,mod.log,'entity-getter-v1')end end
    selftest=probe.new(stingray,mod.log,test,readiness);deps.store=selftest.store(deps.store)
   end
  end
  end
  runtime=mod.require('src/steam_runtime.lua').new(mod,assert(stingray),deps,assert(loader.input_service,'Update LLL for its shared input service'))
  rawset(_G,'DBF_PHOTO_MODE_OWNER',runtime)
  mod.log('Photo Mode ready on '..tostring(rawget(_G,'jit')and jit.version or _VERSION))
 end,
 on_update=function()
  if visibility_probe then visibility_probe.tick()end
  if runtime then runtime.tick()end
  if runtime and selftest then
   local ok,done=pcall(selftest.tick,runtime)
   if not ok then selftest.abort(runtime,done)
   elseif done then local closed,why=stop();if closed then entry.on_enable()else mod.log('Native DoF self-test: runtime retirement pending: '..tostring(why))end end
  end
 end,
 on_disable=stop,
 on_cleanup_poll=stop}
return entry

-- Separate module graph: the Lua 5.1 runtime must never load the FFI bundle.
local runtime
return {live_lua_api=1,name='War Journalist — Lua 5.1 development port',
 on_enable=function()
  assert(_VERSION=='Lua 5.1','Unsupported Lua runtime')
  local loader=assert(rawget(_G,'LiveLuaLoader'),'Live Lua Loader is required')
  assert(loader.capabilities and loader.capabilities.native_ffi==false,'Use the Lua 5.1 loader package')
  assert(not rawget(_G,'DBF_PHOTO_MODE_OWNER'),'Another Photo Mode runtime is already active')
  local deps={camera=mod.require('src/steam_camera.lua'),input=mod.require('src/steam_input.lua'),
   path=mod.require('src/steam_path.lua'),decorative_overlay=mod.require('src/steam_overlay.lua'),
   lighting=mod.require('src/steam_lighting.lua'),lights=mod.require('src/photo_lights.lua'),
   light_presets=mod.require('src/photo_light_presets.lua'),
   gizmos=mod.require('src/photo_light_gizmos.lua'),
   core=mod.require('src/vendor/core.lua'),store=mod.require('src/vendor/store.lua'),view=mod.require('src/vendor/view.lua'),
   options=mod.require('src/photo_options.lua'),menu=mod.require('src/photo_menu.lua'),legend=mod.require('src/control_legend.lua'),
   composition=mod.require('src/composition.lua'),look=mod.require('src/look.lua'),lens=mod.require('src/lens.lua')}
  -- Pure retained geometry, loaded once at entry with the legacy picker indices.
  deps.composition.logo_art=mod.require('src/assets/logo_art.lua')
  deps.composition.logo_art[2]=mod.require('src/assets/helldiver_crest.lua')
  -- Optional documented shared API. Older loaders keep the working camera;
  -- they never fall back to an unqualified in-game capture or helper pipe.
  local capture=loader.capture_service
  local caps=type(capture)=='table'and capture.capabilities
  -- Development qualification is tied to the factory-lifetime repair. Do not
  -- silently re-enable the known-crashing API v1 helper after a loader rollback.
  local revision=loader.capabilities.revision
  local capture_revision=revision=='R33-steam-screenshots-factoryfix-candidate'or revision=='R34-steam-lua51-preview.1'
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
  local subject_qualification='R34-unit-pose12-private-roundtrip-20261020-v1'
  if subject_qualification and revision=='R34-steam-lua51-preview.1'then
   deps.load_subject=function(sr,is_frozen)
    local function pack(...)return{n=select('#',...),...}end
    local values=pack(sr.Network.game_session())
    if values.n~=1 or type(values[1])~='userdata'then return nil,'Subject session unavailable'end
    local native,why=mod.require('src/steam_subject_native.lua').new(sr,{qualified=true,contract='unit-pose-sync-v1',
     qualification=subject_qualification,session=values[1]})
    if not native then return nil,why end
    return mod.require('src/steam_subject.lua').new(native,mod.require('src/assets/steam_subject_poses.lua'),is_frozen)
   end
  end
  runtime=mod.require('src/steam_runtime.lua').new(mod,assert(stingray),deps,assert(loader.input_service,'Update LLL for its shared input service'))
  rawset(_G,'DBF_PHOTO_MODE_OWNER',runtime)
  mod.log('Lua 5.1 camera/menu candidate ready; native feature ports remain in progress')
 end,
 on_update=function()if runtime then runtime.tick()end end,
 on_disable=function()
  if not runtime then return true end
  local ok,why=runtime.dispose();if not ok then return false,why end
  if rawget(_G,'DBF_PHOTO_MODE_OWNER')==runtime then rawset(_G,'DBF_PHOTO_MODE_OWNER',nil)end
  runtime=nil;return true
 end}

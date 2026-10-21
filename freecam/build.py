"""Build the self-contained Photo Mode release; never installs."""
from pathlib import Path
import argparse, hashlib, json, os, re, struct, sys, zipfile
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'tools'))
import lua_archive
import photo_assets

def capture_library_name():
    name=json.loads((ROOT/'vendor/PROVENANCE.json').read_text()).get('capture_library','PhotoCapture64.dll')
    if not re.fullmatch(r'PhotoCapture(?:64|_[0-9a-f]{12,64})\.dll',name):raise ValueError('Invalid owned screenshot library name')
    return name

def studio_source(dof_candidate=False,scene_candidate=False,native_candidate=False,combined_scene_candidate=False,camera_lifecycle=''):
    """Expand owned Photo studio features without reading or patching a camera controller."""
    if combined_scene_candidate and not dof_candidate:raise ValueError('Combined compositor requires DoF factory')
    if combined_scene_candidate and scene_candidate:raise ValueError('Combined compositor replaces the separate scene pass')
    controller=(ROOT/'controller.lua').read_text(encoding='utf-8')
    hook="""
rawset(_G,'DBF_PHOTO_SAFE_EFFECTS',true)
rawset(_G,'DBF_PHOTO_RENDER_VERSION',6)
local DBF_FREECAM_LOOK=(function()
__CAMERA_LOOK__
end)()
local DBF_SIMULATION_BACKEND=(function()
__SIMULATION_BACKEND__
end)().new(sr)
H.dbf_camera_ownership=assert(rawget(_G,'DBF_PHOTO_CAMERA_OWNERSHIP'),'Photo camera ownership service unavailable')
do
 local backend=(function()
__HOVER_PAUSE_BACKEND__
end)()
 local guard=(function()
__HOVER_PAUSE__
end)()
 local ok,value=pcall(backend.new,sr)
 H.dbf_hover_pause_backend=ok and value or nil
 H.dbf_hover_pause=guard.new(H.dbf_hover_pause_backend)
 if not ok then log('Hover pause reader unavailable: '..tostring(value))end
end
local DBF_PLAYER_FREEZE=(function()
__SIMULATION__
end)().new(sr,function()return anchor and anchor.unit,target and target.world,anchor~=nil and not anchor.spectate and not known_body(anchor.unit) and not SPEC.active and not SAFE.gate end,DBF_SIMULATION_BACKEND,H.dbf_hover_pause)
local DBF_PHOTO_OPTIONS=(function()
__PHOTO_OPTIONS__
end)()
DBF_PHOTO_OPTIONS.faction_art=(function()
__FACTION_ART__
end)()
H.dbf_game_chat=(function()
__CHAT_CONTEXT__
end)().new(nil,sr.Window)
local DBF_PHOTO_LENS=(function()
__PHOTO_LENS__
end)()
local DBF_PHOTO_COMPOSITION=(function()
__PHOTO_COMPOSITION__
end)()
DBF_PHOTO_COMPOSITION.logo_art=(function()
__LOGO_ART__
end)()
DBF_PHOTO_COMPOSITION.logo_art[2]=(function()
__HELLDIVER_CREST__
end)()
local DBF_PHOTO_POSTFX=(function()
__PHOTO_POSTFX__
end)()
local DBF_PHOTO_PROFILE=(function()
__PHOTO_PROFILE__
end)()
DBF_PHOTO_PROFILE.camera_factory=(function()
__CAMERA_PROFILE__
end)()
local DBF_PHOTO_HUD=(function()
__PHOTO_HUD__
end)().new()
__PHOTO_DOF_CANDIDATE__
local DBF_PHOTO_RUNTIME=(function()
__PHOTO_RUNTIME__
end)().new(sr,DBF_PHOTO_LENS,DBF_PHOTO_COMPOSITION,DBF_PHOTO_POSTFX,log,DBF_PHOTO_HUD,DBF_PHOTO_PROFILE__PHOTO_DOF_ARGUMENT____PHOTO_SCENE_ARGUMENT__)
local DBF_PHOTO_MENU=(function()
__PHOTO_MENU__
end)()
DBF_PHOTO_MENU.legend_factory=(function()
__CONTROL_LEGEND__
end)()
DBF_PHOTO_MENU.gizmo_factory=(function()
__LIGHT_GIZMOS__
end)()
local DBF_PHOTO_SCREENSHOT=(function()
__SCREENSHOT__
end)()
local DBF_PHOTO_SCREENSHOT_BACKEND=(function()
__SCREENSHOT_BACKEND__
end)()
local DBF_SCREENSHOTS
do
 local ok,value=pcall(function()
  local root=assert(rawget(_G,'DBF_PHOTO_PACKAGE_ROOT'),'Photo package path unavailable');local folder=root..'/Screenshots'
  local convert=DBF_PHOTO_SCREENSHOT.native_converter(root..'/__CAPTURE_LIBRARY__',folder)
  local backend=assert(DBF_PHOTO_SCREENSHOT_BACKEND.new(sr))
  return DBF_PHOTO_SCREENSHOT.new(backend,convert,folder,log)
 end)
 if ok then DBF_SCREENSHOTS=value else log('Screenshot capture unavailable: '..tostring(value))end
end
local DBF_FOCUS_SAMPLER
do
 local depth=(function()
__FOCUS_DEPTH__
end)()
 local focus=(function()
__FOCUS_SAMPLER__
end)()
 local ok,value=pcall(function()return focus.new(sr,depth.new(sr))end)
 if ok then DBF_FOCUS_SAMPLER=value else log('Autofocus unavailable: '..tostring(value))end
end
local DBF_PHOTO_LIGHTS=(function()
__PHOTO_LIGHTS__
end)().new(sr,log)
DBF_PHOTO_LIGHTS.scene_context=function()return target and target.world,WORLD.epoch end
do
 local presets=(function()
__LIGHT_PRESETS__
 end)()
 presets.replace=(function()
__PHOTO_FILE_REPLACE__
 end)().replace
 local root=rawget(_G,'DBF_PHOTO_PACKAGE_ROOT')
 DBF_PHOTO_LIGHTS.presets=presets.new(root and(root..'/lighting-presets.ini'))
end
H.dbf_subject_backend=(function()
__SUBJECT_BACKEND__
end)()
do
 local ok,value=pcall(H.dbf_subject_backend.new,sr)
 H.dbf_subject_backend=ok and value or nil
 if not ok then log('Subject renderer unavailable: '..tostring(value))end
end
H.dbf_subject=(function()
__SUBJECT__
end)().new(H.dbf_subject_backend,log)
H.dbf_poses=(function()
__SUBJECT_POSES__
end)().new(sr,H.dbf_subject_backend,function()return PHOTO.active and DBF_PLAYER_FREEZE.rate()==0 end,log,(function()
__SUBJECT_POSE_FRAMES__
end)())
DBF_PHOTO_OPTIONS.set_subject_poses(H.dbf_poses.catalog)
do
 local guard=(function()
__RAGDOLL_PAUSE__
 end)()
 local ok,value=pcall(function()return guard.new(guard.native(sr,H.dbf_subject_backend),log)end)
 if ok then H.dbf_ragdoll_pause=value;DBF_PLAYER_FREEZE.ragdoll_guard=value
 else log('Frozen ragdoll guard unavailable: '..tostring(value))end
end
H.dbf_pose_flush=function(dt)
 if not H.dbf_poses then return true end
 if H.dbf_ragdoll_pause and(H.dbf_poses.active or H.dbf_poses.pending)then
  local ok,why=H.dbf_ragdoll_pause.release();if ok==false then return false,why end
 end
 return H.dbf_poses.flush(dt)
end
H.dbf_ragdoll_after_render=function(...)
 if H.dbf_ragdoll_pause then
  local ok,ready,why=pcall(H.dbf_ragdoll_pause.flush,PHOTO.active and DBF_PLAYER_FREEZE.rate()==0,H.dbf_poses and(H.dbf_poses.active or H.dbf_poses.pending))
  if not ok or ready==false then
   local message=tostring(ok and why or ready)
   if H.dbf_ragdoll_error~=message then H.dbf_ragdoll_error=message;log('Frozen ragdoll guard: '..message)end
  else H.dbf_ragdoll_error=nil end
 end
 return ...
end
do
 local backend=(function()
__AI_BACKEND__
 end)()
 local control=(function()
__AI_CONTROL__
 end)()
 local ok,value=pcall(function()return control.new(backend.new(sr),log)end)
 if ok then H.dbf_ai=value else log('Dummy AI unavailable: '..tostring(value))end
end
H.dbf_director=(function()
__DIRECTOR__
end)().new(PHOTO,function()
 if H.dbf_subject_backend then return H.dbf_subject_backend.frame()end
 return nil,'Local player context unavailable'
end,rawget(_G,'DBF_PHOTO_PACKAGE_ROOT')and(rawget(_G,'DBF_PHOTO_PACKAGE_ROOT')..'/director-shots.ini'),log)
H.dbf_input_epoch=0
-- Called after the previous update returns. Positive World delta and restored
-- Photo time policy are required before the deferred entry may acquire input.
H.dbf_input_after_update=function(...)
 if H.dbf_poses then H.dbf_poses.after_update()end
 -- A closed idle camera deliberately drops target. Deferred hover cleanup
 -- still needs real completed updates; otherwise its owned zero stays applied.
 local update_world=target and target.world
 if H.dbf_hover_pause and H.dbf_hover_pause.pending and(not update_world or not world_alive(update_world))then update_world=try(sr.Application.main_world)end
 if update_world and world_alive(update_world)then
  local delta=try(sr.World.delta_time,update_world)
  if type(delta)=='number'and delta>=0 and delta<math.huge then
   if DBF_PLAYER_FREEZE.rate()>0 and delta>0 and not PHOTO.active then H.dbf_input_epoch=H.dbf_input_epoch+1 end
   if H.dbf_hover_pause_backend then H.dbf_hover_pause_backend.after_update(delta)end
   H.dbf_hover_pause.after_update()
  end
 end
 return ...
end
H.dbf_input_before_update=function()
 if H.dbf_input_recovery then H.dbf_input_recovery.poll(H.dbf_recovery_key and H.dbf_recovery_key()or 121)end
 if DBF_PLAYER_FREEZE.needs_input_capture()then
  local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
  local input=api and api.camera_input
  local focused=input and input.focused and input.focused()
  local menu_ok,menu=true,false
  if input and type(input.native_menu_active)=='function'then menu_ok,menu=pcall(input.native_menu_active)end
  if not focused or api.is_open()or not menu_ok or menu~=false then
   if H.dbf_poses and(H.dbf_poses.active or H.dbf_poses.pending)then
    H.dbf_poses.release();H.dbf_pose_flush()
    if H.dbf_poses.active or H.dbf_poses.pending then return end
   end
   DBF_PLAYER_FREEZE.release();return
  end
  DBF_PLAYER_FREEZE.hold()
 end
end
local DBF_SAVED_CAMERA=(function()
__SAVED_CAMERA__
end)().new(PHOTO,function()
  if not target or not anchor or not world_alive(target.world)or not try(sr.Unit.alive,anchor.unit)or anchor.spectate or known_body(anchor.unit)then return end
  local point=try(sr.Unit.world_position,anchor.unit,anchor.node)
  if point then return target.world,WORLD.epoch,anchor.unit,{xyz(point)}end
end,log)
H.dbf_cinema=(function()
__CINEMA_CAMERA__
end)().new(PHOTO,function()
 if not target or not anchor or not world_alive(target.world)or not try(sr.Unit.alive,anchor.unit)or anchor.spectate or known_body(anchor.unit)then return end
 return {world=tostring(target.world),epoch=WORLD.epoch,player=tostring(anchor.unit),gameplay_input=try(sr.Window.mouse_focus)==true and try(sr.Window.show_cursor)==false}
end)
local DBF_FREECAM=(function()
__CONTROLLER__
end)().new(PHOTO,CFG,function()
 if CFG.ensure_scene then local ready,why,retry=CFG.ensure_scene();if not ready then return false,why,retry end end
 return target~=nil and anchor~=nil and not SPEC.active and H.dbf_camera_ownership.available
end,log,DBF_PLAYER_FREEZE,DBF_PHOTO_OPTIONS,DBF_PHOTO_RUNTIME,DBF_PHOTO_MENU,DBF_PHOTO_COMPOSITION,DBF_SAVED_CAMERA,DBF_SCREENSHOTS,DBF_FOCUS_SAMPLER,DBF_PHOTO_LIGHTS,H.dbf_subject,H.dbf_director,nil,function()return H.dbf_input_epoch end,H.dbf_ai,H.dbf_poses,H.dbf_camera_ownership,H.dbf_cinema)
H.dbf_input_recovery=(function()
__INPUT_RECOVERY__
end)().new({window=sr.Window,log=log,
 input=function()
  local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
  return api and api.camera_input
 end,
 stop_photo=DBF_FREECAM.recovery_stop,
 views=function()
  local views={};local package_table=rawget(_G,'package');local loaded=type(package_table)=='table'and package_table.loaded
  local epic=type(loaded)=='table'and loaded['dbf.epic_lut.frontend.v1']
  if epic then views[#views+1]={key=epic,name='Epic LUT',close=epic.recover_input or epic.dismiss}end
  local mcm=rawget(_G,'DBFMCM')
  if mcm then views[#views+1]={key=mcm,name='MCM',close=mcm.close}end
  local loader=rawget(_G,'LiveLuaLoader')
  if loader then views[#views+1]={key=loader,name='LLL',close=loader.close_manager}end
  return views
 end})
DBF_FREECAM.input_recovery=H.dbf_input_recovery
H.dbf_recovery_key=DBF_FREECAM.recovery_key
rawset(_G,'DBF_PHOTO_EDITOR_INPUT',DBF_FREECAM.editor_bridge)
rawset(_G,'DBF_PHOTO_INPUT_RECOVERY',H.dbf_input_recovery)
PHOTO.dbf_stop=DBF_FREECAM.stop
PHOTO.dbf_clear_saved=DBF_SAVED_CAMERA.clear
DBF_PHOTO_LIGHTS.update_from_photo=function()
 local context=PHOTO.active and PHOTO.light_context
 local ok,why=DBF_PHOTO_LIGHTS.flush(context and context.world,context)
 if not ok and DBF_PHOTO_LIGHTS.pending then log('Photo lighting: '..tostring(why))end
end
DBF_PHOTO_LIGHTS.cache_camera=function()
 if not PHOTO.active or not target or not world_alive(target.world)then PHOTO.light_context=nil;return end
 local pose=try(sr.Camera.world_pose,target.cam)
 if not pose then
  -- A transient pose read during an action-shot handoff must not destroy lights.
  -- Retain only the last numeric anchor for this exact live world/scene epoch.
  local prior=PHOTO.light_context
  if not prior or prior.world~=target.world or prior.scene_epoch~=WORLD.epoch then PHOTO.light_context=nil end
  return
 end
 PHOTO.light_context={world=target.world,scene_epoch=WORLD.epoch,position={xyz(M.translation(pose))},forward={xyz(M.forward(pose))},right={xyz(M.right(pose))},up={xyz(M.up(pose))}}
end
local function bindings_step()
  H.dbf_game_chat.attach(rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API'))
  local ok,why=pcall(DBF_FREECAM.tick,last_dt)
  if not ok then DBF_FREECAM.stop();log('freecam error: '..tostring(why)) end
end
""".replace('__CONTROLLER__',controller).replace('__SIMULATION__',(ROOT/'simulation.lua').read_text(encoding='utf-8')).replace('__SIMULATION_BACKEND__',(ROOT/'simulation_backend.lua').read_text(encoding='utf-8')).replace('__CAMERA_LOOK__',(ROOT/'look.lua').read_text(encoding='utf-8'))
    candidate=''
    if dof_candidate:
        # Explicit review opt-in. This authorizes a preview; it does not assert
        # that the candidate's native GPU result has passed visual validation.
        candidate="""local DBF_PHOTO_DOF_FACTORY=(function()
local DBF_PHOTO_DEPTH=(function()
__PHOTO_DEPTH__
end)()
local DBF_PHOTO_DOF=(function()
__PHOTO_DOF__
end)()
local DBF_PHOTO_SHADER_TEMPLATE_GUARD=(function()
__PHOTO_SHADER_TEMPLATE_GUARD__
end)()
return {new=function(runtime_sr)
 return DBF_PHOTO_DOF.new(runtime_sr,DBF_PHOTO_DEPTH.new(runtime_sr),true,DBF_PHOTO_SHADER_TEMPLATE_GUARD.new(runtime_sr))
end}
end)()
""".replace('__PHOTO_DEPTH__',(ROOT/'depth_resource.lua').read_text(encoding='utf-8')).replace('__PHOTO_DOF__',(ROOT/('scene_dof_overlay.lua'if combined_scene_candidate else 'dof_overlay.lua')).read_text(encoding='utf-8')).replace('__PHOTO_SHADER_TEMPLATE_GUARD__',(ROOT/'shader_template_guard.lua').read_text(encoding='utf-8'))
        if combined_scene_candidate:
            template=photo_assets.hash64(re.search(r"^M.shader='([^']+)'$",(ROOT/'scene_dof_overlay.lua').read_text(encoding='utf-8'),re.M).group(1))>>32
            candidate=candidate.replace('DBF_PHOTO_SHADER_TEMPLATE_GUARD.new(runtime_sr)',f'DBF_PHOTO_SHADER_TEMPLATE_GUARD.new(runtime_sr,nil,0x{template:08x})')
    if scene_candidate:
        candidate+="""local DBF_PHOTO_SCENE_FACTORY=(function()
local DEPTH=(function()
__SCENE_DEPTH__
end)()
local SCENE=(function()
__SCENE_OVERLAY__
end)()
local GUARD=(function()
__SCENE_GUARD__
end)()
return {new=function(runtime_sr)
 local instance=SCENE.new(runtime_sr,DEPTH.new(runtime_sr),true,GUARD.new(runtime_sr,nil,0xd926b3f7))
 instance.active=function(options)return SCENE.uniforms(options).active end
 return instance
end}
end)()
""".replace('__SCENE_DEPTH__',(ROOT/'depth_resource.lua').read_text(encoding='utf-8')).replace('__SCENE_OVERLAY__',(ROOT/'scene_overlay.lua').read_text(encoding='utf-8')).replace('__SCENE_GUARD__',(ROOT/'shader_template_guard.lua').read_text(encoding='utf-8'))
    hook=hook.replace('__PHOTO_DOF_CANDIDATE__',candidate).replace('__PHOTO_DOF_ARGUMENT__',',DBF_PHOTO_DOF_FACTORY'if dof_candidate else ',nil'if scene_candidate else '').replace('__PHOTO_SCENE_ARGUMENT__',',DBF_PHOTO_SCENE_FACTORY'if scene_candidate else '').replace('__CAPTURE_LIBRARY__',capture_library_name())
    for token,filename in [('__PHOTO_OPTIONS__','photo_options.lua'),('__PHOTO_LENS__','lens.lua'),('__PHOTO_COMPOSITION__','composition.lua'),('__PHOTO_POSTFX__','postfx.lua'),('__PHOTO_RUNTIME__','photo_runtime.lua'),('__PHOTO_HUD__','hud.lua'),('__PHOTO_PROFILE__','render_profile.lua'),('__PHOTO_MENU__','photo_menu.lua'),('__CONTROL_LEGEND__','control_legend.lua'),('__LOGO_ART__','assets/logo_art.lua'),('__CAMERA_PROFILE__','camera_profile.lua'),('__SAVED_CAMERA__','saved_camera.lua')]:
        hook=hook.replace(token,(ROOT/filename).read_text(encoding='utf-8'))
    for token,filename in [('__SCREENSHOT__','screenshot.lua'),('__SCREENSHOT_BACKEND__','screenshot_backend.lua'),('__FOCUS_DEPTH__','depth_resource.lua'),('__FOCUS_SAMPLER__','focus_sampler.lua'),('__PHOTO_LIGHTS__','photo_lights.lua'),('__LIGHT_GIZMOS__','photo_light_gizmos.lua'),('__LIGHT_PRESETS__','photo_light_presets.lua'),('__PHOTO_FILE_REPLACE__','photo_file_replace.lua'),('__CHAT_CONTEXT__','chat_context.lua'),('__HELLDIVER_CREST__','assets/helldiver_crest.lua'),('__FACTION_ART__','assets/faction_art.lua'),('__SUBJECT_BACKEND__','subject_backend.lua'),('__SUBJECT__','subject.lua'),('__SUBJECT_POSES__','subject_poses.lua'),('__RAGDOLL_PAUSE__','ragdoll_pause.lua'),('__SUBJECT_POSE_FRAMES__','assets/subject_pose_frames.lua'),('__AI_BACKEND__','ai_backend.lua'),('__AI_CONTROL__','ai_control.lua'),('__DIRECTOR__','director.lua'),('__CINEMA_CAMERA__','cinema_camera.lua'),('__HOVER_PAUSE__','hover_pause.lua'),('__HOVER_PAUSE_BACKEND__','hover_pause_backend.lua')]:
        hook=hook.replace(token,(ROOT/filename).read_text(encoding='utf-8'))
    if camera_lifecycle:
        marker='local DBF_PHOTO_RUNTIME=(function()'
        if hook.count(marker)!=1:raise ValueError('Photo camera lifecycle embed contract changed')
        hook=hook.replace(marker,camera_lifecycle+marker,1)
    hook=hook.replace('__INPUT_RECOVERY__',(ROOT/'input_recovery.lua').read_text(encoding='utf-8'))
    return hook


def payload_files(output,ownership_source=None):
    """Complete public runtime payload shared by BSL and the MDL adapter."""
    if ownership_source is None:
        import importlib.util
        spec=importlib.util.spec_from_file_location('photo_owned_camera_build',ROOT/'independent_build.py')
        owned=importlib.util.module_from_spec(spec);spec.loader.exec_module(owned)
        ownership_source=owned.ownership_source()
    files={'src/camera_runtime.lua':(output/'WarJournalist-runtime.lua').read_bytes(),
        'src/camera_ownership.lua':ownership_source.encode(),
        'src/standalone.lua':(ROOT/'standalone.lua').read_bytes(),
        'src/photo_input_capture.lua':(ROOT/'photo_input_capture.lua').read_bytes(),
        'PROVENANCE.json':(output/'PROVENANCE.json').read_bytes()}
    vendor=ROOT/'vendor';identity=json.loads((vendor/'PROVENANCE.json').read_text())
    for name in ('core','store','capture','camera_input','view','font','bingus_memory','bingus_runtime'):
        body=(vendor/(name+'.lua')).read_bytes()
        if hashlib.sha256(body).hexdigest()!=identity['runtime_sha256'][name+'.lua']:raise ValueError('Vendored Lua identity mismatch: '+name)
        files['src/vendor/'+name+'.lua']=body
    native=(vendor/'standalone-library.txt').read_text().strip()
    if not re.fullmatch(r'mcm_input_[0-9a-f]+\.dll',native):raise ValueError('Invalid private input DLL manifest')
    files['standalone-library.txt']=native.encode()
    for name in (native,capture_library_name()):
        body=bytes.fromhex((vendor/(name+'.hex')).read_text())
        if hashlib.sha256(body).hexdigest()!=identity['runtime_sha256'][name]:raise ValueError('Vendored native identity mismatch: '+name)
        files[name]=body
    files['LICENSE-Bingus.txt']=(vendor/'LICENSE-Bingus.txt').read_bytes()
    files['LICENSE-Link.txt']=(vendor/'LICENSE-Link.txt').read_bytes()
    files['FACTION-ART-CREDITS.json']=(ROOT/'assets/faction-art-provenance.json').read_bytes()
    files['VENDOR-PROVENANCE.json']=(vendor/'PROVENANCE.json').read_bytes()
    for path in (ROOT/'assets').glob('*.png'):files['assets/'+path.name]=path.read_bytes()
    files['assets/helldivers_cursor.cur']=(ROOT/'assets/helldivers_cursor.cur').read_bytes()
    return files

def lua_bytes(body):
    # Quoted byte escapes preserve vendor CRLF/UTF-8 exactly when Lua decodes them.
    return '"'+''.join(chr(value)if 32<=value<=126 and value not in(34,92)else '\\%03d'%value for value in body)+'"'

def compile_lua(body,name):
    import ctypes
    lua=ctypes.CDLL(os.environ.get('HD2_LUA51_DLL',r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2\bin\lua51.dll'))
    lua.luaL_newstate.restype=ctypes.c_void_p
    lua.luaL_loadbuffer.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p]
    lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
    lua.lua_close.argtypes=[ctypes.c_void_p]
    state=lua.luaL_newstate()
    try:
        if lua.luaL_loadbuffer(state,body,len(body),name.encode()):raise ValueError(lua.lua_tolstring(state,-1,None).decode())
    finally:lua.lua_close(state)

def package_bsl(output,version=None,dof_candidate=False):
    version=version or(ROOT.parent/'VERSION').read_text().strip()
    files=payload_files(output)
    if (b'local DBF_PHOTO_DOF_FACTORY='in files['src/camera_runtime.lua'])!=bool(dof_candidate):
        raise ValueError('Runtime DoF path and packaged asset selection differ')
    for name,body in files.items():
        if name.endswith('.lua'):compile_lua(body,name)
    embedded=[]
    for name,body in sorted(files.items()):
        if name.endswith('.dll'):value='{hex='+lua_bytes(body.hex().encode())+'}'
        elif name.startswith('src/')or name in ('standalone-library.txt','assets/helldivers_cursor.cur'):value=lua_bytes(body)
        else:continue
        embedded.append('['+lua_bytes(name.encode())+']='+value+',')
    template=(ROOT/'bsl_startup.lua').read_text(encoding='utf-8')
    if template.count('-- __EMBEDDED_FILES__')!=1:raise ValueError('BSL bootstrap embed contract changed')
    startup=template.replace('-- __EMBEDDED_FILES__','\n'.join(embedded)).replace('__VERSION__',version).replace('__CAPTURE_LIBRARY__',capture_library_name()).encode()
    compile_lua(startup,'WarJournalist-BSL-startup')
    entry='mods/dbf_photomode/startup';envelope=struct.pack('<II',len(startup),2)+startup
    registry_gpu=b''
    if dof_candidate:
        import dof_assets
        core_resources,shared_resources,asset_audit=dof_assets.resources(output)
        archive,gpu=photo_assets.archive_rows(shared_resources+[(lua_archive.hash_name(entry),lua_archive.LUA_TYPE,envelope,b'')])
        registry,registry_gpu=photo_assets.archive_rows(core_resources)
    else:
        archive,gpu=photo_assets.archive_rows(photo_assets.load_resources()+[(lua_archive.hash_name(entry),lua_archive.LUA_TYPE,envelope,b'')])
        asset_audit=photo_assets.validate_archive(archive,gpu)
        registry,registry_gpu=photo_assets.archive_rows([photo_assets.registry_resource()])
        if registry_gpu:raise ValueError('Unexpected registry GPU data')
    parsed=photo_assets.read_archive(archive,gpu)
    startup_rows=[row for row in parsed if row[1]==lua_archive.LUA_TYPE]
    if len(startup_rows)!=1 or startup_rows[0][2]!=envelope:raise ValueError('BSL archive source round-trip failed')
    manifest={'Version':1,'Guid':'0a1f063d-d880-4282-a5c3-89f9efc52b21','Name':'War Journalist '+version,
        'Description':'Self-contained Photo Mode with 40 decorative overlays, shader DoF and scene preview assets, standalone menu/input and HDR-aware PNG capture. Requires only Bingus Shared Loader v15+ / API 1. MCM is optional.',
        'Options':[{'Name':'War Journalist '+version,'Description':'All runtime and assets included. Requires only Bingus Shared Loader v15+ / API 1. Enable, deploy and restart.','Include':['Addon']}]}
    package={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),
        'Addon/9ba626afa44a3aa3.patch_0':archive,'Addon/9ba626afa44a3aa3.patch_0.stream':b'',
        'Addon/9ba626afa44a3aa3.patch_0.gpu_resources':gpu,
        'Addon/ee6b1ba7e22d71ed.patch_0':registry,'Addon/ee6b1ba7e22d71ed.patch_0.stream':b'',
        'Addon/ee6b1ba7e22d71ed.patch_0.gpu_resources':registry_gpu,'PROVENANCE.json':files['PROVENANCE.json'],
        'ASSET-MANIFEST.json':(json.dumps(asset_audit,indent=2)+'\n').encode(),
        'VENDOR-PROVENANCE.json':files['VENDOR-PROVENANCE.json'],
        'LICENSE-Bingus.txt':files['LICENSE-Bingus.txt'],'LICENSE-Link.txt':files['LICENSE-Link.txt'],'FACTION-ART-CREDITS.json':files['FACTION-ART-CREDITS.json'],'README.md':(ROOT.parent/'README.md').read_bytes(),
        'INSTALL.txt':(ROOT/'README.md').read_bytes(),'Source/bsl_startup.lua':(ROOT/'bsl_startup.lua').read_bytes()}
    for name,body in files.items():
        if name.startswith('assets/'):package[name]=body
        if name in ('README.md','SUBJECT-POSE-CATALOGUE.md'):package[name]=body
    notes=ROOT.parent/'docs'/('RELEASE-'+version+'.md')
    if not notes.is_file():notes=ROOT.parent/('RELEASE-'+version+'.md')
    if notes.is_file():package['RELEASE-NOTES.md']=notes.read_bytes()
    known_issues=ROOT.parent/'docs/KNOWN-ISSUES.md'
    if not known_issues.is_file():known_issues=ROOT.parent/'KNOWN-ISSUES.md'
    if known_issues.is_file():package['KNOWN-ISSUES.md']=known_issues.read_bytes()
    package['FILES-SHA256.txt']=''.join(hashlib.sha256(body).hexdigest()+'  '+name+'\n'for name,body in sorted(package.items())).encode()
    target=output/('War-Journalist-'+version+'-BSL.zip')
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED)as zip:
        for name,body in sorted(package.items()):zip.writestr(name,body)
    with zipfile.ZipFile(target)as zip:
        if zip.testzip()is not None or len(zip.namelist())!=len(set(zip.namelist())):raise ValueError('BSL ZIP integrity failed')
    (output/'War-Journalist-BSL-startup.lua').write_bytes(startup)
    (output/'BSL-BUILD-RECEIPT.json').write_text(json.dumps({'version':version,'artifact':target.name,
        'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'entry':entry,'runtime_files_sha256':{name:hashlib.sha256(body).hexdigest()for name,body in sorted(files.items())},
        'asset_audit':asset_audit,
        'validation':'All embedded Lua compiled; complete native asset closure, shader registrations, startup round-trip and ZIP integrity passed',
        'live_validation':False,'deployment':'not installed'},indent=2)+'\n')
    print(target)
    return target

def build(output,dof_candidate=False):
    """Build the owned camera runtime and self-contained BSL package."""
    import importlib.util
    spec=importlib.util.spec_from_file_location('photo_owned_camera_build',ROOT/'independent_build.py')
    owned=importlib.util.module_from_spec(spec);spec.loader.exec_module(owned)
    result=owned.generate(dof_candidate=dof_candidate).encode('utf-8')
    compile_lua(result,'WarJournalist-owned-camera')
    output.mkdir(parents=True,exist_ok=True)
    (output/'WarJournalist-runtime.lua').write_bytes(result)
    modules={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(ROOT.glob('*.lua'))
             if not p.name.endswith('_tests.lua')}
    (output/'PROVENANCE.json').write_text(json.dumps({
        'version':(ROOT.parent/'VERSION').read_text().strip(),'camera_engine':'independent',
        'runtime_sha256':hashlib.sha256(result).hexdigest(),'source_modules_sha256':modules,
        'independent_builder_sha256':hashlib.sha256((ROOT/'independent_build.py').read_bytes()).hexdigest(),
        'dof_candidate_preview':bool(dof_candidate),'deployment':'not installed','live_validation':False,
    },indent=2)+'\n')
    (output/'INSTALL.txt').write_text((ROOT/'README.md').read_text())
    return package_bsl(output,(ROOT.parent/'VERSION').read_text().strip(),dof_candidate=dof_candidate)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT.parent/'dist/review/owned-camera-build')
    parser.add_argument('--dof-candidate',action='store_true',help='Include the explicit DoF fallback preview; final shader quality remains under review')
    args=parser.parse_args()
    build(args.output,dof_candidate=args.dof_candidate)

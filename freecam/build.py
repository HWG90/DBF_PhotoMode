"""Build the self-contained Photo Mode release; never installs."""
from pathlib import Path
import argparse, hashlib, json, os, re, struct, sys, zipfile
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'tools'))
import lua_archive
import photo_assets

def patch(source):
    def replace(old,new):
        nonlocal source
        if source.count(old)!=1: raise ValueError('ActionCam source contract changed: '+old[:70])
        source=source.replace(old,new)
    replace('local function bindings_step()', 'local function legacy_bindings_step()')
    # Freecam keys belong to MCM; profile/restart bindings continue using MBM.
    source=re.sub(r'^  \{id = \'actioncam\.photo_[^\n]+\n','',source,flags=re.M)
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
local DBF_PLAYER_FREEZE=(function()
__SIMULATION__
end)().new(sr,function()return anchor and anchor.unit,target and target.world,anchor~=nil and not anchor.spectate and not known_body(anchor.unit) and not SPEC.active and not SAFE.gate end,DBF_SIMULATION_BACKEND)
local DBF_PHOTO_OPTIONS=(function()
__PHOTO_OPTIONS__
end)()
local DBF_PHOTO_LENS=(function()
__PHOTO_LENS__
end)()
local DBF_PHOTO_COMPOSITION=(function()
__PHOTO_COMPOSITION__
end)()
DBF_PHOTO_COMPOSITION.logo_art=(function()
__LOGO_ART__
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
local DBF_PHOTO_RUNTIME=(function()
__PHOTO_RUNTIME__
end)().new(sr,DBF_PHOTO_LENS,DBF_PHOTO_COMPOSITION,DBF_PHOTO_POSTFX,log,DBF_PHOTO_HUD,DBF_PHOTO_PROFILE)
local DBF_PHOTO_MENU=(function()
__PHOTO_MENU__
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
  local convert=DBF_PHOTO_SCREENSHOT.native_converter(root..'/PhotoCapture64.dll',folder)
  local backend=assert(DBF_PHOTO_SCREENSHOT_BACKEND.new(sr))
  return DBF_PHOTO_SCREENSHOT.new(backend,convert,folder,log)
 end)
 if ok then DBF_SCREENSHOTS=value else log('Screenshot capture unavailable: '..tostring(value))end
end
local DBF_SAVED_CAMERA=(function()
__SAVED_CAMERA__
end)().new(PHOTO,function()
  if not target or not anchor or not world_alive(target.world)or not try(sr.Unit.alive,anchor.unit)or anchor.spectate or known_body(anchor.unit)then return end
  local point=try(sr.Unit.world_position,anchor.unit,anchor.node)
  if point then return target.world,WORLD.epoch,anchor.unit,{xyz(point)}end
end,log)
local DBF_FREECAM=(function()
__CONTROLLER__
end)().new(PHOTO,CFG,function()return target~=nil and anchor~=nil and not SPEC.active end,log,DBF_PLAYER_FREEZE,DBF_PHOTO_OPTIONS,DBF_PHOTO_RUNTIME,DBF_PHOTO_MENU,DBF_PHOTO_COMPOSITION,DBF_SAVED_CAMERA,DBF_SCREENSHOTS)
PHOTO.dbf_stop=DBF_FREECAM.stop
PHOTO.dbf_clear_saved=DBF_SAVED_CAMERA.clear
local function bindings_step()
  local ok,why=pcall(DBF_FREECAM.tick,last_dt)
  if not ok then DBF_FREECAM.stop();log('freecam error: '..tostring(why)) end
end
""".replace('__CONTROLLER__',controller).replace('__SIMULATION__',(ROOT/'simulation.lua').read_text(encoding='utf-8')).replace('__SIMULATION_BACKEND__',(ROOT/'simulation_backend.lua').read_text(encoding='utf-8')).replace('__CAMERA_LOOK__',(ROOT/'look.lua').read_text(encoding='utf-8'))
    for token,filename in [('__PHOTO_OPTIONS__','photo_options.lua'),('__PHOTO_LENS__','lens.lua'),('__PHOTO_COMPOSITION__','composition.lua'),('__PHOTO_POSTFX__','postfx.lua'),('__PHOTO_RUNTIME__','photo_runtime.lua'),('__PHOTO_HUD__','hud.lua'),('__PHOTO_PROFILE__','render_profile.lua'),('__PHOTO_MENU__','photo_menu.lua'),('__LOGO_ART__','assets/logo_art.lua'),('__CAMERA_PROFILE__','camera_profile.lua'),('__SAVED_CAMERA__','saved_camera.lua')]:
        hook=hook.replace(token,(ROOT/filename).read_text(encoding='utf-8'))
    for token,filename in [('__SCREENSHOT__','screenshot.lua'),('__SCREENSHOT_BACKEND__','screenshot_backend.lua')]:
        hook=hook.replace(token,(ROOT/filename).read_text(encoding='utf-8'))
    replace('-- One frame of Photo Mode: fly the detached camera and place it.',hook+'\n-- One frame of Photo Mode: fly the detached camera and place it.')
    replace("  if PHOTO_REF and PHOTO_REF.active then", "  if PHOTO_REF and PHOTO_REF.dbf_clear_saved and (reason=='death'or reason=='world gone'or reason=='restart'or reason=='shutdown')then PHOTO_REF.dbf_clear_saved(reason)end\n  if PHOTO_REF and PHOTO_REF.dbf_stop then PHOTO_REF.dbf_stop() end\n  if PHOTO_REF and PHOTO_REF.active then")
    replace('PHOTO.pos = last_written and {last_written[1], last_written[2], last_written[3]} or {cx, cy, cz}', 'PHOTO.pos = {cx, cy, cz}')
    replace('function PHOTO.apply(cam, unit, pose, cx, cy, cz)', 'function PHOTO.apply(cam, unit, pose, cx, cy, cz)\n  local held,why=DBF_PLAYER_FREEZE.hold();if held==false then DBF_FREECAM.stop();if why then log(why)end;return end')
    replace("      log('photo mode: off (Helldiver down)')", "      DBF_SAVED_CAMERA.clear('death')\n      DBF_FREECAM.stop()\n      log('photo mode: off (Helldiver down)')")
    replace('  local fx, fy, fz = xyz(M.forward(pose))\n  local rx, ry, rz = xyz(M.right(pose))\n  local I = PHOTO.input', """  local initial={xyz(M.forward(pose))}
  local I = PHOTO.input
  local forward,right=DBF_FREECAM_LOOK.basis(PHOTO,initial,I)
  local fx,fy,fz=unpack(forward)
  local rx,ry,rz=unpack(right)
  DBF_PHOTO_RUNTIME.apply(cam,unit,target.world,forward,right,PHOTO.options or DBF_PHOTO_OPTIONS.defaults,I.dt)""")
    replace('local spd = CFG.PHOTO_SPEED * (I.fast and CFG.PHOTO_FAST or 1) * last_dt',
            'local norm=math.max(1,math.sqrt(mf*mf+mr*mr+mu*mu))\n  local spd = CFG.PHOTO_SPEED * math.max(0,math.min(I.dt or last_dt,0.1)) / norm')
    replace("      log('error ' .. failures .. ': ' .. tostring(err))", "      DBF_FREECAM.stop()\n      log('error ' .. failures .. ': ' .. tostring(err))")
    # Keep camera/Helldiver discovery; remove all normal gameplay camera writes.
    first=source.index('local function apply()')
    last=source.index('---------------------------------------------------------------- render hook',first)
    source=source[:first]+"""local function apply()
  if not target then return end
  if not world_alive(target.world) then drop_all('world gone');return end
  if not try(sr.Unit.alive,target.unit) then drop_all('camera unit gone');return end
  if anchor and not try(sr.Unit.alive,anchor.unit) then H.anchor_gone() end
  local cam,unit=target.cam,target.unit
  local lp=try(sr.Camera.local_position,cam,unit)
  local pose=try(sr.Camera.world_pose,cam)
  if not lp or not pose then return end
  local cx,cy,cz=xyz(lp)
  if PHOTO.active then return PHOTO.apply(cam,unit,pose,cx,cy,cz) end
  -- Identity can still converge while photo mode is inactive; no camera adjustment.
  H.id_sample(target.world,cx,cy,cz,pose)
end

"""+source[last:]
    replace('  pcall(bindings_step)', '  -- Photo input is sampled in render, independently of simulation time.')
    replace('    counts.render = counts.render + 1', '    bindings_step()\n    counts.render = counts.render + 1')
    replace('  pcall(options_step)', '  -- Freecam owns the sole MCM registration; ActionCam options are disabled.')
    source=source.replace("CFG.LOG_NAME   = 'ActionCam.log'", "CFG.LOG_NAME   = 'Freecam.log'")
    source=source.replace("'ActionCam_previous.log'", "'Freecam_previous.log'")
    source=source.replace('CFG.EXTRACT_RESEARCH      = true', 'CFG.EXTRACT_RESEARCH      = false')
    source=source.replace("'ActionCam v' .. CFG.VERSION .. ' started:", "'Freecam camera foundation started:")
    source+='''\nlocal dbf_previous_shutdown=rawget(_G,'shutdown')
shutdown=function(...)
  DBF_FREECAM.close()
  drop_all('shutdown')
  if dbf_previous_shutdown then return dbf_previous_shutdown(...) end
end
'''
    return source

def payload_files(output):
    """Complete public runtime payload shared by BSL and the MDL adapter."""
    files={'src/actioncam.lua':(output/'ActionCam-Freecam.lua').read_bytes(),
        'src/standalone.lua':(ROOT/'standalone.lua').read_bytes(),
        'PROVENANCE.json':(output/'PROVENANCE.json').read_bytes()}
    vendor=ROOT/'vendor';identity=json.loads((vendor/'PROVENANCE.json').read_text())
    for name in ('core','store','capture','camera_input','view','font','bingus_memory','bingus_runtime'):
        body=(vendor/(name+'.lua')).read_bytes()
        if hashlib.sha256(body).hexdigest()!=identity['runtime_sha256'][name+'.lua']:raise ValueError('Vendored Lua identity mismatch: '+name)
        files['src/vendor/'+name+'.lua']=body
    native=(vendor/'standalone-library.txt').read_text().strip()
    if not re.fullmatch(r'mcm_input_[0-9a-f]+\.dll',native):raise ValueError('Invalid private input DLL manifest')
    files['standalone-library.txt']=native.encode()
    for name in (native,'PhotoCapture64.dll'):
        body=bytes.fromhex((vendor/(name+'.hex')).read_text())
        if hashlib.sha256(body).hexdigest()!=identity['runtime_sha256'][name]:raise ValueError('Vendored native identity mismatch: '+name)
        files[name]=body
    files['LICENSE-Bingus.txt']=(vendor/'LICENSE-Bingus.txt').read_bytes()
    files['VENDOR-PROVENANCE.json']=(vendor/'PROVENANCE.json').read_bytes()
    for path in (ROOT/'assets').glob('*.png'):files['assets/'+path.name]=path.read_bytes()
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

def package_bsl(output,version=None):
    version=version or(ROOT.parent/'VERSION').read_text().strip()
    files=payload_files(output)
    for name,body in files.items():
        if name.endswith('.lua'):compile_lua(body,name)
    embedded=[]
    for name,body in sorted(files.items()):
        if name.endswith('.dll'):value='{hex='+lua_bytes(body.hex().encode())+'}'
        elif name.startswith('src/')or name=='standalone-library.txt':value=lua_bytes(body)
        else:continue
        embedded.append('['+lua_bytes(name.encode())+']='+value+',')
    template=(ROOT/'bsl_startup.lua').read_text(encoding='utf-8')
    if template.count('-- __EMBEDDED_FILES__')!=1:raise ValueError('BSL bootstrap embed contract changed')
    startup=template.replace('-- __EMBEDDED_FILES__','\n'.join(embedded)).replace('__VERSION__',version).encode()
    compile_lua(startup,'WarJournalist-BSL-startup')
    entry='mods/dbf_photomode/startup';envelope=struct.pack('<II',len(startup),2)+startup
    archive,gpu=photo_assets.archive_rows(photo_assets.load_resources()+[(lua_archive.hash_name(entry),lua_archive.LUA_TYPE,envelope,b'')])
    parsed=photo_assets.read_archive(archive,gpu)
    startup_rows=[row for row in parsed if row[1]==lua_archive.LUA_TYPE]
    if len(startup_rows)!=1 or startup_rows[0][2]!=envelope:raise ValueError('BSL archive source round-trip failed')
    asset_audit=photo_assets.validate_archive(archive,gpu)
    registry,registry_gpu=photo_assets.archive_rows([photo_assets.registry_resource()])
    if registry_gpu:raise ValueError('Unexpected registry GPU data')
    manifest={'Version':1,'Guid':'0a1f063d-d880-4282-a5c3-89f9efc52b21','Name':'War Journalist '+version,
        'Description':'Self-contained Photo Mode with all 40 decorative overlay assets, standalone menu/input and PNG capture. Requires only Bingus Shared Loader v15+ / API 1. MCM is optional.',
        'Options':[{'Name':'War Journalist '+version,'Description':'All runtime and assets included. Requires only Bingus Shared Loader v15+ / API 1. Enable, deploy and restart.','Include':['Addon']}]}
    package={'manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),
        'Addon/9ba626afa44a3aa3.patch_0':archive,'Addon/9ba626afa44a3aa3.patch_0.stream':b'',
        'Addon/9ba626afa44a3aa3.patch_0.gpu_resources':gpu,
        'Addon/ee6b1ba7e22d71ed.patch_0':registry,'Addon/ee6b1ba7e22d71ed.patch_0.stream':b'',
        'Addon/ee6b1ba7e22d71ed.patch_0.gpu_resources':b'','PROVENANCE.json':files['PROVENANCE.json'],
        'ASSET-MANIFEST.json':(json.dumps(asset_audit,indent=2)+'\n').encode(),
        'VENDOR-PROVENANCE.json':files['VENDOR-PROVENANCE.json'],
        'LICENSE-Bingus.txt':files['LICENSE-Bingus.txt'],'README.md':(ROOT.parent/'README.md').read_bytes(),
        'INSTALL.txt':(ROOT/'README.md').read_bytes(),'Source/bsl_startup.lua':(ROOT/'bsl_startup.lua').read_bytes()}
    for name,body in files.items():
        if name.startswith('assets/'):package[name]=body
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

def build(archive,output):
    if archive:
        original=archive.read_bytes();resources=lua_archive.read(original)
        name=lua_archive.hash_name('mods/actioncam/actioncam')
        kind,body=resources[name]
        if kind!=lua_archive.LUA_TYPE or body[4:8]!=b'\x02\0\0\0': raise ValueError('Expected Lua source resource')
        source=body[8:].decode('utf-8').rstrip('\0');origin=archive.name;origin_hash=hashlib.sha256(original).hexdigest()
    else:
        body=(ROOT/'vendor/actioncam-2.3.1.lua').read_bytes()
        identity=json.loads((ROOT/'vendor/PROVENANCE.json').read_text())
        if hashlib.sha256(body).hexdigest()!=identity['actioncam_source_sha256']:raise ValueError('Vendored camera identity mismatch')
        source=body.decode('utf-8');origin='ActionCam 2.3.1 (vendored source)';origin_hash=identity['actioncam_archive_sha256']
    result=patch(source).encode('utf-8')
    # Compile the complete generated runtime before producing installable bytes.
    import ctypes
    lua=ctypes.CDLL(os.environ.get('HD2_LUA51_DLL',r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2\bin\lua51.dll'))
    lua.luaL_newstate.restype=ctypes.c_void_p
    lua.luaL_loadbuffer.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p]
    lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
    lua.lua_close.argtypes=[ctypes.c_void_p]
    state=lua.luaL_newstate()
    try:
        if lua.luaL_loadbuffer(state,result,len(result),b'freecam-generated'):
            raise ValueError(lua.lua_tolstring(state,-1,None).decode())
    finally:lua.lua_close(state)
    output.mkdir(parents=True,exist_ok=True)
    (output/'ActionCam-Freecam.lua').write_bytes(result)
    (output/'PROVENANCE.json').write_text(json.dumps({'source_archive':origin,'source_sha256':origin_hash,
        'photo_modules_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'photo_options.lua',ROOT/'lens.lua',ROOT/'composition.lua',ROOT/'postfx.lua',ROOT/'photo_runtime.lua',ROOT/'hud.lua',ROOT/'render_profile.lua',ROOT/'camera_profile.lua',ROOT/'saved_camera.lua',ROOT/'photo_menu.lua']},
        'simulation_sha256':hashlib.sha256((ROOT/'simulation.lua').read_bytes()).hexdigest(),
        'simulation_backend_sha256':hashlib.sha256((ROOT/'simulation_backend.lua').read_bytes()).hexdigest(),
        'look_sha256':hashlib.sha256((ROOT/'look.lua').read_bytes()).hexdigest(),
        'controller_sha256':hashlib.sha256((ROOT/'controller.lua').read_bytes()).hexdigest(),'deployment':'not installed','live_validation':False},indent=2)+'\n')
    (output/'INSTALL.txt').write_text((ROOT/'README.md').read_text())
    return package_bsl(output,(ROOT.parent/'VERSION').read_text().strip())

if __name__=='__main__':
    version=(ROOT.parent/'VERSION').read_text().strip()
    parser=argparse.ArgumentParser();parser.add_argument('--actioncam',type=Path,help='Optional explicit camera foundation override; defaults to owned vendored source');parser.add_argument('--output',type=Path,default=ROOT.parent/'dist/releases'/('photo-'+version))
    args=parser.parse_args()
    build(args.actioncam,args.output)

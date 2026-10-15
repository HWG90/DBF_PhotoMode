local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Standalone=dofile(root..'standalone.lua')
local Capture=dofile(root..'photo_input_capture.lua')
local Camera=dofile(root..'vendor/camera_input.lua')
local function empty()return{package={loaded={}}}end
local function status(open,active,pending,owner)return{open=open,active=active,pending_restore=pending,owner=owner}end
do
 local G=empty();assert(Standalone.external_status(G).available)
 G.LiveLuaLoader={input_status=function()return{active=false}end}
 assert(Standalone.external_status(G).available,'documented lazy LLL no-capture fallback is exact inactive')
 for _,bad in ipairs({{active=false,other=true},{active=false,owner='foreign'},{active=true},{active='unknown'},{active=false,pending_restore='unknown'}})do
  G.LiveLuaLoader.input_status=function()return bad end
  assert(Standalone.external_status(G)==nil,'malformed LLL ownership cannot grant capture')
 end
 G.LiveLuaLoader={};assert(Standalone.external_status(G)==nil)
 G.LiveLuaLoader.input_status=function()error('reader lost')end;assert(Standalone.external_status(G)==nil)
 G.LiveLuaLoader.input_status=function()return status(false,false,true)end
 assert(Standalone.external_status(G).available==false)
 G.LiveLuaLoader.input_status=function()return status(false,false,false,'manager')end
 assert(Standalone.external_status(G).owner=='manager')
end
do
 local legacy={menu={visible=false},capture={status=function()return{active=false,pending_restore=false}end}}
 assert(Standalone.epic_status(legacy).available)
 legacy.menu.visible=true;assert(Standalone.epic_status(legacy).available==false)
 legacy.menu.visible=false;legacy.capture.status=function()return{active=false,pending_restore=true}end
 assert(Standalone.epic_status(legacy).pending_restore)
 legacy.capture.status=function()return{active=false}end;assert(Standalone.epic_status(legacy)==nil)
 legacy.capture.status=function()error('read unavailable')end;assert(Standalone.epic_status(legacy)==nil)
 local modern={input_status=function()return status(false,false,false)end}
 assert(Standalone.epic_status(modern).available)
 modern.input_status=function()return status(true,false,false)end;assert(not Standalone.epic_status(modern).available)
 modern.input_status=function()return status(false,true,false,'Epic LUT')end;assert(Standalone.epic_status(modern).active)
 modern.input_status=function()return status(false,false,true)end;assert(Standalone.epic_status(modern).pending_restore)
 modern.input_status=function()return{active=false,pending_restore=false}end;assert(Standalone.epic_status(modern)==nil)
 assert(Standalone.epic_status(false)==nil and Standalone.epic_status(nil).available)
end
local function fixture(no_parent)
 local s={G=empty(),focus=true,cursor=false,clip=false,focused=true,mode=0,writes=0,native_changes=0,resumes=0,
  menu=false,chat=false,resume=true,parent=false,upstream=true}
 local window={}
 for _,field in ipairs({{'mouse_focus','focus'},{'show_cursor','cursor'},{'clip_cursor','clip'}})do
  local method,key=field[1],field[2];window[method]=function()return s[key]end
  window['set_'..method]=function(value)s.writes=s.writes+1;s[key]=value;return true end
 end
 local native={mcm_install=function()s.native_changes=s.native_changes+1;return 1 end,
  mcm_capture=function(value)s.native_changes=s.native_changes+1;s.mode=value;return 1 end,
  mcm_captured=function()return s.mode end,
  mcm_release=function()s.native_changes=s.native_changes+1;if not s.sticky then s.mode=0 end end}
 local input={poll=function()end,focused=function()return s.focused end,window=function()return 1 end,
  lock_aim=function()window.set_mouse_focus(false);return true end,
  menu_cursor=function(menu)window.set_mouse_focus(false);window.set_show_cursor(menu);window.set_clip_cursor(true);return true end,
  down=function()return false end,wheel=function()return 0 end}
 local parent;if not no_parent then parent=function()return s.parent end end
 local gate=Standalone.ownership(function()return s.upstream end,parent,s.G)
 local capture=Capture.new(window,gate.restore_parent)
 local camera=Camera.new(native,capture,input,gate.available)
 gate.attach(camera,native,input)
 function camera.native_menu_active()return s.menu end
 function camera.chat_active()return s.chat end
 function camera.native_menu_resume()
  s.resumes=s.resumes+1
  if s.on_resume then s.on_resume()end
  return s.resume
 end
 s.camera,s.capture,s.gate=camera,capture,gate
 return s
end
do
 local s=fixture();local external=status(true,true,false,'Epic LUT')
 s.G.package.loaded['dbf.epic_lut.frontend.v1']={input_status=function()return external end}
 local token=s.camera.acquire({})
 assert(token==nil and s.writes==0 and s.native_changes==0 and s.resumes==0,
  'Epic ownership must block acquire before native_menu_resume or a Window/native write')
 assert(s.capture.acquire('bypass')==nil,'capture parent must independently protect Epic ownership')
 assert(not s.camera.external_status().available)
 external=status(false,false,true);assert(s.camera.acquire({})==nil and s.resumes==0)
 external=status(false,false,false);assert(s.camera.acquire({})and s.camera.release())
 s.parent=true;assert(s.camera.acquire({})==nil and not s.gate.available())
 s.parent=nil;assert(s.camera.external_status()==nil and s.capture.acquire('bypass')==nil)
end
do
 local s=fixture();assert(s.camera.acquire({}))
 local before=s.writes
 s.G.package.loaded['dbf.epic_lut.frontend.v1']={menu={visible=true},capture={status=function()return{active=true,pending_restore=false,owner='Epic LUT'}end}}
 assert(s.camera.release()and s.writes==before and s.focus==false,'a newer editor owns even same-valued Window flags during release')
end
do
 local s=fixture(true);assert(s.camera.external_status().available)
 local mcm_state=status(false,true,false,'mcm');local mcm_open=true
 s.G.DBFMCM={input_status=function()return mcm_state end,is_open=function()return mcm_open end}
 assert(s.camera.acquire({})==nil and s.camera.recover_native()==false)
 assert(s.native_changes==0 and s.writes==0 and s.resumes==0,'late MCM must block before native menu resume or native/Window changes')
 mcm_state=status(false,false,true);mcm_open=false
 assert(s.camera.acquire({})==nil and s.capture.acquire('bypass')==nil and s.camera.recover_native()==false)
 mcm_state={active=false};assert(s.camera.external_status().available,'documented MCM pre-initialization fallback is inactive')
 s.G.DBFMCM={input_status=function()return status(false,true,false,'replacement MCM')end,is_open=function()return false end}
 assert(s.camera.acquire({})==nil and s.camera.recover_native()==false,'standalone Photo follows current reloaded MCM provider')
 s.G.DBFMCM.is_open=nil;assert(s.camera.external_status()==nil and s.camera.acquire({})==nil)
 s=fixture();s.parent=true
 s.G.DBFMCM={input_status=function()return status(false,true,false,'mcm')end,is_open=function()return true end}
 assert(#s.camera.external_status().owners==1,'shared parent must not duplicate the current MCM owner')
end
do
 local G=empty();local lease=status(true,false,false)
 G.DBFMCM={input_status=function()return lease end,is_open=function()return lease.open end}
 local gate=Standalone.ownership(nil,function()return lease.open,lease end,G)
 local observed=assert(gate.external_status())
 assert(not observed.available and observed.open and not observed.claimed and observed.owner==nil,
  'open-only MCM intent blocks acquisition without claiming Window restoration')
 assert(gate.parent()==true and gate.restore_parent()==false)
 lease=status(true,true,false,'mcm')
 assert(gate.restore_parent()==true,'an actual captured MCM lease still supersedes Photo Window restoration')
end
for _,blocked in ipairs({'photo','parent','loader','epic','unknown_epic','background','native_menu','chat','unknown_menu','unknown_chat','upstream'})do
 local s=fixture()
 if blocked=='photo'then assert(s.camera.acquire({}))
 elseif blocked=='parent'then s.parent=true
 elseif blocked=='loader'then s.G.LiveLuaLoader={input_status=function()return{active=false,pending_restore=true}end}
 elseif blocked=='epic'then s.G.package.loaded['dbf.epic_lut.frontend.v1']={input_status=function()return status(true,true,false,'Epic LUT')end}
 elseif blocked=='unknown_epic'then s.G.package.loaded['dbf.epic_lut.frontend.v1']={}
 elseif blocked=='background'then s.focused=false
 elseif blocked=='native_menu'then s.menu=true
 elseif blocked=='chat'then s.chat=true
 elseif blocked=='unknown_menu'then s.menu=nil
 elseif blocked=='unknown_chat'then s.chat=nil
 elseif blocked=='upstream'then s.upstream=false end
 local writes,changes,resumes=s.writes,s.native_changes,s.resumes
 local ok,why=s.camera.recover_native()
 assert(ok==false and type(why)=='string',blocked..' must refuse native recovery')
 assert(s.writes==writes and s.native_changes==changes and s.resumes==resumes,blocked..' refusal must be mutation-free')
end
do
 local s=fixture();s.mode=3;s.focus=false;s.cursor=true
 assert(s.camera.recover_native()and s.mode==0 and s.native_changes==1 and s.resumes==1)
 assert(s.writes==0 and s.focus==false and s.cursor==true,'native recovery leaves gameplay Window repair to its coordinator')
 s=fixture();s.mode=3;s.sticky=true
 assert(s.camera.recover_native()==false and s.mode==3 and s.resumes==0 and s.writes==0)
 s.sticky=false;assert(s.camera.recover_native()and s.mode==0,'failed release readback remains retryable')
 s=fixture();s.mode=3;s.resume=false
 assert(s.camera.recover_native()==false and s.mode==0 and s.resumes==1 and s.writes==0,'native menu resume requires exact acknowledgement')
 s.resume=true;assert(s.camera.recover_native())
 s=fixture();s.on_resume=function()s.G.package.loaded['dbf.epic_lut.frontend.v1']={input_status=function()return status(true,true,false,'Epic LUT')end}end
 assert(s.camera.recover_native()==false and s.writes==0,'a new editor during resume cannot grant final recovery acknowledgement')
end
print('standalone_ownership_tests: strict LLL/Epic/MCM ownership, pre-resume capture refusal, foreign flags and guarded own-native recovery passed')

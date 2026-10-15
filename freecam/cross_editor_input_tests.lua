local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Capture=dofile(root..'photo_input_capture.lua')
local Camera=dofile(root..'vendor/camera_input.lua')
local Standalone=dofile(root..'standalone.lua')
-- Optional source injection runs exactly these contracts against Epic LUT's
-- canonical vendor/menu/capture.lua. CI remains independent of that checkout.
local injected=rawget(_G,'DBF_PHOTO_EPIC_CAPTURE_SOURCE')
local Editor
if type(injected)=='string'then Editor=assert(loadstring(injected,'actual-epic-capture'))()
else
 Editor={new=function(native,window)
  local self={active=false};local saved
  function self.sync(visible,focused,hwnd)
   if not visible or not focused then return self.release()end
   if self.active then return true end
   if window.mouse_focus()~=true then return false,'Editor gameplay baseline unavailable'end
   saved={focus=window.mouse_focus(),cursor=window.show_cursor(),clip=window.clip_cursor()}
   assert(native.mcm_install(hwnd)==1 and native.mcm_capture(1)==1)
   window.set_mouse_focus(false);window.set_show_cursor(true);window.set_clip_cursor(true)
   self.active=true;return true
  end
  function self.release()
   if not self.active and not saved then return true end
   native.mcm_release()
   window.set_mouse_focus(saved.focus);window.set_show_cursor(saved.cursor);window.set_clip_cursor(saved.clip)
   self.active=false;saved=nil;return true
  end
  function self.status()return{active=self.active,pending_restore=saved~=nil and not self.active}end
  return self
 end}
end
local mcm_source=rawget(_G,'DBF_PHOTO_MCM_CAPTURE_SOURCE')
local MCMEditor=type(mcm_source)=='string'and assert(loadstring(mcm_source,'actual-mcm-capture'))()or Editor
local function fixture(initial,kind)
 local s={flags={focus=true,cursor=initial.cursor,clip=initial.clip},writes=0,gate={0,0},native_changes={0,0},focused=true}
 local window={}
 for _,entry in ipairs({{'mouse_focus','focus'},{'show_cursor','cursor'},{'clip_cursor','clip'}})do
  local name,key=entry[1],entry[2]
  window[name]=function()return s.flags[key]end
  window['set_'..name]=function(value)s.writes=s.writes+1;s.flags[key]=value;return true end
 end
 local function helper(index)
  return{mcm_install=function()s.native_changes[index]=s.native_changes[index]+1;return 1 end,
   mcm_set_cursor_mode=function()s.native_changes[index]=s.native_changes[index]+1;return 1 end,
   mcm_capture=function(mode)s.gate[index]=mode;s.native_changes[index]=s.native_changes[index]+1;return 1 end,
   mcm_captured=function()return s.gate[index]end,
   mcm_release=function()s.gate[index]=0;s.native_changes[index]=s.native_changes[index]+1 end}
 end
 local editor_native,photo_native=helper(1),helper(2)
 local editor=(kind and MCMEditor or Editor).new(editor_native,window,function()end)
 local ownership
 if kind then
  local globals={package={loaded={}}};s.menu_open=false
  if kind=='MCM'then globals.DBFMCM={input_status=editor.status,is_open=function()return s.menu_open end}
  else globals.LiveLuaLoader={input_status=function()
   local state=editor.status();return{active=state.active,pending_restore=state.pending_restore,owner=state.owner,open=s.menu_open}
  end}end
  ownership=Standalone.ownership(nil,nil,globals);s.ownership=ownership
 end
 local capture=Capture.new(window,ownership and ownership.restore_parent or function()return false end)
 local input={poll=function()end,focused=function()return s.focused end,window=function()return 1 end,
  lock_aim=function()window.set_mouse_focus(false);return true end,
  menu_cursor=function(menu)window.set_mouse_focus(false);window.set_show_cursor(menu);window.set_clip_cursor(true);return true end,
  down=function()return false end,wheel=function()return 0 end}
 s.editor,s.capture,s.photo=editor,capture,Camera.new(photo_native,capture,input,ownership and ownership.available or function()return true end)
 return s
end
for _,baseline in ipairs({{cursor=false,clip=false},{cursor=false,clip=true},{cursor=true,clip=true}})do
 local s=fixture(baseline)
 assert(s.editor.sync(true,true,1)and s.flags.focus==false and s.gate[1]==1)
 local writes=s.writes;local other=s.native_changes[1]
 for attempt=1,3 do
  local token,why=s.photo.acquire({})
  assert(token==nil and why:find('already disabled',1,true),'Photo must refuse another editor\'s disabled gameplay focus')
  assert(s.writes==writes and s.native_changes[2]==0,'refusal must precede any Window or own native mutation')
  assert(s.gate[1]==1 and s.native_changes[1]==other,'refusal cannot release the editor\'s different native helper')
  assert(not s.photo.status().active and not s.capture.status().active,'a refused baseline cannot leave a retained Photo lease')
 end
 assert(s.editor.release()and s.flags.focus==true)
 assert(s.photo.acquire({}),'normal acquisition must recover after the owning editor closes')
 assert(s.photo.sample({})and s.flags.focus==false)
 assert(s.photo.release()and s.gate[1]==0 and s.gate[2]==0)
 assert(s.flags.focus==true and s.flags.cursor==baseline.cursor and s.flags.clip==baseline.clip,
  'Photo release restores the exact original gameplay flags, preserving cursor and clip preferences')
end
do
 local s=fixture({cursor=false,clip=false});s.flags.focus=false
 local token,why=s.capture.acquire('dbf_freecam')
 assert(token==nil and why:find('already disabled',1,true)and s.writes==0 and not s.capture.status().active,
  'an unregistered focus owner is still protected when no shared native gate reports it')
 assert(s.photo.release()and s.native_changes[2]==0 and not s.flags.focus,'inactive Photo cleanup must not force-recover foreign focus')
 s.flags.focus='unknown';token,why=s.capture.acquire('dbf_freecam')
 assert(token==nil and why:find('state unavailable',1,true)and s.writes==0,'existing boolean state validation remains strict')
end
for _,kind in ipairs({'MCM','LLL'})do
 -- Public menu-open intent may be observed before that frontend's capture tick.
 local s=fixture({cursor=false,clip=true},kind);assert(s.photo.acquire({})and not s.flags.focus)
 s.menu_open=true
 local state=assert(s.ownership.external_status())
 assert(state.open and not state.available and not state.claimed and state.owner==nil)
 assert(s.photo.release()and s.flags.focus,'open-only intent must restore Photo gameplay baseline before the waiting menu captures')
 assert(s.editor.sync(true,true,1)and not s.flags.focus and s.gate[1]==1)
 s.menu_open=false;assert(s.editor.release()and s.flags.focus and not s.flags.cursor and s.flags.clip)
 assert(s.gate[1]==0 and s.gate[2]==0)
 -- The opposite update order: the menu refuses disabled focus and immediately
 -- closes (MCM's real adapter policy), then Photo restores its existing lease.
 s=fixture({cursor=false,clip=false},kind);assert(s.photo.acquire({}))
 s.menu_open=true;assert(s.editor.sync(true,true,1)==false)
 s.menu_open=false;assert(s.editor.release())
 assert(s.photo.release()and s.flags.focus and not s.flags.cursor and not s.flags.clip)
 s.menu_open=true;assert(s.editor.sync(true,true,1));s.menu_open=false;assert(s.editor.release()and s.flags.focus)
end
print('cross_editor_input_tests: '..(injected and'actual Epic capture'or'self-contained editor')..
 ' + Photo two-native-gate overlap refusal, no-write ownership protection, MCM/LLL open-intent ordering and exact gameplay restoration passed')

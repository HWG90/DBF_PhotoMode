local input_factory=assert(loadfile('freecam/steam_input.lua'))()
local recovery=assert(loadfile('freecam/input_cleanup.lua'))()
local service_factory=assert(loadfile('freecam/test_reference/input_service_r35.lua'))()
local DENIED='Keyboard request refused (0x00000005)'
local function fixture(failure,revision)
 local keyboard_owner;local mask=string.rep('\255',32);local focused=true;local cursor_owner
 local platform={keyboard_capture_mask=mask}
 function platform.keyboard_prepare()
  local handle={};keyboard_owner={handle=handle,client=1,generation=0,attempted=false};return handle
 end
 function platform.keyboard_acquire(handle)
  assert(keyboard_owner.handle==handle);keyboard_owner.attempted=true
  if failure=='lost'then error('lost reply')end
  if failure=='accepted'then keyboard_owner.accepted=true;keyboard_owner.generation=7;return true end
  keyboard_owner.accepted=false;keyboard_owner.reason=DENIED;return false,DENIED
 end
 function platform.keyboard_release(handle)
  assert(keyboard_owner.handle==handle)
  return false,failure=='lost'and'lost reply'or DENIED
 end
 function platform.keyboard_snapshot()error('Unaccepted keyboard lease sampled')end
 function platform.pointer_snapshot()return{valid=true,x=5,y=5,width=100,height=100,buttons=0,wheel=0}end
 function platform.camera_snapshot()return{valid=true,x=5,y=5,width=100,height=100,buttons=0,wheel=0,dx=0,dy=0}end
 function platform.release_pointer()return true end
 local capture={status=function()return{owner=cursor_owner,pending_restore=false}end,
  acquire=function(owner)cursor_owner=owner;return{}end,
  activate=function()focused=false;return true end,
  release=function()focused=true;cursor_owner=nil;return true end}
 local sr={Window={has_focus=function()return true end},Gui={resolution=function()return 100,100 end},
  Keyboard={button_id=function(name)return name=='p'and 1 or 2 end,button=function(id)return id==1 end}}
 _G.DBFMCM=nil
 local service=service_factory.new(platform,sr.Window,capture)
 _G.LiveLuaLoader={capabilities={revision=revision or 'R35-26088801-cffi-dev.2'},input_service=service}
 return input_factory.new(sr,service,recovery),service,function()return focused,keyboard_owner end
end
local input,service,inspect=fixture('denied')
assert(input.set_mode('menu'),'Explicit refusal must roll back and use engine input')
assert(input.keyboard_fallback)
local state=service.status();assert(state.owner=='dbf_freecam'and state.active and not state.keyboard)
local _,owner=inspect();assert(owner==nil,'Rejected keyboard authority was not retired')
input.frame();assert(input.sample());assert(input.down(80),'P must remain readable through the engine')
assert(input.release());local focus=inspect();assert(focus and service.status().owner==nil)
input,service,inspect=fixture('denied','R35-26088801-cffi-insert-fix.2')
assert(input.set_mode('menu')and input.keyboard_fallback)
assert(input.release());assert(inspect()and service.status().owner==nil)
input,service,inspect=fixture('denied','unknown-loader')
assert(input.set_mode('menu')==false and not input.keyboard_fallback)
assert(service.status().pending_restore,'Unqualified loader must retain ownership')
-- A lost reply may have created a native registration. Do not clear it or
-- silently downgrade to engine input while that ownership is uncertain.
input,service,inspect=fixture('lost')
assert(input.set_mode('menu')==false)
local focus,unknown=inspect();assert(unknown and unknown.attempted and not input.keyboard_fallback)
assert(service.status().pending_restore)

-- Even a misleading later error cannot retire an accepted native generation.
input,service,inspect=fixture('accepted')
assert(input.set_mode('menu'))
assert(input.release()==false)
local _,accepted=inspect();assert(accepted and accepted.accepted and accepted.generation==7)
assert(service.status().pending_restore and not input.keyboard_fallback)

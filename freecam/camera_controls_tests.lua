-- Exclusive camera ownership outlives input capture while any Photo cleanup is pending.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local controller=dofile(root..'controller.lua');local core=dofile('src/core.lua')
local function fixture()
 local calls={acquire=0,release=0,input_acquire=0,input_release=0};local state={lease=false,input=false,effect_ok=true,input_ok=true,time_pending=false,enter_ok=true,native_open=false}
 local photo={active=false,input={}}
 local input={down=function()return false end,focused=function()return true end,
  native_menu_active=function()return state.native_open end,
  native_menu_handoff=function()calls.input_release=calls.input_release+1;state.input=false;return true end,
  acquire=function()assert(state.lease,'Camera ownership must precede native input');calls.input_acquire=calls.input_acquire+1;state.input=true;return{}end,
  release=function()calls.input_release=calls.input_release+1;if not state.input_ok then return false,'native input pending'end;state.input=false;return true end,
  sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
 local ownership={acquire=function()calls.acquire=calls.acquire+1;state.lease=true;if not state.enter_ok then return false,'original camera cleanup failed'end;return true end,
  release=function()if not state.lease then return true end;assert(not state.input and state.effect_ok and not state.time_pending,'Camera ownership released before Photo cleanup');calls.release=calls.release+1;state.lease=false;return true end}
 local effects={release=function()return state.effect_ok,'effects pending'end,apply=function()return true end,capabilities=function()return{}end}
 local freeze={release=function()return true end,hold=function()return true end,needs_input_capture=function()return state.time_pending end}
 DBFMCM=core.new(nil,function()end);DBFMCM.camera_input=input;DBFMCM.is_open=function()return false end;DBFMCM.close=function()return true end
 local c=controller.new(photo,{},function()return true end,function()end,freeze,nil,effects,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,ownership)
 c.tick(.016)
 local handle=assert(DBFMCM.mods.dbf_freecam).handle
 assert(handle.set('freeze_player',false))
 return c,photo,state,calls,handle
end
local c,photo,state,calls,h=fixture();assert(h.activate('toggle'));assert(photo.active and state.lease and state.input)
state.effect_ok=false;assert(not c.stop());assert(not photo.active and state.lease and not state.input and calls.release==0)
state.effect_ok=true;assert(c.stop());assert(not state.lease and calls.release==1)
assert(h.activate('toggle'));state.input_ok=false;assert(not c.stop());assert(state.lease and calls.release==1)
state.input_ok=true;assert(c.stop());assert(not state.lease and calls.release==2)
assert(h.activate('toggle'));state.time_pending=true;assert(not c.stop());assert(state.input and state.lease and calls.release==2)
state.time_pending=false;assert(c.stop());assert(not state.input and not state.lease and calls.release==3)
assert(c.close())
local shared,p3,s3,n3,h3=fixture();assert(h3.activate('toggle'))
local held_pos,held_view={3,4,5},{0,1,0};p3.pos,p3.view=held_pos,held_view
s3.native_open=true;shared.tick(.016)
assert(p3.active and s3.lease and not s3.input and shared.camera_suspended()and n3.release==0,'Native menus must yield only Photo input while retaining its camera lease')
assert(p3.pos==held_pos and p3.view==held_view,'Native menu handoff must preserve the composed Photo view')
assert(h3.activate('toggle'));assert(p3.active and s3.lease and n3.acquire==1,'Native menu must refuse Photo reactivation and retain its camera lease')
s3.native_open=false;shared.tick(.016)
assert(p3.active and s3.lease and s3.input and n3.input_acquire==2 and n3.acquire==1,'Closing the native menu must restore Photo input without reacquiring its camera lease')
assert(shared.stop()and not s3.lease and not s3.input and n3.release==1);assert(shared.close())
local failed,failed_photo,s2,n2,h2=fixture();s2.enter_ok=false
assert(h2.activate('toggle'));assert(not failed_photo.active and not s2.lease and not s2.input and n2.input_acquire==0 and n2.release==1)
assert(failed.close())
DBFMCM=nil
print('Photo camera controller lease: acquire-before-input, effect/time/input cleanup retries, native-menu view/input handoff and failed-entry cancellation passed')

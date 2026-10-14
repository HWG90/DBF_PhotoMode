local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Core=dofile('src/core.lua');local Controller=dofile(root..'controller.lua');local Options=dofile(root..'photo_options.lua')
local keys={};local fail=false;local close_calls=0;local effects_released=0;local time_released=0;local input_released=0;local keyups=0;local subject_restore=0;local ai_restore=0
local service=Core.new(nil,function()end);service.is_open=function()return false end
service.create_photo_view=function()return{}end;service.photo_resolution=function()return 1920,1080 end
service.camera_input={down=function(k)return keys[k]or false end,focused=function()return true end,acquire=function()return{}end,
 release=function()input_released=input_released+1;return true end,sample=function()return{wheel=0,mouse_x=0,mouse_y=0,dt=.016}end}
local factory={new=function()return{bind=function()end,draw=function()end,tick=function()end,editing_key=function()return false end,
 close=function()close_calls=close_calls+1;if fail then error('retired GUI fixture')end end}end}
local effects={parameters={},release=function()effects_released=effects_released+1;return true end}
local freeze={start=function()return true end,release=function()time_released=time_released+1;return true end,hold=function()return true end}
local subject={pending=false,count=function()return 1 end,queue=function(v)if v==nil then subject_restore=subject_restore+1 end;return true end,
 refresh=function()return false,'fixture'end,release=function()return true end}
local ai={mode='normal',count=function()return 0 end,ready=function()return true end,queue=function(mode)if mode=='normal'then ai_restore=ai_restore+1 end;return true end}
local photo={};DBFMCM=service
local ctrl=Controller.new(photo,{},function()return true end,function()end,freeze,Options,effects,factory,nil,nil,nil,nil,nil,subject,nil,nil,nil,ai)
ctrl.tick(.016);keys[80]=true;ctrl.tick(.016);keys[80]=false;ctrl.tick(.016);assert(photo.active)
-- Inject teardown failures only after a live input lease exists.
ctrl._input_release={finish=function()keyups=keyups+1;return true end}
ai.mode='dummy';fail=true
local before={effects_released,time_released,input_released,keyups,subject_restore,ai_restore}
local ok,why=ctrl.stop()
assert(ok==false and why:find('retired GUI fixture',1,true)and not photo.active and ctrl._panel_close_pending)
assert(effects_released>before[1]and time_released>before[2]and input_released>before[3],'Menu exception prevented effect/time/input cleanup')
assert(keyups==0,'Photo exit injected synthetic button releases')
assert(subject_restore>before[5]and ai_restore==before[6],'Menu exception prevented subject cleanup or discarded persistent AI behavior')
assert(ctrl.close()==false and service.mods.dbf_freecam,'Failed menu close abandoned retry')
assert(ai_restore>before[6],'Shutdown did not queue AI cleanup')
ai.mode='normal';fail=false;local tried=close_calls
assert(ctrl.close()and close_calls>tried and not ctrl._panel_close_pending and not service.mods.dbf_freecam,'Successful retry failed to complete shutdown')
DBFMCM=nil
print('Photo close cleanup: GUI exception preserves retry while effect, time, input and queued subject/AI cleanup continue')

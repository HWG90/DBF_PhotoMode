-- Offline ownership tests; these do not reproduce an HDR/device reset.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'photo_runtime.lua')
local worlds={10,20};local unavailable=false;local malformed=false;local refuse_destroy=false
local created,destroyed={},{};local lens_releases,postfx_releases=0,0
local sr={Application={main_world=function()return 10 end,worlds=function()
 if unavailable then error('World list temporarily unavailable')end
 if malformed then return nil end
 return worlds
end},World={create_screen_gui=function(owner)
 local gui={owner=owner};created[#created+1]=gui;return gui
end,destroy_gui=function(owner,gui)
 assert(owner==gui.owner,'Wrong GUI owner')
 local live=false;for _,value in ipairs(worlds)do if value==owner then live=true end end
 assert(live,'Retired world reached native destructor')
 if refuse_destroy then error('Native cleanup refused')end
 destroyed[#destroyed+1]=gui
end},Gui={resolution=function()return 1920,1080 end}}
local lens={new=function()return {apply=function()return .9 end,release=function()lens_releases=lens_releases+1;return true end}end}
local postfx={new=function()return {parameters={},apply=function()return true,'fixture' end,release=function()postfx_releases=postfx_releases+1;return true end}end}
local composition={shaders={''},layout=function()return {}end}
local options={dof=false,dof_mode=1,hide_hud=false,shader=1}
local runtime=factory.new(sr,lens,composition,postfx,function()end)
local function apply()return runtime.apply(1,2,10,{0,1,0},{1,0,0},options,.016)end

assert(apply()and #created==1)
worlds={10,30}
assert(apply()and #created==2 and #destroyed==0,'World replacement must forget the retired GUI without native destruction and create in the new live owner')
assert(runtime.release()and #destroyed==1 and destroyed[1]==created[2],'Ordinary close must destroy its live GUI')
assert(runtime.release()and #destroyed==1,'Repeated close must not destroy twice')

assert(apply()and #created==3)
unavailable=true
local ok,why=runtime.release()
assert(not ok and why=='Photo GUI world lifetime unavailable'and #destroyed==1,'Unavailable listing must preserve GUI ownership without a native call')
unavailable=false;malformed=true
assert(not runtime.release()and #destroyed==1,'Malformed listing must not be treated as proof of world retirement')
malformed=false;refuse_destroy=true
assert(not runtime.release()and #destroyed==1,'A failed live destructor must preserve ownership for retry')
refuse_destroy=false
assert(runtime.release()and #destroyed==2 and destroyed[2]==created[3],'Known live ownership must retry the same GUI exactly once')
assert(runtime.release()and #destroyed==2)

assert(apply()and #created==4)
worlds={}
assert(runtime.release()and #destroyed==2,'A confirmed absent world must never enter native GUI cleanup')
assert(lens_releases>0 and postfx_releases>0,'GUI ownership guards must retain the other cleanup paths')
print('Photo GUI lifecycle: retired-world replacement/close, ordinary cleanup, unknown-list retry, destructor retry and idempotence passed; no live HDR/display crash claim')

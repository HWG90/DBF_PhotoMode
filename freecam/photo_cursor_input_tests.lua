local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Attach=dofile(root..'photo_cursor_input.lua')
local Camera=dofile(root..'vendor/camera_input.lua')
local Clip=dofile(root..'cursor_capture.lua')
local desktop={0,0,6400,2160};local client={0,0,3840,2160};local current=desktop;local writes=0;local focused=true;local leased=false;local mode=0;local released=0;local refuse=false
local function equal(a,b)for i=1,4 do if a[i]~=b[i]then return false end end;return true end
local clip=Clip.new({window=function()if not focused then return nil,'focus_lost'end;return{window=1,rect=client}end,
 clip=function()return current end,write=function(target,expected)assert(equal(current,expected));if refuse then return false,'refused'end;current=target or desktop;writes=writes+1;return true,current,true end})
local native={mcm_release=function()mode=0 end,mcm_captured=function()return mode end,mcm_install=function()return 1 end,mcm_capture=function(m)mode=m;return 1 end}
local capture={acquire=function()leased=true;return{}end,owns=function()return leased end,release=function()released=released+1;leased=false;return true end}
local cursor_flags=false
local input={poll=function()end,focused=function()return focused end,window=function()return 1 end,down=function()return false end,wheel=function()return 0 end,
 lock_aim=function()return true end,menu_cursor=function(menu)cursor_flags=menu;return true end,look=function()return 0,0 end,mouse=function()return 1,1 end}
local camera=Attach.attach(Camera.new(native,capture,input,function()return true end),input,clip)
assert(camera.acquire()and mode==3 and equal(current,client),'Engine boolean alone did not confine the camera')
local n=writes;assert(camera.sample()and writes==n,'Stable capture rewrites Windows each frame')
assert(camera.set_focus(true)and mode==1 and cursor_flags and equal(current,client),'Menu transition lost confinement')
assert(camera.menu_sample()and equal(current,client));assert(camera.set_focus(false)and mode==3 and not cursor_flags and equal(current,client))
client={100,50,2660,1490};assert(camera.sample()and equal(current,client),'Window resize retained stale bounds')
focused=false;assert(camera.sample()==nil and mode==0 and not leased and equal(current,desktop),'AltTab did not restore mouse freedom')
focused=true;assert(camera.acquire());refuse=true;assert(camera.release()==false and mode==3 and leased,'Failed confinement restoration discarded the input lease')
refuse=false;assert(camera.release()and not leased and mode==0 and equal(current,desktop))
assert(camera.acquire());current={300,200,700,600};n=writes;assert(camera.sample()==nil and writes==n and equal(current,{300,200,700,600}),'Foreign confinement was overwritten')
assert(not pcall(Attach.attach,camera,input,clip),'Duplicate confinement attached')
print('Photo cursor input: actual Windows rectangle despite stale engine flag, camera/menu transitions, stable writes, resize, AltTab, release retry and foreign ownership passed')

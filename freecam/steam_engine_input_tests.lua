-- Engine input service: Window flags held and restored, cursor/motion conversion, and the
-- real steam_input consumer on top of it. Fake engine only.
local root='freecam/'
local flags={mouse_focus=true,show_cursor=false,clip_cursor=true};local refuse
local W={}
for _,name in ipairs({'mouse_focus','show_cursor','clip_cursor'})do
 W[name]=function()return flags[name]end
 W['set_'..name]=function(value)if refuse~=name then flags[name]=value end end
end
W.has_focus=function()return true end
local axes={mouse={x=0,y=0},cursor={x=0,y=0},wheel={x=0,y=0}};local ids={mouse=0,wheel=1,cursor=2}
local down={}
local Mouse={axis_id=function(name)return ids[name]end,button_id=function(name)return({left=0,right=1,middle=2})[name]end,
 axis=function(id)for name,i in pairs(ids)do if i==id then return axes[name]end end end,button=function(id)return down[id]and 1 or 0 end}
local sr={Window=W,Mouse=Mouse,Gui={resolution=function()return 1920,1080 end},Keyboard={button_id=function()return 7 end,button=function()return 0 end}}
local service=dofile(root..'engine_input.lua').new(sr)
assert(service.version==1 and service.capabilities.menu and service.capabilities.camera and service.capabilities.relative_mouse and service.capabilities.keyboard==false)
local token=assert(service.acquire('dbf_freecam','menu'))
assert(flags.mouse_focus==false and flags.show_cursor==true and flags.clip_cursor==true,'Menu lease takes the mouse from the game and shows the cursor')
assert(service.acquire('other','menu')==nil,'One lease at a time')
axes.cursor={x=100,y=1000};axes.wheel={x=0,y=-1};axes.mouse={x=3,y=4};down[0]=true
local s=service.snapshot(token)
assert(s.valid and s.x==100 and s.y==80 and s.width==1920 and s.height==1080,'Cursor converts to client top-left')
assert(s.buttons==1 and s.wheel==-120 and s.dx==3 and s.dy==-4,'Buttons, wheel notches and y-down motion')
assert(service.release(token)and flags.mouse_focus==true and flags.show_cursor==false and flags.clip_cursor==true,'Release restores the saved flags')
assert(service.snapshot(token)==nil,'A released token samples nothing')
refuse='show_cursor';flags.show_cursor=false
assert(service.acquire('dbf_freecam','menu')==nil and flags.mouse_focus==true,'A refused flag rolls the others back')
refuse=nil
-- The real consumer: engine keys stay active because the host does not capture the keyboard.
local input=dofile(root..'steam_input.lua').new(sr,service,nil,{require_keyboard=false})
assert(input.set_mode('menu'));input.frame()
axes.cursor={x=960,y=540};down[0]=false
assert(input.sample().buttons==0);input.frame();down[1]=true
local sample=assert(input.sample())
assert(sample.valid and sample.x==960 and sample.y==540 and sample.right and not sample.click,'Menu sample through steam_input')
assert(input.set_mode('camera')and flags.show_cursor==false and flags.mouse_focus==false,'Camera keeps the cursor hidden')
input.frame();input.sample();input.frame();axes.mouse={x=5,y=-2};down[1]=false
sample=assert(input.sample());assert(sample.dx==5 and sample.dy==2,'Camera motion after the first sample')
assert(input.release()and flags.mouse_focus==true,'Closing returns the mouse to the game')
print('Engine input: Window flags held and restored, refused flag rollback, cursor/motion conversion and steam_input on the engine host passed')

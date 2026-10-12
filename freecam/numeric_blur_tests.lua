local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local api=dofile(root..'vendor/core.lua').new()
local commits=0
local handle=api.register({id='blur_photo',name='Photo blur fixture',on_change=function()commits=commits+1 end,pages={
 {id='camera',name='Camera',require_confirmation=false,controls={
  {id='focus',type='slider',label='Focus',default=5,min=.1,max=200,step=.01,fine_step=.001,commit_on_blur=true},
  {id='other',type='slider',label='Other',default=2,min=0,max=20,step=1,commit_on_blur=true}}},
 {id='second',name='Second',require_confirmation=false,controls={}}}})
local commands,keys={},{}
local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()end},{})
menu.bind(handle,api.mods.blur_photo.pages)
local function draw()menu.draw(1920,1080,true,false,{focus='TAB',hide='H'})end
local function tick(input)menu.tick(input or {click=false,dt=.016},function(k)return keys[k]or false end)end
local function press(k)keys[k]=true;tick();draw();keys[k]=false;tick();draw()end
local function begin()menu.page=1;menu.selection=1;draw();press(13);assert(menu.editing_text())end
local function type_value(codes)for _,k in ipairs(codes)do press(k)end end
local function click(x,y)tick({click=true,x=x,y=y,dt=.016});draw();tick({click=false,dt=.016});draw()end
local function field(id)local b;for _,c in ipairs(commands)do if c.ui_role=='field'and c.control_id==id then b=c end end;return assert(b)end
draw();tick();begin();type_value({49,190,52,48,53});local before=commits
click(1,800);assert(math.abs(handle.get('focus')-1.405)<1e-9 and not menu.editing_text(),'Clicking outside must commit fine typed precision')
tick();draw();assert(commits==before+1,'Blur must commit exactly once')
begin();type_value({50});assert(menu.dismiss());assert(math.abs(handle.get('focus')-1.405)<1e-9,'Escape must cancel typed changes')
begin();type_value({190});before=commits;click(1,800)
assert(menu.editing_text()and commits==before and math.abs(handle.get('focus')-1.405)<1e-9,'Partial invalid text must retain the editor without persistence')
press(83);assert(menu.selection==1 and menu.editing_text()and commits==before,'Invalid numeric drafts must block W/S row navigation')
assert(menu.dismiss());begin();type_value({51});local other=field('other');click(other.x+other.w/2,other.y+other.h/2)
assert(handle.get('focus')==3 and handle.get('other')==2 and menu.editing_text(),'Cross-field blur must only update the original field')
assert(menu.dismiss());begin();type_value({52});press(69)
assert(menu.page==2 and handle.get('focus')==4 and not menu.editing_text(),'Page switching must commit pending input')
begin();keys[16]=true;press(68);keys[16]=false
assert(math.abs(handle.get('focus')-4.001)<1e-9,'Shift+A/D must use the fine step')
press(68);assert(math.abs(handle.get('focus')-4.011)<1e-9,'A/D must retain the regular step')
assert(menu.dismiss());begin();type_value({55});assert(menu.blur())
assert(handle.get('focus')==7 and not menu.editing_text(),'Focus transfer must commit via blur')
begin();type_value({56});api.mods.blur_photo.controls.focus.disabled=true;before=commits;assert(menu.blur())
assert(handle.get('focus')==7 and commits==before,'Capability loss must discard a pending edit without committing')
api.mods.blur_photo.controls.focus.disabled=false;begin();type_value({57});menu.close()
assert(handle.get('focus')==9,'Normal close must save a valid pending value')
-- Typing owns A/D until leaving the field; W/S saves the draft then adjusts the next selected row.
draw();tick();begin();type_value({52});before=commits;press(68)
assert(menu.editing_text()and handle.get('focus')==9 and commits==before,'A/D must not modify the saved value while a typed draft owns input')
press(83);assert(menu.selection==2 and handle.get('focus')==4 and not menu.editing_text(),'W/S must commit valid typed input before row navigation')
press(68);assert(handle.get('other')==3 and handle.get('focus')==4,'A/D must immediately adjust the newly selected row')
print('PASS Photo numeric blur, exact-once persistence, Escape, invalid draft, typed input ownership, W/S blur navigation, field ownership, page/focus/close and fine adjustment')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua').new(nil,function()end);local controls={{id='value',type='slider',label='Numeric value',default=3,min=-10,max=10,step=.5},
 {id='other',type='slider',label='Other value',default=2,min=0,max=20,step=1},{id='disabled',type='slider',label='Disabled value',default=4,min=0,max=10,step=1,disabled=true},
 {id='choice',type='choice',label='Choice',default=1,choices={'One','Two'}},{id='binding',type='keybind',label='Binding',default=220},
 {id='action',type='button',label='Action',on_activate=function()error('Reset must never activate an action')end},{id='status',type='text',label='Status'}}
local handle=core.register({id='numeric_photo',name='Photo',pages={{id='camera',name='Camera',require_confirmation=false,controls=controls}}})
local commands;local keys={};local menu=dofile(root..'photo_menu.lua').new({draw=function(c)commands=c end,release=function()commands={}end},{focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(handle,core.mods.numeric_photo.pages)
local function draw(focused)menu.draw(1920,1080,focused~=false,false,{focus='TAB',hide='H'})end
local function tick(input)menu.tick(input or {click=false,dt=.016},function(k)return keys[k]or false end)end
local function press(k)keys[k]=true;tick();draw();keys[k]=false;tick();draw()end
local function field(id,last)local result;for _,c in ipairs(commands)do if c.ui_role=='field'and c.control_id==id then result=c;if not last then break end end end;assert(result);return result end
local function begin()menu.selection=1;draw();press(13);assert(menu.editing_text())end
local function type_number(codes)for _,k in ipairs(codes)do press(k)end end
local function reset(id)
 local b=field(id);keys[2]=true;tick({x=b.x+b.w/2,y=b.y+b.h/2,click=false,dt=.016});draw();keys[2]=false;tick();draw()
end
draw();tick();begin();type_number({189,50,190,55});assert(handle.get('value')==3,'Typed edits remain pending');press(13);assert(handle.get('value')==-2.5 and not menu.editing_text(),'Commit rounds to the registered step')
begin();type_number({57,57,57});press(32);assert(handle.get('value')==10,'Space commits and clamps upper bound')
begin();type_number({189,57,57});press(13);assert(handle.get('value')==-10,'Commit clamps lower bound')
begin();type_number({190});press(13);assert(menu.editing_text()and handle.get('value')==-10,'Invalid input must not save or exit')
press(8);type_number({49,190,53});press(13);assert(handle.get('value')==1.5)
begin();type_number({50});assert(menu.dismiss());assert(handle.get('value')==1.5 and not menu.editing_text(),'Escape-style dismissal cancels pending input')
begin();press(68);assert(handle.get('value')==2,'A/D stepping remains available before typing');press(13);assert(not menu.editing_text())
-- Clicking the numeric box enters typing; Ctrl+A/Backspace/Delete replace a pending number.
local number_box=field('value',true);tick({x=number_box.x+number_box.w/2,y=number_box.y+number_box.h/2,click=true});tick({click=false});draw();assert(menu.editing_text())
type_number({49,50});keys[17]=true;press(65);keys[17]=false;type_number({51});press(13);assert(handle.get('value')==3)
begin();press(46);press(13);assert(menu.editing_text(),'Empty numeric input is refused');press(97);press(110);press(101);press(13);assert(handle.get('value')==1.5,'Numpad digits/decimal are supported')
-- Right-click prefers the hovered setting, then the selected setting; it refuses disabled/actions/status.
handle.set('value',7);handle.set('other',9);draw();reset('other');assert(handle.get('other')==2 and handle.get('value')==7)
keys[2]=true;tick({x=1,y=1,click=false});keys[2]=false;tick();draw();assert(handle.get('value')==3,'Outside rows, right-click resets the selected setting')
handle.set('value',6);draw();reset('disabled');assert(handle.get('value')==6 and handle.get('disabled')==4,'Hovering a disabled row must not reset the selected field')
reset('action');assert(handle.get('value')==6)
handle.set('choice',2);draw();reset('choice');assert(handle.get('choice')==1)
-- A keybind capture owns mouse buttons; held input on focus reacquisition is not replayed.
menu.selection=5;draw();press(13);assert(menu.editing_key());keys[2]=true;tick();assert(handle.get('value')==6);keys[2]=false;press(27);assert(not menu.editing_key())
menu.selection=1;draw();begin();keys[49]=true;menu.suspend();tick();draw();keys[49]=false;tick();draw();press(13);assert(handle.get('value')==6,'Focus reacquisition must not type a held digit')
draw(false);keys[2]=true;keys[32]=true;tick();keys[2]=false;keys[32]=false;tick();assert(handle.get('value')==6 and not menu.editing_text(),'Camera focus never edits or resets settings')
menu.close();print('Photo numeric/reset menu: pending typing, decimal/minus/numpad, clamp/step, invalid input, cancel, A/D, Ctrl+A, pointer entry, guarded reset and focus edges passed')

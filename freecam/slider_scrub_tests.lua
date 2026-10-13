local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local core=dofile('src/core.lua').new(nil,function()end)
local controls={{id='precise',type='slider',label='Precise slider',default=50,min=0,max=100,step=1,fine_step=.01},
 {id='coarse',type='slider',label='Coarse slider',default=50,min=0,max=100,step=1},
 {id='disabled',type='slider',label='Disabled slider',default=50,min=0,max=100,step=1,disabled=true},
 {id='color',type='color',label='Color',default='#808080'}}
local handle=core.register({id='slider_scrub',name='Photo',pages={{id='camera',name='Camera',controls=controls}}})
local commands;local shift=false
local menu=dofile(root..'photo_menu.lua').new({draw=function(value)commands=value end,release=function()commands={}end},
 {focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind(handle,core.mods.slider_scrub.pages)
local function draw(focused)menu.draw(1920,1080,focused~=false,false,{focus='TAB',hide='H'})end
local function tick(x,y,click)menu.tick({x=x,y=y,click=click,dt=.016},function(k)return k==16 and shift end);draw()end
local function find(role,id)for _,command in ipairs(commands)do if command.ui_role==role and command.control_id==id then return command end end;error('Missing '..role..' '..id)end
local function track(id)local b=find('slider_track',id);return b,b.y+b.h/2 end
local function near(id,expected,message)assert(math.abs(handle.get(id)-expected)<.000001,(message or id)..': '..handle.get(id)..' ~= '..expected)end
local function release()tick(nil,nil,false)end
draw();release()
-- Normal drags still map directly onto the track, including outside bounds.
local b,y=track('precise');tick(b.x+b.w*.25,y,true);near('precise',25)
tick(b.x+b.w*.4,y,true);near('precise',40)
tick(b.x+b.w*1.5,y,true);near('precise',100);release()
-- A Shift click preserves the current value even when far from its thumb.
handle.set('precise',50);shift=true;b,y=track('precise');local x=b.x+b.w*.95
tick(x,y,true);near('precise',50,'Shift click must anchor the current value')
x=x+b.w*.5;tick(x,y,true);near('precise',55,'Half a track while shifted moves only five percent of the range')
x=x+b.w*.01;tick(x,y,true);near('precise',55.1)
x=x-b.w*.001;tick(x,y,true);near('precise',55.09,'Fine drag reaches values between normal steps')
shift=false;tick(x,y,true);near('precise',55.09,'Releasing Shift without moving must not jump')
x=x+b.w*.05;tick(x,y,true);near('precise',60.09,'Unshifted motion resumes at full speed from the refined value')
shift=true;tick(x,y,true);near('precise',60.09,'Pressing Shift without moving must not jump')
x=x-b.w*.1;tick(x,y,true);near('precise',59.09);release()
-- Entering Shift during a normal drag keeps its applied value and pointer offset.
shift=false;b,y=track('precise');x=b.x+b.w*.5;tick(x,y,true);near('precise',50)
x=x+b.w*.1;tick(x,y,true);near('precise',60)
shift=true;tick(x,y,true);near('precise',60);x=x+b.w*.1;tick(x,y,true);near('precise',61)
shift=false;tick(x,y,true);near('precise',61);x=x+b.w*.1;tick(x,y,true);near('precise',71);release()
b,y=track('precise');tick(b.x+b.w*.1,y,true);near('precise',10,'A new normal drag returns to absolute track mapping');release()
-- Small movements accumulate before rounding through the authoritative MCM handle.
handle.set('precise',50);shift=true;b,y=track('precise');x=b.x+b.w*.5;tick(x,y,true)
for i=1,10 do tick(x+b.w*.0001*i,y,true)end;near('precise',50.01,'Sub-step pointer motion must accumulate');release()
-- Bounds discard overshoot so reversing direction immediately moves the value.
handle.set('precise',99);b,y=track('precise');x=b.x+b.w*.5;tick(x,y,true)
x=x+b.w*20;tick(x,y,true);near('precise',100);x=x-b.w*.1;tick(x,y,true);near('precise',99)
x=x-b.w*20;tick(x,y,true);near('precise',0);x=x+b.w*.1;tick(x,y,true);near('precise',1);release()
-- Coarse-only controls keep their registered increment but require ten times the travel.
b,y=track('coarse');x=b.x+b.w*.5;tick(x,y,true);near('coarse',50)
tick(x+b.w*.04,y,true);near('coarse',50);tick(x+b.w*.1,y,true);near('coarse',51);release()
b,y=track('disabled');tick(b.x+b.w*.9,y,true);tick(b.x+b.w*2,y,true);near('disabled',50);release()
-- Losing menu focus cancels a scrub rather than replaying camera pointer movement.
b,y=track('precise');handle.set('precise',50);x=b.x+b.w*.5;tick(x,y,true)
draw(false);tick(x+b.w,y,true);near('precise',50);release();shift=false
-- Color channels use the same slower relative motion with legal integer RGB values.
menu.selection=4;draw();local field=find('field','color');tick(field.x+field.w/2,field.y+field.h/2,true);release()
local channel;for _,command in ipairs(commands)do if command.ui_role=='field'and command.ui_key=='channel:1'then channel=command end end;assert(channel)
shift=true;x=channel.x+channel.w*.9;y=channel.y+channel.h/2;tick(x,y,true);assert(handle.get('color')=='#808080')
tick(x+channel.w*.2,y,true);assert(handle.get('color')=='#858080','Shift RGB drag advances five channel levels for one fifth of a track');release()
menu.close()
print('Photo slider scrubbing: real MCM handles, normal mapping, 10x slower Shift motion, fine increments, continuous modifier transitions, accumulated tiny movement, immediate clamp reversal, coarse controls, disabled/focus guards and RGB channels passed')

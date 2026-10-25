-- Engine input service: Window flags untouched, a virtual menu cursor from relative motion,
-- camera motion passed through, a mouse missing in the first frames, the _id fallback,
-- one log line per first event, and the real steam_input consumer on top. Fake engine only.
local root='freecam/'
local window_calls=0
local W=setmetatable({has_focus=function()return true end},{__index=function(_,k)return function()window_calls=window_calls+1 end end})
local motion,wheel={x=0,y=0},{x=0,y=0};local down={};local ready=false
local Mouse={axis=function(id)return id==0 and motion or id==1 and wheel or nil end,button=function(id)return down[id]and 1 or 0 end}
Mouse.axis_index=function(name)if not ready then return nil end;return({mouse=0,wheel=1})[name]end
Mouse.button_index=function(name)return({left=0,right=1,middle=2})[name]end
local sr={Window=W,Mouse=Mouse,Gui={resolution=function()return 1920,1080 end},Keyboard={button_id=function()return 7 end,button=function()return 0 end}}
local lines={}
local service=dofile(root..'engine_input.lua').new(sr,function(m)lines[#lines+1]=m end)
local caps=service.capabilities
assert(service.version==1 and caps.menu and caps.camera and caps.relative_mouse and caps.virtual_cursor and caps.keyboard==false)
assert(service.acquire('dbf_freecam','menu')==nil,'No lease before the engine mouse exists')
ready=true
local token=assert(service.acquire('dbf_freecam','menu'))
assert(service.acquire('other','menu')==nil,'One lease at a time')
local s=service.snapshot(token)
assert(s.valid and s.x==960 and s.y==540 and s.width==1920 and s.height==1080,'The virtual cursor starts at the centre')
motion={x=30,y=-20};down[0]=true;wheel={x=0,y=-1}
s=service.snapshot(token)
assert(s.x==990 and s.y==520 and s.dx==30 and s.dy==-20,'Relative motion moves the cursor (y counts down)')
assert(s.buttons==1 and s.wheel==-120,'Buttons and wheel notches')
motion={x=-5000,y=5000};s=service.snapshot(token);assert(s.x==0 and s.y==1079,'The cursor stays on screen')
assert(service.release(token)and service.snapshot(token)==nil,'A released token samples nothing')
assert(window_calls==0,'Window flags are never changed')
local found,moved,clicked=0,0,0
for _,m in ipairs(lines)do
 if m:find('mouse found',1,true)then found=found+1 end
 if m:find('first mouse motion',1,true)then moved=moved+1 end
 if m:find('first left click',1,true)then clicked=clicked+1 end
end
assert(found==1 and moved==1 and clicked==1,'One log line per first event')
-- Builds that name them _id still work.
local legacy={axis=Mouse.axis,button=Mouse.button,axis_id=function(n)return({mouse=0,wheel=1})[n]end,button_id=Mouse.button_index}
local old=dofile(root..'engine_input.lua').new({Mouse=legacy,Gui=sr.Gui})
assert(old.acquire('dbf_freecam','camera'),'axis_id/button_id fallback')
-- The real consumer: engine keys stay active because the host does not capture the keyboard.
motion={x=0,y=0};down={}
local input=dofile(root..'steam_input.lua').new(sr,service,nil,{require_keyboard=false})
assert(input.set_mode('menu'));input.frame()
local sample=assert(input.sample());assert(sample.valid and sample.x>=0,'Menu sample through steam_input')
input.frame();motion={x=0,y=-10}
sample=assert(input.sample());local up=sample.y
input.frame();motion={x=0,y=10};sample=assert(input.sample());assert(sample.y<up,'Moving the mouse down lowers the menu pointer (menu y grows upward)')
input.frame();motion={x=0,y=0};down[1]=true;sample=assert(input.sample());assert(sample.right and not sample.click,'Right button through steam_input')
down[1]=false
assert(input.set_mode('camera'))
input.frame();input.sample();input.frame();motion={x=5,y=-2}
sample=assert(input.sample());assert(sample.dx==5 and sample.dy==-2,'Camera motion after the first sample, y down as in the contract')
assert(input.release()and window_calls==0,'Closing leaves the game\'s Window flags alone')
-- Keyboard isolation from a bridge: LLL's whitelist mask, arming then active, keys read
-- from the bridge (the engine no longer sees them), mode changes that keep the reservation,
-- a pending release that is retried, and a host whose bridge cannot load falling back.
local function key_mask(codes)local b={};for i=1,32 do b[i]=0 end;for _,c in ipairs(codes)do local i=math.floor(c/8)+1;b[i]=b[i]+2^(c%8)end
 local t={};for i=1,32 do t[i]=string.char(b[i])end;return table.concat(t)end
local K={state=1,keys={},acquired=0,released=0,retiring=0}
local bridge={keyboard_acquire=function(mask)assert(mask==dofile(root..'engine_input.lua').keyboard_mask and#mask==32);K.acquired=K.acquired+1;K.state=1;return 7 end,
 keyboard_sample=function()return K.state,K.state==2 and key_mask(K.keys)or string.rep('\0',32),7 end,
 keyboard_release=function()if K.retiring>0 then K.retiring=K.retiring-1;return false,'Keyboard lease is still retiring'end;K.released=K.released+1;K.state=3;return true end}
lines={};local kb=dofile(root..'engine_input.lua').new(sr,function(m)lines[#lines+1]=m end,function()return bridge end)
assert(kb.capabilities.keyboard==true and kb.capabilities.keyboard_mask==dofile(root..'engine_input.lua').keyboard_mask)
local engine_keys=0;sr.Keyboard.button=function()engine_keys=engine_keys+1;return 0 end
input=dofile(root..'steam_input.lua').new(sr,kb,nil,{require_keyboard=false})
assert(input.set_mode('menu')and K.acquired==1);input.frame()
sample=assert(input.sample());assert(sample.pending and not input.keyboard_isolated(),'Arming is pending, not yet isolated')
K.state=2;K.keys={87,16};input.frame()
sample=assert(input.sample());assert(sample.valid and input.keyboard_isolated(),'Active lease isolates the keyboard')
assert(input.down(87)and input.down(16)and not input.down(65)and engine_keys==0,'Keys come from the bridge, never the engine')
assert(input.set_mode('camera')and K.acquired==1,'A mode change keeps the reservation')
input.frame();assert(input.sample()and input.keyboard_isolated())
K.retiring=1;assert(not input.release(),'A retiring worker leaves the release pending')
assert(kb.status().pending_restore and input.release()and K.released==1 and kb.status().owner==nil,'The retried release completes')
K.state=2;assert(input.set_mode('menu')and K.acquired==2);input.frame();input.sample()
K.state=3;input.frame();assert(input.sample()==nil and not input.keyboard_isolated(),'A revoked reservation (focus change) is reported')
assert(input.release())
-- No bridge (native Windows refuses the DLL): refused once, then engine keys.
lines={};local none=dofile(root..'engine_input.lua').new(sr,function(m)lines[#lines+1]=m end,function()error('loadlib refused (577)')end)
input=dofile(root..'steam_input.lua').new(sr,none,nil,{require_keyboard=false})
assert(input.set_mode('menu')and input.keyboard_fallback and not input.keyboard_isolated(),'Falls back to engine keys')
input.frame();input.sample();input.down(87);assert(engine_keys>0,'Engine keys after the fallback')
assert(table.concat(lines,'\n'):find('keyboard isolation unavailable: ',1,true)and input.release())
print('Engine input: Window flags untouched, virtual menu cursor, camera motion, late mouse, _id fallback, first-event log lines, steam_input on the engine host and bridge keyboard isolation passed')

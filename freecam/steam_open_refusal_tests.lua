-- The Photo key must never look ignored. A refused open is logged with its reason and
-- shown on screen for a few seconds while the panel stays closed (Discord, 2026-11-05:
-- "it'll only let me activate slow mo").
assert(_VERSION=='Lua 5.1'and (not rawget(_G,'jit')or DBF_PHOTO_TEST_LUAJIT==true),'Run in Lua 5.1 or the explicit LuaJIT fixture runner')

-- The menu's closed-state notice: a short banner that fades, then leaves nothing behind.
do
 local commands
 local menu=assert(loadfile('freecam/photo_menu.lua'))().new({draw=function(v)commands=v end},{})
 local reason='Gameplay camera unavailable'
 local function texts()
  local out={};for _,c in ipairs(commands or{})do if c.type=='text'then out[#out+1]=c end end;return out
 end
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,0)==true,'A fresh notice is shown')
 local t=texts();assert(#t==2 and t[1].text=='PHOTO MODE'and t[2].text==reason and t[2].a==1,'Title and reason are drawn in full')
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,4)==true and texts()[2].a==1,'The reason stays readable for four seconds')
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,4.5)==true and math.abs(texts()[2].a-.5)<1e-9,'Then it fades')
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,5)==false and #commands==0,'An expired notice clears the screen')
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,nil)==false and #commands==0,'Missing timing never leaves a permanent banner')
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',reason,0/0)==false and menu.draw_notice(1920,1080,'PHOTO MODE',reason,-1)==false,'Invalid timing draws nothing')
 local long=string.rep('Native keyboard isolation is required; ',12)
 assert(menu.draw_notice(1920,1080,'PHOTO MODE',long,0)==true)
 for _,c in ipairs(commands)do if c.type=='rect'then assert(c.x>=0 and c.x+c.w<=1920,'A long reason stays on screen')end end
 assert(#texts()[2].text<#long,'A long reason is shortened to fit')
 print('Photo menu notice: visible, fades, clears, invalid timing and long reasons passed')
end

DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua')
DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local notices={}
local f=fixture(false,function(f,deps)
 f.logs={};f.log=function(message)f.logs[#f.logs+1]=message end
 local camera_new=deps.camera.new
 deps.camera.new=function(...)
  local camera=camera_new(...);local open=camera.open
  camera.open=function()if f.camera_refusal then return false,f.camera_refusal end;return open()end
  return camera
 end
 local menu_new=deps.menu.new
 deps.menu.new=function(panel,actions)
  local item=menu_new(panel,actions)
  function item.draw_notice(_,_,title,text,elapsed)
   notices[#notices+1]={title=title,text=text,elapsed=elapsed}
   local shown=type(elapsed)=='number'and elapsed>=0 and elapsed<5
   panel.draw(shown and{{fixture_role='notice',text=text}}or{});return shown
  end
  return item
 end
end)
local function logged(text)return table.concat(f.logs,'\n'):find(text,1,true)~=nil end
local function press()f.pressed.p=true;f.step(.016);f.pressed.p=false;f.step(.016)end

f.camera_refusal='Gameplay camera unavailable'
press()
assert(not f.runtime.active,'Photo Mode stays closed')
assert(logged('Photo Mode did not open: Gameplay camera unavailable'),'The refusal is logged with its reason')
assert(#notices>=1 and notices[1].title=='PHOTO MODE'and notices[1].text=='Gameplay camera unavailable'and notices[1].elapsed==0,
 'The refusal is shown at once although the panel is closed')
assert(f.panel.last[1]and f.panel.last[1].fixture_role=='notice','The banner is on screen')
for _=1,60 do f.step(.05)end
assert(notices[#notices].elapsed>2.9,'The banner keeps being drawn while it is visible')
for _=1,50 do f.step(.05)end
local drawn=#notices
for _=1,20 do f.step(.05)end
assert(#notices==drawn,'An expired banner is no longer drawn')
assert(#f.panel.last==0,'An expired banner leaves nothing on screen')

-- Every press is logged and shows a fresh banner, so mashing the key is visible too.
local lines=#f.logs
press()
assert(#f.logs>lines and notices[#notices-1].elapsed==0,'A second refusal is logged and shown afresh')

-- A successful open takes the screen back; the banner stops.
f.camera_refusal=nil
f.pressed.p=true;f.step(.016,1);f.pressed.p=false
assert(f.runtime.active,'Photo Mode opens once the camera is available')
drawn=#notices
for _=1,5 do f.step(.016,1)end
assert(#notices==drawn,'No banner is drawn over an open Photo Mode')
assert(f.panel.last[1]and f.panel.last[1].fixture_role=='panel','The panel is drawn normally')
f.runtime.close(true);for _=1,5 do f.step(.016)end
assert(#notices==drawn,'Closing normally shows no banner')
f.finish()
print('Photo key refusal: logged reason, closed-panel banner, fade-out, repeat presses and normal open passed')

local Observer=dofile('freecam/esc_state_observer.lua')
local now,down,focus=0,false,true;local logs={};local calls=0
local sr={Application={time_since_launch=function()return now end},
 Keyboard={button_id=function(name)return name=='esc'and 27 or 1 end,button=function(id)calls=calls+1;return id==27 and(down and 1 or 0)or 1 end,active=function()return true end},
 Mouse={active=function()return true end},Window={has_focus=function()return true end,mouse_focus=function()return focus end,show_cursor=function()return not focus end,clip_cursor=function()return false end}}
local o=Observer.new(sr,function(s)logs[#logs+1]=s end)
o.tick(false);local n=calls;for _=1,100 do o.tick(false)end;assert(calls==n,'Unchanged clock repeated key polling')
for i=1,6 do
 now=now+1;down=true;focus=not focus;o.tick(false)
 for _,dt in ipairs({.05,.2,.5})do now=now+dt;o.tick(false)end
 now=now+.1;down=false;o.tick(false)
end
assert(o.done(),'Six transitions must retire the observer')
n=calls;local count=#logs;for _=1,100 do now=now+1;o.tick(false)end
assert(calls==n and #logs==count,'Retired observer must be idle')
local all=table.concat(logs,'\n')
assert(all:find('Window.mouse_focus=false',1,true)and all:find('Window.mouse_focus=true',1,true))
assert(all:find('key.w=1',1,true),'Preserve raw held-key observations in either menu state')
local p=Observer.new(sr,function()end);p.tick(true);assert(p.done(),'Photo Mode must invalidate a native menu comparison')
local t=Observer.new(sr,function()end);t.tick(false);now=now+181;t.tick(false);assert(t.done(),'Duration bound')
print('ESC observer: getter-only snapshots, bounded polling/transitions, Photo exclusion and fully idle retirement passed')

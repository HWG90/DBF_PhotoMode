local root=DBF_PHOTO_TEST_ROOT or'freecam/'
local Recovery=dofile(root..'input_recovery.lua')
local function fixture()
 local s={keys={},focused=true,native_menu=false,chat=false,focus=false,cursor=true,writes=0,stops=0,resets=0,
  external={available=true,open=false,active=false,pending_restore=false},
  native={active=false,owned=false,cleanup_pending=false,native_mode=0},views={},events={},logs={}}
 local function event(name)s.events[#s.events+1]=name end
 local window={mouse_focus=function()return s.focus end,show_cursor=function()return s.cursor end,
  set_mouse_focus=function(v)s.writes=s.writes+1;event('focus');if s.focus_fail then return false end;s.focus=v;return true end,
  set_show_cursor=function(v)s.writes=s.writes+1;event('cursor');if s.cursor_fail then return false end;s.cursor=v;return true end}
 local input={focused=function()return s.focused end,down=function(key)return s.keys[key]==true end,
  native_menu_active=function()return s.native_menu end,chat_active=function()return s.chat end,
  external_status=function()return s.external end,status=function()return s.native end,
  recover_native=function()s.resets=s.resets+1;event('native');return not s.reset_pending,'native pending'end}
 local deps={window=window,input=function()return input end,views=function()return s.views end,
  stop_photo=function()s.stops=s.stops+1;event('photo');return not s.stop_pending,'pose cleanup pending'end,
  log=function(value)s.logs[#s.logs+1]=value end}
 s.recovery=Recovery.new(deps);s.input=input;return s
end
do
 local s=fixture();assert(s.recovery.poll()and not s.recovery.status().active and s.writes==0)
 local epic,mcm,lll={},{},{}
 s.views={{key=epic,name='Epic',close=function()s.events[#s.events+1]='epic';return true end},
  {key=mcm,name='MCM',close=function()s.events[#s.events+1]='mcm';return true end},
  {key=lll,name='LLL',close=function()s.events[#s.events+1]='lll';return true end}}
 assert(s.recovery.request()and s.recovery.step())
 assert(table.concat(s.events,',')=='epic,mcm,lll,photo,native,focus,cursor','All editor acknowledgments and Photo cleanup precede native/focus repair')
 assert(s.focus and not s.cursor and not s.recovery.status().active)
 local writes=s.writes;assert(s.recovery.poll()and s.writes==writes,'Inactive recovery never maintains or steals focus')
end
do
 local s=fixture();local ready=false;local old,new={},{};local old_calls,new_calls=0,0
 s.views={{key=old,name='old Epic',close=function()old_calls=old_calls+1;return ready,'cursor restoration pending'end}}
 s.recovery.request();assert(not s.recovery.step()and s.stops==0 and s.writes==0)
 s.views={{key=new,name='new Epic',close=function()new_calls=new_calls+1;return true end}}
 assert(not s.recovery.step()and old_calls==2 and new_calls==0,'Replaced provider retains its original pending close')
 ready=true;assert(s.recovery.step()and old_calls==3 and new_calls==1)
end
do
 local s=fixture();s.stop_pending=true;s.recovery.request()
 assert(not s.recovery.step()and s.writes==0 and s.resets==0,'Pose/time cleanup pending cannot relinquish native input first')
 s.stop_pending=false;s.focused=false;assert(not s.recovery.step()and s.writes==0)
 s.focused=true;s.native_menu=true;assert(not s.recovery.step()and s.writes==0 and s.resets==0)
 s.native_menu=false;s.chat=true;assert(not s.recovery.step()and s.writes==0)
 s.chat=false;s.external.active=true;s.external.owner='another editor'
 assert(not s.recovery.step()and s.writes==0 and s.resets==0,'New external ownership is checked after close requests')
 s.external.active=false;s.external.owner=nil;assert(s.recovery.step())
end
do
 local s=fixture();s.recovery.request();s.external={active=false}
 assert(not s.recovery.step()and s.writes==0,'Unavailable ownership cannot authorize focus repair')
 s.external={available=true,open=false,active=false,pending_restore=false};s.reset_pending=true
 assert(not s.recovery.step()and s.writes==0)
 s.reset_pending=false;s.native.native_mode=1
 assert(not s.recovery.step()and s.writes==0,'A nonzero native gate blocks final window repair')
 s.native.native_mode=0;s.native.owned=true
 assert(not s.recovery.step()and s.writes==0,'A retained Photo lease blocks final window repair')
 s.native.owned=false;s.cursor_fail=true;assert(not s.recovery.step()and s.focus and s.cursor)
 s.cursor_fail=false;assert(s.recovery.step()and s.focus and not s.cursor,'Partial Window repair remains retryable')
end
do
 local s=fixture();s.keys[17]=true;s.keys[16]=true;s.keys[121]=true
 assert(s.recovery.poll()and s.stops==1)
 assert(s.recovery.poll()and s.stops==1,'Holding the recovery chord cannot repeatedly close editors')
 s.keys[121]=false;s.recovery.poll();s.keys[121]=true;s.focused=false
 assert(s.recovery.poll()and s.stops==1,'Recovery hotkey ignores other applications')
 s.focused=true;s.keys[121]=false;s.keys[120]=true
 assert(s.recovery.poll(120)and s.stops==2,'Recovery key is rebindable while retaining Ctrl+Shift modifiers')
end
do
 local s=fixture();s.views={{key={},name='unknown editor'}};s.recovery.request()
 assert(not s.recovery.step()and s.writes==0,'An unacknowledged editor is never force-released')
end
print('Input recovery: ordered editor/Photo/native cleanup, exact acknowledgments, provider replacement, hotkey edges, native-menu/foreground refusal and retryable gameplay-focus repair passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local M=dofile(root..'subject_poses.lua')
local function fixture()
 local x={identity='player:1',unit={},alive=true,graph=true,state=0,paused=false,events={},calls={},missing={}}
 local U={}
 function U.alive(unit)x.calls[#x.calls+1]='alive';assert(unit==x.unit);return x.alive end
 function U.has_animation_state_machine(unit)x.calls[#x.calls+1]='graph';assert(unit==x.unit and x.alive);return x.graph end
 function U.animation_get_state(unit)
  x.calls[#x.calls+1]='get';assert(unit==x.unit and x.alive and x.graph)
  local values={};for i=1,31 do values[i]=0 end;values[9]=x.state;return unpack(values)
 end
 function U.has_animation_event(unit,event)x.calls[#x.calls+1]='has';assert(unit==x.unit and x.alive and x.graph and type(event)=='string');return not x.missing[event]end
 function U.animation_event(...)
  assert(select('#',...)==2,'Binding requires exactly two arguments')
  local unit,event=...;assert(unit==x.unit and x.alive and x.graph);x.events[#x.events+1]=event
  if x.event_error then error('event failed')end
  -- No return values: native Lua binding is void.
 end
 local backend={frame=function()
  if x.frame_error then error('frame unavailable')end
  return{local_owner=x.remote~=true,identity=x.identity,root_handle=x.unit}
 end}
 x.api=M.new({Unit=U},backend,function()return x.paused end)
 x.U=U;assert(x.api.refresh(.5));return x
end
do
 local x=fixture();assert(#M.catalog==3 and x.api.capabilities.salute and x.api.capabilities.wave and x.api.capabilities.taunt)
 assert(not x.api.queue('victory'),'No guessed victory catalog')
 assert(x.api.queue('salute')and#x.events==0,'Menu queue dispatched a native event')
 assert(x.api.flush(.016)and x.events[1]=='action_salute_01'and x.api.active)
 x.state=176;assert(x.api.flush(.016));x.state=178;assert(x.api.flush(.016))
 assert(x.api.queue_stop()and#x.events==1);assert(x.api.flush(.016)and x.events[2]=='action_salute_exit')
 x.state=177;assert(x.api.flush(.016));assert(x.api.queue_stop());assert(x.api.flush(.016)and#x.events==2,'Repeated salute exit')
 x.state=0;assert(x.api.flush(.016)and not x.api.active and not x.api.current())
end
do
 local x=fixture();assert(x.api.queue('wave'));assert(x.api.flush(.016));x.state=199;assert(x.api.flush(.016))
 assert(x.api.release());assert(x.api.flush(.016)and x.events[2]=='emote_wave_done')
 x.state=0;assert(x.api.flush(.016)and not x.api.active)
 assert(x.api.refresh(.5));assert(x.api.queue('taunt'));assert(x.api.flush(.016));x.state=135;assert(x.api.flush(.016))
 local before=#x.events;assert(x.api.queue_stop());assert(x.api.flush(.016)and#x.events==before and x.api.status:find('naturally',1,true),'Taunt stop fabricated an event')
 x.state=0;assert(x.api.flush(.016)and not x.api.active)
end
do
 local x=fixture();x.paused=true;assert(x.api.queue('salute'));local ok,why=x.api.flush(.016)
 assert(not ok and#x.events==0 and why:find('Pause entire action',1,true),'Paused pose changed clock or dispatched')
 x.paused=false;assert(x.api.queue('salute'));assert(x.api.flush(.016));x.state=178;assert(x.api.flush(.016))
 x.paused=true;assert(x.api.queue_stop());assert(not x.api.flush(.016)and#x.events==1 and x.api.current()=='salute','Paused stop discarded ownership')
 x.paused=false;assert(x.api.queue_stop());assert(x.api.flush(.016)and#x.events==2)
end
for _,kind in ipairs({'dead','graph','remote','world','busy','read'})do
 local x=fixture();assert(x.api.queue('wave'))
 if kind=='dead'then x.alive=false elseif kind=='graph'then x.graph=false elseif kind=='remote'then x.remote=true
 elseif kind=='world'then x.identity='player:2';x.unit={} elseif kind=='busy'then x.state=35 else x.frame_error=true end
 local ok=x.api.flush(.016);assert(not ok and#x.events==0,'Rejected '..kind..' reached event setter')
end
do
 local x=fixture();assert(x.api.queue('salute'));assert(x.api.flush(.016));x.state=178;assert(x.api.flush(.016))
 x.identity='player:2';x.unit={};x.state=0;assert(x.api.queue_stop());x.api.flush(.016)
 assert(#x.events==1 and not x.api.current(),'Old cleanup touched replacement avatar')
end
do
 local x=fixture();assert(x.api.queue('salute'));x.missing.action_salute_exit=true
 assert(not x.api.flush(.016)and#x.events==0,'Missing exit allowed salute entry')
 x.missing.action_salute_exit=nil;assert(x.api.refresh(.5));assert(x.api.queue('salute'));assert(x.api.flush(.016))
 x.state=178;assert(x.api.flush(.016));x.state=35;assert(x.api.flush(.016));assert(not x.api.current(),'Foreign gameplay action kept pose ownership')
 assert(x.api.queue_stop());assert(x.api.flush(.016)and#x.events==1)
end
do
 local x=fixture();assert(x.api.queue('wave'));x.event_error=true;assert(not x.api.flush(.016))
 assert(x.api.current()=='wave','Uncertain event dispatch lost cleanup record')
 x.event_error=false;x.state=199;assert(x.api.queue_stop());assert(x.api.flush(.016)and x.events[2]=='emote_wave_done')
end
do
 local x=fixture();assert(x.api.queue('salute'));assert(x.api.flush(.016));assert(x.api.queue_stop())
 assert(x.api.flush(.016)and x.api.pending and x.api.current()=='salute'and#x.events==1,'Early Stop lost queued engine entry')
 x.state=176;assert(x.api.flush(.016)and x.events[2]=='action_salute_exit'and not x.api.pending)
 x.state=0;assert(x.api.flush(.016)and not x.api.current())
end
do
 local x=fixture();assert(x.api.queue('wave'));assert(x.api.flush(.016));x.paused=true
 for i=1,25 do x.api.flush(.1)end
 assert(x.api.current()=='wave','Paused entry wait expired')
 x.paused=false;for i=1,25 do x.api.flush(.1)end
 assert(not x.api.current()and#x.events==1,'Ignored engine event was retried or retained indefinitely')
end
print('Subject pose events: exact two-argument calls, local ownership, fresh alive/graph checks, queued updates, pause refusal, observed states, normal exits, natural Taunt completion and respawn/foreign-action isolation passed')

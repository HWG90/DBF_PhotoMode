-- Private passive signal qualification. No camera or visibility setters.
-- Input events are consumed once in the existing active Handycam update; no
-- timer, thread, input-state polling or gameplay input interception is added.
local M={}
local function pack(...)return{n=select('#',...),...}end
-- Candidate names are hypotheses, not known game controls. Existence queries
-- precede every indexed getter. Discovery is bounded and never calls a setter.
function M.parameters(sr,emit)
 local U,B=sr.Unit or{},sr.Matrix4x4 or{}
 local candidates={}
 for _,name in ipairs({'aim_weapon','weapon_aim','head_aim','aim_target','look_target','weapon_target','aim','look'})do candidates[#candidates+1]={'constraint_target',name}end
 for _,name in ipairs({'focused','focus','aiming','is_aiming','strafe','strafing','move_x','move_y','move_angle','move_speed','aim_yaw','aim_pitch'})do candidates[#candidates+1]={'variable',name}end
 local cursor,read_cursor,owner,world=1,0,nil,nil;local found={};local stopped=false;local complete=false
 return function(head)
  if stopped then return end
  if not head.root_handle or not head.world then return end
  if owner and(owner~=head.root_handle or world~=head.world)then stopped=true;emit('parameter trace stopped: selected subject changed');return end
  owner,world=head.root_handle,head.world
  if cursor>#candidates and #found==0 then return end
  local ok,why=pcall(function()
   assert(U.alive(owner)==true and U.world(owner)==world and sr.Application.main_world()==world,'Parameter subject retired')
   if type(U.has_animation_state_machine)~='function'or U.has_animation_state_machine(owner)~=true then return end
   local candidate
   if cursor<=#candidates then
    candidate=candidates[cursor];cursor=cursor+1
   else read_cursor=read_cursor%#found+1;candidate=found[read_cursor]end
   local kind,name=candidate[1],candidate[2]
   local has,find,get=U['animation_has_'..kind],U['animation_find_'..kind],U['animation_get_'..kind]
   if type(has)~='function'or type(find)~='function'or type(get)~='function'then emit('parameter API unavailable: '..kind);stopped=true;return end
   if has(owner,name)==true then
    if not candidate.found then candidate.found=true;found[#found+1]=candidate end
    local index=find(owner,name);assert(type(index)=='number'and index%1==0 and index>=0 and index<4096,'Parameter index refused')
    local value=get(owner,index)
    if kind=='variable'then
     assert(type(value)=='number'and value==value and math.abs(value)<1e8,'Parameter value refused')
     emit('parameter variable='..name..' value='..string.format('%.8g',value)..'; meaning unverified')
    else
     local a={B.to_elements(value)};assert(#a==12,'Constraint matrix shape refused')
     for i,v in ipairs(a)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Constraint matrix value refused');a[i]=string.format('%.6g',v)end
     emit('parameter constraint='..name..' matrix='..table.concat(a,',')..'; space and meaning unverified')
    end
   end
   if cursor==#candidates+1 and not complete then
    complete=true;emit('parameter discovery complete: candidates='..#candidates..' matches='..#found..'; no writes')
   end
  end)
  if not ok then stopped=true;emit('parameter trace stopped: '..tostring(why))end
 end
end
-- One bounded read-only search for a native aim-distance animation signal.
-- A matching name/value is evidence to qualify, not authority to steer aim.
function M.aim_distances(sr,head,emit)
 local U=sr.Unit;local unit,world=head.root_handle,head.world
 if not(U and type(U.animation_has_variable)=='function'and type(U.animation_find_variable)=='function'and type(U.animation_get_variable)=='function')then return end
 if not(unit and world and U.alive(unit)==true and U.world(unit)==world)then return end
 if U.has_animation_state_machine(unit)~=true then return end
 local started=os.clock();local found=0
 for _,name in ipairs({'aim_distance','aim_target_distance','aiming_distance','weapon_aim_distance',
  'target_distance','distance_to_target','look_distance','look_target_distance',
  'aim_raycast_distance','crosshair_distance','reticle_distance','target_range'})do
  assert(os.clock()-started<.002,'Aim distance read budget exceeded')
  if U.animation_has_variable(unit,name)==true then
   local index=U.animation_find_variable(unit,name)
   assert(type(index)=='number'and index%1==0 and index>=0 and index<4096,'Aim distance index unavailable')
   local value=U.animation_get_variable(unit,index)
   emit('aim distance candidate='..name..' type='..type(value)..' value='..tostring(value)..'; read-only, meaning unverified')
   found=found+1
  end
 end
 emit(string.format('aim distance inventory: candidates=12 found=%d elapsed_ms=%.3f; writes=0; idle',found,(os.clock()-started)*1000))
end
function M.new(sr,log,on_event,diagnostics,on_movement)
 local self={};local live=true;local prior,wrapper;local seen=setmetatable({},{__mode='k'})
 local gui_count,event_count=0,0;local pending;local unavailable=false
 local function emit(text)pcall(log,'Camera signal: '..text)end
 local parameters=diagnostics and M.parameters(sr,emit)
 local distance_done=false
 local pose_stopped=false;local pose_max_ms=0
 local function pose_sample(head,sample)
  if not diagnostics or pose_stopped then return end
  local began=os.clock()
  local ok,why=pcall(function()
   local U,B=sr.Unit,sr.Matrix4x4
   local unit,world=head.root_handle,head.world
   if not(unit and world and U and B and type(B.to_elements)=='function')then return end
   if not distance_done then distance_done=true;M.aim_distances(sr,head,emit)end
   assert(U.alive(unit)==true and U.world(unit)==world and sr.Application.main_world()==world,'Selected aim subject retired')
   -- One known rig node per sample; never enumerate units or animation variables.
   local name=sample==1 and 'unit_root'or sample==2 and 'weapon_aim'or'aim_weapon'
   local node=1
   if sample~=1 then if not U.has_node(unit,name)then emit('pose node='..name..' absent');return end;node=U.node(unit,name)end
   local values={B.to_elements(U.world_pose(unit,node))}
   assert(#values==12,'Aim matrix shape changed')
   for i,v in ipairs(values)do assert(type(v)=='number'and v==v and math.abs(v)<1e8,'Aim matrix invalid');values[i]=string.format('%.6g',v)end
   emit('pose node='..name..' matrix='..table.concat(values,',')..'; selected subject, not an authoritative aim target')
   if sample==1 and type(U.has_animation_state_machine)=='function'and U.has_animation_state_machine(unit)==true and type(U.animation_get_state)=='function'then
    local state=pack(pcall(U.animation_get_state,unit))
    if state[1]and state.n-1<=64 then
     local layers={};for i=2,state.n do layers[i-1]=tostring(state[i]):sub(1,96)end
     emit('animation layers='..table.concat(layers,'|')..'; values='..(state.n-1)..'; read-only')
    else
     -- Animation snapshots are tuples, not necessarily one value per layer.
     -- Unknown tuple sizes must not disable independent known-node observations.
     emit('animation snapshot skipped; values='..(state.n-1)..'; getter_ok='..tostring(state[1]))
    end
   end
   if parameters then parameters(head)end
  end)
  local elapsed=(os.clock()-began)*1000;pose_max_ms=math.max(pose_max_ms,elapsed)
  if not ok or elapsed>2 then pose_stopped=true;emit('pose trace stopped: '..tostring(ok and '2 ms budget exceeded'or why))end
  if sample==3 or pose_stopped then emit(string.format('pose trace max_step_ms=%.3f',pose_max_ms))end
 end
 local G=sr.Gui
 if G and type(G.set_visible)=='function'then
  prior=G.set_visible
  wrapper=function(...)
   local result=pack(prior(...))
   if live and gui_count<32 then
    local gui,value=...
    if gui~=nil and type(value)=='boolean'and seen[gui]~=value then
     seen[gui]=value;gui_count=gui_count+1;emit('Gui.set_visible gui='..tostring(gui)..' visible='..tostring(value))
    end
   end
   return unpack(result,1,result.n)
  end
  G.set_visible=wrapper
 end
 function self.tick(active)
  if not live or not active or unavailable or event_count>=32 and not on_event and not on_movement then return end
  local I,T=sr.Input,sr.InputEventType
  if not(I and type(I.event_queue)=='function'and T and T.BUTTON_PRESSED~=nil and T.BUTTON_RELEASED~=nil)then
   if not unavailable then unavailable=true;emit('Input event constants unavailable; no guessed event types')end
   return
  end
  local ok,events=pcall(I.event_queue)
  if not ok or type(events)~='table'or #events>512 then unavailable=true;event_count=32;emit('Input event shape/budget refused');return end
  for _,event in ipairs(events)do
   if (diagnostics and event_count<32 or on_movement)and type(event)=='table'and sr.Keyboard and event.sender==sr.Keyboard and(event.type==T.BUTTON_PRESSED or event.type==T.BUTTON_RELEASED)then
    local called,name=pcall(sr.Keyboard.button_name,event.id)
    if called and(name=='s'or name=='a'or name=='d')then
     if on_movement then on_movement(name,event.type==T.BUTTON_PRESSED)end
     if diagnostics and event_count<32 then
     local action=event.type==T.BUTTON_PRESSED and'pressed'or'released'
     event_count=event_count+1;pending={name=name,action=action,remaining=3}
     emit('keyboard='..name..' action='..action..'; movement state not inferred')
     end
    end
   end
   if type(event)=='table'and event.sender==sr.Mouse and(event.type==T.BUTTON_PRESSED or event.type==T.BUTTON_RELEASED)then
    local called,name=pcall(sr.Mouse.button_name,event.id)
    if called and(name=='middle'or name=='right')then
     if on_event then on_event(name,event.type==T.BUTTON_PRESSED)end
     local action=event.type==T.BUTTON_PRESSED and'pressed'or'released'
     if event_count<32 then
      event_count=event_count+1;pending={name=name,action=action,remaining=3}
      emit('mouse='..name..' action='..action..'; first-person state not inferred')
     end
    end
   end
  end
 end
 function self.observe(frame,head)
  if not live or not pending then return end
  local p,h,f=frame.position,head.head,frame.forward;local distance=0
  for i=1,3 do distance=distance+(p[i]-h[i])^2 end
  emit(string.format('event=%s:%s sample=%d camera=%.5g,%.5g,%.5g forward=%.5g,%.5g,%.5g head_distance=%.5g fov=%.5g',
   pending.name,pending.action,4-pending.remaining,p[1],p[2],p[3],f[1],f[2],f[3],math.sqrt(distance),frame.fov))
  pose_sample(head,4-pending.remaining)
  pending.remaining=pending.remaining-1;if pending.remaining==0 then pending=nil end
 end
 function self.release()
  live=false;pending=nil
  if wrapper and G.set_visible==wrapper then G.set_visible=prior end
  return true
 end
 return self
end
return M

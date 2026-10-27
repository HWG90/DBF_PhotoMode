-- Opt-in development experiment, never a movement controller. One write per
-- A/D/S press (three trials total), bounded observation, no native reapplication.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
function M.consume(folder,pid)
 local path=folder..'/wj-movement-probe.request'
 local f=io.open(path,'rb');if not f then return false end
 local token=f:read(64);f:close()
 return token=='move-angle-once-v1\n'and os.rename(path,path..'.claimed.'..tostring(pid))==true
end
function M.new(sr,log,measure)
 local U,B,V=sr.Unit,sr.Matrix4x4,sr.Vector3
 local self={};local work;local used={};local stopped=false;measure=measure or os.clock
 local function emit(s)log('Movement probe: '..s)end
 local function valid(row)
  if not(U.alive(row.unit)==true and U.world(row.unit)==row.world and sr.Application.main_world()==row.world)then return false end
  if tostring(U.resource_name(row.unit))~=row.resource or U.num_scene_graph_items(row.unit)~=row.nodes then return false end
  return U.has_animation_state_machine(row.unit)==true and U.animation_has_variable(row.unit,'move_angle')==true and U.animation_find_variable(row.unit,'move_angle')==row.index
 end
 local function value(row)
  local n=U.animation_get_variable(row.unit,row.index);assert(finite(n)and math.abs(n)<=360,'Movement angle invalid');return n
 end
 local function heading(unit,forward)
  local v=B.forward(U.world_pose(unit,1));local x,y,z=V.x(v),V.y(v),V.z(v)
  assert(finite(x)and finite(y)and finite(z),'Movement root direction invalid')
  local a,b,c=unpack(forward);assert(finite(a)and finite(b)and finite(c),'Movement view direction invalid')
  local norm=math.sqrt((x*x+y*y+z*z)*(a*a+b*b+c*c));assert(norm>.5,'Movement direction length invalid')
  return math.deg(math.acos(math.max(-1,math.min(1,(x*a+y*b+z*c)/norm))))
 end
 function self.release(reason)
  if not work then return true end
  local row=work
  local ok,why=pcall(function()
   if row.owned then
    if not valid(row)then emit('retired owner; no restoration write')
    elseif value(row)~=0 then emit('native change preserved; no restoration write')
    else
     assert(U.animation_set_variable(row.unit,row.index,row.before)~=false,'Movement restoration refused')
     assert(value(row)==row.before,'Movement restoration not acknowledged')
     emit('restored move_angle='..row.before)
    end
   end
  end)
  if not ok then stopped=true;return false,tostring(why)end
  emit('key='..row.key..' finished='..tostring(reason or'cancelled'));work=nil;return true
 end
 function self.event(name,pressed,now)
  if name~='a'and name~='d'and name~='s'then return true end
  if not pressed then if work and work.key==name then return self.release('key released')end;return true end
  if stopped or work or used[name]then return true end
  assert(finite(now),'Movement clock invalid');used[name]=true
  work={key=name,deadline=now+.6,next_at=now+.1,reads=0}
  emit('key='..name..' armed; one zero-angle write; no continuous override')
  return true
 end
 function self.tick(frame,enabled,now,forward)
  if not work then return true end
  if not enabled then return self.release('inactive, frozen or ADS')end
  if not finite(now)then return self.release('clock unavailable')end
  if now<work.next_at then return true end
  local began=measure()
  local ok,why=pcall(function()
   local row=work
   assert(frame and frame.explicit_subject and frame.root_handle and frame.world,'Movement subject unavailable')
   if row.unit and(row.unit~=frame.root_handle or row.world~=frame.world or row.identity~=frame.identity)then
    assert(self.release('subject changed'));return
   end
   if not row.unit then
    for _,name in ipairs({'alive','world','resource_name','num_scene_graph_items','has_animation_state_machine','animation_has_variable','animation_find_variable','animation_get_variable','animation_set_variable'})do
     assert(type(U[name])=='function','Movement API unavailable: '..name)
    end
    row.unit,row.world,row.identity=frame.root_handle,frame.world,frame.identity
    assert(U.alive(row.unit)==true and U.world(row.unit)==row.world and sr.Application.main_world()==row.world,'Movement subject retired')
    row.resource=tostring(U.resource_name(row.unit));assert(row.resource:lower():find('4d1c334d294dfa97',1,true),'Movement subject is not the qualified Helldiver resource')
    row.nodes=U.num_scene_graph_items(row.unit);assert(row.nodes==107,'Movement subject graph differs')
    assert(U.has_animation_state_machine(row.unit)==true and U.animation_has_variable(row.unit,'move_angle')==true,'Movement variable unavailable')
    row.index=U.animation_find_variable(row.unit,'move_angle');assert(finite(row.index)and row.index%1==0 and row.index>=0 and row.index<4096,'Movement variable index invalid')
   end
   if not valid(row)then assert(self.release('subject retired'));return end
   if now>row.deadline or row.reads>=12 then assert(self.release('observation complete'));return end
   row.reads=row.reads+1;row.next_at=now+.05
   local current=value(row)
   if row.owned then
    emit(string.format('key=%s sample=%d move_angle=%.6g root_view_degrees=%.4f; no reapply',row.key,row.reads,current,heading(row.unit,forward)))
    if current~=0 then assert(self.release('native overwrite observed'))end
   elseif math.abs(current)>=30 then
    row.before=current
    emit(string.format('key=%s before=%.6g root_view_degrees=%.4f',row.key,current,heading(row.unit,forward)))
    row.owned=true -- Preserve cleanup if a setter throws after writing.
    assert(U.animation_set_variable(row.unit,row.index,0)~=false,'Movement test write refused')
    assert(value(row)==0,'Movement test write not acknowledged')
    row.deadline=now+.16;emit('single move_angle=0 write acknowledged; body-facing effect unverified')
   end
  end)
  local elapsed=(measure()-began)*1000
  if not ok or elapsed>2 then
   stopped=true;emit('stopped='..tostring(ok and'2 ms work budget exceeded'or why))
   local released,reason=self.release('probe stopped');if not released then return false,reason end
  end
  return true
 end
 return self
end
return M

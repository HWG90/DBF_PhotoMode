-- DLL-free conservative Freeze fallback. A live pack anywhere in the solo
-- world selects the user-authorized tiny positive rate; no ownership claim.
-- One resource-filtered query per explicit Freeze, never a steady-state scan.
local M={}
M.rate=1e-14
-- Bounded diagnostic for qualifying an active-flight signal. Existing animation
-- getters only, once per explicit Freeze; no input heuristic or state setters.
function M.activity_probe(sr,log,context,pack_unit,capture)
 local U=sr.Unit;local started=os.clock();local rows={}
 local function budget()assert(os.clock()-started<.002,'2 ms activity probe budget')end
 local ok,why=pcall(function()
  for _,item in ipairs({{'pack',pack_unit},{'selected_body',context and context.root_handle}})do
   local role,unit=item[1],item[2]
   if unit then
    budget();assert(U.alive(unit)==true and U.world(unit)==sr.Application.main_world(),'Activity subject retired')
    local fields={role=role,state='unavailable',variables='',absent=''};rows[#rows+1]=fields
    if type(U.has_animation_state_machine)=='function'and U.has_animation_state_machine(unit)==true then
     local state={U.animation_get_state(unit)};assert(#state<=128,'Animation snapshot exceeds bound')
     local values={}
     for i,value in ipairs(state)do
      assert(type(value)=='number'and value==value and math.abs(value)<1e12,'Animation snapshot shape changed')
      values[i]=string.format('%.9g',value)
     end
     fields.state=table.concat(values,',');local variables,absent={},{}
     for _,name in ipairs({'hover','hovering','is_hovering','hover_active','hoverpack','hoverpack_active','jetpack','jetpack_active','jumppack','jump_pack','in_air','is_in_air','airborne','ragdoll','is_ragdoll'})do
      budget()
      if U.animation_has_variable(unit,name)==true then
       local index=U.animation_find_variable(unit,name)
       assert(type(index)=='number'and index%1==0 and index>=0 and index<4096,'Animation variable index invalid')
       local value=U.animation_get_variable(unit,index)
       assert(type(value)=='number'and value==value and math.abs(value)<1e8,'Animation variable invalid')
       variables[#variables+1]=name..'='..string.format('%.9g',value)
      else absent[#absent+1]=name end
     end
     fields.variables=table.concat(variables,',');fields.absent=table.concat(absent,',')
    else fields.state='no_animation_state_machine';fields.variables='';fields.absent=''end
   end
  end
 end)
 -- Emit after the bounded reads; never use this diagnostic as activation proof.
 for _,row in ipairs(rows)do
  log('Hover activity probe: capture='..capture..' role='..row.role..' state='..row.state..' variables='..row.variables..' absent='..row.absent..'; unverified; writes=0')
 end
 log(string.format('Hover activity probe: capture=%d complete=%s read_ms=%.3f reason=%s; writes=0',capture,tostring(ok),(os.clock()-started)*1000,ok and'complete'or tostring(why)))
end
function M.new(sr,log,diagnostics)
 local A,W,U,I=sr.Application,sr.World,sr.Unit,sr.IdString64
 local probes=0
 local function select_rate(context)
  local started=os.clock()
  local world=A.main_world();if not world then return nil,'Hover Freeze world unavailable'end
  -- IdString64 is scratch userdata; obtain and consume within this callback.
  local units=W.units_by_resource(world,I.from_hex('5ec80f4f1cdb66cf'))
  if type(units)~='table'then return nil,'Hover Freeze pack inventory unavailable'end
  local count=0
  for _,unit in pairs(units)do
   count=count+1;if count>256 then return nil,'Hover Freeze pack inventory exceeds bound'end
   if U.alive(unit)==true and U.world(unit)==world then
    if diagnostics and log and probes<6 then
     probes=probes+1;M.activity_probe(sr,log,context,unit,probes)
    end
    if log then log(string.format('Hover Freeze: live pack present; requested multiplier=1e-14 check_ms=%.3f; no thrust write',(os.clock()-started)*1000))end
    return M.rate
   end
  end
  if log then log(string.format('Hover Freeze: no live pack; requested multiplier=0 check_ms=%.3f',(os.clock()-started)*1000))end
  return 0
 end
 local function sample(value,index)
  local started=os.clock()
  local world=A.main_world();if not world then return end
  local dt=W.delta_time(world)
  if log then log(string.format('Hover Freeze sample: requested=%.17g sample=%d world_dt=%.17g read_ms=%.3f',value,index,dt,(os.clock()-started)*1000))end
 end
 return select_rate,sample
end
return M

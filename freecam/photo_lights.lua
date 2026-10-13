-- Local photo lights use the bundled light-only boot unit. Never enumerate, edit,
-- or destroy authored scene lights. All mutation belongs in the update phase.
local M={resource='e07f49224f0a5759',resource_name='mods/dbf_photo/units/photo_light_v1',maximum=3,testing_status='Not tested fully'}
M.defaults={kind='omni',enabled=true,intensity=3,color='#FFFFFF',range=8,cone=45,right=0,forward=1,up=0,follow_camera=false}
local function copy(value)local out={};for k,v in pairs(value or{})do out[k]=type(v)=='table'and copy(v)or v end;return out end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function callable(v)local t=type(v);return t=='function'or(t=='table'and getmetatable(v)and type(getmetatable(v).__call)=='function')end
local function clean(values,base)
 if values~=nil and type(values)~='table'then return nil,'Invalid photo light settings'end
 local out=copy(base or M.defaults)
 for key,value in pairs(values or{})do if M.defaults[key]~=nil then out[key]=value end end
 if out.kind~='omni'and out.kind~='spot'then return nil,'Choose a point or spot light'end
 if type(out.enabled)~='boolean'or type(out.follow_camera)~='boolean'then return nil,'Invalid light visibility'end
 if type(out.color)~='string'or not out.color:match('^#%x%x%x%x%x%x$')then return nil,'Use a six-digit light color'end
 local limits={intensity={0,10000},range={.1,1000},cone={1,175},right={-100,100},forward={-100,100},up={-100,100}}
 for key,bounds in pairs(limits)do
  if not finite(out[key])then return nil,'Invalid light '..key end
  out[key]=math.max(bounds[1],math.min(bounds[2],out[key]))
 end
 out.color=out.color:upper();return out
end
local function context(value)
 if type(value)~='table'then return nil end
 local out={}
 for _,name in ipairs({'position','forward','right','up'})do
  local vector=value[name];if type(vector)~='table'then return nil end
  out[name]={};for i=1,3 do if not finite(vector[i])then return nil end;out[name][i]=vector[i]end
 end
 for _,name in ipairs({'forward','right','up'})do
  local vector=out[name];local length=math.sqrt(vector[1]^2+vector[2]^2+vector[3]^2)
  if length<.001 then return nil end
  for i=1,3 do vector[i]=vector[i]/length end
 end
 -- A malformed camera basis must not place a light into arbitrary space.
 for _,pair in ipairs({{'forward','right'},{'forward','up'},{'right','up'}})do
  local a,b=out[pair[1]],out[pair[2]];if math.abs(a[1]*b[1]+a[2]*b[2]+a[3]*b[3])>.01 then return nil end
 end
 local r,f,u=out.right,out.forward,out.up
 if (r[2]*f[3]-r[3]*f[2])*u[1]+(r[3]*f[1]-r[1]*f[3])*u[2]+(r[1]*f[2]-r[2]*f[1])*u[3]<.99 then return nil end
 return out
end
local function linear(byte)local v=byte/255;return v<=.04045 and v/12.92 or((v+.055)/1.055)^2.4 end
function M.new(sr,log,reuse,handoff)
 -- Refresh preserves the controller/update callback's shared table identity.
 -- Occupied refresh requires an explicit handoff of the previous owned records;
 -- ordinary refresh never strands units or queued work in the old closure.
 if reuse then
  assert(type(reuse)=='table'and type(reuse.count)=='function'and not reuse.pending,'Photo light refresh requires an idle manager')
  if handoff then
   assert(handoff.owner==reuse and type(handoff.records)=='table'and#handoff.records==reuse.count()and#handoff.records<=M.maximum,'Invalid owned photo light handoff')
   local list=reuse.list();local maximum_id=0
   for i,record in ipairs(handoff.records)do
    assert(record.id==list[i].id and record.unit~=nil and record.world~=nil and record.world==handoff.world and type(record.caps)=='table'and clean(record.values)and context(record.anchor),'Invalid owned photo light record')
    maximum_id=math.max(maximum_id,record.id)
   end
   assert(finite(handoff.serial)and handoff.serial==math.floor(handoff.serial)and handoff.serial>=maximum_id,'Invalid photo light serial')
   assert(finite(handoff.selected)and handoff.selected==math.floor(handoff.selected)and handoff.selected>=0 and handoff.selected<=#handoff.records and(#handoff.records==0 or handoff.selected>0),'Invalid photo light selection')
   assert(handoff.frame==nil or context(handoff.frame),'Invalid photo light camera handoff')
  else assert(reuse.count()==0,'Photo light refresh requires an empty idle manager')end
 else assert(handoff==nil,'Photo light handoff requires its existing manager')end
 local self=reuse or{};self.status=M.testing_status..' - Photo lighting is waiting for a camera';self.available=false;self.revision=reuse and(self.revision or 0)+1 or 0;self.pending=false
 local records=handoff and handoff.records or{};local selected=handoff and handoff.selected or 0;local world=handoff and handoff.world;local frame=handoff and context(handoff.frame);local serial=handoff and handoff.serial or 0;local queue={}
 local W,U,L,A=sr.World or{},sr.Unit or{},sr.Light or{},sr.Application or{}
 local function world_live(candidate)
  if not candidate or type(A.worlds)~='function'then return false end
  local ok,worlds=pcall(A.worlds);if not ok or type(worlds)~='table'then return false end
  for _,item in pairs(worlds)do if item==candidate then return true end end;return false
 end
 local function owned_live(record)
  if not world_live(record.world)then return false,'retired'end
  local ok,alive=pcall(U.alive,record.unit)
  if not ok then return nil,tostring(alive)end
  return alive==true,alive==true and nil or'dead'
 end
 local function remove_at(index)
  local record=records[index];if not record then return true end
  local alive,why=owned_live(record)
  if alive==nil then return false,'Photo light cleanup pending: '..tostring(why)end
  if alive then
   local ok,err=pcall(W.destroy_unit,record.world,record.unit)
   if not ok then return false,'Photo light cleanup pending: '..tostring(err)end
  end
  table.remove(records,index);if index<selected then selected=selected-1 end
  selected=math.min(selected,#records);if selected==0 and#records>0 then selected=1 end;self.revision=self.revision+1
  return true
 end
 local function status(message)self.status=M.testing_status..' - '..tostring(message);return self.status end
 local function fail(why)status(why);return false,self.status end
 local function unavailable(why)self.available=false;return false,M.testing_status..' - '..why end
 function self.ready(candidate)
  candidate=candidate or world
  local required={{W,'spawn_unit','World.spawn_unit'},{W,'destroy_unit','World.destroy_unit'},{W,'update_unit','World.update_unit'},
   {U,'alive','Unit.alive'},{U,'light','Unit.light'},{U,'set_local_position','Unit.set_local_position'},
   {U,'set_local_rotation','Unit.set_local_rotation'},{A,'main_world','Application.main_world'},{A,'worlds','Application.worlds'},
   {A,'can_get','Application.can_get'},{L,'node','Light.node'},{L,'set_type','Light.set_type'},{L,'set_color','Light.set_color'},
   {L,'set_intensity','Light.set_intensity'},{L,'set_enabled','Light.set_enabled'},{L,'set_casts_shadows','Light.set_casts_shadows'}}
  for _,item in ipairs(required)do if not callable(item[1][item[2]])then return unavailable('Photo lighting unavailable: '..item[3])end end
  if not callable(sr.Vector3)or not(sr.Quaternion and callable(sr.Quaternion.look))or not(sr.IdString64 and callable(sr.IdString64.from_hex))then
   return unavailable('Photo lighting placement API unavailable')
  end
  if not world_live(candidate)then return unavailable('Photo lighting is waiting for a scene')end
  local ok,main=pcall(A.main_world);if not ok or main~=candidate then return unavailable('Photo lights require the main scene')end
  local has_resource,resource=pcall(function()return A.can_get('unit',sr.IdString64.from_hex(M.resource))end)
  if not has_resource or resource~=true then return unavailable('Photo light boot asset is unavailable; restart with the bundled assets')end
  local caps={point=true,spot=callable(L.set_spot_angle_end),
   range=callable(L.set_falloff_start)and callable(L.set_falloff_end),follow_camera=true,color=true}
  self.available=true;return true,nil,caps
 end
 local function apply(record)
  local alive,why=owned_live(record);if alive~=true then return false,'Photo light is '..tostring(why)end
  local same,light=pcall(U.light,record.unit,1)
  if not same or not light then return false,'Photo light component unavailable'end
  -- Unit.light may create a fresh Lua userdata wrapper on each lookup. The
  -- alive, owned unit is the identity boundary; always use its fresh component.
  record.light=light
  local got,node=pcall(L.node,light)
  if not got or not finite(node)or node<1 or node~=math.floor(node)then return false,'Photo light transform node unavailable'end
  if node~=1 then
   if not callable(U.scene_graph_parent)or not callable(L.set_local_position)or not callable(L.set_local_rotation)then return false,'Photo light child placement API unavailable'end
   local known,parent=pcall(U.scene_graph_parent,record.unit,node)
   if not known or parent~=1 then return false,'Photo light transform hierarchy unsupported'end
  end
  record.node=node
  local o,b=record.values,record.anchor;local position={}
  for i=1,3 do position[i]=b.position[i]+b.right[i]*o.right+b.forward[i]*o.forward+b.up[i]*o.up end
  local ran,err=pcall(function()
   L.set_enabled(light,false)
   U.set_local_position(record.unit,1,sr.Vector3(unpack(position)))
   U.set_local_rotation(record.unit,1,sr.Quaternion.look(sr.Vector3(unpack(b.forward)),sr.Vector3(unpack(b.up))))
   -- Light setters write the light's scene graph node. A root-attached light
   -- already has the intended world transform; zeroing it would move the unit
   -- to the world origin. Only neutralize a verified direct child on this copy.
   if node~=1 then
    L.set_local_position(light,record.unit,sr.Vector3(0,0,0))
    L.set_local_rotation(light,record.unit,sr.Quaternion.look(sr.Vector3(0,1,0),sr.Vector3(0,0,1)))
   end
   L.set_type(light,o.kind)
   L.set_color(light,sr.Vector3(linear(tonumber(o.color:sub(2,3),16)),linear(tonumber(o.color:sub(4,5),16)),linear(tonumber(o.color:sub(6,7),16))))
   L.set_intensity(light,o.intensity);L.set_casts_shadows(light,false)
   if callable(L.set_baked)then L.set_baked(light,false)end
   if record.caps.range then
    -- The shiplight prefab enables automatic falloff/culling. Manual distance
    -- must override that mode on this owned copy before setting its range.
    if callable(L.set_auto_falloff_end_and_culling)then L.set_auto_falloff_end_and_culling(light,false)end
    L.set_falloff_start(light,0);L.set_falloff_end(light,o.range)
   end
   -- Helldivers exposes the cone end setter, but not Stingray's older inner
   -- cone setter. Use only functions inventoried in the running game.
   if o.kind=='spot'then
    if callable(L.set_spot_angle_start)then L.set_spot_angle_start(light,0)end
    L.set_spot_angle_end(light,math.rad(o.cone))
   end
   L.set_enabled(light,o.enabled);W.update_unit(record.world,record.unit)
  end)
  return ran,not ran and tostring(err)or nil
 end
 function self.count()return#records end
 function self.selected()
  local record=records[selected];return record and copy(record.values)or nil,selected,#records
 end
 function self.list()
  local out={};for i,record in ipairs(records)do out[i]={id=record.id,values=copy(record.values),selected=i==selected,error=record.error}end;return out
 end
 function self.markers()
  local S,V,Q=sr.Script or{},sr.Vector3 or{},sr.Matrix4x4 or{}
  if type(V)~='table'then V={}end
  local get_count,set_count=S.temp_count,S.set_temp_count
  if not(callable(get_count)and callable(set_count))then get_count,set_count=S.temp_byte_count,S.set_temp_byte_count end
  if not(callable(get_count)and callable(set_count)and callable(L.world_position)and callable(L.world_pose)and callable(Q.forward)
   and callable(V.x)and callable(V.y)and callable(V.z))then return{},'Photo light markers unavailable'end
  local saved,counts=pcall(function()return{get_count()}end)
  if not saved or#counts==0 then return{},'Photo light temporary scope unavailable'end
  for _,count in ipairs(counts)do if not finite(count)or count<0 or count~=math.floor(count)then return{},'Photo light temporary scope unavailable'end end
  local out={}
  local ran,why=pcall(function()
   local function numeric(vector)
    local value={V.x(vector),V.y(vector),V.z(vector)}
    for i=1,3 do assert(finite(value[i]),'Invalid photo light marker position')end
    return value
   end
   for i,record in ipairs(records)do
    if owned_live(record)==true then
     local light=U.light(record.unit,1)
     local position=numeric(L.world_position(light))
     local direction=numeric(Q.forward(L.world_pose(light)))
     out[#out+1]={id=record.id,position=position,forward=direction,kind=record.values.kind,color=record.values.color,
      enabled=record.values.enabled,selected=i==selected,cone=record.values.cone,range=record.values.range,error=record.error}
    end
   end
  end)
  local restored,reason=pcall(set_count,unpack(counts))
  if not ran or not restored then return{},'Photo light marker readback failed: '..tostring(not ran and why or reason)end
  return out
 end
 function self.select(index)
  if not finite(index)or index~=math.floor(index)or not records[index]then return fail('Choose an existing photo light')end
  selected=index;self.revision=self.revision+1;return true
 end
 function self.release(reason)
  local first
  for i=#records,1,-1 do local ok,why=remove_at(i);if not ok then first=first or why end end
  self.available=false;frame=nil;queue={};self.pending=false
  if first then return fail(first)end
  world=nil;selected=0;status(reason and('Photo lights cleared: '..reason)or'Photo lights cleared');return true
 end
 function self.tick(candidate,camera)
  if world and candidate~=world then local ok,why=self.release('scene changed');if not ok then return false,why end end
  if not candidate then return self.release('camera closed')end
  world=candidate;frame=context(camera)
  for i=#records,1,-1 do
   local record=records[i];local alive,why=owned_live(record)
   if alive==false then table.remove(records,i);if i<selected then selected=selected-1 end;selected=math.min(selected,#records);self.revision=self.revision+1
   elseif alive==nil then return fail('Photo light ownership unavailable: '..tostring(why))
   elseif record.values.follow_camera and frame then
    local previous=record.anchor;record.anchor=copy(frame);local ok,err=apply(record)
    if not ok then
     record.anchor=previous;local restored,reason=apply(record)
     if not restored then pcall(L.set_enabled,record.light,false)end
     record.error=tostring(err)..(restored and''or('; restoration pending: '..tostring(reason)));return fail(record.error)
    end
    record.error=nil
   end
  end
  if selected==0 and#records>0 then selected=1 end
  local ready,why=self.ready(candidate)
  if not ready then return fail(why)end
  if not frame then return fail('Photo lighting is waiting for camera placement')end
  status(#records==0 and'Add up to three photo lights'or('Photo light '..selected..' of '..#records));return true
 end
 function self.create(values)
  local ready,why,caps=self.ready();if not ready then return fail(why)end
  if not frame then return fail('Photo lighting is waiting for camera placement')end
  if#records>=M.maximum then return fail('Three photo lights are already placed')end
  local o,err=clean(values);if not o then return fail(err)end
  if o.kind=='spot'and not caps.spot then return fail('Spot lights are unavailable in this engine')end
  local ran,unit=pcall(function()
   local b=frame;local p={};for i=1,3 do p[i]=b.position[i]+b.right[i]*o.right+b.forward[i]*o.forward+b.up[i]*o.up end
   return W.spawn_unit(world,sr.IdString64.from_hex(M.resource),sr.Vector3(unpack(p)),sr.Quaternion.look(sr.Vector3(unpack(b.forward)),sr.Vector3(unpack(b.up))))
  end)
  if not ran or not unit then return fail('Photo light could not spawn: '..tostring(unit))end
  serial=serial+1;local record={id=serial,world=world,unit=unit,values=o,anchor=copy(frame),caps=caps};records[#records+1]=record;selected=#records
  -- Register the owned unit before component lookup so partial initialization
  -- is still removable, including a failed destroy that needs a retry.
  local got,light=pcall(function()
   if callable(U.num_lights)then assert(U.num_lights(unit)==1,'Photo light unit must contain exactly one light')end
   return U.light(unit,1)
  end)
  if got and light then record.light=light else record.error='Photo light unit has no accessible light component'end
  local ok,reason=false,record.error;if record.light then ok,reason=apply(record)end
  if not ok then record.error=reason;local removed,cleanup=remove_at(selected);return fail(tostring(reason)..(removed and''or('; '..tostring(cleanup))))end
  self.revision=self.revision+1;status('Photo light '..selected..' added');if log then log(self.status)end;return true
 end
 function self.update(values)
  local record=records[selected];if not record then return fail('Add a photo light first')end
  local o,why=clean(values,record.values);if not o then return fail(why)end
  if o.kind=='spot'and not record.caps.spot then return fail('Spot lights are unavailable in this engine')end
  if not record.caps.range and values and values.range~=nil then return fail('Light range is unavailable in this engine')end
  local previous,anchor=record.values,record.anchor;record.values=o
  if o.follow_camera and frame then record.anchor=copy(frame)end
  local ok,err=apply(record)
  if not ok then
   record.values=previous;record.anchor=anchor
   local restored,reason=apply(record)
   if not restored then pcall(L.set_enabled,record.light,false)end
   record.error=tostring(err)..(restored and''or('; restoration pending: '..tostring(reason)))
   return fail('Photo light update failed: '..record.error)
  end
  record.error=nil;self.revision=self.revision+1;status('Photo light '..selected..' updated');return true
 end
 function self.place_at_camera()
  local record=records[selected];if not record then return fail('Add a photo light first')end
  if not frame then return fail('Photo lighting is waiting for camera placement')end
  local previous=record.anchor;record.anchor=copy(frame);local ok,why=self.update({})
  if not ok then record.anchor=previous;local restored,reason=apply(record);if not restored then record.error=tostring(why)..'; restoration pending: '..tostring(reason);pcall(L.set_enabled,record.light,false)end end
  return ok,why
 end
 function self.remove(index)
  index=index or selected
  if not finite(index)or index~=math.floor(index)or not records[index]then return fail('Choose an existing photo light')end
  local ok,why=remove_at(index);if not ok then return fail(why)end;status('Photo light removed');return true
 end
 -- Menu input is sampled in render. Queue its requests, then execute them from
 -- the real game update callback. Repeated slider edits merge without growing
 -- an unbounded action queue, and an exit discards outstanding creates/edits.
 function self.queue(action,values)
  local allowed={create=true,update=true,select=true,place_at_camera=true,remove=true,release=true}
  if not allowed[action]then return fail('Unknown photo light action')end
  if(action=='create'or action=='update')and values~=nil and type(values)~='table'then return fail('Invalid photo light settings')end
  if action=='release'then queue={{action=action,values=values}};self.pending=true;return true end
  if action=='update'and queue[#queue]and queue[#queue].action==action then
   queue[#queue].values=queue[#queue].values or{}
   for key,value in pairs(values or{})do queue[#queue].values[key]=type(value)=='table'and copy(value)or value end
  else
   if#queue>=32 then return fail('Photo light updates are still pending')end
   queue[#queue+1]={action=action,values=type(values)=='table'and copy(values)or values}
  end
  self.pending=true;return true
 end
 function self.flush(candidate,camera)
  if queue[1]and queue[1].action=='release'then return self.release(queue[1].values)end
  if not candidate then return self.release('camera closed')end
  local ok,why=self.tick(candidate,camera)
  if not ok then return false,why end
  local pending=queue;queue={};self.pending=false
  for _,request in ipairs(pending)do
   local done,reason=self[request.action](request.values)
   if not done then return false,reason end
  end
  return true
 end
 self.clear=self.release;self.close=self.release
 return self
end
return M

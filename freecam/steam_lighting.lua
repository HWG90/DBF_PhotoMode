-- Camera-local lighting bridge. No avatar identity is inferred from a camera.
-- Native discovery is explicit on entry; static lights do no update work.
local M={}
local fields={light_enabled='enabled',light_intensity='intensity',light_color='color',
 light_range='range',light_cone='cone',light_right='right',light_forward='forward',
 light_up='up',light_follow='follow_camera'}
function M.new(sr,model,log,player_context)
 -- The current engine's falloff_end getter reads +0x80, while its setter
 -- writes +0x34. Owned-light readback verified 8/16/4 m at the setter field;
 -- do not use that unrelated getter to discard the ordinary Lua capability.
 local manager=model.new(sr,log);
 if type(player_context)=='function'then manager.player_context=player_context end
 local world,epoch;local following=false;local active=false;local fault=false
 local scene_world,scene_levels;local scene_generation=0
 local function scene_stamp(w)
  local W=sr.World or{}
  if type(W.levels)~='function'then return end
  local ok,levels=pcall(W.levels,w)
  if not ok or type(levels)~='table'or #levels==0 or #levels>256 then return end
  local seen={};for _,level in ipairs(levels)do if seen[level]then return end;seen[level]=true end
  return levels,seen
 end
 local function scene_epoch(w)
  local levels,seen=scene_stamp(w)
  local same=w==scene_world and levels and scene_levels and #levels==#scene_levels
  if same then for _,level in ipairs(scene_levels)do if not seen[level]then same=false;break end end end
  if not same then scene_generation=scene_generation+1 end
  scene_world,scene_levels=w,levels
  return scene_generation
 end
 local self={available=false,status='Photo lighting backend is not active'}
 manager.scene_context=function()return world,epoch end
 local function result(ok,why)
  self.status=why or manager.status
  if not ok and why then log(why)end
  return ok,why
 end
 local function refresh()
  following=manager.follows_camera()or manager.follow_player==true
  self.status=manager.status
 end
 function self.open(w,g,frame)
  assert(not active,'Lighting session is already active')
  world,epoch=w,scene_epoch(w)
  local ok,why=manager.ready(w)
  self.available=ok==true
  if not ok then return result(false,why)end
  active=true
  ok,why=manager.tick(world,frame);refresh()
  return result(ok,why)
 end
 function self.tick(frame)
  if not active or fault then return true end
  if not following and not manager.pending then return true end
  if type(frame)=='function'then frame=frame()end
  local ok,why=manager.flush(world,frame)
  refresh();if not ok then fault=true end;return result(ok,why)
 end
 function self.action(action,value)
  if not active or not self.available then return false,self.status end
  local ok,why=manager.queue(action,value)
  if ok then fault=false end
  return result(ok,why)
 end
 function self.change(id,value)
  if id=='light_follow_player'then
   if type(player_context)~='function'then return false,'Verified local player context unavailable'end
   return self.action('set_follow_player',value)
  end
  if id=='light_selected'then return self.action('select',value)end
  if id=='light_kind'then return self.action('update',{kind=value==2 and'spot'or'omni'})end
  local field=fields[id]
  if not field then return false,'Lighting control requires a verified player context'end
  return self.action('update',{[field]=value})
 end
 function self.subject(action,frame,distance,name)
  if type(distance)~='number'or distance~=distance or distance<=0 or distance>1000 then
   return false,'Lighting subject distance must be between 0 and 1000 m'
  end
  local target={}
  for axis=1,3 do target[axis]=frame.position[axis]+frame.forward[axis]*distance end
  if action=='aim'then return self.action('aim',{target=target})end
  if action=='preset'then return self.action('preset',{name=name,target=target,frame=frame})end
  return false,'Unknown subject lighting action'
 end
 function self.setup(action,presets,slot,frame,distance)
  if not active or not self.available then return false,self.status end
  if action=='clear'then return presets.clear(slot)end
  if type(distance)~='number'or distance~=distance or distance<=0 or distance>1000 then
   return false,'Lighting subject distance must be between 0 and 1000 m'
  end
  local target={};for axis=1,3 do target[axis]=frame.position[axis]+frame.forward[axis]*distance end
  if action=='save'then
   local setup,why=manager.export_setup();if not setup then return false,why end
   return presets.save(slot,setup,target,frame)
  elseif action=='recall'then
   local setup,why=presets.recall(slot,target,frame);if not setup then return false,why end
   return self.action('import_setup',setup)
  end
  return false,'Unknown lighting setup action'
 end
 function self.close()
  if not active then self.available=false;return true end
  local ok,why=manager.release('photo mode exited')
  if not ok then return result(false,why)end
  active=false;self.available=false;following=false;fault=false;world,epoch=nil,nil
  return true
 end
 function self.selected()return manager.selected()end
 function self.revision()return manager.revision end
 function self.markers()return active and manager.count()>0 and manager.list()or nil end
 function self.scene()return world,epoch end
 return self
end
return M

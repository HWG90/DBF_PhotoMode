-- Only a verified scene profile may identify post-processing parameters.
-- No guessed renderer-setting calls: some native bindings terminate the process.
local M={}
function M.new(sr,lens,profile_factory)
 local self={};local saved;local native_profile;local status='Depth of field unavailable for this scene'
 function self.apply(world,o,fov,unit,cam,custom_dof)
  local profile=rawget(_G,'DBF_PHOTO_RENDER_PROFILE')
  if not profile and profile_factory then
   if not native_profile or native_profile.world~=world or native_profile.unit~=unit or native_profile.cam~=cam then
    if saved then local ok,why=self.release();if not ok then return false,why end end
    native_profile=profile_factory.new(sr,world,nil,unit,cam)
   end
   profile=native_profile
  end
  if profile and profile.tick then profile.tick()end
  self.parameters=profile and profile.parameters or {}
  if not profile or profile.world~=world or type(profile.read)~='function' or type(profile.write)~='function' then
   status='Depth of field unavailable for this scene';return false,status
  end
  if saved and saved.profile~=profile then local ok,why=self.release();if not ok then return false,why end end
  if not saved then saved={profile=profile,values={},written={}}end
  local depth=lens.depth(o.focus_distance,o.aperture,fov)
  local values={dof=o.dof and 1 or 0,focus_distance=o.focus_distance,aperture=o.aperture,
   focal_region=depth.region,exposure=o.exposure,saturation=o.filter==7 and 0 or o.saturation/100,
   contrast=o.contrast/100,bloom=o.bloom and 1 or 0}
  if profile.parameters and profile.parameters.focal_distance then
   values.focus_distance,values.aperture=nil,nil
   values.scene_dof=o.dof and 1 or 0;values.scene_bloom=o.bloom and 1 or 0
   values.focal_distance=depth.near;values.focal_region=depth.region
   values.focal_region_start=math.max(.05,depth.near*.5)
   values.focal_region_end=math.max(.05,math.min(200,depth.region*.5))
   values.focal_near_scale=1;values.focal_far_scale=1
   values.focal_near_max=1;values.focal_far_max=1;values.focal_far_max_close=1
  end
  for key,value in pairs(values)do if profile.parameters and profile.parameters[key]then
   if saved.values[key]==nil then local v=profile.read(key);assert(type(v)=='number','Photo parameter is not numeric');saved.values[key]=v end
   saved.written[key]=value
   if profile.read(key)~=value or (profile.pending and profile.pending(key))then profile.write(key,value)end
  end end
  if profile.flush then profile.flush()end
  status=profile.parameters and profile.parameters.dof and (profile.parameters.focus_distance and 'DoF toggle ready; lens controls under test' or 'Depth of field toggle ready; focus and aperture unavailable') or 'Depth of field unavailable for this scene'
  return profile.parameters and profile.parameters.dof,status
 end
 function self.release()
  if not saved then return true end
  local ok,why=pcall(function()for key,value in pairs(saved.values)do
   if saved.profile.restore and key~='dof'and key~='bloom'then saved.profile.restore(key,value)
   elseif saved.profile.read(key)==saved.written[key]or (saved.profile.pending and saved.profile.pending(key))then saved.profile.write(key,value)end
  end;if saved.profile.flush then saved.profile.flush()end end)
  if not ok then return false,tostring(why)end;saved=nil;return true
 end
 function self.status()return status end
 return self
end
return M

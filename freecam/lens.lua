local M={}
function M.up(forward,right,degrees)
 local f,r=forward,right;local u={r[2]*f[3]-r[3]*f[2],r[3]*f[1]-r[1]*f[3],r[1]*f[2]-r[2]*f[1]}
 local angle=math.rad(degrees or 0);local c,s=math.cos(angle),math.sin(angle)
 return {u[1]*c+r[1]*s,u[2]*c+r[2]*s,u[3]*c+r[3]*s}
end
function M.depth(focus,aperture,fov)
 -- 24 mm sensor height, 0.03 mm circle of confusion; metres throughout.
 local focal=.024/(2*math.tan(math.max(math.rad(1),fov)/2))
 local hyper=focal*focal/(aperture*.00003)+focal
 local near=hyper*focus/(hyper+focus-focal)
 local far=hyper>focus-focal and hyper*focus/(hyper-focus+focal) or 100000
 return {near=near,far=far,region=math.min(200,far-near),focal_length=focal}
end
function M.new(sr)
 local self={};local saved
 function self.apply(cam,unit,forward,right,options)
  if not saved or saved.cam~=cam or saved.unit~=unit then
   assert(not saved,'Photo camera changed before lens restoration')
   saved={cam=cam,unit=unit,fov=sr.Camera.vertical_fov(cam)}
  end
  local fov=options.fov>0 and math.rad(math.max(1,options.fov)) or saved.fov
  sr.Camera.set_vertical_fov(cam,fov);saved.written=fov
  local up=M.up(forward,right,options.roll)
  sr.Camera.set_local_rotation(cam,unit,sr.Quaternion.look(sr.Vector3(unpack(forward)),sr.Vector3(unpack(up))))
  return fov
 end
 function self.release()
  if not saved then return true end
  if sr.Unit and not sr.Unit.alive(saved.unit)then saved=nil;return true end
  local ok,why=pcall(function()
   if sr.Camera.vertical_fov(saved.cam)==saved.written then sr.Camera.set_vertical_fov(saved.cam,saved.fov)end
  end)
  if not ok then return false,tostring(why)end;saved=nil;return true
 end
 return self
end
return M

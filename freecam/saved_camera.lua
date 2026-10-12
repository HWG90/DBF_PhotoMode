-- A session-local shot bookmark. Never retain engine vectors or read a retired unit.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function position(p)return type(p)=='table'and finite(p[1])and finite(p[2])and finite(p[3])end
function M.new(photo,context,log)
 local self={};local saved;local distance;local reason
 local function current()
  local ok,world,epoch,player,point=pcall(context)
  if ok and world~=nil and epoch~=nil and player~=nil and position(point)then return world,epoch,player,point end
 end
 function self.clear(why)
  local had=saved~=nil;saved=nil;distance=nil;reason=why
  if had and why then log('Saved camera cleared: '..why)end
 end
 function self.hold(radius)
  if not saved then return false end
  local world,epoch,player,point=current()
  if not world then return false end -- Camera discovery can briefly lose its target.
  if world~=saved.world or epoch~=saved.epoch or player~=saved.player then self.clear('player or scene changed');return false end
  local dx,dy,dz=point[1]-saved.pos[1],point[2]-saved.pos[2],point[3]-saved.pos[3]
  distance=math.sqrt(dx*dx+dy*dy+dz*dz)
  if distance>radius then self.clear('outside retention radius');return false end
  return true
 end
 function self.save(radius)
  if not photo.active or not position(photo.pos)or not photo.view or not finite(photo.view.yaw)or not finite(photo.view.pitch)then return false,'Start Photo Mode and place the camera first' end
  local world,epoch,player,point=current();if not world then return false,'Player and scene are unavailable' end
  local candidate={world=world,epoch=epoch,player=player,pos={photo.pos[1],photo.pos[2],photo.pos[3]},yaw=photo.view.yaw,pitch=photo.view.pitch,
   roll=photo.options and photo.options.roll or 0,fov=photo.options and photo.options.fov or 0}
  local dx,dy,dz=point[1]-candidate.pos[1],point[2]-candidate.pos[2],point[3]-candidate.pos[3]
  if dx*dx+dy*dy+dz*dz>radius*radius then return false,'Camera is outside the saved-camera radius' end
  saved=candidate;reason=nil;self.hold(radius);log('Camera position saved');return true
 end
 function self.restore(radius,handle)
  if not self.hold(radius)then return false end
  photo.pos={saved.pos[1],saved.pos[2],saved.pos[3]};photo.view={yaw=saved.yaw,pitch=saved.pitch}
  handle.set('roll',saved.roll);handle.set('fov',saved.fov)
  log('Saved camera position restored');return true
 end
 function self.status(radius)
  if saved then return string.format('Saved camera: %.1f / %.0f m',distance or 0,radius)end
  return reason and 'Saved camera cleared: '..reason or 'Saved camera: none'
 end
 return self
end
return M

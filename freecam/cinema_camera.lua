-- Runtime-only static shot. Store numbers and identity tokens, never engine vectors.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function token(v)return type(v)=='string'or finite(v)end
local function copy(v)local out={};for k,value in pairs(v)do out[k]=type(value)=='table'and copy(value)or value end;return out end
function M.new(photo,context)
 local self={state='off',status='Place a camera, then begin an action shot'};local shot,candidate
 local function current()
  local ok,value=pcall(context)
  if not ok or type(value)~='table'or not token(value.world)or not token(value.epoch)or not token(value.player)then return nil,'Cinema player or scene unavailable'end
  return {world=value.world,epoch=value.epoch,player=value.player}
 end
 local function same(a,b)return a and b and a.world==b.world and a.epoch==b.epoch and a.player==b.player end
 local function state(value)self.state=value;photo.cinema_state=value end
 function self.place()
  candidate,shot=nil,nil;state('place');self.status='Place the camera, then choose Begin action shot';return true
 end
 function self.prepare(render_fov)
  if self.state~='place'or not photo.active then return false,'Open Photo Mode and place the camera first'end
  local identity,why=current();if not identity then return false,why end
  local p,v=photo.pos,photo.view
  if type(p)~='table'or type(v)~='table'or not finite(v.yaw)or math.abs(v.yaw)>8*math.pi or not finite(v.pitch)or math.abs(v.pitch)>math.rad(89.001)then return false,'Wait for a rendered camera pose'end
  for i=1,3 do if not finite(p[i])or math.abs(p[i])>=1e8 then return false,'Camera position unavailable'end end
  local o=photo.options or{};local fov=finite(render_fov)and math.deg(render_fov)or o.fov
  if not finite(fov)or fov<1 or fov>179 or not finite(o.roll or 0)or math.abs(o.roll or 0)>180 then return false,'Wait for a rendered camera lens'end
  candidate={identity=identity,pos={p[1],p[2],p[3]},yaw=v.yaw,pitch=v.pitch,roll=o.roll or 0,fov=fov}
  self.status='Restoring gameplay before the action shot';return true
 end
 function self.commit()
  if not candidate or not same(candidate.identity,current())then candidate=nil;return false,'Cinema player or scene changed before gameplay resumed'end
  shot=candidate;candidate=nil;state('perform');self.status='CINEMA CAMERA — gameplay controls active';return self.hold()
 end
 function self.cancel()candidate=nil;return true end
 function self.hold()
  if self.state~='perform'then return true end
  if not photo.active or not shot or not same(shot.identity,current())then return false,'Cinema ended: player or scene changed'end
  photo.pos={shot.pos[1],shot.pos[2],shot.pos[3]}
  photo.view={yaw=shot.yaw,pitch=shot.pitch,sequence=photo.sample_sequence or 0}
  photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
  photo.locked=false;photo.lock_pose=nil
  if photo.options then photo.options.fov=shot.fov;photo.options.roll=shot.roll end
  return true
 end
 function self.reposition()
  local ok,why=self.hold();if not ok then return false,why end
  -- Hold wrote a fresh numeric pose; keep it while returning input to placement.
  candidate,shot=nil,nil;state('place');self.status='Camera placement controls active';return true
 end
 function self.stop()candidate,shot=nil,nil;state('off');self.status='Place a camera, then begin an action shot';return true end
 function self.gameplay_input_ready()
  local ok,value=pcall(context);return ok and type(value)=='table'and value.gameplay_input==true
 end
 function self.snapshot()return shot and copy(shot)or nil end
 state('off');return self
end
return M

-- Photo owns motion independently of any gameplay camera mod. Numeric state is
-- updated once per input sample; the view and lens are drawn on every render.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function point(v)return type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3])end
local function copy(v)return{v[1],v[2],v[3]}end
local function near(a,b)
 if not(point(a)and point(b))then return false end
 local x,y,z=a[1]-b[1],a[2]-b[2],a[3]-b[3];return x*x+y*y+z*z<=1e-8
end
function M.new(sr,photo,look,runtime,freeze,cinema,config,log)
 local self={pending=false};local lease,consumed,held
 config=config or{};log=log or function()end
 local function vector(v)
  if type(v)=='table'and point(v)then return copy(v)end
  local ok,x,y,z=pcall(function()return sr.Vector3.x(v),sr.Vector3.y(v),sr.Vector3.z(v)end)
  if ok and finite(x)and finite(y)and finite(z)then return{x,y,z}end
 end
 local function owner(frame)return config.scene or frame and frame.scene end
 local function valid(frame,scene,cleanup)
  local check=scene and(cleanup and scene.owned or scene.valid)or nil
  if type(check)~='function'then check=scene and scene.valid end
  if type(check)~='function'then return nil,'Camera scene validator unavailable'end
  local ok,value,why=pcall(check,frame)
  if not ok then return nil,tostring(value)end
  return value,why
 end
 local function identity(a,b)
  return a and b and a.epoch==b.epoch and a.world==b.world and a.unit==b.unit and a.cam==b.cam
   and a.player==b.player and a.player_identity==b.player_identity
 end
 local function safe(fn,...)
  if type(fn)~='function'then return false,'Camera service unavailable'end
  local ok,value,why=pcall(fn,...)
  if not ok then return false,tostring(value)end
  if value==false then return false,why or'Camera service refused the operation'end
  return true
 end
 local function clear_lease()
  if lease and lease.scene and type(lease.scene.clear_written)=='function'then pcall(lease.scene.clear_written,lease.frame)end
  lease=nil;self.pending=false;consumed=nil;held=nil
 end
 local function release(check)
  if not lease then self.pending=false;consumed=nil;held=nil;return true end
  self.pending=true
  local state,why
  if type(check)=='function'then
   local ok,value,reason=pcall(check,lease.frame)
   if ok then state,why=value,reason else state,why=nil,tostring(value)end
  else state,why=valid(lease.frame,type(check)=='table'and check or lease.scene,true)end
  if state==false then clear_lease();return true end
  if state~=true then return false,why or'Camera position cleanup awaits a verified scene'end
  if lease.written then
   local ok,current=pcall(sr.Camera.local_position,lease.frame.cam,lease.frame.unit)
   current=ok and vector(current)or nil
   if not current then return false,'Camera position cleanup read failed'end
   if lease.restoring and near(current,lease.original)then
    local updated,issue=safe(sr.World.update_unit,lease.frame.world,lease.frame.unit)
    if not updated then return false,issue end
   elseif near(current,lease.written)then
    lease.restoring=true
    local restored,problem=safe(sr.Camera.set_local_position,lease.frame.cam,lease.frame.unit,sr.Vector3(unpack(lease.original)))
    if not restored then return false,problem end
    local updated,issue=safe(sr.World.update_unit,lease.frame.world,lease.frame.unit)
    if not updated then return false,issue end
   end
  end
  clear_lease();return true
 end
 function self.release(check)
  local ok,value,why=pcall(release,check)
  if not ok then if lease then self.pending=true end;return false,tostring(value)end
  return value,why
 end
 local function apply(frame,suspended)
  if type(frame)~='table'or not(point(frame.position)and point(frame.forward)and point(frame.right)and point(frame.player_position))then return false,'Camera frame is invalid'end
  local scene=owner(frame);local verified,why=valid(frame,scene)
  if verified~=true then return false,why or'Camera frame is not verified'end
  if lease and not identity(lease.frame,frame)then return false,'Release the previous camera before moving its replacement'end
  if self.pending then return false,'Camera position cleanup is pending'end
  if not photo.active then return false,'Photo Mode is not active'end
  local cinema_ok,cinema_why=safe(cinema and cinema.hold or function()return true end)
  if not cinema_ok then return false,cinema_why end
  local frozen,freeze_why=safe(freeze and freeze.hold or function()return true end)
  if not frozen then return false,freeze_why end
  -- These services do not yield, but they may deliberately retire a scene.
  local still,problem=valid(frame,scene);if still~=true then return false,problem or'Camera frame changed before movement'end
  if not lease then
   lease={frame=frame,scene=scene,original=copy(frame.position)};consumed=nil;held=nil
   if not point(photo.pos)then photo.pos=copy(frame.position)end
  end
  local input=photo.input or{};local sequence=input.sequence
  local numbered=finite(sequence)and sequence>=0 and sequence%1==0
  local fresh=numbered and sequence~=consumed
  if fresh then consumed=sequence end
  local performing=cinema and cinema.state=='perform'
  local locked=photo.locked==true
  if not locked then held=nil end
  local blocked=suspended==true or input.suspended==true or locked or performing
  local strength=photo.options and photo.options.smoothing_strength
  strength=finite(strength)and math.max(0,math.min(100,strength))or 50
  local smoothing_time=.003*strength
  local smoothing=photo.options and photo.options.camera_smoothing==true and strength>0 and not blocked
  local sample={smoothing=smoothing,smoothing_time=smoothing_time,dt=fresh and input.dt or 0,sequence=numbered and sequence or consumed or 0,mouse_x=0,mouse_y=0,sensitivity=input.sensitivity}
  if fresh and not blocked then sample.mouse_x=input.mouse_x or 0;sample.mouse_y=input.mouse_y or 0 end
  -- A suspended sample is consumed, so closing a menu cannot replay its mouse.
  if blocked and photo.view then photo.view.target_yaw=nil;photo.view.target_pitch=nil end
  local f,r=look.basis(photo,frame.forward,sample)
  if not(point(f)and point(r))then return false,'Camera look basis unavailable'end
  local dt=finite(input.dt)and math.max(0,math.min(.1,input.dt))or 0
  if blocked or not smoothing then lease.target=nil end
  if locked then
   if not held then held={position=copy(photo.pos),forward=copy(f),right=copy(r)}end
   photo.pos=copy(held.position);f,r=held.forward,held.right
  elseif fresh and not blocked then
   local mf=(input.forward and 1 or 0)-(input.back and 1 or 0)
   local mr=(input.right and 1 or 0)-(input.left and 1 or 0)
   local mu=(input.up and 1 or 0)-(input.down and 1 or 0)
   local direction={f[1]*mf+r[1]*mr,f[2]*mf+r[2]*mr,f[3]*mf+r[3]*mr+mu}
   local norm=math.max(1,math.sqrt(direction[1]^2+direction[2]^2+direction[3]^2))
   local speed=finite(config.PHOTO_SPEED)and math.max(0,config.PHOTO_SPEED)or 5
   local boost=input.fast and(finite(config.PHOTO_FAST)and math.max(0,config.PHOTO_FAST)or 1)or 1
   local step=speed*boost*dt/norm
   local target=smoothing and(lease.target or copy(photo.pos))or photo.pos
   for axis=1,3 do target[axis]=target[axis]+direction[axis]*step end
   if smoothing then
    lease.target=target;local alpha=1-math.exp(-dt/smoothing_time)
    for axis=1,3 do photo.pos[axis]=photo.pos[axis]+(target[axis]-photo.pos[axis])*alpha end
   end
  end
  if performing and photo.handycam==true then
   local ready=cinema and cinema.gameplay_input_ready and cinema.gameplay_input_ready()
   if ready then
    if not lease.head then
     assert(type(sr.Unit.has_node)=='function'and sr.Unit.has_node(frame.player,'head'),'Handycam head attachment unavailable')
     lease.head=sr.Unit.node(frame.player,'head')
     local count=sr.Unit.num_scene_graph_items(frame.player)
     assert(type(lease.head)=='number'and lease.head%1==0 and lease.head>=1 and lease.head<=count,'Handycam head node invalid')
    end
    local p=assert(vector(sr.Unit.world_position(frame.player,lease.head)),'Handycam head position unavailable')
    -- The scene reader can observe our last render before gameplay publishes
    -- its next camera pose. That is output, not a fresh aiming sample.
    local prior=lease.handycam
    local echo=prior and prior.output_forward and near(frame.forward,prior.output_forward)
    local yaw=echo and prior.yaw or math.atan2(frame.forward[2],frame.forward[1])
    local pitch=echo and prior.pitch or math.asin(math.max(-1,math.min(1,frame.forward[3])))
    local now=cinema.wall_time();assert(finite(now),'Handycam real-time clock unavailable')
    local head=copy(p)
    local previous=lease.handycam
    local elapsed=previous and math.max(0,math.min(.1,now-previous.time))or 0
    local smooth=photo.options and photo.options.camera_smoothing==true and strength>0 and previous
    if smooth then
     local alpha=1-math.exp(-elapsed/smoothing_time)
     for i=1,3 do p[i]=previous.position[i]+(p[i]-previous.position[i])*alpha end
     yaw=previous.yaw+((yaw-previous.yaw+math.pi)%(2*math.pi)-math.pi)*alpha
     pitch=previous.pitch+(pitch-previous.pitch)*alpha
    end
    -- Keep the clean tracking pose separate: shake never feeds back into tracking.
    local intensity=photo.options and photo.options.handycam_intensity or 50
    intensity=finite(intensity)and math.max(0,math.min(100,intensity))*.01 or .5
    local speed=0
    if previous and elapsed>0 then
     local origin=previous.head or previous.position
     local dx,dy,dz=head[1]-origin[1],head[2]-origin[2],head[3]-origin[3]
     speed=math.min(8,math.sqrt(dx*dx+dy*dy+dz*dz)/elapsed)
    end
    -- Animation/head samples can repeat between simulation updates. Filter
    -- their measured speed so repeated/spiked samples cannot step shake gain
    -- or frequency on alternating render frames. Never feed sway into tracking.
    local filtered_speed=previous and previous.speed or 0
    if elapsed>0 then filtered_speed=filtered_speed+(speed-filtered_speed)*(1-math.exp(-elapsed/.18))end
    local energy=intensity*(.2+filtered_speed*.1)
    local phase=(previous and previous.phase or 0)+elapsed*(2.5+filtered_speed*.65)
    local shake=energy*(math.sin(phase*2.13)+.35*math.sin(phase*5.71))
    lease.handycam={position=p,yaw=yaw,pitch=pitch,time=now,head=head,phase=phase,energy=energy,speed=filtered_speed,
     sway_yaw=math.rad(1.4)*shake,sway_pitch=math.rad(1.8)*energy*math.sin(phase*2.87),
     sway_roll=1.8*energy*math.sin(phase*1.73)}
   end
   local view=lease.handycam
   if not view then return false,'Handycam awaits gameplay focus'end
   local yaw,pitch=view.yaw+(view.sway_yaw or 0),view.pitch+(view.sway_pitch or 0)
   photo.pos=copy(view.position);photo.view={yaw=yaw,pitch=pitch,sequence=consumed or 0}
   local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
   f,r={cy*cp,sy*cp,sp},{sy,-cy,0}
   view.output_forward=copy(f)
  else lease.handycam=nil;lease.head=nil end
  if not performing then
   local radius=finite(config.PHOTO_MAX_RANGE)and math.max(0,config.PHOTO_MAX_RANGE)or 500
   local p,h=photo.pos,frame.player_position;local x,y,z=p[1]-h[1],p[2]-h[2],p[3]-h[3]
   local distance=math.sqrt(x*x+y*y+z*z)
   if distance>radius and distance>0 then local k=radius/distance;p[1],p[2],p[3]=h[1]+x*k,h[2]+y*k,h[3]+z*k;lease.target=nil end
  end
  if not point(photo.pos)then return false,'Photo camera position is invalid'end
  -- Record the attempted write before calling the engine: even a partial setter
  -- failure must remain available for compare-owned cleanup by the controller.
  lease.written=copy(photo.pos)
  local moved,move_why=safe(sr.Camera.set_local_position,frame.cam,frame.unit,sr.Vector3(unpack(photo.pos)))
  if not moved then self.pending=true;return false,move_why end
  local render_options=photo.options or{}
  if performing and photo.handycam and lease.handycam and lease.handycam.sway_roll~=0 then
   local adjusted=lease.render_options or{};lease.render_options=adjusted
   for k in pairs(adjusted)do adjusted[k]=nil end
   for k,v in pairs(render_options)do adjusted[k]=v end
   adjusted.roll=(render_options.roll or 0)+(lease.handycam.sway_roll or 0);render_options=adjusted
  end
  local ok,result=pcall(runtime.apply,frame.cam,frame.unit,frame.world,f,r,render_options,dt)
  if not ok then self.pending=true;return false,tostring(result)end
  local updated,update_why=safe(sr.World.update_unit,frame.world,frame.unit)
  if not updated then self.pending=true;return false,update_why end
  if type(scene.mark_written)=='function'then
   local u={r[2]*f[3]-r[3]*f[2],r[3]*f[1]-r[1]*f[3],r[1]*f[2]-r[2]*f[1]}
   local roll=render_options.roll or 0;roll=finite(roll)and math.rad(roll)or 0
   local c,s=math.cos(roll),math.sin(roll);local rr,uu={},{}
   for i=1,3 do rr[i]=r[i]*c-u[i]*s;uu[i]=u[i]*c+r[i]*s end
   local marked,mark_why=safe(scene.mark_written,frame,photo.pos,f,rr,uu)
   if not marked then return false,mark_why end
  end
  return true
 end
 function self.apply(frame,input_suspended)
  local ok,value,why=pcall(apply,frame,input_suspended)
  if not ok then if lease then self.pending=true end;return false,tostring(value)end
  return value,why
 end
 return self
end
return M

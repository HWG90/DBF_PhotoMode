-- Runtime-only static shots and camera paths. Store numbers and identity tokens,
-- never engine vectors; camera/input ownership remains with the Cinema caller.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function token(v)return type(v)=='string'or finite(v)end
local function copy(v)local out={};for k,value in pairs(v)do out[k]=type(value)=='table'and copy(value)or value end;return out end
local function realtime()
 local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
 local now=api and api.camera_input and api.camera_input.now
 if type(now)=='function'then local ok,value=pcall(now);if ok and finite(value)then return value end end
 if not M._clock then
  local ok,clock=pcall(function()
   local ffi=require('ffi');pcall(ffi.cdef,'unsigned long long Cinema_GetTickCount64(void) __asm__("GetTickCount64");')
   local K=ffi.load('kernel32');return function()return tonumber(K.Cinema_GetTickCount64())/1000 end
  end)
  M._clock=ok and clock or function()return nil end
 end
 return M._clock()
end
-- Photo looks down +X, with positive pitch up and roll around its forward axis.
-- Keep quaternion math numeric so no borrowed engine rotation survives a frame.
local function rotation(p)
 local y,t,r=p.yaw/2,-p.pitch/2,math.rad(p.roll)/2
 local cy,sy,ct,st,cr,sr=math.cos(y),math.sin(y),math.cos(t),math.sin(t),math.cos(r),math.sin(r)
 return{sr*ct*cy-cr*st*sy,cr*st*cy+sr*ct*sy,cr*ct*sy-sr*st*cy,cr*ct*cy+sr*st*sy}
end
local function orientation(a,b,t)
 local q,r=rotation(a),rotation(b);local dot=0
 for i=1,4 do dot=dot+q[i]*r[i]end
 if dot<0 then dot=-dot;for i=1,4 do r[i]=-r[i]end end
 local x,y=1-t,t
 if dot<.9995 then local angle=math.acos(math.min(1,dot));local s=math.sin(angle);x,y=math.sin((1-t)*angle)/s,math.sin(t*angle)/s end
 local n=0;for i=1,4 do q[i]=q[i]*x+r[i]*y;n=n+q[i]*q[i]end
 n=math.sqrt(n);for i=1,4 do q[i]=q[i]/n end
 local a,b,c,d=q[1],q[2],q[3],q[4]
 return math.atan2(2*(d*c+a*b),1-2*(b*b+c*c)),
  math.max(math.rad(-89),math.min(math.rad(89),-math.asin(math.max(-1,math.min(1,2*(d*b-c*a)))))),
  math.deg(math.atan2(2*(d*a+b*c),1-2*(a*a+b*b)))
end
function M.new(photo,context,clock)
 local self={state='off',status='Place a camera, then begin an action shot',path_playing=false};local shot,candidate
 local points,playback={},nil;local candidate_path;clock=clock or realtime
 local function current()
  local ok,value=pcall(context)
  if not ok or type(value)~='table'or not token(value.world)or not token(value.epoch)or not token(value.player)then return nil,'Cinema player or scene unavailable'end
  return {world=value.world,epoch=value.epoch,player=value.player}
 end
 local function same(a,b)return a and b and a.world==b.world and a.epoch==b.epoch and a.player==b.player end
 local function state(value)self.state=value;photo.cinema_state=value end
 local function capture(render_fov)
  if not photo.active then return nil,'Open Photo Mode and place the camera first'end
  local identity,why=current();if not identity then return nil,why end
  local p,v=photo.pos,photo.view
  if type(p)~='table'or type(v)~='table'or not finite(v.yaw)or math.abs(v.yaw)>8*math.pi or not finite(v.pitch)or math.abs(v.pitch)>math.rad(89.001)then return nil,'Wait for a rendered camera pose'end
  for i=1,3 do if not finite(p[i])or math.abs(p[i])>=1e8 then return nil,'Camera position unavailable'end end
  local o=photo.options or{};local fov=finite(render_fov)and math.deg(render_fov)or o.fov
  if not finite(fov)or fov<1 or fov>179 or not finite(o.roll or 0)or math.abs(o.roll or 0)>180 then return nil,'Wait for a rendered camera lens'end
  return{identity=identity,pos={p[1],p[2],p[3]},yaw=v.yaw,pitch=v.pitch,roll=o.roll or 0,fov=fov}
 end
 local function halt_path()playback=nil;candidate_path=nil;self.path_playing=false end
 function self.place()
  halt_path();candidate,shot=nil,nil;state('place');self.status='Place the camera, then choose Begin action shot';return true
 end
 function self.prepare(render_fov)
  if self.state~='place'or not photo.active then return false,'Open Photo Mode and place the camera first'end
  local value,why=capture(render_fov);if not value then return false,why end
  halt_path();candidate=value
  self.status='Restoring gameplay before the action shot';return true
 end
 function self.commit()
  if not candidate or not same(candidate.identity,current())then candidate=nil;halt_path();return false,'Cinema player or scene changed before gameplay resumed'end
  shot=candidate;candidate=nil
  if candidate_path then
   local ok,now=pcall(clock);if not ok or not finite(now)then halt_path();shot=nil;return false,'Camera path real-time clock unavailable'end
   playback={points=candidate_path,elapsed=0,last=now,index=1,fraction=0};candidate_path=nil;self.path_playing=true
  end
  state('perform');self.status='CINEMA CAMERA — gameplay controls active';return self.hold()
 end
 function self.cancel()candidate=nil;candidate_path=nil;return true end
 local function path_frame()
  if not playback then return true end
  local ok,now=pcall(clock);if not ok or not finite(now)then return false,'Camera path real-time clock unavailable'end
  playback.elapsed=playback.elapsed+math.max(0,now-playback.last);playback.last=math.max(playback.last,now)
  local list=playback.points;local elapsed=playback.elapsed
  for i=1,#list-1 do
   local a,b=list[i],list[i+1]
   if elapsed<a.duration then
    local t=elapsed/a.duration
    playback.index,playback.fraction=i,t
    shot=copy(a)
    if a.transition~='cut'then
     t=t*t*(3-2*t)
     -- A curve through the recorded points, easing at each chosen composition.
     local p0,p3=list[math.max(1,i-1)].pos,list[math.min(#list,i+2)].pos
     for axis=1,3 do local p1,p2=a.pos[axis],b.pos[axis]
      local position=.5*((2*p1)+(-p0[axis]+p2)*t+(2*p0[axis]-5*p1+4*p2-p3[axis])*t*t+(-p0[axis]+3*p1-3*p2+p3[axis])*t*t*t)
      if not finite(position)or math.abs(position)>=1e8 then return false,'Camera path position exceeds supported scene bounds'end
      shot.pos[axis]=position
     end
     shot.yaw,shot.pitch,shot.roll=orientation(a,b,t);shot.fov=a.fov+(b.fov-a.fov)*t
    end
    self.status=string.format('CAMERA PATH — point %d/%d, %.1f s',i,#list,elapsed)
    return true
   end
   elapsed=elapsed-a.duration
  end
  shot=copy(list[#list]);halt_path();self.status='Camera path complete — final camera held; gameplay controls active';return true
 end
 function self.hold()
  if self.state~='perform'then return true end
  if not photo.active or not shot or not same(shot.identity,current())then
   halt_path();candidate,shot=nil,nil;points={};state('off');return false,'Cinema ended: player or scene changed'
  end
  local advanced,why=path_frame();if not advanced then halt_path();candidate,shot=nil,nil;state('off');return false,why end
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
  halt_path();candidate,shot=nil,nil;state('place');self.status='Camera placement controls active';return true
 end
 function self.stop()halt_path();candidate,shot=nil,nil;state('off');self.status='Place a camera, then begin an action shot';return true end
 function self.path_add(render_fov,duration,transition)
  if #points>=32 then return false,'Camera path is limited to 32 points'end
  duration=duration or 3;transition=transition or'smooth'
  if not finite(duration)or duration<.1 or duration>60 then return false,'Camera segment duration must be 0.1–60 seconds'end
  if transition~='smooth'and transition~='cut'then return false,'Choose Smooth or Cut for the camera transition'end
  local point,why=capture(render_fov);if not point then return false,why end
  if #points>0 and not same(points[1].identity,point.identity)then return false,'Camera path belongs to another scene or player; clear it first'end
  point.duration,point.transition=duration,transition;points[#points+1]=point
  self.status='Camera point '..#points..' added';return true,#points
 end
 local function point_at(index)
  if not finite(index)or index%1~=0 or not points[index]then return nil,'Select a recorded camera point'end
  return points[index]
 end
 function self.path_remove(index)
  index=index or#points;local point,why=point_at(index);if not point then return false,why end
  table.remove(points,index);return true,#points
 end
 function self.path_clear()if candidate_path then candidate=nil end;halt_path();points={};return true end
 function self.path_set_duration(index,value)
  local point,why=point_at(index);if not point then return false,why end
  if not finite(value)or value<.1 or value>60 then return false,'Camera segment duration must be 0.1–60 seconds'end
  point.duration=value;return true
 end
 function self.path_set_transition(index,value)
  local point,why=point_at(index);if not point then return false,why end
  if value~='smooth'and value~='cut'then return false,'Choose Smooth or Cut for the camera transition'end
  point.transition=value;return true
 end
 function self.path_points()return copy(points)end
 function self.path_prepare()
  if self.state~='place'or not photo.active then return false,'Open Photo Mode and place the camera first'end
  if #points<2 then return false,'Record at least two camera points'end
  if not same(points[1].identity,current())then return false,'Camera path belongs to another scene or player; clear it first'end
  candidate=copy(points[1]);candidate_path=copy(points);self.status='Restoring gameplay before the camera path';return true
 end
 self.path_play=self.path_prepare
 function self.path_stop()
  local ok,why=self.hold();if not ok then return false,why end
  halt_path();if self.state=='perform'then self.status='Camera path stopped — current camera held; gameplay controls active'end
  return true
 end
 function self.path_info()
  local duration=0;for i=1,#points-1 do duration=duration+points[i].duration end
  return{count=#points,playing=self.path_playing,elapsed=playback and playback.elapsed or 0,limit=32,
   index=playback and playback.index or nil,fraction=playback and playback.fraction or 0,duration=duration}
 end
 self.path_snapshot=self.path_info
 function self.gameplay_input_ready()
  local ok,value=pcall(context);return ok and type(value)=='table'and value.gameplay_input==true
 end
 function self.snapshot()return shot and copy(shot)or nil end
 state('off');return self
end
return M

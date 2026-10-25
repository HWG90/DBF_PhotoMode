-- Numeric, session-local path preview. The controller owns camera lifetime.
-- No native handles, player guesses, file writes or idle clock reads.
local M={maximum=32}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e8 end
local function arc(a,b)return(b-a+math.pi)%(2*math.pi)-math.pi end
local function clone(p)
 return{pos={p.pos[1],p.pos[2],p.pos[3]},yaw=p.yaw,pitch=p.pitch,roll=p.roll,fov=p.fov,
  duration=p.duration,transition=p.transition}
end
function M.new()
 local self={playing=false};local points={};local playback
 function self.add(point)
  if #points>=M.maximum then return false,'Camera path is limited to 32 points'end
  if type(point)~='table'or type(point.pos)~='table'then return false,'Camera point unavailable'end
  for _,key in ipairs({'yaw','pitch','roll','fov','duration'})do if not finite(point[key])then return false,'Invalid camera point'end end
  for i=1,3 do if not finite(point.pos[i])then return false,'Invalid camera position'end end
  if point.duration<.1 or point.duration>60 or point.fov<=0 or point.fov>=math.pi or
   (point.transition~=1 and point.transition~=2)then return false,'Invalid camera segment'end
  self.stop();points[#points+1]=clone(point);return true
 end
 function self.stop()self.playing=false;playback=nil end
 function self.clear()self.stop();points={}end
 function self.count()return #points end
 function self.remove(index)
  if type(index)~='number'or index%1~=0 or not points[index]then return false,'Choose a recorded point'end
  self.stop();table.remove(points,index);return true
 end
 function self.configure(index,duration,transition)
  if not points[index]or not finite(duration)or duration<.1 or duration>60 or
   (transition~=1 and transition~=2)then return false,'Invalid camera segment'end
  self.stop();points[index].duration=duration;points[index].transition=transition;return true
 end
 function self.point(index)return points[index]and clone(points[index])end
 function self.play(now)
  if #points<2 then return false,'Record at least two camera points'end
  if not finite(now)then return false,'Camera path clock unavailable'end
  playback={start=now,last=now,index=1,offset=0};self.playing=true;return true
 end
 function self.sample(now,out)
  if not playback then return false end
  if not finite(now)or now<playback.last then self.stop();return false,'Camera path clock changed'end
  playback.last=now
  local elapsed=now-playback.start
  local index=playback.index
  while index<#points and elapsed-playback.offset>=points[index].duration do
   playback.offset=playback.offset+points[index].duration;index=index+1
  end
  playback.index=index
  local a,b=points[index],points[math.min(index+1,#points)]
  local t=index==#points and 0 or math.min(1,(elapsed-playback.offset)/a.duration)
  t=a.transition==2 and 0 or t*t*(3-2*t)
  out.pos=out.pos or{}
  for i=1,3 do out.pos[i]=a.pos[i]+(b.pos[i]-a.pos[i])*t end
  out.yaw=a.yaw+arc(a.yaw,b.yaw)*t;out.pitch=a.pitch+(b.pitch-a.pitch)*t
  out.roll=a.roll+math.deg(arc(math.rad(a.roll),math.rad(b.roll)))*t
  out.fov=a.fov+(b.fov-a.fov)*t
  if index==#points then self.stop()end
  return true
 end
 return self
end
return M

-- Session scene effects and bounded depth sampling, shared by both Lua builds.
local M={}
function M.new(sr,resources,overlay,sampler,now,pick)
 local self={};local click,held,request;local due=0;local mode_seen
 -- Center auto-focus once a depth read has proved too slow to repeat (the
 -- sampler suspends continuous reads): a centred Helldiver is measured from
 -- its skeleton, and scenery is read once each time the camera comes to rest.
 local view,moved_at,read_view,body_due,on_body=nil,0,nil,0,false
 local function track(camera,time)
  local p,f=camera and camera.pos,camera and camera.forward
  if not(p and f)then return false end
  local key={p[1],p[2],p[3],f[1],f[2],f[3]};local changed=view==nil
  for i=1,6 do
   if type(key[i])~='number'or key[i]~=key[i]or math.abs(key[i])==math.huge then return false end
   if view and math.abs(key[i]-view[i])>(i<=3 and 1e-3 or 1e-4)then changed=true end
  end
  if changed then view=key;moved_at=time end
  return true
 end
 -- True when this frame is finished (with an optional status), false to run
 -- the shared depth request below.
 local function settled_center(options,time,set_distance,camera)
  if pick and pick.center and time>=body_due then
   body_due=time+.25
   local ok,distance=pcall(pick.center,camera)
   on_body=ok and type(distance)=='number'and distance==distance and distance>0 and distance<math.huge
   if on_body then
    request=nil;distance=math.max(.1,math.min(200,math.floor(distance*1000+.5)/1000))
    -- Breathing and idle motion must not rewrite the lens every check.
    local current=options.focus_distance
    if type(current)=='number'and math.abs(current-distance)<math.max(.01,distance*.015)then return true end
    local accepted,reason=set_distance(distance);if accepted==false then return true,reason end
    return true,string.format('Focus %.3f m (Helldiver)',distance)
   end
  end
  if on_body then return true end
  if time-moved_at<.3 then request=nil;return true,'Center auto-focus: focuses when the camera stops'end
  if read_view~=view then read_view=view;request={u=.5,v=.5,deadline=time+4,next_at=time,once=true}end
  return false
 end
 function self.ready()return overlay.ready()end
 function self.rearm()if overlay.rearm then overlay.rearm()end end
 function self.render(options,fov,holes)return overlay.apply(options,fov,holes)end
 function self.pick_depth(x,y,width,height)
  -- Selection owns this click. Do not also focus a cached projected root.
  click,request=nil,nil
  return sampler.sample(x/width,1-y/height,true)
 end
 function self.release()
  click,held,request=nil,nil,nil;mode_seen=nil;due=0
  view,moved_at,read_view,body_due,on_body=nil,0,nil,0,false
  local ok,why=sampler.release();if not ok then return false,why end
  return overlay.release()
 end
 function self.focus(options,input,menu_mode,blocked,editing,set_distance,camera)
  local mode=options.focus_mode or 1;local time=now();local width,height=sr.Gui.resolution()
  if mode~=mode_seen then click,held,request=nil,nil,nil;due=0;mode_seen=mode;read_view,body_due,on_body=nil,0,false end
  if mode==1 or options.dof==false or editing then click,request=nil,nil;held=input and input.click;return end
  if mode==3 then
   local tracked=track(camera,time);local metrics=sampler.metrics and sampler.metrics()
   if tracked and type(metrics)=='table'and metrics.automatic_suspended then
    local done,message=settled_center(options,time,set_distance,camera)
    if done then return message end
   else
    if time<due then return end;request={u=.5,v=.5,deadline=time+4,next_at=time};due=time+1
   end
  elseif menu_mode and input then
   local pressed=input.click and not held;held=input.click
   if blocked(input.x,input.y)then click=nil
   elseif pressed then
    if click and time>=click.time and time-click.time<=.5 and math.abs(input.x-click.x)<=8 and math.abs(input.y-click.y)<=8 then
     request={u=input.x/width,v=1-input.y/height,deadline=time+4,next_at=time};click=nil
    else click={x=input.x,y=input.y,time=time}end
   end
  else click=nil;held=nil end
  if not request or time<request.next_at then return end
  if time>request.deadline then request=nil;return 'Focus depth still unavailable'end
  local distance,why,info=sampler.sample(request.u,request.v,false,mode==3 and not request.once)
  if not distance then request.next_at=info and info.retry_at or time+.5;return why end
  local accepted,reason=set_distance(math.max(.1,math.min(200,math.floor(distance*1000+.5)/1000)))
  if accepted==false then return reason end
  -- This view's scenery is now in focus; a suspended sampler reads again only
  -- after the camera moves and stops.
  if mode==3 then read_view=view end
  request=nil;return string.format('Focus %.3f m',distance)
 end
 return self
end
return M

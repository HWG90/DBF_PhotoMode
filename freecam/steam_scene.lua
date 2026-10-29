-- Session scene effects and bounded depth sampling, shared by both Lua builds.
local M={}
function M.new(sr,resources,overlay,sampler,now)
 local self={};local click,held,request;local due=0;local mode_seen
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
  local ok,why=sampler.release();if not ok then return false,why end
  return overlay.release()
 end
 function self.focus(options,input,menu_mode,blocked,editing,set_distance)
  local mode=options.focus_mode or 1;local time=now();local width,height=sr.Gui.resolution()
  if mode~=mode_seen then click,held,request=nil,nil,nil;due=0;mode_seen=mode end
  if mode==1 or options.dof==false or editing then click,request=nil,nil;held=input and input.click;return end
  if mode==3 then
   if time<due then return end;request={u=.5,v=.5,deadline=time+4,next_at=time};due=time+1
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
  local distance,why,info=sampler.sample(request.u,request.v,false,mode==3)
  if not distance then request.next_at=info and info.retry_at or time+.5;return why end
  local accepted,reason=set_distance(math.max(.1,math.min(200,math.floor(distance*1000+.5)/1000)))
  if accepted==false then return reason end
  request=nil;return string.format('Focus %.3f m',distance)
 end
 return self
end
return M

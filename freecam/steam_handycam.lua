-- Tracking arithmetic retained from steam-lua51-port camera_motion.lua.
-- No engine handles/writes; caller verifies local-player lifetime every sample.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e8 end
local function copy(v)return{v[1],v[2],v[3]}end
local function near(a,b)local x,y,z=a[1]-b[1],a[2]-b[2],a[3]-b[3];return x*x+y*y+z*z<=1e-8 end
-- Turn correction that points the eye mount at the game's aim point. The game
-- aims from its own shoulder camera, so a view from the eye sees the reticle
-- off the point of impact by an amount that depends on target depth. Only the
-- view turns; the mount, offsets and tracking never move. Outside the bounds
-- (target behind, closer than the mount reach, or a large swing) no correction.
M.aim_min_distance,M.aim_max_correction,M.aim_time=.75,math.rad(20),.08
local function aim_correction(mounted,yaw,pitch,aim)
 local dx,dy,dz=aim[1]-mounted[1],aim[2]-mounted[2],aim[3]-mounted[3]
 local d=math.sqrt(dx*dx+dy*dy+dz*dz)
 if not(d>=M.aim_min_distance)then return end
 local cy=(math.atan2(dy,dx)-yaw+math.pi)%(2*math.pi)-math.pi
 local cp=math.asin(math.max(-1,math.min(1,dz/d)))-pitch
 if math.abs(cy)>M.aim_max_correction or math.abs(cp)>M.aim_max_correction then return end
 return cy,cp
end
function M.new()
 local previous_state
 return{reset=function()previous_state=nil end,step=function(position,forward,now,options,aim)
  for _,v in ipairs({position,forward})do for i=1,3 do assert(finite(v[i]),'Handycam transform invalid')end end
  assert(finite(now),'Handycam clock invalid')
  local p=copy(position);local frame={forward=forward}
  local strength=options.smoothing_strength or 50
  local smoothing_time=math.max(.001,strength*.003)
    local prior=previous_state
    local echo=prior and prior.output_forward and near(frame.forward,prior.output_forward)
    local yaw=echo and prior.yaw or math.atan2(frame.forward[2],frame.forward[1])
    local pitch=echo and prior.pitch or math.asin(math.max(-1,math.min(1,frame.forward[3])))
    local now=now;assert(finite(now),'Handycam real-time clock unavailable')
    local head=copy(p)
    local previous=previous_state
    local elapsed=previous and math.max(0,math.min(.1,now-previous.time))or 0
    local lag=options.handycam_lag_ms
    lag=finite(lag)and math.max(0,math.min(500,lag))or 0
    if previous and lag>0 then
     local alpha=1-math.exp(-elapsed/(lag*.001))
     for i=1,3 do p[i]=previous.position[i]+(p[i]-previous.position[i])*alpha end
    end
    local smooth=options.camera_smoothing==true and strength>0 and previous
    if smooth then
     local alpha=1-math.exp(-elapsed/smoothing_time)
     -- Aim smoothing and the configurable position lag are independent.
     -- Sway remains angular and never feeds back into the mount.
     yaw=previous.yaw+((yaw-previous.yaw+math.pi)%(2*math.pi)-math.pi)*alpha
     pitch=previous.pitch+(pitch-previous.pitch)*alpha
    end
    -- Keep the clean tracking pose separate: shake never feeds back into tracking.
    local intensity=options.handycam_intensity or 50
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
    previous_state={position=p,yaw=yaw,pitch=pitch,time=now,head=head,phase=phase,energy=energy,speed=filtered_speed,
     sway_yaw=math.rad(1.4)*shake,sway_pitch=math.rad(1.8)*energy*math.sin(phase*2.87),
     sway_roll=1.8*energy*math.sin(phase*1.73)}
  local view=previous_state
  local yaw_offset,pitch_offset=options.handycam_yaw_deg,options.handycam_pitch_deg
  yaw_offset=finite(yaw_offset)and math.max(-180,math.min(180,yaw_offset))or 0
  pitch_offset=finite(pitch_offset)and math.max(-89,math.min(89,pitch_offset))or 0
  -- Offset the clean mount in view-local metres after position smoothing.
  -- Never feed the offset back into lag, speed estimation or shake history.
  local forward_cm,up_cm=options.handycam_forward_cm,options.handycam_up_cm
  forward_cm=finite(forward_cm)and math.max(-30,math.min(30,forward_cm))or 14
  up_cm=finite(up_cm)and math.max(-30,math.min(30,up_cm))or 7
  local y,p=view.yaw,view.pitch
  local cy,sy,cp,sp=math.cos(y),math.sin(y),math.cos(p),math.sin(p)
  local side=options.handycam_right_cm
  side=(finite(side)and math.max(-30,math.min(30,side))or 0)*.01
  local ahead,height=forward_cm*.01,up_cm*.01
  local horizontal=cp*ahead-sp*height
  local mounted={view.position[1]+cy*horizontal+sy*side,view.position[2]+sy*horizontal-cy*side,
   view.position[3]+sp*ahead+cp*height}
  -- Aim lock replaces the manual yaw/pitch nudge with the exact, depth-aware
  -- turn. It eases toward each new target so a depth jump does not snap.
  -- A lost sample eases back to no correction instead of snapping.
  local aim_yaw,aim_pitch=0,0
  if options.handycam_aim~=false then
   local ty,tp
   if type(aim)=='table'and finite(aim[1])and finite(aim[2])and finite(aim[3])then ty,tp=aim_correction(mounted,view.yaw,view.pitch,aim)end
   local prior_yaw,prior_pitch=prior and prior.aim_yaw,prior and prior.aim_pitch
   if ty or prior_yaw then
    ty,tp=ty or 0,tp or 0
    if prior_yaw and elapsed>0 then
     local alpha=1-math.exp(-elapsed/M.aim_time)
     ty,tp=prior_yaw+(ty-prior_yaw)*alpha,prior_pitch+(tp-prior_pitch)*alpha
    elseif prior_yaw then ty,tp=prior_yaw,prior_pitch end
    aim_yaw,aim_pitch=ty,tp;yaw_offset,pitch_offset=0,0
    if math.abs(ty)+math.abs(tp)>1e-6 or type(aim)=='table'then view.aim_yaw,view.aim_pitch=ty,tp end
   end
  end
  local yaw=view.yaw+view.sway_yaw+aim_yaw+math.rad(yaw_offset)
  local pitch=math.max(math.rad(-89.9),math.min(math.rad(89.9),view.pitch+view.sway_pitch+aim_pitch+math.rad(pitch_offset)))
  local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
  local f,r={cy*cp,sy*cp,sp},{sy,-cy,0};view.output_forward=copy(f)
  return mounted,f,r,view.sway_roll
 end}
end
return M

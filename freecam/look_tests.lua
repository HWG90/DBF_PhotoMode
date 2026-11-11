local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local look=dofile(root..'look.lua')
local photo={}
local f,r=look.basis(photo,{0,1,0},{sequence=1,mouse_x=0,mouse_y=0})
assert(math.abs(f[2]-1)<1e-6 and math.abs(r[1]-1)<1e-6)
f=look.basis(photo,{0,-1,0},{sequence=2,mouse_x=100,mouse_y=0,sensitivity=0.15})
assert(f[1]>0 and f[2]>0)
local yaw=photo.view.yaw
look.basis(photo,{0,1,0},{sequence=2,mouse_x=100,mouse_y=0})
assert(photo.view.yaw==yaw) -- repeated render cannot apply the same delta twice
f=look.basis(photo,{0,1,0},{sequence=3,mouse_x=0,mouse_y=-100000})
assert(f[3]<1 and f[3]>0.99)
assert(math.abs(f[1]*f[1]+f[2]*f[2]+f[3]*f[3]-1)<1e-6)
print('Independent look: initial basis, raw yaw, repeated renders, pitch bounds and normalized forward passed')
-- A level start keeps yaw and pitch and drops roll, even looking straight down.
f,r=look.level({0,.8,-.6})
assert(math.abs(f[2]-.8)<1e-6 and math.abs(f[3]+.6)<1e-6 and r[3]==0 and math.abs(r[1]-1)<1e-6)
f,r=look.level({0,0,-1})
assert(f[3]>-1 and f[3]<-.99 and r[3]==0,'Straight down is clamped like mouse look')
print('Level start: yaw and pitch kept, roll dropped, vertical clamp passed')
-- Smoothed look after a fast swipe: the turn still owed can exceed half a turn (1800 counts at
-- 0.15 are 270 degrees, in a tenth of a second against a 0.3 s smoothing time). The view must
-- finish that turn the way the mouse went, never take the shorter way round.
do
 local view={};local scale=math.rad(0.15);local sequence=0;local turned=0;local back=0
 local function step(dx)
  sequence=sequence+1;local before=view.view and view.view.yaw
  look.basis(view,{1,0,0},{sequence=sequence,mouse_x=dx,mouse_y=0,sensitivity=0.15,smoothing=true,smoothing_time=.3,dt=1/120})
  if before then
   local d=(view.view.yaw-before+math.pi)%(2*math.pi)-math.pi
   turned=turned+d;if d<-1e-9 then back=back+1 end
  end
 end
 step(0);for _=1,12 do step(-150)end;for _=1,600 do step(0)end
 assert(back==0,'Smoothed look turned against the mouse on '..back..' frames')
 assert(math.abs(turned-1800*scale)<.01,'Smoothed look turned '..math.deg(turned)..' degrees for a 270 degree swipe')
 -- Dropping the target (mode change, action shot) drops the turn still owed.
 step(-150);view.view.target_yaw=nil;view.view.target_pitch=nil
 local rest=view.view.yaw;for _=1,60 do step(0)end
 assert(math.abs(view.view.yaw-rest)<1e-9,'A cleared target kept turning')
 -- Switching smoothing off mid-turn continues from where the view is.
 step(-150);sequence=sequence+1;local at=view.view.yaw
 look.basis(view,{1,0,0},{sequence=sequence,mouse_x=0,mouse_y=0,sensitivity=0.15,smoothing=false})
 assert(math.abs(view.view.yaw-at)<1e-9 and view.view.target_yaw==nil,'Raw look jumped when smoothing ended')
 assert(view.view.yaw>=0 and view.view.yaw<2*math.pi,'Yaw left its range')
end
print('Smoothed look: a swipe past half a turn finishes the way the mouse went; cleared target and raw hand-over passed')

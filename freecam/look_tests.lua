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

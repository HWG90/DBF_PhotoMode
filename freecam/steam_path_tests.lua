local P=dofile('freecam/steam_path.lua')
local p=P.new();local out={};assert(not p.sample(0,out));assert(not p.play(0))
local a={pos={0,0,0},yaw=math.rad(179),pitch=0,roll=179,fov=1,duration=2,transition=1}
assert(p.add(a));a.pos[1]=999
local b={pos={10,0,0},yaw=math.rad(-179),pitch=.2,roll=-179,fov=2,duration=1,transition=2}
assert(p.add(b));assert(p.play(10));assert(p.sample(11,out));assert(out.pos[1]==5 and out.fov==1.5)
assert(math.abs(out.yaw-math.pi)<1e-8 and math.abs(out.roll-180)<1e-8,'Shortest rotation arc')
assert(p.sample(12,out));assert(out.pos[1]==10 and not p.playing)
assert(p.configure(1,2,2));assert(p.play(0));p.sample(1.99,out);assert(out.pos[1]==0)
p.sample(2,out);assert(out.pos[1]==10 and not p.playing,'Cut only at duration boundary')
assert(p.play(10));assert(not p.sample(9,out)and not p.playing,'Clock regression must stop')
local copied=p.point(1);copied.pos[1]=100;assert(p.point(1).pos[1]==0)
assert(not p.remove(.5));assert(p.remove(1));assert(p.count()==1);assert(not p.play(0))
p.clear();assert(p.count()==0)
for i=1,32 do assert(p.add(b))end;assert(not p.add(b));assert(p.play(0));assert(p.sample(10000,out)and not p.playing)
assert(out.pos[1]==10,'Long frames traverse bounded point list and hold final point')
print('Steam path: bounded copied points, smooth/cut boundaries, shortest arcs, clock failure and zero idle work passed')

-- Handycam aim lock, the game's aim-cache float decoding and packed-page code
-- witnesses. Pure arithmetic and mock memory; no engine or bridge.
local H=dofile('freecam/steam_handycam.lua')
local function close(a,b,e)return math.abs(a-b)<=(e or 1e-6)end
local function toward(p,f,aim)
 local d={aim[1]-p[1],aim[2]-p[2],aim[3]-p[3]};local n=math.sqrt(d[1]^2+d[2]^2+d[3]^2)
 return f[1]*d[1]/n+f[2]*d[2]/n+f[3]*d[3]/n
end
local o={handycam_lag_ms=0,handycam_intensity=0,camera_smoothing=false,handycam_forward_cm=14,handycam_up_cm=7,handycam_yaw_deg=6,handycam_pitch_deg=-3}
-- The game aims from a shoulder camera: its point of impact 8 m ahead and to
-- the right of the eye. Aim lock turns the eye view onto it, ignoring the
-- manual yaw/pitch nudge, while the mount itself never moves.
do
 local h=H.new();local aim={8,-.6,1.4}
 local p,f=h.step({0,0,1.6},{1,0,0},0,o,aim)
 assert(close(p[1],.14)and close(p[3],1.67),'Aim lock leaves the eye mount alone')
 assert(close(toward(p,f,aim),1,1e-9),'The first sample centres the view on the point of impact')
 local q,g=h.step({0,0,1.6},{1,0,0},1/60,o,nil)
 assert(q[1]==p[1]and q[3]==p[3]and toward(q,g,aim)<1 and toward(q,g,aim)>toward(q,{1,0,0},aim),'A lost sample eases back instead of snapping')
 for i=2,60 do q,g=h.step({0,0,1.6},{1,0,0},i/60,o,nil)end
 local yaw=math.atan2(g[2],g[1])
 assert(close(yaw,math.rad(6),1e-3),'Without samples the manual nudge returns')
end
-- A depth jump eases over ~80 ms; a near jump does not snap the view.
do
 local h=H.new();local far,near={60,-.6,1.4},{3,-.6,1.4}
 local p,f=h.step({0,0,1.6},{1,0,0},0,o,far)
 local before=math.atan2(f[2],f[1])
 p,f=h.step({0,0,1.6},{1,0,0},1/60,o,near)
 local target=math.atan2(near[2]-p[2],near[1]-p[1])
 local mid=math.atan2(f[2],f[1])
 assert(mid<before and mid>target,'One frame moves part of the way to a new depth')
 for i=2,40 do p,f=h.step({0,0,1.6},{1,0,0},i/60,o,near)end
 assert(close(toward(p,f,near),1,1e-6),'It settles on the new point of impact')
end
-- Outside the bounds no correction: behind the eye, inside the mount reach, or a big swing.
for _,aim in ipairs({{-5,0,1.6},{.3,0,1.6},{2,3,1.6}})do
 local h=H.new();local _,f=h.step({0,0,1.6},{1,0,0},0,o,aim)
 assert(close(math.atan2(f[2],f[1]),math.rad(6),1e-9),'Implausible aim samples keep the manual nudge')
end
-- Off: the manual yaw/pitch apply exactly as before.
do
 local h=H.new();o.handycam_aim=false
 local _,f=h.step({0,0,1.6},{1,0,0},0,o,{8,-.6,1.4})
 assert(close(math.atan2(f[2],f[1]),math.rad(6),1e-9)and close(math.asin(f[3]),math.rad(-3),1e-9),'Aim lock off keeps manual offsets')
 o.handycam_aim=nil
end
-- Echo safety: our own corrected output read back as the camera forward
-- must not drift the tracked direction.
do
 local h=H.new();local aim={20,-1,1.6};local f={1,0,0}
 for i=0,300 do local _;_,f=h.step({0,0,1.6},f,i/60,o,aim)end
 local p=h.step({0,0,1.6},f,301/60,o,aim)
 assert(close(toward(p,f,aim),1,1e-6),'Reading back our output does not accumulate the correction')
end
-- The game's cached aim floats.
do
 _G.mod={require=function()error('not used')end}
 local backend=dofile('freecam/subject_backend.lua')
 local function bytes(x)
  -- Pack a float32 the slow, obvious way for the fixture.
  if x==0 then return'\0\0\0\0'end
  local sign=x<0 and 128 or 0;x=math.abs(x);local m,e=math.frexp(x);local exponent=e+126
  local mantissa=math.floor((m*2-1)*8388608+.5)
  return string.char(mantissa%256,math.floor(mantissa/256)%256,math.floor(mantissa/65536)%128+(exponent%2)*128,sign+math.floor(exponent/2))
 end
 for _,v in ipairs({0,1,-1,.5,123.25,-4096.75,1e-3,3.4e38})do
  local got=backend.f32(bytes(v),0)
  assert(math.abs(got-v)<=math.abs(v)*1e-7,'Float '..v..' decoded as '..got)
 end
 assert(backend.f32('\0\0\128\127',0)~=backend.f32('\0\0\128\127',0),'Infinity is not a usable aim point')
 assert(backend.f32('\1\0\0\0',0)==math.ldexp(1,-149),'Subnormals decode')
 _G.mod=nil
end
-- Packed code pages: exact bytes when readable, accepted only inside the
-- hash-verified images when the read is refused, refused outside them.
do
 local exe,game=0x140000000,0x7ff800000000
 local function header(size)
  local h={};h[60]=string.char(128,0,0,0);return h
 end
 local pages={}
 local function poke(at,s)for i=1,#s do pages[at+i-1]=s:byte(i)end end
 local function u32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
 local function u64(n)return u32(n%4294967296)..u32(math.floor(n/4294967296))end
 for _,base in ipairs({exe,game})do poke(base+60,u32(128));poke(base+128,'PE\0\0');poke(base+128+80,u32(0x400000))end
 poke(exe+0x1000,'\072\139\209')
 local packed={[exe+0x2000]=true,[game+0x3000]=true}
 local bridge={module_base=function(name)return name=='game.dll'and game or exe end,
  read_memory=function(at,n)
   if packed[at-at%0x1000]then error('Protected native read failed')end
   local out={};for i=0,n-1 do local b=pages[at+i];assert(b,'unmapped');out[#out+1]=string.char(b)end;return table.concat(out)
  end,
  function_address=function(fn)error('Native binding is not executable')end,
  userdata_address=function()return 0 end}
 local loaded=package.loaded['src/host_native.lua']
 _G.mod={dir='.',require=function()end}
 local host=dofile('freecam/host_native.lua')
 host.open=function()return bridge end
 local memory=host.memory()
 assert(memory.code(exe+0x1000,'\072\139\209')and not memory.code(exe+0x1000,'\072\139\210'),'Readable witnesses compare exactly')
 assert(memory.code(exe+0x2000,'\001\002')and memory.code(game+0x3010,'\003'),'Packed pages inside the verified images pass')
 assert(memory.packed_witnesses==2)
 assert(not memory.code(exe+0x500000,'\001'),'Outside the images a refused read is a mismatch')
 -- A Lua 5.1 CClosure: tt=6 at +8, isC=1 at +10, f at +0x20.
 local fn=function()end;local closure=tonumber((tostring(fn):match('^function: (%w+)$'):gsub('^0x','')),16)
 poke(closure,string.rep('\0',8)..'\6\0\1\0'..string.rep('\0',20)..u64(exe+0x2010))
 assert(memory.function_address(fn)==exe+0x2010,'A packed binding entry resolves through its closure')
 poke(closure+32,u64(0x10000))
 assert(not pcall(memory.function_address,fn),'An entry outside the images is refused')
 poke(closure+10,'\0');poke(closure+32,u64(exe+0x2010))
 assert(not pcall(memory.function_address,fn),'A Lua closure is refused')
 bridge.function_address=function()error('Native function required')end
 local ok,why=pcall(memory.function_address,fn);assert(not ok and tostring(why):find('Native function required'),'Other bridge refusals pass through')
 _G.mod=nil
end
print('Handycam aim lock: depth-aware turn onto the point of impact, eased depth jumps, bounds, manual fallback, echo safety, aim-cache floats and packed-page code witnesses passed')

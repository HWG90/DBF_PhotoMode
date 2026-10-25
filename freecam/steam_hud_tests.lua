local factory=dofile('freecam/steam_hud.lua')
local function fixture()
 local f={scene=4,root=2000000,state=3000000,world={},visible=true,writes={},reads=0}
 local game=1048576
 local function u(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
 local function p(n)return u(n%4294967296)..u(math.floor(n/4294967296))end
 local signature='\072\131\236\040\068\139\001\076\139\209\065\139\192\069\139\200\131\224\239\065\131\201\016\132\210\068\015\068\200\068\137\009'
 local function read(at,n)
  f.reads=f.reads+1
  if f.unreadable then return nil end
  if at==game+60 then return u(128)end
  if at==game+128 then return'PE\0\0'end
  if at==game+128+8 then return u(0x6ad7c05d)end
  if at==game+128+80 then return u(0x3382000)end
  if at==game+0x12e4cc0 then return f.bad_signature and string.rep('\0',#signature)or signature end
  if at==game+0x2ce1508 then return p(f.state)end
  if at==game+0x2e28788 then return p(f.root)end
  if at==f.state+0xac29c then return u(f.scene)end
  if at==f.root+0x24e334 then return f.uninitialized and'\0'or'\1'end
  if at==f.root+0x820+0xf0 then return p(f.bad_parent and f.root+0x260 or f.root+0x258)end
  if at==f.root+0x24e340+0x146940+0xf0 then return p(f.root+0x820)end
  if at==f.root+0x820 then return u(f.visible and 0x92 or 0x82)end
  error('Unexpected HUD read '..at..'/'..n)
 end
 local function write(widget,value)
  assert(widget==f.root+0x820 and f.scene==4 and not f.bad_parent and not f.uninitialized,'Stale HUD write')
  f.writes[#f.writes+1]=value;f.visible=value
  if f.partial then f.partial=false;error('partial HUD write')end
 end
 f.memory={game=game,read=read}
 f.sr={Application={main_world=function()return f.world end}}
 f.new=function()return factory.new(f.sr,function()end,f.memory,write)end
 return f
end
local f=fixture();local h=f.new();assert(#f.writes==0 and not h.status().native_owned)
assert(h.set(true)and not f.visible and h.status().native_owned)
local reads=f.reads;for i=1,100 do assert(h.set(true))end;assert(f.reads==reads and #f.writes==1,'Settled intent repeats native work')
assert(h.tick(1));reads=f.reads;for i=1,100 do assert(h.tick(1.01))end;assert(f.reads==reads,'Bounded native owner checks were bypassed')
assert(h.set(false)and f.visible and #f.writes==2)
assert(h.release()and h.release())
-- Never overwrite a later native visibility writer or keep applying on a loop.
f=fixture();h=f.new();assert(h.set(true));f.visible=true;assert(h.tick(1)and h.status().foreign)
assert(h.set(true)and h.release()and f.visible and #f.writes==1)
-- Definitive scene/world retirement drops the old lease before any old address.
f=fixture();h=f.new();assert(h.set(true));f.scene=3;assert(h.release()and #f.writes==1)
f=fixture();h=f.new();assert(h.set(true));f.world={};assert(h.release()and #f.writes==1)
-- Unknown reads retain ownership and cleanup can be retried successfully.
f=fixture();h=f.new();assert(h.set(true));f.unreadable=true
assert(not h.release()and h.status().native_owned and h.status().pending_restore)
f.unreadable=false;assert(h.release()and f.visible and not h.status().pending_restore)
-- A partially applied native error is restored through the same owned entry.
f=fixture();h=f.new();f.partial=true;assert(not h.set(true));assert(f.visible and #f.writes==2 and not h.status().native_owned)
-- Refuse old bindings/parents before mutation.
f=fixture();f.bad_signature=true;assert(not pcall(f.new)and#f.writes==0)
f=fixture();h=f.new();f.bad_parent=true;assert(not h.set(true)and#f.writes==0)
-- Custom HUD values retain independent ownership and foreign values survive.
f=fixture();f.scene=3;h=f.new();local custom={hidden=false,opacity=.8,photo_hidden=false};DBFHUD=custom
assert(h.set(true)and custom.hidden and custom.opacity==0 and custom.photo_hidden)
custom.opacity=.6;assert(h.release()and not custom.hidden and custom.opacity==.6 and not custom.photo_hidden)
assert(not h.status().custom_owned and#f.writes==0);DBFHUD=nil
print('WJ gameplay HUD: exact build/parent gate, owned hide/restore, zero settled work, bounded checks, foreign state, retirement, unknown/partial cleanup and custom-HUD ownership passed')

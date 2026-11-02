-- Proton (LLL) reads the HUD font through the mod's own main bridge (host_native.open), never a
-- bridge named in font.lua: the 26251122 port retired hd2_nativeinfo_f6d3465944c1aea1 from port51/
-- and the Photo menu silently fell back to the stock font.
local factory=dofile('freecam/vendor/font.lua')
local saved_mod,saved_loadlib=mod,package.loadlib
package.loadlib=function(path)error('font.lua must not load a bridge by name: '..tostring(path))end
local FONT,ATLAS,MATERIAL='b56d2abac5d17df2','d1ebb991c79f934b','9f85b87d3ff20cbb'
local base,owner=0x140000000,0x1F0000000
local bytes={}
local function le32(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function put(address,s)for i=1,#s do bytes[address+i-1]=s:byte(i)end end
local function hash_bytes(hex)return le32(tonumber(hex:sub(9,16),16))..le32(tonumber(hex:sub(1,8),16))end
local function pointer_bytes(v)return le32(v%4294967296)..le32(math.floor(v/4294967296))end
-- game.dll as build 26251122 presents it: PE stamp, image size, checksum, then the HUD font globals.
put(base+0x3c,le32(0x100));put(base+0x100,'PE\0\0');put(base+0x108,le32(0x6AE0E5FF));put(base+0x150,le32(0x3382000));put(base+0x158,le32(0x2ED103A))
put(base+0x312D998,hash_bytes(FONT));put(base+0x312E618,hash_bytes(ATLAS));put(base+0x3180C08,pointer_bytes(owner));put(owner+24,hash_bytes(MATERIAL))
local function read(address,count)
 local out={}
 for i=0,count-1 do local b=bytes[address+i];if not b then error('Protected native read failed')end;out[#out+1]=string.char(b)end
 return table.concat(out)
end
local opened,refuse=0,nil
local host_native={library=function(name)error('font.lua asked for a bridge by name: '..name)end,
 open=function()opened=opened+1;if refuse then error(refuse)end;return{module_base=function(name)assert(name=='game.dll',name);return base end,read_memory=read}end}
local logged={}
mod={dir='C:/Mods/dbf_freecam',log=function(line)logged[#logged+1]=line end,require=function(rel)assert(rel=='src/host_native.lua','unexpected private import '..rel);return host_native end}
local sr={IdString64={from_hex=function(v)return v end},Application={can_get=function(kind,id)
 return kind=='font'and id==FONT or kind=='texture'and id==ATLAS or kind=='material'and id==MATERIAL end}}
-- 1. As the LLL runtime builds it: no memory handed in, the mod's log for refusals.
local font=factory.new(nil,nil,nil,nil,mod.log)
local d=assert(font.resolve(sr),'Proton resolves the HUD font through host_native.open()')
assert(d.font==FONT and d.atlas==ATLAS and d.material==MATERIAL,'HUD font triple read from game.dll')
assert(opened==1,'the main bridge is opened once')
assert(font.resolve(sr).font==FONT and opened==1,'later resolves reuse the opened bridge')
assert(#logged==0,'nothing is logged on success')
-- 2. A refused host keeps the stock font, says so once, and is not reopened every frame;
--    invalidate() (each Photo Mode open) retries.
refuse='War Journalist native bridge refused this host'
local refused=factory.new(nil,nil,nil,nil,mod.log);opened=0
assert(refused.resolve(sr)==nil and opened==1,'a refused bridge leaves the stock font')
for i=1,50 do assert(refused.resolve(sr)==nil)end
assert(opened==1,'a refused bridge is not reopened every frame')
assert(#logged==1 and logged[1]:find('stock font',1,true)and logged[1]:find(refuse,1,true),'the refusal is reported once with its reason: '..tostring(logged[1]))
refused.invalidate();refuse=nil
assert(refused.resolve(sr).font==FONT and opened==2,'the next Photo Mode open retries the bridge')
assert(#logged==1,'a recovered bridge adds no log line')
-- 3. Another game build's stamp keeps the stock font: no unverified offsets are read.
put(base+0x108,le32(0x6AD7C05D))
assert(factory.new(nil,nil,nil,nil,mod.log).resolve(sr)==nil,'another game build keeps the stock font')
put(base+0x108,le32(0x6AE0E5FF))
mod=saved_mod;package.loadlib=saved_loadlib
print('Proton HUD font: read through the main bridge, refusal reported once, retried on open passed')

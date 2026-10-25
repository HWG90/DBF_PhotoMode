-- Current gameplay HUD visibility lease. The native widget/flags/setter are
-- independently qualified by the accepted DBF-ASS HUD adapter. No code patches,
-- widget allocation, guessed parent handles or writes outside the setter.
local M={}
local function word(s)
 assert(type(s)=='string'and#s>=4,'HUD word unavailable')
 local a,b,c,d=s:byte(1,4);return a+b*256+c*65536+d*16777216
end
function M.new(sr,log,memory,setter)
 log=log or function()end
 if not memory then memory=mod.require('src/host_native.lua').memory()end
 local game=assert(memory.game,'HUD module unavailable')
 local function read(at,n)
  assert(type(at)=='number'and at>=65536 and at<2^47 and n>=1 and n<=256,'HUD read bounds differ')
  local s=memory.read(at,n);assert(type(s)=='string'and#s==n,'HUD state unreadable');return s
 end
 local function p(at)
  local s=read(at,8);local value=word(s)+word(s:sub(5))*4294967296
  assert(value>=65536 and value<2^47 and value%8==0,'HUD owner pointer unavailable');return value
 end
 local pe=word(read(game+60,4));assert(pe>=64 and pe<1048576 and read(game+pe,4)=='PE\0\0','HUD PE header differs')
 assert(word(read(game+pe+8,4))==0x6ad7c05d and word(read(game+pe+80,4))==0x3382000,'HUD game build unsupported')
 local signature='\072\131\236\040\068\139\001\076\139\209\065\139\192\069\139\200\131\224\239\065\131\201\016\132\210\068\015\068\200\068\137\009'
 assert(read(game+0x12e4cc0,#signature)==signature,'HUD visibility binding differs')
 if not setter then
  local open,why=package.loadlib(mod.dir..'/port51/hd2_nativeinfo_3139cc5f8ecb4078.dll','luaopen_hd2_nativeinfo');assert(open,why)
  local native=open();assert(type(native.hud_visible)=='function','Typed HUD bridge unavailable')
  setter=function(widget,visible)assert(native.hud_visible(widget,visible and 1 or 0))end
 end
 local self={};local owned,custom,desired,foreign,pending,last_probe
 local function identity()
  local state=p(game+0x2ce1508)
  if word(read(state+0xac29c,4))~=4 then return nil end
  local root=p(game+0x2e28788)
  if read(root+0x24e334,1)~='\1'then return nil end
  local world=sr.Application.main_world();if world==nil then return nil end
  local widget=root+0x820;local panel=root+0x24e340+0x146940
  assert(p(widget+0xf0)==root+0x258 and p(panel+0xf0)==widget,'Gameplay HUD parent hierarchy differs')
  return{root=root,widget=widget,state=state,world=world}
 end
 local function same(a,b)return a and b and a.root==b.root and a.widget==b.widget and a.state==b.state and a.world==b.world end
 local function visible(at)return math.floor(word(read(at,4))/16)%2==1 end
 local function write(entry,value)
  entry.written=value -- A throwing native call can partially apply.
  setter(entry.identity.widget,value)
  assert(visible(entry.identity.widget)==value,'HUD visibility readback differs')
 end
 local function restore_custom()
  if not custom then return true end
  if rawget(_G,'DBFHUD')~=custom.hud then custom=nil;return true end
  local hud=custom.hud
  for _,name in ipairs({'hidden','opacity','photo_hidden'})do
   local entry=custom.fields[name]
   if entry and rawget(hud,name)==entry.written then
    if name=='photo_hidden'and type(custom.setter)=='function'and rawget(hud,'set_photo_hidden')==custom.setter then
     custom.setter(entry.before)
    end
    if rawget(hud,name)==entry.written then rawset(hud,name,entry.before)end
    custom.fields[name]=nil
   end
  end
  custom=nil;return true
 end
 local function release()
  local ok,why=pcall(function()
   if owned then
    local current=identity()
    if same(current,owned.identity)then
     if visible(current.widget)==owned.written then write(owned,owned.before)end
    end
    owned=nil
   end
   restore_custom()
  end)
  pending=not ok
  if not ok then return false,tostring(why)end
  return true
 end
 function self.set(hidden)
  assert(type(hidden)=='boolean','HUD preference must be boolean')
  if pending then return false,'HUD restoration is pending'end
  if desired==hidden then return true end
  local released,reason=release();if not released then return false,reason end
  desired=hidden;foreign=nil;last_probe=nil
  if not hidden then return true end
  local ok,why=pcall(function()
   local current=identity()
   if current then
    owned={identity=current,before=visible(current.widget)}
    write(owned,false)
   end
   local hud=rawget(_G,'DBFHUD')
   if type(hud)=='table'then
    custom={hud=hud,setter=rawget(hud,'set_photo_hidden'),fields={}}
    for name,value in pairs({hidden=true,opacity=0,photo_hidden=true})do
     custom.fields[name]={before=rawget(hud,name),written=value};rawset(hud,name,value)
    end
    if type(custom.setter)=='function'then custom.setter(true)end
   end
  end)
  if not ok then
   local restored,reason=release()
   if restored then desired=nil end
   return false,restored and tostring(why)or reason
  end
  return true
 end
 function self.tick(time)
  if pending then return false,'HUD restoration is pending'end
  if not owned or foreign then return true end
  assert(type(time)=='number'and time==time and time>=0,'HUD clock unavailable')
  if last_probe and time>=last_probe and time-last_probe<.2 then return true end
  last_probe=time
  local ok,why=pcall(function()
   local current=identity()
   if not same(current,owned.identity)then owned=nil;return end
   if visible(current.widget)~=owned.written then
    owned=nil;foreign=true;log('Gameplay HUD visibility changed; preserving its current owner')
   end
  end)
  if not ok then pending=true;return false,tostring(why)end
  return true
 end
 function self.release()
  local ok,why=release();if ok then desired,foreign,last_probe=nil,nil,nil end;return ok,why
 end
 function self.status()return{hidden=desired==true,native_owned=owned~=nil,custom_owned=custom~=nil,pending_restore=pending==true,foreign=foreign==true}end
 return self
end
return M

-- Decorative overlay adapter; the development runtime requires explicit session
-- opt-in. Native asset selection/rendering still requires cold-load validation.
-- new(sr, view_module, composition [, log]); open(), draw(w,h,options,seconds),
-- invalidate(), close(), dispose(). Options use composition's shader index,
-- shader_opacity (0..100), shader_scale (.005..16), shader_animate (default true).
-- Caller supplies active application seconds; this module never reads a clock.
-- Availability discovery is lazy on selection/reopen/invalidation. Negative
-- results remain idle. Positive animated draws retain view's per-frame material
-- availability/lifetime guards; static draws use its immutable preview promise.
-- Caller must invalidate after boot-resource changes even for static overlays.
-- False/throwing GUI retirement retains ownership and blocks draw until an
-- explicit close/open/invalidate retry. Native material handles are never held.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function M.new(sr,view_module,composition,log)
 local names,colors={},{}
 for index,name in ipairs(composition.shaders)do
  assert(name==''or name:match('^[a-z0-9_]+$'),'Invalid decorative shader catalog')
  names[index]=name
  local rgb=composition.shader_colors and composition.shader_colors[name]or{255,255,255}
  colors[index]={rgb[1],rgb[2],rgb[3]}
 end
 local self={};local active,disposed,pending=false,false,false
 local view,selected,available,commands,key,reason
 local function release()
  if view then
   local called,ok,why=pcall(view.release)
   if not called or ok==false then
    pending=true;reason=tostring(called and(why or'Overlay cleanup pending')or ok)
    return false,reason
   end
  end
  view,commands,key=nil,nil,nil;pending=false
  return true
 end
 function self.close()
  active=false;selected,available=nil,nil
  return release()
 end
 function self.open()
  if disposed then return false,'Overlay disposed'end
  local ok,why=self.close();if not ok then return false,why end
  active=true;reason=nil;return true
 end
 function self.invalidate()
  selected,available=nil,nil
  local ok,why=release();if ok then reason=nil end
  return ok,why
 end
 function self.dispose()
  local ok,why=self.close();if ok then disposed=true end
  return ok,why
 end
 local function off()
  selected,available=nil,nil;local ok,why=release()
  if ok then reason=nil end;return ok,why
 end
 function self.draw(w,h,o,seconds)
  if pending then return false,reason end
  if disposed or not active then return false,'Overlay is closed'end
  local index=o.shader or 1;local name=names[index]
  if not name then return false,'Unknown decorative shader'end
  local opacity=o.shader_opacity or 10
  if name==''or opacity==0 then return off()end
  local scale=o.shader_scale or 1;local animate=o.shader_animate~=false
  if not finite(w)or not finite(h)or w<=0 or h<=0 or
   not finite(opacity)or opacity<0 or opacity>100 or
   not finite(scale)or scale<.005 or scale>16 or
   animate and(not finite(seconds)or seconds<0)then return false,'Invalid overlay parameters'end
  if selected~=name then
   local ok,why=release();if not ok then return false,why end
   selected,available=name,nil
  end
  local material='mods/dbf_photo/materials/mapped_'..name
  if available==nil then
   local called,found=pcall(sr.Application.can_get,'material',material)
   available=called and found==true
   if not available then reason='Decorative shader assets unavailable'end
  end
  if not available then return false,reason end
  if not view then view=view_module.new(sr,true,log)end
  if not key or key.w~=w or key.h~=h or key.opacity~=opacity or key.scale~=scale or key.animate~=animate then
   commands={{type='rect',x=0,y=0,w=w,h=h,layer=90,a=opacity/100,c=colors[index],
    preview_material=material,preview_static=not animate,preview_required=true,
    preview_mapping={4/scale,0,0,0,4/scale,0,0,0,1},preview_animation=animate and 1 or 0,preview_time=0}}
   key={w=w,h=h,opacity=opacity,scale=scale,animate=animate}
  end
  if animate then commands[1].preview_time=seconds end
  local called,ok,why=pcall(view.draw,commands,not animate and commands or nil)
  if not called then pending=true;reason=tostring(ok);return false,reason end
  if ok==false then
   if why=='Preview cleanup pending'then pending=true;reason=why;return false,reason end
   -- Preview is an explicit opt-in experiment. A refused allocation or
   -- drawability guard must not become an automatic per-frame retry loop.
   -- Retire any owned view once, then require selection/invalidation/reopen.
   available=false;reason=why or'Overlay draw unavailable'
   local retired,issue=release()
   if not retired then return false,issue end
   return false,reason
  end
  reason=nil;return true
 end
 function self.status()return reason,pending end
 return self
end
return M

local factory=dofile('freecam/vendor/font.lua')
local reads=0;local available=true
local sr={IdString64={from_hex=function(v)return v end},Application={can_get=function(kind,id)
 reads=reads+1
 if not available then return false end
 if kind=='font'then return id=='e007454455e2d2bb'end
 if kind=='texture'then return id=='1b0106d1d0ff112f'end
 if kind=='material'then return id=='47c50c5fab67ccab'end
 error(kind)
end}}
local original=package.loadlib;package.loadlib=function()error('BML font must never load a DLL')end
local font=factory.new(nil,nil,nil,true);local descriptor=assert(font.resolve(sr))
assert(descriptor.font=='e007454455e2d2bb'and descriptor.atlas=='1b0106d1d0ff112f')
local before=reads;for i=1,100 do assert(font.resolve(sr)==descriptor)end;assert(reads==before,'Resolved font must not repeat resource discovery')
available=false;local absent=factory.new(nil,nil,nil,true);assert(absent.resolve(sr)==nil)
before=reads;for i=1,100 do assert(absent.resolve(sr)==nil)end;assert(reads==before,'Missing font must not repeat resource discovery')
available=true;absent.invalidate();assert(absent.resolve(sr),'Explicit reopen retries a font that loaded later')
package.loadlib=original
print('Windows Core Sans: complete loaded descriptor, zero DLL calls, stable resolution and missing-resource idle passed')

local runtime_font=factory.new(nil,nil,nil,true)
local runtime_sr={IdString64=sr.IdString64,Application={can_get=function(kind,id)
 return kind=='font'and id=='e01b1c60bb279a7c'or kind=='texture'and id=='039ab81e76d9bf05'or kind=='material'and id=='c38a65a21fb3e8d0'
end}}
assert(runtime_font.resolve(runtime_sr).font=='e01b1c60bb279a7c','Prefer the loaded game runtime font over an unavailable Core Sans family')

local latin=factory.new(nil,nil,nil,true)
local latin_sr={IdString64=sr.IdString64,Application={can_get=function(kind,id)
 return kind=='font'and id=='28a718e0d452eff0'or kind=='texture'and id=='c2cffd6538624e20'or kind=='material'and id=='c38a65a21fb3e8d0'
end}}
assert(latin.resolve(latin_sr).font=='28a718e0d452eff0','The Latin package must use its own loaded font and atlas')

local hud=factory.new(nil,nil,nil,true)
local hud_sr={IdString64=sr.IdString64,Application={can_get=function(kind,id)
 return kind=='font'and id=='b56d2abac5d17df2'or kind=='texture'and id=='d1ebb991c79f934b'or kind=='material'and id=='a21d59a5cbcbb5c4'
end}}
local actual=assert(hud.resolve(hud_sr))
assert(actual.atlas=='d1ebb991c79f934b','Prefer the observed HUD atlas over the absent name in the font header')
assert(actual.material=='a21d59a5cbcbb5c4','Bitmap atlas must use the matching bitmap shader, not the runtime-font shader')

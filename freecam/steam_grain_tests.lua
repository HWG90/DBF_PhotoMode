-- Pure composition contracts in actual Lua 5.1; no runtime, GUI or file writes.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run this fixture in actual Lua 5.1')
local composition=dofile('freecam/composition.lua')
composition.logo_art=dofile('freecam/assets/logo_art.lua')
composition.logo_art[2]=dofile('freecam/assets/helldiver_crest.lua')
local defaults=dofile('freecam/photo_options.lua').defaults
local function options()
 local values={};for key,value in pairs(defaults)do values[key]=value end
 values.grain=61;values.grain_size=2.25;values.vignette=35;values.vignette_width=19;values.grid=2
 return values
end
local function equal(a,b,path)
 if type(a)~=type(b)then error('Changed type at '..path)end
 if type(a)~='table'then if a~=b then error('Changed value at '..path)end;return end
 for key,value in pairs(a)do if key~='layer'then equal(value,b[key],path)end end
 for key in pairs(b)do if key~='layer'and a[key]==nil then error('Added field at '..path..'.'..tostring(key))end end
end
local function joined(static,grain)
 local result={};local foreground=false
 for _,command in ipairs(static)do
  assert(command.layer==100 or command.layer==102,'Static commands need explicit ordering')
  if command.layer==102 then foreground=true else assert(not foreground,'Static background must precede foreground');result[#result+1]=command end
 end
 for _,command in ipairs(grain)do assert(command.layer==101,'Grain must sit above finishing effects and below guides/logo');result[#result+1]=command end
 for _,command in ipairs(static)do if command.layer==102 then result[#result+1]=command end end
 return result
end
local comparisons=0
for _,frame in ipairs({1,2,3,4,5})do for _,filter in ipairs({1,2,19})do
 for _,logo in ipairs({2,3,5,7,13})do for _,clean in ipairs({false,true})do
  local o=options();o.frame,o.filter,o.logo,o.clean_view=frame,filter,logo,clean
  local static=composition.layout_static(1920,1080,o)
  for _,phase in ipairs({0,1,4095})do
   local legacy=composition.layout(1920,1080,o,(phase+.25)/12)
   local grain=composition.layout_grain(1920,1080,o,phase)
   assert(#grain==96,'Enabled grain must produce exactly 96 rectangles')
   local split=joined(static,grain);assert(#legacy==#split,'Split composition changed command count')
   for index,command in ipairs(legacy)do
    assert(command.layer==nil,'Legacy layout must not acquire split-layer fields')
    equal(command,split[index],'command '..index)
   end
   if clean then for _,command in ipairs(static)do assert(command.layer==100,'Clean view hides only foreground guides/logo')end end
   comparisons=comparisons+1
  end
 end end
end end
-- Grain is contained by the selected frame, including particles larger than it.
for _,dimensions in ipairs({{1920,1080},{1080,1920},{3,2}})do
 for _,frame in ipairs({1,2,3,4,5})do for _,size in ipairs({.1,2.25,8})do
  local w,h=dimensions[1],dimensions[2];local o=options();o.frame,o.grain_size=frame,size
  local ratio=({false,2.39,16/9,1,4/5})[frame];local x,y,fw,fh=0,0,w,h
  if ratio then if w/h>ratio then fw=h*ratio;x=(w-fw)/2 else fh=w/ratio;y=(h-fh)/2 end end
  for _,command in ipairs(composition.layout_grain(w,h,o,4095))do
   assert(command.kind=='rect'and command.layer==101 and command.a>0)
   assert(command.x>=x-.001 and command.y>=y-.001 and command.x+command.w<=x+fw+.001 and command.y+command.h<=y+fh+.001,'Grain left the selected frame')
  end
 end end
end
do
 local o=options();o.grain=0
 assert(#composition.layout_grain(1920,1080,o,0)==0,'Disabled grain must be empty')
 for _,phase in ipairs({-1,.5,4096,math.huge,-math.huge,0/0,'1',false})do
  assert(not pcall(composition.layout_grain,1920,1080,o,phase),'Reject non-integer or out-of-range phase')
 end
 assert(not pcall(composition.layout_grain,1920,1080,o,nil),'Require an explicit integer phase')
 -- Capture policy hides the grid, retaining the selected logo and grain.
 o=options();o.logo=5;o.grid=1
 local static=composition.layout_static(1920,1080,o);local foreground=0
 for _,command in ipairs(static)do if command.layer==102 then foreground=foreground+1 end end
 local art=composition.logo_art[5]
 assert(foreground==#(art.rects or{})+#(art.triangles or{}),'Grid suppression must retain the complete logo')
 assert(#composition.layout_grain(1920,1080,o,5)==96,'Capture policy keeps grain')
end
do
 local art=composition.logo_art;local saved_dofile,saved_loadfile,saved_open=dofile,loadfile,io.open
 local function unavailable()error('Grain generation must not read assets or rebuild static layout')end
 composition.logo_art=setmetatable({},{__index=unavailable})
 dofile,loadfile,io.open=unavailable,unavailable,unavailable
 local static_layout=composition.layout_static;composition.layout_static=unavailable
 local ok,why=pcall(function()
  local o=options();o.logo=13
  for phase=0,4095 do assert(#composition.layout_grain(1920,1080,o,phase)==96)end
 end)
 composition.logo_art=art;composition.layout_static=static_layout
 dofile,loadfile,io.open=saved_dofile,saved_loadfile,saved_open
 assert(ok,why)
end
print('Steam grain: '..comparisons..' legacy/split comparisons, 96 bounded particles, layer/clean/capture semantics, strict phases and no asset/static work passed')

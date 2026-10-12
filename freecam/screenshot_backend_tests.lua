local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'screenshot_backend.lua')
local function integer(v)local out={};for i=1,4 do out[i]=string.char(v%256);v=math.floor(v/256)end;return table.concat(out)end
local function dds(width,height,pixels)
 local header='DDS '..integer(124)..integer(0x1007)..integer(height)..integer(width)..integer(width*4)..string.rep('\0',56)
 header=header:sub(1,76)..integer(32)..integer(4)..'DX10'..string.rep('\0',40)
 assert(#header==128)
 return header..integer(28)..integer(3)..integer(0)..integer(1)..integer(0)..(pixels or string.rep('\255',width*height*4))
end
local body=dds(2,2);local meta=factory.inspect(body:sub(1,148),#body)
assert(meta.width==2 and meta.height==2 and meta.format==28 and meta.bytes==164 and meta.dx10)
assert(not pcall(factory.inspect,body:sub(1,147),#body));assert(not pcall(factory.inspect,dds(0,2),160));assert(not pcall(factory.inspect,body,148))
local original_open=io.open;local files={};local calls=0;local allowed=true
io.open=function(path,mode)
 if mode=='rb'and files[path]then local content=files[path]
  return {close=function()end,seek=function(_,where)if where=='end'then return #content end;return 0 end,read=function(_,n)return content:sub(1,n)end}
 end
end
local sr={Application={save_render_target=function(target,path)assert(target=='back_buffer');calls=calls+1;files[path]=body end}}
local backend=assert(factory.new(sr,function()return allowed end))
assert(not backend.capture('relative.dds'));assert(not backend.capture('C:/Shots/bad.png'));assert(not backend.capture('C:/Shots/../outside.dds'));assert(calls==0)
allowed=false;assert(not backend.capture('C:/Shots/one.dds'));assert(calls==0)
allowed=true;local ok,result=backend.capture('C:/Shots/one.dds');assert(ok and result.path=='C:/Shots/one.dds'and calls==1)
assert(not backend.capture('C:/Shots/one.dds')and calls==1,'Capture must not overwrite an existing image')
sr.Application.save_render_target=function()calls=calls+1 end
assert(not backend.capture('C:/Shots/missing.dds'),'A nil native return must not be reported as a saved screenshot')
sr.Application.save_render_target=function(_,path)calls=calls+1;files[path]='not an image'end
assert(not backend.capture('C:/Shots/invalid.dds'))
sr.Application.save_render_target=function()error('Native capture refused')end
assert(not backend.capture('C:/Shots/exception.dds'))
io.open=original_open
print('Photo screenshot backend: existing-target guard, absolute DDS path, no overwrite, file/header/dimension validation and failure reporting passed')

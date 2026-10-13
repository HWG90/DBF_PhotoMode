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
 if mode=='r+b'and files[path]then local offset=0
  return {close=function()end,seek=function(_,_,where)offset=where;return offset end,write=function(_,value)files[path]=files[path]:sub(1,offset)..value..files[path]:sub(offset+#value+1);offset=offset+#value end}
 end
 if mode=='rb'and files[path]then local content=files[path]
  return {close=function()end,seek=function(_,where)if where=='end'then return #content end;return 0 end,read=function(_,n)return content:sub(1,n)end}
 end
end
local sr={Application={save_render_target=function(target,path)assert(target=='back_buffer');calls=calls+1;files[path]=body end}}
local hdr=false;local hdr_proof=true
local backend=assert(factory.new(sr,function()return allowed,{format=16,width=2,height=2,kind=4,mips=1,array=1,hdr_enabled=hdr,hdr10_output_verified=hdr_proof}end))
assert(not backend.capture('relative.dds'));assert(not backend.capture('C:/Shots/bad.png'));assert(not backend.capture('C:/Shots/../outside.dds'));assert(calls==0)
allowed=false;assert(not backend.capture('C:/Shots/one.dds'));assert(calls==0)
allowed=true;local ok,result=backend.capture('C:/Shots/one.dds');assert(ok and result.path=='C:/Shots/one.dds'and calls==1)
assert(not backend.capture('C:/Shots/one.dds')and calls==1,'Capture must not overwrite an existing image')
local hdr_body=body:sub(1,128)..integer(24)..body:sub(133)
sr.Application.save_render_target=function(_,path)calls=calls+1;files[path]=hdr_body end
hdr=true;ok,result=backend.capture('C:/Shots/hdr.dds');assert(ok and result.color_encoding=='hdr10-pq-bt2020'and result.white_nits==203 and result.hdr_enabled==true,'HDR encoding must follow the live flag and verified native output branch')
hdr=false;ok,result=backend.capture('C:/Shots/sdr10.dds');assert(ok and result.color_encoding=='srgb','RGB10 storage alone must not select PQ conversion')
hdr=true;hdr_proof=false;ok,result=backend.capture('C:/Shots/no-proof.dds');assert(ok and result.color_encoding=='srgb','A changed output branch must not be treated as verified HDR10')
hdr_proof=true;local unknown=body:sub(1,128)..integer(0)..body:sub(133)
sr.Application.save_render_target=function(_,path)calls=calls+1;files[path]=unknown end
ok,result=backend.capture('C:/Shots/unknown-hdr.dds');assert(ok and result.format==24 and result.color_encoding=='hdr10-pq-bt2020','Descriptor-proven UNKNOWN DDS must still normalize and select HDR10 correctly')
sr.Application.save_render_target=function()calls=calls+1 end
assert(not backend.capture('C:/Shots/missing.dds'),'A nil native return must not be reported as a saved screenshot')
sr.Application.save_render_target=function(_,path)calls=calls+1;files[path]='not an image'end
assert(not backend.capture('C:/Shots/invalid.dds'))
sr.Application.save_render_target=function()error('Native capture refused')end
assert(not backend.capture('C:/Shots/exception.dds'))
local sdr_width=2;local sdr_hdr=false
local sdr_backend=assert(factory.new(sr,function()return true,{format=0,width=sdr_width,height=2,kind=4,mips=1,array=1,hdr_enabled=sdr_hdr}end))
sr.Application.save_render_target=function(_,path)files[path]=body end
ok,result=sdr_backend.capture('C:/Shots/engine-sdr.dds');assert(ok and result.color_encoding=='sdr-bgra-engine','Verified native SDR RGBA-labelled BGRA needs the engine-specific converter')
sdr_width=3;ok,result=sdr_backend.capture('C:/Shots/unmatched-sdr.dds');assert(ok and result.color_encoding=='srgb','Do not swap channels for an unverified surface shape')
sdr_width=2;sdr_hdr=true;ok,result=sdr_backend.capture('C:/Shots/non-sdr-state.dds');assert(ok and result.color_encoding=='srgb','The SDR correction requires a verified live SDR flag')
io.open=original_open
print('Photo screenshot backend: existing-target guard, absolute DDS path, no overwrite, file/header/dimension validation and failure reporting passed')

-- Tests for png_stored.lua. Pixel checks live in test_png_stored.py.
local png=dofile('png_stored.lua')
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
assert(png.crc32('')==0 and png.crc32('123456789')==0xCBF43926,'CRC-32 check value')
assert(png.adler32('')==1 and png.adler32('Wikipedia')==0x11E60398,'Adler-32 check value')
assert(hex(png.chunk('IEND',''))=='0000000049454e44ae426082','IEND chunk bytes')
-- A 3x2 SDR image.
local sdr=table.concat{
 string.char(1,2,3,255),string.char(4,5,6,255),string.char(7,8,9,0),
 string.char(10,11,12,255),string.char(13,14,15,255),string.char(16,17,18,255)}
local whole=png.encode{width=3,height=2,format='bgra8',data=sdr}
-- Pull the image data out of a PNG so two files can be compared.
local function stream(file)
 local at,parts=9,{}
 while at<=#file do
  local a,b,c,d=file:byte(at,at+3);local length=((a*256+b)*256+c)*256+d;local kind=file:sub(at+4,at+7)
  if kind=='IDAT'then parts[#parts+1]=file:sub(at+8,at+7+length)end
  at=at+12+length
 end
 return table.concat(parts)
end
assert(whole:sub(1,8)=='\137PNG\r\n\26\n','Signature')
assert(hex(whole:sub(9,33))=='0000000d49484452'..'00000003'..'00000002'..'0802000000'..hex(whole:sub(30,33)),'IHDR: 3x2, 8-bit RGB')
assert(whole:sub(-12)==png.chunk('IEND',''),'IEND last')
for _,step in ipairs({1,16,17,100})do
 local job=png.begin{width=3,height=2,format='bgra8',data=sdr};local parts={job.head};local n=0
 repeat local out=job:step(step);parts[#parts+1]=out;n=n+1 until job.done
 parts[#parts+1]=job.tail
 local file=table.concat(parts)
 assert(stream(file)==stream(whole)and file:sub(1,33)==whole:sub(1,33)and file:sub(-12)==whole:sub(-12),'Step size '..step..' changes the stream')
 assert(#file>=#whole,'Smaller steps only add IDAT framing')
 assert(job.done and job:progress()==1 and job.rows_done==2)
end
-- Padded rows after a header.
local padded='HDR!'..sdr:sub(1,12)..'pad'..sdr:sub(13,24)..'pad'
assert(png.encode{width=3,height=2,format='bgra8',data=padded,offset=4,pitch=15}==whole,'Pitch and offset are honoured')
-- Two HDR pixels.
local function pack(r,g,b,a)local v=r+g*1024+b*1048576+(a or 3)*1073741824;return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216))end
local hdr=png.encode{width=2,height=1,format='rgb10a2',data=pack(0,512,1023)..pack(1,2,3,0)}
assert(hex(hdr:sub(9,33)):sub(1,16+8+8+10)=='0000000d49484452'..'00000002'..'00000001'..'1002000000','IHDR: 16-bit RGB')
assert(hdr:sub(34,45)=='\0\0\0\4cICP\9\16\0\1','HDR10 tag')
-- The DDS reader, with both the game's format labels and the loader's fixed ones.
local function dds(dxgi,w,h,extra)
 local function n(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
 local hd=string.rep('\0',148)
 local function put(at,s)hd=hd:sub(1,at)..s..hd:sub(at+#s+1)end
 put(0,'DDS ');put(4,n(124));put(12,n(h));put(16,n(w));put(20,n(w*4));put(84,'DX10');put(128,n(dxgi));put(132,n(3));put(140,n(1))
 return hd..string.rep('\0',w*h*4)
end
for dxgi,format,label in pairs({[87]={'bgra8',false},[91]={'bgra8',false},[28]={'bgra8',true},[24]={'rgb10a2',false},[0]={'rgb10a2',true}})do
 local info=png.inspect_dds(dds(dxgi,4,3),148+48)
 assert(info.format==format[1]and info.engine_label==format[2]and info.width==4 and info.height==3 and info.offset==148,'DXGI '..dxgi)
end
assert(not pcall(png.inspect_dds,dds(41,4,3),148+48),'Depth is not a screenshot')
assert(not pcall(png.inspect_dds,dds(87,4,3):sub(1,100),100),'A short file refuses')
assert(not pcall(png.inspect_dds,'notadds'..string.rep('\0',200),207),'Not a DDS refuses')
local job=png.begin_dds(dds(87,4,3))
assert(job.dds.dxgi==87 and job.width==4 and job.height==3)
local out={job.head};repeat out[#out+1]=job:step(1)until job.done;out[#out+1]=job.tail
assert(#table.concat(out)>0 and job.done)
assert(not pcall(png.begin,{width=2,height=1,format='bgra8',data='short'}),'Short data refuses')
assert(not pcall(png.begin,{width=2,height=1,format='rgba8',data=string.rep('\0',8)}),'Unknown format refuses')
print('png_stored: all tests passed')

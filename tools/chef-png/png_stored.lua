-- Screenshot DDS to PNG. Plain Lua 5.1, no bit library, a slice at a time.
-- Uncompressed PNG: the only real work is the two checksums.
--
--   local job=png.begin_dds(dds_bytes)
--   file:write(job.head)
--   repeat file:write(job:step(262144))until job.done
--   file:write(job.tail)
--
-- See README.md for the rest.
local M={}
local byte,char,sub,gsub,concat,floor=string.byte,string.char,string.sub,string.gsub,table.concat,math.floor

-- X[a*256+b+1] = a xor b. The CRC is kept as four bytes so no bit library is needed.
local X={}
do
 local nib={}
 for a=0,15 do for b=0,15 do
  local r,x,y,p=0,a,b,1
  for _=1,4 do if x%2~=y%2 then r=r+p end;x=floor(x/2);y=floor(y/2);p=p*2 end
  nib[a*16+b]=r
 end end
 for a=0,255 do
  local ah,al=floor(a/16),a%16;local base=a*256+1
  for b=0,255 do X[base+b]=nib[ah*16+floor(b/16)]*16+nib[al*16+b%16]end
 end
end
local T0,T1,T2,T3={},{},{},{}
do
 local function xor32(a,b)
  local r,p=0,1
  for _=1,4 do r=r+X[(a%256)*256+(b%256)+1]*p;a=floor(a/256);b=floor(b/256);p=p*256 end
  return r
 end
 for n=0,255 do
  local c=n
  for _=1,8 do if c%2==1 then c=xor32(floor(c/2),0xEDB88320)else c=floor(c/2)end end
  T0[n]=c%256;T1[n]=floor(c/256)%256;T2[n]=floor(c/65536)%256;T3[n]=floor(c/16777216)
 end
end
-- CRC-32 of s[i..j], carrying on from the four state bytes. Start at 255,255,255,255.
local function crc_update(c0,c1,c2,c3,s,i,j)
 for k=i,j do
  local t=X[c0*256+byte(s,k)+1]
  c0,c1,c2,c3=X[T0[t]*256+c1+1],X[T1[t]*256+c2+1],X[T2[t]*256+c3+1],T3[t]
 end
 return c0,c1,c2,c3
end
local function crc_bytes(c0,c1,c2,c3)return char(255-c3,255-c2,255-c1,255-c0)end
function M.crc32(s)
 local c0,c1,c2,c3=crc_update(255,255,255,255,s,1,#s)
 return ((255-c3)*256+(255-c2))*65536+(255-c1)*256+(255-c0)
end
-- Adler-32 and CRC-32 of s[i..j] in one pass.
local function sums_update(a,b,c0,c1,c2,c3,s,i,j)
 local k=i
 while k<=j do
  local stop=k+4095;if stop>j then stop=j end
  for n=k,stop do
   local v=byte(s,n);a=a+v;b=b+a
   local t=X[c0*256+v+1]
   c0,c1,c2,c3=X[T0[t]*256+c1+1],X[T1[t]*256+c2+1],X[T2[t]*256+c3+1],T3[t]
  end
  a=a%65521;b=b%65521;k=stop+1
 end
 return a,b,c0,c1,c2,c3
end
function M.adler32(s)local a,b=sums_update(1,0,255,255,255,255,s,1,#s);return b*65536+a end
local function be32(n)return char(floor(n/16777216)%256,floor(n/65536)%256,floor(n/256)%256,n%256)end
local function le16(n)return char(n%256,floor(n/256))end
local function chunk(kind,data)
 local c0,c1,c2,c3=crc_update(255,255,255,255,kind,1,4)
 c0,c1,c2,c3=crc_update(c0,c1,c2,c3,data,1,#data)
 return be32(#data)..kind..data..crc_bytes(c0,c1,c2,c3)
end
M.chunk=chunk

-- SDR rows: BGRA in, RGB out, one gsub per row.
local function rows_bgra8(data,offset,pitch,width,first,count)
 local parts={}
 for r=0,count-1 do
  local at=offset+(first+r)*pitch+1
  parts[#parts+1]='\0'..(gsub(sub(data,at,at+width*4-1),'(.)(.)(.)(.)','%3%2%1'))
 end
 return concat(parts)
end
-- HDR rows: 10-bit channels in, 16-bit RGB out.
local function rows_rgb10a2(data,offset,pitch,width,first,count)
 local parts,px={},{}
 for r=0,count-1 do
  local at=offset+(first+r)*pitch+1
  for x=0,width-1 do
   local b0,b1,b2,b3=byte(data,at+x*4,at+x*4+3)
   local v=b0+b1*256+b2*65536+b3*16777216
   local red,green,blue=v%1024,floor(v/1024)%1024,floor(v/1048576)%1024
   red=red*64+floor(red/16);green=green*64+floor(green/16);blue=blue*64+floor(blue/16)
   px[x+1]=char(floor(red/256),red%256,floor(green/256),green%256,floor(blue/256),blue%256)
  end
  parts[#parts+1]='\0'..concat(px,'',1,width)
 end
 return concat(parts)
end
local FORMATS={bgra8={rows=rows_bgra8,depth=8,out_pixel=3},rgb10a2={rows=rows_rgb10a2,depth=16,out_pixel=6}}

-- spec: width, height, format ('bgra8' or 'rgb10a2'), data, and optionally offset and pitch.
function M.begin(spec)
 local width,height=spec.width,spec.height
 assert(type(width)=='number'and type(height)=='number'and width>=1 and height>=1 and width<=16384 and height<=16384 and width%1==0 and height%1==0,'PNG: bad size')
 local format=assert(FORMATS[spec.format],'PNG: format must be bgra8 or rgb10a2')
 local data=spec.data;assert(type(data)=='string','PNG: data must be a string')
 local offset=spec.offset or 0;local pitch=spec.pitch or width*4
 assert(pitch>=width*4 and offset>=0 and #data>=offset+pitch*(height-1)+width*4,'PNG: data shorter than the image')
 local job={width=width,height=height,format=spec.format,done=false,rows_done=0,in_bytes=pitch*height,out_bytes=0}
 local head={'\137PNG\r\n\26\n',chunk('IHDR',be32(width)..be32(height)..char(format.depth,2,0,0,0))}
 if spec.format=='rgb10a2'then head[#head+1]=chunk('cICP',char(9,16,0,1))end -- HDR10 tag
 job.head=concat(head);job.tail=chunk('IEND','')
 local row_bytes=1+width*format.out_pixel
 local a,b=1,0            -- Adler-32 so far
 local carry=''           -- bytes waiting for the next block
 local started=false
 function job:step(budget)
  assert(not self.done,'PNG: finished')
  local per_row=pitch
  local rows=floor((budget or 262144)/per_row);if rows<1 then rows=1 end
  if self.rows_done+rows>height then rows=height-self.rows_done end
  local filtered=format.rows(data,offset,pitch,width,self.rows_done,rows)
  assert(#filtered==rows*row_bytes,'PNG: row conversion size')
  self.rows_done=self.rows_done+rows
  local last=self.rows_done==height
  local raw=carry..filtered;carry=''
  local out,is_payload={},{}
  -- Blocks of up to 65535 bytes. A short tail waits for the next step unless this is the end.
  local at,n=1,#raw
  assert(not last or n>0,'PNG: nothing to finish')
  while(not last and n-at+1>=65535)or(last and at<=n)do
   local take=n-at+1;if take>65535 then take=65535 end
   local final=last and at+take-1>=n
   out[#out+1]=char(final and 1 or 0)..le16(take)..le16(65535-take)
   out[#out+1]=sub(raw,at,at+take-1);is_payload[#out]=true
   at=at+take
   if final then break end
  end
  if at<=n then carry=sub(raw,at)end
  if #out==0 then return''end -- not a full block yet
  local prefix=''
  if not started then prefix='\120\1';started=true end -- zlib header, once
  local c0,c1,c2,c3=crc_update(255,255,255,255,'IDAT',1,4)
  c0,c1,c2,c3=crc_update(c0,c1,c2,c3,prefix,1,#prefix)
  local total=#prefix
  for i=1,#out do
   local piece=out[i]
   -- Pixel bytes go into both sums, headers only into the CRC.
   if is_payload[i]then a,b,c0,c1,c2,c3=sums_update(a,b,c0,c1,c2,c3,piece,1,#piece)
   else c0,c1,c2,c3=crc_update(c0,c1,c2,c3,piece,1,#piece)end
   total=total+#piece
  end
  if last then
   local trailer=be32(b*65536+a)
   c0,c1,c2,c3=crc_update(c0,c1,c2,c3,trailer,1,4)
   out[#out+1]=trailer;total=total+4
   self.done=true
  end
  self.out_bytes=self.out_bytes+total
  return be32(total)..'IDAT'..prefix..concat(out)..crc_bytes(c0,c1,c2,c3)
 end
 function job:progress()return self.rows_done/height end
 return job
end

-- Read the screenshot's DDS header: 148 bytes, then the pixels.
function M.inspect_dds(header,size)
 local function u(i)local a,b,c,d=byte(header,i+1,i+4);assert(d,'DDS: header short');return a+b*256+c*65536+d*16777216 end
 assert(#header>=148 and sub(header,1,4)=='DDS 'and u(4)==124 and sub(header,85,88)=='DX10','DDS: not a DX10 DDS')
 local height,width,dxgi=u(12),u(16),u(128)
 assert(width>=1 and height>=1 and width<=16384 and height<=16384,'DDS: bad size')
 assert(u(132)==3 and u(140)==1 and u(136)==0,'DDS: not one plain 2D surface')
 assert(u(24)<=1 and u(28)<=1,'DDS: mips or slices')
 local format=(dxgi==87 or dxgi==91 or dxgi==28 or dxgi==29)and'bgra8'or(dxgi==24 or dxgi==0)and'rgb10a2'or nil
 assert(format,'DDS: pixel format '..dxgi..' is not a screenshot format')
 local pitch=u(20);if pitch<width*4 then pitch=width*4 end
 if size then assert(size>=148+pitch*(height-1)+width*4,'DDS: file shorter than its header says')end
 return{width=width,height=height,dxgi=dxgi,format=format,pitch=pitch,offset=148,
  engine_label=dxgi==28 or dxgi==29 or dxgi==0}
end
function M.begin_dds(dds)
 local info=M.inspect_dds(dds,#dds)
 local job=M.begin{width=info.width,height=info.height,format=info.format,data=dds,offset=148,pitch=info.pitch}
 job.dds=info;return job
end
-- All in one call. Fine for small images.
function M.encode(spec)
 local job=M.begin(spec);local parts={job.head}
 repeat parts[#parts+1]=job:step(spec.step or math.huge)until job.done
 parts[#parts+1]=job.tail;return concat(parts)
end
return M

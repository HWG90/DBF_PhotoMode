-- Current renderer resources: read existing registrations, never insert targets.
local M={}
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d,'Renderer record truncated');return a+b*256+c*65536+d*16777216 end
local function pointer(s,o)return u32(s,o)+u32(s,o+4)*4294967296 end
function M.new(sr,memory,bridge)
 local self={};local function bulk(at,n)local chunks={};for offset=0,n-1,4096 do chunks[#chunks+1]=memory.read(at+offset,math.min(4096,n-offset))end;return table.concat(chunks)end
 local function ptr(at)local p=pointer(memory.read(at,8),0);assert(p>=65536 and p<2^47,'Renderer pointer invalid');return p end
 local function word(at)return u32(memory.read(at,4),0)end
 local function check()
  local pe=word(memory.exe+60);assert(word(memory.exe+pe+8)==0x6ae0964a,'Renderer build differs')
  assert(memory.function_address(sr.Renderer.resource)==memory.exe+0x3f9390,'Renderer getter differs')
  assert(memory.read(memory.exe+0x103d1d,6)=='\139\133\144\004\000\000'and memory.read(memory.exe+0x103d2c,7)=='\072\139\133\128\004\000\000','Renderer cache consumer differs')
  local renderer=ptr(ptr(memory.exe+0x24099e8)+0x338);return renderer
 end
 function self.target(hash)
  local renderer=check();local map=renderer+0x1790;local count=word(map);assert(count>0 and count<=4096,'Renderer registry count invalid')
  local rows=ptr(map+8);local resource;local records=bulk(rows,count*32)
  for i=0,count-1 do local row=records:sub(i*32+1,i*32+32)
   if u32(row,24)~=4294967294 and u32(row,0)==hash then assert(not resource,'Renderer resource ambiguous');resource=pointer(row,8)end
  end
  assert(resource and resource>=65536 and resource<2^47,'Existing renderer resource unavailable')
  local backend=ptr(renderer+0x1168);local active=word(backend+0x490);assert(active<=8,'Renderer cache generation invalid')
  local cache=ptr(backend+0x480)+active*40;local n=word(cache);assert(n>0 and n<=4096,'Renderer cache count invalid');local entries=ptr(cache+8);local backing;local records=bulk(entries,n*24)
  for i=0,n-1 do local row=records:sub(i*24+1,i*24+24)
   if u32(row,16)~=4294967294 and pointer(row,0)==resource then assert(not backing,'Renderer backing ambiguous');backing=pointer(row,8)end
  end
  assert(backing and backing>=65536 and backing<2^47,'Renderer backing unavailable')
  local d=memory.read(backing,36);local id=u32(d,0);assert(id%16777216~=16777215,'Renderer texture ID invalid')
  return{renderer=renderer,resource=resource,backing=backing,id=id,format=u32(d,8),width=u32(d,20),height=u32(d,24),mips=u32(d,28),array=u32(d,32),kind=d:byte(4)}
 end
 function self.registered(requested)
  local renderer=check();local manager=ptr(renderer+0x1208);local slots,cap=word(manager+0x100),word(manager+0x104);local buckets=word(manager+0x11c)
  assert(slots>0 and slots<=cap and cap<=100000 and buckets>0 and buckets<=slots,'Shader registry invalid')
  local rows=ptr(manager+0x108)
  for _,wanted in ipairs({0x9fcfe126,requested or 0x217cc71f})do
   local index=wanted%buckets;local seen={};local found=false
   for _=1,slots do
    assert(index<slots and not seen[index],'Shader registry chain invalid');seen[index]=true
    local row=memory.read(rows+index*32,32);local next_index=u32(row,24)
    if next_index==4294967294 then break end
    if u32(row,0)==wanted then local p=pointer(row,8);assert(p>=65536 and p<2^47,'Shader definition invalid');found=true;break end
    index=next_index%2147483648;if index==2147483647 then break end
   end
   assert(found,'Photo shader registration unavailable')
  end
  return true
 end
 function self.color()
  local target=self.target(0xa68c78a4);local display=self.target(0x2b269c03)
  assert(target.resource~=display.resource and target.backing~=display.backing and target.id~=display.id,'Scene color aliases display')
  local getter=sr.Application.render_setting;assert(memory.function_address(getter)==memory.exe+0x3d42f0,'Render setting getter differs')
  assert(memory.read(memory.exe+0x3d40ba,7)=='\072\139\013\255\055\110\001','Render setting schema binding differs')
  local settings=ptr(memory.exe+0x1ab78c0);local n=word(settings);assert(n>0 and n<=4096,'Render settings count invalid');local rows=ptr(settings+8);local schema={};local records=bulk(rows,n*24)
  for i=0,n-1 do local row=records:sub(i*24+1,i*24+24);schema[u32(row,16)]=u32(row,0)end
  assert(schema[0xbf7ef641]==4 and schema[0x3f5fea89]==1,'Render settings schema differs')
  target.hdr_enabled=getter('hdr_enabled');target.ui_brightness=getter('ui_brightness');return true,target
 end
 local depth={}
 function depth.available()local ok,value=pcall(self.target,0x9b8038e0);return ok,not ok and tostring(value)or nil end
 function depth.get()
  local target=self.target(0x9b8038e0);assert(target.kind==2 and target.format==1 and target.mips==1 and target.array==1,'Depth descriptor differs')
  local resource=sr.Renderer.resource('linear_depth');assert(bridge.userdata_address(resource)==target.resource,'Depth handle differs')
  depth.binding_identity=tostring(target.backing)..':'..tostring(target.id);return resource
 end
 self.depth=depth
 return self
end
return M

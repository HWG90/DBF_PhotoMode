-- Engine DDS capture (native Windows / no Linux worker): the back buffer through the real
-- coordinator, header corrections proven by size, refusals, and failure records.
-- In-memory files and a fake engine writer only.
local C=dofile('freecam/engine_capture.lua')
local function le32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function dds(w,h,format,pitch)
 local header='DDS '..le32(124)..le32(0)..le32(h)..le32(w)..le32(pitch or w*4)..string.rep('\0',84-24)..'DX10'..string.rep('\0',128-88)..le32(format)..le32(3)..le32(0)..le32(1)..le32(0)
 return header..string.rep('\1',w*h*4)
end
local files={}
local function handle(path,mode)
 local pos=0
 local h={}
 function h:seek(where,offset)if where=='end'then pos=#files[path]else pos=offset or 0 end;return pos end
 function h:read(n)local s=files[path]:sub(pos+1,pos+n);pos=pos+#s;return s end
 function h:write(s)local d=files[path];files[path]=d:sub(1,pos)..s..d:sub(pos+#s+1);pos=pos+#s;return true end
 function h:close()return true end
 return h
end
local fs={open=function(path,mode)if not files[path]then return nil end;return handle(path,mode)end}
local hdr,written,next_file=false,0,nil
local sr={Application={render_setting=function(k)assert(k=='hdr_enabled');return hdr end,
 save_render_target=function(name,path)assert(name=='back_buffer');written=written+1;if next_file==false then error('target missing')end;files[path]=next_file end}}
assert(C.new({Application={}},'C:/x',fs)==nil,'No engine writer, no backend')
local backend=assert(C.new(sr,'C:/Users/me/Pictures/',fs))
assert(backend.output_directory=='C:/Users/me/Pictures'and backend.extension=='dds'and backend.capabilities.format=='dds')
local function format(path)local s=files[path];local a,b,c,d=s:byte(129,132);return a+b*256+c*65536+d*16777216 end
-- Through the real coordinator: hidden frames, then the engine writes the back buffer.
local now=0;local capture=dofile('freecam/steam_capture.lua').new(backend,function()return now end)
local ctx={session='s',scene='w',focused=true,frame_id=0}
local name='War-Journalist-20261025-120000-1-1.dds';local path='C:/Users/me/Pictures/'..name
next_file=dds(8,4,28)
assert(capture.begin({output_token=name,output_path=path},ctx))
for i=1,13 do ctx.frame_id=i;now=now+.016;capture.rendered(i,true,true,ctx);capture.tick(ctx)end
for _=1,3 do now=now+.016;capture.tick(ctx)end
local result=capture.result()
assert(written==1 and result and result.state=='succeeded'and result.output_path==path,'The coordinator gets a succeeded record')
assert(format(path)==87,'SDR BGRA labelled 28 is corrected to 87')
-- HDR: RGB10A2 written as format 0 becomes 24; a size that does not prove it stays.
hdr=true;next_file=dds(8,4,0)
local token=backend.new_job_token();local p2='C:/Users/me/Pictures/War-Journalist-2.dds'
assert(backend.request({job_token=token,output_token='War-Journalist-2.dds',output_path=p2}).state=='succeeded'and format(p2)==24)
next_file=dds(8,4,0,40);token=backend.new_job_token();local p3='C:/Users/me/Pictures/War-Journalist-3.dds'
assert(backend.request({job_token=token,output_token='War-Journalist-3.dds',output_path=p3}).state=='succeeded'and format(p3)==0,'Unproven layouts are left as written')
-- Refusals and failures.
token=backend.new_job_token()
assert(backend.request({job_token=token,output_token='War-Journalist-2.dds',output_path=p2})==nil,'An existing file is never replaced')
assert(backend.request({job_token=token,output_token='shot.png',output_path='C:/Users/me/Pictures/shot.png'})==nil,'Only our DDS names')
assert(backend.request({job_token='engine-shot:0',output_token='War-Journalist-4.dds',output_path='C:/Users/me/Pictures/War-Journalist-4.dds'})==nil,'Only the latest token')
next_file=false;local r=backend.request({job_token=token,output_token='War-Journalist-5.dds',output_path='C:/Users/me/Pictures/War-Journalist-5.dds'})
assert(r.state=='failed'and r.reason:find('target missing',1,true),'An engine error is a failed record')
assert(backend.status(r.job_token,r.output_token).state=='failed'and select(2,backend.cancel(r.job_token,r.output_token)).state=='failed')
print('Engine capture: back buffer through the coordinator, SDR/HDR header corrections, unproven layouts kept, refusals and failure records passed')

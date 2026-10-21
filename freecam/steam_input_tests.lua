local F=dofile('freecam/steam_input.lua')
local token,owner,snapshots,releases,buttons={},nil,0,0,1
local raw={x=50,y=25,width=100,height=100,buttons=buttons,wheel=120,dx=3,dy=-4}
local service={version=1,capabilities={menu=true,camera=false,relative_mouse=false},
 acquire=function(id,mode)assert(id=='dbf_freecam');if owner then return nil,'Owned'end;owner=token;return token end,
 owns=function(t)return t==owner end,
 status=function()return{owner=owner and 'dbf_freecam'or nil,pending_restore=false}end,
 snapshot=function(t)assert(t==owner);snapshots=snapshots+1;return raw end,
 release=function(t)assert(t==owner);releases=releases+1;owner=nil;return true end}
local pressed=0
local sr={Gui={resolution=function()return 200,300 end},Window={has_focus=function()return true end},
 Keyboard={button_id=function(name)assert(name=='caps lock');return 20 end,button=function(id)pressed=pressed+1;return 1 end}}
local input=F.new(sr,service)
for i=1,100 do input.frame();assert(input.down(20))end
assert(input.focused()and not input.pending_restore(),'Focus is the cached frame state; idle state owns no cleanup token')
assert(snapshots==0 and pressed==100,'Closed input must never query the pointer helper')
assert(input.set_mode('menu'));input.frame()
local p=input.sample();assert(p.x==100 and p.y==225 and not p.click and p.wheel==0,'Ignore held opening click')
assert(input.sample()==p and snapshots==1,'At most one sample per frame')
assert(raw.buttons==1 and raw.x==50,'Never mutate shared sample')
raw.buttons=0;input.frame();assert(input.sample())
raw.buttons=1;input.frame();assert(input.sample().click)
assert(input.wheel()==120 and input.wheel()==0,'Consume wheel once')
assert(input.set_mode('camera')==false and owner==nil,'Never infer raw motion from cursor XY')
service.capabilities.camera=true;service.capabilities.relative_mouse=true
assert(input.set_mode('camera'));raw.buttons=0;input.frame()
p=input.sample();assert(p.dx==0 and p.dy==0,'Discard motion on ownership transition')
input.frame();p=input.sample();assert(p.dx==3 and p.dy==-4)
owner=nil;input.frame();assert(input.sample()==nil,'Reject a revoked token')
-- The real service accepts release of a revoked owned token for final cleanup.
service.release=function(t)assert(t==token);return true end
assert(input.release())
assert(input.set_mode('menu'));service.release=function()return false,'Restore pending'end
assert(input.release()==false and not input.owns(),'Pending restoration must not grant input')
assert(input.pending_restore(),'Failed release exposes its retained cleanup token')
service.release=function()owner=nil;return true end
assert(input.release())
assert(not input.pending_restore())
service.acquire=function()owner=token;return nil,'Activation failed',token end
assert(input.set_mode('menu')==false and not input.owns(),'Failed acquire must preserve cleanup token without granting input')
assert(input.release())
-- Screenshot's existing VK_PAUSE binding uses the engine's named button.
local pause_reads=0
sr.Keyboard.button_id=function(name)assert(name=='pause');return 19 end
sr.Keyboard.button=function(id)assert(id==19);pause_reads=pause_reads+1;return 1 end
input.frame();assert(input.down(19)and input.down(19)and pause_reads==1)
assert(input.down(255)==false,'Unsupported bindings stay unavailable')
local function bitmap(codes)
 local bytes={};for i=1,32 do bytes[i]=0 end
 for _,code in ipairs(codes or{})do local i=math.floor(code/8)+1;bytes[i]=bytes[i]+2^(code%8)end
 local out={};for i=1,32 do out[i]=string.char(bytes[i])end;return table.concat(out)
end
local capture_mask=('00331f08ffe1ff03feffff27fffffff7ff0003003f0000fc010000f804000000'):gsub('%x%x',
 function(hex)return string.char(tonumber(hex,16))end)
local function captured_fixture(legacy)
 local f={snapshots=0,acquires=0,releases=0,mode_changes=0,engine_reads=0,engine_ids=0,resolutions=0,
  focus=true,owns=true,claimed=false,generation=7,acquire_calls={}}
 f.raw={valid=true,x=50,y=25,width=100,height=100,buttons=0,wheel=120,dx=3,dy=-4,
  keyboard_state=2,keyboard_active=true,keyboard_keys=bitmap(),keyboard_mask=capture_mask,keyboard_generation=7}
 local broker={version=1,capabilities={menu=true,camera=true,relative_mouse=true,keyboard=not legacy,keyboard_mask=not legacy and capture_mask or nil}}
 broker.acquire=function(...)
  local id,mode,third,options=...
  assert(id=='dbf_freecam'and third==nil and(mode=='menu'or mode=='camera'))
  f.acquires=f.acquires+1;f.acquire_calls[f.acquires]={argc=select('#',...),options=options}
  if f.acquire_refuse then return nil,'Acquire refused'end
  f.token={};f.claimed=true
  if f.acquire_cleanup then return nil,'Activation refused',f.token end
  return f.token
 end
 broker.owns=function(t)return f.claimed and f.owns and t==f.token end
 broker.status=function()return{owner=f.claimed and'dbf_freecam'or nil,pending_restore=f.restore_pending==true}end
 broker.snapshot=function(t)
  assert(t==f.token);f.snapshots=f.snapshots+1
  if f.snapshot_error then error(f.snapshot_error)end
  if f.snapshot_absent then return nil,'Snapshot absent'end
  return f.raw
 end
 broker.release=function(t)
  assert(t==f.token);f.releases=f.releases+1
  if f.release_refuse then return false,'Release refused'end
  f.claimed=false;return true
 end
 local native={Window={has_focus=function()return f.focus end},
  Gui={resolution=function()f.resolutions=f.resolutions+1;return 200,300 end},
  Keyboard={button_id=function(name)f.engine_ids=f.engine_ids+1;return name=='f12'and 123 or name=='w'and 87 or 20 end,
   button=function()f.engine_reads=f.engine_reads+1;return f.engine_value==nil and 1 or f.engine_value end}}
 f.broker=broker;f.input=F.new(native,broker)
 function f.frame()f.input.frame()end
 function f.active(codes)
  f.raw.keyboard_state,f.raw.keyboard_active,f.raw.valid=2,true,true
  f.raw.keyboard_keys=bitmap(codes);f.raw.keyboard_mask=capture_mask;f.raw.keyboard_generation=f.generation
 end
 return f
end
do
 local f=captured_fixture();local i=f.input
 assert(i.set_mode('camera'));assert(f.acquire_calls[1].argc==4 and f.acquire_calls[1].options.keyboard==true)
 f.active({87,161,163,165});f.frame()
 assert(i.down(87)and i.down(16)and i.down(17)and i.down(18),'Captured physical and generic modifier aliases must work')
 assert(i.down(161)and not i.down(160)and i.down(163)and not i.down(162)and i.down(165)and not i.down(164))
 assert(not i.down(65)and f.engine_reads==0,'Captured up keys must not leak engine-held gameplay keys')
 local p=i.sample();assert(p.valid and p.dx==0 and p.dy==0 and p.x==100 and p.y==225)
 assert(i.sample()==p and i.wheel()==120 and i.wheel()==0 and f.snapshots==1,
  'Down-before-pointer, every key, pointer and wheel share exactly one snapshot')
 assert(i.down(123)and i.down(123)and f.engine_reads==1,'Unmasked F12 may use one cached engine read')
 f.raw.keyboard_keys=bitmap();assert(i.down(87)and f.snapshots==1,'The current frame retains its exact physical snapshot')
 f.frame();assert(not i.down(87));p=i.sample();assert(p.dx==3 and p.dy==-4 and f.snapshots==2)
 local native=f.snapshots;f.focus=false;f.frame();assert(not i.down(87)and not i.down(123)and f.snapshots==native)
 assert(i.release());f.focus=true;f.frame();assert(i.down(87),'Only explicit release permits normal engine fallback again')
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'))
 f.raw.keyboard_state,f.raw.keyboard_active,f.raw.valid=1,false,false
 f.raw.x,f.raw.y,f.raw.width,f.raw.height=nil,nil,nil,nil
 f.raw.buttons,f.raw.dx,f.raw.dy,f.raw.wheel=99,99,99,99;f.raw.keyboard_keys=bitmap({87,17,16})
 f.frame();assert(not i.down(87)and not i.down(17)and not i.down(123)and i.owns())
 local p=i.sample();assert(p and p.pending and p.valid==false and p.dx==0 and p.dy==0 and p.x==0 and p.y==0)
 assert(p.buttons==0 and p.wheel==0 and not p.click and not p.right and f.engine_reads==0 and f.resolutions==0)
 assert(i.sample()==p and f.snapshots==1,'Arming returns stable neutral input and retains the lease')
 f.raw.x,f.raw.y,f.raw.width,f.raw.height=50,25,100,100;f.raw.buttons=0;f.active({87});f.frame()
 p=i.sample();assert(p.valid and not p.pending and p.dx==0 and p.dy==0 and i.down(87),
  'Arming never consumes suppression of the first actual raw camera sample')
 f.frame();assert(i.sample().dx==99 and f.snapshots==3);assert(i.release())
end
do
 local f=captured_fixture(true);local i=f.input
 assert(i.set_mode('camera')and f.acquire_calls[1].argc==3 and f.acquire_calls[1].options==nil)
 f.frame();assert(i.down(87)and f.snapshots==0,'Old brokers retain mouse-only engine keyboard behavior')
 assert(i.sample()and f.snapshots==1)
 assert(i.set_mode('menu')and f.releases==1 and f.acquires==2,'Old brokers preserve release/acquire mode transitions')
 assert(i.release())
end
do
 local f=captured_fixture();local i=f.input
 f.broker.set_mode=function(t,mode)
  assert(t==f.token and(mode=='menu'or mode=='camera'));f.mode_changes=f.mode_changes+1
  if f.mode_refuse then return false,'Mode refused'end
  return true
 end
 assert(i.set_mode('menu'));local token=f.token;f.frame();assert(i.sample())
 f.active({87});assert(i.set_mode('camera')and f.token==token and f.acquires==1 and f.releases==0)
 assert(i.mode()=='camera'and f.mode_changes==1);local p=i.sample();assert(p.dx==0 and i.down(87))
 assert(i.set_mode('camera')and f.mode_changes==1,'An unchanged mode performs no broker transition')
 f.mode_refuse=true;assert(not i.set_mode('menu')and i.pending_restore()and not i.owns())
 f.frame();assert(not i.down(87)and not i.down(123)and i.sample()==nil and f.engine_reads==0)
 assert(f.acquires==1 and f.releases==0,'A refused in-place mode change never silently reacquires a mouse-only lease')
 assert(i.release())
end
local malformed={
 function(f)f.raw.keyboard_keys=string.rep('x',31)end,
 function(f)f.raw.keyboard_keys={}end,
 function(f)f.raw.keyboard_keys=string.rep('x',33)end,
 function(f)f.raw.keyboard_mask=string.rep('x',31)end,
 function(f)f.raw.keyboard_mask={}end,
 function(f)f.raw.keyboard_mask=string.rep('x',33)end,
 function(f)f.raw.keyboard_mask=string.rep('\0',32)end,
 function(f)f.raw.keyboard_mask=bitmap({87})end,
 function(f)f.raw.keyboard_active=false end,
 function(f)f.raw.keyboard_active=1 end,
 function(f)f.raw.valid=false end,
 function(f)f.raw.keyboard_state=1 end,
 function(f)f.raw.keyboard_state=6 end,
 function(f)f.raw.keyboard_state='2'end,
 function(f)f.raw.keyboard_generation=0 end,
 function(f)f.raw.keyboard_generation=-1 end,
 function(f)f.raw.keyboard_generation=1.5 end,
 function(f)f.raw.keyboard_generation=4294967296 end,
 function(f)f.raw.keyboard_generation=0/0 end,
 function(f)f.raw.keyboard_generation=math.huge end,
 function(f)f.raw=42 end,
 function(f)f.snapshot_absent=true end,
 function(f)f.snapshot_error={kind='snapshot-error'}end}
for _,break_sample in ipairs(malformed)do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'));break_sample(f);f.frame()
 assert(not i.down(87)and not i.down(123)and i.sample()==nil and not i.owns())
 local snapshots=f.snapshots
 for _=1,50 do f.frame();assert(not i.down(87)and not i.down(123)and i.sample()==nil)end
 assert(f.engine_reads==0 and f.snapshots==snapshots,'Malformed capture stays blocked until release without fallback or polling')
 assert(i.release());f.frame();assert(i.down(87))
end
for _,state in ipairs({3,4,5})do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('menu'))
 f.raw.keyboard_state,f.raw.keyboard_active,f.raw.valid=state,false,false;f.frame()
 assert(not i.down(87)and not i.down(123)and i.sample()==nil and f.engine_reads==0)
 assert(i.release())
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'));f.frame();assert(i.sample())
 f.generation=8;f.active({87});f.frame();assert(i.sample()==nil and not i.down(87)and not i.down(123))
 f.generation=7;f.active({87});local snapshots=f.snapshots;f.frame()
 assert(i.sample()==nil and f.snapshots==snapshots,'A changed generation is never adopted or silently recovered')
 assert(i.release()and i.set_mode('camera'));f.generation=8;f.active({87});f.frame();assert(i.down(87))
 assert(i.release())
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'));f.owns=false;f.restore_pending=true
 f.frame();assert(not i.down(87)and not i.down(123)and f.engine_reads==0 and f.snapshots==0)
 f.release_refuse=true;assert(not i.release()and i.pending_restore());f.frame()
 assert(not i.down(87)and not i.down(123)and f.engine_reads==0)
 f.release_refuse=false;assert(i.release());f.frame();assert(i.down(87))
end
do
 local f=captured_fixture();f.acquire_cleanup=true;assert(not f.input.set_mode('camera')and f.input.pending_restore())
 f.frame();assert(not f.input.down(87)and not f.input.down(123)and f.engine_reads==0)
 assert(f.input.release())
end
do
 local count=0;for code=0,255 do count=count+math.floor(capture_mask:byte(math.floor(code/8)+1)/2^(code%8))%2 end
 assert(#capture_mask==32 and count==119,'Fixture matches the final broker wire mask')
 for _,code in ipairs({44,58,59,60,61,62,63,64,91,92,123})do
  assert(math.floor(capture_mask:byte(math.floor(code/8)+1)/2^(code%8))%2==0)
 end
end
for _,bad in ipairs({false,'short',string.rep('\0',32),{}})do
 local f=captured_fixture();f.broker.capabilities.keyboard_mask=bad
 assert(not f.input.set_mode('camera')and f.acquires==0,'Keyboard opt-in requires the canonical binary mask before acquire')
end
do
 local f=captured_fixture();f.broker.capabilities.keyboard_mask=nil
 assert(not f.input.set_mode('camera')and f.acquires==0,'A keyboard-capable legacy factory without its mask must fail closed')
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'));f.frame();assert(i.sample())
 local snapshots=f.snapshots;f.broker.capabilities.keyboard_mask=bitmap({87});f.frame()
 assert(i.sample()==nil and not i.down(87)and not i.down(123)and f.snapshots==snapshots and f.engine_reads==0,
  'A changed public mask refuses without polling or falling back')
 assert(i.release())
end
do
 local f=captured_fixture();local i=f.input
 -- Consume the exact published platform mask; do not duplicate a VK whitelist.
 f.broker.capabilities.keyboard_mask=bitmap({87});f.raw.keyboard_mask=f.broker.capabilities.keyboard_mask
 f.raw.keyboard_keys=bitmap({87});assert(i.set_mode('camera'));f.frame()
 assert(i.down(87)and i.sample().valid and f.engine_reads==0);assert(i.release())
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('camera'))
 f.raw.keyboard_generation=4294967295;f.frame();assert(i.sample(),'Positive maximum u32 is exact in Lua 5.1')
 assert(i.release())
end
do
 local f=captured_fixture();local i=f.input;f.acquire_refuse=true
 assert(not i.set_mode('camera')and f.acquires==1)
 f.frame();assert(not i.down(87)and not i.down(123)and f.engine_reads==0,
  'A requested captured lease never silently retries acquisition as mouse-only')
 assert(i.release());f.frame();assert(i.down(87))
end
do
 local f=captured_fixture();local i=f.input;assert(i.set_mode('menu'));local token=f.token
 assert(i.set_mode('camera')and f.acquires==2 and f.releases==1 and token~=f.token,
  'A broker without optional set_mode retains the acknowledged release/acquire route')
 f.raw.buttons=1;f.frame();local p=i.sample();assert(not p.click and p.dx==0)
 f.raw.buttons=0;f.frame();assert(i.sample())
 f.raw.buttons=1;f.frame();assert(i.sample().click,'Captured keyboard never weakens opening-click suppression')
 assert(i.release())
end
for _,kind in ipairs({'nil','throw'})do
 local f=captured_fixture();local i=f.input;local problem={kind='mode-change'}
 f.broker.set_mode=function()if kind=='throw'then error(problem)end;return nil,'Mode unconfirmed'end
 assert(i.set_mode('menu'));local ok,why=i.set_mode('camera')
 assert(not ok and i.pending_restore()and f.acquires==1 and f.releases==0)
 if kind=='throw'then assert(why==problem)end
 f.frame();assert(not i.down(87)and not i.down(123)and f.engine_reads==0);assert(i.release())
end
for _,kind in ipairs({'nil','throw'})do
 local f=captured_fixture();local i=f.input;local problem={kind='release-'..kind};local attempts=0
 assert(i.set_mode('camera'));local token=f.token;f.frame();assert(i.sample())
 f.broker.release=function(t)
  assert(t==token);attempts=attempts+1
  if attempts==1 then
   if kind=='throw'then error(problem)end
   return nil,problem
  end
  f.claimed=false;return true
 end
 local ok,why=i.release()
 assert(not ok and why==problem and i.pending_restore()and not i.owns(),
  'An unconfirmed/throwing release preserves the token and original synchronous reason')
 local snapshots=f.snapshots
 for _=1,50 do
  f.frame();assert(not i.down(87)and not i.down(123)and i.sample()==nil)
 end
 assert(attempts==1 and f.snapshots==snapshots and f.engine_reads==0,
  'Pending release has no automatic release/snapshot retry or engine fallback')
 assert(i.release()and attempts==2 and not i.pending_restore(),'Only acknowledged true retires the same cleanup token')
 f.frame();assert(i.down(87),'Gameplay keyboard fallback resumes after acknowledged release')
end
print('Steam input: shared pointer/physical-key snapshot, arming retention, exact capture guards, aliases, old brokers, mode reuse and cleanup ownership passed')

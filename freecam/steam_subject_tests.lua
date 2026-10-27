-- Pure controller contracts in actual Lua 5.1. No game adapter or engine ABI.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local Subject=dofile('freecam/steam_subject.lua')
local function node(x)return{p={x,2,3},q={0,0,0,1},s={1,1,1}}end
local function copy(value)
 if type(value)~='table'then return value end
 local out={};for key,item in pairs(value)do out[key]=copy(item)end;return out
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not same(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end;return true
end
local function fixture()
 local f={native=0,discoveries=0,validations=0,snapshots=0,node_writes=0,mode_writes=0,commits=0,
  frozen=true,freeze_reads=0,decodes=0,validation='valid',epoch=1,written={}}
 local rig={resource='4d1c334d294dfa97',node_count=107,nodes={}}
 for i=1,107 do rig.nodes[i]={parent=i-1}end
 local a={identity='subject-a',resource=rig.resource,node_count=107,label='Helldiver A',epoch=1,mode='position_and_rotation',nodes={}}
 local b={identity='subject-b',resource=rig.resource,node_count=107,label='Helldiver B',epoch=1,mode='position_and_rotation',nodes={}}
 for i=1,107 do a.nodes[i]=node(i/10);b.nodes[i]=node(10+i/10)end
 f.a,f.b,f.original,f.original_a=a,b,copy(b),copy(a)
 local bank={version=1,rig=rig,catalog={{id='upper',label='Upper',full_body=false},
  {id='full',label='Full',full_body=true},{id='other',label='Other',full_body=true}}}
 bank.decode=function(id)
  f.decodes=f.decodes+1
  if f.decode_error then error(f.decode_error)end
  if f.decode_missing then return nil,'Pose unavailable'end
  local pose={full_body=id~='upper',nodes={}}
  for i=8,92 do pose.nodes[i]=node((id=='other'and 200 or 100)+i/10)end
  if f.decode_invalid then pose.nodes[40].q[4]=0/0 end
  return pose
 end
 local adapter={version=1}
 local function count()f.native=f.native+1 end
 local function valid(target)
  return f.validation=='valid'and target.epoch==f.epoch
 end
 adapter.discover=function(resource,limit,authored)
  count();f.discoveries=f.discoveries+1
  assert(resource==rig.resource and limit==4 and authored==rig)
  if f.discover_error then error(f.discover_error)end
  return f.candidates or{a,b}
 end
 adapter.valid=function(target,authored)
  count();f.validations=f.validations+1;assert(authored==rig)
  if f.validation=='unknown'then return nil,'Lifetime unavailable'end
  return valid(target)
 end
 adapter.snapshot=function(target,authored)
  count();f.snapshots=f.snapshots+1;assert(valid(target)and authored==rig)
  if f.snapshot_error then error(f.snapshot_error)end
  local result={identity=target.identity,resource=target.resource,node_count=target.node_count,mode=target.mode,nodes=target.nodes}
  if f.snapshot_invalid then result=copy(result);result.nodes[30].s[2]=nil end
  return result
 end
 adapter.set_node=function(target,authored,index,expected,value,mode)
  count();f.node_writes=f.node_writes+1
  assert(f.snapshots>0 and authored==rig and index>=8 and index<=92,'Capture all body state before the first write')
  if f.before_node then f.before_node(target,index);f.before_node=nil end
  if not valid(target)or target.mode~=mode or not same(target.nodes[index],expected)then return false,'Fresh node guard refused'end
  f.written[#f.written+1]=index
  if f.fail_node==index then
   if f.effect=='all'then target.nodes[index]=copy(value)
   elseif f.effect=='partial'then target.nodes[index].p[1]=value.p[1]end
   if f.throw then error(f.error_object or'Node setter threw')end
   return false,'Node setter refused'
  end
  target.nodes[index]=copy(value);return true
 end
 adapter.set_mode=function(target,authored,expected,value)
  count();f.mode_writes=f.mode_writes+1;assert(f.snapshots>0 and authored==rig)
  if not valid(target)or target.mode~=expected then return false,'Fresh mode guard refused'end
  if f.fail_mode then
   if f.effect=='all'then target.mode=value end
   if f.throw then error(f.error_object or'Mode setter threw')end
   return false,'Mode setter refused'
  end
  target.mode=value;return true
 end
 adapter.commit=function(target,authored)
  count();f.commits=f.commits+1;assert(valid(target)and authored==rig)
  if f.commit_error then error(f.commit_error)end
  if f.commit_refuse then return false,'Scene refresh refused'end
  return true
 end
 f.controller=Subject.new(adapter,bank,function()f.freeze_reads=f.freeze_reads+1;return f.frozen end)
 f.adapter,f.bank=adapter,bank
 function f.select()
  assert(f.controller.refresh());assert(f.controller.status().selected==nil,'Discovery never selects even a sole avatar')
  assert(f.controller.select('subject-b'))
 end
 function f.original_body()
  assert(same(b,f.original),'Selected subject must return to its complete original state')
  assert(same(a,f.original_a),'Other photographic candidates must remain untouched')
 end
 function f.anchors()
  for i=1,107 do if i<8 or i>92 then assert(same(b.nodes[i],f.original.nodes[i]),'Scene anchors must not be written')end end
 end
 return f
end
do
 local f=fixture();local c=f.controller;local status,choices=c.status(),c.choices()
 for _=1,1000 do assert(c.status()==status and c.choices()==choices)end
 assert(f.native==0 and f.freeze_reads==0 and f.decodes==0,'Construction and idle status have zero native/clock/decoder work')
 assert(status.capability=='explicit_photographic_subject'and status.player_authority==false)
 assert(not c.select('subject-b')and not c.apply('full'))
 f.select();assert(#c.choices()==2 and c.choices()[2].id=='subject-b'and c.choices()[2].nodes==nil)
 f.frozen=false;assert(not c.apply('full')and f.snapshots==0 and f.node_writes==0)
 f.frozen=true;assert(c.apply('full')and c.status().state=='posed'and c.status().pose=='full')
 assert(f.snapshots==1 and f.decodes==1 and f.node_writes==85 and f.mode_writes==1 and f.commits==1)
 f.anchors();assert(not c.refresh()and not c.select('subject-a'),'A held lease cannot silently switch targets')
 local writes,mode,commits=f.node_writes,f.mode_writes,f.commits
 assert(c.apply('full')and f.decodes==1 and f.node_writes==writes and f.mode_writes==mode and f.commits==commits,
  'A repeated explicit request validates once without decoding or rewriting an unchanged pose')
 assert(c.apply('upper')and f.decodes==2 and same(f.b.nodes[8],f.original.nodes[8]),
  'Non-fullbody returns root8 to the original baseline after a full-body pose')
 assert(c.apply('other')and f.decodes==3);f.anchors()
 assert(c.reset()and c.status().pose==nil and c.status().selected=='subject-b');f.original_body()
 local native=f.native
 for _=1,100 do assert(c.reset()and c.resume()and c.status().pose==nil)end
 assert(f.native==native,'Reset clears remembered pose and remains idle without a lease')
 assert(c.apply('full')and c.close()and c.status().selected==nil);f.original_body()
end
for _,throw in ipairs({false,true})do for _,effect in ipairs({'none','all'})do
 local f=fixture();f.select();f.fail_mode=true;f.throw=throw;f.effect=effect;f.error_object={kind='mode-error'}
 assert(not f.controller.apply('full')and f.controller.status().pending and f.node_writes==0)
 if throw then assert(f.controller.status().detail==f.error_object,'Keep the original error object')end
 assert(not f.controller.close(),'Exit makes at most one separately guarded mode-cleanup attempt')
 local native=f.native
 for _=1,100 do assert(not f.controller.close()and not f.controller.reset()and not f.controller.apply('full'))end
 assert(f.native==native,'Blocked cleanup has no automatic native retries')
 f.fail_mode=false;assert(f.controller.recover());f.original_body()
 assert(f.node_writes==0 and f.mode_writes==(effect=='all'and 2 or 1))
end end
for _,throw in ipairs({false,true})do for _,effect in ipairs({'none','all'})do
 local f=fixture();f.select();f.fail_node=13;f.throw=throw;f.effect=effect
 assert(not f.controller.apply('full')and f.controller.status().pending and f.node_writes==6)
 local written=#f.written;assert(f.written[written]==13 and f.b.mode=='ignore');f.anchors()
 f.fail_node=nil;assert(f.controller.recover());f.original_body()
 assert(f.node_writes==6+(effect=='all'and 6 or 5),'Restore only the actually changed/acknowledged subset')
end end
do
 local f=fixture();f.select();f.fail_node=13;f.effect='partial'
 -- A changed X alone is intermediate only if another component also differs.
 local decode=f.bank.decode;f.bank.decode=function(id)local p=decode(id);p.nodes[13].p[2]=22;return p end
 assert(not f.controller.apply('full'));local writes=f.node_writes
 assert(not f.controller.recover()and f.node_writes==writes,'Unknown partial data cannot be treated as foreign or overwritten')
 f.validation='unknown';assert(not f.controller.recover()and f.node_writes==writes)
 f.validation='retired';assert(f.controller.invalidate()and f.controller.status().state=='retired')
 assert(f.node_writes==writes and f.controller.status().restored==false,'Retirement drops the lease without claiming restoration')
end
for _,effect in ipairs({'none','all'})do
 local f=fixture();f.select();assert(f.controller.apply('full'))
 f.fail_node=8;f.effect=effect;assert(not f.controller.close()and f.controller.status().pending)
 local writes=f.node_writes;f.fail_node=nil;assert(f.controller.recover());f.original_body()
 assert(f.node_writes==writes+(effect=='all'and 84 or 85),'Explicit cleanup retry resolves failed restoration before continuing')
 assert(f.controller.status().selected==nil)
end
for _,fault in ipairs({'commit_refuse','commit_error'})do
 local f=fixture();f.select();f[fault]=fault=='commit_error'and{}or true
 assert(not f.controller.apply('full')and f.controller.status().pending)
 assert(not f.controller.close())
 local native=f.native;for _=1,100 do assert(not f.controller.close())end;assert(f.native==native)
 f[fault]=nil;assert(f.controller.recover());f.original_body()
end
do
 local f=fixture();f.select();assert(f.controller.apply('full'))
 f.b.nodes[20]=node(777);assert(f.controller.reset()and f.b.nodes[20].p[1]==777)
 assert(f.controller.status().state=='foreign'and not f.controller.status().restored and f.b.mode==f.original.mode)
 for i=8,92 do if i~=20 then assert(same(f.b.nodes[i],f.original.nodes[i]))end end
 f.anchors()
end
do
 local f=fixture();f.select();assert(f.controller.apply('full'));f.b.mode='foreign_mode'
 local modes=f.mode_writes
 assert(not f.controller.apply('upper')and f.controller.status().pending)
 assert(f.controller.recover()and f.b.mode=='foreign_mode'and f.mode_writes==modes)
 assert(f.controller.status().state=='foreign'and not f.controller.status().restored)
 for i=8,92 do assert(same(f.b.nodes[i],f.original.nodes[i]))end
end
do
 local f=fixture();f.select();f.before_node=function(target,index)target.nodes[index]=node(888)end
 assert(not f.controller.apply('full')and f.controller.status().pending)
 local writes=f.node_writes
 assert(not f.controller.recover()and f.node_writes==writes,'A refused compare-write with ambiguous state retains unknown cleanup')
 f.epoch=2;assert(f.controller.invalidate()and f.controller.status().state=='retired')
end
for _,fault in ipairs({'snapshot_error','snapshot_invalid','decode_error','decode_missing','decode_invalid'})do
 local f=fixture();f.select();f[fault]=true
 assert(not f.controller.apply('full')and not f.controller.status().pending and f.node_writes==0 and f.mode_writes==0,
  'Invalid baseline or decoded frame must fail before any mutation')
 f[fault]=nil;assert(f.controller.apply('upper')and f.controller.resume());f.original_body()
end
do
 local f=fixture();f.candidates={f.a};assert(f.controller.refresh()and f.controller.status().selected==nil)
 assert(not f.controller.apply('full')and f.node_writes==0,'Even one discovered avatar requires explicit selection')
 f.candidates={f.a,f.b,f.a,f.b,f.a};assert(not f.controller.refresh())
 local unsupported=Subject.new({},f.bank,function()return true end)
 for _=1,100 do assert(not unsupported.refresh()and not unsupported.apply('full')and unsupported.close())end
 assert(not unsupported.status().available and unsupported.status().state=='unsupported')
end
do
 local f=fixture();f.select();local canonical=0
 local function float32(value)
  if value==0 then return value end
  local sign=value<0 and-1 or 1;local m,e=math.frexp(math.abs(value))
  return sign*math.ldexp(math.floor(m*16777216+.5)/16777216,e)
 end
 f.adapter.canonical_node=function(target,rig,value)
  canonical=canonical+1
  assert(target==f.b and rig==f.bank.rig and f.snapshots==0 and f.node_writes==0 and f.mode_writes==0,
   'Canonicalize all authored targets before baseline capture and before any setter')
  local result=copy(value)
  for _,field in ipairs({'p','q','s'})do for i,n in ipairs(result[field])do result[field][i]=float32(n)end end
  return result
 end
 assert(f.controller.apply('upper')and canonical==84)
 assert(f.b.nodes[9].p[1]==float32(100.9)and f.b.nodes[9].p[1]~=100.9,
  'Store the exact canonical target rather than a guessed tolerance around authored doubles')
 assert(same(f.b.nodes[8],f.original.nodes[8]),'Never canonicalize the preserved body root')
 assert(f.controller.apply('upper')and canonical==84 and f.controller.reset());f.original_body()
end
for _,fault in ipairs({'refuse','throw','non_numeric'})do
 local f=fixture();f.select();local calls=0;local error_object={kind='canonical-error'}
 f.adapter.canonical_node=function(_,_,value)
  calls=calls+1
  if fault=='throw'then error(error_object)end
  if fault=='refuse'then return nil,'Canonical target refused'end
  local result=copy(value);result.q[3]=math.huge;return result
 end
 assert(not f.controller.apply('full')and calls==1 and f.snapshots==0 and f.node_writes==0 and f.mode_writes==0)
 assert(not f.controller.status().pending,'Bad canonical targets must fail before acquiring mutation ownership')
 if fault=='throw'then assert(f.controller.status().detail==error_object)end
 assert(f.controller.close());f.original_body()
end
do
 local f=fixture();f.select();f.fail_node=13;f.effect='partial'
 local decode=f.bank.decode;f.bank.decode=function(id)local p=decode(id);p.nodes[13].p[2]=22;return p end
 assert(not f.controller.apply('full'));local intermediate=copy(f.b.nodes[13]);local calls=0
 local problem={kind='adapter-recovery-error'}
 f.adapter.resolve_node=function(target,rig,index,before,value,current,expected_mode)
  calls=calls+1
  assert(target==f.b and rig==f.bank.rig and index==13 and expected_mode==target.mode)
  assert(expected_mode==(calls==1 and'ignore'or f.original.mode),'Proof uses the fresh acknowledged own mode')
  assert(same(current,intermediate)and same(target.nodes[13],intermediate))
  assert(same(before,f.original.nodes[13])and value.p[1]==101.3 and value.p[2]==22)
  if calls==1 then return false,'Component retirement refused'end
  if calls==2 then return nil,'Component ownership unknown'end
  if calls==3 then error(problem)end
  -- A qualified native adapter must prove exact ownership from its private
  -- per-component ledger, without changing the real snapshot or native state.
  -- Mutating the numeric arguments cannot mutate controller-owned records.
  before.p[1],value.p[1],current.p[1]=-1,-2,-3
  return true
 end
 local snapshots,writes=f.snapshots,f.node_writes
 assert(not f.controller.recover()and f.snapshots==snapshots+1 and f.node_writes==writes)
 assert(not f.controller.recover()and f.snapshots==snapshots+2 and f.node_writes==writes)
 assert(not f.controller.recover()and f.controller.status().detail==problem and f.node_writes==writes)
 local native=f.native
 for _=1,100 do assert(not f.controller.close()and not f.controller.reset())end
 assert(calls==3 and f.native==native,'Only explicit recovery may enter the read-only component proof')
 f.fail_node=nil;assert(f.controller.recover()and calls==4);f.original_body()
 assert(f.node_writes==writes+6,'Controller restores the actual mixed node only after exact component ownership proof')
 local finished_calls=calls;assert(f.controller.recover()and calls==finished_calls)
end
for _,effect in ipairs({'none','all'})do
 local f=fixture();f.select();f.fail_node=13;f.effect=effect
 f.adapter.resolve_node=function()error('Exact before/target must not need a component proof')end
 assert(not f.controller.apply('full'));f.fail_node=nil;assert(f.controller.recover());f.original_body()
 assert(f.controller.apply('full')and f.controller.reset(),'Acknowledged nodes never request partial ownership proof')
end
local function partial_body()
 local f=fixture();f.select();f.fail_node=13;f.effect='partial'
 local decode=f.bank.decode;f.bank.decode=function(id)local p=decode(id);p.nodes[13].p[2]=22;return p end
 assert(not f.controller.apply('full')and f.b.mode=='ignore');f.fail_node=nil
 return f
end
do
 local f=partial_body();local intermediate=copy(f.b.nodes[13]);local writes=f.node_writes
 assert(not f.controller.close()and f.controller.status().pending)
 assert(f.b.mode==f.original.mode and f.node_writes==writes and same(f.b.nodes[13],intermediate),
  'Exit restores independently owned mode while leaving uncertain body state untouched and pending')
 assert(f.mode_writes==2 and f.commits==1)
 local native=f.native
 for _=1,100 do assert(not f.controller.close()and not f.controller.reset())end
 assert(f.native==native,'Unknown body has no automatic cleanup reads, writes or mode refresh retries')
 f.adapter.resolve_node=function(_,_,index,_,_,current,mode)
  assert(index==13 and same(current,intermediate)and mode==f.original.mode);return true
 end
 assert(f.controller.recover());f.original_body()
 assert(f.node_writes==writes+6 and f.mode_writes==2,'Later exact component proof restores body without reacquiring ignore')
end
do
 local f=partial_body();f.b.mode='foreign_mode';local modes,writes=f.mode_writes,f.node_writes
 assert(not f.controller.close()and f.b.mode=='foreign_mode'and f.mode_writes==modes and f.node_writes==writes)
 f.adapter.resolve_node=function()return false,'Mode is foreign'end
 assert(not f.controller.recover()and f.b.mode=='foreign_mode'and f.node_writes==writes,
  'Unknown body never grants ownership of a foreign animation mode')
 f.validation='retired';assert(f.controller.invalidate()and f.controller.status().restored==false)
end
for _,throw in ipairs({false,true})do for _,effect in ipairs({'none','all'})do
 local f=partial_body();f.fail_mode=true;f.throw=throw;f.effect=effect
 local writes=f.node_writes;assert(not f.controller.close()and f.controller.status().pending)
 local native=f.native
 for _=1,100 do assert(not f.controller.close()and not f.controller.reset())end
 assert(f.native==native,'A failed independent mode cleanup stays owned without automatic retries')
 f.fail_mode=false
 assert(not f.controller.recover()and f.b.mode==f.original.mode and f.node_writes==writes)
 f.adapter.resolve_node=function()return true end
 assert(f.controller.recover());f.original_body()
end end
do
 local f=partial_body();f.commit_refuse=true;local writes=f.node_writes
 assert(not f.controller.close()and f.b.mode==f.original.mode and f.commits==1)
 local native=f.native;for _=1,100 do assert(not f.controller.close())end;assert(f.native==native)
 f.commit_refuse=false
 assert(not f.controller.recover()and f.commits==2 and f.node_writes==writes,
  'Explicit recovery can finish independent mode evaluation while body proof remains pending')
 f.adapter.resolve_node=function()return true end;assert(f.controller.recover());f.original_body()
end
do
 local f=partial_body();f.snapshot_invalid=true;assert(not f.controller.close())
 local native=f.native;for _=1,100 do assert(not f.controller.close())end
 assert(f.native==native,'Unavailable snapshot on the first exit does not cause automatic mode ownership scans')
 f.snapshot_invalid=false;assert(not f.controller.recover()and f.b.mode==f.original.mode)
 f.adapter.resolve_node=function()return true end;assert(f.controller.recover());f.original_body()
end
local function matrix_node(value)
 local result=copy(value)
 result.pose={1,0,0,0,1,0,0,0,1,value.p[1],value.p[2],value.p[3]}
 return result
end
local function same_pose(a,b)
 if not a.pose or not b.pose then return false end
 for i=1,12 do if a.pose[i]~=b.pose[i]then return false end end
 return true
end
local function matrix_fixture()
 local f=fixture();f.canonical_outputs={};f.baseline_aliases={}
 for i=8,92 do
  f.b.nodes[i]=matrix_node(f.b.nodes[i]);f.baseline_aliases[i]=f.b.nodes[i]
 end
 f.original=copy(f.b)
 f.adapter.canonical_node=function(target,rig,value)
  assert(target==f.b and rig==f.bank.rig)
  local result=matrix_node(value);f.canonical_outputs[#f.canonical_outputs+1]=result;return result
 end
 f.adapter.set_node=function(target,rig,index,expected,value,mode)
  f.native=f.native+1;f.node_writes=f.node_writes+1
  assert(f.snapshots>0 and rig==f.bank.rig and index>=8 and index<=92)
  if target.epoch~=f.epoch or target.mode~=mode or not same_pose(target.nodes[index],expected)then return false,'Fresh matrix guard refused'end
  f.written[#f.written+1]=index
  if f.fail_node==index then
   if f.effect=='all'then target.nodes[index]=copy(value)
   elseif f.effect=='partial'then target.nodes[index].pose[10]=value.pose[10];target.nodes[index].p[1]=value.p[1]end
   if f.throw then error('Matrix setter threw')end
   return false,'Matrix setter refused'
  end
  target.nodes[index]=copy(value)
  if f.decompose_differently then target.nodes[index].q[1]=value.q[1]+.000001 end
  return true
 end
 function f.matrix_original()
  assert(f.b.mode==f.original.mode)
  for i=8,92 do assert(same_pose(f.b.nodes[i],f.original.nodes[i]),'Restore the exact original 12 matrix scalars')end
  f.anchors();assert(same(f.a,f.original_a))
 end
 return f
end
do
 local f=matrix_fixture();f.select();f.decompose_differently=true
 assert(f.controller.apply('full')and f.node_writes==85)
 assert(f.b.nodes[48].q[1]~=f.canonical_outputs[41].q[1],
  'A valid quaternion getter may decompose an identical stored matrix differently')
 local writes=f.node_writes
 assert(f.controller.apply('full')and f.node_writes==writes,
  'Exact stored matrices, rather than decomposed PQS, acknowledge held ownership')
 -- Both baseline and canonical results were borrowed tables at the boundary.
 -- Altering those old tables must not change private lease originals/targets.
 for i=8,92 do f.baseline_aliases[i].pose[10]=-1000 end
 for _,value in ipairs(f.canonical_outputs)do value.pose[10]=-2000 end
 assert(f.controller.apply('full')and f.node_writes==writes)
 assert(f.controller.reset());f.matrix_original()
 local native,decoded=f.native,f.decodes
 for _=1,100 do assert(f.controller.reset()and f.controller.close()and not f.controller.status().pending)end
 assert(f.native==native and f.decodes==decoded,'Retired matrix leases have zero idle work')
end
do
 local f=matrix_fixture();f.select()
 assert(f.controller.apply('upper')and #f.canonical_outputs==84 and f.node_writes==84)
 assert(same(f.b.nodes[8],f.original.nodes[8]),'Upper-body root8 retains its exact matrix without canonicalization')
 assert(f.controller.apply('full')and f.controller.apply('upper'))
 assert(same_pose(f.b.nodes[8],f.original.nodes[8]))
 assert(f.controller.reset());f.matrix_original()
end
for _,fault in ipairs({'short','long','hole','named','nonfinite','false','metatable'})do
 local f=matrix_fixture();f.select();local canonical=f.adapter.canonical_node
 f.adapter.canonical_node=function(...)
  local value=canonical(...)
  if fault=='short'then value.pose[12]=nil
  elseif fault=='long'then value.pose[13]=0
  elseif fault=='hole'then value.pose[6]=nil;value.pose[13]=0
  elseif fault=='named'then value.pose.extra=0
  elseif fault=='nonfinite'then value.pose[5]=math.huge
  elseif fault=='false'then value.pose=false
  else setmetatable(value.pose,{})end
  return value
 end
 assert(not f.controller.apply('full')and f.mode_writes==0 and f.node_writes==0 and f.snapshots==0,
  'Malformed raw matrices fail before baseline capture or native writes')
 assert(not f.controller.status().pending and f.controller.close());f.matrix_original()
end
for _,field in ipairs({'p','q','s'})do
 local f=matrix_fixture();f.select();f.b.nodes[92][field][1]=0/0
 assert(not f.controller.apply('full')and f.mode_writes==0 and f.node_writes==0,
  'A matrix never bypasses mandatory finite PQS validation')
end
for _,fault in ipairs({'late_target','late_snapshot','all_pqs_target','all_pqs_snapshot'})do
 local f=matrix_fixture();f.select()
 if fault=='late_target'or fault=='all_pqs_target'then
  local canonical=f.adapter.canonical_node;local index=7
  f.adapter.canonical_node=function(...)
   index=index+1;local value=canonical(...)
   if fault=='all_pqs_target'or index==92 then value.pose=nil end
   return value
  end
 else
  for i=8,92 do if fault=='all_pqs_snapshot'or i==92 then f.b.nodes[i].pose=nil end end
 end
 assert(not f.controller.apply('full')and f.mode_writes==0 and f.node_writes==0 and f.commits==0,
  'Any late-node or whole-frame representation mismatch refuses before the first mode/node write')
 assert(not f.controller.status().pending)
end
do
 local f=matrix_fixture();f.select();assert(f.controller.apply('full'))
 local changed=copy(f.b.nodes[20]);changed.pose[1]=2;f.b.nodes[20]=changed
 local writes=f.node_writes;assert(f.controller.reset()and f.node_writes==writes+84)
 assert(same(f.b.nodes[20],changed)and f.controller.status().state=='foreign'and not f.controller.status().restored,
  'Different raw matrices remain foreign even when every PQS scalar is equal')
 for i=8,92 do if i~=20 then assert(same_pose(f.b.nodes[i],f.original.nodes[i]))end end
 assert(f.b.mode==f.original.mode)
end
for _,throw in ipairs({false,true})do for _,effect in ipairs({'none','all'})do
 local f=matrix_fixture();f.select();f.fail_node=13;f.effect=effect;f.throw=throw
 f.adapter.resolve_node=function()error('Exact whole-matrix before/target needs no component proof')end
 assert(not f.controller.apply('full')and f.controller.status().pending)
 f.fail_node=nil;assert(f.controller.recover());f.matrix_original()
 assert(f.node_writes==6+(effect=='all'and 6 or 5))
end end
do
 local f=matrix_fixture();f.select();f.fail_node=13;f.effect='partial'
 local decode=f.bank.decode;f.bank.decode=function(id)local p=decode(id);p.nodes[13].p[2]=22;return p end
 assert(not f.controller.apply('full'));local partial=copy(f.b.nodes[13]);local writes=f.node_writes
 assert(not f.controller.close()and f.node_writes==writes and f.b.mode==f.original.mode)
 local native=f.native;for _=1,100 do assert(not f.controller.close()and not f.controller.reset())end
 assert(f.native==native and same(f.b.nodes[13],partial),'Unknown matrix mixtures stay pending without idle writes')
 local calls=0
 f.adapter.resolve_node=function(_,_,index,before,target,current,mode)
  calls=calls+1;assert(index==13 and mode==f.original.mode and same(current,partial))
  assert(same_pose(before,f.original.nodes[13])and target.pose[11]==22)
  before.pose[10],target.pose[10],current.pose[10]=-1,-2,-3
  return true
 end
 f.fail_node=nil;assert(f.controller.recover()and calls==1);f.matrix_original()
end
do
 local f=matrix_fixture();f.select();assert(f.controller.apply('full'))
 local snapshot=f.adapter.snapshot
 f.adapter.snapshot=function(...)
  local value=copy(snapshot(...));for i=8,92 do value.nodes[i].pose=nil end;return value
 end
 local writes=f.node_writes
 assert(not f.controller.apply('upper')and f.controller.status().pending)
 assert(not f.controller.close()and f.node_writes==writes and f.b.mode==f.original.mode,
  'Representation loss retains the body lease while independently restoring known-owned mode')
 local native=f.native;for _=1,100 do assert(not f.controller.close()and not f.controller.reset())end
 assert(f.native==native)
 f.adapter.resolve_node=function()error('Mixed representations cannot reach a component proof')end
 assert(not f.controller.recover()and f.node_writes==writes)
 f.adapter.snapshot=snapshot;assert(f.controller.recover());f.matrix_original()
end
do
 local f=fixture();local reads=0
 f.adapter.tracking_frame=function(target)reads=reads+1;return{identity=target.identity}end
 assert(f.controller.refresh());assert(f.controller.select_nearest({0,0,0}))
 assert(f.controller.tracking_frame()==nil and reads==0,'Nearest suggestion is not a tracking selection')
 assert(f.controller.select('subject-b'));assert(f.controller.tracking_frame().identity=='subject-b')
 f.adapter.camera_target=function()return f.a end
 assert(f.controller.select_camera({}));assert(f.controller.tracking_frame().identity=='subject-a')
 assert(f.controller.close());assert(f.controller.tracking_frame()==nil)
end
do
 local f=fixture();f.select();f.frozen=false
 assert(not f.controller.hold_bone_transfer()and f.mode_writes==0)
 f.frozen=true;assert(f.controller.hold_bone_transfer()and f.b.mode=='ignore')
 assert(f.node_writes==0 and f.controller.status().pose=='freeze-bone-trial')
 assert(not f.controller.hold_bone_transfer()and f.mode_writes==1)
 assert(f.controller.resume()and f.node_writes==0 and f.mode_writes==2);f.original_body()
 assert(f.controller.hold_bone_transfer());f.b.mode='rotation'
 local writes=f.mode_writes;assert(f.controller.close()and f.b.mode=='rotation'and f.mode_writes==writes,'Foreign mode is never overwritten by trial cleanup')
end
for _,throw in ipairs({false,true})do
 local f=fixture();f.select();f.fail_mode=true;f.effect='all';f.throw=throw
 assert(not f.controller.hold_bone_transfer()and f.controller.status().pending and f.b.mode=='ignore')
 f.fail_mode=nil;assert(f.controller.recover());f.original_body();assert(f.node_writes==0)
end
print('Steam selected subject: explicit selection, zero idle work, exact PQS/matrix12 ownership, anchors, foreign/partial guards and recovery passed')

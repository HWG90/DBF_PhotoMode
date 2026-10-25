-- Actual Lua 5.1 only; no engine calls, native handles or runtime integration.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'))
local file=assert(io.open('freecam/assets/steam_subject_poses.lua','rb'));local source=file:read('*a');file:close()
local original=dofile('freecam/assets/subject_pose_frames.lua')
local function load_bank(text)
 local conversions=0
 local env={assert=assert,type=type,ipairs=ipairs,math={abs=math.abs},
  tonumber=function(...)conversions=conversions+1;return tonumber(...)end}
 local chunk=assert(loadstring(text or source,'lazy subject pose bank'));setfenv(chunk,env)
 local bank=chunk();assert(conversions==0,'Loading must never parse or materialize pose scalars')
 return bank,function()return conversions end
end
local function expect(value,why)assert(value,why)end
local bank,conversions=load_bank()
expect(bank.version==1 and bank.poses==nil and #bank.catalog==213,'Lazy API preserves all catalog entries without eager pose objects')
local function same(a,b)
 if type(a)~='table'then return a==b end
 if type(b)~='table'then return false end
 for key,value in pairs(a)do if not same(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
expect(same(bank.rig,original.rig),'All 107 rig entries and bone/resource metadata must match')
expect(same(bank.catalog,original.catalog),'All 213 catalog entries, IDs, labels and order must match')
local scalar_checks=0
for _,entry in ipairs(original.catalog)do
 local reference=original.poses[entry.id];local decoded=assert(bank.decode(entry.id))
 expect(type(decoded.full_body)=='boolean'and decoded.full_body==reference.full_body,'Preserve full_body: '..entry.id)
 local nodes=0;local identities={}
 for node,pose in pairs(decoded.nodes)do
  nodes=nodes+1;expect(type(node)=='number'and node%1==0 and node>=8 and node<=92,'Only bounded body nodes may be materialized')
  expect(not identities[pose],'Every decoded bone must be independent');identities[pose]=true
  for _,field in ipairs({'p','q','s'})do
   local count=field=='q'and 4 or 3
   expect(#pose[field]==count and not identities[pose[field]],'Numeric rows must have independent exact shapes');identities[pose[field]]=true
   for i=1,count do
    local value,wanted=pose[field][i],reference.nodes[node][field][i]
    expect(type(value)=='number'and value==wanted,'Exact parsed-double parity: '..entry.id..' node '..node..' '..field..i)
    if value==0 then expect(1/value==1/wanted,'Preserve signed zero')end
    scalar_checks=scalar_checks+1
   end
  end
 end
 expect(nodes==85,'Every pose must decode exactly 85 body nodes')
end
expect(scalar_checks==181050,'Every authored body scalar must be compared')
local first=bank.catalog[1].id;local a,b=assert(bank.decode(first)),assert(bank.decode(first))
expect(a~=b and a.nodes~=b.nodes and a.nodes[8]~=b.nodes[8]and a.nodes[8].p~=b.nodes[8].p,'Decodes must be fresh')
local baseline=b.nodes[8].p[1];a.nodes[8].p[1]=12345
expect(b.nodes[8].p[1]==baseline and bank.decode(first).nodes[8].p[1]==baseline,'Caller mutation must never poison the bank or another selection')
local before=conversions();bank.decode(first);expect(conversions()-before==935,'Only one selected pose performs 85 index and 850 scalar conversions')
for _,id in ipairs({'missing','',string.rep('x',65),0,false,{}})do
 local value,why=bank.decode(id);expect(value==nil and type(why)=='string','Unknown/malformed identity is a clean refusal')
end
expect(bank.decode(nil)==nil,'Nil identity refuses')
local function private(fn,name)
 for i=1,30 do local key,value=debug.getupvalue(fn,i);if not key then break end;if key==name then return value,i end end
 error('Missing private fixture target '..name)
end
local rows=private(bank.decode,'rows');local indices=private(bank.decode,'indices');local lookup=private(bank.decode,'lookup')
local index=lookup[first];local encoded=indices[index];local row_id=tonumber(encoded:sub(1,4),16);local saved=rows[row_id]
local invalid_rows={false,{},'',string.rep('1',321),'0,0,0,0,0,0,1,1,1',
 '0,0,0,0,0,0,1,1,1,1,1','0,,0,0,0,0,0,1,1,1,1',',0,0,0,0,0,0,1,1,1,1',
 '0,0,0,0,0,0,1,1,1,1,',' 0,0,0,0,0,0,1,1,1,1','0x0,0,0,0,0,0,1,1,1,1',
 '1e999,0,0,0,0,0,1,1,1,1','nan,0,0,0,0,0,1,1,1,1','0,0,0,0,0,0,2,1,1,1',
 '0,0,0,0,0,0,1,1.1,1,1','100000000,0,0,0,0,0,1,1,1,1',string.rep('0',33)..',0,0,0,0,0,1,1,1,1'}
for _,bad in ipairs(invalid_rows)do
 rows[row_id]=bad;local result,why=bank.decode(first)
 expect(result==nil and type(why)=='string','Corrupt row must return no partial pose');rows[row_id]=saved
end
rows[row_id]=nil;expect(bank.decode(first)==nil,'Missing interned row refuses');rows[row_id]=saved
for _,bad in ipairs({false,{},'',string.rep('0',341),'0000'..encoded:sub(5),'FFFF'..encoded:sub(5),'GGGG'..encoded:sub(5)})do
 indices[index]=bad;local result,why=bank.decode(first)
 expect(result==nil and type(why)=='string','Selected index corruption refuses within finite bounds');indices[index]=encoded
end
local flags,flag_index=private(bank.decode,'full_body')
debug.setupvalue(bank.decode,flag_index,flags:sub(1,index-1)..'x'..flags:sub(index+1))
expect(bank.decode(first)==nil,'Corrupt full_body flag refuses');debug.setupvalue(bank.decode,flag_index,flags)
expect(bank.decode(first)~=nil,'Independent decoded data remains recoverable after fixture corruption is removed')
local function replace_once(text,old,new)
 local lo,hi=assert(text:find(old,1,true));return text:sub(1,lo-1)..new..text:sub(hi+1)
end
for _,text in ipairs({replace_once(source,'local full_body="','local full_body="x'),
 replace_once(source,'["id"]="salute"','["id"]="INVALID"'),
 replace_once(source,'"'..encoded..'"','"0000"')})do
 local ok=pcall(load_bank,text);expect(not ok,'Malformed startup index/catalog metadata must fail before exposing an API')
end
-- Heap assertions measure retained objects; CPU values are diagnostic only.
local function collected()for _=1,3 do collectgarbage('collect')end;return collectgarbage('count')end
local retained=collected();local started=os.clock()
for _,entry in ipairs(bank.catalog)do local selected=assert(bank.decode(entry.id))end
local all_seconds=os.clock()-started;local after_all=collected()
expect(math.abs(after_all-retained)<32,'Decoder must not retain any previously selected poses')
local selected=assert(bank.decode(first));local selected_kib=collected()-after_all
expect(selected_kib>0 and selected_kib<128,'One pose must stay below the bounded selected-pose heap allowance')
expect(selected.nodes[8]and selected.nodes[92]and not selected.nodes[7]and not selected.nodes[93],'Anchors are never materialized')
print(string.format('Steam pose bank: exact parity for 213 entries / %d scalars, fresh 85-node selections, bounded corruption/refusal, no startup parsing/cache/native work; selected heap %.2f KiB; all decode CPU %.4f s (no time threshold)',scalar_checks,selected_kib,all_seconds))

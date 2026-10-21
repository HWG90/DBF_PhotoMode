-- Five persistent lighting setups. Only bounded numbers and settings are saved;
-- positions/directions are relative to the chosen subject and camera basis.
local M={maximum=5,lights=3,version=1,bytes=32768}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function copy(v)local out={};for k,x in pairs(v or{})do out[k]=type(x)=='table'and copy(x)or x end;return out end
local function slot(n)return finite(n)and n%1==0 and n>=1 and n<=M.maximum end
local function point(v,limit)
 if type(v)~='table'then return false end
 for i=1,3 do if not finite(v[i])or math.abs(v[i])>(limit or 10000000)then return false end end;return true
end
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local vectors={p='position',f='forward',r='right',u='up'}
local function basis(b)
 if type(b)~='table'then return false end
 for _,name in pairs(vectors)do if not point(b[name])then return false end end
 for _,name in ipairs({'forward','right','up'})do if math.abs(dot(b[name],b[name])-1)>.01 then return false end end
 local r,f,u=b.right,b.forward,b.up
 if math.abs(dot(r,f))>.01 or math.abs(dot(r,u))>.01 or math.abs(dot(f,u))>.01 then return false end
 return(r[2]*f[3]-r[3]*f[2])*u[1]+(r[3]*f[1]-r[1]*f[3])*u[2]+(r[1]*f[2]-r[2]*f[1])*u[3]>.99
end
local numbers={intensity={0,10000},range={.1,1000},cone={1,175},right={-100,100},forward={-100,100},up={-100,100}}
local value_keys={'kind','enabled','intensity','color','range','cone','right','forward','up','follow_camera','follow_player'}
local function valid_values(v)
 if type(v)~='table'or(v.kind~='omni'and v.kind~='spot')or type(v.enabled)~='boolean'or type(v.follow_camera)~='boolean'or(v.follow_player~=nil and type(v.follow_player)~='boolean')or(v.follow_player and v.follow_camera)or type(v.color)~='string'or not v.color:match('^#%x%x%x%x%x%x$')then return false end
 for name,limits in pairs(numbers)do if not finite(v[name])or v[name]<limits[1]or v[name]>limits[2]then return false end end;return true
end
local function valid_setup(s,relative)
 if type(s)~='table'or type(s.definitions)~='table'or#s.definitions<1 or#s.definitions>M.lights or not finite(s.selected)or s.selected%1~=0 or s.selected<1 or s.selected>#s.definitions then return false end
 for key in pairs(s.definitions)do if not finite(key)or key%1~=0 or key<1 or key>#s.definitions then return false end end
 for _,d in ipairs(s.definitions)do if type(d)~='table'or not valid_values(d.values)or not basis(d.anchor)or(relative and dot(d.anchor.position,d.anchor.position)>1000000)then return false end end
 return true
end
local function to_local(v,b)return{dot(v,b.right),dot(v,b.forward),dot(v,b.up)}end
local function to_world(v,b)
 local out={};for i=1,3 do out[i]=v[1]*b.right[i]+v[2]*b.forward[i]+v[3]*b.up[i]end;return out
end
local function transform(setup,target,frame,inverse)
 if not point(target)or not basis(frame)then return nil,'Choose a subject and camera placement first'end
 if not valid_setup(setup,not inverse)then return nil,'Invalid or out-of-range lighting setup'end
 local result={version=1,definitions={},selected=setup.selected}
 for i,d in ipairs(setup.definitions)do
  local values=copy(d.values);local anchor={}
  if inverse then
   local p={};for n=1,3 do p[n]=d.anchor.position[n]+d.anchor.right[n]*values.right+d.anchor.forward[n]*values.forward+d.anchor.up[n]*values.up-target[n]end
   anchor.position=to_local(p,frame)
   for _,name in ipairs({'forward','right','up'})do anchor[name]=to_local(d.anchor[name],frame)end
   values.right=0;values.forward=0;values.up=0
  else
   anchor.position=to_world(d.anchor.position,frame);for n=1,3 do anchor.position[n]=anchor.position[n]+target[n]end
   for _,name in ipairs({'forward','right','up'})do anchor[name]=to_world(d.anchor[name],frame)end
  end
  result.definitions[i]={values=values,anchor=anchor}
 end
 if not valid_setup(result,inverse)then return nil,'Lighting setup is beyond the 1000 m subject radius'end
 return result
end
function M.encode(rows)
 assert(type(rows)=='table','Invalid lighting preset slots');for index in pairs(rows)do assert(slot(index),'Invalid lighting preset slot')end
 local out={'version=1\n'}
 for i=1,M.maximum do local setup=rows[i];if setup then
  assert(valid_setup(setup,true),'Invalid stored lighting setup')
  out[#out+1]=i..'.count='..#setup.definitions..'\n'..i..'.selected='..setup.selected..'\n'
  for j,d in ipairs(setup.definitions)do
   for _,key in ipairs(value_keys)do local value=d.values[key];if key=='follow_player'and value==nil then value=false end
    if type(value)=='boolean'then value=value and'1'or'0'elseif type(value)=='number'then value=string.format('%.17g',value)end
    out[#out+1]=i..'.'..j..'.'..key..'='..value..'\n'
   end
   for _,prefix in ipairs({'p','f','r','u'})do for n=1,3 do out[#out+1]=i..'.'..j..'.'..prefix..n..'='..string.format('%.17g',d.anchor[vectors[prefix]][n])..'\n'end end
  end
 end end
 local data=table.concat(out);assert(#data<=M.bytes,'Lighting preset file is too large');return data
end
function M.decode(data)
 if type(data)~='string'or#data>M.bytes then return nil,'Lighting preset file is too large'end
 local rows,counts,seen={},{},{};local version
 for line in(data..'\n'):gmatch('([^\r\n]*)[\r\n]')do if line~=''then
  local key,value=line:match('^([%w_.]+)=([^\r\n]+)$');if not key or seen[key]then return nil,'Invalid lighting preset file'end;seen[key]=true
  if key=='version'then version=tonumber(value)
  else
   local number,name=key:match('^(%d)%.([a-z]+)$');local index=tonumber(number)
   if index then
    if not slot(index)or(name~='count'and name~='selected')then return nil,'Unknown lighting preset field'end
    local n=tonumber(value);if not finite(n)or n%1~=0 or n<1 or n>M.lights then return nil,'Invalid lighting preset count'end
    rows[index]=rows[index]or{version=1,definitions={}}
    if name=='count'then counts[index]=n else rows[index].selected=n end
   else
    local a,b,field=key:match('^(%d)%.(%d)%.([%w_]+)$');index=tonumber(a);local light=tonumber(b)
    if not slot(index)or not light or light<1 or light>M.lights then return nil,'Invalid lighting preset slot'end
    rows[index]=rows[index]or{version=1,definitions={}};local setup=rows[index]
    setup.definitions[light]=setup.definitions[light]or{values={},anchor={position={},forward={},right={},up={}}};local d=setup.definitions[light]
    local prefix,axis=field:match('^([pfru])([123])$')
    if prefix then local n=tonumber(value);if not finite(n)then return nil,'Invalid lighting coordinate'end;d.anchor[vectors[prefix]][tonumber(axis)]=n
    elseif numbers[field]then local n=tonumber(value);if not finite(n)then return nil,'Invalid light value'end;d.values[field]=n
    elseif field=='enabled'or field=='follow_camera'or field=='follow_player'then if value~='0'and value~='1'then return nil,'Invalid light toggle'end;d.values[field]=value=='1'
    elseif field=='kind'or field=='color'then d.values[field]=value
    else return nil,'Unknown lighting preset value'end
   end
  end
 end end
 if version~=M.version then return nil,'Unsupported lighting preset version'end
 for index,setup in pairs(rows)do if counts[index]~=#setup.definitions or not valid_setup(setup,true)then return nil,'Incomplete or out-of-range lighting setup'end end
 return rows
end
local function atomic_replace(source,target)
 if M.replace then return M.replace(source,target)end
 -- Standalone portable fallback: keep a recovery journal across Windows'
 -- refusal to rename over an existing file. Runtime hosts can inject a truly
 -- atomic replace/storage provider, as the legacy builder does below.
 local backup=target..'.replace-backup'
 local old=io.open(target,'rb')
 if not old then
  local journal=io.open(backup,'rb')
  if journal then journal:close();local ok,why=os.rename(backup,target);if not ok then return false,why end;old=io.open(target,'rb')end
 end
 if old then
  old:close();os.remove(backup)
  local ok,why=os.rename(target,backup);if not ok then return false,why end
 end
 local ok,why=os.rename(source,target)
 if not ok then if old then os.rename(backup,target)end;return false,why end
 if old then os.remove(backup)end
 return true
end
function M.storage(path,filesystem)
 local fs=filesystem or{open=io and io.open,replace=atomic_replace,remove=os and os.remove};local self={}
 local function available()return type(path)=='string'and#path>0 and type(fs.open)=='function'and type(fs.replace)=='function'and type(fs.remove)=='function'end
 function self.load()
  if not available()then return nil,'Lighting preset storage unavailable'end
  local f=fs.open(path,'rb')
  if not f and not filesystem then f=fs.open(path..'.replace-backup','rb')end
  if not f then return{}end
  local ok,data=pcall(f.read,f,M.bytes+1);local closed,done=pcall(f.close,f)
  if not ok or not closed or not done then return nil,'Lighting preset read failed'end
  return M.decode(data)
 end
 function self.save(rows)
  if not available()then return false,'Lighting preset storage unavailable'end
  local ok,data=pcall(M.encode,rows);if not ok then return false,tostring(data)end
  local temp=path..'.tmp';local f,why=fs.open(temp,'wb');if not f then return false,why end
  local wrote,done,reason=pcall(f.write,f,data);local closed,finished,close_why=pcall(f.close,f)
  if not wrote or not done or not closed or not finished then fs.remove(temp);return false,tostring(wrote and(reason or close_why)or done)end
  local moved,accepted,err=pcall(fs.replace,temp,path)
  if not moved or not accepted then fs.remove(temp);return false,tostring(moved and err or accepted)end
  return true
 end
 return self
end
function M.new(path,storage)
 local self={status='Lighting presets: select a setup slot'};local rows={};local load_error;storage=storage or M.storage(path)
 local ok,loaded,why=pcall(storage.load)
 if ok and type(loaded)=='table'then rows=loaded else load_error=tostring(ok and why or loaded);self.status='Lighting presets: '..load_error end
 local function commit(candidate,message)
  if load_error then return false,'Existing lighting preset file was not loaded: '..load_error end
  local called,accepted,reason=pcall(storage.save,candidate)
  if not called or accepted~=true then self.status='Lighting preset save failed: '..tostring(called and reason or accepted);return false,self.status end
  rows=candidate;self.status=message;return true
 end
 function self.list()local labels={};for i=1,M.maximum do labels[i]='Setup '..i..(rows[i]and' — saved'or' — empty')end;return labels end
 function self.occupied(index)return slot(index)and rows[index]~=nil end
 function self.save(index,setup,target,frame)
  if not slot(index)then return false,'Choose a lighting setup slot'end
  local relative,reason=transform(setup,target,frame,true);if not relative then self.status=reason;return false,reason end
  local candidate=copy(rows);candidate[index]=relative;return commit(candidate,'Setup '..index..' saved relative to subject')
 end
 function self.recall(index,target,frame)
  if not slot(index)or not rows[index]then return nil,'This lighting setup is empty'end
  local setup,reason=transform(rows[index],target,frame,false)
  self.status=setup and('Setup '..index..' recalled at subject')or reason;return setup,reason
 end
 function self.clear(index)
  if not slot(index)then return false,'Choose a lighting setup slot'end
  local candidate=copy(rows);candidate[index]=nil;return commit(candidate,'Setup '..index..' cleared')
 end
 return self
end
return M

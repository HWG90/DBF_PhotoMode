-- Numbered pose files: strict text format and probing storage. The only
-- module here that touches files, through an injected {open,rename,remove}.
local M={MAXIMUM=99,MAX_BYTES=32768,RIG='4d1c334d294dfa97',NODES=107,VERSION=1}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function clean(text,limit)
 text=tostring(text or''):gsub('[%c]',' ')
 if #text>limit then text=text:sub(1,limit)end
 return text
end
function M.path(folder,n)return folder..'/wj-pose-'..string.format('%02d',n)..'.txt'end
local function join(values,count)
 local out={};for i=1,count do out[i]=string.format('%.17g',values[i])end;return table.concat(out,',')
end
function M.encode(frame,meta)
 assert(type(frame)=='table'and type(frame.nodes)=='table','Pose frame required')
 meta=meta or{}
 local lines={'version='..M.VERSION,'rig='..M.RIG,'nodes='..M.NODES,'label='..clean(meta.label or'Pose',96),'source='..clean(meta.source or'edited',64)}
 for i=8,92 do
  local node=assert(frame.nodes[i],'Pose frame node missing: '..i)
  lines[#lines+1]=i..'='..join(node.p,3)..';'..join(node.q,4)..';'..join(node.s,3)
 end
 return table.concat(lines,'\n')..'\n'
end
local function numbers(text,count)
 local out={};local n=0
 for token in (text..','):gmatch('([^,]*),')do
  n=n+1;if n>count then return nil end
  local value=tonumber(token);if not finite(value)then return nil,'Pose value is not a number'end
  out[n]=value
 end
 if n~=count then return nil end
 return out
end
local HEADER={version=true,rig=true,nodes=true,label=true,source=true}
function M.decode(text)
 if type(text)~='string'or text==''then return nil,'Pose file is empty'end
 if #text>M.MAX_BYTES then return nil,'Pose file is too large'end
 local header,nodes={},{}
 for line in (text..'\n'):gmatch('([^\r\n]*)[\r\n]')do if line~=''then
  local key,value=line:match('^([%w_]+)=(.*)$');if not key then return nil,'Pose file has an unknown line'end
  local n=tonumber(key)
  if n then
   if n%1~=0 or n<8 or n>92 or key~=tostring(n)then return nil,'Pose file has an unknown line'end
   if nodes[n]then return nil,'Pose file repeats '..n end
   local p,q,s=value:match('^([^;]*);([^;]*);([^;]*)$');if not p then return nil,'Pose file has an unknown line'end
   local pv,why=numbers(p,3);if not pv then return nil,why or'Pose file has an unknown line'end
   local qv;qv,why=numbers(q,4);if not qv then return nil,why or'Pose file has an unknown line'end
   local sv;sv,why=numbers(s,3);if not sv then return nil,why or'Pose file has an unknown line'end
   local norm=qv[1]*qv[1]+qv[2]*qv[2]+qv[3]*qv[3]+qv[4]*qv[4]
   if norm<.99*.99 or norm>1.01*1.01 then return nil,'Pose quaternion is not normalised'end
   nodes[n]={p=pv,q=qv,s=sv}
  elseif HEADER[key]then
   if header[key]~=nil then return nil,'Pose file repeats '..key end
   header[key]=value
  else return nil,'Pose file has an unknown line'end
 end end
 if header.version~=tostring(M.VERSION)then return nil,'Unsupported pose file version'end
 if header.rig~=M.RIG or header.nodes~=tostring(M.NODES)then return nil,'This pose is for a different rig'end
 for i=8,92 do if not nodes[i]then return nil,'Pose file is missing node '..i end end
 return{full_body=true,label=header.label or'',source=header.source or'',nodes=nodes}
end
function M.storage(folder,fs)
 fs=fs or{open=io and io.open,rename=os and os.rename,remove=os and os.remove}
 local self={};local entries={}
 local function available()return type(folder)=='string'and #folder>0 and type(fs.open)=='function'and type(fs.rename)=='function'and type(fs.remove)=='function'end
 local function read_all(path)
  if not available()then return nil end
  local f=fs.open(path,'rb');if not f then return nil end
  local ok,data=pcall(f.read,f,M.MAX_BYTES+1);pcall(f.close,f)
  if not ok or type(data)~='string'then return''end
  return data
 end
 local function number_label(n)return string.format('%02d',n)end
 function self.rescan()
  entries={}
  for n=1,M.MAXIMUM do
   local data=read_all(M.path(folder,n))
   if data~=nil then
    local frame=M.decode(data)
    entries[#entries+1]={number=n,label=frame and frame.label or nil,readable=frame~=nil}
   end
  end
  return entries
 end
 function self.list()return entries end
 function self.labels()
  if #entries==0 then return{'No saved poses'}end
  local out={};for i,entry in ipairs(entries)do out[i]=number_label(entry.number)..' — '..(entry.readable and entry.label or'unreadable')end
  return out
 end
 function self.load(n)
  local data=read_all(M.path(folder,n));if data==nil then return nil,'No pose file '..number_label(n)end
  return M.decode(data)
 end
 local function write(path,text)
  if not available()then return false,'Pose storage unavailable'end
  local temp,backup=path..'.tmp',path..'.bak'
  local f,why=fs.open(temp,'wb');if not f then return false,why or'Pose file could not be written'end
  local called,written,err=pcall(f.write,f,text);local closed,close_ok,close_err=pcall(f.close,f)
  if not called or not written or not closed or not close_ok then fs.remove(temp);return false,tostring(called and(err or close_err)or written)end
  local old=fs.open(path,'rb')
  if old then
   pcall(old.close,old);fs.remove(backup)
   local moved,reason=fs.rename(path,backup);if not moved then fs.remove(temp);return false,reason end
  end
  local moved,reason=fs.rename(temp,path)
  if not moved then if old then fs.rename(backup,path)end;fs.remove(temp);return false,reason end
  return true
 end
 function self.save_new(frame,meta)
  self.rescan();local taken={};for _,entry in ipairs(entries)do taken[entry.number]=true end
  local free;for n=1,M.MAXIMUM do if not taken[n]then free=n;break end end
  if not free then return nil,'No free pose number; delete one first'end
  local ok,why=write(M.path(folder,free),M.encode(frame,meta));if not ok then return nil,why end
  self.rescan();return free
 end
 function self.overwrite(n,frame)
  local existing=self.load(n)
  local meta={label=existing and existing.label or'Pose '..number_label(n),source=existing and existing.source or'edited'}
  local ok,why=write(M.path(folder,n),M.encode(frame,meta));if not ok then return false,why end
  self.rescan();return true
 end
 function self.delete(n)
  local path=M.path(folder,n);local ok,why=fs.remove(path);fs.remove(path..'.bak')
  if not ok then return false,why or'Pose file could not be deleted'end
  self.rescan();return true
 end
 self.rescan()
 return self
end
return M

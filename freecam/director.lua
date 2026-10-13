-- Five persistent camera shots, expressed in the current local player's yaw
-- basis. Only Photo Mode's detached camera is moved; no player transform writes.
local M={maximum=5,version=1}
local fields={'right','forward','up','yaw','pitch','roll','fov'}
local limits={right=1000,forward=1000,up=1000,yaw=math.pi,pitch=math.rad(89),roll=180,fov=120}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function angle(n)return(n+math.pi)%(2*math.pi)-math.pi end
local function copy(value)local result={};for k,v in pairs(value or{})do result[k]=type(v)=='table'and copy(v)or v end;return result end
local function valid(row)
 if type(row)~='table'then return false end
 for _,key in ipairs(fields)do if not finite(row[key])or math.abs(row[key])>limits[key]or(key=='fov'and row[key]<0)then return false end end
 return true
end
local function slot(index)return finite(index)and index%1==0 and index>=1 and index<=M.maximum end
function M.encode(rows)
 local out={'version=1\n'}
 for i=1,M.maximum do if rows[i]then
  assert(valid(rows[i]),'Invalid Director shot')
  for _,key in ipairs(fields)do out[#out+1]=i..'.'..key..'='..string.format('%.17g',rows[i][key])..'\n' end
 end end
 return table.concat(out)
end
function M.decode(data)
 if type(data)~='string'or #data>16384 then return nil,'Director preset file is too large'end
 local rows,seen,version={},{}
 for line in (data..'\n'):gmatch('([^\r\n]*)[\r\n]')do if line~=''then
  local key,value=line:match('^([%w_.]+)=([^\r\n]+)$');if not key or seen[key]then return nil,'Invalid Director preset file'end;seen[key]=true
  if key=='version'then version=tonumber(value)
  else
   local number,name=key:match('^(%d)%.([a-z]+)$');local index=tonumber(number)
   if not slot(index)or not limits[name]then return nil,'Unknown Director preset field'end
   local n=tonumber(value);if not finite(n)then return nil,'Invalid Director preset value'end
   rows[index]=rows[index]or{};rows[index][name]=n
  end
 end end
 if version~=M.version then return nil,'Unsupported Director preset version'end
 for _,row in pairs(rows)do if not valid(row)then return nil,'Incomplete or out-of-range Director preset'end end
 return rows
end
function M.storage(path,filesystem)
 local fs=filesystem or{open=io and io.open,rename=os and os.rename,remove=os and os.remove}
 local self={}
 local function available()return type(path)=='string'and #path>0 and type(fs.open)=='function'and type(fs.rename)=='function'and type(fs.remove)=='function'end
 function self.load()
  if not available()then return nil,'Director preset storage unavailable'end
  local f,why=fs.open(path,'rb');if not f then return {},nil end
  local ok,data=pcall(f.read,f,16385);local closed,close_ok,err=pcall(f.close,f)
  if not ok or not closed or not close_ok then return nil,'Director preset read failed: '..tostring(ok and err or data)end
  return M.decode(data)
 end
 function self.save(rows)
  if not available()then return false,'Director preset storage unavailable'end
  local data=M.encode(rows);local temp,backup=path..'.tmp',path..'.bak'
  local f,why=fs.open(temp,'wb');if not f then return false,why end
  local called,written,err=pcall(f.write,f,data);local closed,close_ok,close_err=pcall(f.close,f)
  if not called or not written or not closed or not close_ok then fs.remove(temp);return false,tostring(called and(err or close_err)or written)end
  local old=fs.open(path,'rb');if old then old:close();fs.remove(backup)
   local moved,reason=fs.rename(path,backup);if not moved then fs.remove(temp);return false,reason end
  end
  local moved,reason=fs.rename(temp,path)
  if not moved then if old then fs.rename(backup,path)end;fs.remove(temp);return false,reason end
  return true
 end
 return self
end
function M.new(photo,context,path,log,storage)
 local self={status='Director: select a shot slot'};local rows={};log=log or function()end
 storage=storage or M.storage(path)
 local loaded,values,why=pcall(storage.load)
 if loaded and type(values)=='table'then rows=values else self.status='Director presets: '..tostring(loaded and why or values);log(self.status)end
 local function current()
  local ok,value,reason=pcall(context)
  if not ok or type(value)~='table'or value.local_owner~=true or not value.identity or not finite(value.yaw)or type(value.position)~='table'then return nil,tostring(ok and reason or value or 'Local player unavailable')end
  for i=1,3 do if not finite(value.position[i])then return nil,'Local player transform unavailable'end end
  return value
 end
 local function commit(candidate,message)
  local called,accepted,reason=pcall(storage.save,candidate)
  if not called or accepted==false then self.status='Director save failed: '..tostring(called and reason or accepted);return false,self.status end
  rows=candidate;self.status=message;return true
 end
 function self.ready()
  if not photo.active then return false,'Open Photo Mode to place or recall a shot'end
  local value,why=current();return value~=nil,why,value
 end
 function self.list()
  local names={};for i=1,M.maximum do names[i]='Shot '..i..(rows[i]and' — saved'or' — empty')end;return names
 end
 function self.occupied(index)return slot(index)and rows[index]~=nil end
 function self.save(index)
  if not slot(index)then return false,'Choose a Director shot slot'end
  local ready,why,player=self.ready();if not ready then self.status=why;return false,why end
  if type(photo.pos)~='table'or not photo.view or not finite(photo.view.yaw)or not finite(photo.view.pitch)then return false,'Place the Photo Mode camera first'end
  for i=1,3 do if not finite(photo.pos[i])then return false,'Camera position unavailable'end end
  local dx,dy,dz=photo.pos[1]-player.position[1],photo.pos[2]-player.position[2],photo.pos[3]-player.position[3]
  local c,s=math.cos(player.yaw),math.sin(player.yaw)
  local row={right=dx*s-dy*c,forward=dx*c+dy*s,up=dz,yaw=angle(photo.view.yaw-player.yaw),pitch=photo.view.pitch,roll=photo.options and photo.options.roll or 0,fov=photo.options and photo.options.fov or 0}
  if not valid(row)then return false,'Camera is outside the Director shot limits'end
  local candidate=copy(rows);candidate[index]=row;return commit(candidate,'Shot '..index..' saved relative to player')
 end
 function self.clear(index)
  if not slot(index)then return false,'Choose a Director shot slot'end
  local candidate=copy(rows);candidate[index]=nil;return commit(candidate,'Shot '..index..' cleared')
 end
 function self.recall(index,handle)
  if not slot(index)or not rows[index]then return false,'This Director shot is empty'end
  local ready,why,player=self.ready();if not ready then self.status=why;return false,why end
  local row=rows[index];local c,s=math.cos(player.yaw),math.sin(player.yaw)
  local values={fov=row.fov,roll=row.roll};local old={fov=handle.get('fov'),roll=handle.get('roll')}
  local called,accepted,reason=pcall(function()
   if handle.set_many then return handle.set_many(values)end
   for _,key in ipairs({'fov','roll'})do local ok,err=handle.set(key,values[key]);if ok==false then for name,value in pairs(old)do handle.set(name,value)end;return false,err end end
   return true
  end)
  if not called or accepted==false then return false,'Director lens recall failed: '..tostring(called and reason or accepted)end
  photo.pos={player.position[1]+row.forward*c+row.right*s,player.position[2]+row.forward*s-row.right*c,player.position[3]+row.up}
  photo.view={yaw=(player.yaw+row.yaw)%(2*math.pi),pitch=row.pitch,sequence=photo.input and photo.input.sequence}
  photo.locked=false;photo.lock_pose=nil
  if photo.options then photo.options.fov=row.fov;photo.options.roll=row.roll end
  self.status='Shot '..index..' recalled relative to current player';return true
 end
 return self
end
return M

-- Five persistent camera shots, expressed in the current local player's yaw
-- basis. Only Photo Mode's detached camera is moved; no player transform writes.
local M={maximum=5,version=1}
local fields={'right','forward','up','yaw','pitch','roll','fov'}
local limits={right=1000,forward=1000,up=1000,yaw=math.pi,pitch=math.rad(89),roll=180,fov=120,bone=4}
-- Optional bone anchor (absent: the player's yaw basis, as before). The offset and the camera
-- direction are then in that bone's own axes, so a camera on the face stays on the face.
local bone_names={'root','hips','chest','head'}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function angle(n)return(n+math.pi)%(2*math.pi)-math.pi end
local function copy(value)local result={};for k,v in pairs(value or{})do result[k]=type(v)=='table'and copy(v)or v end;return result end
local function valid(row)
 if type(row)~='table'then return false end
 if row.bone~=nil and not(finite(row.bone)and row.bone%1==0 and row.bone>=1 and row.bone<=#bone_names)then return false end
 for _,key in ipairs(fields)do
  -- A bone's axes can point anywhere, so its local pitch may reach straight up or down.
  local limit=key=='pitch'and row.bone and math.pi/2 or limits[key]
  if not finite(row[key])or math.abs(row[key])>limit or(key=='fov'and row[key]<0)then return false end
 end
 return true
end
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function unit(v)
 if type(v)~='table'then return nil end
 for i=1,3 do if not finite(v[i])then return nil end end
 local n=math.sqrt(dot(v,v));if n<1e-6 then return nil end
 return{v[1]/n,v[2]/n,v[3]/n}
end
-- A bone as position p and normalised axes x, y, z (nil if unusable).
local function bone_basis(b)
 if type(b)~='table'or type(b.p)~='table'then return nil end
 for i=1,3 do if not finite(b.p[i])then return nil end end
 local x,y,z=unit(b.x),unit(b.y),unit(b.z)
 if x and y and z then return b.p,x,y,z end
end
-- The nearest of head/chest/hips within 1 m of the camera, else the body root.
local function anchor(bones,pos)
 local best,best_distance
 for code=2,#bone_names do
  local p=bone_basis(bones[bone_names[code]])
  if p then
   local d=math.sqrt((pos[1]-p[1])^2+(pos[2]-p[2])^2+(pos[3]-p[3])^2)
   if d<=1 and(not best_distance or d<best_distance)then best,best_distance=code,d end
  end
 end
 if best then return best end
 if bone_basis(bones.root)then return 1 end
end
local function slot(index)return finite(index)and index%1==0 and index>=1 and index<=M.maximum end
function M.encode(rows)
 local out={'version=1\n'}
 for i=1,M.maximum do if rows[i]then
  assert(valid(rows[i]),'Invalid Director shot')
  for _,key in ipairs(fields)do out[#out+1]=i..'.'..key..'='..string.format('%.17g',rows[i][key])..'\n' end
  if rows[i].bone then out[#out+1]=i..'.bone='..rows[i].bone..'\n' end
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
 -- The current camera as a shot relative to the player frame.
 local function relative(player)
  if type(photo.pos)~='table'or not photo.view or not finite(photo.view.yaw)or not finite(photo.view.pitch)then return nil,'Place the Photo Mode camera first'end
  for i=1,3 do if not finite(photo.pos[i])then return nil,'Camera position unavailable'end end
  local roll,fov=photo.options and photo.options.roll or 0,photo.options and photo.options.fov or 0
  local code=type(player.bones)=='table'and anchor(player.bones,photo.pos)
  local row
  if code then
   local p,x,y,z=bone_basis(player.bones[bone_names[code]])
   local d={photo.pos[1]-p[1],photo.pos[2]-p[2],photo.pos[3]-p[3]}
   local cp=math.cos(photo.view.pitch)
   local f={math.cos(photo.view.yaw)*cp,math.sin(photo.view.yaw)*cp,math.sin(photo.view.pitch)}
   local l={dot(f,x),dot(f,y),dot(f,z)}
   row={bone=code,right=dot(d,x),forward=dot(d,y),up=dot(d,z),yaw=math.atan2(l[2],l[1]),pitch=math.asin(math.max(-1,math.min(1,l[3]))),roll=roll,fov=fov}
  else
   local dx,dy,dz=photo.pos[1]-player.position[1],photo.pos[2]-player.position[2],photo.pos[3]-player.position[3]
   local c,s=math.cos(player.yaw),math.sin(player.yaw)
   row={right=dx*s-dy*c,forward=dx*c+dy*s,up=dz,yaw=angle(photo.view.yaw-player.yaw),pitch=photo.view.pitch,roll=roll,fov=fov}
  end
  if not valid(row)then return nil,'Camera is outside the Director shot limits'end
  return row
 end
 -- Place the camera at a shot relative to the player frame, lens included.
 local function place(row,player,handle)
  local pos,view
  if row.bone then
   local p,x,y,z=bone_basis(type(player.bones)=='table'and player.bones[bone_names[row.bone]])
   if not p then return false,'This shot\'s '..bone_names[row.bone]..' bone is unavailable on the selected Helldiver'end
   local cp=math.cos(row.pitch);local l={math.cos(row.yaw)*cp,math.sin(row.yaw)*cp,math.sin(row.pitch)}
   local f={l[1]*x[1]+l[2]*y[1]+l[3]*z[1],l[1]*x[2]+l[2]*y[2]+l[3]*z[2],l[1]*x[3]+l[2]*y[3]+l[3]*z[3]}
   pos={p[1]+row.right*x[1]+row.forward*y[1]+row.up*z[1],p[2]+row.right*x[2]+row.forward*y[2]+row.up*z[2],p[3]+row.right*x[3]+row.forward*y[3]+row.up*z[3]}
   view={yaw=math.atan2(f[2],f[1])%(2*math.pi),pitch=math.asin(math.max(-1,math.min(1,f[3])))}
  else
   local c,s=math.cos(player.yaw),math.sin(player.yaw)
   pos={player.position[1]+row.forward*c+row.right*s,player.position[2]+row.forward*s-row.right*c,player.position[3]+row.up}
   view={yaw=(player.yaw+row.yaw)%(2*math.pi),pitch=row.pitch}
  end
  local values={fov=row.fov,roll=row.roll};local old={fov=handle.get('fov'),roll=handle.get('roll')}
  local called,accepted,reason=pcall(function()
   if handle.set_many then return handle.set_many(values)end
   for _,key in ipairs({'fov','roll'})do local ok,err=handle.set(key,values[key]);if ok==false then for name,value in pairs(old)do handle.set(name,value)end;return false,err end end
   return true
  end)
  if not called or accepted==false then return false,'Director lens recall failed: '..tostring(called and reason or accepted)end
  photo.pos=pos
  photo.view={yaw=view.yaw,pitch=view.pitch,sequence=photo.input and photo.input.sequence}
  photo.locked=false;photo.lock_pose=nil
  if photo.options then photo.options.fov=row.fov;photo.options.roll=row.roll end
  return true
 end
 function self.save(index)
  if not slot(index)then return false,'Choose a Director shot slot'end
  local ready,why,player=self.ready();if not ready then self.status=why;return false,why end
  local row;row,why=relative(player);if not row then return false,why end
  local candidate=copy(rows);candidate[index]=row;return commit(candidate,'Shot '..index..' saved relative to player')
 end
 -- The camera at the last Photo Mode close, for this game session only.
 local last
 function self.remember()
  local ready,why,player=self.ready();if not ready then return false,why end
  local row;row,why=relative(player);if not row then return false,why end
  last=row;return true
 end
 function self.return_to_last(handle)
  if not last then return false,'No camera to return to'end
  local ready,why,player=self.ready();if not ready then return false,why end
  local ok;ok,why=place(last,player,handle);if not ok then return false,why end
  self.status='Camera returned to its place relative to the player';return true
 end
 function self.clear(index)
  if not slot(index)then return false,'Choose a Director shot slot'end
  local candidate=copy(rows);candidate[index]=nil;return commit(candidate,'Shot '..index..' cleared')
 end
 function self.recall(index,handle)
  if not slot(index)or not rows[index]then return false,'This Director shot is empty'end
  local ready,why,player=self.ready();if not ready then self.status=why;return false,why end
  local ok;ok,why=place(rows[index],player,handle);if not ok then return false,why end
  self.status='Shot '..index..' recalled relative to current player';return true
 end
 return self
end
return M

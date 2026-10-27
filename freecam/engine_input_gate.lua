-- Engine-only experiment. Threshold readback is not gameplay isolation proof.
-- No native modules, query wrappers, polling, or writes in settled state.
local M={}
function M.new(sr,log)
 local self={};local owned={};local message
 local function note(value)if message~=value then message=value;if log then pcall(log,'Engine input gate: '..value)end end end
 function self.available()
  for _,name in ipairs({'Keyboard','Mouse'})do
   local device=sr[name]
   if type(device)~='table'or type(device.down_threshold)~='function'or type(device.set_down_threshold)~='function'then return false end
  end
  return true
 end
 local function read(device)
  local ok,value=pcall(device.down_threshold)
  if not ok or type(value)~='number'or value~=value or value<0 or value>1 then return nil,'Threshold read unavailable'end
  return value
 end
 function self.release()
  for i=#owned,1,-1 do
   local row=owned[i];local current,why=read(row.device)
   if current==nil then return false,why end
   if current==row.before then table.remove(owned,i)
   elseif current~=1 then
    -- A different owner changed this device; preserve its setting.
    table.remove(owned,i);note(row.name..' changed by another owner; preserved')
   else
    local ok,result=pcall(row.device.set_down_threshold,row.before)
    if not ok or result==false then return false,'Threshold restoration refused: '..row.name end
    if read(row.device)~=row.before then return false,'Threshold restoration unacknowledged: '..row.name end
    table.remove(owned,i)
   end
  end
  note('released');return true
 end
 function self.acquire()
  if #owned>0 then return false,'Threshold cleanup pending'end
  if not self.available()then note('threshold APIs unavailable; gameplay keys remain shared');return true,false end
  local function refuse(why)
   local restored,issue=self.release();return false,restored and why or issue
  end
  for _,name in ipairs({'Keyboard','Mouse'})do
   local device=sr[name];local before,why=read(device)
   if before==nil then return refuse(why)end
   if before==1 then return refuse(name..' threshold already owned')end
   -- Record before the call: a throwing setter may have partially applied.
   owned[#owned+1]={name=name,device=device,before=before}
   local ok,result=pcall(device.set_down_threshold,1)
   if not ok or result==false or read(device)~=1 then return refuse('Threshold request refused: '..name)end
  end
  note('threshold candidate active; Keyboard=1 Mouse=1; gameplay validation pending')
  return true,true
 end
 function self.pending()return #owned>0 end
 return self
end
return M

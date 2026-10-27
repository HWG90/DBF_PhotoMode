-- Reversible Windows cursor-boundary experiment. No native module or ESC UI.
-- A successful flag readback is not proof of gameplay-input suppression.
local M={}
function M.new(sr,log)
 local W=sr.Window;local self={kind='native-cursor-candidate'}
 local before,attempted,retry_at,retry_reason;local last_message
 local esc;local K=sr.Keyboard
 if type(K)=='table'and type(K.button_index or K.button_id)=='function'then
  local ok,id=pcall(K.button_index or K.button_id,'esc');if ok and type(id)=='number'and id>=0 and id%1==0 then esc=id end
 end
 local function note(message)if last_message~=message then last_message=message;if log then pcall(log,'Engine cursor gate: '..message)end end end
 local function read()
  local ok,value=pcall(W.show_cursor)
  if not ok or type(value)~='boolean'then return nil end;return value
 end
 local function now()
  local A=sr.Application
  if A and type(A.time_since_launch)=='function'then local ok,n=pcall(A.time_since_launch);if ok and type(n)=='number'and n==n and n>=0 and n<math.huge then return n end end
  return os.clock()
 end
 function self.available()return type(W)=='table'and type(W.show_cursor)=='function'and type(W.set_show_cursor)=='function'end
 function self.pending()return attempted==true end
 function self.release()
  if not attempted then return true end
  if retry_at and now()<retry_at then return false,retry_reason end
  local function pending(reason)retry_reason=reason;retry_at=now()+.25;note(reason);return false,reason end
  local current=read();if current==nil then return pending('Cursor restoration awaits a readable state')end
  if current==true and esc and type(K.button)=='function'then
   local ok,value=pcall(K.button,esc)
   if ok and(value==true or type(value)=='number'and value>.5)then
    -- ESC is also processed by the native menu. Never hide its cursor while
    -- Photo Mode closes from that same key; native UI owns the next state.
    attempted=false;before=nil;retry_at=nil;note('yielded visible cursor to native ESC');return true
   end
  end
  if current~=before then
   local ok,result=pcall(W.set_show_cursor,before)
   if not ok or result==false or read()~=before then return pending('Cursor restoration not acknowledged')end
  end
  attempted=false;before=nil;retry_at=nil;retry_reason=nil;note('restored original cursor visibility');return true
 end
 function self.acquire()
  if attempted then return false,'Cursor restoration pending'end
  if not self.available()then note('cursor APIs unavailable; gameplay input remains shared');return true,false end
  before=read();if before==nil then return false,'Cursor baseline unavailable'end
  if before then before=nil;return false,'Close the native menu before opening Photo Mode'end
  attempted=true;retry_at=nil;retry_reason=nil
  local ok,result=pcall(W.set_show_cursor,true)
  if not ok or result==false or read()~=true then
   local restored,why=self.release();return false,restored and'Visible cursor request refused'or why
  end
  note('visible cursor acquired without ESC; gameplay validation pending');return true,true
 end
 return self
end
return M

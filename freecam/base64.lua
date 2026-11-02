-- Base64 (RFC 4648, padded) to bytes, for the binaries the package carries: a third smaller
-- than hex. Plain Lua 5.1 has no bit library, so each four-character group is arithmetic on
-- its 24 bits.
local M={}
local values={}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
for i=1,64 do values[alphabet:sub(i,i)]=i-1 end
local char,floor=string.char,math.floor
function M.decode(text)
 assert(type(text)=='string'and #text%4==0 and text:match('^[%w%+/]*=?=?$'),'Not base64')
 local padding=#text:match('=*$')
 local bytes=text:gsub('(.)(.)(.)(.)',function(a,b,c,d)
  local n=values[a]*262144+values[b]*4096+(values[c]or 0)*64+(values[d]or 0)
  return char(floor(n/65536),floor(n/256)%256,n%256)
 end)
 return bytes:sub(1,#bytes-padding)
end
return M

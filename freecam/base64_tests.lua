-- Base64 decoding for the binaries the package carries: plain Lua 5.1, no bit library.
assert(_VERSION=='Lua 5.1'and (not rawget(_G,'jit')or DBF_PHOTO_TEST_LUAJIT==true),'Run in Lua 5.1 or the explicit LuaJIT fixture runner')
local B=dofile('freecam/base64.lua')
-- RFC 4648 section 10 vectors.
for text,bytes in pairs({['']='',Zg__='f',Zm8_='fo',Zm9v='foo',Zm9vYg__='foob',Zm9vYmE_='fooba',Zm9vYmFy='foobar'})do
 assert(B.decode((text:gsub('_','=')))==bytes,text)
end
-- Every byte value, through both alphabet ends and every padding length.
local all={};for i=0,255 do all[#all+1]=string.char(i)end;all=table.concat(all)
local encoded='AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w=='
assert(B.decode(encoded)==all,'All 256 byte values')
-- Malformed text refuses rather than returning partial bytes.
for _,bad in ipairs({'Zg=','Z===','Zg==Zg==','Zm9v!AAA','Zm 9v','=Zm9','Zm=v',false,{}})do
 assert(not pcall(B.decode,bad),'Refuse '..tostring(bad))
end
print('Base64: RFC 4648 vectors, all byte values, malformed input refused')

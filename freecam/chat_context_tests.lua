local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'chat_context.lua');local layout=module.layout
local function integer(value,size)local out={};for _=1,size do out[#out+1]=string.char(value%256);value=math.floor(value/256)end;return table.concat(out)end
local base,manager,open=0x10000000,0x20000000,0
local metadata={base=base,stamp=layout.stamp,image_size=layout.image_size};local prefix,store=layout.writer_prefix,layout.writer_store
local generation_change,missing,reads=false,false,0
local backend={module=function()return metadata end,read=function(address,size)
 reads=reads+1
 if address==base+layout.writer then return prefix end
 if address==base+layout.writer+0x66 then return store end
 if address==base+layout.manager then return integer(manager,8)end
 if address==manager+layout.feed+layout.open then
  if missing then return end
  if generation_change then manager=manager+0x1000 end
  return string.char(open)
 end
 error('Unexpected chat context read')
end}
local reader=module.new(backend)
assert(reader.chat_active()==false,'Closed chat must return exact false')
open=1;assert(reader.chat_active()==true,'The actual widget open byte must enable the guard')
open=0;assert(reader.chat_active()==false,'Sending/Escape closing the widget must immediately clear the guard')
open=2;assert(reader.chat_active()==nil,'Unknown byte types must remain unavailable, never guessed open')
open=1;missing=true;assert(reader.chat_active()==nil,'An unreadable chat widget must not lock all photo activation')
missing=false;generation_change=true;assert(reader.chat_active()==nil,'A swapped chat manager must reject the observed byte')
generation_change=false;assert(reader.chat_active()==true,'A new valid manager generation must be reacquired')
manager=0;assert(reader.chat_active()==nil,'Main-menu/loading missing chat must be unavailable')
manager=0x20000000;metadata.stamp=0;local before=reads;assert(reader.chat_active()==nil and reads==before,'Unknown builds must not read guessed game offsets')
metadata.stamp=layout.stamp;metadata.image_size=0;assert(reader.chat_active()==nil and reads==before,'Changed game image bounds must reject the reader')
metadata.image_size=layout.image_size;prefix='bad';assert(module.new(backend).chat_active()==nil,'Changed writer code must refuse the field')
prefix=layout.writer_prefix;store='bad';assert(module.new(backend).chat_active()==nil,'Changed writer storage offset must refuse the field')
store=layout.writer_store;open=0;reader=module.new(backend)
local api={camera_input={}};assert(reader.attach(api)and api.camera_input.chat_active()==false)
local foreign=function()return true end;api.camera_input.chat_active=foreign
assert(not reader.attach(api)and api.camera_input.chat_active==foreign,'A pre-existing authoritative input reader must remain owned by its provider')
assert(not reader.attach({}),'A late input API must wait without creating a synthetic provider')
print('Game chat context: exact open/closed byte, build/writer guards, loading/generation handling, unavailable fallback and provider ownership passed')

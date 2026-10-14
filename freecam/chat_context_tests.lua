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

-- Escape/settings owns input only while ID 1 is present in its bounded stack.
do
 local menu=module.menu_layout;local current_manager=0x30000000
 local ids={};local depth=0;local unreadable,swap_manager,swap_stack=false,false,false
 local signature_bad=false;local menu_reads=0;local stack_reads=0
 local function stack()
  local bytes={};for i=1,menu.capacity do bytes[i]=integer(ids[i]or 0,4)end
  bytes[#bytes+1]=integer(depth,4);return table.concat(bytes)
 end
 local fixture={module=function()return metadata end,read=function(address,size)
  menu_reads=menu_reads+1
  for _,entry in ipairs(menu.signatures)do if address==base+entry[1]then return signature_bad and'changed'or entry[2]end end
  if address==base+menu.manager then
   if swap_manager and stack_reads>0 then return integer(current_manager+0x1000,8)end
   return integer(current_manager,8)
  end
  if address==current_manager+menu.stack then
   stack_reads=stack_reads+1;if unreadable then return end
   local bytes=stack();if swap_stack and stack_reads%2==0 then bytes=integer(9,4)..bytes:sub(5)end;return bytes
  end
  if address==base+layout.writer then return layout.writer_prefix end
  if address==base+layout.writer+0x66 then return layout.writer_store end
  if address==base+layout.manager then return integer(manager,8)end
  if address==manager+layout.feed+layout.open then return string.char(0)end
  error('Unexpected native menu context read')
 end}
 local function observe(reader)stack_reads=0;return reader.native_menu_active()end
 local reader=module.new(fixture)
 assert(observe(reader)==false,'A retained manager with an empty stack must not mean Escape is open')
 ids={4,6,8};depth=3;assert(observe(reader)==false,'Unrelated native UI IDs must not block camera input')
 for position=1,menu.capacity do ids={4,6,8,9,10};ids[position]=menu.escape;depth=menu.capacity
  assert(observe(reader)==true,'Escape must remain active when a child/options screen covers its stack entry')
 end
 ids={menu.escape};depth=0;assert(observe(reader)==false,'Inactive trailing Escape IDs must be ignored')
 depth=menu.capacity+1;assert(observe(reader)==nil,'Oversized native UI stacks must be unavailable')
 depth=1;unreadable=true;assert(observe(reader)==nil,'An unreadable native UI stack must not grant input')
 unreadable=false;swap_manager=true;assert(observe(reader)==nil,'A manager changed during observation must be rejected')
 swap_manager=false;swap_stack=true;assert(observe(reader)==nil,'A stack changed during observation must be rejected')
 swap_stack=false;assert(observe(reader)==true,'A coherent stack must recover after an observation race')
 current_manager=0;assert(observe(reader)==nil,'Loading without a native UI manager must remain unavailable')
 current_manager=0x30000001;assert(observe(reader)==nil,'An unaligned native UI manager must be refused')
 current_manager=0x30000000
 metadata.stamp=0;local before=menu_reads;assert(observe(reader)==nil and menu_reads==before,'Unsupported builds must not read native menu offsets')
 metadata.stamp=layout.stamp;metadata.image_size=0;assert(observe(reader)==nil and menu_reads==before,'Changed image bounds must not read native menu offsets')
 metadata.image_size=layout.image_size;signature_bad=true
 assert(observe(module.new(fixture))==nil,'Changed native Escape instruction signatures must refuse the stack')
 signature_bad=false
 local calls={};local mouse_focus=true;local show_cursor=false;local release_refused=false;local cursor_refused=false;local bad_readback=false
 local window={set_mouse_focus=function(value)calls[#calls+1]='focus:'..tostring(value);mouse_focus=value;return true end,
  set_show_cursor=function(value)calls[#calls+1]='cursor:'..tostring(value);if cursor_refused then return false end;show_cursor=value;return true end,
  mouse_focus=function()return mouse_focus end,show_cursor=function()return not bad_readback and show_cursor end}
 reader=module.new(fixture,window)
 local input={release=function()calls[#calls+1]='release';if release_refused then return false,'lease busy'end;mouse_focus=true;show_cursor=false;return true end}
 assert(reader.native_menu_handoff(input)and mouse_focus==false and show_cursor==true)
 assert(table.concat(calls,',')=='release,focus:false,cursor:true','Native menu cursor restoration must follow provider lease restoration')
 calls={};release_refused=true;assert(reader.native_menu_handoff(input)==false and #calls==1,'A refused input release must retain ownership without touching the native cursor')
 release_refused=false;cursor_refused=true;calls={};assert(reader.native_menu_handoff(input)==false,'Cursor refusal must remain retryable')
 cursor_refused=false;calls={};assert(reader.native_menu_handoff(input)and mouse_focus==false and show_cursor==true,'A cursor refusal must recover on the next handoff')
 bad_readback=true;assert(reader.native_menu_handoff(input)==false,'An accepted cursor write with failed readback must not acknowledge handoff')
 bad_readback=false;assert(reader.native_menu_handoff(input),'A cursor readback failure must retain a successful retry path')
 ids={};depth=0;calls={};assert(reader.native_menu_handoff(input)and #calls==1,'A closed native menu must only restore the provider lease')
 local attached={camera_input=input};assert(reader.attach(attached)and input.native_menu_active==reader.native_menu_active and type(input.native_menu_handoff)=='function')
 local foreign_reader=function()return true end;local foreign_handoff=function()return true end
 local foreign_input={chat_active=foreign,native_menu_active=foreign_reader,native_menu_handoff=foreign_handoff}
 assert(not reader.attach({camera_input=foreign_input})and foreign_input.chat_active==foreign and foreign_input.native_menu_active==foreign_reader and foreign_input.native_menu_handoff==foreign_handoff,'Attachment must preserve all foreign reader/handoff ownership')
 local reader_only={native_menu_active=foreign_reader};reader.attach({camera_input=reader_only})
 assert(reader_only.native_menu_active==foreign_reader and reader_only.native_menu_handoff==nil,'A foreign menu reader must not acquire this reader\'s cursor handoff')
end
print('Native Escape context: bounded/coherent stack, covered options, build/signature refusal, cursor handoff ordering, retry and foreign ownership passed')

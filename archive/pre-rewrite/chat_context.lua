-- Read-only chat widget predicate adapted from Link's Link to Memory.
-- Copyright (c) 2026 Link. MIT; see vendor/LICENSE-Link.txt.
-- No dependency on the addon, input events or chat messages. Context reads
-- never call game functions; the owned cursor handoff uses Window UI APIs.
local M={}
-- Escape/settings UI stack, read side of MCM's native Escape integration
-- (CowboyBingus, Zero-Clause BSD). The manager persists after the menu closes;
-- only an ID 1 in the current bounded stack proves Escape/options are open.
M.menu_layout={manager=0x347ce28,stack=0x429c,capacity=5,escape=1,
 signatures={{0x18fa514,'\x48\x8b\x1d\x0d\x29\xb8\x01\x4c\x8d\x05\x5a\xf8\x9c\x00\x45\x33'},
 {0x18fa53f,'\x48\x8b\x83\x88\x43\x00\x00\x48\x85\xc0\x74\x10\xc6\x40\x10\x01'}}}
M.layout={stamp=0x6ab3b43f,image_size=0x4744000,manager=0x346d538,feed=0x14498,open=0x139b8,writer=0x185f500,
 writer_prefix='\x48\x89\x5c\x24\x10\x48\x89\x6c\x24\x18\x48\x89\x74\x24\x20\x57\x48\x83\xec\x60\xf3\x0f\x10\x81\xf8\x25\x00\x00\x48\x8b\xd9\x48',
 writer_store='\x40\x88\xbb\xb8\x39\x01\x00'}
local function u32(bytes,offset)
 local a,b,c,d=bytes:byte(offset+1,offset+4);assert(d,'Chat context read truncated');return a+b*256+c*65536+d*16777216
end
local function pointer(bytes)return u32(bytes,0)+u32(bytes,4)*4294967296 end
local function native_backend()
 local ffi=require('ffi')
 pcall(ffi.cdef,[[void *FCH_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");void *FCH_GetCurrentProcess(void) __asm__("GetCurrentProcess");int FCH_ReadProcessMemory(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");]])
 local kernel=ffi.load('kernel32');local process=kernel.FCH_GetCurrentProcess();local buffer=ffi.new('uint8_t[128]');local count=ffi.new('size_t[1]')
 local function read(address,size)
  assert(address>=65536 and address<2^47 and size>0 and size<=128,'Chat context read bounds invalid')
  if kernel.FCH_ReadProcessMemory(process,ffi.cast('void*',address),buffer,size,count)==0 or tonumber(count[0])~=size then return end
  return ffi.string(buffer,size)
 end
 local module_base,identity
 local function module()
  local base=tonumber(ffi.cast('uintptr_t',kernel.FCH_GetModuleHandleA('game.dll')))
  if base<65536 then module_base,identity=nil,nil;return end
  if base==module_base then return identity end
  local header=read(base,64);assert(header and header:sub(1,2)=='MZ','Chat game module header unavailable')
  local pe=u32(header,60);assert(pe>=64 and pe<1048576,'Chat game module PE bounds changed')
  local image=assert(read(base+pe,84),'Chat game module PE header unavailable')
  assert(image:sub(1,4)=='PE\0\0'and image:sub(5,6)=='\x64\x86'and image:sub(25,26)=='\x0b\x02','Chat game module identity changed')
  identity={base=base,stamp=u32(image,8),image_size=u32(image,80)};module_base=base;return identity
 end
 return {module=module,read=read}
end
function M.new(backend,window)
 local self={};local checked;local menu_checked;local init_error
 local handoff;local owned_handoffs=setmetatable({},{__mode='k'})
 if not backend then local ok,value=pcall(native_backend);if ok then backend=value else init_error=tostring(value)end end
 local function active()
  assert(backend,init_error or 'Chat context unavailable')
  local module=backend.module();if not module then return nil,'Game chat module unavailable' end
  assert(module.stamp==M.layout.stamp and module.image_size==M.layout.image_size,'Game chat layout unsupported')
  local base=module.base;assert(base>=65536 and base<2^47,'Game chat module address invalid')
  if checked~=base then
   assert(backend.read(base+M.layout.writer,#M.layout.writer_prefix)==M.layout.writer_prefix,'Chat widget writer identity changed')
   assert(backend.read(base+M.layout.writer+0x66,#M.layout.writer_store)==M.layout.writer_store,'Chat widget field offset changed')
   checked=base
  end
  local address=base+M.layout.manager
  local raw=backend.read(address,8);if not raw then return nil,'Chat manager unavailable' end
  local manager=pointer(raw);if manager==0 then return nil,'Game chat not created yet' end
  assert(manager>=65536 and manager<2^47 and manager%8==0,'Chat manager identity invalid')
  local flag=backend.read(manager+M.layout.feed+M.layout.open,1)
  if not flag then return nil,'Chat widget unavailable' end
  if backend.read(address,8)~=raw then return nil,'Chat widget changed during observation' end
  local value=flag:byte();assert(value==0 or value==1,'Chat widget open state changed type')
  return value==1
 end
 function self.chat_active()
  local ok,value,why=pcall(active);if not ok then self.reason=tostring(value);return nil,self.reason end
  self.reason=why;return value,why
 end
 local function menu_active()
  assert(backend,init_error or'Native menu context unavailable')
  local module=backend.module();if not module then return nil,'Native menu module unavailable'end
  assert(module.stamp==M.layout.stamp and module.image_size==M.layout.image_size,'Native menu layout unsupported')
  local base=module.base;assert(base>=65536 and base<2^47,'Native menu module address invalid')
  if menu_checked~=base then
   for _,entry in ipairs(M.menu_layout.signatures)do
    assert(backend.read(base+entry[1],#entry[2])==entry[2],'Native Escape UI layout changed')
   end
   menu_checked=base
  end
  local address=base+M.menu_layout.manager
  local raw=backend.read(address,8);if not raw then return nil,'Native UI manager unavailable'end
  local manager=pointer(raw);if manager==0 then return nil,'Native UI not created yet'end
  assert(manager>=65536 and manager<2^47 and manager%8==0,'Native UI manager identity invalid')
  local stack=backend.read(manager+M.menu_layout.stack,24);if not stack then return nil,'Native UI stack unavailable'end
  local depth=u32(stack,20);assert(depth<=M.menu_layout.capacity,'Native UI stack bounds changed')
  local active=false
  for index=0,depth-1 do if u32(stack,index*4)==M.menu_layout.escape then active=true end end
  -- Reacquire each observation; a retained manager is not lifetime proof.
  if backend.read(address,8)~=raw or backend.read(manager+M.menu_layout.stack,24)~=stack then return nil,'Native UI changed during observation'end
  return active
 end
 function self.native_menu_active()
  local ok,value,why=pcall(menu_active);if not ok then self.menu_reason=tostring(value);return nil,self.menu_reason end
  self.menu_reason=why;return value,why
 end
 local function handoff_input(input,allow_unfocused)
  assert(type(input)=='table'and type(input.status)=='function','Native menu input ownership unavailable')
  local state=input.status();assert(type(state)=='table','Native menu input ownership unavailable')
  -- A newer frontend owns its Window state even if its values happen to match
  -- ours. Forget our restoration claim before considering the native UI stack.
  if state.available==false then
   if type(input.external_status)=='function'then
    local external=input.external_status()
    assert(type(external)=='table'and type(external.claimed)=='boolean','External cursor ownership unknown')
    if external.claimed then handoff=nil;return false end
    -- A menu waiting to acquire is intent, not a newer cursor writer. Restore
    -- our valid baseline so its first capture can start from gameplay focus.
    assert(external.open==true and external.available==false,'Native menu input availability unknown')
   else handoff=nil;return false end
  else assert(state.available==true,'Native menu input availability unknown')end
  assert(state.active==false and state.native_mode==0,'Native menu input capture is not released')
  if not allow_unfocused then assert(state.focused==true,'Native menu game window is not focused')end
  return true,state
 end
 function self.native_menu_resume(input)
  if not handoff then return true end
  local called,ok,why=pcall(function()
   if not handoff_input(input)then return true end
   assert(handoff.input==input,'Native menu cursor owner changed')
   assert(self.native_menu_active()==false,'Native menu is open or its state is unavailable')
   for _,entry in ipairs(handoff.flags)do
    if entry.written~=nil then
     local current=window[entry.get]();assert(type(current)=='boolean','Native menu cursor state unavailable')
     if current==entry.written and current~=entry.saved then
      assert(window[entry.set](entry.saved)~=false,'Native menu cursor restoration refused')
      assert(window[entry.get]()==entry.saved,'Native menu cursor restoration readback failed')
     end
     -- A changed flag belongs to its newer writer. Other unchanged flags can
     -- still be restored independently (the game may already hide its cursor).
     entry.written=nil
    end
   end
   handoff=nil;return true
  end)
  if not called then return false,tostring(ok)end
  return ok==true,why
 end
 function self.native_menu_handoff(input)
  -- Release Photo's native/cursor lease first, then lend the native menu only
  -- these two Window flags. Keep their original baseline across all retries.
  local called,ok,why=pcall(function()
   local released,reason=input.release();assert(released==true,reason or'Native menu input release pending')
   if self.native_menu_active()~=true then return self.native_menu_resume(input)end
   if not window then return true end
   local owned,state=handoff_input(input,true);if not owned then return true end
   if not handoff then
    local focus,cursor=window.mouse_focus(),window.show_cursor()
    assert(type(focus)=='boolean'and type(cursor)=='boolean','Native menu cursor baseline unavailable')
    handoff={input=input,flags={{get='mouse_focus',set='set_mouse_focus',saved=focus,desired=false},
     {get='show_cursor',set='set_show_cursor',saved=cursor,desired=true}}}
   end
   assert(handoff.input==input,'Native menu cursor owner changed')
   -- Keep the post-release baseline even if focus disappeared before this
   -- handoff. Defer all Window writes until the game is foreground again.
   assert(state.focused==true,'Native menu game window is not focused')
   for _,entry in ipairs(handoff.flags)do
    -- Record the attempted value before calling a setter: it can succeed and
    -- still fail its readback. Cleanup later compares the actual flag first.
    entry.written=entry.desired
    assert(window[entry.set](entry.desired)~=false,'Native menu cursor handoff refused')
    assert(window[entry.get]()==entry.desired,'Native menu cursor readback failed')
   end
   return true
  end)
  if not called then return false,tostring(ok)end
  return ok==true,why
 end
 self.active=self.chat_active
 function self.attach(api)
  local input=api and api.camera_input
  if type(input)~='table'then return false end
  if input.chat_active==nil then input.chat_active=self.chat_active end
  if input.native_menu_active==nil then input.native_menu_active=self.native_menu_active end
  if input.native_menu_active==self.native_menu_active then
   if input.native_menu_handoff==nil and input.native_menu_resume==nil then
    owned_handoffs[input]=function()return self.native_menu_handoff(input)end
    input.native_menu_handoff=owned_handoffs[input]
   end
   if input.native_menu_handoff==owned_handoffs[input]and input.native_menu_resume==nil then
    input.native_menu_resume=function()return self.native_menu_resume(input)end
   end
  end
  return input.chat_active==self.chat_active
 end
 return self
end
return M

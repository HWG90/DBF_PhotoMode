-- BML adapter for the accepted R34 external input service. No in-game DLL.
local M={}
-- Read only the saved HUD action; never execute a settings file. The helper
-- accepts subsets of its whitelist, so excluded keys reach the native game.
function M.hud_keyboard_mask(mask,config,names)
 if type(config)~='string'or #config>131072 then return mask,0,'Unavailable',"Could not read the game's Toggle HUD binding." end
 config=config:gsub('//[^\r\n]*','')
 local misc=config:match('Misc%s*=%s*(%b{})')
 local action=misc and misc:match('ToggleHudVisibility%s*=%s*(%b[])')
 if not action then return mask,0,'Unbound',"Toggle HUD is unbound. Assign it in the game's key bindings." end
 local codes={};for code,name in pairs(names)do codes[name]=code end
 for i=0,9 do codes['num '..i]=96+i;codes['numpad '..i]=96+i end
 for name,code in pairs({['num *']=106,['num +']=107,['num -']=109,['num .']=110,['num /']=111,
  ['right shift']=161,['right ctrl']=163,['right alt']=165,['left control']=162,['right control']=163})do codes[name]=code end
 local bytes={mask:byte(1,32)};local count=0;local labels={}
 local function exclude(code)
  local at=math.floor(code/8)+1;local bit=2^(code%8)
  if bytes[at]and math.floor(bytes[at]/bit)%2==1 then bytes[at]=bytes[at]-bit;count=count+1 end
 end
 for row in action:gmatch('%b{}')do
  local device=row:match('device_type%s*=%s*"([^"]+)"')
  local input=row:match('input%s*=%s*"([^"]+)"')
  if device and input and input~=''and #labels<16 then labels[#labels+1]=device=='Keyboard'and(input=='slash'and'/'or input:upper())or(device..' '..input)end
  if row:match('device_type%s*=%s*"([^"]+)"')=='Keyboard'then
   local code=codes[row:match('input%s*=%s*"([^"]+)"')]
   if code then
    -- Modifier aliases must stay consistent with the helper's mask contract.
    local group=(code==16 or code==160 or code==161)and{16,160,161}or
     (code==17 or code==162 or code==163)and{17,162,163}or
     (code==18 or code==164 or code==165)and{18,164,165}or{code}
    for _,key in ipairs(group)do exclude(key)end
   end
  end
 end
 return string.char(unpack(bytes)),count,#labels>0 and table.concat(labels,' / ')or'Unbound',#labels==0 and"Toggle HUD is unbound. Assign it in the game's key bindings."or nil
end
function M.hud_config(root,open)
 open=open or io.open
 local steam=root:gsub('\\','/'):match('^(.-)/steamapps/common/')
 if not steam then return end
 local function read(path)
  local f=open(path,'rb');if not f then return end
  local s=f:read(131073);f:close();if type(s)=='string'and #s<=131072 then return s end
 end
 local users=read(steam..'/config/loginusers.vdf');if not users then return end
 local selected,only,total=nil,nil,0
 for id,row in users:gmatch('"(7656%d+)"%s*(%b{})')do
  total=total+1;only=id
  if row:match('"MostRecent"%s*"1"')then if selected then return end;selected=id end
 end
 selected=selected or(total==1 and only)
 if not selected then return end
 -- SteamID64 exceeds Lua 5.1's exact double range; subtract in decimal limbs.
 local account=(tonumber(selected:sub(1,-9))-765611979)*100000000+tonumber(selected:sub(-8))-60265728
 if account<0 or account>=4294967296 then return end
 return read(steam..'/userdata/'..string.format('%.0f',account)..'/553850/remote/input_settings.config')
end
function M.new(sr,transport,log,hud_config,names)
 local P={}
local function u32(bytes, at)
    assert(type(bytes) == 'string' and at >= 1 and at + 3 <= #bytes, 'Truncated filesystem reply')
    local a,b,c,d = bytes:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function integer(value)
    assert(value >= 0 and value < 4294967296 and value == math.floor(value), 'Invalid filesystem integer')
    return string.char(value % 256, math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end
local function text(bytes, at)
    local length = u32(bytes, at)
    assert(at + 3 + length <= #bytes, 'Truncated filesystem string')
    return bytes:sub(at + 4, at + 3 + length), at + 4 + length
end
 local proof=transport.exchange(string.rep('\0',12))
 assert(u32(proof,1)==0 and u32(proof,5)==0,'Input helper refused this build')
 assert(u32(proof,9)==sr.Application.process_id(),'Input helper belongs to another process')
 local position
 P.exe,position=text(proof,13)
 P.root=text(proof,position)
local sequence = 0
local function call(operation, path, bytes)
    assert(type(path) == 'string' and #path > 0 and #path <= 32760 and not path:find('%z'), 'Invalid filesystem path')
    sequence = sequence % 4294967295 + 1
    local reply=transport.exchange(integer(sequence)..integer(operation)..integer(#path)..path..(bytes or ''))
    assert(u32(reply, 1) == sequence, 'Stale filesystem response')
    return u32(reply, 5), reply
end
 function P.now()return sr.Application.time_since_launch()end
local pointer={}
local function signed(bytes,at)
    local value=u32(bytes,at)
    return value>=2147483648 and value-4294967296 or value
end
function P.pointer_snapshot()
    local status,reply=call(10,'pointer')
    assert(status==0 and #reply==36,'Pointer service unavailable')
    pointer.valid=u32(reply,9)==1
    pointer.x,pointer.y=signed(reply,13),signed(reply,17)
    pointer.width,pointer.height=u32(reply,21),u32(reply,25)
    pointer.buttons,pointer.wheel=u32(reply,29),signed(reply,33)
    return pointer
end
function P.release_pointer() return call(11,'pointer')==0 end
local camera_pointer={}
function P.camera_snapshot()
    local status,reply=call(12,'pointer-v1')
    assert(status==0 and #reply==44,'Relative pointer service unavailable')
    camera_pointer.valid=u32(reply,9)==1
    camera_pointer.x,camera_pointer.y=signed(reply,13),signed(reply,17)
    camera_pointer.width,camera_pointer.height=u32(reply,21),u32(reply,25)
    camera_pointer.buttons,camera_pointer.wheel=u32(reply,29),signed(reply,33)
    camera_pointer.dx,camera_pointer.dy=signed(reply,37),signed(reply,41)
    return camera_pointer
end
local keyboard_mask=('00331f08ffe1ff03feffff27fffffff7ff0003003f0000fc010000f804000000'):gsub('%x%x',function(value)return string.char(tonumber(value,16))end)
P.keyboard_capture_mask=keyboard_mask
P.base_keyboard_capture_mask=keyboard_mask
P.keyboard_scope='registered gameplay key whitelist; F12/Win/system shortcuts excluded'
local keyboard_owner,keyboard_client=nil,0
local function keyboard_owned(handle)
    return handle~=nil and keyboard_owner and keyboard_owner.handle==handle and keyboard_owner
end
local function keyboard_error(status)
    return string.format('Keyboard request refused (0x%08x)',status)
end
function P.keyboard_prepare()
    if keyboard_owner then return nil,'Keyboard request already owned or restoring' end
    if keyboard_client>=4294967295 then return nil,'Keyboard client IDs exhausted' end
    if hud_config then
        local count
        keyboard_mask,count,P.hud_binding_label,P.hud_binding_warning=M.hud_keyboard_mask(P.base_keyboard_capture_mask,hud_config(),names)
        if keyboard_mask~=P.keyboard_capture_mask then log('Input HUD binding: '..count..' keyboard capture bits excluded; saved Toggle HUD key reaches gameplay')end
        P.keyboard_capture_mask=keyboard_mask
    end
    keyboard_client=keyboard_client+1
    local handle={}
    keyboard_owner={handle=handle,client=keyboard_client,generation=0,attempted=false,sample={}}
    return handle
end
function P.keyboard_acquire(handle)
    local current=keyboard_owned(handle)
    if not current then return false,'Keyboard request not owned' end
    if current.attempted then return current.accepted==true,current.reason end
    current.attempted=true -- An exchange failure may follow native registration.
    local ok,accepted,why=pcall(function()
        local status,reply=call(16,'keyboard-v1',integer(1)..integer(current.client)..keyboard_mask)
        if status~=0 then return false,keyboard_error(status) end
        assert(#reply==56 and u32(reply,9)==1 and u32(reply,13)==current.client,'Invalid keyboard acquisition acknowledgement')
        local generation,state=u32(reply,17),u32(reply,21)
        assert(generation>0 and state>=1 and state<=5,'Invalid keyboard generation or state')
        assert(reply:sub(25,56)==keyboard_mask,'Keyboard capture mask changed')
        current.generation=generation
        if state~=1 and state~=2 then return false,'Keyboard acquisition inactive (state '..state..')' end
        return true
    end)
    if not ok then why=tostring(accepted);accepted=false end
    current.accepted,current.reason=accepted==true,why
    return current.accepted,why
end
function P.keyboard_snapshot(handle,mode)
    local current=keyboard_owned(handle)
    if not current then return nil,'Keyboard request not owned' end
    if not current.accepted or current.generation==0 then return nil,current.reason or 'Keyboard acquisition unacknowledged' end
    local value=mode=='menu'and 0 or mode=='camera'and 1
    if value==nil then return nil,'Unsupported keyboard pointer mode' end
    local ok,result,why=pcall(function()
        local status,reply=call(17,'keyboard-v1',integer(current.client)..integer(current.generation)..integer(value))
        if status~=0 then return nil,keyboard_error(status) end
        assert(#reply==88 and u32(reply,45)==1 and u32(reply,49)==current.generation,'Invalid keyboard snapshot acknowledgement')
        local state=u32(reply,53)
        assert(state>=1 and state<=5,'Invalid keyboard snapshot state')
        local sample=current.sample
        sample.valid=u32(reply,9)==1
        sample.x,sample.y=signed(reply,13),signed(reply,17)
        sample.width,sample.height=u32(reply,21),u32(reply,25)
        sample.buttons,sample.wheel=u32(reply,29),signed(reply,33)
        sample.dx,sample.dy=signed(reply,37),signed(reply,41)
        sample.keyboard_active=state==2
        sample.keyboard_state,sample.keyboard_generation=state,current.generation
        sample.keyboard_keys,sample.keyboard_mask=reply:sub(57,88),keyboard_mask
        if state>=3 then current.accepted=false;current.reason='Keyboard lease inactive (state '..state..')' end
        return sample
    end)
    if not ok then return nil,tostring(result) end
    return result,why
end
function P.keyboard_release(handle)
    local current=keyboard_owned(handle)
    if not current then return false,'Keyboard request not owned' end
    local ok,released,why=pcall(function()
        local status,reply=call(18,'keyboard-v1',integer(current.client)..integer(current.generation))
        if status~=0 then return false,keyboard_error(status) end
        assert(#reply==20 and u32(reply,9)==1 and u32(reply,13)==current.client,'Invalid keyboard release acknowledgement')
        local generation=u32(reply,17)
        assert(current.generation==0 or generation==current.generation,'Stale keyboard release generation')
        return true
    end)
    if not ok then why=tostring(released);released=false end
    if released==true then keyboard_owner=nil;return true end
    current.reason=why or 'Keyboard restoration unacknowledged'
    return false,current.reason
end local acquire,snapshot,release=P.keyboard_acquire,P.keyboard_snapshot,P.keyboard_release
 local last_state,samples,max_ms
 function P.keyboard_acquire(handle)
  local ok,why=acquire(handle)
  last_state,samples,max_ms=nil,0,0
  log('Input keyboard acquisition '..(ok and 'acknowledged' or 'refused: '..tostring(why)))
  return ok,why
 end
 function P.keyboard_snapshot(handle,mode)
  local started=P.now()
  local value,why=snapshot(handle,mode)
  samples=samples+1;max_ms=math.max(max_ms,(P.now()-started)*1000)
  local state=value and value.keyboard_state or tostring(why)
  if state~=last_state then last_state=state;log('Input keyboard state='..tostring(state)..' mode='..tostring(mode))end
  return value,why
 end
 function P.keyboard_release(handle)
  local ok,why=release(handle)
  log('Input keyboard restoration '..(ok and 'acknowledged' or 'pending: '..tostring(why))..string.format('; samples=%d max_exchange_ms=%.3f',samples or 0,max_ms or 0))
  return ok,why
 end
 return P
end
function M.connect(mod,sr)
 local config=mod.require('src/wjl_helper_startup.lua').config(mod,sr)
 local transport=mod.require('src/vendor/wjl_transport.lua')(config)
 local names=mod.require('src/steam_input.lua').key_names
 local ok,platform=pcall(M.new,sr,transport,mod.log,function()return M.hud_config(mod.game_root or '')end,names)
 if not ok then transport.close();error(platform)end
 mod.game_root=platform.root
 mod.render_contract_verified=config.contract_ready and config.contract_ready()==true or false
 mod.render_contract_id=mod.render_contract_verified and config.contract_id or nil
 mod.log('Windows stock renderer contract: '..(mod.render_contract_verified and 'verified' or 'unavailable; scene effects remain disabled'))
 local capture=mod.require('src/vendor/wjl_capture.lua').new(platform,sr.Window,mod.log)
 local service,driver=mod.require('src/vendor/wjl_input_service.lua').new(platform,sr.Window,capture)
 local close=driver.close
 function driver.close()
  local restored,why=close()
  if restored then transport.close()end
  return restored,why
 end
 mod.log('Input: WJL keyboard service connected; process proof verified')
 return service,driver
end
return M

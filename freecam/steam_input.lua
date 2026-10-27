-- Consumer of LLL's shared, token-owned input service. Never opens a helper
-- connection, changes Window flags, or approximates raw motion from cursor XY.
local M={}
local names={[8]='backspace',[9]='tab',[13]='enter',[16]='left shift',[17]='left ctrl',[18]='left alt',[19]='pause',
 [20]='caps lock',[27]='esc',[32]='space',[33]='page up',[34]='page down',[35]='end',[36]='home',
 [37]='left',[38]='up',[39]='right',[40]='down',[45]='insert',[46]='delete',
 [186]='semicolon',[187]='equal',[188]='comma',[189]='minus',[190]='period',[191]='slash',
 [192]='backtick',[219]='open bracket',[220]='backslash',[221]='close bracket',[222]='quote'}
for code=48,57 do names[code]=string.char(code)end
for code=65,90 do names[code]=string.char(code+32)end
for code=112,135 do names[code]='f'..(code-111)end
-- Further keys MCM can bind, by the engine's names (Keyboard index = virtual key).
for code,name in pairs({[12]='clear',[44]='print screen',[91]='left system',[92]='right system',[93]='context menu',
 [106]='numpad *',[107]='numpad +',[109]='numpad -',[110]='numpad .',[111]='numpad /',[144]='num lock',[145]='scroll lock',
 [160]='left shift',[161]='right shift',[162]='left ctrl',[163]='right ctrl',[164]='left alt',[165]='right alt'})do names[code]=name end
for code=96,105 do names[code]='numpad '..(code-96)end
-- Engine key names by virtual key, for hosts that bind keys by name. A name
-- maps back to one key: where a left-hand key repeats a generic modifier's
-- name, the generic (lower) code keeps it, independent of table order.
M.key_names={}
do
 local first={}
 for code,name in pairs(names)do if not first[name]or code<first[name]then first[name]=code end end
 for name,code in pairs(first)do M.key_names[code]=name end
end
local mouse_bits={[1]=1,[2]=2,[4]=4,[5]=8,[6]=16}
local modifiers={[16]={160,161},[17]={162,163},[18]={164,165}}
local zero_mask=string.rep('\0',32)
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end
local function bit(bytes,code)return math.floor(bytes:byte(math.floor(code/8)+1)/2^(code%8))%2==1 end
function M.new(sr,service,recovery,policy)
 assert(type(service)=='table'and service.version==1,'LLL shared input service v1 is required')
 local self={};local token,mode,release_wait,blocked,first_sample
 local keyboard_required=type(policy)=='table'and policy.require_keyboard==true
 local keyboard_denied=false
 local keyboard_requested,keyboard_generation,keyboard_keys,keyboard_mask,keyboard_contract_mask,capture_fault
 local ids,keys,output={},{},{}
 local sampled,sample_result,wheel_taken,foreground=false,false,false,false
 local clip_attempted=false
 local function pointer_clip(active)
  if not(policy and type(policy.pointer_clip)=='function')then return true end
  if not active and not clip_attempted then return true end
  if active then clip_attempted=true end
  local called,ok=pcall(policy.pointer_clip,active)
  if not called or ok~=true then return false,'Photo pointer confinement is unconfirmed'end
  if not active then clip_attempted=false end
  return true
 end
 local function owns()return token~=nil and service.owns(token)==true end
 local function invalidate()
  for key in pairs(keys)do keys[key]=nil end
  for key in pairs(output)do output[key]=nil end
  sampled,sample_result,wheel_taken=false,false,false;keyboard_keys,keyboard_mask=nil,nil
 end
 local function retired()
  token,mode,release_wait,blocked,first_sample=nil,nil,nil,nil,nil
  keyboard_requested,keyboard_generation,keyboard_contract_mask,capture_fault=nil,nil,nil,nil;invalidate()
 end
 function self.release()
  local clipped,issue=pointer_clip(false)
  if not clipped then release_wait=true;invalidate();return false,issue end
  if not token then retired();return true end
  if not owns()then
   local state=service.status()
   if not(state.owner=='dbf_freecam'and state.pending_restore==true)then
    retired();return true
   end
  end
  local called,ok,why=pcall(service.release,token)
  if called and ok~=true and why=='Keyboard request refused (0x00000005)'and recovery then
   local recovered,done,reason=pcall(recovery.retire_denied,service,token)
   if recovered and done==true then retired();return true end
   if not recovered then why=done elseif reason then why=reason end
  end
  if not called or ok~=true then
   release_wait=true;invalidate()
   if not called then return false,ok end
   if why~=nil then return false,why end
   return false,'Photo input restoration is unconfirmed'
  end
  retired()
  return true
 end
 function self.set_mode(value)
  assert(value=='menu'or value=='camera','Invalid Photo input mode')
  if keyboard_required and not(service.capabilities and service.capabilities.keyboard==true)then
   return false,'Native keyboard isolation is required; update the shared input service'
  end
  local capture_keyboard=not keyboard_denied and service.capabilities and service.capabilities.keyboard==true
  local canonical_mask=service.capabilities and service.capabilities.keyboard_mask
  if owns()and not release_wait and not capture_fault and keyboard_requested==capture_keyboard and service.capabilities[value]==true and
   (not capture_keyboard or canonical_mask==keyboard_contract_mask)then
   if mode==value then return true end
   if capture_keyboard and type(service.set_mode)=='function'then
    local called,ok,why=pcall(service.set_mode,token,value)
    invalidate()
    if not called or ok~=true then
     release_wait=true;capture_fault='Photo input mode change is unconfirmed'
     return false,called and why or ok
    end
    mode,blocked,first_sample=value,true,true;return true
   end
  end
  local ok,why=self.release();if not ok then return false,why end
  if not service.capabilities or service.capabilities[value]~=true then return false,'LLL '..value..' input is unavailable'end
  if service.capabilities.keyboard~=nil and type(service.capabilities.keyboard)~='boolean'then return false,'Invalid LLL keyboard capability'end
  if capture_keyboard and(type(canonical_mask)~='string'or #canonical_mask~=32 or canonical_mask==zero_mask)then
   return false,'LLL canonical keyboard mask is unavailable'
  end
  local cleanup
  keyboard_requested=capture_keyboard;keyboard_contract_mask=capture_keyboard and canonical_mask or nil
  if capture_keyboard then token,why,cleanup=service.acquire('dbf_freecam',value,nil,{keyboard=true})
  else token,why,cleanup=service.acquire('dbf_freecam',value,nil)end
  if not token then
   if cleanup then token=cleanup;release_wait=true end
   if capture_keyboard and why=='Keyboard request refused (0x00000005)'then
    local restored=self.release()
    local status=service.status()
    if restored and type(status)=='table'and status.owner==nil and status.pending_restore==false then
     if keyboard_required then return false,'Native keyboard isolation was denied; Photo Mode stayed closed'end
     keyboard_denied=true
     self.keyboard_fallback='Native keyboard capture was denied; engine key input is active'
     return self.set_mode(value)
    end
   end
   return false,why
  end
  if capture_keyboard then keyboard_contract_mask=service.capabilities.keyboard_mask end
  mode,blocked,first_sample=value,true,true;invalidate()
  return true
 end
 function self.frame()
  invalidate()
  foreground=sr.Window.has_focus()==true
  local ok,why=pointer_clip(foreground and owns()and not release_wait and not capture_fault)
  if not ok then capture_fault=why end
 end
 local function fail(reason,detail)
  output.valid=false;output.reason=reason;output.detail=detail
  if keyboard_requested then capture_fault=reason;keyboard_keys,keyboard_mask=nil,nil end
  return nil,reason
 end
 function self.sample()
  if sampled then return sample_result and output or nil,output.reason end
  sampled=true
  if capture_fault then return fail(capture_fault)end
  if release_wait then return fail('Photo input restoration pending')end
  if keyboard_requested and(not service.capabilities or service.capabilities.keyboard~=true or service.capabilities.keyboard_mask~=keyboard_contract_mask)then
   return fail('LLL keyboard capture contract changed')
  end
  if not owns()then return fail('Photo input lease revoked')end
  local called,source,why=pcall(service.snapshot,token)
  if not called then return fail('Photo input snapshot failed',source)end
  if not source then return fail(why or'Pointer sample unavailable')end
  if type(source)~='table'then return fail('Invalid Photo input snapshot')end
  if keyboard_requested then
   local state,active,generation=source.keyboard_state,source.keyboard_active,source.keyboard_generation
   if type(state)~='number'or state%1~=0 or state<1 or state>5 or type(active)~='boolean'or
    type(source.keyboard_keys)~='string'or #source.keyboard_keys~=32 or type(source.keyboard_mask)~='string'or #source.keyboard_mask~=32 or
    not finite(generation)or generation%1~=0 or generation<=0 or generation>4294967295 or
    keyboard_generation and generation~=keyboard_generation then
    return fail('Invalid captured keyboard sample')
   end
   if source.keyboard_mask~=keyboard_contract_mask then return fail('Captured keyboard mask does not match the broker contract')end
   keyboard_generation=generation
   if state==1 and active==false and source.valid==false then
    output.valid=false;output.pending=true;output.reason='Keyboard capture is arming'
    output.x,output.y,output.dx,output.dy,output.buttons,output.wheel=0,0,0,0,0,0
    output.click,output.right=false,false;sample_result=true;return output
   end
   if state~=2 or active~=true or source.valid~=true then return fail('Captured keyboard is unavailable')end
   keyboard_keys,keyboard_mask=source.keyboard_keys,source.keyboard_mask
  end
  if source.valid==false then return fail('Pointer sample is invalid')end
  if not(finite(source.x)and finite(source.y)and finite(source.width)and source.width>0 and finite(source.height)and source.height>0
   and finite(source.buttons)and finite(source.wheel))then return fail('Invalid pointer sample')end
  if blocked and source.buttons==0 then blocked=false end
  local width,height=sr.Gui.resolution()
  output.valid=true;output.x=source.x*width/source.width;output.y=height-source.y*height/source.height
  output.buttons=blocked and 0 or source.buttons;output.wheel=blocked and 0 or source.wheel
  output.click=math.floor(output.buttons)%2==1;output.right=math.floor(output.buttons/2)%2==1
  output.dx,output.dy=0,0
  if mode=='camera'then
   if not(service.capabilities.relative_mouse==true and finite(source.dx)and finite(source.dy))then
    return fail('Raw camera input unavailable')
   end
   output.dx,output.dy=first_sample and 0 or source.dx,first_sample and 0 or source.dy
  end
  first_sample=false
  sample_result=true
  return output
 end
 function self.down(code)
  if not foreground then return false end
  if type(code)~='number'or code%1~=0 or code<0 or code>255 then return false end
  if keys[code]~=nil then return keys[code]end
  local mask=mouse_bits[code]
  if mask then
   local sample=self.sample();return sample~=nil and math.floor(sample.buttons/mask)%2==1 or false
  end
  if keyboard_requested then
   local sample=self.sample()
   if not sample or sample.pending then keys[code]=false;return false end
   local family=modifiers[code]
   if bit(keyboard_mask,code)then
    local value=bit(keyboard_keys,code)
    if family then value=value or bit(keyboard_keys,family[1])or bit(keyboard_keys,family[2])end
    keys[code]=value==true;return keys[code]
   end
  end
  local id=ids[code]
  if id==nil then
   local ok,value=false,nil
   if names[code]then ok,value=pcall(sr.Keyboard.button_id,names[code])end
   id=ok and type(value)=='number'and value or false;ids[code]=id
  end
  local value=id~=false and sr.Keyboard.button(id)
  keys[code]=value==true or type(value)=='number'and value>.5 or false
  return keys[code]
 end
 function self.wheel()
  if wheel_taken then return 0 end;wheel_taken=true
  local sample=self.sample();return sample and sample.wheel or 0
 end
 function self.keyboard_isolated()return owns()and not release_wait and not capture_fault and keyboard_requested==true and keyboard_generation~=nil and keyboard_keys~=nil and keyboard_mask==keyboard_contract_mask end
 function self.status()return{owner=owns()and'dbf_freecam'or nil,mode=mode,required_keyboard=keyboard_required,requested_keyboard=keyboard_requested==true,keyboard_isolated=self.keyboard_isolated(),pending_restore=release_wait==true,reason=capture_fault}end
 function self.owns()return owns()and not release_wait and not capture_fault end
 function self.pending_restore()return token~=nil and release_wait==true end
 function self.focused()return foreground end
 function self.mode()return mode end
 return self
end
return M

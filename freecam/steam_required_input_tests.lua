-- Native broker denial must never silently enable gameplay keys for Photo Mode.
local source=assert(io.open('freecam/steam_input_refusal_tests.lua','rb')):read('*a')
source=source:gsub('local function fixture%(failure,revision%)','local function fixture(failure,revision,policy)')
source=source:gsub('input_factory.new%(sr,service,recovery%)','input_factory.new(sr,service,recovery,policy)')
source=source..[[
local input,service,inspect=fixture('denied','R35-26088801-cffi-insert-fix.2',{require_keyboard=true})
local ok,why=input.set_mode('menu')
assert(ok==false and why:find('isolation was denied',1,true),'Current Photo Mode cannot accept engine-key fallback')
assert(not input.keyboard_fallback and service.status().owner==nil and not service.status().pending_restore)
assert(inspect(),'Rejected native keyboard capture must restore pointer focus')
assert(input.release())
input,service,inspect=fixture('lost','R35-26088801-cffi-insert-fix.2',{require_keyboard=true})
assert(not input.set_mode('menu')and service.status().pending_restore,'Unknown native acquisition must retain cleanup')
]]
assert(loadstring(source,'@strict-input-refusal-tests'))()
local factory=dofile('freecam/steam_input.lua')
local token={};local mask=string.rep('\255',32);local keys=string.rep('\0',8)..'\2'..string.rep('\0',23)
local owned,releases,engine_reads,acquisitions=true,0,0,0
local sample={x=5,y=10,width=100,height=100,buttons=0,wheel=0,dx=0,dy=0,valid=true,
 keyboard_state=2,keyboard_active=true,keyboard_generation=99,keyboard_keys=keys,keyboard_mask=mask}
local service={version=1,capabilities={menu=true,camera=true,relative_mouse=true,keyboard=true,keyboard_mask=mask}}
function service.acquire(owner,mode,unused,options)assert(owner=='dbf_freecam'and options.keyboard);owned=true;acquisitions=acquisitions+1;return token end
function service.owns(t)return owned and t==token end
function service.status()return{owner=owned and'dbf_freecam'or nil,pending_restore=false}end
function service.release(t)assert(t==token);owned=false;releases=releases+1;return true end
function service.snapshot(t)assert(t==token and owned);return sample end
function service.set_mode(t,mode)assert(t==token and owned and mode=='camera');return true end
local sr={Window={has_focus=function()return true end},Gui={resolution=function()return 1920,1080 end},
 Keyboard={button_id=function()engine_reads=engine_reads+1;return 1 end,button=function()engine_reads=engine_reads+1;return true end}}
local input=factory.new(sr,service,nil,{require_keyboard=true})
assert(input.set_mode('menu'));assert(not input.keyboard_isolated(),'Acquisition is not an accepted sample')
input.frame();assert(input.sample()and input.keyboard_isolated())
assert(input.down(65)and not input.down(87)and engine_reads==0,'Captured menu keys must use physical broker snapshot only')
assert(input.status().required_keyboard and input.status().requested_keyboard and input.status().keyboard_isolated)
assert(input.set_mode('camera')and acquisitions==1,'Mode switch must retain the owned native keyboard generation')
input.frame();assert(input.sample()and input.keyboard_isolated())
sample.keyboard_generation=100;input.frame();assert(not input.sample()and not input.keyboard_isolated()and not input.owns())
assert(input.release()and releases==1 and not input.status().keyboard_isolated)
service.capabilities.keyboard=false
input=factory.new(sr,service,nil,{require_keyboard=true})
local ok,why=input.set_mode('camera');assert(ok==false and why:find('isolation is required',1,true))
assert(service.status().owner==nil and acquisitions==1,'Missing isolation capability must not acquire a pointer-only lease')
print('WJ mandatory keyboard isolation: accepted samples/mode switching, denial cleanup, capability refusal, generation failure and zero engine-key reads passed')

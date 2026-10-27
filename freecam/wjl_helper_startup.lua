-- One-shot helper extraction/startup. Child inherits the game's integrity level.
local M={}
local launch_sequence=0
function M.config(mod,sr)
 local payload=mod.require('src/wjl_helper_payload.lua')
 assert(payload.name:match('^wjl_steam_service_%x+%.exe$')and payload.sha256:match('^%x+$')and #payload.sha256==64)
 local directory=assert(os.getenv('APPDATA'))..'/Arrowhead/Helldivers2/'
 local path=directory..payload.name
 local bytes=payload.hex:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
 local existing=io.open(path,'rb')
 if existing then local body=existing:read('*a');existing:close();assert(body==bytes,'Bundled WJL helper cache differs; refusing to execute')
 else local file=assert(io.open(path,'wb'));assert(file:write(bytes));assert(file:close())end
 local pid=sr.Application.process_id();assert(type(pid)=='number'and pid>0 and pid==math.floor(pid))
 launch_sequence=launch_sequence+1
 local token='wjl_input_'..pid..'_'..os.time()..'_'..launch_sequence
 local contract=mod.require('src/engine_render_contract.lua')
 assert(type(contract.id)=='string'and #contract.id==64 and contract.id:match('^[0-9a-f]+$'),'Invalid render contract identity')
 assert(type(contract.checks)=='table'and #contract.checks>0 and #contract.checks<=32,'Invalid render contract checks')
 local checks,total={},0
 for _,row in ipairs(contract.checks)do
  assert(type(row.file)=='string'and(row.file=='bundles.nxa'or row.file:match('^bundles%.%d+%.nxa$')),'Invalid stock witness path')
  assert(type(row.offset)=='number'and row.offset>=0 and row.offset==math.floor(row.offset)and row.offset<2^53,'Invalid stock witness offset')
  assert(type(row.size)=='number'and row.size>0 and row.size==math.floor(row.size)and row.size<=16*1024*1024,'Invalid stock witness size')
  assert(type(row.sha256)=='string'and #row.sha256==64 and row.sha256:match('^[0-9a-f]+$'),'Invalid stock witness hash')
  total=total+row.size
  checks[#checks+1]=row.file..':'..string.format('%.0f',row.offset)..':'..row.size..':'..row.sha256
 end
 assert(total<=16*1024*1024,'Stock renderer verification exceeds its read budget')
 local witness=contract.id..'|'..token
 assert(type(contract.resource)=='string'and contract.resource:match('^%x+$')and #contract.resource==16,'Invalid renderer resource')
 assert(type(contract.resource_type)=='string'and contract.resource_type:match('^%x+$')and #contract.resource_type==16,'Invalid renderer resource type')
 -- cmd.exe ships with Windows and with Wine/Proton; PowerShell does not ship with Proton
 -- and some Windows installs block it. start /wait returns once the helper's --launch
 -- copy has seen the service ready (or exit). The helper resolves the game from its
 -- process id and checks the stock renderer contract itself.
 local exe=path:gsub('/','\\')
 assert(not exe:find('[%%"\r\n]'),'The settings folder path cannot be passed to cmd.exe')
 local launcher='start "" /wait "'..exe..'" --launch --game-pid '..pid..' --pipe '..token..' --contract '..contract.id..
  ' --contract-resource '..contract.resource..' --contract-type '..contract.resource_type..' --check '..table.concat(checks,' --check ')
 assert(#launcher<8000,'WJL launcher exceeds the cmd.exe command-line limit')
 -- The helper truncates its log when it starts; a missing log means it never ran.
 local local_data=os.getenv('LOCALAPPDATA')
 local service_log=local_data and local_data:gsub('\\','/')..'/WJL/Helldivers2/Steam/service.log'
 if service_log then os.remove(service_log)end
 return {pipe=token,contract_id=contract.id,launcher=launcher,
  contract_ready=function()local f=io.open(directory..'wjl-render-contract-'..pid..'.txt','rb');if not f then return false end;local body=f:read(256);f:close();return body==witness end,
  failure=function()local f=service_log and io.open(service_log,'rb');if not f then return 'No WJL helper log written'end;local body=f:read(4096);f:close();return body end}
end
return M

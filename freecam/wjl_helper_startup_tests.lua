local startup=dofile('freecam/wjl_helper_startup.lua')
local payload={name='wjl_steam_service_0123456789abcdef.exe',sha256=string.rep('a',64),hex='4d5a0102'}
local files={};local writes=0
local old_open,old_env=io.open,os.getenv
os.getenv=function(name)assert(name=='APPDATA');return 'C:/User Space/Settings'end
io.open=function(path,mode)
 if mode=='rb'then if not files[path]then return nil end;return{read=function()return files[path]end,close=function()return true end}end
 assert(mode=='wb');return{write=function(_,body)files[path]=body;if path:match('%.exe$')then writes=writes+1 end;return true end,close=function()return true end}
end
local contract={id=string.rep('b',64),checks={{file='bundles.nxa',offset=0,size=8,sha256=string.rep('c',64)}}}
local mod={require=function(name)if name=='src/engine_render_contract.lua'then return contract end;assert(name=='src/wjl_helper_payload.lua');return payload end}
local sr={Application={process_id=function()return 1234 end}}
local config=startup.config(mod,sr);assert(config.pipe:match('^wjl_input_1234_%d+_%d+$'))
assert(config.launcher:match('^powershell.exe %-WindowStyle Hidden %-NoProfile %-NonInteractive %-EncodedCommand [%w+/=]+$')and #config.launcher<4096,'Bootstrap must fit cmd.exe command-line limits')
assert(writes==1);startup.config(mod,sr);assert(writes==1,'Unchanged helper is never rewritten')
for key in pairs(files)do files[key]='foreign'end
assert(not pcall(startup.config,mod,sr),'Changed helper must be refused before execution')
io.open,os.getenv=old_open,old_env
print('Bundled WJL startup: exact extraction/cache, foreign-file refusal and encoded one-shot launcher passed')

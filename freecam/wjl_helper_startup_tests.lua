local startup=dofile('freecam/wjl_helper_startup.lua')
local payload={name='wjl_steam_service.exe',sha256=string.rep('a',64),hex='4d5a0102'}
local files={};local writes=0;local removed={}
local old_open,old_env,old_remove,old_rename=io.open,os.getenv,os.remove,os.rename
local locked={}
local env={APPDATA='C:/User Space/Settings',LOCALAPPDATA='C:\\User Space\\Local'}
os.getenv=function(name)return env[name]end
os.remove=function(path)removed[#removed+1]=path;if locked[path]then return nil,'in use'end;files[path]=nil;return true end
os.rename=function(from,to)if files[to]or not files[from]then return nil end;files[to],files[from]=files[from],nil;return true end
io.open=function(path,mode)
 if mode=='rb'then if not files[path]then return nil end;return{read=function()return files[path]end,close=function()return true end}end
 assert(mode=='wb');return{write=function(_,body)files[path]=body;if path:match('%.exe')then writes=writes+1 end;return true end,close=function()return true end}
end
local contract={id=string.rep('b',64),resource='ee6b1ba7e22d71ed',resource_type='27862fe24795319c',
 checks={{file='bundles.nxa',offset=0,size=8,sha256=string.rep('c',64)},{file='bundles.17.nxa',offset=475061920,size=81198,sha256=string.rep('d',64)}}}
local mod={require=function(name)if name=='src/engine_render_contract.lua'then return contract end;assert(name=='src/wjl_helper_payload.lua');return payload end}
local sr={Application={process_id=function()return 1234 end}}
local config=startup.config(mod,sr);assert(config.pipe:match('^wjl_input_1234_%d+_%d+$'))
-- cmd.exe only: no script host, no generated script file. cmd runs the helper itself
-- (never start, whose shell fallback shows dialogs); the outer quotes are cmd /c's.
assert(config.launcher=='""C:\\User Space\\Settings\\Arrowhead\\Helldivers2\\wjl_steam_service.exe" --launch --game-pid 1234 --pipe '..config.pipe..
 ' --contract '..contract.id..' --contract-resource ee6b1ba7e22d71ed --contract-type 27862fe24795319c --check bundles.nxa:0:8:'..string.rep('c',64)..
 ' --check bundles.17.nxa:475061920:81198:'..string.rep('d',64)..'"',config.launcher)
assert(not config.launcher:lower():find('powershell',1,true)and not config.launcher:find('start',1,true)and #config.launcher<8000)
for path in pairs(files)do assert(path:match('%.exe$'),'Only the helper is written: '..path)end
-- A stale helper log never stands in for this launch's diagnostics.
assert(removed[1]=='C:/User Space/Local/WJL/Helldivers2/Steam/service.log')
-- Earlier releases' helpers and 1.3.0's PowerShell log go, by exact name; nothing else.
assert(#removed==1+#startup.retired)
for index,name in ipairs(startup.retired)do assert(removed[1+index]=='C:/User Space/Settings/Arrowhead/Helldivers2/'..name)end
assert(startup.retired[#startup.retired]=='wjl_startup.log')
for _,name in ipairs(startup.retired)do assert(name=='wjl_startup.log'or name:match('^wjl_steam_service_%x+%.exe$'))end
assert(config.failure()=='No WJL helper log written')
files[removed[1]]='Refused: installed game hashes do not match this service build\n'
assert(config.failure():match('^Refused'))
-- The proof binds the contract to this launch's pipe token.
assert(config.contract_ready()==false)
files['C:/User Space/Settings/Arrowhead/Helldivers2/wjl-render-contract-1234.txt']=contract.id..'|'..config.pipe
assert(config.contract_ready()==true)
files['C:/User Space/Settings/Arrowhead/Helldivers2/wjl-render-contract-1234.txt']=contract.id..'|wjl_input_1234_0_0'
assert(config.contract_ready()==false,'A proof from another launch is refused')
assert(writes==1);startup.config(mod,sr);assert(writes==1,'Unchanged helper is never rewritten')
-- cmd.exe would expand %VARIABLE% inside the quoted path.
env.APPDATA='C:/100%Settings';assert(not pcall(startup.config,mod,sr),'A path cmd.exe would rewrite is refused')
env.APPDATA='C:/User Space/Settings'
contract.checks[1].sha256=string.rep('C',64);assert(not pcall(startup.config,mod,sr),'The helper takes lowercase hashes only')
contract.checks[1].sha256=string.rep('c',64)
-- One file, one name: a copy from another release (or damaged) is replaced before any start.
local helper='C:/User Space/Settings/Arrowhead/Helldivers2/wjl_steam_service.exe'
files[helper]='foreign';startup.config(mod,sr)
assert(files[helper]=='\77\90\1\2'and not files[helper..'.new'],'An older helper is replaced, never run')
-- Windows keeps a running program's file: an older helper still running is not run either.
files[helper]='older';locked[helper]=true
local ok,why=pcall(startup.config,mod,sr)
assert(not ok and why=='An older WJL helper is still running; restart the game'and files[helper]=='older'and not files[helper..'.new'],tostring(why))
locked[helper]=nil
io.open,os.getenv,os.remove,os.rename=old_open,old_env,old_remove,old_rename
print('Bundled WJL startup: one helper file under one name, replaced when it differs, refused while an older one runs, cmd.exe launcher without PowerShell, fresh helper log and launch-bound renderer proof passed')

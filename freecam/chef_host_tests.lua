-- chef_host.lua: files, screenshots, the held mouse, drawing.
local host=dofile('freecam/chef_host.lua')

-- Files: a .tmp renamed over its file lands in the file.
do
 local disk,opens={},{}
 local function open(path,mode)
  opens[#opens+1]=path..' '..mode
  if mode:find('[wa]')then
   local parts={};return{write=function(_,s)parts[#parts+1]=s;return true end,close=function()disk[path]=table.concat(parts);return true end}
  end
  if not disk[path]then return nil,'missing'end
  local data=disk[path];return{read=function()local d=data;data=nil;return d end,close=function()return true end}
 end
 local fs=host.files(open)
 local f=fs.open('C:/game/x.ini.tmp','wb');f:write('a=1\n','b=2\n');assert(f:close())
 assert(#opens==0,'A .tmp never reaches the disk')
 local r=fs.open('C:/game/x.ini.tmp','rb');assert(r:read('*a')=='a=1\nb=2\n')
 assert(fs.rename('C:/game/x.ini','C:/game/x.ini.bak')==true and disk['C:/game/x.ini.bak']==nil,'A real file stays in place')
 assert(fs.rename('C:/game/x.ini.tmp','C:/game/x.ini')==true and disk['C:/game/x.ini']=='a=1\nb=2\n')
 assert(fs.staged()==0 and fs.remove('C:/game/x.ini.bak')==true)
 assert(fs.open('C:/game/x.ini','rb'):read()=='a=1\nb=2\n')
 -- store.lua saves and loads through the scope.
 local scope_io,scope_os=host.scope(io,os,fs)
 local env=setmetatable({io=scope_io,os=scope_os},{__index=_G})
 local chunk=assert(loadfile('freecam/vendor/store.lua'));setfenv(chunk,env)
 local store=chunk().new('C:/game')
 assert(store.save('dbf_freecam_lua51',{fov=55,label='Wide',hide_hud=true}))
 local values=store.load('dbf_freecam_lua51')
 assert(values.fov==55 and values.label=='Wide'and values.hide_hud==true,'Settings round trip')
 assert(store.save('dbf_freecam_lua51',{fov=60}))
 assert(store.load('dbf_freecam_lua51').fov==60 and store.load('dbf_freecam_lua51').label==nil,'The second save replaces the first')
 for _,line in ipairs(opens)do assert(not line:find('%.tmp')and not line:find('%.bak'),'Disk saw a staged file: '..line)end
end

-- Screenshots: the loader's file name comes back.
do
 assert(host.capture({},'C:/game')==nil,'No chef.capture: no service')
 local n,refuse=0,nil
 local chef={capture=function()n=n+1;if refuse then return nil,refuse end;return string.format('mods_2fgoose_2fwar_5fjournalist_capture_%02d.dds',n)end}
 local service=host.capture(chef,'C:/game/')
 assert(service.version==1 and service.output_directory=='C:/game'and service.capabilities.format=='dds'and service.capabilities.max_jobs==1)
 local token=service.new_job_token()
 assert(service.request({job_token='old',output_token='War-Journalist-1.dds',output_path='C:/game/War-Journalist-1.dds'})==nil)
 local reply=service.request({job_token=token,output_token='War-Journalist-1.dds',output_path='C:/game/War-Journalist-1.dds'})
 assert(reply.state=='succeeded'and reply.output_path=='C:/game/War-Journalist-1.dds'and reply.job_token==token)
 assert(service.saved_name('C:/game/War-Journalist-1.dds')=='C:/game/mods_2fgoose_2fwar_5fjournalist_capture_01.dds')
 assert(service.status(token,'War-Journalist-1.dds').state=='succeeded')
 local retired,last=service.cancel(token,'War-Journalist-1.dds');assert(retired==true and last.state=='succeeded')
 refuse='one capture a second at most'
 token=service.new_job_token()
 reply=service.request({job_token=token,output_token='War-Journalist-2.dds',output_path='C:/game/War-Journalist-2.dds'})
 assert(reply.state=='failed'and reply.reason==refuse,'A refusal is reported as the loader said it')
end

-- Depth: chef.capture('depth') from Chef 1.4.2 on. Older loaders get no depth service.
do
 assert(host.depth({capture=function()end,loader_version='1.4.1'},'C:/game')==nil,'1.4.1 has no depth capture')
 assert(host.depth({loader_version='1.4.2'},'C:/game')==nil,'No chef.capture: no service')
 local words,refuse={},nil
 local chef={loader_version='1.4.2',capture=function(what)words[#words+1]=what;if refuse then return nil,refuse end;return'goose_war_journalist_depth_01.dds'end}
 local depth=host.depth(chef,'C:/game/')
 assert(depth and depth.async==true and depth.wait==5)
 assert(depth.last==nil,'Nothing asked yet')
 assert(depth.request()=='C:/game/goose_war_journalist_depth_01.dds'and words[1]=='depth')
 assert(depth.last=='C:/game/goose_war_journalist_depth_01.dds','last is the newest file asked for')
 refuse='one capture a second at most';local path,why=depth.request();assert(path==nil and why==refuse and depth.last=='C:/game/goose_war_journalist_depth_01.dds','A refusal leaves last alone')
 chef.capture=function()error('boom')end;path,why=depth.request();assert(path==nil and why:find('boom',1,true))
 assert(host.depth({capture=function()end,loader_version='1.5.0'},'C:/game')and host.depth({capture=function()end,loader_version='2.0'},'C:/game'),'Newer loaders keep it')
end

-- Input: the hold comes and goes with the lease; the cursor moves by chef.mouse_delta.
do
 local engine_input=dofile('freecam/engine_input.lua')
 local axis_reads=0
 local sr={Gui={resolution=function()return 1920,1080 end},
  Mouse={axis_index=function(n)return({mouse=0,wheel=1})[n]end,button_index=function(n)return({left=0,right=1,middle=2})[n]end,
   axis=function(i)axis_reads=axis_reads+1;if i==0 then return{x=50,y=50}end;return{x=0,y=0}end,button=function(i)return i==0 and 1 or 0 end}}
 local holds,menu={},false
 local chef={hold_mouse=function(on)holds[#holds+1]=on;return true end,mouse_delta=function()return 10,-20 end,menu_open=function()return menu end}
 local lines={};local service=host.input(chef,sr,function(s)lines[#lines+1]=s end,engine_input)
 local token=assert(service.acquire('dbf_freecam','menu'))
 assert(holds[1]==true and service.held(),'Photo Mode holds the mouse')
 local sample=service.snapshot(token)
 assert(sample.x==960+10 and sample.y==540-20,'The held cursor moves by chef.mouse_delta, not the engine axis')
 assert(sample.buttons%2==1,'Clicks still read')
 menu=true;sample=service.snapshot(token)
 assert(sample.buttons==0 and sample.dx==0 and sample.dy==0 and sample.x==970 and sample.y==520,'Nothing reaches Photo Mode under the loader menu')
 menu=false
 assert(service.release(token)==true and holds[2]==false and not service.held(),'The hold goes with the lease')
 -- Hold refused: the engine axis still works.
 local refused={hold_mouse=function()return false,'no dead zone'end,mouse_delta=function()return 0,0 end}
 local fallback=host.input(refused,sr,function(s)lines[#lines+1]=s end,engine_input)
 token=assert(fallback.acquire('dbf_freecam','menu'))
 assert(not fallback.held()and fallback.snapshot(token).x==960+50,'Without the hold the engine axis moves the cursor')
 local said=false;for _,line in ipairs(lines)do said=said or line:find('no dead zone',1,true)~=nil end
 assert(said,'The refusal is logged')
 fallback.release(token)
end
-- Drawing: addon.render() calls what Photo Mode put in the global.
do
 local G={};local lines={}
 local hook=host.render(G,function(s)lines[#lines+1]=s end)
 local base=rawget(G,'render')
 assert(type(base)=='function','A mod without a render global gets one to wrap')
 hook();assert(#lines==0,'Nothing to draw while Photo Mode is closed')
 local draws=0;local prior=rawget(G,'render')
 rawset(G,'render',function(...)draws=draws+1;return prior(...)end)
 hook();hook()
 assert(draws==2,'Each loader render reaches the Photo Mode wrapper')
 assert(#lines==1,'The first forwarded render is logged once')
 rawset(G,'render',prior);hook();assert(draws==2,'A restored render is left alone')
 local found=function()end;local H={render=found}
 host.render(H,nil);assert(rawget(H,'render')==found,'A render the loader gave is kept as the base')
end
print('Chef host: all tests passed')

-- chef_scene_resources.lua, with fakes.
local M=dofile('freecam/chef_scene_resources.lua')
local inspect=dofile('freecam/engine_scene_resources.lua').inspect
local contract=dofile('freecam/engine_render_contract.lua')
local registry={depth_binding='private-local-v1'}
local function n(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function dds(format,w,h)
 local hd=string.rep('\0',148)
 local function put(at,s)hd=hd:sub(1,at)..s..hd:sub(at+#s+1)end
 put(0,'DDS ');put(4,n(124));put(12,n(h));put(16,n(w));put(84,'DX10');put(128,n(format));put(132,n(3));put(140,n(1))
 return hd..string.rep('\0',w*h*(format==10 and 8 or 4))
end
-- save: nil, as under Chef, or function(name,path,files). capture: the host's depth service, or nil.
local function fake(save,build,capture)
 local lines,files,opens,calls,ids,assets={},{},{},{},{},{};local gets,binds=0,0;local clock={now=0}
 local handles={linear_depth={},output_target={}};local world={}
 local sr={Application={process_id=function()return 7 end,main_world=function()return world end,time_since_launch=function()return clock.now end,
   build_identifier=function()return build or M.build end,can_get=function(_,name)assets[#assets+1]=name;return true end,
   render_setting=function(key)if key=='hdr_enabled'then return false end;if key=='ui_brightness'then return 203 end;return false end,
   save_render_target=save and function(name,path)return save(name,path,files)end or nil},
  Gui={resolution=function()return 4,2 end},
  Renderer={resource=function(name)gets=gets+1;return assert(handles[name])end},
  IdString64={from_hex=function(hex)ids[hex]=ids[hex]or{hex=hex};return ids[hex]end},
  Material={set_resource=function(_,slot,value)calls[#calls+1]={'resource',slot,value};binds=binds+1;return true end,
   set_texture=function(_,slot,value)calls[#calls+1]={'texture',slot,value};binds=binds+1;return true end}}
 local mod={config_dir='C:/game',log=function(s)lines[#lines+1]=s end,
  require=function(path)assert(path=='src/steam_scene_overlay.lua',path);return dofile('freecam/steam_scene_overlay.lua')end}
 local old_open,old_remove=io.open,os.remove
 io.open=function(path)
  opens[#opens+1]=path;local bytes=files[path];if not bytes then return nil,'missing'end;local at=0
  return{read=function(_,size)if size=='*a'then size=#bytes-at end;local s=bytes:sub(at+1,at+size);at=at+#s;return s end,
   seek=function(_,where,pos)if where=='end'then at=#bytes else at=pos or 0 end;return at end,close=function()return true end}
 end
 os.remove=function(path)files[path]=nil;return true end
 local r=M.new(sr,mod,registry,contract,inspect,capture)
 local function count(text)local c=0;for _,l in ipairs(lines)do if l:find(text,1,true)then c=c+1 end end;return c end
 return r,{lines=lines,files=files,opens=opens,handles=handles,sr=sr,count=count,calls=calls,ids=ids,clock=clock,assets=assets,gets=function()return gets end,binds=function()return binds end,
  restore=function()io.open,os.remove=old_open,old_remove end}
end
-- Chef: no save_render_target. GPU binding works, focus does not.
do
 local r,f=fake(nil)
 assert(r.registered()and r.registered(0x49a73b4c),'The engine says whether the shader and material are loaded')
 assert(f.assets[1]=='mods/dbf_photo/shaders/windows_private_depth_8994dbbab90c07c5'and f.assets[3]=='mods/dbf_photo/shaders/windows_private_depth_535eeb61c686fbab','The private-slot pair, HDR then SDR')
 local ok,why=r.depth.available();assert(ok==true and why==nil,tostring(why))
 local cpu,reason=r.cpu_depth();assert(cpu==false and reason:find('leaves it out',1,true),tostring(reason))
 assert(r.depth.get()==f.handles.linear_depth and r.depth.binding_identity:find('|',1,true)and r.depth.render_world()=='ui')
 for _=1,50 do assert(r.depth.available());r.depth.get();r.color()end
 assert(f.gets()==2,'An unchanged display looks each target up once')
 local ok2,c=r.color()
 assert(ok2 and c.format==19 and c.width==4 and c.height==2 and c.hdr_enabled==false and c.ui_brightness==203 and c.resource==f.handles.output_target,'Colour descriptor')
 assert(c.proof:find('no readback',1,true),c.proof)
 assert(r.depth.bind({},'diffuse_map',r.depth.get())and f.binds()==1,'Depth is bound to the private shader parameter')
 assert(f.calls[1][1]=='resource'and f.calls[1][2]=='wjl_scene_depth'and f.calls[1][3]==f.handles.linear_depth,'By name, the depth target')
 assert(f.count('depth bound to the private slot; the engine answered true')==1)
 assert(r.depth.bind({},'diffuse_map',r.depth.get())and f.count('depth bound to the private slot')==1,'Said once while the answer holds')
 assert(not pcall(r.depth.bind,{},'diffuse_map',{}),'A foreign depth handle refuses')
 assert(not pcall(r.depth.bind,{},'output_target',r.depth.get()),'A foreign slot refuses')
 local ran,err=pcall(r.focus_descriptor);assert(not ran and tostring(err):find('Focus needs the CPU depth readback',1,true),tostring(err))
 assert(#f.opens==0,'Nothing is opened without a readback')
 assert(f.count('CPU depth readback unavailable')==1,'The refusal is logged once')
 assert(f.count('formats from the renderer contract')==1)
 assert(r.release());f.restore()
end
-- Readback allowed: focus works.
do
 local saves=0
 local r,f=fake(function(name,path,files)assert(name=='linear_depth');saves=saves+1;files[path]=dds(41,4,2);return true end)
 assert(r.depth.available());assert(r.cpu_depth()==true)
 assert(saves==1 and f.files['C:/game/wj-chef-depth-7.dds']==nil,'The probe file is read once and removed')
 local ok,meta=r.focus_descriptor()
 assert(ok and meta.format==1 and meta.kind==2 and meta.width==4 and meta.height==2 and meta.identity:find('linear_depth',1,true)and meta.display_identity,'Focus descriptor')
 local _,c=r.color();assert(c.proof:find('depth readback observed',1,true),c.proof)
 for _=1,20 do assert(r.depth.available())end;assert(saves==1,'One readback per display change')
 assert(f.count('CPU depth readback worked: 4x2 DXGI=41')==1)
 f.restore()
end
-- A failing readback is logged, not fatal. A wrong depth format is fatal.
do
 local r,f=fake(function()error('Application.save_render_target is off limits to Chef Shared Loader mods')end)
 assert(r.depth.available());local cpu,reason=r.cpu_depth();assert(cpu==false and reason:find('refused: ',1,true)and reason:find('off limits',1,true),tostring(reason))
 f.restore()
 local bad,g=fake(function(name,path,files)files[path]=dds(28,4,2);return true end)
 local ok,why=bad.depth.available();assert(ok==false and why:find('Depth must be R32_FLOAT',1,true),tostring(why))
 g.restore()
end
-- Another game build: effects off.
do
 local r,f=fake(nil,'stingray:0000000000000000000000000000000000000000')
 local ok,why=r.depth.available();assert(ok==false and why:find('is not the one the renderer contract was made for',1,true),tostring(why))
 assert(f.gets()==0,'No target lookup on another build')
 local ran=pcall(r.depth.get);assert(not ran);f.restore()
end
-- The contract must name the right targets.
do
 local r,f=fake(nil)
 assert(not pcall(M.new,f.sr,{config_dir='C:/game',log=function()end},{depth_binding='global'},contract,inspect),'Withdrawn binding contracts refuse')
 assert(not pcall(M.new,f.sr,{config_dir='C:/game',log=function()end},registry,{version=1,depth={name='x',format='R32F'},color={name='output_target',format='R16G16B16A16F'}},inspect),'Other target names refuse')
 f.restore()
end
-- Chef 1.4.2: the focus sampler asks chef.capture('depth'). The scene check never asks on its own; it proves the
-- format from the sampler's file (source.last) and remembers it for the launch.
do
 local PATH='C:/game/goose_war_journalist_depth_01.dds'
 local asked=0;local source={wait=5,request=function()asked=asked+1;return PATH end}
 local r,f=fake(nil,nil,source)
 assert(r.depth.available()and asked==0,'The scene check does not ask')
 local cpu,reason=r.cpu_depth();assert(cpu==false and reason=='no focus capture yet',tostring(reason))
 local ok,meta=r.focus_descriptor();assert(ok and meta.width==4 and meta.height==2,'Focus may go first: its file is the proof')
 assert(f.count('CPU depth readback unavailable: no focus capture yet')==1)
 source.last=PATH;f.clock.now=.3;assert(r.depth.available());local _,why=r.cpu_depth();assert(why=='depth capture pending',tostring(why))
 f.files[PATH]=dds(41,4,2):sub(1,160);f.clock.now=.6;assert(r.depth.available());assert(r.cpu_depth()==false,'A part-written file is not a proof')
 f.files[PATH]=dds(41,4,2);f.clock.now=.9;assert(r.depth.available())
 assert(r.cpu_depth()==true and asked==0,'Whole: proved, never asked')
 assert(f.count('CPU depth readback worked: 4x2 DXGI=41 (chef.capture)')==1)
 local _,c=r.color();assert(c.proof:find('depth readback observed',1,true))
 -- Remembered across Photo Mode sessions: the next open starts proved, with no file around.
 assert(r.release());f.files[PATH]=nil;f.clock.now=5
 assert(r.depth.available()and r.cpu_depth()==true,'Proved once per display for the launch')
 assert(f.count('CPU depth readback worked')==1 and f.count('depth format proved by readback')==1)
 f.restore()
 -- Never whole: given up, said once. The next file asked for is watched.
 local source2={wait=5,request=function()end}
 local r2,g=fake(nil,nil,source2)
 assert(r2.depth.available());source2.last=PATH
 for t=1,7 do g.clock.now=t;assert(r2.depth.available())end
 local _,why2=r2.cpu_depth();assert(why2:find('not whole',1,true),tostring(why2));assert(g.count('not whole in time')==1)
 source2.last='C:/game/goose_war_journalist_depth_02.dds';g.files[source2.last]=dds(41,4,2);g.clock.now=8;assert(r2.depth.available())
 assert(r2.cpu_depth()==true,'The next file proves it')
 g.restore()
 -- The wrong format: fatal, effects off, and it stays so for the launch.
 local source3={wait=5,request=function()end}
 local r3,k=fake(nil,nil,source3)
 assert(r3.depth.available());source3.last=PATH;k.files[PATH]=dds(28,4,2);k.clock.now=.5
 local ok3,why3=r3.depth.available();assert(ok3==false and why3:find('Depth must be R32_FLOAT',1,true),tostring(why3))
 assert(r3.release());local ok4,why4=r3.depth.available();assert(ok4==false and why4:find('Depth must be R32_FLOAT',1,true),'Fatal stays')
 k.restore()
end
print('Chef scene resources: all tests passed')

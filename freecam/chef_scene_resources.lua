-- Scene effects under Chef. Depth and colour bound on the GPU, formats from the renderer
-- contract. Focus needs a CPU depth read; under Chef that is the loader's depth capture.
local M={}
local DXGI={R32F=41,R16G16B16A16F=10}
-- The game build the contract was made for (26251122). Any other build keeps the effects off.
M.build='stingray:46805437a3d445f9df7662b60086ac8ae3c65b5c95da6'
-- capture: the host's depth service (chef_host.depth), or nil on a Chef without chef.capture('depth').
-- The focus sampler asks it; this module only reads the file it asked for, to prove the format.
function M.new(sr,mod,registry,contract,inspect,capture)
 assert(registry.depth_binding=='private-local-v1','Unknown or withdrawn depth binding contract')
 assert(type(contract)=='table'and contract.version==1 and type(contract.depth)=='table'and type(contract.color)=='table','Renderer contract unavailable')
 assert(contract.depth.name=='linear_depth'and contract.color.name=='output_target','Renderer contract names differ')
 local depth_dxgi=assert(DXGI[contract.depth.format],'Unknown contract depth format')
 assert(DXGI[contract.color.format]==10,'Contract colour must be RGBA16F')
 local self={};local cache;local handles={};local generation=0;local cpu_reason;local last_bind
 local folder=assert(mod.config_dir,'Settings folder unavailable')
 -- Chef drops save_render_target. Try anyway and say what happened.
 local function readback()
  local save=sr.Application.save_render_target
  if type(save)~='function'then return nil,"Application.save_render_target is not in this mod's Application (Chef Shared Loader leaves it out)"end
  local path=folder..'/wj-chef-depth-'..tostring(sr.Application.process_id())..'.dds'
  local called,result=pcall(save,'linear_depth',path)
  if not called then return nil,'save_render_target refused: '..tostring(result)end
  if result==false then return nil,'save_render_target returned false'end
  local f=io.open(path,'rb');if not f then return nil,'the depth file was not written or cannot be read: '..path end
  local size=f:seek('end');f:seek('set',0);local header=f:read(148);f:close()
  pcall(os.remove,path)
  local ok,info=pcall(inspect,header,size)
  if not ok then return nil,tostring(info)end
  return info
 end
 -- Chef 1.4.2 on: the focus sampler asks chef.capture('depth') and the loader writes the file over a few
 -- frames. The newest file asked for (capture.last) is watched until whole and proves the format, once per
 -- display for the launch. Asking here too would spend the loader's one capture a second on a proof.
 local proven={};local pending,watched
 local function u(s,i)local a,b,c,d=s:byte(i,i+3);return a+b*256+c*65536+d*16777216 end
 local function fatal(why)cache.fatal=why;proven[cache.signature]={fatal=why};pending=nil end
 local function look(now)
  if now<pending.next then return end
  pending.next=now+.25
  local f=io.open(pending.path,'rb');local head,size
  if f then size=f:seek('end');head=f:seek('set',0)==0 and f:read(148);f:close()end
  if type(head)=='string'and #head==148 and head:sub(1,4)=='DDS 'then
   local format=u(head,129)
   if format~=depth_dxgi then return fatal('Depth must be R32_FLOAT; the depth capture is DXGI='..format)end
   local w,h=u(head,17),u(head,13)
   if size>=148+w*h*4 then
    local ok,info=pcall(inspect,head,size)
    if not ok then return fatal(tostring(info))end
    cache.cpu=true;cache.depth={width=info.width,height=info.height,dxgi=info.dxgi};proven[cache.signature]={depth=cache.depth};cpu_reason=nil;pending=nil
    mod.log(string.format('Chef scene: CPU depth readback worked: %dx%d DXGI=%d (chef.capture)',info.width,info.height,info.dxgi))
    return
   end
  end
  if now>=pending.til then pending=nil;cpu_reason='the depth capture was not whole in time';mod.log('Chef scene: '..cpu_reason)end
 end
 local function watch(now)
  local path=capture.last
  if path and path~=watched then watched=path;pending={path=path,til=now+(capture.wait or 5),next=now};cpu_reason='depth capture pending'end
  if pending then look(now)end
 end
 local function verify()
  local w,h=sr.Gui.resolution();local world=sr.Application.main_world()
  local hdr=sr.Application.render_setting('hdr_enabled');assert(type(hdr)=='boolean','HDR setting unavailable')
  local signature=w..'x'..h..'|'..tostring(hdr)
  if cache and cache.world==world and cache.signature==signature then
   if capture and not cache.cpu and not cache.fatal then watch(sr.Application.time_since_launch())end
   if cache.fatal then error(cache.fatal,0)end
   return cache
  end
  handles={};cache=nil;pending=nil;watched=nil
  local known=capture and proven[signature]
  if known and known.fatal then error(known.fatal,0)end
  assert(world,'Main world unavailable')
  local build=type(sr.Application.build_identifier)=='function'and sr.Application.build_identifier()
  build=type(build)=='string'and build:gsub('%s','')or tostring(build)
  assert(build==M.build,'Game build '..build..' is not the one the renderer contract was made for; scene effects stay off')
  assert(type(w)=='number'and type(h)=='number'and w>0 and h>0 and w<=16384 and h<=16384,'Viewport unavailable')
  local d,why
  if known then d=known.depth;cpu_reason=nil
  elseif capture then why='no focus capture yet'
  else d,why=readback()end
  local cpu=d~=nil
  if d and not known then
   assert(d.dxgi==depth_dxgi,'Depth must be R32_FLOAT')
   mod.log(string.format('Chef scene: CPU depth readback worked: %dx%d DXGI=%d',d.width,d.height,d.dxgi))
  elseif not d then
   d={width=w,height=h,dxgi=depth_dxgi}
   if cpu_reason~=why then cpu_reason=why;mod.log('Chef scene: CPU depth readback unavailable: '..why)end
  end
  -- Colour target. No readback.
  local c={width=w,height=h,dxgi=10,mips=1,array=1}
  handles.depth=assert(sr.Renderer.resource('linear_depth'),'linear_depth target unavailable')
  handles.color=assert(sr.Renderer.resource('output_target'),'output_target unavailable')
  assert(handles.depth~=handles.color,'Color and depth handles alias')
  local white=sr.Application.render_setting('ui_brightness');assert(type(white)=='number'and white>0 and white<=10000,'UI white setting unavailable')
  generation=generation+1
  cache={key=generation..'|'..signature,signature=signature,depth=d,color=c,hdr=hdr,white=white,world=world,cpu=cpu}
  mod.log('Chef scene: engine depth and colour bound on the GPU'..(cpu and', depth format proved by readback'or', formats from the renderer contract'))
  return cache
 end
 -- Shader and material ship with the mod. The engine says if they loaded.
 function self.registered(requested)
  local overlay=mod.require('src/steam_scene_overlay.lua')
  local shader,material,sdr_shader,sdr_material=overlay.paths(registry.depth_binding)
  if requested~=nil then
   assert(requested==0x49a73b4c,'Unknown scene shader registration')
   shader,material=sdr_shader,sdr_material
  end
  assert(sr.Application.can_get('shader_library',shader)and sr.Application.can_get('material',material),'Owned scene assets are not loaded')
  return true
 end
 self.depth={binding_contract=registry.depth_binding}
 function self.depth.render_world()return'ui'end
 function self.depth.available()local ok,value=pcall(verify);return ok,not ok and tostring(value)or nil end
 function self.depth.get()local c=verify();self.depth.binding_identity=c.key..'|'..tostring(handles.depth);return handles.depth end
 -- The private slot. A render target does not reach the shader this way; the colour effects do not need it.
 function self.depth.bind(material,slot,resource)
  assert(slot=='diffuse_map'and resource==handles.depth,'Depth binding identity differs')
  local result=sr.Material.set_resource(material,'wjl_scene_depth',resource)
  local said=tostring(result)
  if said~=last_bind then last_bind=said;mod.log('Chef scene: depth bound to the private slot; the engine answered '..said)end
  return result~=false
 end
 function self.color()
  local c=verify()
  return true,{format=19,width=c.color.width,height=c.color.height,mips=1,array=1,resource=handles.color,backing=c.key,id=tostring(handles.color),hdr_enabled=c.hdr,ui_brightness=c.white,
   proof=c.cpu and'Chef: depth readback observed; colour from the renderer contract'or'Chef: depth and colour from the renderer contract; no readback'}
 end
 -- Focus needs the CPU depth read. With a capture source the sampler's own file is that read.
 function self.focus_descriptor()
  local c=verify()
  assert(c.cpu or capture,'Focus needs the CPU depth readback: '..tostring(cpu_reason))
  return true,{format=1,kind=2,mips=1,array=1,width=c.depth.width,height=c.depth.height,identity=c.key..'|linear_depth',display_identity=c.key}
 end
 function self.cpu_depth()if cache then return cache.cpu,cpu_reason end;return nil,cpu_reason end
 function self.release()cache=nil;handles={};pending=nil;watched=nil;return true end
 return self
end
return M

-- Opt-in, one-shot qualification on an owned disposable unit. No main-world
-- setters, camera/input changes, frame polling after completion or native DLL.
local M={}
function M.consume(folder,pid)
 local path=folder..'/wj-visibility-probe.request';local f=io.open(path,'rb');if not f then return false end
 local token=f:read(64);f:close()
 if token~='private-visibility-v1\n'and token~='private-mesh-catalog-v1\n'and token~='private-visibility-hold-v1\n' then return false end
 if os.rename(path,path..'.claimed.'..tostring(pid)..'.'..token:sub(1,-2))~=true then return false end
 return token:sub(1,-2)
end
function M.new(sr,log,clock,mode,visibility_factory)
 local A,W,U,Mesh=sr.Application,sr.World,sr.Unit,sr.Mesh
 local self={};local world,unit,held_lease,baseline;local phase=0;local done=false;local error_reason;local maximum=0;local retries=0
 -- Resident resource observed on the selected outfit, October 26. Only a
 -- separately spawned copy is modified, never the previously observed handles.
 local resources={'3bae7995707e30fb'};local resource_index=1
 if mode=='private-mesh-catalog-v1'then resources={
  '3bae7995707e30fb','98ef4e039e963bdb','312c88caefdf6f9c','e17025ba1d43acd3',
  'a5710e9464a26f48','1ab1fdccc59f05da','b0552d54fcd2a0d3','d2a2e2bc4fa5be21',
  'c80b17cf0adc14a8','ad4f0063842dbb63','a70972419680b0b2','86b26185ad78f9e8',
  'ea846ef460cc5ba0','544ed679357b6cb7','6a589144bb3f838f','abf65fc9fc79fa96','619253c08af8dfdf'}end
 local function cleanup()
  if world then
   local ok,why=pcall(A.release_world,world)
   if not ok then return false,tostring(why)end
   world,unit,held_lease,baseline=nil,nil,nil,nil
  end
  return true
 end
 function self.release()done=true;return cleanup()end
 local function finish()
  done=true;self.result={passed=not error_reason,error=error_reason,max_step_ms=maximum,world_released=world==nil}
  log('Private visibility probe: '..(error_reason and'stopped: '..error_reason or'default visibility roundtrip passed; context argument honored')..
   '; private_world_released='..tostring(world==nil)..'; max_step_ms='..string.format('%.3f',maximum)..'; player writes=0')
 end
 function self.tick()
  if done then return end
  local started=clock()
  local resource=resources[resource_index]
  local ok,why=pcall(function()
   if phase==0 then
    assert(A.can_get('unit',sr.IdString64.from_hex(resource))==true,'Observed outfit resource is not resident')
    local created=assert(A.new_world(),'Private world unavailable')
    assert(created~=A.main_world(),'Private world aliases gameplay world')
    world=created;phase=1
   elseif phase==1 then
    unit=assert(W.spawn_unit(world,sr.IdString64.from_hex(resource)),'Private outfit spawn failed');phase=2
   elseif phase==2 then
    assert(U.alive(unit)==true and U.world(unit)==world,'Private outfit ownership changed')
    local count=U.num_meshes(unit);assert(type(count)=='number'and count>=1 and count<=128,'Private outfit mesh count invalid')
    local mesh=assert(U.mesh(unit,1),'Private mesh missing')
    local function set(value,context,expected)
     U.set_mesh_visibility(unit,1,value,context)
     assert(Mesh.visibility(mesh)==expected,'Visibility context/readback mismatch at '..context..'='..tostring(value))
    end
    set(true,'default',true)
    set(false,'shadow_caster',true)
    set(false,'occluder',true)
    set(false,'default',false)
    set(true,'shadow_caster',false)
    set(true,'occluder',false)
    set(true,'default',true)
    if mode=='private-mesh-catalog-v1'then
     for index=1,math.min(count,16)do
      local m=U.mesh(unit,index);local label='unavailable';local bounds='unavailable'
      if type(Mesh.name)=='function'then local got,value=pcall(Mesh.name,m);if got then label=tostring(value)end end
      if type(Mesh.bounding_volume_components)=='function'and sr.Vector3 then
       local got,value=pcall(function()
        local lo,hi,radius=Mesh.bounding_volume_components(m);local V=sr.Vector3
        return string.format('%.5g,%.5g,%.5g:%.5g,%.5g,%.5g:r=%.5g',V.x(lo),V.y(lo),V.z(lo),V.x(hi),V.y(hi),V.z(hi),radius)
       end)
       if got then bounds=value end
      end
      log('Private outfit mesh: resource='..resource..' index='..index..' name='..label..' bounds='..bounds)
     end
    end
    if visibility_factory then
     local indices={};for index=1,count do indices[index]=index end
     baseline={};for index=1,count do baseline[index]=Mesh.visibility(U.mesh(unit,index))end
     local lease=visibility_factory.new(sr)
     local hidden,reason=lease.hide({{unit=unit,world=world,resource=tostring(U.resource_name(unit)),indices=indices}})
     assert(hidden,reason)
     if mode=='private-visibility-hold-v1'then held_lease=lease;phase=5;return end
     local restored,issue=lease.release();assert(restored,issue)
     assert(lease.count()==0,'Private visibility lease retained meshes')
     log('Private visibility service: resource='..resource..' meshes='..count..' hide/restore passed')
    end
    phase=3
   elseif phase==5 then
    local restored,reason=held_lease.release();assert(restored,reason)
    for index,expected in ipairs(baseline)do assert(Mesh.visibility(U.mesh(unit,index))==expected,'Cross-frame visibility restore differs')end
    assert(held_lease.count()==0,'Cross-frame visibility lease retained meshes');held_lease=nil
    log('Private visibility service: cross-frame hide/restore passed; original visibility preserved')
    phase=3
   elseif phase==3 then
    local released,reason=cleanup();assert(released,reason)
    if not error_reason and resource_index<#resources then resource_index=resource_index+1;phase=0 else phase=4 end
   end
  end)
  maximum=math.max(maximum,(clock()-started)*1000)
  if not ok then
   error_reason=tostring(why);retries=retries+1
   if phase~=3 then phase=3 elseif retries>=3 then finish()end
  elseif phase==4 then finish()end
 end
 return self
end
return M

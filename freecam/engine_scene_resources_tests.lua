local module=dofile('freecam/engine_scene_resources.lua')
local function n(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function dds(format)
 local h=string.rep('\0',148)
 local function put(at,s)h=h:sub(1,at)..s..h:sub(at+#s+1)end
 put(0,'DDS ');put(4,n(124));put(12,n(2));put(16,n(2));put(84,'DX10');put(128,n(format));put(132,n(3));put(140,n(1))
 return h..string.rep('\0',4*(format==10 and 8 or 4))
end
assert(module.inspect(dds(41):sub(1,148),164).dxgi==41)
assert(not pcall(module.inspect,dds(10):sub(1,148),164),'Format/size mismatch must refuse')
local files={['C:/game/data/owned.patch_0']='a'};local old_open,old_remove,old_env=io.open,os.remove,os.getenv
os.getenv=function(name)assert(name=='APPDATA');return 'C:/settings'end
io.open=function(path,mode)
 local bytes=files[path];if not bytes then return nil end
 local at=0;return{read=function(_,size)if size=='*a'then return bytes end;local s=bytes:sub(at+1,at+size);at=at+#s;return s end,
 seek=function(_,where,pos)if where=='end'then at=#bytes else at=pos or 0 end;return at end,close=function()return true end}
end
os.remove=function(path)files[path]=nil;return true end
local captures,gets,binds=0,0,0;local hdr=false;local bad_depth=false;local handles={linear_depth={},output_target={}}
local function new_world()local world=newproxy(true);getmetatable(world).__tostring=function()return '[World]'end;return world end
local world=new_world()
local sr={Application={process_id=function()return 99 end,main_world=function()return world end,
 can_get=function()return true end,render_setting=function(key)return key=='hdr_enabled'and hdr or key=='ui_brightness'and 203 or false end,
 save_render_target=function(name,path)assert(name=='linear_depth','Color/back-buffer CPU readback is forbidden');captures=captures+1;files[path]=dds(bad_depth and 28 or 41)end},
 Gui={resolution=function()return 2,2 end},Renderer={resource=function(name)gets=gets+1;assert(captures>=1 and handles[name],'Never look up unverified/missing resources');return handles[name]end},
 Material={set_resource=function(mat,slot,value)assert(slot=='diffuse_map'and value==handles.linear_depth);binds=binds+1 end}}
local mod={render_contract_verified=true,game_root='C:/game',log=function()end,require=function()return{paths=function(global)assert(not global);return's','m','ss','sm'end}end}
assert(not pcall(module.new,sr,{render_contract_verified=false},{name='owned.patch_0',hex='61'}),'No GPU lookup without a stock graph witness')
local r=module.new(sr,mod,{name='owned.patch_0',hex='61'})
assert(r.registered());assert(r.depth.available());assert(captures==1 and gets==2)
for i=1,100 do assert(r.depth.available());r.depth.get();r.color()end
assert(captures==1 and gets==2,'Unchanged targets must not repeat GPU readback or resource lookup')
local ok,c=r.color();assert(ok and c.format==19 and c.width==2 and c.hdr_enabled==false)
assert(not r.depth.global_binding,'Withdrawn global-depth candidate must not reactivate')
assert(r.depth.bind({},'diffuse_map',r.depth.get()));assert(binds==1)
local private=module.new(sr,mod,{name='owned.patch_0',hex='61',depth_binding='private-local-v1'})
assert(private.depth.binding_contract=='private-local-v1'and not private.depth.global_binding)
local old_paths=mod.require
mod.require=function()return{paths=function(binding)assert(binding=='private-local-v1');return's','m','ss','sm'end}end
assert(private.registered());mod.require=old_paths
local old_captures,old_gets=captures,gets
assert(private.depth.available());local target=private.depth.get()
local old_set=sr.Material.set_resource
sr.Material.set_resource=function(_,slot,value)assert(slot=='wjl_scene_depth'and value==handles.linear_depth);binds=binds+1 end
assert(private.depth.bind({},'diffuse_map',target));assert(binds==2)
assert(not pcall(private.depth.bind,{},'diffuse_map',{}),'Foreign depth handle must refuse')
assert(not pcall(private.depth.bind,{},'output_target',target),'Foreign parameter must refuse')
sr.Material.set_resource=old_set
local control={source='output_target'}
local controlled=module.new(sr,mod,{name='owned.patch_0',hex='61',depth_binding='private-local-v1'},control)
assert(controlled.depth.available());local real_depth=controlled.depth.get();local color_key=controlled.depth.binding_identity
sr.Material.set_resource=function(_,slot,value)assert(slot=='wjl_scene_depth'and value==handles.output_target);binds=binds+1 end
assert(controlled.depth.bind({},'diffuse_map',real_depth),'Color control binds only the already verified GPU resource')
local count=captures;control.source='linear_depth';assert(controlled.depth.get()==real_depth and controlled.depth.binding_identity~=color_key)
sr.Material.set_resource=function(_,slot,value)assert(slot=='wjl_scene_depth'and value==handles.linear_depth);binds=binds+1 end
assert(controlled.depth.bind({},'diffuse_map',real_depth));assert(captures==count,'Changing probe source must not submit another readback')
control.source='output_target';controlled.depth.get();assert(controlled.depth.binding_identity==color_key,'Color/depth/color invalidates the retained quad deterministically')
control.source='guessed_resource';assert(not pcall(controlled.depth.get),'Probe cannot look up arbitrary resources')
local ids={};sr.IdString64={from_hex=function(hex)ids[hex]=ids[hex]or newproxy();return ids[hex]end}
local slot_id=sr.IdString64.from_hex('9c7af65000000000')
local atlas_id=sr.IdString64.from_hex('d1ebb991c79f934b')
local texture_binds=0;local atlas_available=true;local old_can_get=sr.Application.can_get
sr.Application.can_get=function(kind,id)assert(kind=='texture'and id==atlas_id);return atlas_available end
sr.Material.set_texture=function(_,slot,value)
 assert(slot==(control.source=='atlas-id'and slot_id or 'wjl_scene_depth')and value==atlas_id)
 texture_binds=texture_binds+1
end
control.source='atlas-string';controlled.depth.get();local string_key=controlled.depth.binding_identity
assert(controlled.depth.bind({},'diffuse_map',real_depth)and texture_binds==1)
control.source='atlas-id';controlled.depth.get();assert(controlled.depth.binding_identity~=string_key)
assert(controlled.depth.bind({},'diffuse_map',real_depth)and texture_binds==2,'Boxed slot must also survive diagnostic logging')
atlas_available=false;assert(not pcall(controlled.depth.bind,{},'diffuse_map',real_depth)and texture_binds==2,'Missing atlas refuses before setter')
control.source='depth-id';controlled.depth.get()
sr.Material.set_resource=function(_,slot,value)assert(slot==slot_id and value==handles.linear_depth);return true end
assert(controlled.depth.bind({},'diffuse_map',real_depth)and captures==count,'Boxed depth uses existing GPU handle without new readback')
sr.Application.can_get=old_can_get
-- Withdrawn GPU-copy modes refuse before any renderer allocation or submission.
local native_calls=0
sr.Renderer.create_resource=function()native_calls=native_calls+1 end
sr.Renderer.run_resource_generator=function()native_calls=native_calls+1 end
for _,source in ipairs({'copy-color','copy-depth'})do
 control.source=source;assert(not pcall(controlled.depth.get))
 assert(not pcall(controlled.depth.bind,{},'diffuse_map',real_depth))
end
assert(native_calls==0,'Withdrawn copy path must never reach native APIs')
assert(controlled.depth.render_world()=='ui')
control.gui_world='main';assert(controlled.depth.render_world()=='main')
control.gui_world='arbitrary';assert(not pcall(controlled.depth.render_world))
control.gui_world=nil
assert(controlled.release());sr.Material.set_resource=old_set
assert(not pcall(module.new,sr,mod,{depth_binding=true}),'Withdrawn global contract must refuse')
assert(not pcall(module.new,sr,mod,{depth_binding='indexed-global-v2'}),'Withdrawn indexed global contract must refuse')
assert(private.release());captures,gets=old_captures,old_gets
hdr=true;assert(r.depth.available());assert(captures==2 and gets==4,'HDR change explicitly revalidates')
-- Distinct shipping world handles have identical text, and the renderer can
-- reuse resource handles. Both retained GUI bindings and depth files must
-- still invalidate on a world change and when an earlier world returns.
local first_world=world
local _,first_focus=r.focus_descriptor();local _,first_color=r.color();r.depth.get();local first_binding=r.depth.binding_identity
world=new_world();assert(world~=first_world and tostring(world)==tostring(first_world))
local before_captures,before_gets=captures,gets
local _,second_focus=r.focus_descriptor();local _,second_color=r.color();r.depth.get()
assert(captures==before_captures+1 and gets==before_gets+2,'New world must revalidate despite identical world text')
assert(second_focus.identity~=first_focus.identity and second_focus.display_identity~=first_focus.display_identity,'World transition must retire the autofocus and selection snapshot')
assert(second_color.backing~=first_color.backing and r.depth.binding_identity~=first_binding,'World transition must invalidate retained material bindings with reused resource handles')
for i=1,100 do r.focus_descriptor();r.depth.get();r.color()end
assert(captures==before_captures+1 and gets==before_gets+2,'Settled world performs no repeated readback or lookup')
world=first_world;local _,returned=r.focus_descriptor()
assert(returned.identity~=first_focus.identity and returned.identity~=second_focus.identity,'Returning to an earlier world must not revive its old depth generation')
world=nil;before_captures,before_gets=captures,gets
assert(not r.depth.available()and captures==before_captures and gets==before_gets,'Missing world must retire the cache without renderer work')
world=first_world;local _,reappeared=r.focus_descriptor()
assert(reappeared.identity~=returned.identity and captures==before_captures+1,'Reappearing world must be readmitted')
assert(r.release());local _,reopened=r.focus_descriptor()
assert(reopened.identity~=reappeared.identity,'Release must not recycle a depth generation within this owner')
assert(r.release());bad_depth=true;local before=gets;assert(not r.depth.available());assert(gets==before,'Bad depth proof must not query resource handles')
for key in pairs(files)do assert(key=='C:/game/data/owned.patch_0','Every owned probe file must be removed')end
assert(r.release());files['C:/game/data/owned.patch_0']='foreign'
local other=module.new(sr,mod,{name='owned.patch_0',hex='61'});assert(not pcall(other.registered),'Foreign shader registry refuses before use')
io.open,os.remove,os.getenv=old_open,old_remove,old_env
print('Engine scene resources: exact registry, depth-only DDS proof, GPU-only color, no missing-target lookup, cached readbacks, HDR invalidation, binding and cleanup passed; visual shader output pending')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'render_profile.lua');local values={dof_enabled=false,bloom_enabled=true};local queued={};local calls=0
local sr={Application={render_setting=function(name)return values[name]end,set_render_setting=function(name,value)
 assert(value=='true'or value=='false','Must use serialized Boolean overload');calls=calls+1;queued[#queued+1]={name=name,value=value=='true'}
end}}
local profile=assert(factory.new(sr,1,function()return true end));assert(profile.parameters.dof and profile.parameters.bloom)
profile.write('dof',1);assert(profile.read('dof')==0 and profile.pending('dof'));profile.write('dof',1);assert(calls==1)
profile.tick();assert(profile.pending('dof'));for _,change in ipairs(queued)do values[change.name]=change.value end;queued={}
profile.tick();assert(profile.read('dof')==1 and not profile.pending())
profile.write('bloom',0);assert(profile.pending('bloom'));profile.write('bloom',1);assert(calls==3)
for _,change in ipairs(queued)do values[change.name]=change.value end;queued={};profile.tick();assert(profile.read('bloom')==1 and not profile.pending())
profile.write('dof',0);for _,change in ipairs(queued)do values[change.name]=change.value end;queued={};profile.tick();assert(values.dof_enabled==false)
print('Renderer settings: serialized values, delayed verification, duplicate suppression, cancellation and exact restore passed')

local lens=dofile(root..'lens.lua');local scene_values={focal_distance=.25,focal_region=.1,focal_region_start=.2,focal_region_end=.2,focal_near_scale=1,focal_far_scale=1,scene_dof=0,scene_bloom=0}
local original={};local parameters={focus_distance=true,aperture=true};for k,v in pairs(scene_values)do original[k]=v;parameters[k]=true end
local flushed=0;DBF_PHOTO_RENDER_PROFILE={world=42,parameters=parameters,read=function(k)return scene_values[k]end,write=function(k,v)scene_values[k]=v end,restore=function(k)scene_values[k]=original[k]end,flush=function()flushed=flushed+1 end}
local effect=dofile(root..'postfx.lua').new({},lens);local o=dofile(root..'photo_options.lua').read({get=function(k)return dofile(root..'photo_options.lua').defaults[k]end})
o.focus_distance=5;o.aperture=1.2;effect.apply(42,o,math.rad(50));local shallow=scene_values.focal_region
assert(scene_values.focal_distance<5 and shallow>0 and flushed>0)
o.aperture=16;effect.apply(42,o,math.rad(50));assert(scene_values.focal_region>shallow)
assert(effect.release());for k,v in pairs(original)do assert(scene_values[k]==v)end;DBF_PHOTO_RENDER_PROFILE=nil
print('Legacy profile math fixture: focal region and owned-value restore; this does not verify engine focus/aperture support')

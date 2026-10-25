local factory=dofile('freecam/steam_scene_overlay.lua')
local created,destroyed,bindings,triangles,removed=0,0,0,0,0
local available,registered,depth_available=true,true,true
local owner,width,token=2,1920,{}
local vectors,scalars={},{}
local fail_triangle,fail_destroy=false,false
local color_available,color_format,color_width,color_backing=true,19,nil,88888
local color_checks=0
local function verify_color()
 color_checks=color_checks+1
 return color_available,{resource=77777,backing=color_backing,id=33554433,format=color_format,width=color_width or width,height=1080,mips=1,array=1,ui_brightness=336.35858,hdr_enabled=true}
end
local depth={binding_identity='a',available=function()return depth_available,'depth unavailable'end,
 get=function()return token,'depth retired'end,
 bind=function(h,key,value)assert(h==33 and key=='diffuse_map'and value==token);bindings=bindings+1;return true end}
local sr={Application={can_get=function(kind,name)assert(kind=='shader_library'and name==factory.shader or kind=='material'and name==factory.material);return available end,
 main_world=function()return 1 end,worlds=function()return {1,owner}end},
 World={create_screen_gui=function(w)assert(w==owner);created=created+1;return created end,
 destroy_gui=function(w)assert(w==owner);if fail_destroy then error('cleanup retry')end;destroyed=destroyed+1 end},
 Gui={resolution=function()return width,1080 end,material=function(_,name)assert(name==factory.material);return 33 end,
 triangle=function(_,a,b,c,layer,_,name,ua,ub,uc)
  assert(a[2]==0 and b[2]==0 and c[2]==0 and layer==88 and name==factory.material and ua and ub and uc)
  assert(bindings>0 and vectors.scissor_rect and vectors.atlas_scissor and vectors.clip_box and scalars.desaturate and scalars.scissor_mode and scalars.threshold_fade,'Bind all uniforms/depth before draw')
  if fail_triangle then error('draw refused')end;triangles=triangles+1;return triangles
 end,destroy_triangle=function()removed=removed+1 end},
 Material={set_scalar=function(_,key,value)scalars[key]=value end,set_resource=function()error('Use verified binder')end,
 set_vector4=function(_,key,value)vectors[key]=value end},
 Vector2=function(...)return {...}end,Vector3=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end}
local registration={present=function()return registered,'not registered'end}
local neutral={dof=false,dof_mode=1,scene_shader=1,exposure=0,contrast=100,saturation=100}
local o={dof=true,dof_mode=2,focus_distance=1.4,aperture=2,bokeh_shape=2,dof_quality=2,
 scene_shader=10,scene_strength=75,scene_depth_range=150,exposure=.5,contrast=120,saturation=65,fog_distance=40,fog_density=80}
local overlay=factory.new(sr,depth,false,registration,verify_color);assert(not overlay.apply(o,.9)and created==0)
overlay=factory.new(sr,depth,true,nil,verify_color);assert(not overlay.apply(o,.9)and created==0,'Registration is mandatory')
overlay=factory.new(sr,depth,true,registration,verify_color)
assert(overlay.apply(neutral,.9)and created==0 and not overlay.shader_dof_active,'Neutral Native preserves the frame without drawing')
registered=false;assert(not overlay.apply(o,.9)and created==0 and not overlay.shader_dof_active);registered=true
available=false;assert(not overlay.apply(o,.9)and created==0);available=true
depth_available=false;assert(not overlay.apply(o,.9)and created==0);depth_available=true
color_available=false;assert(not overlay.apply(o,.9)and created==0 and not overlay.shader_dof_active);color_available=true
color_format=0;assert(not overlay.apply(o,.9)and created==0,'Gbuffer formats cannot masquerade as HDR1 color');color_format=19
color_width=480;assert(not overlay.apply(o,.9)and created==0,'Quarter-size source must never replace the frame');color_width=nil
local ok,_,suppress=overlay.apply(o,.9);assert(ok and suppress and overlay.shader_dof_active and overlay.scene_active)
assert(created==1 and bindings==1 and triangles==2)
assert(vectors.scissor_rect[1]==1.4 and vectors.scissor_rect[2]==2 and vectors.scissor_rect[3]==.9 and vectors.scissor_rect[4]==96)
assert(vectors.atlas_scissor[1]==150 and vectors.atlas_scissor[2]==.8 and vectors.atlas_scissor[3]==6 and vectors.atlas_scissor[4]==1)
assert(vectors.clip_box[1]==.5 and vectors.clip_box[2]==1.2 and vectors.clip_box[3]==.65 and vectors.clip_box[4]==336.35858)
assert(scalars.scissor_mode==9 and scalars.threshold_fade==.75 and scalars.desaturate==40)
local checks=color_checks;assert(overlay.apply(o,.9)and triangles==2 and color_checks>checks,'Color target must be freshly verified even on retained draws')
color_backing=99999;assert(overlay.apply(o,.9)and triangles==4 and overlay.color_binding_identity:find('99999',1,true),'New color backing must invalidate retained carrier')
o.focus_distance=10;assert(overlay.apply(o,.9)and triangles==6 and removed==4 and created==1)
o.dof_mode=1;ok,_,suppress=overlay.apply(o,.9)
assert(ok and not suppress and not overlay.shader_dof_active and vectors.scissor_rect[4]==0 and overlay.scene_active,'Native scene mode disables shader gather without suppressing native DoF')
o.dof_mode=2;o.dof=false;ok,_,suppress=overlay.apply(o,.9)
assert(ok and not suppress and vectors.scissor_rect[4]==0,'DoF-off scenes do not gather or suppress native')
depth.binding_identity='b';assert(overlay.apply(o,.9)and bindings==2,'Backing changes require rebinding')
width=2560;assert(overlay.apply(o,.9)and created==2 and destroyed==1)
assert(overlay.apply(neutral,.9)and destroyed==2 and not overlay.scene_active)
token=nil;assert(not overlay.apply(o,.9)and created==2 and not overlay.shader_dof_active);token={}
o.dof=true;assert(overlay.apply(o,.9));owner=3
assert(overlay.release()and destroyed==2,'Retired worlds must never be destroyed')
overlay=factory.new(sr,depth,true,registration,verify_color);assert(overlay.apply(o,.9));fail_destroy=true
assert(not overlay.release()and not overlay.shader_dof_active,'Failed cleanup retains ownership but closes native-suppression signal')
fail_destroy=false;assert(overlay.release()and destroyed==3)
overlay=factory.new(sr,depth,true,registration,verify_color);fail_triangle=true
ok,_,suppress=overlay.apply(o,.9);assert(not ok and not suppress and not overlay.shader_dof_active and destroyed==4)
fail_triangle=false;assert(not overlay.apply(o,.9),'Draw failure disables that instance')
local u=factory.uniforms({dof=true,dof_mode=2,scene_shader=math.huge,scene_strength=0/0,exposure=0/0,
 contrast=-1,saturation=1000,focus_distance=math.huge,aperture=-1,fog_distance=-1,fog_density=math.huge},0/0)
assert(u.scissor[1]==5 and u.scissor[2]==1.2 and u.scissor[3]==.9 and u.clip[1]==0 and u.clip[2]==.5 and u.clip[3]==2 and u.fog_distance==.1 and u.clip[4]==203,'Non-finite inputs must not reach native setters')
local shader_options={dof=true,dof_mode=2,scene_shader=1,exposure=0,contrast=100,saturation=100}
for _,sample in ipairs({{value=1,packed=24},{value=4,packed=96},{value=8,packed=192},{value=0,packed=24},{value=100,packed=192},{value=0/0,packed=96},{value=math.huge,packed=96}})do
 local values={dof=true,dof_mode=2,dof_strength=sample.value}
 assert(factory.uniforms(values,.9).scissor[4]==sample.packed,'Strength must be finite, bounded and independent from aperture')
 values.dof_mode=1;assert(factory.uniforms(values,.9).scissor[4]==0,'Native ignores shader strength')
end
u=factory.uniforms(shader_options,.9)
assert(u.active and u.shader_dof_active and not u.scene_active and u.clip[1]==0 and u.clip[2]==1 and u.clip[3]==1 and u.clip[4]==203,'Processed-color source uses neutral grade without a brightness or saturation fudge')
assert(shader_options.exposure==0 and shader_options.contrast==100 and shader_options.saturation==100,'Uniform packing never mutates user values')
u=factory.uniforms(neutral,.9)
assert(not u.active and u.clip[1]==0 and u.clip[2]==1 and u.clip[3]==1,'Native without scene adjustments keeps its original color path')
print('Combined scene/DoF: exact shared uniforms, Native/Shader/DoF-off composition, registration/resource/depth/full-color guards, fresh fullsize format/backing verification, draw-before-native-suppression signal, retained draw/rebinding/resize, retired world and cleanup failure passed; no game accessed')

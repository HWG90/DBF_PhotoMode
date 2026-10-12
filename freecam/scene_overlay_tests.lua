local factory=dofile(assert(DBF_PHOTO_TEST_ROOT)..'scene_overlay.lua')
local created,destroyed,bindings,triangles,removed=0,0,0,0,0
local ready=true;local registered=true;local owner=2;local width=1920;local token={};local uniforms={};local fail_material=false;local fail_destroy=false
local sr={Application={can_get=function(kind,name)assert(kind=='shader_library'and name==factory.shader or kind=='material'and name==factory.material);return ready end,main_world=function()return 1 end,worlds=function()return {1,owner}end},
 World={create_screen_gui=function(w)assert(w==owner);created=created+1;return created end,destroy_gui=function(w)assert(w==owner);if fail_destroy then error('destroy temporarily refused')end;destroyed=destroyed+1 end},
 Gui={resolution=function()return width,1080 end,material=function(_,name)assert(name==factory.material);if fail_material then error('material failed')end;return 33 end,
 triangle=function(_,a,b,c,layer,_,name,ua,ub,uc)assert(a[2]==0 and b[2]==0 and c[2]==0 and layer==87 and name==factory.material and uniforms.scissor_rect and bindings>0 and ua and ub and uc);triangles=triangles+1;return triangles end,
 destroy_triangle=function()removed=removed+1 end},
 Material={set_scalar=function()end,set_resource=function()error('Verified depth binder required')end,set_vector4=function(_,key,value)uniforms[key]=value end},
 Vector2=function(...)return {...}end,Vector3=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end}
local depth={binding_identity='a',get=function()return token end,bind=function(h,key,value)assert(h==33 and key=='diffuse_map'and value==token);bindings=bindings+1;return true end}
local registration={present=function()return registered,'not registered'end}
local neutral={scene_shader=1,exposure=0,contrast=100,saturation=100}
local o={scene_shader=10,scene_strength=75,exposure=.5,contrast=120,saturation=65,fog_distance=40,fog_density=80,scene_depth_range=150}
local overlay=factory.new(sr,depth,false,registration);assert(not overlay.apply(o)and created==0)
overlay=factory.new(sr,depth,true);assert(not overlay.apply(o)and created==0,'Registration must be verified before any native material use')
overlay=factory.new(sr,depth,true,registration);assert(overlay.apply(neutral)and created==0,'Neutral options must preserve original full-resolution pixels')
registered=false;assert(not overlay.apply(o)and created==0);registered=true
ready=false;assert(not overlay.apply(o)and created==0);ready=true
assert(overlay.apply(o));assert(created==1 and bindings==1 and triangles==2)
assert(uniforms.scissor_rect[1]==9 and uniforms.scissor_rect[2]==.75 and uniforms.scissor_rect[3]==40 and uniforms.scissor_rect[4]==.8)
assert(uniforms.atlas_scissor[1]==.5 and uniforms.atlas_scissor[2]==1.2 and uniforms.atlas_scissor[3]==.65 and uniforms.atlas_scissor[4]==150)
assert(overlay.apply(o)and triangles==2,'Unchanged controls must not recreate retained carriers')
o.scene_shader=2;assert(overlay.apply(o)and triangles==4 and removed==2 and created==1,'Color inversion gets the correct multiplex index without a new material instance')
depth.binding_identity='b';assert(overlay.apply(o)and bindings==2 and triangles==6,'Texture backing identity changes must rebind even with the same wrapper')
width=2560;assert(overlay.apply(o)and created==2 and destroyed==1)
assert(overlay.apply(neutral)and destroyed==2,'Neutral controls remove the carrier')
local values=factory.uniforms({scene_shader=math.huge,exposure=0/0,contrast=-10,saturation=1000,scene_strength=-1,fog_distance=-1,fog_density=math.huge})
assert(not values.active or values.atlas[2]==.5);assert(values.scissor[1]==0 and values.scissor[2]==0 and values.scissor[3]==.1 and values.scissor[4]==.5 and values.atlas[1]==0 and values.atlas[3]==2,'Non-finite or out-of-range values must never reach native uniforms')
depth.get=function()return nil,'retired depth'end;assert(not overlay.apply(o)and created==2)
depth.get=function()return token end;assert(overlay.apply(o));owner=3;assert(overlay.release()and destroyed==2,'Retired worlds must not receive destroy calls')
overlay=factory.new(sr,depth,true,registration);fail_material=true;assert(not overlay.apply(o)and destroyed==3);fail_material=false;assert(not overlay.apply(o),'A native material error disables only this scene instance')
overlay=factory.new(sr,depth,true,registration);assert(overlay.apply(o));fail_destroy=true;assert(not overlay.release());fail_destroy=false;assert(overlay.release()and destroyed==4,'Failed release keeps ownership for a later cleanup retry')
print('Scene overlay: registration/resource refusal, exact effect/grading/fog uniforms, native XZ/UV carrier order, neutral transparency, backing rebind, resize, retired-world and failure cleanup passed; no game process accessed')

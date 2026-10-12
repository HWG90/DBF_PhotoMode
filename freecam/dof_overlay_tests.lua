local factory=dofile(assert(DBF_PHOTO_TEST_ROOT)..'dof_overlay.lua')
local created,destroyed,bindings,reads,triangles,removed=0,0,0,0,0,0
local ready=true;local owner=2;local width=1920;local token={};local focus
local sr={Application={can_get=function()return ready end,main_world=function()return 1 end,worlds=function()return {1,owner}end},
World={create_screen_gui=function(w)assert(w==owner);created=created+1;return created end,destroy_gui=function(w)assert(w==owner);destroyed=destroyed+1 end},
Gui={resolution=function()return width,1080 end,material=function()return 3 end,
triangle=function(_,a,b,c,layer,_,_,ua,ub,uc)assert(a[2]==0 and b[2]==0 and c[2]==0 and layer==88 and focus and bindings>0 and ua and ub and uc,'Bind resources/uniforms and full UVs before native XZ carrier submission');triangles=triangles+1;return triangles end,
destroy_triangle=function()removed=removed+1 end},
Material={set_scalar=function()end,set_resource=function(_,key,value)assert(key=='diffuse_map'and value==token);bindings=bindings+1 end,
set_vector4=function(_,key,value)if key=='scissor_rect'then focus=value end end},
Vector2=function(...)return {...}end,Vector3=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end}
local depth={get=function()reads=reads+1;return token end}
local o={dof=true,focus_distance=2,aperture=1.2}
local overlay=factory.new(sr,depth,false);assert(not overlay.apply(o,.9)and created==0 and reads==0,'Unverified constructor must never draw')
local missing=factory.new(sr,depth,true,{present=function()return false,'not registered'end})
local drawn,reason=missing.apply(o,.9);assert(not drawn and reason=='not registered'and created==0 and reads==0,'Available assets must never bypass renderer template registration')
overlay=factory.new(sr,depth,true);ready=false;assert(not overlay.apply(o,.9)and created==0 and reads==0,'Absent resources must never call native material APIs')
ready=true;assert(overlay.apply(o,.9));assert(created==1 and bindings==1 and focus[1]==2 and focus[2]==1.2)
o.focus_distance=15;o.aperture=22;assert(overlay.apply(o,.9));assert(created==1 and bindings==1 and focus[1]==15 and focus[2]==22,'Lens edits update uniforms without rebuilding the GUI')
width=2560;assert(overlay.apply(o,.9));assert(created==2 and destroyed==1 and bindings==2,'Resize recreates the owned carrier')
assert(triangles==6 and removed==2,'Retained carrier must be resubmitted after lens edits')
o.dof=false;assert(overlay.apply(o,.9));assert(destroyed==2,'DoF off removes the carrier')
o.dof=true;depth.get=function()return nil,'depth retired'end;assert(not overlay.apply(o,.9)and created==2,'Retired depth must never be bound')
depth.get=function()return token end;assert(overlay.apply(o,.9));owner=3
assert(overlay.release()and destroyed==2,'Retired world must not receive destroy calls')
print('DoF overlay: visual gate, loaded-resource guard, depth binding, focus/aperture uniforms, resize/off cleanup and retired-world refusal passed; no game process accessed')

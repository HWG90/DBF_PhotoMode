local View=dofile('freecam/vendor/view.lua')
local world={};local allocations,destroys,binds,uniforms,geometry=0,0,0,0,0
local width=1920;local refuse=false
local function allocate()
 allocations=allocations+1;if refuse then refuse=false;return nil end;return allocations
end
local function destroy()destroys=destroys+1 end
local G={resolution=function()return width,1080 end,material=function()return{}end,
 create_material=function()return{}end,text=allocate,rect=allocate,triangle=allocate,
 destroy_text=destroy,destroy_rect=destroy,destroy_triangle=destroy}
local sr={Gui=G,Application={worlds=function()return{world}end,main_world=function()return world end,can_get=function()return true end},
 World={create_screen_gui=function()return{}end,destroy_gui=function()end},
 IdString64={from_hex=function(h)return h end},Material={set_texture=function()binds=binds+1 end,
 set_scalar=function()uniforms=uniforms+1 end,set_vector4=function()uniforms=uniforms+1 end},
 Vector2=function(...)return{...}end,Vector3=function(...)return{...}end,Vector4=function(...)return{...}end,Color=function(...)return{...}end}
local font={font='1111111111111111',material='2222222222222222',atlas='3333333333333333'}
local function text()
 local values={type='text',text='Readable',x=10,y=20,size=14,a=1,c={255,255,255}}
 local proxy=setmetatable({},{__index=function(_,key)
  if key=='x'or key=='c'then geometry=geometry+1 end;return values[key]
 end})
 return proxy,values
end
local command,values=text();local commands={command};local token={};local v=View.new(sr,false)
v._accept_font(font);v.draw(commands,token)
local cold_allocations=allocations;local before=binds;geometry=0
for i=1,20 do v.draw(commands,token)end
assert(geometry==0 and allocations==cold_allocations,'Immutable retained draws must skip geometry reads and allocations')
assert(binds==before+20,'Retained font atlas must still bind every frame')
values.x=30;v.draw(commands)
assert(allocations>cold_allocations and destroys>0,'Mutable callers must detect in-place edits')
values.x=40;before=allocations;v.draw(commands,token)
assert(allocations>before,'Mutable draw invalidates previous immutable token')
before=allocations;v._accept_font({font='4444444444444444',material=font.material,atlas=font.atlas});v.draw(commands,token)
assert(allocations>before,'Font changes invalidate retained geometry')
before=allocations;v.clear();v.draw(commands,token);assert(allocations>before,'Clear must invalidate fast state')
before=allocations;world={};v.draw(commands,token);assert(allocations>before,'World replacement must rebuild native primitives')
v.release();refuse=true;before=allocations;v.draw(commands,token);v.draw(commands,token)
assert(allocations>=before+2,'Failed native allocation must retry with the same token')
v.release();width=0;before=allocations;assert(v.draw(commands,token)==false and allocations==before)
width=1920;v.draw(commands,token);assert(allocations>before,'Drawing resumes after invalid resolution')
local preview={type='rect',x=0,y=0,w=20,h=20,a=1,c={255,255,255},hud_preview=true,
 preview_material='owned_preview',preview_mapping={1,2,3,4,5,6,7,8,9},preview_time=1}
local mixed={command,preview};v.draw(mixed,mixed);before=uniforms
preview.preview_time=2;v.draw(mixed,mixed)
assert(uniforms>before,'Dynamic preview uniforms must update despite the stable outer token')
preview.preview_static=true;local static_mixed={command,preview};v.draw(static_mixed,static_mixed)
before=uniforms;local static_allocations=allocations;geometry=0
for _=1,20 do v.draw(static_mixed,static_mixed)end
assert(uniforms==before and allocations==static_allocations and geometry==0,
 'Explicit immutable static previews skip geometry scans and uniform writes')
preview.preview_time=3;v.draw(static_mixed)
assert(uniforms>before,'Static preview flag never weakens mutable caller behavior')
v.release()
local required=View.new(sr,true)
local required_commands={{type='rect',x=0,y=0,w=20,h=20,a=1,c={255,255,255},
 preview_material='owned_required',preview_required=true}}
required.draw(required_commands);local required_allocations,required_destroys=allocations,destroys
local can_get=sr.Application.can_get;sr.Application.can_get=function()return false end
assert(required.draw(required_commands)==false and allocations==required_allocations and destroys==required_destroys,
 'Required preview preflight must preserve prior IDs and GUI ownership before refusing')
sr.Application.can_get=can_get;required.draw(required_commands)
assert(allocations==required_allocations,'Preflight refusal must preserve reusable owned primitives')
required.release();assert(destroys==required_destroys+2,'Refused preview must still retire both owned triangles')
for _,plane in ipairs({'hud_preview','popup'})do
 local parent=View.new(sr,false)
 local child={type='rect',x=0,y=0,w=20,h=20,a=1,c={255,255,255},
  preview_material='owned_'..plane,preview_required=true};child[plane]=true
 local commands={command,child}
 assert(parent.draw(commands,commands)==nil,'A nil child draw result remains normal initial success')
 local allocated,destroyed=allocations,destroys;sr.Application.can_get=function()return false end
 local ok,why=parent.draw(commands,commands)
 assert(ok==false and why=='Required preview material unavailable',plane..' refusal must precede cached parent success')
 assert(allocations==allocated and destroys==destroyed,'Child refusal preserves existing parent and child nodes')
 sr.Application.can_get=can_get
 assert(parent.draw(commands,commands)==true,'A recovered nil child draw result permits cached parent success')
 parent.release()
end
local nested=View.new(sr,false);local triangle,destroy_triangle,destroy_gui=G.triangle,G.destroy_triangle,sr.World.destroy_gui
local attempts=0
G.triangle=function(...)attempts=attempts+1;if attempts==1 then return nil end;return triangle(...)end
G.destroy_triangle=function()return false end
local child={type='rect',x=0,y=0,w=20,h=20,a=1,c={255,255,255},hud_preview=true,
 preview_material='owned_child',preview_required=true}
local ok,why=nested.draw({command,child})
assert(ok==false and why=='Preview cleanup pending','Parent draw must propagate child pending retirement')
local pending_allocations=allocations
for _=1,20 do local ready,reason=nested.draw({command,child});assert(ready==false and reason==why)end
assert(allocations==pending_allocations,'Pending child cleanup cannot allocate a main plane or report parent success')
sr.World.destroy_gui=function()return false end
assert(nested.release()==false,'Parent release must propagate pending whole-GUI retirement from its child')
sr.World.destroy_gui=destroy_gui;assert(nested.release()~=false)
G.triangle,G.destroy_triangle=triangle,destroy_triangle
-- Empty draws must propagate whole-GUI retirement refusal for a complete quad.
-- The same owned GUI remains blocked until explicit retirement succeeds.
for _,fault in ipairs({'refuse','throw'})do
 local complete=View.new(sr,true)
 assert(complete.draw(required_commands)~=false)
 local retire_calls=0
 sr.World.destroy_gui=function()
  retire_calls=retire_calls+1
  if fault=='throw'then error('whole GUI retirement threw')end
  return false
 end
 local ok,why=complete.draw({})
 assert(ok==false and why=='Preview cleanup pending','Empty draw must propagate failed whole-GUI retirement')
 local before_allocations,before_retire=allocations,retire_calls
 for _=1,20 do assert(complete.draw(required_commands)==false)end
 assert(allocations==before_allocations and retire_calls==before_retire,
  'Pending complete-GUI ownership adds no automatic drawing or retirement work')
 sr.World.destroy_gui=destroy_gui
 assert(complete.release()~=false and complete.draw(required_commands)~=false)
 assert(complete.release()~=false)
end
-- Routine draws never write per-primitive text reports to the log.
do
 local messages={};local d=View.new(sr,true,function(line)messages[#messages+1]=line end)
 d.draw({{type='text',text='Quiet',x=10,y=20,size=14,a=1,c={255,255,255}}})
 assert(#messages==0,'Text diagnostics are opt-in');assert(d.release()~=false)
end
-- Diagnostic bookkeeping is lazy, but its one-shot output and explicit release
-- reset must remain identical for mutable as well as retained callers.
DBF_VIEW_TEXT_DIAGNOSTICS=true
do
 local messages={};local d=View.new(sr,true,function(line)messages[#messages+1]=line end)
 local label={type='text',text='Diagnostic',x=10,y=20,size=14,a=1,c={255,255,255}}
 local commands={label,{type='rect',x=30,y=40,w=50,h=60,a=1,c={255,255,255}}}
 local first=allocations+1
 d.draw(commands)
 assert(#messages==2 and messages[1]=='MCM TEXT DIAGNOSTIC primitives=2 duplicate_handles=0')
 assert(messages[2]=='MCM TEXT 1 z=101.00 label="Diagnostic" allocation='..first)
 local allocated=allocations
 for _=1,20 do d.draw(commands)end
 assert(#messages==2 and allocations==allocated,'Mutable unchanged frames retain primitives without repeating diagnostics')
 label.x=11;d.draw(commands)
 assert(#messages==2 and allocations==allocated+1,'Mutable changes do not restart one-shot diagnostics')
 assert(d.release()~=false)
 first=allocations+1;d.draw(commands,commands)
 assert(#messages==4 and messages[3]=='MCM TEXT DIAGNOSTIC primitives=2 duplicate_handles=0')
 assert(messages[4]=='MCM TEXT 1 z=101.00 label="Diagnostic" allocation='..first)
 allocated=allocations
 for _=1,20 do d.draw(commands,commands)end
 assert(#messages==4 and allocations==allocated,'Retained frames preserve the one-shot diagnostic contract')
 assert(d.release()~=false)
end
DBF_VIEW_TEXT_DIAGNOSTICS=nil
print('Steam retained view: immutable/static geometry, mutable safety, font binding, lifetime/retry and required/dynamic previews passed')

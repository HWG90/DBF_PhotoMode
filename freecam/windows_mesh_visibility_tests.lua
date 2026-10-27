local M=dofile('freecam/windows_mesh_visibility.lua')
local function fixture()
 local f={world={},writes=0};local a,b,c={visible=true,shadow=false},{visible=false,shadow=true},{visible=true,shadow=true}
 local u={meshes={a,b,c},alive=true,resource='outfit'};f.u,f.a,f.b,f.c=u,a,b,c
 local sr={Unit={alive=function(x)return x.alive end,world=function()return f.world end,resource_name=function(x)return x.resource end,
  num_meshes=function(x)return #x.meshes end,mesh=function(x,i)return x.meshes[i]end,
  set_mesh_visibility=function(x,i,v,context)
   assert(context=='default');f.writes=f.writes+1;x.meshes[i].visible=v
   if f.fail and not v then f.fail=false;error('Setter failed after write')end
   if f.refuse_restore and v then x.meshes[i].visible=false end
  end},Mesh={visibility=function(m)return m.visible end}}
 f.service=M.new(sr);f.rows={{unit=u,world=f.world,resource=u.resource,indices={1,2,3}}};return f
end
local f=fixture();assert(f.service.hide(f.rows));assert(f.writes==2 and f.service.count()==2 and not f.a.visible and not f.b.visible)
assert(not f.a.shadow and f.b.shadow and f.c.shadow,'Other culling contexts remain unchanged')
f.u.meshes={f.c,f.b,f.a};assert(f.service.release());assert(f.a.visible and f.c.visible and not f.b.visible,'Reordered meshes restore by object identity; pre-hidden stays hidden')
local writes=f.writes;assert(f.service.release()and f.writes==writes,'Repeated release is idle')
local retired=fixture();retired.service.hide(retired.rows);retired.u.alive=false;assert(retired.service.release()and retired.writes==2)
local foreign=fixture();foreign.service.hide(foreign.rows);foreign.a.visible=true;assert(foreign.service.release()and foreign.writes==3)
local partial=fixture();partial.fail=true;assert(not partial.service.hide(partial.rows));assert(partial.a.visible and partial.service.count()==0,'Partial write is rolled back')
local retry=fixture();retry.service.hide(retry.rows);retry.refuse_restore=true;assert(not retry.service.release()and retry.service.count()==2)
retry.refuse_restore=false;assert(retry.service.release()and retry.service.count()==0)
local invalid=fixture();invalid.rows[2]={unit=invalid.u,world={},resource='outfit',indices={1}}
assert(not invalid.service.hide(invalid.rows)and invalid.writes==0,'Whole request validation precedes mutations')
print('Windows mesh visibility: explicit default context, pre-hidden/foreign state, mesh reorder, retirement, partial writes and restoration retry passed')

local force=fixture();assert(force.service.hide(force.rows));local writes=force.writes
assert(force.service.reassert()and force.writes==writes,'Already hidden meshes have no enforcement writes')
force.a.visible=true;assert(force.service.reassert());assert(not force.a.visible and force.writes==writes+1)
force.u.resource='replacement';assert(not force.service.reassert()and force.writes==writes+1,'Never enforce against a replaced resource')

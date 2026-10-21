-- Standalone source-only contracts. No game, native DLL, clock or asset writes.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'),'Run in actual Lua 5.1')
local Overlay=dofile('freecam/steam_overlay.lua')
local View=dofile('freecam/vendor/view.lua')
local catalog=dofile('freecam/composition.lua')
local function options(index,animated)
 return{shader=index or 2,shader_opacity=37,shader_scale=2,shader_animate=animated==true}
end
local function fixture()
 local f={world={},queries=0,creates=0,releases=0,allocations=0,destroys=0,uniforms=0,materials=0,
  available=true,nodes={},width=1920,views=0,last_vectors={}}
 local sr={Application={},Gui={},World={},Material={}}
 sr.Application.time_since_launch=function()error('Adapter must use supplied time')end
 sr.Application.worlds=function()return{f.world}end
 sr.Application.main_world=function()return f.world end
 sr.Application.can_get=function(kind,path)
  f.queries=f.queries+1;assert(kind=='material'and path:match('^mods/dbf_photo/materials/mapped_[a-z0-9_]+$'))
  f.path=path;if f.query_error then error('availability failed')end
  if f.late_missing and f.queries>=3 then return false end;return f.available
 end
 sr.Gui.resolution=function()return f.width,1080 end
 sr.World.create_screen_gui=function()f.creates=f.creates+1;return{}end
 sr.World.destroy_gui=function(_,gui)
  f.destroys=f.destroys+1
  if f.gui_destroy_error then error('GUI retirement failed')end
  if f.gui_destroy_refuse then return false,'GUI retirement refused'end
  for id,node in pairs(f.nodes)do if node.gui==gui then f.nodes[id]=nil end end
 end
 sr.Gui.material=function(_,path)
  f.materials=f.materials+1;return{path=path,generation=f.materials}
 end
 sr.Material.set_scalar=function(handle)
  assert(handle.generation==f.materials,'Never reuse a prior native material handle')
  f.uniforms=f.uniforms+1;if f.uniform_error then error('uniform failed')end
 end
 sr.Material.set_vector4=function(handle,name,value)
  assert(handle.generation==f.materials);f.uniforms=f.uniforms+1;f.last_vectors[name]=value
 end
 sr.Gui.triangle=function(gui,a,b,c,z,color,material)
  f.allocations=f.allocations+1;if f.fail_triangle==f.allocations then return nil end
  f.nodes[f.allocations]={gui=gui,a=a,b=b,c=c,z=z,color=color,material=material};return f.allocations
 end
 sr.Gui.destroy_triangle=function(_,id)
  f.triangle_destroys=(f.triangle_destroys or 0)+1
  if f.triangle_destroy_error then error('triangle retirement failed')end
  if f.triangle_destroy_refuse then return false end
  f.nodes[id]=nil
 end
 sr.Gui.rect=function()error('Decorative overlays must never use a solid rectangle fallback')end
 sr.Vector2=function(...)return{...}end;sr.Vector3=sr.Vector2;sr.Vector4=sr.Vector2;sr.Color=sr.Vector2
 local views={new=function(native,preview,log)
  assert(preview==true);f.views=f.views+1
  local v=View.new(native,preview,log);local release,draw=v.release,v.draw
  v.release=function()
   f.releases=f.releases+1
   if f.release_error then error('retirement failed')end
   if f.release_refuse then return false,'retirement refused'end
   return release()
  end
  v.draw=function(commands,token)f.commands,f.token=commands,token;return draw(commands,token)end
  return v
 end}
 f.overlay=Overlay.new(sr,views,catalog);return f
end
do
 local f=fixture();local o=options();o.shader=1
 assert(not f.overlay.draw(1920,1080,o,0));assert(f.overlay.open())
 for _=1,200 do assert(f.overlay.draw(1920,1080,o))end
 assert(f.queries==0 and f.creates==0 and f.views==0,'None must remain completely idle')
 o=options();assert(f.overlay.draw(1920,1080,o))
 assert(f.path=='mods/dbf_photo/materials/mapped_crt_scan'and f.allocations==2)
 local c=f.commands[1];assert(c.layer==90 and c.a==.37 and c.preview_static and f.token==f.commands)
 assert(c.x==0 and c.y==0 and c.w==1920 and c.h==1080)
 assert(f.last_vectors.scissor_rect[1]==2 and f.last_vectors.scissor_rect[4]==0)
 assert(f.last_vectors.atlas_scissor[2]==2 and f.last_vectors.atlas_scissor[4]==0)
 assert(f.last_vectors.clip_box[3]==1)
 local q,u,a,m=f.queries,f.uniforms,f.allocations,f.materials
 for i=1,200 do assert(f.overlay.draw(1920,1080,o,i))end
 assert(f.queries==q and f.uniforms==u and f.allocations==a and f.materials==m,
  'Immutable static overlays do no repeated material discovery, uniform writes or node work')
 o.shader_scale=4;assert(f.overlay.draw(1920,1080,o));assert(f.last_vectors.scissor_rect[1]==1 and f.allocations==a)
 o.shader_animate=true;assert(f.overlay.draw(1920,1080,o,7));q,u=f.queries,f.uniforms
 for i=1,20 do assert(f.overlay.draw(1920,1080,o,7+i/10))end
 assert(f.allocations==a and f.uniforms>u and f.queries==q+40,
  'Animation updates fresh material uniforms without node churn, retaining bounded active material guards')
 assert(f.last_vectors.scissor_rect[4]==9 and f.last_vectors.atlas_scissor[4]==1)
 assert(not f.overlay.draw(1920,1080,o,0/0),'Animated time must be finite')
 o.shader_opacity=0;assert(f.overlay.draw(1920,1080,o));q,u,a=f.queries,f.uniforms,f.allocations
 for _=1,200 do assert(f.overlay.draw(1920,1080,o))end
 assert(f.releases==1 and next(f.nodes)==nil and f.queries==q and f.uniforms==u and f.allocations==a)
 assert(f.overlay.dispose()and not f.overlay.open(),'Disposal retires the adapter')
end
do
 local f=fixture();assert(f.overlay.open());f.available=false;local o=options()
 assert(not f.overlay.draw(1920,1080,o));local q=f.queries
 f.available=true;for _=1,300 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.views==0,'Remember unavailable assets without polling or allocating a GUI')
 assert(f.overlay.invalidate());assert(f.overlay.draw(1920,1080,o));assert(f.queries>q)
 local a=f.allocations;q=f.queries;f.world={};assert(f.overlay.draw(1920,1080,o))
 assert(f.allocations==a+2 and f.queries>q,'Static cache must retain native lifetime guards')
 local copper
 for i,name in ipairs(catalog.shaders)do if name=='oxidized_copper'then copper=i end end
 o.shader=copper;assert(f.overlay.draw(1920,1080,o))
 assert(f.commands[1].c[1]==188 and f.commands[1].c[2]==110 and f.commands[1].c[3]==66,'Preserve catalog carrier color')
 q=f.queries;assert(f.overlay.open());assert(f.overlay.draw(1920,1080,o));assert(f.queries>q,'Reopen explicitly retries availability')
 assert(f.overlay.close())
end
do
 local f=fixture();assert(f.overlay.open());local o=options(2,true)
 assert(f.overlay.draw(1920,1080,o,1));local a=f.allocations
 f.available=false;assert(not f.overlay.draw(1920,1080,o,2))
 assert(next(f.nodes)==nil and f.allocations==a and f.releases==1,
  'Positive-to-missing animated material retires its quad without solid fallback or leaked nodes')
 local q=f.queries;for _=1,100 do assert(not f.overlay.draw(1920,1080,o,3))end
 assert(f.queries==q,'Material loss stays unavailable until explicit invalidation')
 f.available=true;assert(f.overlay.invalidate()and f.overlay.draw(1920,1080,o,4));assert(f.overlay.close())
end
do
 local f=fixture();assert(f.overlay.open());local o=options();assert(f.overlay.draw(1920,1080,o))
 local a,creates=f.allocations,f.creates;f.world={};f.available=false
 assert(not f.overlay.draw(1920,1080,o))
 assert(f.allocations==a and f.creates==creates and f.releases==1,
  'Missing material after static world replacement refuses before GUI allocation or fallback')
 assert(f.overlay.close())
end
do
 local f=fixture();assert(f.overlay.open());f.late_missing=true
 assert(not f.overlay.draw(1920,1080,options(2,true),1))
 local _,pending=f.overlay.status();assert(pending and f.allocations==0,
  'Availability loss after preflight must never fall through to a solid rectangle')
 assert(f.overlay.close()and f.destroys==1,'Late guard failure retains a GUI that can be retired')
end
do
 local f=fixture();assert(f.overlay.open());f.query_error=true;local o=options()
 assert(not f.overlay.draw(1920,1080,o));local q=f.queries
 for _=1,20 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.views==0,'Thrown discovery must also remain idle')
 f.query_error=false;o.shader=3;assert(f.overlay.draw(1920,1080,o),'Selection change explicitly retries discovery')
 q=f.queries;assert(not f.overlay.draw(1920,1080,{shader=999}));assert(f.queries==q,'Unknown shaders never query a fallback path')
 assert(f.overlay.close())
end
for _,fault in ipairs({'release_refuse','release_error'})do
 local f=fixture();assert(f.overlay.open());local o=options();assert(f.overlay.draw(1920,1080,o))
 f[fault]=true;o.shader=1;assert(not f.overlay.draw(1920,1080,o));local releases,q=f.releases,f.queries
 local _,pending=f.overlay.status();assert(pending and next(f.nodes),'Retirement failure preserves owned GUI')
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.releases==releases and f.queries==q,'Pending cleanup performs no automatic retries')
 assert(not f.overlay.dispose()and not f.overlay.open(),'Explicit retry cannot discard refused ownership')
 f[fault]=false;assert(f.overlay.dispose());assert(next(f.nodes)==nil and not f.overlay.open())
end
do
 local f=fixture();assert(f.overlay.open());f.uniform_error=true
 assert(not f.overlay.draw(1920,1080,options()));local _,pending=f.overlay.status();assert(pending)
 local queries,creates=f.queries,f.creates
 for _=1,30 do assert(not f.overlay.draw(1920,1080,options()))end
 assert(f.queries==queries and f.creates==creates,'Thrown drawing retains its GUI without automatic work')
 f.uniform_error=false;assert(f.overlay.close()and f.destroys==1)
end
do
 local f=fixture();assert(f.overlay.open());f.fail_triangle=2;local o=options()
 assert(not f.overlay.draw(1920,1080,o)and next(f.nodes)==nil,'Incomplete quad must not cache or leak its surviving triangle')
 local q,a,r,u=f.queries,f.allocations,f.releases,f.uniforms
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.allocations==a and f.releases==r and f.uniforms==u and r==1,
  'An incomplete preview retires once and performs no unchanged native work')
 assert(f.overlay.invalidate()and f.overlay.draw(1920,1080,o)and f.allocations==4,
  'Explicit invalidation recovers an incomplete quad')
 a,u=f.allocations,f.uniforms;assert(f.overlay.draw(1920,1080,o));assert(f.allocations==a and f.uniforms==u)
 f.width=0;assert(not f.overlay.draw(1920,1080,o),'Static cache must retain drawability guards')
 f.width=1920;q,a,r=f.queries,f.allocations,f.releases
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.allocations==a and f.releases==r,
  'Restored drawability does not silently retry the refused preview')
 assert(f.overlay.close()and f.overlay.open()and f.overlay.draw(1920,1080,o))
 assert(f.overlay.close())
end
for _,fault in ipairs({'release_refuse','release_error'})do
 local f=fixture();assert(f.overlay.open());local o=options();assert(f.overlay.draw(1920,1080,o))
 f[fault]=true;f.width=0;assert(not f.overlay.draw(1920,1080,o))
 local _,pending=f.overlay.status();assert(pending and next(f.nodes),'Refused preview retirement preserves ownership')
 local q,a,r=f.queries,f.allocations,f.releases
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.allocations==a and f.releases==r,'Pending refused-preview retirement stays idle')
 f[fault]=false;f.width=1920
 assert(f.overlay.close()and f.overlay.open()and f.overlay.draw(1920,1080,o)and f.overlay.close())
end
for _,fault in ipairs({'gui_destroy_refuse','gui_destroy_error'})do
 local f=fixture();assert(f.overlay.open());local o=options();assert(f.overlay.draw(1920,1080,o))
 assert(f.nodes[1]and f.nodes[2],'Complete preview must own both native triangles')
 f.triangle_destroy_refuse=true;f[fault]=true
 assert(not f.overlay.close()and f.nodes[1]and f.nodes[2],
  'Failed complete-GUI retirement preserves both surviving native triangles')
 local _,pending=f.overlay.status();assert(pending,'Complete-GUI retirement must retain pending adapter ownership')
 assert(not f.overlay.dispose()and f.nodes[1]and f.nodes[2],
  'Disposal cannot discard a refused or throwing complete-GUI retirement')
 local q,a,r,d,t=f.queries,f.allocations,f.releases,f.destroys,f.triangle_destroys
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==q and f.allocations==a and f.releases==r and f.destroys==d and f.triangle_destroys==t,
  'Pending complete-GUI retirement adds no queries, allocations or destructor retries')
 f[fault]=false;f.triangle_destroy_refuse=false
 assert(f.overlay.dispose()and next(f.nodes)==nil,'Explicit acknowledged GUI disposal retires all native nodes')
 assert(f.triangle_destroys==t,'Whole-GUI recovery must not retry the failed child destructor')
end
for _,fault in ipairs({'triangle_destroy_refuse','triangle_destroy_error'})do
 local f=fixture();assert(f.overlay.open());f.fail_triangle=2;f[fault]=true;local o=options()
 assert(not f.overlay.draw(1920,1080,o))
 local _,pending=f.overlay.status()
 assert(pending and f.nodes[1]and f.triangle_destroys==1,
  'Failed partial-quad cleanup must retain its survivor and require whole-GUI retirement')
 local queries,allocations=f.queries,f.allocations
 for _=1,100 do assert(not f.overlay.draw(1920,1080,o))end
 assert(f.queries==queries and f.allocations==allocations and f.triangle_destroys==1,
  'Pending partial cleanup must block native queries, deletion retries and new nodes')
 f.gui_destroy_refuse=true;assert(not f.overlay.close()and f.nodes[1],'Refused whole-GUI retirement preserves the survivor')
 f.gui_destroy_refuse=false;f.gui_destroy_error=true
 assert(not f.overlay.dispose()and f.nodes[1],'Throwing whole-GUI retirement preserves the survivor')
 f.gui_destroy_error=false;assert(f.overlay.dispose()and next(f.nodes)==nil)
 assert(f.triangle_destroys==1,'Recovery retires the whole GUI without retrying the failed triangle destructor')
end
-- Count only portable Lua bookkeeping: these native doubles return retained
-- sentinels instead of allocating mock vector/material/world tables per call.
-- Geometry, uniforms and lifetime behavior are checked independently above.
do
 local world,gui,handle,vector={},{},{},{};local worlds={world}
 local queries,materials,uniforms,triangles=0,0,0,0
 local sr={Application={},Gui={},World={},Material={}}
 sr.Application.worlds=function()return worlds end;sr.Application.main_world=function()return world end
 sr.Application.can_get=function()queries=queries+1;return true end
 sr.Gui.resolution=function()return 1920,1080 end
 sr.World.create_screen_gui=function()return gui end;sr.World.destroy_gui=function()end
 sr.Gui.material=function()materials=materials+1;return handle end
 sr.Material.set_scalar=function()uniforms=uniforms+1 end;sr.Material.set_vector4=sr.Material.set_scalar
 sr.Gui.triangle=function()triangles=triangles+1;return triangles end;sr.Gui.destroy_triangle=function()end
 sr.Vector2=function()return vector end;sr.Vector3=sr.Vector2;sr.Vector4=sr.Vector2;sr.Color=sr.Vector2
 local adapter=Overlay.new(sr,View,catalog);local o=options(2,true)
 assert(adapter.open()and adapter.draw(1920,1080,o,0))
 for i=1,100 do assert(adapter.draw(1920,1080,o,i/100))end
 local q,m,u,t=queries,materials,uniforms,triangles
 collectgarbage('collect');collectgarbage('stop');local kb=collectgarbage('count')
 for i=1,2000 do assert(adapter.draw(1920,1080,o,i/100))end
 local bytes=(collectgarbage('count')-kb)*1024;collectgarbage('restart')
 assert(bytes/2000<400,'Unchanged animation must avoid per-frame helper/key/diagnostic allocation')
 assert(queries==q+4000 and materials==m+2000 and uniforms==u+10000 and triangles==t,
  'Allocation optimization preserves both material guards, fresh handles, all uniforms and retained geometry')
 assert(adapter.dispose())
end
print('Steam decorative overlay: private selection, lazy discovery, static idle, guarded animation, lifetime and cleanup retry passed')

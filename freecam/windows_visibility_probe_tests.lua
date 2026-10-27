local P=dofile('freecam/windows_visibility_probe.lua')
local function fixture(ignored,mode,lease_factory)
 local f={writes=0,created=0,released=0,reads=0};local main,private,unit,mesh={},{},{},{}
 local values={default=true,shadow_caster=true,occluder=true}
 local sr={Application={main_world=function()return main end,can_get=function()return true end,
  new_world=function()f.created=f.created+1;return private end,
  release_world=function(w)assert(w==private);if f.fail_release then error('release refused')end;f.released=f.released+1 end},
  World={spawn_unit=function(w)assert(w==private);if f.fail_spawn then error('spawn refused')end;return unit end},
  Unit={alive=function(u)return u==unit end,world=function(u)assert(u==unit);return private end,
   resource_name=function(u)assert(u==unit);return 'private-copy'end,
   num_meshes=function()return 5 end,mesh=function(u,index)assert(u==unit and index>=1 and index<=5);return mesh end,
   set_mesh_visibility=function(u,index,value,context)
    assert(u==unit and index==1);f.writes=f.writes+1
    if ignored then values.default=value else values[context]=value end
   end},Mesh={visibility=function(m)assert(m==mesh);f.reads=f.reads+1;return values.default end},
   IdString64={from_hex=function(s)assert(s:match('^%x+$')and #s==16);return s end}}
 local t=0;f.p=P.new(sr,function(s)f.log=s end,function()t=t+.0001;return t end,mode,lease_factory)
 return f
end
local f=fixture();for _=1,4 do f.p.tick()end
assert(f.p.result.passed and f.created==1 and f.released==1 and f.writes==7)
for _=1,120 do f.p.tick()end;assert(f.created==1 and f.writes==7 and f.reads==7,'Completed probe stays idle')
assert(f.p.release()and f.released==1,'Cleanup is idempotent')
local bad=fixture(true);for _=1,4 do bad.p.tick()end
assert(not bad.p.result.passed and bad.released==1 and bad.writes==2,'Ignored context is rejected on a disposable copy')
local spawn=fixture();spawn.fail_spawn=true;for _=1,3 do spawn.p.tick()end
assert(not spawn.p.result.passed and spawn.released==1 and spawn.writes==0,'Spawn failure still releases private world')
local cleanup=fixture();cleanup.p.tick();cleanup.fail_release=true;assert(not cleanup.p.release())
cleanup.fail_release=false;assert(cleanup.p.release()and cleanup.released==1,'Failed cleanup retains ownership for retry')
local catalog=fixture(false,'private-mesh-catalog-v1');for _=1,68 do catalog.p.tick()end
assert(catalog.p.result.passed and catalog.created==17 and catalog.released==17 and catalog.writes==119,'Catalog releases each private world before the next resource')
for _=1,120 do catalog.p.tick()end;assert(catalog.created==17,'Catalog does not repeat')
local hold=fixture(false,'private-visibility-hold-v1',dofile('freecam/windows_mesh_visibility.lua'))
for _=1,3 do hold.p.tick()end;assert(not hold.p.result and hold.released==0,'Keep the hidden copy alive across callbacks')
hold.p.tick();hold.p.tick();assert(hold.p.result.passed and hold.released==1,'Cross-callback restoration verified before disposal')
print('Private visibility probe: context discrimination, disposable ownership, idle completion and cleanup failure/retirement passed')

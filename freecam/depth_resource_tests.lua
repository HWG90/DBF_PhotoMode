local root=assert(DBF_PHOTO_TEST_ROOT)
local factory=dofile(root..'depth_resource.lua')
local calls=0;local verified=true;local token={}
local sr={Renderer={resource=function(name)assert(name=='linear_depth');calls=calls+1;return token end}}
local depth=factory.new(sr,function()return verified end)
assert(depth.get()==token and calls==1)
verified=false;assert(depth.get()==nil and calls==1,'Missing target must never invoke the native lookup')
verified=true;sr.Renderer.resource=function()error('lookup failed')end
local value,why=depth.get();assert(value==nil and why:find('lookup failed',1,true))
depth=factory.new(sr,function()error('retired target')end)
value,why=depth.get();assert(value==nil and why:find('retired target',1,true),'Validation failure must be contained')
sr.Renderer.resource=function()return nil end;depth=factory.new(sr,function()return true end)
assert(depth.get()==nil,'Null resources must not be bound')
print('Depth target lookup: existing-only validation, absent/retired refusal, native failure containment and null rejection passed; no game process accessed')

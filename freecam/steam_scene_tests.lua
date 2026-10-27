local M=dofile('freecam/steam_scene.lua');local now=0;local samples=0;local writes=0;local last;local released=0
local sampler={sample=function(u,v)samples=samples+1;last={u,v};if now<2 then return nil,'display settling',{retry_at=2}end;return 7.125 end,release=function()released=released+1;return true end}
local overlay={ready=function()return true end,apply=function()return true end,release=function()released=released+1;return true end}
local c=M.new({Gui={resolution=function()return 1000,500 end}},{},overlay,sampler,function()return now end)
local o={focus_mode=2};local function blocked(x)return x<100 end;local function set(v)writes=writes+1;assert(v==7.125);return true end
local function step(x,y,down)c.focus(o,{x=x,y=y,click=down},true,blocked,false,set)end
step(20,250,true);now=.1;step(20,250,false);now=.2;step(20,250,true);assert(samples==0,'Menu double-click sampled scene')
now=.3;step(500,100,false);now=.4;step(500,100,true);now=.5;step(500,100,false);now=.6;step(500,100,true)
assert(samples==1 and writes==0 and last[1]==.5 and last[2]==.8,'Scene click must retain top-left UV while display settles')
now=1;step(500,100,false);assert(samples==1)
now=2;step(500,100,false);assert(samples==2 and writes==1,'Delayed subject focus was lost')
o.focus_mode=3;now=3;c.focus(o,nil,false,blocked,false,set);assert(samples==3 and writes==2 and last[1]==.5 and last[2]==.5)
now=3.2;c.focus(o,nil,false,blocked,false,set);assert(samples==3,'Center focus ignored cooldown')
o.dof=false;now=5;c.focus(o,nil,false,blocked,false,function()error('Disabled focus control was written')end)
assert(samples==3,'Disabled DoF must not sample depth or write disabled focus controls')
assert(c.release()and released==2)
sampler.sample=function(u,v,fresh)assert(u==.25 and v==.8 and fresh==true);return .708 end
assert(c.pick_depth(250,100,1000,500)==.708,'Subject picking shares qualified fresh top-left depth')
print('Scene focus input: menu exclusion, top-left double-click UV, delayed display retry, center cooldown and cleanup passed')

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
-- After one over-budget read the sampler suspends continuous reads. Center
-- focus then follows a centred Helldiver's skeleton and reads scenery once per
-- camera stop, never while the camera moves.
local suspended,reads,skeleton,scenery=false,{},nil,12.5
local slow={sample=function(u,v,fresh,automatic)
  reads[#reads+1]={u=u,v=v,fresh=fresh,automatic=automatic}
  if automatic and suspended then return nil,'Center auto-focus paused to avoid stutter.'end
  suspended=true;return scenery end,
 release=function()return true end,metrics=function()return{automatic_suspended=suspended}end}
local centers=0
local pick={center=function(camera)centers=centers+1;assert(camera.pos and camera.forward);if skeleton then return skeleton end;return nil,'No Helldiver at the center'end}
local cam={pos={0,0,1},forward={1,0,0}};local focus_value,lens_writes=nil,0
local function setter(v)lens_writes=lens_writes+1;focus_value=v;return true end
local function scene_with(p)return M.new({Gui={resolution=function()return 1000,500 end}},{},overlay,slow,function()return now end,p)end
local c2=scene_with(pick);local opts={focus_mode=3}
local function frame(t,camera)now=t;opts.focus_distance=focus_value;return c2.focus(opts,nil,false,blocked,false,setter,camera==nil and cam or camera or nil)end
frame(0)
assert(#reads==1 and reads[1].automatic==true and focus_value==12.5,'The first slow read still focuses')
for t=.1,3,.1 do frame(t)end
assert(#reads==1,'A suspended sampler must not reread a view it already focused')
local message
for i=1,10 do cam.pos={i*.1,0,1};message=frame(3+i*.1)end
assert(#reads==1 and message=='Center auto-focus: focuses when the camera stops','No depth read while the camera moves')
scenery=30
for t=4.05,6,.05 do message=frame(t)end
assert(#reads==2 and reads[2].automatic==false and reads[2].fresh==false and reads[2].u==.5 and reads[2].v==.5,'Exactly one one-off read per camera stop')
assert(focus_value==30 and lens_writes==2)
skeleton=3.2;cam.pos={2,0,1};message=frame(6.5)
assert(focus_value==3.2 and message=='Focus 3.200 m (Helldiver)'and #reads==2,'A centred Helldiver is focused from its skeleton')
local writes_before=lens_writes;skeleton=3.21;frame(6.8);frame(7.1)
assert(lens_writes==writes_before,'Idle motion inside the dead band must not rewrite the lens')
skeleton=3.6;frame(7.4);assert(focus_value==3.6)
for i=1,8 do cam.pos={2+i*.1,0,1};frame(7.4+i*.1)end
assert(#reads==2 and focus_value==3.6,'A moving camera on a Helldiver keeps skeleton focus without depth reads')
skeleton=nil
for t=8.3,9.5,.05 do frame(t)end
assert(#reads==3 and focus_value==30,'Scenery is read once after leaving the Helldiver')
local checks=centers;for t=9.51,10,.01 do frame(t)end
assert(centers-checks<=3,'Skeleton checks are rate-limited')
-- Without a picker the scenery path still works; without a camera the old
-- suspended message stands and nothing is read.
c2=scene_with(nil);reads={};cam.pos={9,9,1}
for t=11,12,.05 do frame(t)end
assert(#reads==1 and reads[1].automatic==false,'Scenery focus does not need the picker')
reads={};message=frame(13,false)
assert(#reads==1 and reads[1].automatic==true and message=='Center auto-focus paused to avoid stutter.','No camera keeps the old suspended path')
print('Scene focus input: menu exclusion, top-left double-click UV, delayed display retry, center cooldown, cleanup, Helldiver skeleton focus and settled scenery reads passed')

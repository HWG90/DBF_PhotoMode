-- The full unchanged ActionCam source is injected by test_actioncam_compat.py.
local factory=assert(loadstring(ADAPTER_SOURCE,'@ActionCam-compatibility'))()
local function up(fn,wanted)
 for i=1,120 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==wanted then return value,i end end
end
local function put(fn,name,value)local _,i=up(fn,name);assert(i,name);assert(debug.setupvalue(fn,i,value)==name)end
local function strip_wrapper(fn)
 local stripped=assert(loadstring(string.dump(fn,true),'@stripped-loader-wrapper'))
 setfenv(stripped,getfenv(fn))
 for i=1,120 do
  local name,value=debug.getupvalue(fn,i);if not name then break end
  assert(debug.setupvalue(stripped,i,value)=='','Fixture must remove wrapper upvalue names')
 end
 return stripped
end
local function prior_wrapper(prior)return function(...)return prior(...)end end
local function vector(x,y,z)return{x,y,z}end
local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return vector(...)end})
local function fixture()
 local events={step=0,render=0,position=0,fov=0,near=0,scale=0,unit=0,registered={},down={},messages={}}
 local camera={fov=.8,pos=vector(1,2,3),near=.05}
 local sr={Vector3=V,Matrix4x4={},Application={worlds=function()return{'world'}end},Unit={alive=function()return true end,
  set_local_scale=function(unit,node,value)assert(unit=='helmet'and node==2);assert(value[1]==1);events.scale=events.scale+1 end},
  Camera={local_position=function()return camera.pos end,vertical_fov=function()return camera.fov end,
   set_vertical_fov=function(_,value)events.fov=events.fov+1;camera.fov=value end,
   set_near_range=function(_,value)events.near=events.near+1;camera.near=value end},
  World={update_unit=function()events.unit=events.unit+1 end}}
 local env=setmetatable({stingray=sr,package={loaded={}},io={open=function()return nil end},os={getenv=function()return nil end,remove=function()end,rename=function()end,date=function()return ''end},
  update=function(dt,...)events.step=events.step+1;return 'game-update',dt,... end,
  render=function(...)events.render=events.render+1;return 'game-render',... end},{__index=_G});env._G=env
 env.ModBindingsMenu={api=1,register_binding=function(id)events.registered[id]=true;return true end,is_down=function(id)return events.down[id]==true end}
 local bridge=factory.new(env,function(message)events.messages[#events.messages+1]=message end)
 local function load_original(source)
  local chunk=assert(loadstring(source or ACTIONCAM_SOURCE,'@mods/actioncam/actioncam'));setfenv(chunk,env);chunk();env.package.loaded['mods/actioncam/actioncam']=true
  local wrapper=env.update;local step=assert(up(wrapper,'step'));local hook=assert(up(step,'hook_render'));local apply=assert(up(hook,'apply'));local bind=assert(up(step,'bindings_step'))
  local user=up(bind,'USER');if user then user.bindings=4;local opt=up(bind,'OPT');if opt then opt.registered=true end end
  return {wrapper=wrapper,step=step,hook=hook,apply=apply,bind=bind,photo=up(bind,'PHOTO'),cfg=up(step,'CFG'),H=up(step,'H')}
 end
 return env,bridge,events,camera,load_original
end
local function prime_fov(original,camera)
 put(original.apply,'target',{world='world',cam='camera',unit='camera-unit'})
 put(original.apply,'applied_frame',up(original.apply,'frame'))
 put(original.apply,'last_written',{1,2,3});put(original.apply,'written_fov',.9);put(original.apply,'game_fov_base',.7)
 camera.fov=.8
end

-- Original first: adapt an already installed update/render chain exactly once.
local env,bridge,e,camera,load_original=fixture();local original=load_original();original.hook()
local original_game_update=up(original.wrapper,'previous_update')
assert(bridge.refresh());assert(bridge.count==1 and bridge.available and not bridge.held)
assert(up(original.wrapper,'previous_update')==original_game_update,'Game update chain must be preserved')
local gated_step=up(original.wrapper,'step');local gated_apply=up(original.hook,'apply');local gated_bind=up(original.step,'bindings_step')
assert(gated_step~=original.step and gated_apply~=original.apply and gated_bind~=original.bind)
assert(bridge.refresh()and up(original.wrapper,'step')==gated_step,'Attachment must be idempotent')
-- Normal ActionCam gameplay FOV behavior still runs while Photo is inactive.
prime_fov(original,camera);env.render('idle');assert(e.fov==1 and math.abs(camera.fov-1)<1e-9 and e.render==1)
gated_bind();assert(e.registered['actioncam.restart']and e.registered['actioncam.profile_1'])
assert(not e.registered['actioncam.photo_toggle'],'Independent ActionCam Photo bindings must not collide')
e.down['actioncam.photo_toggle']=true;gated_bind();assert(not original.photo.active)
-- Real profile controls remain registered and available outside Photo.
e.down['actioncam.profile_1']=true;gated_bind();local OPT=up(up(original.bind,'switch_profile'),'OPT');assert(OPT.profile==1)
e.down['actioncam.profile_1']=false;gated_bind()

-- Handoff restores original First Person and FOV leases before Photo owns it.
prime_fov(original,camera);camera.fov=.9
local near=up(original.apply,'near_restore');local NEAR=up(near,'NEAR');NEAR.active,NEAR.orig=true,.12
local helmet_restore=up(near,'helmet_restore_ref');local shrink_restore=up(helmet_restore,'shrink_restore');local SHRINK=up(shrink_restore,'SHRINK')
SHRINK.unit,SHRINK.node,SHRINK.orig='helmet',2,{1,1,1}
assert(bridge.acquire()and bridge.held and e.scale==1 and e.near==1 and math.abs(camera.fov-.7)<1e-9)
assert(not NEAR.active and SHRINK.unit==nil and up(original.apply,'target')==nil)
local before_fov=e.fov;local before_frame=up(original.step,'frame')
prime_fov(original,camera);env.update(.016,'tail');env.render('photo')
assert(e.step==1 and e.render==2,'Camera suppression must retain game callbacks')
assert(e.fov==before_fov and up(original.step,'frame')==before_frame,'ActionCam must not update/write its camera during Photo')
e.down['actioncam.profile_2']=true;gated_bind();assert(OPT.profile==1,'ActionCam shortcuts must yield during Photo')
assert(bridge.release()and not bridge.held and up(original.apply,'target')==nil)
e.down['actioncam.profile_2']=false;gated_bind();gated_bind()
e.down['actioncam.profile_2']=true;gated_bind();assert(OPT.profile==2,'ActionCam shortcuts must resume after release')
local a,b,c=env.update(.016,'tail');assert(a=='game-update'and b==.016 and c=='tail','Original callback results must survive')
prime_fov(original,camera);local old=e.fov;env.render('restored');assert(e.fov==old+1,'Original camera must resume on exit')

-- Photo first: late ActionCam is discovered, including while Photo already owns it.
local env2,bridge2,e2,c2,load2=fixture();assert(bridge2.refresh()and bridge2.count==0);assert(bridge2.acquire())
local late=load2();late.hook();assert(bridge2.refresh()and bridge2.count==1 and bridge2.held)
prime_fov(late,c2);env2.render('late');env2.update(.016)
assert(e2.fov==0 and e2.render==1 and e2.step==1,'A late original camera must yield before drawing')
assert(bridge2.release());env2.update(.016);assert(up(late.step,'frame')==1,'Late ActionCam resumes normally')

-- Unknown versions are refused before any closure or binding mutation.
local env3,bridge3,e3,c3,load3=fixture();local unknown=load3(ACTIONCAM_SOURCE:gsub("CFG.VERSION = '[^']+'","CFG.VERSION = '99.99'",1))
env3.update=strip_wrapper(prior_wrapper(env3.update))
local update3,binds3=env3.update,up(unknown.bind,'PHOTO_BINDS')
local supported,why=bridge3.refresh();assert(not supported and why:find('Unsupported ActionCam'))
assert(env3.update==update3 and up(unknown.wrapper,'step')==unknown.step and up(unknown.bind,'PHOTO_BINDS')==binds3)
assert(not bridge3.acquire()and not bridge3.held,'Unknown camera cannot grant a Photo lease')

-- Ownership failures must retain the gate instead of resuming competing writes.
local env4,bridge4,e4,c4,load4=fixture();local o4=load4();assert(bridge4.refresh());assert(bridge4.acquire())
local records=up(bridge4.release,'records');local record=records[o4.wrapper];local old_drop=record.drop
record.drop=function()error('cleanup deliberately pending')end
assert(not bridge4.release()and bridge4.held,'Failed cleanup must keep the original camera suspended')
local frame4=up(o4.step,'frame');env4.update(.016);assert(up(o4.step,'frame')==frame4)
record.drop=old_drop;assert(bridge4.release()and not bridge4.held)

-- A failed start has never granted Photo its camera. Once the caller cancels
-- its own input/time/effects, original ActionCam must not remain locked out.
record.drop=function()error('handoff entry failed')end
assert(not bridge4.acquire()and bridge4.held and bridge4.entry_failed)
assert(not bridge4.acquire(),'Failed entry must not turn a retry into a valid lease')
assert(bridge4.release()and not bridge4.held and not bridge4.entry_failed)
record.drop=old_drop

-- Callback errors request the owner's cleanup, retain the original error, and
-- preserve nil/multiple returns on successful calls.
assert(bridge4.acquire());local cleaned=0
local wrapped=bridge4.wrap_update(function()error('original update failure')end,function()cleaned=cleaned+1;assert(bridge4.release())end)
local worked,error_text=pcall(wrapped);assert(not worked and error_text:find('original update failure')and cleaned==1 and not bridge4.held)
local passthrough=bridge4.wrap_update(function()return nil,'second',nil,4 end)
local function pack(...)return{n=select('#',...),...}end
local returns=pack(passthrough());assert(returns.n==4 and returns[1]==nil and returns[2]=='second'and returns[4]==4)

-- The Photo toggle has priority; held ActionCam keys cannot leak across handoff.
local priority=false;bridge4.set_priority(function()return priority end);local binds4=up(o4.step,'bindings_step');binds4()
local opt4=up(up(o4.bind,'switch_profile'),'OPT');local initial=opt4.profile
priority=true;e4.down['actioncam.profile_1']=true;binds4();assert(opt4.profile==initial)
priority=false;binds4();assert(opt4.profile==initial,'Held profile key must drain before resume')
e4.down['actioncam.profile_1']=false;binds4();e4.down['actioncam.profile_1']=true;binds4();assert(opt4.profile==1)

-- Detect lost gate ownership without silently overwriting a different mod.
put(o4.wrapper,'step',o4.step);assert(not bridge4.refresh());assert(up(o4.wrapper,'step')==o4.step)

-- A later unrelated chained callback does not invalidate the known adapter.
local env5,bridge5,e5,c5,load5=fixture();local o5=load5();assert(bridge5.refresh())
local saved_binds5=up(bridge5.release,'records')[o5.wrapper].binds
local previous=env5.update;env5.update=function(...)return previous(...)end
assert(bridge5.refresh()and bridge5.count==1);assert(bridge5.acquire());assert(bridge5.release())
assert(bridge5.acquire());assert(not bridge5.dispose(),'Active camera must not detach before cleanup')
assert(bridge5.release());assert(bridge5.dispose()and bridge5.disabled)
assert(up(o5.wrapper,'step')==o5.step and up(o5.hook,'apply')==o5.apply and up(o5.step,'bindings_step')==o5.bind)
assert(up(o5.bind,'PHOTO_BINDS')==saved_binds5,'Failed startup must restore original Photo bindings')
assert(bridge5.refresh()and up(o5.wrapper,'step')==o5.step,'Disposed adapter must not reattach through a retained callback')

-- A real loader startup failure restores ActionCam and does not retry a partial
-- camera runtime every frame. This exercises the LLL bootstrap, not a stub owner.
local env6,_,e6,_,load6=fixture();local o6=load6();local constructions=0
local saved_binds6=up(o6.bind,'PHOTO_BINDS')
env6.mod={log=function()end,dir='fixture',require=function(name)
 if name=='src/actioncam_compat.lua'then return factory end
 assert(name=='src/standalone.lua');return{new=function()constructions=constructions+1;error('private service unavailable')end}
end}
local lll_chunk=assert(loadstring(LLL_SOURCE,'@PhotoMode-LLL-fixture'));setfenv(lll_chunk,env6);local addon=lll_chunk()
addon.on_update();addon.on_update();assert(constructions==1 and up(o6.wrapper,'step')==o6.step and up(o6.step,'bindings_step')==o6.bind)
assert(up(o6.bind,'PHOTO_BINDS')==saved_binds6,'Bootstrap failure must not disable original Photo controls')

-- ActionCam 2.4's binding levels remain its own choice. Photo bindings are
-- excluded even in Full, while Essential keeps restart and profile cycling.
local env7,bridge7,e7,_,load7=fixture();local o7=load7();local user7=up(o7.bind,'USER')
if user7 then
 user7.bindings=1;assert(bridge7.refresh());local gate7=up(o7.step,'bindings_step');gate7()
 assert(next(e7.registered)==nil,'None must not register an ActionCam binding')
 user7.bindings=2;o7.H.bindings_changed();gate7()
 assert(e7.registered['actioncam.restart']and e7.registered['actioncam.profile_next']and e7.registered['actioncam.profile_prev'])
 assert(not e7.registered['actioncam.profile_1']and not e7.registered['actioncam.photo_toggle'],'Essential must retain its original level')
 local opt7=up(up(o7.bind,'switch_profile'),'OPT');local count7=#up(o7.bind,'profile_choices');local initial7=opt7.profile
 e7.down['actioncam.profile_next']=true;gate7();assert(opt7.profile==(initial7%count7)+1)
 e7.down['actioncam.profile_next']=false;gate7();e7.down['actioncam.profile_prev']=true;gate7();assert(opt7.profile==initial7)
 assert(bridge7.acquire());e7.down['actioncam.profile_next']=true;gate7();assert(opt7.profile==initial7,'Profile cycling must yield during Photo')
 assert(bridge7.release());e7.down['actioncam.profile_prev']=false;e7.down['actioncam.profile_next']=false;gate7();gate7()
 user7.bindings=4;o7.H.bindings_changed();gate7()
 assert(e7.registered['actioncam.profile_1']and not e7.registered['actioncam.photo_toggle'],'Full preserves profiles without a competing Photo camera')
 user7.bindings=1;o7.H.bindings_changed();e7.down['actioncam.profile_next']=true;gate7();assert(opt7.profile==initial7,'None must stop previously registered shortcuts')
end
-- A version number alone never permits a different camera implementation.
local env8,bridge8,_,_,load8=fixture()
local changed=ACTIONCAM_SOURCE:gsub('local function step%(dt%)','local function step(dt) if dt == -1234567 then error("changed camera") end',1)
assert(changed~=ACTIONCAM_SOURCE)
local o8=load8(changed);local saved8=up(o8.bind,'PHOTO_BINDS')
env8.update=strip_wrapper(prior_wrapper(env8.update))
local accepted8,reason8=bridge8.refresh();assert(not accepted8 and reason8:find('Unsupported ActionCam camera hooks'))
assert(up(o8.wrapper,'step')==o8.step and up(o8.bind,'PHOTO_BINDS')==saved8,'Changed source must remain untouched')

-- Actual LLL uses `prior`; shipped wrappers may strip all upvalue names. Follow
-- these function links without replacing any loader or unrelated callback.
local env9,bridge9,e9,_,load9=fixture();local o9=load9();o9.hook()
local original9=env9.update;local named9=prior_wrapper(original9)
local callback9
local previous9=named9;local decoy9=math.abs
callback9=function(...)
 if select('#',...)==-1234567 then return callback9(...),decoy9(1)end
 return previous9(...)
end
local stripped9=strip_wrapper(callback9);env9.update=stripped9
local wrapper_bytes9=string.dump(stripped9,true)
local saved_links9={};for i=1,120 do local name,value=debug.getupvalue(stripped9,i);if not name then break end;saved_links9[i]=value end
assert(bridge9.refresh()and bridge9.count==1,'Stripped wrappers and the LLL prior link must expose the audited owner')
assert(env9.update==stripped9 and string.dump(stripped9,true)==wrapper_bytes9 and up(named9,'prior')==original9)
for i,value in pairs(saved_links9)do local _,current=debug.getupvalue(stripped9,i);assert(current==value,'Intermediary/C callback links must remain untouched')end
assert(bridge9.acquire());local frame9=up(o9.step,'frame');local a9,b9,c9=env9.update(.016,'tail')
assert(e9.step==1 and a9=='game-update'and b9==.016 and c9=='tail'and up(o9.step,'frame')==frame9)
assert(bridge9.release()and bridge9.dispose(),'Discovered owner must retain normal handoff and restoration')

-- Function references stored in tables are outside callback-chain discovery.
local env10,bridge10,_,_,load10=fixture();local o10=load10();local binds10=up(o10.bind,'PHOTO_BINDS')
local hidden10={previous=env10.update};env10.update=function(...)return hidden10.previous(...)end
local ok10,why10=bridge10.refresh();assert(not ok10 and why10:find('camera owner cannot be verified'))
assert(up(o10.wrapper,'step')==o10.step and up(o10.bind,'PHOTO_BINDS')==binds10,'Unverified table-owned callbacks must remain untouched')

-- The graph bound is checked before installation, even if a known owner exists
-- elsewhere. Excessive wrapper chains never cause a partial camera mutation.
local env11,bridge11,_,_,load11=fixture();local o11=load11();local binds11=up(o11.bind,'PHOTO_BINDS')
env11.render=o11.wrapper
for i=1,100 do env11.update=prior_wrapper(env11.update)end
local ok11,why11=bridge11.refresh();assert(not ok11 and why11=='Camera callback chain cannot be verified')
assert(up(o11.wrapper,'step')==o11.step and up(o11.hook,'apply')==o11.apply and up(o11.bind,'PHOTO_BINDS')==binds11)
assert(not bridge11.acquire()and not bridge11.held,'An over-limit graph must not grant a Photo lease')
print('ActionCam compatibility: actual source, both load orders, idle profiles/FOV, exclusive Photo writes, FP restoration, callback results, unsupported source, cleanup retry, binding edges and bounded stripped loader chains passed')

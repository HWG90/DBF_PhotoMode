DBF_PHOTO_CAPTURE_FIXTURE_ONLY=true
local fixture=dofile('freecam/steam_capture_runtime_tests.lua');DBF_PHOTO_CAPTURE_FIXTURE_ONLY=nil
local f=fixture(false,function(f,deps,sr)
 f.ragdoll_reads=0;f.held=false;f.releases=0
 deps.subject_backend={new=function()return{}end}
 deps.subject_visibility={new=function()return{ready=function()return false end,refresh=function()return false end,
 release=function()return true end,flush=function()return true end}end}
 deps.ragdoll={native=function()return{}end,new=function()return{
 flush=function(enabled)f.ragdoll_reads=f.ragdoll_reads+1;f.held=enabled;return true end,
 release=function()f.releases=f.releases+1;if f.refuse then return false,'Restore pending'end;f.held=false;return true end}end}
 local time=sr.Application.set_time_step_policy
 sr.Application.set_time_step_policy=function(k,v)
  if v~=0 then assert(not f.held,'Ragdoll transfer must release before time resumes')end;return time(k,v)
 end
end)
for i=1,100 do f.step(.016)end;assert(f.ragdoll_reads==0,'Closed ragdoll must do no work')
f.open();f.step(.016);assert(f.held and f.rate==0)
f.refuse=true;assert(not f.runtime.close(true));assert(f.rate==0,'Failed ragdoll restore must retain zero time')
f.refuse=false;assert(f.runtime.close(true));assert(not f.held and f.rate==1 and not f.lease)
f.finish()
print('Ragdoll runtime: zero-time-only updates, no closed work, release-before-resume and held-time cleanup retry passed')

-- A guarded startup failure is transient, not a permanent feature veto.
local cold=fixture(false,function(f,deps)
 f.initializations=0;f.ragdoll_initializations=0;f.held=false
 deps.subject_backend={new=function()
  f.initializations=f.initializations+1
  if f.initializations==1 then error('Native binding not ready during startup')end
  return{}
 end}
 deps.subject_visibility={new=function()return{ready=function()return false end,refresh=function()return false end,
 release=function()return true end,flush=function()return true end}end}
 deps.ragdoll={native=function()f.ragdoll_initializations=f.ragdoll_initializations+1;return{}end,new=function()return{
 flush=function(enabled)f.held=enabled;return true end,release=function()f.held=false;return true end}end}
end)
assert(cold.initializations==1 and cold.ragdoll_initializations==0)
for i=1,100 do cold.step(.016)end
assert(cold.initializations==1,'A closed idle runtime must not retry native initialization')
cold.open();cold.step(.016)
assert(cold.initializations==2 and cold.ragdoll_initializations==1 and cold.held,
 'Opening after a transient native failure must acquire the ragdoll controller')
assert(cold.runtime.close(true)and not cold.held and cold.rate==1 and not cold.lease)
cold.open();assert(cold.initializations==2 and cold.ragdoll_initializations==1,'Reuse successful adapters')
cold.finish()
print('Ragdoll startup retry: no idle probes, retry on open, reuse guarded adapters and clean resume passed')

local hover=fixture(false,function(f,deps)
 deps.subject_backend={pause_gate=true,new=function()return{can_freeze=function()return false,'Hover Pack pause is being repaired'end}end}
 deps.subject_visibility={new=function()return{ready=function()return false end,refresh=function()return false end,
 release=function()return true end,flush=function()return true end}end}
end)
hover.open();assert(hover.runtime.active and hover.rate==1 and not hover.runtime.handle.get('freeze_player'))
assert(hover.runtime.handle.set('freeze_player',true))
assert(hover.rate==1 and not hover.runtime.handle.get('freeze_player'),'Refused zero must immediately show Off, not a stale On selection')
assert(hover.runtime.close(true)and not hover.lease and hover.rate==1);hover.finish()
print('Hover pause runtime: camera/menu stays available, refused toggle immediately shows Off, time/input clean passed')

local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'subject.lua');local generation=1;local writes={};local retired=false
local helmet={identity='helmet:2',mesh_count=2};local cape={identity='cape:3',mesh_count=1}
local masks={['helmet:2']={255,0},['cape:3']={255}}
local context={local_owner=true,identity='player:496:world:1',groups={hide_player={helmet,cape},hide_cape={cape}}}
local backend={resolve=function()return context end,valid=function()return not retired end,
 read=function(part,index)return masks[part.identity][index]end,
 write=function(part,index,value)writes[#writes+1]={part=part.identity,index=index,value=value};masks[part.identity][index]=value and 255 or 0 end}
local subject=module.new(backend);assert(subject.ready())
assert(subject.apply({hide_player=true})and subject.count()==2 and #writes==2)
assert(masks['helmet:2'][2]==0,'Pre-existing invisible mesh must remain untouched')
subject.apply({hide_player=true});assert(#writes==2,'Holding hide must not emit per-frame repeated setters')
assert(subject.apply({hide_cape=true})and masks['helmet:2'][1]==255 and masks['cape:3'][1]==0,'Group transitions must restore removed owned rows and retain overlapping rows')
assert(subject.release()and masks['cape:3'][1]==255 and subject.count()==0)
subject.apply({hide_player=true});masks['helmet:2'][1]=8
assert(subject.release()and masks['helmet:2'][1]==8,'A foreign pass-mask writer must never be overwritten during release')
masks['helmet:2'][1]=255;subject.apply({hide_player=true});retired=true;local count=#writes
assert(subject.release()and #writes==count,'Retired units must never be written during cleanup')
retired=false;masks['helmet:2'][1]=255;masks['cape:3'][1]=255
subject.apply({hide_player=true});context.identity='player:502:world:2';subject.apply({})
assert(masks['helmet:2'][1]==255 and masks['cape:3'][1]==255,'World/player handoff must restore still-owned old renderer rows')
context.local_owner=false;assert(not pcall(subject.ready),'Remote/preview/camera ownership must be rejected')
context.local_owner=true;masks['helmet:2'][1]=2;subject.ready();assert(subject.capabilities.hide_player==false,'Partial existing visibility masks require a supported exact restore route')
masks['helmet:2'][1]=255
local real=backend.write;local failed=true
backend.write=function(part,index,value)if failed and value then error('retry sentinel')end;return real(part,index,value)end
subject.apply({hide_cape=true});assert(not subject.release()and subject.count()==1,'A failed owned restore must remain queued for retry')
failed=false;assert(subject.release()and subject.count()==0)
local before=#writes;assert(subject.queue({hide_player=true})and subject.pending and #writes==before,'Menu callbacks must queue without any engine mutation')
assert(subject.flush(.016)and subject.count()==2 and #writes==before+2,'Only the owning update flush may apply the renderer setters')
assert(subject.queue(nil)and subject.flush(.016)and subject.count()==0)
assert(subject.queue({hide_player=true}));assert(subject.release()and not subject.pending);assert(subject.flush(.016)and subject.count()==0,'Shutdown release must cancel a queued hide before it can execute')
-- Attached parts can appear while visibility is held, including when the
-- initial selection needed no writes. Capability polling has a separate clock.
masks['helmet:2']={0,0};masks['cape:3']={0};context.groups.hide_player={helmet,cape}
assert(subject.queue({hide_player=true})and subject.flush(.016)and subject.count()==0)
local barrel={identity='barrel:8',mesh_count=1};masks['barrel:8']={255};context.groups.hide_player={helmet,cape,barrel}
for i=1,6 do subject.refresh(.1);assert(subject.flush(.1))end
assert(masks['barrel:8'][1]==0 and subject.count()==1,'New attachment escaped hide because original meshes were invisible or capability polling starved updates')
local held_writes=#writes;for i=1,6 do subject.refresh(.1);assert(subject.flush(.1))end
assert(#writes==held_writes,'Attachment refresh repeated unchanged engine setters')
context.groups.hide_player={helmet,cape};for i=1,6 do assert(subject.flush(.1))end
assert(masks['barrel:8'][1]==255 and subject.count()==0,'Detached equipment did not regain its original visibility')
assert(subject.queue(nil)and subject.flush(.016));context.groups.hide_player={helmet,cape};masks['helmet:2']={255,0};masks['cape:3']={255}
print('Subject visibility: local-only proof, overlapping groups, original invisible rows, write coalescing, foreign/retired ownership, handoff and retry cleanup passed')

do
 local resolves,reads=0,0;local revision=1
 local part={identity='stable',mesh_count=1};local mask=255
 local b={resolve=function()resolves=resolves+1;return{local_owner=true,identity='p',groups={hide_player={part}},revision=revision}end,
  unchanged=function(c)return c.revision==revision end,valid=function()return true end,
  read=function()reads=reads+1;return mask end,write=function(_,_,visible)mask=visible and 255 or 0 end}
 local s=module.new(b);assert(s.queue({hide_player=true})and s.flush(.016))
 local before_resolves,before_reads=resolves,reads
 for i=1,100 do s.refresh(.1);assert(s.flush(.1))end
 assert(resolves==before_resolves and reads==before_reads,'Unchanged hidden subjects must stay idle without discovery or mesh reads')
 revision=2;for i=1,6 do assert(s.flush(.1))end
 assert(resolves>before_resolves,'Topology changes must refresh visibility')
 assert(s.release()and mask==255,'Cached visibility must retain owned restoration')
end

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

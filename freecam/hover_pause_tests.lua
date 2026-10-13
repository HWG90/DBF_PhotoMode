local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Guard=dofile(root..'hover_pause.lua')
local function fixture(value)
    local pack={identity='pack455',generation=1,active=true,hover=true,value=value or 6,
        epoch=10,dt=.016,control={x=0,y=0,z=1},action=0}
    local env={current=pack,packs={pack455=pack},writes={},epoch=10,dt=.016}
    local backend={}
    function backend.input_supported()return not env.pad,'Controller input is not suppressed'end
    function backend.snapshot(expected)
        if env.unavailable then return nil,'reader unavailable'end
        local p
        if expected then p=env.packs[expected.identity]else p=env.current end
        if not p or(expected and p.generation~=expected.generation)then return{expired=true}end
        return {identity=p.identity,generation=p.generation,active=p.active,hover=p.hover,value=p.value,
            epoch=env.epoch,dt=env.dt,control={x=p.control.x,y=p.control.y,z=p.control.z},action=p.action}
    end
    local function apply(expected,value,restoring)
        local p=env.packs[expected.identity]
        assert(p and p.generation==expected.generation and p.value==expected.value,'Backend must compare the live owner/value')
        if restoring and env.fail_restore then return false,'restore unavailable'end
        if not restoring and env.fail_set then return false,'set unavailable'end
        p.value=value;env.writes[#env.writes+1]={identity=p.identity,value=value}
        return true
    end
    backend.set=function(s,v)return apply(s,v,false)end
    backend.restore=function(s,v)return apply(s,v,true)end
    env.guard=Guard.new(backend)
    function env.tick(dt)env.epoch=env.epoch+1;env.dt=dt end
    function env.neutral()pack.control={x=0,y=0,z=0};pack.action=0 end
    function env.arm()
        assert(env.guard.prepare());env.neutral();env.tick(.016);assert(env.guard.acquire())
    end
    return env,pack
end

local e,p=fixture();local g=e.guard
assert(not g.acquire()and #e.writes==0,'Acquire must not prepare or mutate implicitly')
assert(g.prepare()and p.value==0 and #e.writes==1)
assert(g.prepare()and #e.writes==1,'Repeated preparation must not replace the saved original')
e.neutral();assert(not g.acquire(),'A cached neutral vector before an engine update is not proof')
e.tick(0);assert(not g.acquire(),'UI/zero-time updates must not satisfy initial neutralization')
e.tick(.016);p.action=1;assert(not g.acquire(),'The jump action must be released as well as the vector')
p.action=0;p.control.y=.01;assert(not g.acquire(),'All horizontal components must be exactly zero')
p.control.y=0/0;assert(not g.acquire(),'NaN input must fail closed')
e.neutral();assert(g.acquire());e.tick(0);assert(g.hold(),'An armed pause can retain its positive-update qualification')
assert(g.release()and g.pending and p.value==0)
assert(not g.prepare(),'Pending restore cannot silently replace the original lease')
assert(not g.after_update()and p.value==0)
e.tick(0);assert(not g.after_update()and p.value==0)
e.tick(.016);assert(g.after_update()and p.value==6 and not g.pending)
assert(g.after_update()and #e.writes==2,'Cleanup must be idempotent')

-- Equipment changes must restore the surviving old pack, never the new local one.
e,p=fixture();e.arm();local old=p
local other={identity='pack999',generation=1,active=false,hover=false,value=12,control={x=0,y=0,z=0},action=0}
e.current=other;e.packs.pack999=other
assert(not e.guard.hold()and e.guard.pending)
e.tick(.016);assert(e.guard.after_update()and old.value==6 and other.value==12)
assert(e.writes[2].identity=='pack455','Restoration must resolve the old owned entity')

-- Lost readers retry; only explicit destruction/recycling releases ownership.
e,p=fixture();e.arm();e.unavailable=true
assert(e.guard.release());e.tick(.016);assert(not e.guard.after_update()and e.guard.pending)
e.unavailable=false;e.fail_restore=true;assert(not e.guard.after_update()and e.guard.pending and p.value==0)
e.fail_restore=false;assert(e.guard.after_update()and p.value==6)
e,p=fixture();e.arm();e.guard.release();p.generation=2;e.tick(.016)
assert(e.guard.after_update()and p.value==0 and #e.writes==1,'A recycled identity must never receive the old value')
e,p=fixture();e.arm();e.guard.release();e.packs.pack455=nil;e.tick(.016)
assert(e.guard.after_update()and not e.guard.pending and #e.writes==1)

e,p=fixture();e.arm();p.value=9
assert(not e.guard.hold()and not e.guard.pending and #e.writes==1 and p.value==9,'A foreign writer must retain its value')
e,p=fixture();e.arm();p.control.z=1
assert(not e.guard.hold()and e.guard.pending,'Non-neutral control during pause must require world resume')
e.tick(.016);assert(e.guard.after_update()and p.value==6)
e,p=fixture();e.fail_set=true
assert(not e.guard.prepare()and not e.guard.pending and p.value==6 and #e.writes==0)

e,p=fixture(0);e.arm();assert(#e.writes==0,'A pre-existing manual hover setting must not be claimed')
e.guard.release();e.tick(.016);assert(e.guard.after_update()and p.value==0 and #e.writes==0)
e,p=fixture();p.active=false
assert(e.guard.prepare()and e.guard.acquire()and #e.writes==0,'Inactive hover packs must preserve ordinary photo pause')
p.active=true;assert(not e.guard.hold(),'An active hover pack appearing during unguarded pause requires resume')
e,p=fixture();p.hover=false
assert(e.guard.prepare()and e.guard.acquire()and e.guard.hold()and #e.writes==0,'Ordinary jump packs pass through')
assert(not Guard.new({}).prepare(),'Unsupported readers must fail closed')
e,p=fixture();p.value=math.huge;assert(not e.guard.prepare()and #e.writes==0)
e,p=fixture();e.pad=true
assert(not e.guard.prepare()and #e.writes==0 and p.value==6,'Unsupported controller input must refuse before any override write')
e,p=fixture();e.arm();e.pad=true
assert(not e.guard.hold()and e.guard.pending,'A newly connected controller must invalidate the armed input guarantee')
e.tick(.016);assert(e.guard.after_update()and p.value==6,'Controller refusal must not block owned restoration')
print('Hover pause: positive-engine-update gate, neutral inputs, deferred restore, old-entity ownership, foreign/recycled state and retry cleanup passed')

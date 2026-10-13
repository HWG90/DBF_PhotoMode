local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local Guard=dofile(root..'hover_pause.lua');local Simulation=dofile(root..'simulation.lua')
local function fixture()
    local f={rate=1.25,value=6,epoch=10,dt=.016,clock=10,world_time=20,action=0,z=1,events={},unit=1}
    local pack={identity='pack455',generation=1}
    local b={input_supported=function()return not f.pad,'Controller route unsupported'end,snapshot=function()
        if f.read_error then error('pack temporarily unreadable')end
        return{identity=pack.identity,generation=pack.generation,active=true,hover=true,value=f.value,
            epoch=f.epoch,dt=f.dt,control={x=0,y=0,z=f.z},action=f.action}
    end}
    local function write(s,v)
        assert(s.identity==pack.identity and s.generation==pack.generation and s.value==f.value)
        if v~=0 and f.data_restore_error then error('data restore pending')end
        f.events[#f.events+1]='height:'..v;f.value=v;return true
    end
    b.set=write;b.restore=write;f.guard=Guard.new(b)
    local sr={World={time=function()return f.world_time end,delta_time=function()return f.dt end},
        Network={game_session=function()return 1 end},
        GameSession={other_peers=function()return f.peers and{2}or{}end,synchronizing_peers=function()return{}end}}
    local policy={snapshot=function()return{value=f.rate}end,value=function()return f.rate end,now=function()return f.clock end,
        set=function(_,v)
            if f.rate_error and v>0 then error('time restore pending')end
            if v==0 then assert(f.guard.status().phase=='armed','Hover control must be acquired before zero time')end
            f.events[#f.events+1]='time:'..v;f.rate=v
        end}
    f.pause=Simulation.new(sr,function()return f.unit,2,true end,policy,f.guard)
    function f.update(dt)
        f.epoch=f.epoch+1;f.dt=dt;f.clock=f.clock+.016
        if dt>0 then f.world_time=f.world_time+dt end
        return f.pause.after_update()
    end
    function f.arm()
        assert(f.pause.prepare());f.z=0;f.update(.016);assert(f.pause.ready());assert(f.pause.start())
    end
    return f
end

local f=fixture();local p=f.pause
assert(p.prepare()and f.value==0 and p.input_release_required()and not p.needs_input_capture())
assert(not p.ready()and not p.start()and f.rate==1.25,'Preparation must not freeze before a completed positive update')
f.z=0;f.update(0);assert(not p.ready()and f.rate==1.25)
f.update(.016);assert(p.ready()and p.start()and p.needs_input_capture()and f.rate==0)
assert(f.events[1]=='height:0'and f.events[2]=='time:0')
f.update(0);assert(p.hold(),'Zero time retains a qualified neutral guard')
assert(p.release()and f.rate==1.25 and f.value==0 and p.cleanup_pending()and not p.needs_input_capture())
f.update(0);assert(f.value==0);f.update(.016)
assert(f.value==6 and not p.cleanup_pending()and f.events[3]=='time:1.25'and f.events[4]=='height:6')

f=fixture();assert(f.pause.prepare());assert(f.pause.release()and f.pause.cleanup_pending(),'Cancel before time ownership must still queue data restore')
f.update(.016);assert(f.value==6 and f.rate==1.25)
f=fixture();f.arm();f.action=1
assert(not f.pause.hold()and f.rate==1.25 and f.value==0,'Lost neutral control must resume before restoring hover automation')
f.update(.016);assert(f.value==6)
f=fixture();f.arm();f.read_error=true
assert(not f.pause.hold()and f.rate==1.25 and f.pause.cleanup_pending(),'Reader loss must resume and retain restoration ownership')
f.read_error=false;f.update(.016);assert(f.value==6)

f=fixture();f.arm();f.rate_error=true
assert(not f.pause.release()and f.pause.paused()and not f.guard.pending and f.value==0,'Failed time restore must retain an armed override')
f.rate_error=false;assert(f.pause.release());f.data_restore_error=true
assert(not f.update(.016)and f.pause.cleanup_pending()and f.value==0)
f.data_restore_error=false;assert(f.update(.016)and f.value==6)

f=fixture();f.arm();assert(f.pause.start(.2)and f.rate==.2 and f.value==0)
assert(not f.pause.start(0)and f.rate==1.25,'Slowmo-to-pause must not bypass preparation while old data restore is pending')
f.update(.016);assert(f.value==6);assert(f.pause.prepare());f.update(.016);assert(f.pause.start()and f.rate==0)
assert(f.pause.release());f.update(.016);assert(f.rate==1.25 and f.value==6)
f=fixture();f.arm();f.rate=.5
assert(not f.pause.hold()and f.rate==.5,'Another time-policy writer must retain its value')
f.update(.016);assert(f.value==6)
f=fixture();f.pause.prepare();f.peers=true
assert(not f.pause.start()and f.rate==1.25 and f.pause.cleanup_pending());f.update(.016);assert(f.value==6)
f=fixture();f.pad=true;assert(not f.pause.prepare()and #f.events==0 and f.rate==1.25)
f=fixture();f.arm();f.pad=true
assert(not f.pause.hold()and f.rate==1.25 and f.value==0);f.update(.016);assert(f.value==6)
print('Hover/simulation integration: neutralize-before-zero, pending-entry cleanup, input loss, ordered resume, failed restoration and slow-motion transitions passed')

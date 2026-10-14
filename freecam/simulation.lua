-- Zero native game-module time in solo; preserve render/UI time and prior multiplier.
local M={}
function M.new(sr,context,backend,hover_guard)
    local self={};local saved;local elapsed=0;local world_time;local verified_time
    local function solo()
        local N,G=sr.Network,sr.GameSession
        if not N or not G then return false end
        local ok,session=pcall(N.game_session)
        if not ok then return false end
        local a,peers,b,joining
        if session then
            a,peers=pcall(G.other_peers,session);b,joining=pcall(G.synchronizing_peers,session)
        else
            a,peers=pcall(N.connections);b,joining=true,{}
        end
        return a and b and type(peers)=='table' and next(peers)==nil and type(joining)=='table' and next(joining)==nil
    end
    local function guard_call(name)
        if not hover_guard or type(hover_guard[name])~='function'then return true end
        local called,ok,why=pcall(hover_guard[name])
        if not called then return false,tostring(ok)end
        if ok==false then return false,why end
        return true,why
    end
    function self.prepare()
        if not solo()then return false,'Full photo pause requires a verified solo session'end
        local unit,world,confirmed=context()
        if not unit or not world or not confirmed then return false,'Local player is not ready'end
        return guard_call('prepare')
    end
    function self.ready()return guard_call('ready')end
    function self.input_release_required()
        if not hover_guard or type(hover_guard.status)~='function'then return false end
        local ok,state=pcall(hover_guard.status)
        return not ok or type(state)~='table'or state.owned==true
    end
    function self.needs_input_capture()return saved~=nil and saved.applied==0 and self.input_release_required()end
    function self.cleanup_pending()return hover_guard and hover_guard.pending==true or false end
    function self.after_update()return guard_call('after_update')end
    function self.release()
        -- Preparation may own a data override before any time policy is acquired.
        if not saved then return guard_call('release')end
        local ok,why=pcall(function()
            local current=backend.value(saved.policy)
            -- A different policy writer owns its new value; do not overwrite it.
            if current==saved.applied then backend.set(saved.policy,saved.policy.value) end
        end)
        if not ok then return false,tostring(why)end
        saved=nil
        return guard_call('release')
    end
    function self.start(rate)
        rate=rate or 0
        if type(rate)~='number' or rate~=rate or rate<0 or rate>1 then return false,'Invalid simulation rate' end
        if saved then
            local unit,world,confirmed=context()
            if not solo() or unit~=saved.unit or world~=saved.world or not confirmed then self.release();return false,'Solo simulation ownership changed' end
            local ok,why=pcall(function()
                assert(backend.value(saved.policy)==saved.applied,'Simulation ownership lost')
                if rate==0 then local ready,reason=guard_call('acquire');assert(ready,reason)end
                if math.abs(saved.applied-rate)>0.0000001 then backend.set(saved.policy,rate)end
                saved.applied=backend.value(saved.policy);saved.start=backend.now();verified_time=nil
                if saved.applied>0 then local released,reason=guard_call('release');assert(released,reason)end
            end)
            if not ok then self.release();return false,tostring(why)end
            return true
        end
        if not solo() then self.release();return false,'Full photo pause requires a verified solo session' end
        local unit,world,confirmed=context()
        if not unit or not world or not confirmed then self.release();return false,'Local player is not ready' end
        local ok,policy=pcall(backend.snapshot)
        if not ok then self.release();return false,tostring(policy) end
        if policy.value==0 then self.release();return false,'Simulation is already paused by another owner' end
        local read,time=pcall(sr.World.time,world)
        if not read or type(time)~='number' then self.release();return false,'World clock unavailable' end
        if rate==0 then local ready,reason=guard_call('acquire');if not ready then return false,reason end end
        saved={policy=policy,world=world,unit=unit,start=backend.now(),applied=rate};elapsed=0;world_time=time;verified_time=nil
        local applied,why=pcall(backend.set,policy,rate)
        if not applied then self.release();return false,tostring(why)end
        saved.applied=backend.value(policy)
        if saved.applied>0 then local released,reason=guard_call('release');if not released then self.release();return false,reason end end
        return true,rate==0 and 'Native simulation pause acquired (solo); verifying gameplay clock' or ('Native slow motion acquired (solo): '..rate)
    end
    function self.hold()
        if not saved then return true end
        local unit,world,confirmed=context()
        local api=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API');local camera=api and api.camera_input
        if not solo() or (camera and camera.pause_allowed and not camera.pause_allowed()) or unit~=saved.unit or world~=saved.world or not confirmed then
            local ok,why=self.release();return false,why or 'Solo simulation ownership changed'
        end
        local ok,why=pcall(function()
            assert(backend.value(saved.policy)==saved.applied,'Native simulation ownership lost')
            if saved.applied==0 then local held,reason=guard_call('hold');assert(held,reason)end
            local now=backend.now();elapsed=now-saved.start
            if saved.applied==0 and elapsed>0.15 then
                local time=sr.World.time(world)
                assert(type(time)=='number','Gameplay clock unavailable')
                if verified_time then assert(math.abs(time-verified_time)<0.00001,'Gameplay clock advanced despite native pause')else verified_time=time end
                assert(math.abs(sr.World.delta_time(world))<0.000001,'Gameplay world time step is still advancing')
            end
        end)
        if not ok then self.release();return false,tostring(why) end
        return true
    end
    function self.paused()return saved~=nil and saved.applied==0 end
    function self.rate()return saved and saved.applied or 1 end
    return self
end
return M

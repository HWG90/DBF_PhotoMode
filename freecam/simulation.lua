-- Zero native game-module time in solo; preserve render/UI time and prior multiplier.
local M={}
function M.new(sr,context,backend)
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
    function self.release()
        if not saved then return true end
        local ok,why=pcall(function()
            local current=backend.value(saved.policy)
            -- A different policy writer owns its new value; do not overwrite it.
            if current==saved.applied then backend.set(saved.policy,saved.policy.value) end
        end)
        if not ok then return false,tostring(why)end
        saved=nil;return true
    end
    function self.start(rate)
        rate=rate or 0
        if type(rate)~='number' or rate~=rate or rate<0 or rate>1 then return false,'Invalid simulation rate' end
        if saved then
            local unit,world,confirmed=context()
            if not solo() or unit~=saved.unit or world~=saved.world or not confirmed then self.release();return false,'Solo simulation ownership changed' end
            local ok,why=pcall(function()
                assert(backend.value(saved.policy)==saved.applied,'Simulation ownership lost')
                if math.abs(saved.applied-rate)>0.0000001 then backend.set(saved.policy,rate)end
                saved.applied=backend.value(saved.policy);saved.start=backend.now();verified_time=nil
            end)
            if not ok then self.release();return false,tostring(why)end
            return true
        end
        if not solo() then return false,'Full photo pause requires a verified solo session' end
        local unit,world,confirmed=context()
        if not unit or not world or not confirmed then return false,'Local player is not ready' end
        local ok,policy=pcall(backend.snapshot)
        if not ok then return false,tostring(policy) end
        if policy.value==0 then return false,'Simulation is already paused by another owner' end
        local read,time=pcall(sr.World.time,world)
        if not read or type(time)~='number' then return false,'World clock unavailable' end
        saved={policy=policy,world=world,unit=unit,start=backend.now(),applied=rate};elapsed=0;world_time=time;verified_time=nil
        local applied,why=pcall(backend.set,policy,rate)
        if not applied then self.release();return false,tostring(why)end
        saved.applied=backend.value(policy)
        return true,rate==0 and 'Native simulation pause acquired (solo); verifying gameplay clock' or ('Native slow motion acquired (solo): '..rate)
    end
    function self.hold()
        if not saved then return true end
        local unit,world,confirmed=context()
        local api=rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API');local camera=api and api.camera_input
        if not solo() or (camera and camera.pause_allowed and not camera.pause_allowed()) or unit~=saved.unit or world~=saved.world or not confirmed then
            local ok,why=self.release();return false,why or 'Solo simulation ownership changed'
        end
        local ok,why=pcall(function()
            assert(backend.value(saved.policy)==saved.applied,'Native simulation ownership lost')
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

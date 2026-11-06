-- Chef cannot expose a global setter hook or a time-policy getter. This uses
-- a cooperative lease and an explicit 1x reset, never a fictional prior state.
local M = {}
local KEY = 'dbf.war_journalist.time_owner'
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e12 end
function M.new(chef, features)
    local self = {owned=false, frozen=false, slow=false, rate=.2, pending=false}
    local token = {owner=chef.name}
    local world, session, generation, next_check, retry_at
    -- Chef 1.4.0: the players event (someone starts joining, is in, or leaves)
    -- and chef.joining(). Listened to only while this lease owns time, so the
    -- loader does no player checks for an idle Photo Mode.
    local listen=features and features.players_event==true
    local joining=features and features.joining==true
    local unsubscribe, crowded
    local function call(name,...)
        local a,b = chef.call(name,...)
        if a==nil and b~=nil then error(name..': '..tostring(b),0) end
        return a,b
    end
    local function clock()
        local now=call('Application.time_since_launch')
        assert(finite(now),'Unscaled time-policy clock unavailable')
        return now
    end
    local function clear()
        if chef.shared(KEY)==token then chef.share(KEY,nil) end
        self.owned,self.frozen,self.slow,self.pending=false,false,false,false
        self.pending_reason=nil
        world,session,generation,next_check,retry_at=nil,nil,nil,nil,nil
        if unsubscribe then
            local stop=unsubscribe;unsubscribe=nil
            local called,why=pcall(stop)
            if not called then chef.log('%s','WJ: players event unsubscribe failed: '..tostring(why)) end
        end
        crowded=nil
    end
    local function on_players(players,waiting)
        if players~=1 or (tonumber(waiting) or 0)>0 then
            crowded=(tonumber(waiting) or 0)>0 and 'Time controls ended: a player is joining' or
                'Time controls ended: the session has other players'
        end
    end
    local function solo()
        local current=call('Network.game_session')
        if type(current)~='userdata' then return nil,'Solo session unavailable' end
        local peers=call('GameSession.peers',current)
        if type(peers)~='table' then return nil,'Solo peer inventory unavailable' end
        local count=0
        for _ in pairs(peers) do count=count+1; if count>1 then return nil,'Time controls are solo only' end end
        if count~=1 then return nil,'Solo peer inventory is not ready' end
        -- A peer still joining is not in GameSession.peers yet; Chef 1.4.0 counts it.
        if joining then
            local called,n=pcall(chef.joining)
            if not called or type(n)~='number' then return nil,'Joining player count unavailable' end
            if n>0 then return nil,'Time controls are solo only: a player is joining' end
        end
        return current
    end
    local function write(value)
        local result=call('Application.set_time_step_policy','external_multiplier',value)
        if result==false then error('Time-policy write refused',0) end
    end
    function self.release(force)
        if not self.owned then return true end
        if chef.shared(KEY)~=token then clear(); return true end
        if not force and retry_at then
            local called,now=pcall(clock)
            if called and now<retry_at then return false,self.pending_reason end
            -- A broken unscaled clock cannot be a reason to spam the setter.
            if not called then return false,self.pending_reason end
        end
        local ok,why=pcall(write,1)
        if not ok then
            self.pending=true
            self.pending_reason=why
            local called,now=pcall(clock)
            retry_at=called and now+1 or math.huge
            return false,why
        end
        clear(); return true
    end
    local function apply(frozen,slow,rate)
        if self.pending then return false,'Time restoration pending; turn time controls off to retry' end
        if self.owned and chef.shared(KEY)~=token then clear(); return false,'Another time owner took control' end
        if crowded then return false,crowded end
        if not frozen and not slow then
            local ok,why=self.release(true)
            if ok then self.rate=rate end
            return ok,why
        end
        local now=clock()
        local current,reason=solo()
        local w=call('Application.main_world')
        local id=chef.world_id()
        if not current or not w or chef.world()~=w or not id or id==0 or call('Window.has_focus')~=true then
            return false,reason or 'Time controls need a focused, settled world'
        end
        if self.owned and (session~=current or world~=w or generation~=id) then return false,'Time session changed' end
        if not self.owned then
            if chef.shared(KEY)~=nil then return false,'Another WJ time owner is active' end
            chef.share(KEY,token)
            self.owned=true -- a throwing setter still creates a cleanup obligation
            world,session,generation=w,current,id
            if listen and not unsubscribe then
                local called,stop=pcall(chef.on,'players',on_players)
                if called and type(stop)=='function' then unsubscribe=stop
                else chef.log('%s','WJ: players event unavailable, polling only: '..tostring(stop)) end
            end
        end
        local target=frozen and 0 or rate
        local previous=self.frozen and 0 or (self.slow and self.rate or 1)
        if target~=previous then write(target) end
        self.frozen,self.slow,self.rate=frozen,slow,rate
        next_check=now+.25
        return true
    end
    function self.set(frozen,slow,rate)
        if type(frozen)~='boolean' or type(slow)~='boolean' or not finite(rate) or rate<.05 or rate>1 then
            return false,'Invalid time controls'
        end
        -- Turning everything off is also the explicit restoration retry.
        if not frozen and not slow then
            local ok,why=self.release(true); if ok then self.rate=rate end; return ok,why
        end
        if not self.pending and self.owned and chef.shared(KEY)==token and
            frozen==self.frozen and slow==self.slow and rate==self.rate then return true end
        local called,ok,why=pcall(apply,frozen,slow,rate)
        if called and ok then return true end
        local restored,cleanup=self.release(true)
        return false,restored and (called and why or ok) or cleanup
    end
    local function checkpoint()
            if crowded then return false,crowded end
            local now=clock()
            if call('Application.main_world')~=world or chef.world_id()~=generation or call('Window.has_focus')~=true then
                return false,'Time controls ended: world or focus changed'
            end
            if now<next_check and now>=next_check-.25 then return true end
            next_check=now+.25
            local current,reason=solo()
            return current==session,reason or 'Time session changed'
    end
    function self.tick()
        if not self.owned then return true end
        if chef.shared(KEY)~=token then clear(); return true,'Time lease changed' end
        if self.pending then return self.release(false) end
        local called,ok,why=pcall(checkpoint)
        if called and ok then return true end
        local restored,reason=self.release(true)
        return restored,restored and (called and why or ok) or reason
    end
    return self
end
return M

-- Getter-based ownership and bounded acknowledgement; no sandbox-local hook
-- pretends to observe other mods. Global render settings have no change event.
local M={}
function M.new(chef,setting)
    setting=setting or 'bloom_enabled'
    assert(setting=='bloom_enabled' or setting=='dof_enabled','Unsupported photo render flag')
    local KEY=setting=='bloom_enabled' and 'dbf.war_journalist.bloom_owner' or 'dbf.war_journalist.dof_owner'
    local label=setting=='bloom_enabled' and 'Bloom' or 'Native DoF'
    local self={state='closed',reason=nil};local token={owner=chef.name}
    local baseline,observed,desired,pending,deadline,next_poll,closing
    local function call(name,...)
        local a,b=chef.call(name,...)
        if a==nil and b~=nil then error(name..': '..tostring(b),0) end
        return a
    end
    local function read()
        local v=call('Application.render_setting',setting)
        assert(type(v)=='boolean',label..' getter must return a boolean');return v
    end
    local function clock()
        local t=call('Application.time_since_launch')
        assert(type(t)=='number' and t==t and t>=0 and t<1e12,label..' clock unavailable');return t
    end
    local function retire(reason)
        if chef.shared(KEY)==token then chef.share(KEY,nil) end
        self.state,self.reason='closed',reason
        baseline,observed,desired,pending,deadline,next_poll,closing=nil,nil,nil,nil,nil,nil,nil
        return true
    end
    local function block(why) self.state,self.reason='blocked',label..': '..tostring(why);return false,self.reason end
    local function submit(value)
        local now=clock()
        pending,deadline,next_poll=value,now+2,now+.1
        self.state='awaiting'
        local result=call('Application.set_render_setting',setting,value and 'true' or 'false')
        assert(result~=false,label..' setter refused')
        return true
    end
    local function cleanup()
        if self.state=='closed' then return true end
        if chef.shared(KEY)~=token then return retire(label..' lease changed; external value preserved') end
        closing=true
        if self.state=='awaiting' then return false,'Awaiting '..label..' acknowledgement' end
        local current=read()
        if pending~=nil then
            -- An explicit cleanup may acknowledge a late write after the
            -- bounded automatic window expired. Never keep polling forever.
            if current~=pending then return false,label..' submission is unacknowledged; cleanup remains pending' end
            observed,pending=current,nil;self.state='active'
        end
        if current~=observed then return retire('External '..label..' edit preserved') end
        if current==baseline then return retire() end
        submit(baseline)
        if read()==baseline then return retire() end
        return false,'Restoring original '..label
    end
    function self.close()
        local called,ok,why=pcall(cleanup)
        if not called then return block(ok) end
        return ok,why
    end
    local function request(value)
        if self.state=='blocked' then return false,self.reason end
        if self.state=='closed' then
            if chef.shared(KEY)~=nil then return false,'Another WJ '..label..' owner is active' end
            baseline=read();observed=baseline;desired=value;closing=false
            chef.share(KEY,token);self.state='active'
        elseif chef.shared(KEY)~=token then retire(label..' lease changed; external value preserved');return false,label..' lease changed' end
        if closing then return false,label..' cleanup is pending' end
        desired=value
        if self.state=='awaiting' then return true end
        local current=read()
        if current~=observed then retire('External '..label..' edit preserved');return false,'Another writer changed '..label end
        if current~=value then return submit(value) end
        return true
    end
    function self.request(value)
        assert(type(value)=='boolean',label..' selection must be boolean')
        local called,ok,why=pcall(request,value)
        if not called then return block(ok) end
        return ok,why
    end
    local function poll()
        if self.state~='awaiting' then return self.state~='blocked',self.reason end
        if chef.shared(KEY)~=token then return retire(label..' lease changed; external value preserved') end
        local now=clock()
        if now<next_poll-.1 then return block(label..' clock moved backward; cleanup remains pending') end
        if now<next_poll then return true end
        if now>deadline then return block(label..' acknowledgement timed out; cleanup remains pending') end
        next_poll=now+.1
        local current=read()
        if current~=pending then
            if now>=deadline then return block(label..' acknowledgement timed out; cleanup remains pending') end
            return true
        end
        observed,pending=current,nil;self.state='active'
        if closing then
            if observed==baseline then return retire() end
            return submit(baseline)
        end
        if desired~=observed then return submit(desired) end
        return true
    end
    function self.tick()
        local called,ok,why=pcall(poll)
        if not called then return block(ok) end
        return ok,why
    end
    function self.waiting() return self.state=='awaiting' end
    return self
end
return M

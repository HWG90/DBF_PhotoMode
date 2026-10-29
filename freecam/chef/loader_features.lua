-- Chef Shared Loader 1.4.0 services, each used only when the running loader
-- reports it. Older loaders (1.2.3-1.3.1) keep the earlier behaviour exactly.
-- Nothing here assumes a trust grant: chef.capture answers for itself.
local M = {}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e12 end

function M.probe(chef)
    local has=type(chef.has)=='function' and chef.has or function() return false end
    return {
        -- chef.hold_mouse/mouse_delta: the loader's own dead-zone hold, released
        -- by the loader too when this mod stops or the game closes.
        mouse_hold=has('mouse_hold')==true and type(chef.hold_mouse)=='function' and type(chef.mouse_delta)=='function',
        players_event=has('players_event')==true and type(chef.on)=='function',
        joining=has('joining')==true and type(chef.joining)=='function',
        menu_state=has('menu_state')==true and type(chef.menu_open)=='function',
        -- Present on 1.4.0 for every mod; only a TRUSTED entry with capture
        -- makes it save anything. Every other mod gets nil, why.
        capture=type(chef.capture)=='function',
    }
end

function M.describe(f)
    local function yes(v) return v and 'yes' or 'no' end
    return 'Chef 1.4 services: mouse hold='..yes(f.mouse_hold)..', players event='..yes(f.players_event)..
        ', joining='..yes(f.joining)..', capture call='..yes(f.capture)..' (trust decided by the loader)'
end

-- One screenshot request at a time, taken only once the loader's menu is
-- closed so the photo is not of the menu. The loader limits it to one a second.
function M.capture_queue(chef, features, notify)
    local self, due, waiting_menu = {}, nil, false
    local function clock()
        local now=chef.call('Application.time_since_launch')
        return finite(now) and now or nil
    end
    local function menu_open()
        if not features.menu_state then return false end
        local ok,open=pcall(chef.menu_open)
        return ok and open==true
    end
    function self.pending() return due~=nil or waiting_menu end
    function self.request()
        if not features.capture then return false,'This Chef Shared Loader has no screenshot call' end
        if self.pending() then return false,'A screenshot is already waiting' end
        waiting_menu=true
        return true,'Screenshot waits for the Chef menu to close'
    end
    function self.cancel() due,waiting_menu=nil,false end
    function self.tick()
        if waiting_menu then
            if menu_open() then return true end
            local now=clock();if not now then self.cancel();return false,'Screenshot clock unavailable' end
            -- Without the menu's state the loader may still be drawing it this frame.
            waiting_menu,due=false,now+(features.menu_state and .25 or 1)
            return true
        end
        if not due then return true end
        if menu_open() then waiting_menu,due=true,nil;return true end
        local now=clock();if not now then self.cancel();return false,'Screenshot clock unavailable' end
        if now<due then return true end
        due=nil
        local called,name,why=pcall(chef.capture)
        if not called then return false,'Screenshot failed: '..tostring(name) end
        if type(name)~='string' then return false,'Screenshot not saved: '..tostring(why or 'no answer') end
        notify('Saved '..name..' (DDS) in the Chef Shared Loader folder')
        return true
    end
    return self
end
return M

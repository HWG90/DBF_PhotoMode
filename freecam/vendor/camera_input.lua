-- Photo input is fully captured; raw mouse deltas belong only to the camera.
local M={}
function M.new(native,capture,input,available)
    local self={api=2,isolated_look=true};local token;local last_time;local mode=3
    function self.release()
        if not token then return true end
        if not capture.owns(token) then token=nil;return true end
        native.mcm_release()
        if native.mcm_captured()~=0 then return false,'Camera input release pending' end
        local ok,why=capture.release(token)
        if ok then token=nil end
        return ok,why
    end
    function self.acquire(bindings)
        input.poll()
        if token then return nil,'Camera input already acquired' end
        if not input.focused() or not available() or native.mcm_captured()~=0 then return nil,'Close menus and focus the game first' end
        -- Native capture snapshots gameplay-held keys and forwards their releases.
        -- Activation must not discard the toggle merely because movement is held.
        local why;token,why=capture.acquire('dbf_freecam')
        if not token then return nil,why end
        local ready,reason=pcall(function()
            assert(not input.lock_aim or input.lock_aim(),'Gameplay mouse focus could not be disabled')
            assert(not input.menu_cursor or input.menu_cursor(false),'Camera cursor could not be hidden')
            assert(native.mcm_install(input.window())~=0 and native.mcm_capture(3)~=0,'Camera window capture unavailable')
            last_time=input.now and input.now() or nil
        end)
        if not ready then self.release();return nil,tostring(reason) end
        mode=3;return token
    end
    function self.sample(bindings)
        input.poll()
        if not token or not capture.owns(token) or not input.focused() or not available() or native.mcm_captured()~=mode then
            self.release();return nil
        end
        if input.menu_cursor and not input.menu_cursor(mode==1)then self.release();return nil end
        local elapsed
        if input.now then local now=input.now();elapsed=last_time and math.max(0,math.min(0.1,now-last_time)) or 0;last_time=now end
        local dx,dy=0,0
        if input.look then dx,dy=input.look() end
        bindings=bindings or {}
        return {forward=input.down(bindings.forward or 87),back=input.down(bindings.back or 83),
            left=input.down(bindings.left or 65),right=input.down(bindings.right or 68),
            up=input.down(bindings.up or 16),down=input.down(bindings.down or 17),escape=input.down(27),wheel=input.wheel(),mouse_x=dx,mouse_y=dy,dt=elapsed}
    end
    function self.set_focus(menu)
        if not token or not capture.owns(token) then return false,'Photo input not acquired' end
        local desired=menu and 1 or 3
        local ok,why=pcall(function()
            assert(input.menu_cursor,'Photo cursor switching unavailable')
            assert(native.mcm_capture(desired)~=0,'Photo focus switch failed')
            assert(input.menu_cursor(menu),'Photo cursor state failed')
        end)
        if not ok then self.release();return false,tostring(why)end
        mode=desired;last_time=input.now and input.now()or nil;return true
    end
    function self.menu_sample()
        input.poll()
        if not token or not capture.owns(token)or not input.focused()or native.mcm_captured()~=1 then return end
        if not input.menu_cursor(true)then self.release();return end
        local x,y;if input.mouse then x,y=input.mouse()end
        local elapsed;if input.now then local now=input.now();elapsed=last_time and math.max(0,math.min(.1,now-last_time))or 0;last_time=now end
        return {x=x,y=y,click=input.down(1),wheel=input.wheel(),dt=elapsed,click_events=input.click_events and input.click_events()or nil}
    end
    function self.down(key) input.poll();return input.down(key) end
    function self.focused() input.poll();return input.focused() end
    -- This clock belongs to native input, independently of simulation speed or
    -- whether movement sampling is suspended while a photo menu has focus.
    if type(input.now)=='function' then function self.now()return input.now()end end
    if type(input.double_click_limits)=='function' then
        function self.double_click_limits(...)return input.double_click_limits(...)end
    end
    function self.pause_allowed()
        return input.photo_check~=nil and native.mcm_photo_pause_allowed(input.photo_check)~=0
    end
    function self.pause(apply)
        if not input.photo_check or not input.photo_apply then return false,'Native solo pause verification unavailable' end
        return input.photo_apply(apply)
    end
    if jit then jit.off(self.set_focus,true);jit.off(self.acquire,true);jit.off(self.sample,true);jit.off(self.pause,true);jit.off(self.pause_allowed,true) end
    return self
end
return M

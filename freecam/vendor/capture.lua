-- Capture lifetime is owned by the menu; all cursor state is restored on exit.
local M={}
function M.new(native,window,log)
    local self={active=false};local snapshot;local external;local native_parent
    local function flags(value,focus,cursor)
        return type(value)=='table' and value.focus==focus and value.cursor==cursor and type(value.clip)=='boolean'
    end
    local function parent_valid(parent,saved)
        if type(parent)~='table' or type(parent.validate)~='function' or type(parent.status)~='function' or type(parent.on_close)~='function' then return false end
        local saved_flags=parent.restoration_snapshot
        if not flags(parent.gameplay_snapshot,true,false) or type(saved_flags)~='table'or
            type(saved_flags.focus)~='boolean'or type(saved_flags.cursor)~='boolean'or type(saved_flags.clip)~='boolean'then return false end
        local ok,owned=pcall(parent.validate);if not ok or owned~=true then return false end
        if saved then for _,key in ipairs({'focus','cursor','clip'})do if parent.restoration_snapshot[key]~=saved[key]then return false end end end
        return true
    end
    local function restore(saved)
        if not saved then return true end
        local errors={}
        for _,field in ipairs({{'set_mouse_focus','focus'},{'set_show_cursor','cursor'},{'set_clip_cursor','clip'}})do
            local ok,result=pcall(window[field[1]],saved[field[2]])
            if not ok or result==false then errors[#errors+1]=field[1]..': '..tostring(ok and 'restoration refused' or result)end
        end
        for _,field in ipairs({{'mouse_focus','focus'},{'show_cursor','cursor'},{'clip_cursor','clip'}})do
            local ok,value=pcall(window[field[1]])
            if not ok or value~=saved[field[2]]then errors[#errors+1]=field[1]..': restoration readback mismatch'end
        end
        if #errors>0 then return false,table.concat(errors,'; ')end
        return true
    end
    function self.acquire(owner)
        if type(owner)~='string' or owner=='' then return nil,'Owner name required'end
        if self.active or snapshot or external then return nil,'Input lease already owned'end
        local ok,saved=pcall(function()return {focus=window.mouse_focus(),cursor=window.show_cursor(),clip=window.clip_cursor()}end)
        if not ok then return nil,tostring(saved)end
        local token={};external={owner=owner,token=token,snapshot=saved};return token
    end
    function self.owns(token)return external~=nil and external.token==token end
    function self.release(token)
        if token~=nil then
            if not self.owns(token)then return false,'Input lease not owned'end
            local ok,reason=restore(external.snapshot)
            if not ok then return false,reason end
            external=nil;return true
        end
        -- Menu cleanup cannot alter another owner's cursor or native gate.
        if external then return false,'Input lease belongs to another owner'end
        -- An inactive instance must not release the shared DLL gate belonging
        -- to another frontend. A retained snapshot is our retry ownership.
        if not self.active and not snapshot and not native_parent then return true end
        native.mcm_release()
        self.active=false
        if tonumber(native.mcm_captured())~=0 then return false,'Native input release readback failed'end
        local target=snapshot
        if native_parent then
            local called,status=pcall(native_parent.status)
            if not called or type(status)~='table' or status.covered then return false,'Native menu restoration pending: parent ownership unavailable'end
            if status.closed then target=native_parent.gameplay_snapshot
            elseif status.open then target=native_parent.restoration_snapshot
            else return false,'Native menu restoration pending: parent state unavailable'end
        end
        local ok,reason=restore(target)
        if not ok then log('Menu cursor restoration pending: '..tostring(reason));return false,reason end
        if native_parent then
            local called,closed,why=pcall(native_parent.on_close)
            if not called or closed~=true then return false,'Native menu restoration pending: '..tostring(called and why or closed)end
            for _,field in ipairs({{'mouse_focus','focus'},{'show_cursor','cursor'},{'clip_cursor','clip'}})do
                local read,value=pcall(window[field[1]])
                if not read or value~=target[field[2]]then return false,'Native menu restoration pending: final cursor readback mismatch'end
            end
        end
        if snapshot then log('Menu cursor snapshot restored')end
        snapshot=nil;native_parent=nil;return true
    end
    function self.status()
        return {owner=external and external.owner or (self.active and 'mcm' or (snapshot and 'mcm_restore' or nil)),active=self.active,pending_restore=snapshot~=nil and not self.active}
    end
    function self.sync(visible,focused,hwnd,parent)
        if not visible or not focused then if self.active or snapshot then return self.release()end;return true end
        if visible and external then return false,'Input lease belongs to '..external.owner end
        if snapshot and not self.active then return false,'Previous cursor restoration pending'end
        if self.active and native_parent and not parent_valid(native_parent)then
            self.release();return false,'Native menu context changed; MCM closed'
        end
        if not self.active then
            if tonumber(native.mcm_captured())~=0 then return false,'Native input capture belongs to another frontend'end
            for _,name in ipairs({'mouse_focus','show_cursor','clip_cursor','set_mouse_focus','set_show_cursor','set_clip_cursor'})do
                if type(window[name])~='function' then return false,'Missing cursor API: '..name end
            end
            local saved={focus=window.mouse_focus(),cursor=window.show_cursor(),clip=window.clip_cursor()}
            if parent then
                if not parent_valid(parent,saved)then return false,'Native menu input ownership could not be verified'end
                native_parent=parent
            elseif saved.focus~=true then return false,'Game mouse focus is already disabled; close the other input owner or recover focus first'end
            snapshot=saved
            local ok,err=pcall(function()
                assert(native.mcm_install(hwnd)~=0,'Native window capture unavailable')
                assert(native.mcm_capture(1)~=0,'Cannot acquire input capture')
                assert(window.set_mouse_focus(false)~=false,'Mouse focus acquisition refused')
                assert(window.set_show_cursor(true)~=false,'Cursor visibility acquisition refused')
                assert(window.set_clip_cursor(true)~=false,'Cursor clipping acquisition refused')
                assert(window.mouse_focus()==false and window.show_cursor()==true and window.clip_cursor()==true,'Cursor acquisition readback failed')
            end)
            if not ok then self.release();return false,tostring(err)end
            self.active=true;log('Menu input capture acquired')
        else
            -- The game may reset cursor flags during its own UI update.
            local ok,why=pcall(function()
                assert(window.set_mouse_focus(false)~=false,'Mouse focus maintenance refused')
                assert(window.set_show_cursor(true)~=false,'Cursor visibility maintenance refused')
                assert(window.set_clip_cursor(true)~=false,'Cursor clipping maintenance refused')
                assert(window.mouse_focus()==false and window.show_cursor()==true and window.clip_cursor()==true,'Cursor maintenance readback failed')
            end)
            if not ok then self.release();return false,tostring(why)end
            if native.mcm_captured()==0 then self.release();return false,'Input capture lost'end
        end
        return true
    end
    function self.shutdown()
        if external then local ok,reason=self.release(external.token);if not ok then return false,reason end end
        return self.release()
    end
    return self
end
return M

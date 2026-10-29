-- Same-scene reopen definitions only. No units survive closing, no disk writes,
-- no scene polling. Loader world events explicitly discard this cache.
local M={}
function M.new(chef,lights)
    local saved,opened
    local self={}
    local function context()
        local world=chef.call('Application.main_world')
        local generation=chef.world_id()
        local session=chef.call('Network.game_session')
        if not world or world~=chef.world() or type(generation)~='number' or generation~=generation or
            generation<=0 or generation>=1e12 or
            type(session)~='userdata' then return nil end
        return {world=world,generation=generation,session=session}
    end
    function self.forget(index)
        if index and saved then saved.lights[index]=nil else saved=nil end
    end
    function self.pending() return saved~=nil end
    function self.capture()
        local list,why=lights.export()
        if not list then return false,why end
        -- Keep a failed restore available across another close. Explicit
        -- remove/clear calls forget(), so cleared lights cannot reappear.
        if next(list)==nil then return true end
        local ok,scene=pcall(context)
        if not ok or not scene or lights.scene()~=scene.world then
            saved=nil;return false,'Light placements could not be tied to a settled scene'
        end
        if opened and (opened.world~=scene.world or opened.generation~=scene.generation or opened.session~=scene.session) then
            saved=nil;return false,'Light scene changed before close; placements discarded'
        end
        scene.lights=list;saved=scene;return true
    end
    function self.restore(opening)
        if not saved and not opening then return true end
        local ok,scene=pcall(context)
        if not ok or not scene then return false,'Light reopen context unavailable; retry explicitly' end
        if opening then opened=scene end
        if not saved then return true end
        if scene.world~=saved.world or scene.generation~=saved.generation or scene.session~=saved.session then
            saved=nil;return true
        end
        local restored,why=lights.replace(saved.lights)
        if restored then saved=nil end
        return restored,why
    end
    return self
end
return M

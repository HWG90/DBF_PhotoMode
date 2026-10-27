-- Chef's guarded calls are the only engine boundary. A skipped void setter is
-- an error, not a successful nil return. No globals, native helpers or IO.
local M = {}
local VIEW_AXES = {'position','forward','up'}
local CALLS = {
    Application = {'main_world', 'time_since_launch'},
    Window = {'has_focus'},
    World = {'debug_camera_pose', 'update_unit'},
    Unit = {'alive', 'num_cameras', 'camera'},
    Camera = {'world_position', 'local_position', 'set_local_position', 'world_pose',
        'local_pose', 'local_rotation', 'set_local_rotation', 'vertical_fov', 'set_vertical_fov'},
    Vector3 = {'x', 'y', 'z'},
    Matrix4x4 = {'translation', 'forward', 'right', 'up', 'rotation',
        'from_quaternion_position', 'multiply', 'inverse'},
    Quaternion = {'to_elements', 'from_elements', 'look'},
}

function M.new(chef, portable)
    local function call(name, ...)
        local a, b, c, d = chef.call(name, ...)
        if a == nil and b ~= nil then error(name .. ': ' .. tostring(b), 0) end
        return a, b, c, d
    end
    local sr = {}
    for family, names in pairs(CALLS) do
        local api = {}; sr[family] = api
        for _, name in ipairs(names) do
            local path = family .. '.' .. name
            if path == 'Quaternion.to_elements' then
                api[name] = function(...) return call(path, ...) end
            else
                -- Chef pads every answer to four values. Native nested calls
                -- must receive one matrix/vector, never its trailing nils.
                api[name] = function(...) return (call(path, ...)) end
            end
        end
    end
    setmetatable(sr.Vector3, {__call = function(_, ...) return (call('Vector3', ...)) end})
    local candidates, scan, world, generation
    sr.World.units = function() return candidates end
    local camera = portable.new(sr)
    local observed = {position={},forward={},right={},up={}}
    local self = {}

    function self.valid()
        -- The loader's world event is delivered only AFTER settling. Check the
        -- live pointer before touching any old unit during that intervening gap.
        return world ~= nil and chef.world_id() == generation and chef.world() == world
            and sr.Application.main_world() == world and sr.Window.has_focus() == true
    end
    function self.forget()
        scan, candidates, world, generation = nil, nil, nil, nil
        camera = portable.new(sr)
    end
    function self.begin()
        assert(world == nil, 'Close the previous camera first')
        local current, id = chef.world(), chef.world_id()
        if not current or not id or id == 0 or sr.Application.main_world() ~= current or sr.Window.has_focus() ~= true then
            return false, 'Camera needs a focused, settled world'
        end
        -- One engine inventory per explicit open; the per-unit work is bounded
        -- to 64 each frame. Never rescan after a failure or while closed.
        local units = call('World.units', current)
        if type(units) ~= 'table' or #units > 32768 then return false, 'Camera inventory unavailable' end
        world, generation, candidates = current, id, {}
        scan = {units = units, index = 1, deadline = sr.Application.time_since_launch() + 5}
        return true
    end
    function self.step()
        if not scan then return camera.active() end
        if not self.valid() then self.forget(); return false, 'World changed during camera discovery' end
        if sr.Application.time_since_launch() > scan.deadline then
            self.forget(); return false, 'Camera discovery timed out; reopen to retry'
        end
        local last = math.min(#scan.units, scan.index + 63)
        for i = scan.index, last do
            local unit = scan.units[i]
            if sr.Unit.alive(unit) and sr.Unit.num_cameras(unit) == 1 then
                candidates[#candidates + 1] = unit
                if #candidates > 64 then self.forget(); return false, 'Too many camera candidates' end
            end
        end
        scan.index = last + 1
        if scan.index <= #scan.units then return nil end
        scan = nil
        -- The existing owner checks the fresh rendered view against all camera
        -- candidates together. No positions or native matrices cross frames.
        local ok, why = camera.open()
        candidates = nil
        if not ok then self.forget() end
        return ok, why
    end
    function self.frame(out) return camera.frame(out) end
    function self.maintain(view)
        if not self.valid() then return false, 'Camera world changed' end
        local current,why=camera.frame(observed)
        if not current then return false,why end
        local same=math.abs(current.fov-view.fov)<1e-6
        for _,key in ipairs(VIEW_AXES) do
            for i=1,3 do if math.abs(current[key][i]-view[key][i])>1e-5 then same=false end end
        end
        if same then return true end
        -- No camera-changed event exists. Reapply only when the game has moved
        -- this same camera component; unchanged views never hit the setters.
        return self.apply(view.position,view.forward,view.up,view.fov)
    end
    function self.apply(position, forward, up, fov)
        if not self.valid() then return false, 'Camera world or focus changed' end
        return camera.write_view(position, forward, up, fov, true)
    end
    function self.close()
        if world == nil then return true end
        if not camera.active() then self.forget(); return true end
        -- A loader generation can change inside the same engine world. Restore
        -- owned values there; never dereference a unit from a retired world.
        if sr.Application.main_world() ~= world then self.forget(); return true end
        local ok, why = camera.close()
        if ok then self.forget() end
        return ok, why
    end
    return self
end
return M

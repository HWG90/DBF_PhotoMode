-- Chef's binding shim suppresses these reads while its own menu is open.
-- It does NOT intercept gameplay input. No window flags/dead zones are changed.
local M = {}
local PREFIX = 'wj.chef.'
local BINDINGS = {
    {'clutch', 'Hold to control camera', 'left alt'},
    {'forward', 'Camera forward', 'w'}, {'back', 'Camera backward', 's'},
    {'left', 'Camera left', 'a'}, {'right', 'Camera right', 'd'},
    {'up', 'Camera up', 'e'}, {'down', 'Camera down', 'q'},
    {'yaw_left', 'Camera look left', 'left'}, {'yaw_right', 'Camera look right', 'right'},
    {'pitch_up', 'Camera look up', 'up'}, {'pitch_down', 'Camera look down', 'down'},
    {'roll_left', 'Camera roll left', 'z'}, {'roll_right', 'Camera roll right', 'c'},
    {'zoom_in', 'Camera zoom in', 'r'}, {'zoom_out', 'Camera zoom out', 'f'},
    {'fast', 'Camera fast movement', 'left shift'},
}
local COMMANDS={{'exit','Close camera / reposition Cinema','p'},{'freeze','Toggle Freeze Action','space'},
    {'lock','Toggle camera movement lock','l'},{'bookmark_save','Save scene bookmark','b'},
    {'bookmark_recall','Recall scene bookmark','n'},{'path_record','Record camera path point','v'},
    {'path_play','Play camera path','k'}}
local function finite(v) return type(v) == 'number' and v == v and math.abs(v) < 1e12 end
function M.new(chef, bindings)
    if type(bindings) ~= 'table' or type(bindings.register_binding) ~= 'function'
        or type(bindings.is_down) ~= 'function' then return nil, 'Chef binding service unavailable' end
    for _, b in ipairs(BINDINGS) do
        local ok, why = bindings.register_binding(PREFIX .. b[1], b[2], nil, {
            category = 'War Journalist controls', default = {button = b[3], trigger = 'hold'},
        })
        if not ok then return nil, why or 'Camera binding refused' end
    end
    local registered,reason=bindings.register_binding(PREFIX..'light_drag','Drag photo light marker',nil,{
        category='War Journalist controls',default={device='mouse',button='middle',trigger='hold'}})
    if not registered then return nil,reason or 'Light drag binding refused' end
    for _,b in ipairs(COMMANDS) do
        local ok,why=bindings.register_binding(PREFIX..b[1],b[2],nil,{
            category='War Journalist controls',default={button=b[3],trigger='press'}})
        if not ok then return nil,why or 'Camera command binding refused' end
    end
    local self, out = {}, {}
    local last, mouse_axis, mouse_first = nil, nil, true
    local function down(id) return bindings.is_down(PREFIX .. id) == true end
    local function axis(positive, negative) return (down(positive) and 1 or 0) - (down(negative) and 1 or 0) end
    function self.drag() if not down('clutch') then return false,false end;return down('light_drag'),down('fast') end
    function self.command()
        if not down('clutch') then return nil end
        for _,item in ipairs(COMMANDS) do if down(item[1]) then return item[1] end end
    end
    function self.reset() last, mouse_first = nil, true end
    function self.sample(mouse)
        -- Only the clutch is sampled when idle. It also gates mouse reads, so
        -- opening Chef's menu stops both keyboard and mouse camera motion.
        if not down('clutch') then self.reset(); return nil end
        if chef.call('Window.has_focus') ~= true then self.reset(); return nil end
        local now, why = chef.call('Application.time_since_launch')
        if not finite(now) then self.reset(); return nil, why or 'Unscaled camera clock unavailable' end
        local dt = last and now >= last and math.min(.1, now - last) or 0
        last = now
        out.dt, out.x, out.y, out.z = dt, axis('right', 'left'), axis('forward', 'back'), axis('up', 'down')
        out.yaw, out.pitch, out.roll = axis('yaw_right', 'yaw_left'), axis('pitch_up', 'pitch_down'), axis('roll_right', 'roll_left')
        out.zoom, out.fast, out.dx, out.dy = axis('zoom_out', 'zoom_in'), down('fast'), 0, 0
        if mouse then
            if mouse_axis == nil then
                local index, reason = chef.call('Mouse.axis_index', 'mouse')
                if not finite(index) or index < 0 or index % 1 ~= 0 then
                    return nil, reason or 'Mouse delta axis unavailable'
                end
                mouse_axis = index
            end
            local v, reason = chef.call('Mouse.axis', mouse_axis)
            if v == nil then return nil, reason or 'Mouse delta unavailable' end
            local x, y = chef.call('Vector3.to_elements', v)
            if not finite(x) or not finite(y) or math.abs(x) > 2000 or math.abs(y) > 2000 then
                self.reset(); return nil, 'Invalid mouse delta'
            end
            if not mouse_first then out.dx, out.dy = x, y end
            mouse_first = false
        else mouse_first = true end
        return out
    end
    return self
end
return M

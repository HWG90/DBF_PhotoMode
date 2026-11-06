local sandbox = assert(loadstring(SANDBOX_SOURCE))().install({
    G = _G, io = {}, os = {getenv = function() end}, debug = debug,
    DIR = 'C:\\fixture\\', GAME_DIR = 'C:\\game\\', log = function() end,
})
local shared = {}
local function context()
    local values, changes, events, logs = {}, {}, {}, {}
    local c = {api = 3, name = 'mods/goose/war_journalist', TOP = 1000}
    local stats = {rects = 0, colors = 0, screens = 0, calls = 0}
    function c.has() return true end
    function c.title() end
    function c.log(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end
    function c.option(id, spec) values[id] = spec.default; return values[id] end
    function c.set(id, v)
        values[id] = v
        if changes[id] then changes[id](v) end
        return v -- Chef returns the VALUE, including false, not a success flag.
    end
    function c.on_change(id, fn) changes[id] = fn end
    function c.share(key, v) shared[key] = v end
    function c.shared(key) return shared[key] end
    function c.on(event, fn)
        events[event] = fn
        return function() events[event] = nil end
    end
    function c.screen() stats.screens = stats.screens + 1; return stats.width or 1920, 1080 end
    function c.color(...) stats.colors = stats.colors + 1; return {...} end
    function c.rect() stats.rects = stats.rects + 1 end
    function c.call() stats.calls = stats.calls + 1; error('No engine work allowed while closed') end
    return c, values, events, logs, stats
end

local c, v, events, logs, stats = context()
local env = sandbox.env(c.name)
assert(env._G ~= _G and not pcall(env.require, 'ffi') and not pcall(env.require, 'wj.unbundled'))
assert(not pcall(env.os.execute, 'never run'))
local chunk = assert(loadstring(CHEF_SOURCE, '@packaged-chef-addon'))
setfenv(chunk, env)
local addon = chunk(c)
assert(addon.status() == 'closed' and addon.update == nil and addon.render == nil)
assert(v.camera == false and stats.calls == 0)
assert(not addon.capabilities.scene_effects and not addon.capabilities.numeric_dof and not addon.capabilities.input_capture)
c.set('grid', 2); c.set('frame', 2)
assert(addon.render == nil and stats.calls == 0)
c.set('overlay', true)
assert(addon.render and addon.update == nil)
addon.render()
assert(stats.rects == 6 and stats.colors == 6)
local composition = env.package.loaded['wj.composition']
local layout, layouts = composition.layout_static, 0
composition.layout_static = function(...) layouts = layouts + 1; return layout(...) end
for _ = 1, 100 do addon.render() end
assert(layouts == 0, 'Unchanged overlay geometry must stay cached')
stats.width = 2560; addon.render(); assert(layouts == 1)
c.set('vignette', 20); addon.render(); assert(layouts == 2)
c.set('overlay', false); assert(addon.render == nil)
assert(addon.on_stop() and addon.shutdown() and not events.world)
assert(sandbox.denied == 0) -- explicit refusal probes above do not perform IO

-- Runtime lifecycle fixtures with a controllable camera backend. These check
-- scheduling/ownership/cleanup, while camera_tests exercises the real adapter.
local factory = env.package.loaded['wj.chef.runtime']
local function runtime()
    local chef, values, ev, messages = context()
    local s = {begins = 0, steps = 0, writes = 0, closes = 0, valid = true, ready = false}
    local cam = {
        begin = function() s.begins = s.begins + 1; return true end,
        valid = function() return s.valid end,
        step = function() s.steps = s.steps + 1; return s.ready or nil end,
        frame = function() return {position = {1,2,3}, forward = {1,0,0}, right = {0,-1,0}, up = {0,0,1}, fov = 1} end,
        apply = function(p, f, u, fov)
            s.writes = s.writes + 1; s.p, s.f, s.u, s.fov = p, f, u, fov
            if s.refuse then return false, 'setter refused' end
            return true
        end,
        maintain = function() return true end,
        close = function()
            s.closes = s.closes + 1
            if s.close_error then error('guarded restore skipped') end
            return not s.pending, 'restore pending'
        end,
    }
    local a = factory.new(chef, {camera = {new = function() return cam end}, composition = composition,
        motion=env.package.loaded['wj.chef.motion'], controls=env.package.loaded['wj.chef.controls'],
        simulation=env.package.loaded['wj.chef.simulation']})
    return a, chef, values, ev, messages, s
end
local a, chef, values, ev, messages, s = runtime()
assert(a.update == nil and s.begins == 0)
chef.set('camera', true)
assert(a.status() == 'opening' and s.begins == 1)
a.update(); assert(s.steps == 1 and s.writes == 0)
chef.set('right', 2); chef.set('forward', 3); chef.set('up', 4); chef.set('fov', 60)
s.ready = true; a.update()
assert(a.status() == 'active' and s.writes == 1)
assert(s.p[1] == 4 and s.p[2] == 0 and s.p[3] == 7 and math.abs(s.fov - math.pi / 3) < 1e-9)
for _ = 1, 1000 do a.update() end
assert(s.writes == 1 and s.steps == 2, 'Active unchanged camera must not rewrite or rescan')
chef.set('yaw', 30); chef.set('pitch', 20); chef.set('roll', 15); a.update()
local norm, dot = 0, 0
for i = 1, 3 do norm = norm + s.f[i]^2; dot = dot + s.f[i] * s.u[i] end
assert(math.abs(norm - 1) < 1e-9 and math.abs(dot) < 1e-9 and s.writes == 2)
local other, other_chef, _, _, _, other_stats = runtime()
other_chef.set('camera', true)
assert(other.status() == 'closed' and other_stats.begins == 0, 'Separate addon environments must share camera ownership')
assert(other.shutdown())
s.valid = false; a.update()
assert(a.status() == 'closed' and a.update == nil and values.camera == false)
assert(next(shared) == nil)
s.valid = true; chef.set('camera', true); a.update()
s.refuse = true; chef.set('right', 1); a.update()
assert(a.status() == 'closed' and a.update == nil, 'A refused setter must stop further writes')
s.refuse = false; chef.set('camera', true); a.update()
s.pending = true; chef.set('camera', false)
assert(a.status() == 'cleanup_pending' and a.update == nil and next(shared) ~= nil)
chef.set('camera', true)
assert(a.status() == 'cleanup_pending' and values.camera == false, 'Failed cleanup must block reacquisition')
s.pending = false; chef.set('camera', true); a.update()
assert(a.status() == 'active')
ev.world(2, false)
assert(a.status() == 'closed' and next(shared) == nil)
chef.set('camera', true); a.update(); assert(a.shutdown())
assert(a.update == nil and a.render == nil and not ev.world)
chef.set('camera', true); assert(a.update == nil, 'Stopped listeners cannot restart the addon')
assert(a.shutdown())

-- Cleanup exceptions retain ownership; a second stop reports the unresolved state.
local broken, bc, _, _, _, bs = runtime()
bc.set('camera', true); bs.ready = true; broken.update(); bs.close_error = true
assert(not broken.on_stop() and not broken.shutdown() and broken.status() == 'cleanup_pending')
assert(next(shared) ~= nil and broken.update == nil)
print('chef runtime: sandbox, retained rendering, ownership and lifecycle passed')

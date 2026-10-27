-- Load only modules embedded in the supplied package, inside the real sandbox.
local sandbox = assert(loadstring(SANDBOX_SOURCE))().install({
    G = _G, io = {}, os = {getenv = function() end}, debug = debug,
    DIR = 'C:\\fixture\\', GAME_DIR = 'C:\\game\\', log = function() end,
})
local chef = {api = 3, name = 'mods/goose/war_journalist', TOP = 1000,
    has = function() return true end, title = function() end, log = function() end,
    option = function(_, spec) return spec.default end, set = function(_, v) return v end,
    on_change = function() end, on = function() return function() end end,
    shared = function() end, share = function() end}
local env = sandbox.env(chef.name)
local chunk = assert(loadstring(CHEF_SOURCE)); setfenv(chunk, env); chunk(chef)
local factory = env.package.loaded['wj.chef.camera']
local portable = env.package.loaded['wj.steam_camera']
local world, generation, now = {}, 1, 0
local unit, component = {}, {}
local p, angle, fov = {1,2,3}, 0, 1
local units = {}; for i = 1, 130 do units[i] = {} end; units[130] = unit
local scans, probes, writes, blocked, dead = 0, 0, 0, nil, false
local focused=true
local function vec(x,y,z) return {x,y,z} end
local function pose(a, pos) return {angle = a, position = {unpack(pos)}} end
local function quaternion(a) return {0,0,math.sin(a/2),math.cos(a/2)} end
local function yaw(q) return 2 * math.atan2(q[3], q[4]) end
local engine = {
    ['Application.main_world'] = function() return world end,
    ['Application.time_since_launch'] = function() return now end,
    ['Window.has_focus'] = function() return focused end,
    ['World.units'] = function(w) assert(w == world); scans = scans + 1; return units end,
    ['World.debug_camera_pose'] = function() return pose(angle, p) end,
    ['World.update_unit'] = function(w, u) assert(w == world and u == unit) end,
    ['Unit.alive'] = function() probes = probes + 1; return not dead end,
    ['Unit.num_cameras'] = function(u) return u == unit and 1 or 0 end,
    ['Unit.camera'] = function(u) assert(u == unit); return component end,
    ['Vector3'] = vec,
    ['Vector3.x'] = function(v) return v[1] end,
    ['Vector3.y'] = function(v) return v[2] end,
    ['Vector3.z'] = function(v) return v[3] end,
    ['Camera.world_position'] = function() return p end,
    ['Camera.local_position'] = function() return p end,
    ['Camera.set_local_position'] = function(c,u,v) assert(c == component and u == unit); p = v; writes = writes + 1 end,
    ['Camera.world_pose'] = function() return pose(angle, p) end,
    ['Camera.local_pose'] = function() return pose(angle, p) end,
    ['Camera.local_rotation'] = function() return quaternion(angle) end,
    ['Camera.set_local_rotation'] = function(c,u,q) angle = yaw(q) end,
    ['Camera.vertical_fov'] = function() return fov end,
    ['Camera.set_vertical_fov'] = function(c,v) fov = v end,
    ['Quaternion.to_elements'] = function(q) return unpack(q) end,
    ['Quaternion.from_elements'] = function(...) return {...} end,
    ['Quaternion.look'] = function(f) return quaternion(math.atan2(f[2], f[1])) end,
    ['Matrix4x4.translation'] = function(m) return m.position end,
    ['Matrix4x4.forward'] = function(m) return {math.cos(m.angle),math.sin(m.angle),0} end,
    ['Matrix4x4.right'] = function(m) return {math.sin(m.angle),-math.cos(m.angle),0} end,
    ['Matrix4x4.up'] = function() return {0,0,1} end,
    ['Matrix4x4.rotation'] = function(m) return quaternion(m.angle) end,
    ['Matrix4x4.from_quaternion_position'] = function(q,v) return pose(yaw(q),v) end,
}
engine['Matrix4x4.multiply'] = function(a,b)
    local c,s = math.cos(b.angle), math.sin(b.angle)
    return pose(a.angle+b.angle, {a.position[1]*c-a.position[2]*s+b.position[1],
        a.position[1]*s+a.position[2]*c+b.position[2], a.position[3]+b.position[3]})
end
engine['Matrix4x4.inverse'] = function(m)
    local c,s = math.cos(m.angle), math.sin(m.angle)
    return pose(-m.angle, {-m.position[1]*c-m.position[2]*s, m.position[1]*s-m.position[2]*c, -m.position[3]})
end
chef.world = function() return world end
chef.world_id = function() return generation end
chef.time = function() return 0 end
function chef.call(name, ...)
    if name == blocked then return nil, 'skipped' end
    assert(engine[name], 'Unexpected API: ' .. name)
    if name=='Matrix4x4.multiply' then assert(select('#',...)==2,'No padded nils in native matrix calls') end
    if name=='Vector3' then assert(select('#',...)==3,'No padded nils in native vector calls') end
    local a,b,c,d=engine[name](...)
    return a,b,c,d
end
local camera = factory.new(chef, portable)
assert(scans == 0 and probes == 0 and camera.close())
assert(camera.begin() and scans == 1)
assert(camera.step() == nil and probes == 64)
assert(camera.step() == nil and probes == 128)
assert(camera.step() == true and scans == 1)
local frame = camera.frame(); assert(frame.position[1] == 1)
local out={position={},forward={},right={},up={}}
local pos=out.position
for _=1,100 do assert(camera.frame(out)==out and out.position==pos) end
assert(camera.apply({4,5,6}, {0,1,0}, {0,0,1}, .8))
assert(p[1] == 4 and fov == .8 and math.abs(angle - math.pi / 2) < 1e-9)
local view={position={4,5,6},forward={0,1,0},up={0,0,1},fov=.8}
local write_count=writes
for _=1,1000 do assert(camera.maintain(view)) end
assert(writes==write_count,'An unchanged held camera never re-enters the setters')
p={10,20,30}
assert(camera.maintain(view) and math.abs(p[1]-4)<1e-9 and writes==write_count+1,'Hold must repair game camera motion')
assert(camera.close() and p[1] == 1 and fov == 1 and math.abs(angle) < 1e-9)

local function open()
    assert(camera.begin())
    local ready
    repeat ready = camera.step() until ready ~= nil
    assert(ready)
end
open(); blocked = 'Camera.set_local_position'
local ok, why = pcall(camera.apply, {9,8,7}, {1,0,0}, {0,0,1}, .7)
assert(not ok and why:find('skipped') and p[1] == 1, 'Guarded nil/reason is not a successful write')
blocked = nil; assert(camera.close())
open(); assert(camera.apply({9,8,7}, {1,0,0}, {0,0,1}, .7))
blocked = 'Camera.set_local_position'
assert(not pcall(camera.close), 'A refused restore must retain its lease')
blocked = nil; assert(camera.close() and p[1] == 1)
open(); assert(camera.apply({4,5,6}, {1,0,0}, {0,0,1}, .8))
p = {20,20,20}; fov = 1.2
assert(camera.close() and p[1] == 20 and fov == 1.2, 'Cleanup must preserve external edits')
open(); assert(camera.apply({4,5,6}, {1,0,0}, {0,0,1}, .8))
generation = generation + 1
assert(not camera.valid() and camera.close() and p[1] == 20, 'Same-world generation changes still restore owned edits')
open(); local before = probes; world = {}; generation = generation + 1
assert(not camera.valid() and camera.close() and probes == before, 'Never touch units in a retired world')
assert(camera.begin()); before = probes; world = {}
assert(camera.step() == false and probes == before)
assert(camera.begin()); now = now + 6
assert(camera.step() == false and camera.close(), 'Discovery has a bounded deadline')
assert(scans == 8, 'One scan per explicit open, no automatic retries')
open();assert(camera.apply({4,5,6},{1,0,0},{0,0,1},.8))
focused=false
assert(not camera.apply({7,8,9},{1,0,0},{0,0,1},.9))
assert(camera.close() and p[1]==20 and fov==1.2,'Focus loss must retain the camera restoration obligation')
print('chef camera: bounded discovery, guarded writes, restoration and world transitions passed')

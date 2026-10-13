-- Bounds-checked CPU sampler for installed-game animation resources. Format
-- reference: HD2SDK Community Edition 5a886256 (animation.py/unit.py/bones.py).
-- This module creates no engine animator and contains no game animation bytes.
local Clip = { MAX_BYTES = 1048576, MAX_BONES = 512, MAX_KEYS = 100000 }
Clip.FILES = {
    unit = '4d1c334d294dfa97.e0a48d0be9a7453f.bin',
    bones = '4d1c334d294dfa97.18dead01056b72e9.bin',
    standing = '759c08277f1296d0.931e336d7646cc26.bin',
    enter = '070b422612518deb.931e336d7646cc26.bin',
    hold = 'e32b270524630569.931e336d7646cc26.bin',
    exit = '39250e5b6313a0b2.931e336d7646cc26.bin',
    wave = 'f7d81dbe0142b9ee.931e336d7646cc26.bin',
    taunt = 'a4950a590f729419.931e336d7646cc26.bin',
    highfive = '75205314048dcdaa.931e336d7646cc26.bin',
}
-- Labels follow exact event/transition names in the captured avatar graph.
-- Held times were sampled and decoded against this same 90-bone rig. Idle
-- uses the ordinary game preview; selecting it requires no authored worker.
Clip.POSES = {
    { id = 'idle', label = 'Idle' },
    { id = 'salute', label = 'Salute', clip = 'hold', time = 0 },
    { id = 'wave', label = 'Wave', clip = 'wave', time = 0.58 },
    { id = 'taunt', label = 'Taunt', clip = 'taunt', time = 0.4 },
    { id = 'highfive', label = 'High Five', clip = 'highfive', time = 0 },
}
function Clip.find_pose(id)
    for _, pose in ipairs(Clip.POSES) do
        if pose.id == id then
            return pose
        end
    end
end
local function finite(n)
    return type(n) == 'number' and n == n and math.abs(n) < math.huge
end
local function reader(bytes)
    assert(type(bytes) == 'string' and #bytes <= Clip.MAX_BYTES, 'Authored animation resource size bound')
    local r = { data = bytes, at = 0 }
    function r.take(n)
        assert(n >= 0 and r.at + n <= #bytes, 'Truncated authored animation resource')
        local s = bytes:sub(r.at + 1, r.at + n)
        r.at = r.at + n
        return s
    end
    function r.seek(at)
        assert(at >= 0 and at <= #bytes, 'Authored resource offset bound')
        r.at = at
    end
    function r.u8()
        return r.take(1):byte()
    end
    function r.u16()
        local a, b = r.take(2):byte(1, 2)
        return a + b * 256
    end
    function r.u32()
        local a, b, c, d = r.take(4):byte(1, 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end
    function r.f32()
        local bits = r.u32()
        local exponent = math.floor(bits / 8388608) % 256
        local fraction = bits % 8388608
        assert(exponent < 255, 'Nonfinite authored animation value')
        local sign = bits >= 2147483648 and -1 or 1
        return sign * (exponent == 0 and fraction * 2 ^ -149 or (1 + fraction / 8388608) * 2 ^ (exponent - 127))
    end
    function r.vector()
        return { r.f32(), r.f32(), r.f32() }
    end
    return r
end
local function normalize(q)
    local sum = 0
    for i = 1, 4 do
        assert(finite(q[i]), 'Invalid authored quaternion')
        sum = sum + q[i] * q[i]
    end
    assert(sum > 0.5 and sum < 1.5, 'Invalid authored quaternion magnitude')
    local n = math.sqrt(sum)
    return { q[1] / n, q[2] / n, q[3] / n, q[4] / n }
end
local function unit_scale(s)
    for i = 1, 3 do
        assert(finite(s[i]) and s[i] > 0 and s[i] <= 128, 'Unsupported authored scale or additive animation')
        if math.abs(s[i] - 1) <= 0.002 then
            s[i] = 1
        end
    end
    -- Compressed unit scale quantizes to 0.999786. Preserve the existing
    -- unit-scale pose constructor instead of accumulating quantization drift.
    return s
end
local function compressed_vector(r)
    return { (r.u16() - 32767) * 10 / 32767, (r.u16() - 32767) * 10 / 32767, (r.u16() - 32767) * 10 / 32767 }
end
local function compressed_rotation(r)
    local bits = r.u32()
    local largest = bits % 4
    local q = {}
    local sum = 0
    for i = 0, 2 do
        local value = (math.floor(bits / 2 ^ (2 + 10 * i)) % 1024 - 512) * 0.75 / 512
        q[(largest + i + 1) % 4 + 1] = value
        sum = sum + value * value
    end
    assert(sum <= 1.005, 'Invalid compressed authored quaternion')
    q[largest + 1] = math.sqrt(math.max(0, 1 - sum))
    return normalize(q)
end
local function matrix(p, q, s)
    q = normalize(q)
    s = unit_scale(s)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local m = {
        1 - 2 * (y * y + z * z),
        2 * (x * y + z * w),
        2 * (x * z - y * w),
        0,
        2 * (x * y - z * w),
        1 - 2 * (x * x + z * z),
        2 * (y * z + x * w),
        0,
        2 * (x * z + y * w),
        2 * (y * z - x * w),
        1 - 2 * (x * x + y * y),
        0,
        p[1],
        p[2],
        p[3],
        1,
    }
    for row = 1, 3 do
        for column = 1, 3 do
            local index = (row - 1) * 4 + column
            m[index] = m[index] * s[row]
        end
    end
    return m
end
local function multiply(a, b)
    local c = {}
    for row = 0, 3 do
        for col = 0, 3 do
            local n = 0
            for k = 0, 3 do
                n = n + a[row * 4 + k + 1] * b[k * 4 + col + 1]
            end
            c[row * 4 + col + 1] = n
        end
    end
    return c
end
local function bones(bytes)
    local r = reader(bytes)
    local count, lods = r.u32(), r.u32()
    assert(count >= 1 and count <= Clip.MAX_BONES and lods <= 64, 'Authored bone count bound')
    r.take(lods * 4)
    local hashes = {}
    for i = 1, count do
        hashes[i] = r.u32()
    end
    r.take(lods * 4)
    local names, seen = {}, {}
    for i = 1, count do
        local name = {}
        for _ = 1, 128 do
            local c = r.u8()
            if c == 0 then
                break
            end
            name[#name + 1] = string.char(c)
        end
        name = table.concat(name)
        assert(
            #name > 0 and #name < 128 and name:match('^[%w_]+$') and not seen[name] and not seen[hashes[i]],
            'Invalid authored bone names'
        )
        names[i] = name
        seen[name] = true
        seen[hashes[i]] = true
    end
    assert(r.at == #bytes, 'Authored bone resource trailing data')
    return names, hashes
end
local function rig(bytes, names, hashes)
    local r = reader(bytes)
    r.seek(52)
    local offset = r.u32()
    r.seek(offset)
    local count = r.u32()
    assert(count >= #names and count <= Clip.MAX_BONES, 'Authored rig node count bound')
    r.take(12)
    local locals = {}
    for i = 1, count do
        local rot = {}
        for j = 1, 9 do
            rot[j] = r.f32()
        end
        local p, s = r.vector(), unit_scale(r.vector())
        r.f32()
        locals[i] =
            { rot[1], rot[2], rot[3], 0, rot[4], rot[5], rot[6], 0, rot[7], rot[8], rot[9], 0, p[1], p[2], p[3], 1 }
        for row = 1, 3 do
            for column = 1, 3 do
                local index = (row - 1) * 4 + column
                locals[i][index] = locals[i][index] * s[row]
            end
        end
    end
    r.take(count * 64)
    local parents = {}
    for i = 1, count do
        r.u16()
        local parent = r.u16()
        assert(i == 1 or parent == 65535 or parent < i - 1, 'Authored rig parent bounds/cycle')
        parents[i] = (i == 1 or parent == 65535) and 0 or parent + 1
    end
    local by_hash = {}
    for i, name in ipairs(names) do
        by_hash[hashes[i]] = { name = name, bone = i }
    end
    local nodes, by_name = {}, {}
    for i = 1, count do
        local named = by_hash[r.u32()]
        nodes[i] = { parent = parents[i], rest = locals[i], name = named and named.name, bone = named and named.bone }
        if named then
            assert(not by_name[named.name], 'Duplicate authored rig bone')
            by_name[named.name] = i
        end
    end
    for _, name in ipairs(names) do
        assert(by_name[name], 'Authored rig/bones mapping differs')
    end
    return nodes
end
local function animation(bytes, count)
    local r = reader(bytes)
    local version, n, duration, size, h1, h2 = r.u32(), r.u32(), r.f32(), r.u32(), r.u32(), r.u32()
    assert(
        version == 0 and n == count and duration > 0 and duration <= 60 and size == #bytes and h1 <= 4096 and h2 <= 4096,
        'Authored animation header changed'
    )
    r.take((h1 + h2) * 8)
    r.u16()
    local flag_bytes = math.ceil(count * 3 / 8)
    flag_bytes = flag_bytes + flag_bytes % 2
    local flags = r.take(flag_bytes)
    local channels = {}
    local function flag(i)
        return math.floor(flags:byte(math.floor(i / 8) + 1) / 2 ^ (i % 8)) % 2 == 1
    end
    for i = 1, count do
        local p = flag((i - 1) * 3) and compressed_vector(r) or r.vector()
        local q = flag((i - 1) * 3 + 1) and compressed_rotation(r) or normalize({ r.f32(), r.f32(), r.f32(), r.f32() })
        local s = unit_scale(flag((i - 1) * 3 + 2) and compressed_vector(r) or r.vector())
        channels[i] =
            { p = { { time = 0, value = p } }, q = { { time = 0, value = q } }, s = { { time = 0, value = s } } }
    end
    for _ = 1, h1 do
        r.f32()
    end
    local keys, terminated = 0, false
    for _ = 1, Clip.MAX_KEYS do
        local at = r.at
        local first = r.u16()
        r.seek(at)
        if first == 3 then
            r.u16()
            terminated = true
            break
        end
        local a, b, c, d = r.u8(), r.u8(), r.u8(), r.u8()
        local kind = math.floor(b / 64)
        local bone, time, subtype
        if kind == 0 then
            r.seek(at)
            subtype = r.u16()
            bone = r.u32()
            time = r.f32()
        else
            bone = math.floor(a / 16) + (b % 64) * 16
            time = ((a % 16) * 65536 + d * 256 + c) / 1000
        end
        assert(time >= 0 and time <= duration + 0.101, 'Authored animation key time bound')
        local field, value
        if kind == 3 then
            field, value = 'q', compressed_rotation(r)
        elseif kind == 2 then
            field, value = 'p', compressed_vector(r)
        elseif kind == 1 then
            field, value = 's', unit_scale(compressed_vector(r))
        elseif subtype == 4 then
            field, value = 'p', r.vector()
        elseif subtype == 5 then
            field, value = 'q', normalize({ r.f32(), r.f32(), r.f32(), r.f32() })
        elseif subtype == 6 then
            field, value = 's', unit_scale(r.vector())
        else
            assert(subtype == 2, 'Unknown authored animation key format')
        end
        if field then
            assert(bone < count, 'Authored animation key bone bound')
            local track = channels[bone + 1][field]
            track[#track + 1] = { time = time, value = value }
            keys = keys + 1
        end
    end
    assert(terminated, 'Authored animation key work bound')
    -- Some game clips contain a second serialized copy after a size footer.
    -- It is not a second playback period. All bytes remain size-bounded.
    if r.at < #bytes then
        local parsed_end = r.at
        assert(r.u32() == parsed_end and #bytes == r.at * 2, 'Authored animation footer changed')
        local half = r.at
        for i = 1, half do
            -- The second copy omits the first header's complete file size.
            assert(
                bytes:byte(half + i) == (i >= 13 and i <= 16 and 0 or bytes:byte(i)),
                'Authored animation copy changed'
            )
        end
    end
    for _, bone in ipairs(channels) do
        for _, track in pairs(bone) do
            for i, key in ipairs(track) do
                key.order = i
            end
            table.sort(track, function(a, b)
                return a.time == b.time and a.order < b.order or a.time < b.time
            end)
        end
    end
    return { duration = duration, channels = channels, keys = keys }
end
function Clip.decode(resources)
    local names, hashes = bones(assert(resources.bones, 'Authored bones missing'))
    local set =
        { names = names, nodes = rig(assert(resources.unit, 'Authored rig missing'), names, hashes), clips = {} }
    for _, name in ipairs({ 'standing', 'enter', 'hold', 'exit' }) do
        set.clips[name] = animation(assert(resources[name], 'Authored ' .. name .. ' missing'), #names)
    end
    -- Legacy decoder fixtures and experimental fallback sets remain valid.
    -- Runtime load() reads the complete versioned file catalog below.
    for _, name in ipairs({ 'wave', 'taunt', 'highfive' }) do
        if resources[name] then
            set.clips[name] = animation(resources[name], #names)
            assert(Clip.find_pose(name).time <= set.clips[name].duration, 'Preview held frame exceeds clip duration')
        end
    end
    set.sample = function(time, pose_id)
        return Clip.sample(set, time, pose_id)
    end
    return set
end
function Clip.load(folder)
    assert(type(folder) == 'string' and #folder > 0 and #folder < 4096, 'Authored animation cache path invalid')
    local resources = {}
    for key, name in pairs(Clip.FILES) do
        local file = assert(io.open(folder .. '/' .. name, 'rb'), 'Authored animation cache missing: ' .. name)
        local bytes = file:read(Clip.MAX_BYTES + 1)
        file:close()
        assert(#bytes <= Clip.MAX_BYTES, 'Authored resource exceeds size bound')
        resources[key] = bytes
    end
    return Clip.decode(resources)
end
local function slerp(a, b, t)
    local d = 0
    for i = 1, 4 do
        d = d + a[i] * b[i]
    end
    local sign = d < 0 and -1 or 1
    d = math.abs(d)
    local out = {}
    if d > 0.9995 then
        for i = 1, 4 do
            out[i] = a[i] + (b[i] * sign - a[i]) * t
        end
    else
        local angle = math.acos(math.min(1, d))
        local inv = 1 / math.sin(angle)
        local wa, wb = math.sin((1 - t) * angle) * inv, math.sin(t * angle) * inv * sign
        for i = 1, 4 do
            out[i] = a[i] * wa + b[i] * wb
        end
    end
    return normalize(out)
end
local function curve(track, time, rotation)
    local left, right = track[1], nil
    for i = 2, #track do
        if track[i].time <= time then
            left = track[i]
        else
            right = track[i]
            break
        end
    end
    if not right or right.time == left.time then
        return left.value
    end
    local t = math.max(0, math.min(1, (time - left.time) / (right.time - left.time)))
    if rotation then
        return slerp(left.value, right.value, t)
    end
    local v = {}
    for i = 1, 3 do
        v[i] = left.value[i] + (right.value[i] - left.value[i]) * t
    end
    return v
end
function Clip.sample(set, time, pose_id)
    assert(finite(time) and time >= 0, 'Authored animation time invalid')
    local pose = assert(Clip.find_pose(pose_id == nil and 'salute' or pose_id), 'Unknown preview pose')
    if pose.id == 'idle' then
        return nil, 'idle', 0
    end
    local clip = assert(set.clips[pose.clip], 'Preview pose clip unavailable: ' .. pose.id)
    local phase, at = pose.id == 'salute' and 'saluting' or pose.id, pose.time
    assert(finite(at) and at >= 0 and at <= clip.duration, 'Preview held frame exceeds clip duration')
    -- Body time stays at the selected authored frame. The driver retains its
    -- independent cape clock, without playing emote entry/exit or sound events.
    local world, named = {}, {}
    for i, node in ipairs(set.nodes) do
        local local_pose = node.rest
        if node.bone then
            local b = clip.channels[node.bone]
            local_pose = matrix(curve(b.p, at), curve(b.q, at, true), curve(b.s, at))
        end
        world[i] = node.parent == 0 and local_pose or multiply(local_pose, world[node.parent])
        if node.name then
            named[node.name] = world[i]
        end
    end
    return named, phase, at
end
function Clip.pose(m)
    local values, scale = {}, {}
    for i = 1, 16 do
        assert(finite(m[i]), 'Invalid authored pose matrix')
        values[i] = m[i]
    end
    for row = 1, 3 do
        local at = (row - 1) * 4
        scale[row] = math.sqrt(m[at + 1] ^ 2 + m[at + 2] ^ 2 + m[at + 3] ^ 2)
        assert(scale[row] > 1e-6 and scale[row] <= 128, 'Unsupported authored pose scale')
        for col = 1, 3 do
            values[at + col] = m[at + col] / scale[row]
        end
    end
    m = values
    local trace = m[1] + m[6] + m[11]
    local q = {}
    if trace > 0 then
        local s = math.sqrt(trace + 1) * 2
        q = { (m[7] - m[10]) / s, (m[9] - m[3]) / s, (m[2] - m[5]) / s, 0.25 * s }
    elseif m[1] > m[6] and m[1] > m[11] then
        local s = math.sqrt(1 + m[1] - m[6] - m[11]) * 2
        q = { 0.25 * s, (m[5] + m[2]) / s, (m[9] + m[3]) / s, (m[7] - m[10]) / s }
    elseif m[6] > m[11] then
        local s = math.sqrt(1 + m[6] - m[1] - m[11]) * 2
        q = { (m[5] + m[2]) / s, 0.25 * s, (m[10] + m[7]) / s, (m[9] - m[3]) / s }
    else
        local s = math.sqrt(1 + m[11] - m[1] - m[6]) * 2
        q = { (m[9] + m[3]) / s, (m[10] + m[7]) / s, 0.25 * s, (m[2] - m[5]) / s }
    end
    return { m[13], m[14], m[15] }, normalize(q), scale
end
return Clip

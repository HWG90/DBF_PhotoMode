-- Camera owns yaw/pitch; gameplay receives none of these mouse deltas.
local M={}
function M.basis(photo,initial,input)
    local v=photo.view
    if not v then
        v={yaw=math.atan2(initial[2],initial[1]),pitch=math.asin(math.max(-1,math.min(1,initial[3])))}
        photo.view=v
    end
    if v.sequence~=input.sequence then
        local scale=math.rad(input.sensitivity or 0.15)
        local dx=math.max(-4096,math.min(4096,input.mouse_x or 0))
        local dy=math.max(-4096,math.min(4096,input.mouse_y or 0))
        local smoothing=input.smoothing==true
        local yaw=smoothing and(v.target_yaw or v.yaw)or v.yaw
        local pitch=smoothing and(v.target_pitch or v.pitch)or v.pitch
        yaw=(yaw-dx*scale)%(2*math.pi)
        pitch=math.max(math.rad(-89),math.min(math.rad(89),pitch-dy*scale))
        if smoothing then
            local dt=tonumber(input.dt)or 0;dt=dt==dt and math.max(0,math.min(.1,dt))or 0
            local alpha=1-math.exp(-dt/(input.smoothing_time or .15))
            v.target_yaw,v.target_pitch=yaw,pitch
            local arc=(yaw-v.yaw+math.pi)%(2*math.pi)-math.pi
            v.yaw=(v.yaw+arc*alpha)%(2*math.pi);v.pitch=v.pitch+(pitch-v.pitch)*alpha
        else v.yaw,v.pitch=yaw,pitch;v.target_yaw,v.target_pitch=nil,nil end
        v.sequence=input.sequence
    end
    local cy,sy,cp,sp=math.cos(v.yaw),math.sin(v.yaw),math.cos(v.pitch),math.sin(v.pitch)
    return {cy*cp,sy*cp,sp},{sy,-cy,0}
end
-- A level view along a camera's forward: its yaw and pitch, never its roll.
function M.level(forward)
    local yaw=math.atan2(forward[2],forward[1])
    local pitch=math.max(math.rad(-89),math.min(math.rad(89),math.asin(math.max(-1,math.min(1,forward[3])))))
    local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    return {cy*cp,sy*cp,sp},{sy,-cy,0}
end
-- Follow cameras for action shots. Pivot: the camera stays where it was placed and turns to
-- keep the subject where it was framed. Pin: the camera keeps its offset from the subject and
-- its orientation in space, moving with it. target is the point to frame (the head), anchor
-- the subject's position.
local function direction(yaw,pitch)
    local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    return {cy*cp,sy*cp,sp},{sy,-cy,0}
end
local function toward(from,to)
    local d={to[1]-from[1],to[2]-from[2],to[3]-from[3]};local n=math.sqrt(d[1]^2+d[2]^2+d[3]^2)
    if n<.05 then return nil end
    return math.atan2(d[2],d[1]),math.asin(math.max(-1,math.min(1,d[3]/n)))
end
function M.follow_start(kind,position,forward,target,anchor)
    assert(kind=='pivot'or kind=='pin','Unknown follow camera')
    local yaw=math.atan2(forward[2],forward[1]);local pitch=math.asin(math.max(-1,math.min(1,forward[3])))
    local state={kind=kind,position={position[1],position[2],position[3]},yaw=yaw,pitch=pitch}
    if kind=='pin'then
        state.offset={position[1]-anchor[1],position[2]-anchor[2],position[3]-anchor[3]}
    else
        local ty,tp=toward(position,target)
        state.dyaw,state.dpitch=ty and(yaw-ty+math.pi)%(2*math.pi)-math.pi or 0,ty and pitch-tp or 0
    end
    return state
end
function M.follow_step(state,target,anchor)
    if state.kind=='pin'then
        local o=state.offset;local f,r=direction(state.yaw,state.pitch)
        return {anchor[1]+o[1],anchor[2]+o[2],anchor[3]+o[3]},f,r
    end
    local p=state.position;local ty,tp=toward(p,target)
    if ty then
        state.yaw=(ty+state.dyaw)%(2*math.pi)
        state.pitch=math.max(math.rad(-89),math.min(math.rad(89),tp+state.dpitch))
    end
    local f,r=direction(state.yaw,state.pitch)
    return {p[1],p[2],p[3]},f,r
end
return M

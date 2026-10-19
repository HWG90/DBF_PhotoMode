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
return M

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
        v.yaw=(v.yaw-dx*scale)%(2*math.pi)
        v.pitch=math.max(math.rad(-89),math.min(math.rad(89),v.pitch-dy*scale))
        v.sequence=input.sequence
    end
    local cy,sy,cp,sp=math.cos(v.yaw),math.sin(v.yaw),math.cos(v.pitch),math.sin(v.pitch)
    return {cy*cp,sy*cp,sp},{sy,-cy,0}
end
return M

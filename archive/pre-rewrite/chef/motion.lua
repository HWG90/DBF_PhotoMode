-- Numeric camera state only. Reused buffers; no native objects or per-frame IO.
local M = {}
local VIEW_KEYS={'position','forward','right','up'}
local CHANNELS={'x','y','z','yaw','pitch','roll','zoom'}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function copy(v) return {v[1],v[2],v[3]} end
function M.new(frame)
    local view = {position = copy(frame.position), forward = copy(frame.forward),
        right = copy(frame.right), up = copy(frame.up), fov = frame.fov}
    local original_fov, edits = frame.fov, {right=0,forward=0,up=0,yaw=0,pitch=0,roll=0,fov=0}
    local self = {}
    local velocity={x=0,y=0,z=0,yaw=0,pitch=0,roll=0,zoom=0}
    local desired={}
    function self.reset_motion() for _,key in ipairs(CHANNELS) do velocity[key]=0 end end
    local function move(x,y,z)
        for i=1,3 do view.position[i] = view.position[i] + view.right[i]*x + view.forward[i]*y + view.up[i]*z end
    end
    local function rotate(yaw,pitch,roll)
        if yaw == 0 and pitch == 0 and roll == 0 then return end
        local f,r,u = view.forward,view.right,view.up
        local cy,sy,cp,sp,cr,sr = math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch),math.cos(roll),math.sin(roll)
        for i=1,3 do
            local yf,yr = f[i]*cy+r[i]*sy,r[i]*cy-f[i]*sy
            local pf,pu = yf*cp+u[i]*sp,u[i]*cp-yf*sp
            f[i],r[i],u[i] = pf,yr*cr+pu*sr,pu*cr-yr*sr
        end
        -- Suppress accumulated floating-point drift during long camera takes.
        local length = math.sqrt(f[1]^2+f[2]^2+f[3]^2)
        for i=1,3 do f[i]=f[i]/length end
        r[1],r[2],r[3]=f[2]*u[3]-f[3]*u[2],f[3]*u[1]-f[1]*u[3],f[1]*u[2]-f[2]*u[1]
        length=math.sqrt(r[1]^2+r[2]^2+r[3]^2)
        for i=1,3 do r[i]=r[i]/length end
        u[1],u[2],u[3]=r[2]*f[3]-r[3]*f[2],r[3]*f[1]-r[1]*f[3],r[1]*f[2]-r[2]*f[1]
    end
    function self.adjust(values)
        move(values.right-edits.right,values.forward-edits.forward,values.up-edits.up)
        rotate(math.rad(values.yaw-edits.yaw),math.rad(values.pitch-edits.pitch),math.rad(values.roll-edits.roll))
        if values.fov ~= edits.fov then view.fov=values.fov==0 and original_fov or math.rad(values.fov) end
        for key in pairs(edits) do edits[key]=values[key] end
    end
    function self.step(input, options)
        if not input then self.reset_motion();return false end
        local dt = input.dt
        if dt<=0 then self.reset_motion();return false end
        local turn = math.rad(options.turn_speed)
        local length = math.sqrt(input.x^2+input.y^2+input.z^2)
        local speed=options.move_speed*(input.fast and 4 or 1)
        desired.x=length>0 and input.x/length*speed or 0
        desired.y=length>0 and input.y/length*speed or 0
        desired.z=length>0 and input.z/length*speed or 0
        desired.yaw=input.yaw*turn+math.rad(input.dx*options.mouse_sensitivity)/dt
        desired.pitch=input.pitch*turn+math.rad(input.dy*options.mouse_sensitivity)/dt
        desired.roll=input.roll*math.rad(options.roll_speed or options.turn_speed)
        desired.zoom=math.rad(input.zoom*(options.zoom_speed or 45))
        local tau=math.max(.001,(options.smoothing_strength or 50)*.003)
        local alpha=options.camera_smoothing and (options.smoothing_strength or 50)>0 and 1-math.exp(-dt/tau) or 1
        for _,key in ipairs(CHANNELS) do
            local v=velocity[key]+(desired[key]-velocity[key])*alpha
            velocity[key]=math.abs(v)<1e-6 and 0 or v
        end
        local yaw,pitch,roll=velocity.yaw*dt,velocity.pitch*dt,velocity.roll*dt
        local fov = view.fov
        if velocity.zoom~=0 then fov=clamp(fov+velocity.zoom*dt,math.rad(5),math.rad(120)) end
        local moved = velocity.x~=0 or velocity.y~=0 or velocity.z~=0
        if not moved and yaw==0 and pitch==0 and roll==0 and fov==view.fov then return false end
        rotate(yaw,pitch,roll)
        if moved then
            move(velocity.x*dt,velocity.y*dt,options.vertical_world and 0 or velocity.z*dt)
            if options.vertical_world then view.position[3]=view.position[3]+velocity.z*dt end
        end
        view.fov=fov
        return true
    end
    function self.view() return view end
    function self.lens(mm)
        assert(type(mm)=='number' and mm>=12 and mm<=300,'Invalid focal length')
        view.fov=2*math.atan(12/mm);self.reset_motion()
    end
    function self.tilt(degrees)
        local f,r=view.forward,view.right
        local yaw=math.atan2(f[2],f[1]);local pitch=math.atan2(f[3],math.sqrt(f[1]^2+f[2]^2))
        local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
        local roll=math.atan2(-r[1]*cy*sp-r[2]*sy*sp+r[3]*cp,r[1]*sy-r[2]*cy)
        rotate(0,0,math.rad(degrees)-roll);self.reset_motion()
    end
    function self.replace(next_view)
        assert(type(next_view)=='table' and type(next_view.fov)=='number' and next_view.fov>0 and next_view.fov<math.pi,'Invalid camera view')
        for _,key in ipairs(VIEW_KEYS) do
            local v=next_view[key];assert(type(v)=='table','Camera basis missing')
            for i=1,3 do assert(type(v[i])=='number' and v[i]==v[i] and math.abs(v[i])<1e7,'Invalid camera coordinate') end
        end
        for _,key in ipairs(VIEW_KEYS) do for i=1,3 do view[key][i]=next_view[key][i] end end
        view.fov=next_view.fov
        self.reset_motion()
    end
    function self.recenter(next_view)
        self.replace(next_view);for key in pairs(edits) do edits[key]=0 end
    end
    return self
end
return M

-- Scene-local paths/bookmarks and five persistent opening-camera-relative presets.
-- Saved data is numeric and validated. Native handles never enter persistence.
local M={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e7 end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function vector(v)
    return type(v)=='table' and finite(v[1]) and finite(v[2]) and finite(v[3])
end
function M.valid(v)
    if type(v)~='table' or not vector(v.position) or not vector(v.forward) or
        not vector(v.right) or not vector(v.up) or not finite(v.fov) or v.fov<=0 or v.fov>=math.pi then return false end
    for _,axis in ipairs({'forward','right','up'}) do if math.abs(dot(v[axis],v[axis])-1)>.001 then return false end end
    if math.abs(dot(v.forward,v.up))>.001 or math.abs(dot(v.forward,v.right))>.001 or math.abs(dot(v.right,v.up))>.001 then return false end
    local f,u,r=v.forward,v.up,v.right
    return (f[2]*u[3]-f[3]*u[2])*r[1]+(f[3]*u[1]-f[1]*u[3])*r[2]+(f[1]*u[2]-f[2]*u[1])*r[3]>.999
end
local function copy(v)
    local out={fov=v.fov}
    for _,key in ipairs({'position','forward','right','up'}) do local p=v[key];out[key]={p[1],p[2],p[3]} end
    return out
end
local function transform(v,a,inverse)
    local out={fov=v.fov}
    for _,key in ipairs({'position','forward','right','up'}) do
        local p=v[key];local q={p[1],p[2],p[3]}
        if inverse then
            if key=='position' then for i=1,3 do q[i]=q[i]-a.position[i] end end
            out[key]={dot(q,a.right),dot(q,a.forward),dot(q,a.up)}
        else
            for i=1,3 do q[i]=p[1]*a.right[i]+p[2]*a.forward[i]+p[3]*a.up[i]+(key=='position' and a.position[i] or 0) end
            out[key]=q
        end
    end
    return out
end
function M.relative(view,anchor,inverse)
    assert(M.valid(view) and M.valid(anchor),'Invalid camera-relative frame')
    return transform(view,anchor,inverse==true)
end
local function frame(point,out)
    out=out or {position={},forward={},right={},up={}}
    local cy,sy,cp,sp=math.cos(point.yaw),math.sin(point.yaw),math.cos(point.pitch),math.sin(point.pitch)
    local cr,sr=math.cos(math.rad(point.roll)),math.sin(math.rad(point.roll))
    local f,r,u=out.forward,out.right,out.up
    f[1],f[2],f[3]=cy*cp,sy*cp,sp
    r[1],r[2],r[3]=sy*cr-cy*sp*sr,-cy*cr-sy*sp*sr,cp*sr
    u[1],u[2],u[3]=-cy*sp*cr-sy*sr,-sy*sp*cr+cy*sr,cp*cr
    for i=1,3 do out.position[i]=point.pos[i] end
    out.fov=point.fov;return out
end
function M.new(chef,path_factory)
    local self={};local path=path_factory.new();local anchor,marks,saved=nil,{},nil
    local sample={pos={}}
    local output={position={},forward={},right={},up={}}
    local function clock()
        local now,why=chef.call('Application.time_since_launch')
        if not finite(now) then error(why or 'Camera path clock unavailable',0) end
        return now
    end
    local function slot(n) return type(n)=='number' and n%1==0 and n>=1 and n<=5 end
    local function load()
        if saved then return true end
        if not chef.has('save_table') then return false,'Chef saved-table service unavailable' end
        local data,why=chef.load_table('camera_presets_v1')
        if not data then
            if why~='none saved' then return false,why or 'Preset read failed' end
            saved={version=1,slots={}};return true
        end
        if type(data)~='table' or data.version~=1 or type(data.slots)~='table' then return false,'Invalid saved camera presets' end
        local clean={version=1,slots={}}
        for i,v in pairs(data.slots) do
            if not slot(i) or not M.valid(v) then return false,'Invalid saved camera preset' end
            clean.slots[i]=copy(v)
        end
        saved=clean;return true
    end
    function self.begin(view) assert(M.valid(view),'Invalid opening camera');anchor=copy(view);marks={};path.clear() end
    function self.reset() anchor=nil;marks={};path.clear() end
    function self.origin() return anchor and copy(anchor) end
    function self.stop() path.stop() end
    function self.playing() return path.playing end
    function self.count() return path.count() end
    function self.record(view,duration,transition)
        if not anchor or not M.valid(view) then return false,'Open a valid photo camera first' end
        local f,r=view.forward,view.right
        local yaw=math.atan2(f[2],f[1]);local pitch=math.atan2(f[3],math.sqrt(f[1]^2+f[2]^2))
        local r0={math.sin(yaw),-math.cos(yaw),0}
        local u0={-math.cos(yaw)*math.sin(pitch),-math.sin(yaw)*math.sin(pitch),math.cos(pitch)}
        return path.add({pos=view.position,yaw=yaw,pitch=pitch,roll=math.deg(math.atan2(dot(r,u0),dot(r,r0))),
            fov=view.fov,duration=duration,transition=transition})
    end
    function self.play() if not anchor then return false,'Open a photo camera first' end;return path.play(clock()) end
    function self.remove(index) return path.remove(index or path.count()) end
    function self.configure(index,duration,transition) return path.configure(index,duration,transition) end
    function self.point(index)
        local point=path.point(index);if not point then return nil,'Choose a recorded point' end
        return frame(point)
    end
    function self.clear() path.clear();return true end
    function self.sample()
        if not path.playing then return nil end
        local ok,why=path.sample(clock(),sample)
        if not ok then return nil,why end
        return frame(sample,output)
    end
    function self.bookmark(action,index,view)
        if not slot(index) or not anchor then return false,'Open a camera and choose slot 1-5' end
        if action=='save' then
            if not M.valid(view) then return false,'Invalid camera view' end
            marks[index]=copy(view);return true
        elseif action=='clear' then marks[index]=nil;return true
        elseif action=='recall' then
            if marks[index] then return copy(marks[index]) end
            return nil,'Bookmark is empty'
        end
        return false,'Unknown bookmark action'
    end
    function self.preset(action,index,view)
        if not slot(index) or not anchor then return false,'Open a camera and choose slot 1-5' end
        local ok,why=load();if not ok then return false,why end
        if action=='recall' then
            if not saved.slots[index] then return nil,'Preset is empty' end
            return transform(saved.slots[index],anchor,false)
        end
        if action~='save' and action~='clear' then return false,'Unknown preset action' end
        if action=='save' and not M.valid(view) then return false,'Invalid camera view' end
        local next_data={version=1,slots={}}
        for i,v in pairs(saved.slots) do next_data.slots[i]=copy(v) end
        next_data.slots[index]=action=='save' and transform(view,anchor,true) or nil
        ok,why=chef.save_table('camera_presets_v1',next_data)
        if not ok then return false,why or 'Preset save failed' end
        saved=next_data;return true
    end
    return self
end
return M

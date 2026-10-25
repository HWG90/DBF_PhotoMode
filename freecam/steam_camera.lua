-- Lua 5.1 camera boundary. Unit references are engine weak handles; numeric
-- Unit IDs are level IDs and must never be used to retain dynamic cameras.
-- Discovery is explicit. A closed camera performs no native reads or scans.
local M = {}
local function finite(n)
    return type(n) == 'number' and n == n and math.abs(n) < 1e8
end
function M.new(sr)
    local A,W,U,C,V,B = sr.Application,sr.World,sr.Unit,sr.Camera,sr.Vector3,sr.Matrix4x4
    local self,held = {},nil
    local generation=0
    local function xyz(v)
        local x,y,z = V.x(v),V.y(v),V.z(v)
        assert(finite(x) and finite(y) and finite(z),'Invalid camera position')
        return x,y,z
    end
    local function numbers(v)local x,y,z=xyz(v);return{x,y,z}end
    local function direction(v)
        assert(type(v)=='table'and finite(v[1])and finite(v[2])and finite(v[3]),'Invalid camera direction')
        assert(math.abs(v[1]^2+v[2]^2+v[3]^2-1)<.02,'Camera direction is not normalized')
    end
    local function quaternion(value)
        local x,y,z,w=sr.Quaternion.to_elements(value)
        assert(finite(x)and finite(y)and finite(z)and finite(w),'Invalid camera rotation')
        return{x,y,z,w}
    end
    local function same_rotation(a,b)
        local minus,plus=0,0
        for i=1,4 do minus=minus+(a[i]-b[i])^2;plus=plus+(a[i]+b[i])^2 end
        return math.min(minus,plus)<1e-8
    end
    local function near(a,b)
        local x,y,z = xyz(a);local p,q,r = xyz(b)
        return (x-p)^2+(y-q)^2+(z-r)^2 <= 1e-6
    end
    local function current()
        if not held then return nil,'Camera is closed' end
        if A.main_world() ~= held.world then held=nil;return nil,'Main world changed' end
        if not U.alive(held.unit) then held=nil;return nil,'Camera unit retired' end
        -- Never retain a component pointer across an engine update.
        local camera = U.camera(held.unit,1)
        if not camera then held=nil;return nil,'Camera component unavailable' end
        if camera~=held.camera then held=nil;return nil,'Camera component replaced' end
        return camera
    end
    function self.open()
        if held then return false,'Camera is already open' end
        local world=A.main_world()
        if not world then return false,'Main world unavailable' end
        local rendered_pose=W.debug_camera_pose(world)
        local rendered=B.translation(rendered_pose)
        local units=W.units(world)
        if type(units)~='table' or #units>32768 then return false,'Camera inventory unavailable' end
        local candidate,count=nil,0
        local candidates={}
        for _,unit in ipairs(units) do
            if U.alive(unit) and U.num_cameras(unit)==1 then
                local camera=U.camera(unit,1)
                if camera and near(C.world_position(camera),rendered) then
                    candidate=unit;count=count+1
                    candidates[#candidates+1]=unit
                end
            end
        end
        if count~=1 then
            local exact,exact_count=nil,0
            local function same_vector(a,b)
                local x,y,z=xyz(a);local p,q,r=xyz(b)
                return x==p and y==q and z==r
            end
            -- Ship cameras can share a position. Only a unique exact match
            -- to the published world pose disambiguates them.
            if count>1 and type(C.world_pose)=='function'and type(B.forward)=='function'and type(B.right)=='function'and type(B.up)=='function'then
                for _,unit in ipairs(candidates)do
                    local pose=C.world_pose(U.camera(unit,1))
                    if same_vector(B.translation(pose),rendered)and
                       same_vector(B.forward(pose),B.forward(rendered_pose))and
                       same_vector(B.right(pose),B.right(rendered_pose))and
                       same_vector(B.up(pose),B.up(rendered_pose))then
                        exact,exact_count=unit,exact_count+1
                    end
                end
            end
            if exact_count~=1 then return false,'Rendered camera is not unique'end
            candidate=exact
        end
        local camera=U.camera(candidate,1)
        local p=C.local_position(camera,candidate)
        local x,y,z=xyz(p)
        generation=generation+1
        held={world=world,unit=candidate,camera=camera,original={x,y,z},anchor=numbers(rendered),generation=generation}
        return true
    end
    function self.identity()
        local camera,why=current();if not camera then return nil,why end
        return{world=held.world,unit=held.unit,camera=camera,generation=held.generation}
    end
    function self.position()
        local camera,why=current();if not camera then return nil,why end
        local x,y,z=xyz(C.local_position(camera,held.unit))
        return {x,y,z}
    end
    function self.frame()
        local camera,why=current();if not camera then return nil,why end
        local pose=C.world_pose(camera)
        return{position=numbers(C.world_position(camera)),forward=numbers(B.forward(pose)),
            right=numbers(B.right(pose)),up=numbers(B.up(pose)),fov=C.vertical_fov(camera)}
    end
    local function write_position(camera,position)
        assert(type(position)=='table' and finite(position[1]) and finite(position[2]) and finite(position[3]),'Invalid camera position')
        -- The parent Unit is mandatory in this game's camera write ABI.
        held.written={position[1],position[2],position[3]}
        local result=C.set_local_position(camera,held.unit,V(position[1],position[2],position[3]))
        if result==false then return false,'Camera position write refused' end
        held.scene_dirty=true
        return true
    end
    function self.write(position)
        local camera,why=current();if not camera then return false,why end
        local ok,problem=write_position(camera,position);if not ok then return false,problem end
        if W.update_unit(held.world,held.unit)==false then return false,'Camera scene update refused' end
        held.scene_dirty=false
        return true
    end
    local function rendered_matches(pose,view)
        local function close(v,n)
            local x,y,z=xyz(v)
            return (x-n[1])^2+(y-n[2])^2+(z-n[3])^2<1e-4
        end
        return close(B.translation(pose),view.position)and close(B.forward(pose),view.forward)and close(B.up(pose),view.up)
    end
    function self.write_view(position,forward,up,fov,verify_rendered)
        assert(finite(fov)and fov>0 and fov<math.pi,'Invalid camera field of view')
        direction(forward);direction(up)
        assert(math.abs(forward[1]*up[1]+forward[2]*up[2]+forward[3]*up[3])<.01,'Camera axes are not orthogonal')
        local camera,why=current();if not camera then return false,why end
        local world_pose=C.world_pose(camera)
        if verify_rendered and held.last_view then
            local rendered=W.debug_camera_pose(held.world)
            -- Publication can precede or follow gameplay's camera update. Both
            -- our last submitted view and this held component's current view
            -- identify the same camera; reject a view matching neither.
            if not rendered_matches(rendered,held.last_view)and not(
                near(B.translation(rendered),B.translation(world_pose))and
                near(B.forward(rendered),B.forward(world_pose))and near(B.up(rendered),B.up(world_pose)))then
                return false,'Rendered camera changed during the action shot'
            end
        end
        if not held.rotation_original then held.rotation_original=quaternion(C.local_rotation(camera,held.unit))end
        if not held.fov_original then held.fov_original=C.vertical_fov(camera)end
        local rotation=sr.Quaternion.look(V(unpack(forward)),V(unpack(up)))
        -- Engine matrices compose in row-vector order (qualified in the current
        -- runtime). Convert the requested world pose through the camera's fresh
        -- parent transform; never retain a native matrix across frames.
        local target=B.from_quaternion_position(rotation,V(unpack(position)))
        local local_target=B.multiply(B.multiply(target,B.inverse(world_pose)),C.local_pose(camera))
        local local_position=numbers(B.translation(local_target));local local_rotation=B.rotation(local_target)
        local ok,problem=write_position(camera,local_position);if not ok then return false,problem end
        held.rotation_written=quaternion(local_rotation)
        if C.set_local_rotation(camera,held.unit,local_rotation)==false then return false,'Camera rotation write refused' end
        held.fov_written=fov
        if C.set_vertical_fov(camera,fov)==false then return false,'Camera field of view write refused' end
        if W.update_unit(held.world,held.unit)==false then return false,'Camera scene update refused' end
        held.scene_dirty=false
        local view=held.last_view or{position={},forward={},up={}};held.last_view=view
        for i=1,3 do view.position[i]=position[i];view.forward[i]=forward[i];view.up[i]=up[i]end
        return true
    end
    function self.close()
        if not held then return true end
        local camera=current();if not camera then return true end
        local position=C.local_position(camera,held.unit)
        if held.written and near(position,V(unpack(held.written))) then
            local result=C.set_local_position(camera,held.unit,V(unpack(held.original)))
            if result==false then return false,'Camera position restoration refused' end
            held.scene_dirty=true
        end
        held.written=nil
        if held.rotation_written and same_rotation(quaternion(C.local_rotation(camera,held.unit)),held.rotation_written)then
            if C.set_local_rotation(camera,held.unit,sr.Quaternion.from_elements(unpack(held.rotation_original)))==false then return false,'Camera rotation restoration refused'end
            held.scene_dirty=true
        end
        held.rotation_written=nil
        if held.fov_written and C.vertical_fov(camera)==held.fov_written then
            if C.set_vertical_fov(camera,held.fov_original)==false then return false,'Camera field of view restoration refused'end
        end
        held.fov_written=nil
        if held.scene_dirty and W.update_unit(held.world,held.unit)==false then return false,'Camera scene restoration refused' end
        held=nil
        return true
    end
    function self.bookmark_context()
        local camera,why=current();if not camera then return nil,why end
        return{world=held.world,unit=held.unit,position={held.anchor[1],held.anchor[2],held.anchor[3]}}
    end
    function self.active()return held~=nil end
    function self.scene()
        local camera,why=current();if not camera then return nil,why end
        return held.world,held.generation
    end
    return self
end
return M

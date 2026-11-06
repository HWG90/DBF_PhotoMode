-- Explicit photographic-subject preview. Never a local-player resolver.
-- Uses the existing exact-matrix pose owner through Chef's guarded boundary.
local M={}
local ONE={Application={'main_world'},World={'units_by_resource','update_unit'},
    Unit={'alive','world','resource_name','num_scene_graph_items','animation_bone_mode','scene_graph_parent','has_node','node',
        'local_pose','set_local_pose','set_animation_bone_mode'},
    IdString64={'from_hex','equal'},Vector3={'x','y','z'},Quaternion={'from_elements'},Network={'game_session'},
    Matrix4x4={'from_elements','from_quaternion_position','set_scale','translation','rotation','scale','right','forward','up'}}
local VOID={['World.update_unit']=true,['Unit.set_local_pose']=true,['Unit.set_animation_bone_mode']=true,['Matrix4x4.set_scale']=true}
function M.engine(chef)
    local sr={}
    local function call(name,...)
        local a,b,c,d=chef.call(name,...)
        if a==nil and b~=nil then error(name..': '..tostring(b),0) end
        if VOID[name] then assert(a~=false,name..' refused');return end
        return a,b,c,d
    end
    for family,names in pairs(ONE) do
        local api={};sr[family]=api
        for _,name in ipairs(names) do
            local path=family..'.'..name
            if VOID[path] then api[name]=function(...) call(path,...);return end
            else api[name]=function(...) return (call(path,...)) end end
        end
    end
    sr.Quaternion.to_elements=function(...) return call('Quaternion.to_elements',...) end
    setmetatable(sr.Vector3,{__call=function(_,...) return (call('Vector3',...)) end})
    -- chef.call pads/truncates answers to four values. Read the exact four
    -- stored affine axes instead of truncating a twelve-value to_elements call.
    -- from_elements is verified against these twelve scalars by the pose owner.
    function sr.Matrix4x4.to_elements(matrix)
        local B,V=sr.Matrix4x4,sr.Vector3
        local r,f,u,p=B.right(matrix),B.forward(matrix),B.up(matrix),B.translation(matrix)
        return V.x(r),V.y(r),V.z(r),V.x(f),V.y(f),V.z(f),V.x(u),V.y(u),V.z(u),V.x(p),V.y(p),V.z(p)
    end
    return sr
end
function M.new(chef,load,simulation)
    local self={};local model,session,world,generation,mutating,cleanup
    local function guard()
        if chef.call('Window.has_focus')~=true or chef.call('Application.main_world')~=world or chef.world_id()~=generation then
            return false,'Subject world or focus changed'
        end
        local current=chef.call('Network.game_session')
        if type(current)~='userdata' or current~=session then return false,'Subject session changed' end
        local peers=chef.call('GameSession.peers',session)
        if type(peers)~='table' then return false,'Subject peer inventory unavailable' end
        local count=0;for _ in pairs(peers) do count=count+1;if count>1 then break end end
        return count==1,count~=1 and 'Subject edits require one visible peer' or nil
    end
    local function invoke(name,...)
        if not model then return false,'Enable subject preview first' end
        mutating,cleanup=true,name=='reset' or name=='close' or name=='recover'
        local called,ok,why=pcall(model[name],...)
        mutating,cleanup=false,false
        if not called then return false,tostring(ok) end
        return ok,why
    end
    function self.enable()
        if model then return true end
        world,generation,session=chef.world(),chef.world_id(),chef.call('Network.game_session')
        local ok,why=guard();if not ok then return false,why end
        local deps=load()
        local native,reason=deps.native.preview(M.engine(chef),{contract='unit-pose-preview-v1',session=session,
            trial_id='chef-explicit-subject',authorize=function()
                return mutating==true and (cleanup or simulation.frozen==true),'Freeze action and an explicit subject command are required'
            end})
        if not native then return false,reason end
        model=deps.model.new(native,deps.bank,function() return simulation.frozen==true end)
        return true
    end
    function self.refresh()
        local ok,why=self.enable();if not ok then return false,why end
        ok,why=guard();if not ok then return false,why end
        local refreshed,choices=invoke('refresh')
        return refreshed,refreshed and ('Found '..#choices..' photographic subjects; choose a slot explicitly') or choices
    end
    function self.select(index)
        if not model then return false,'Refresh photographic subjects first' end
        local choices=model.choices();local item=choices[index]
        if not item then return false,'Selected subject slot is empty' end
        local ok,why=guard();if not ok then return false,why end
        return invoke('select',item.id)
    end
    function self.apply(index)
        if not model or not model.catalog[index] then return false,'Selected pose slot is empty' end
        local ok,why=guard();if not ok then return false,why end
        local result,reason=invoke('apply',model.catalog[index].id)
        return result,reason or (result and model.catalog[index].label)
    end
    function self.reset() if not model then return true end;return invoke('reset') end
    function self.recover() if not model then return true end;return invoke('recover') end
    function self.close()
        if not model then return true end
        local ok,why=invoke('close')
        if ok then model=nil;world,generation,session=nil,nil,nil end
        return ok,why
    end
    function self.status() return model and model.status() or {state='disabled',pending=false} end
    function self.choices() return model and model.choices() or {} end
    return self
end
return M

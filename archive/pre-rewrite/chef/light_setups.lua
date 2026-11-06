-- Five namespaced numeric lighting saves. The chosen camera frame is the
-- anchor; no player identity or native handle is persisted.
local M={}
function M.new(chef,lights,light_factory,shots)
    local saved
    local function slot(n) return type(n)=='number' and n%1==0 and n>=1 and n<=5 end
    local function clean(list)
        if type(list)~='table' then return nil end
        local out={}
        for key,item in pairs(list) do
            if type(key)~='number' or key%1~=0 or key<1 or key>3 or type(item)~='table' or not shots.valid(item.frame) then return nil end
            local options=light_factory.options(item.options);if not options then return nil end
            local frame=shots.relative(item.frame,{position={0,0,0},right={1,0,0},forward={0,1,0},up={0,0,1},fov=1})
            out[key]={frame=frame,options=options}
        end
        return out
    end
    local function load()
        if saved then return true end
        local data,why=chef.load_table('lighting_setups_v1')
        if not data then
            if why~='none saved' then return false,why or 'Lighting preset read failed' end
            saved={version=1,slots={}};return true
        end
        if type(data)~='table' or data.version~=1 or type(data.slots)~='table' then return false,'Invalid lighting presets' end
        local checked={version=1,slots={}}
        for index,list in pairs(data.slots) do
            if not slot(index) then return false,'Invalid lighting preset slot' end
            checked.slots[index]=clean(list);if not checked.slots[index] then return false,'Invalid saved light setup' end
        end
        saved=checked;return true
    end
    local self={}
    function self.action(action,index,view)
        if not slot(index) or not shots.valid(view) then return false,'Open a camera and choose lighting setup 1-5' end
        local ok,why=load();if not ok then return false,why end
        if action=='recall' then
            local list=saved.slots[index];if not list then return false,'Lighting setup is empty' end
            local world={}
            for key,item in pairs(list) do world[key]={options=item.options,frame=shots.relative(item.frame,view)} end
            return lights.replace(world)
        end
        if action~='save' and action~='clear' then return false,'Unknown lighting setup action' end
        local data={version=1,slots={}}
        for i,list in pairs(saved.slots) do data.slots[i]=clean(list) end
        data.slots[index]=nil
        if action=='save' then
            local list,reason=lights.export();if not list then return false,reason end
            data.slots[index]={}
            for key,item in pairs(list) do data.slots[index][key]={options=item.options,frame=shots.relative(item.frame,view,true)} end
        end
        ok,why=chef.save_table('lighting_setups_v1',data)
        if not ok then return false,why or 'Lighting setup write failed' end
        saved=data;return true
    end
    function self.rig(kind,view,distance)
        if not shots.valid(view) or type(distance)~='number' or distance<.1 or distance>100 then return false,'Invalid lighting target' end
        local presets={
            {{-3,-2,3,5,2},{3,-1,1,2,3},{0,3,3,4,1}},
            {{-2,-2,2,4,2},{2,-2,1,2,1}},
            {{-4,0,2,7,2},{1,3,2,2,3}},
        }
        if not presets[kind] then return false,'Unknown lighting rig' end
        local target=shots.relative(view,{position={0,0,0},right={1,0,0},forward={0,1,0},up={0,0,1},fov=1})
        for i=1,3 do target.position[i]=view.position[i]+view.forward[i]*distance end
        local list={}
        for index,light in ipairs(presets[kind]) do
            list[index]={frame=target,options={right=light[1],forward=light[2],up=light[3],intensity=light[4],color=light[5]}}
        end
        return lights.replace(list)
    end
    return self
end
return M

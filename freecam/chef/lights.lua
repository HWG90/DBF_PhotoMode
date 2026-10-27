-- Three owned local lights. Static lights stay idle; opted-in following writes
-- only when the numeric camera frame changes. Chef also tracks the spawns.
local M={resource='e07f49224f0a5759',maximum=3}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e7 end
local COLORS={{255,255,255},{255,190,130},{135,190,255},{255,70,70},{80,255,130},{195,120,255}}
local AXES={'position','forward','right','up'}
local function copy(value)
    local out={};for k,v in pairs(value) do out[k]=type(v)=='table' and copy(v) or v end;return out
end
function M.options(value)
    if type(value)~='table' then return nil end
    if value.enabled~=nil and type(value.enabled)~='boolean' or value.follow~=nil and type(value.follow)~='boolean' then return nil end
    local o={intensity=value.intensity,color=value.color,right=value.right,forward=value.forward,up=value.up,
        kind=value.kind or 'omni',cone=value.cone or 45,range=value.range or 8,
        enabled=value.enabled~=false,follow=value.follow==true}
    if not finite(o.intensity) or o.intensity<0 or o.intensity>10000 or not COLORS[o.color] then return nil end
    for _,axis in ipairs({'right','forward','up'}) do if not finite(o[axis]) or math.abs(o[axis])>100 then return nil end end
    if (o.kind~='omni' and o.kind~='spot') or not finite(o.cone) or o.cone<1 or o.cone>175 or
        not finite(o.range) or o.range<.1 or o.range>1000 then return nil end
    if value.rgb~=nil then
        if type(value.rgb)~='table' then return nil end;o.rgb={}
        for i=1,3 do if not finite(value.rgb[i]) or value.rgb[i]<0 or value.rgb[i]>255 then return nil end;o.rgb[i]=value.rgb[i] end
    end
    return o
end
local function same_frame(a,b)
    for _,axis in ipairs(AXES) do for i=1,3 do if math.abs(a[axis][i]-b[axis][i])>1e-6 then return false end end end;return true
end
function M.new(chef,valid_view)
    local self={revision=0};local records={};local markers,marker_revision={},-1
    local function call(name,...)
        local a,b=chef.call(name,...)
        if a==nil and b~=nil then error(name..': '..tostring(b),0) end
        if a==false and name~='Unit.alive' then error(name..' refused',0) end
        return a
    end
    local function world()
        local w=call('Application.main_world')
        assert(w~=nil and w==chef.world(),'Photo light world unavailable');return w
    end
    local function alive(unit)
        local value=call('Unit.alive',unit)
        assert(type(value)=='boolean','Photo light lifetime unavailable');return value
    end
    local function remove(index)
        local record=records[index];if not record then return true end
        local w=call('Application.main_world')
        assert(w~=nil,'Photo light world unavailable')
        if w~=record.world then
            -- The loader discards its retired-world spawn ledger. Do not call
            -- even despawn here: its cached world may not have settled yet.
            records[index]=nil;self.revision=self.revision+1;return true
        end
        assert(w==chef.world(),'Photo light world is changing')
        if alive(record.unit) then
            -- Keep Chef's spawn ledger until destruction is confirmed.
            -- chef.despawn alone removes it before checking destroy's result.
            call('World.destroy_unit',w,record.unit)
            if alive(record.unit) then return false,'Photo light destruction remains pending' end
        end
        chef.despawn(record.unit)
        records[index]=nil;self.revision=self.revision+1;return true
    end
    function self.remove(index)
        local called,ok,why=pcall(remove,index)
        if not called then return false,ok end
        return ok,why
    end
    function self.clear()
        local result,reason=true,nil
        for index=1,M.maximum do
            local ok,why=self.remove(index)
            if not ok then result,reason=false,why end
        end
        return result,reason
    end
    function self.count()
        local count=0;for index=1,M.maximum do if records[index] then count=count+1 end end;return count
    end
    local function apply(index,options,view)
        assert(type(index)=='number' and index%1==0 and index>=1 and index<=M.maximum,'Choose light 1-3')
        assert(valid_view(view),'Photo camera frame unavailable')
        options=assert(M.options(options),'Invalid photo light settings')
        local w=world();local p={}
        for i=1,3 do p[i]=view.position[i]+view.right[i]*options.right+view.forward[i]*options.forward+view.up[i]*options.up end
        local record=records[index]
        if record and record.world~=w then records[index]=nil;record=nil;self.revision=self.revision+1 end
        if record and not alive(record.unit) then chef.despawn(record.unit);records[index]=nil;record=nil;self.revision=self.revision+1 end
        if not record then
            assert(chef.has('spawn') and type(chef.lights)=='function' and type(chef.light)=='function','Chef photo light helpers unavailable')
            local unit,why=chef.spawn(M.resource,p[1],p[2],p[3])
            assert(unit,why or 'Photo light resource unavailable')
            record={unit=unit,world=w};records[index]=record
            assert(chef.lights(unit)==1,'Photo light must have exactly one light')
        end
        local light=chef.light(record.unit,1)
        assert(type(light)=='table','Photo light component unavailable')
        -- Helpers reacquire the component at each call; no Light/Vector handles
        -- survive this action. Commit cached fields only after all calls pass.
        local previous=record.values
        local rgb=options.rgb or COLORS[options.color]
        local old_rgb=previous and (previous.rgb or COLORS[previous.color])
        local color_changed=not old_rgb or rgb[1]~=old_rgb[1] or rgb[2]~=old_rgb[2] or rgb[3]~=old_rgb[3]
        local changed=not previous or color_changed or previous.intensity~=options.intensity
        if not previous then assert(light.set_shadows(false),'Photo light shadow write refused') end
        if color_changed then
            assert(light.set_color(rgb[1],rgb[2],rgb[3]),'Photo light color write refused')
        end
        if not previous or previous.intensity~=options.intensity then assert(light.set_intensity(options.intensity),'Photo light intensity write refused') end
        if not previous or previous.enabled~=options.enabled then assert(light.set_enabled(options.enabled),'Photo light enable refused');changed=true end
        local kind_changed=(previous and previous.kind or 'omni')~=options.kind
        local cone_changed=options.kind=='spot' and (not previous or previous.cone~=options.cone or kind_changed)
        local range_changed=(previous and previous.range or 8)~=options.range
        if kind_changed or cone_changed or range_changed then
            local component=call('Unit.light',record.unit,1);assert(component,'Photo light component unavailable')
            assert(call('Light.node',component)==1,'Only the bundled root light may be edited')
            if kind_changed then call('Light.set_type',component,options.kind) end
            if cone_changed then call('Light.set_spot_angle_end',component,math.rad(options.cone)) end
            if range_changed then
                local before=call('Light.falloff_end',component)
                assert(finite(before) and before>0,'Native light range getter unavailable; keep 8 m')
                assert(light.set_falloff(0,options.range),'Photo light range write refused')
                local after=call('Light.falloff_end',component)
                assert(finite(after) and math.abs(after-options.range)<.001,'Native light range readback failed')
            end
            changed=true
        end
        if options.kind=='spot' and (not previous or previous.kind~='spot' or not same_frame(record.anchor,view)) then
            local forward=call('Vector3',unpack(view.forward));local up=call('Vector3',unpack(view.up))
            local rotation=call('Quaternion.look',forward,up);assert(rotation,'Photo light rotation unavailable')
            call('Unit.set_local_rotation',record.unit,1,rotation);changed=true
        end
        if previous and (p[1]~=record.position[1] or p[2]~=record.position[2] or p[3]~=record.position[3]) then
            local vector=call('Vector3',p[1],p[2],p[3]);assert(vector,'Photo light position unavailable')
            call('Unit.set_local_position',record.unit,1,vector)
            changed=true
        end
        if changed then call('World.update_unit',w,record.unit) end
        record.position=p;record.values=options;record.anchor=copy(view)
        self.revision=self.revision+1
        return true
    end
    function self.apply(index,options,view)
        local called,ok=pcall(apply,index,options,view)
        if called then return ok end
        -- A partially initialized light remains ours until confirmed destroyed.
        local cleaned,why=self.remove(index)
        return false,tostring(ok)..(cleaned and '' or '; cleanup pending: '..tostring(why))
    end
    function self.following()
        for i=1,M.maximum do if records[i] and records[i].values and records[i].values.follow then return true end end
        return false
    end
    function self.tick(view)
        for index=1,M.maximum do local record=records[index]
            if record and record.values and record.values.follow and not same_frame(record.anchor,view) then
                local ok,why=self.apply(index,record.values,view);if not ok then return false,why end
            end
        end
        return true
    end
    function self.export()
        local list={}
        for index=1,M.maximum do local record=records[index]
            if record then
                if not record.values then return nil,'Recover unfinished light changes first' end
                list[index]={options=copy(record.values),frame=copy(record.anchor)}
            end
        end
        return list
    end
    function self.replace(list)
        if type(list)~='table' then return false,'Invalid lighting setup' end
        for key,item in pairs(list) do
            if type(key)~='number' or key%1~=0 or key<1 or key>M.maximum or type(item)~='table' or
                not M.options(item.options) or not valid_view(item.frame) then return false,'Invalid saved light' end
        end
        local previous,why=self.export();if not previous then return false,why end
        local ok,reason=self.clear();if not ok then return false,reason end
        for index=1,M.maximum do if list[index] then
            ok,reason=self.apply(index,list[index].options,list[index].frame)
            if not ok then
                local cleaned,problem=self.clear()
                if not cleaned then return false,tostring(reason)..'; cleanup pending: '..tostring(problem) end
                for slot=1,M.maximum do if previous[slot] then
                    local restored,error=self.apply(slot,previous[slot].options,previous[slot].frame)
                    if not restored then return false,tostring(reason)..'; previous light recovery failed: '..tostring(error) end
                end end
                return false,reason
            end
        end end
        return true
    end
    function self.markers()
        if marker_revision~=self.revision then
            markers={};for index=1,M.maximum do if records[index] and records[index].values then
                markers[#markers+1]={slot=index,position=records[index].position}
            end end;marker_revision=self.revision
        end
        return markers
    end
    function self.move(index,position)
        local record=records[index]
        if not record or not record.values then return false,'Choose an existing photo light' end
        if type(position)~='table' then return false,'Invalid light position' end
        for i=1,3 do if not finite(position[i]) then return false,'Invalid light position' end end
        local options=copy(record.values);options.follow=false
        local frame=copy(record.anchor)
        for i=1,3 do frame.position[i]=position[i]-frame.right[i]*options.right-frame.forward[i]*options.forward-frame.up[i]*options.up end
        return self.apply(index,options,frame)
    end
    function self.aim(index,target)
        local record=records[index];if not record or not record.values then return false,'Choose an existing photo light' end
        local frame=copy(record.anchor);local direction={};local norm=0
        for i=1,3 do
            if type(target)~='table' or not finite(target[i]) then return false,'Invalid light target' end
            direction[i]=target[i]-record.position[i];norm=norm+direction[i]^2
        end
        if norm<.0001 then return false,'Light and target are too close' end
        norm=math.sqrt(norm);for i=1,3 do direction[i]=direction[i]/norm end
        local up=math.abs(direction[3])>.98 and {0,1,0} or {0,0,1}
        local right={direction[2]*up[3]-direction[3]*up[2],direction[3]*up[1]-direction[1]*up[3],direction[1]*up[2]-direction[2]*up[1]}
        norm=math.sqrt(right[1]^2+right[2]^2+right[3]^2);for i=1,3 do right[i]=right[i]/norm end
        frame.position=copy(record.position);frame.forward=direction;frame.right=right
        frame.up={right[2]*direction[3]-right[3]*direction[2],right[3]*direction[1]-right[1]*direction[3],right[1]*direction[2]-right[2]*direction[1]}
        local options=copy(record.values);options.kind='spot';options.right,options.forward,options.up=0,0,0;options.follow=false
        return self.apply(index,options,frame)
    end
    return self
end
return M

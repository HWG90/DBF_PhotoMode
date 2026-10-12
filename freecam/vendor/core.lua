-- Public, renderer-independent registration and persistence API.
local M={}
local function id(s) assert(type(s)=='string' and #s<=80 and s:match('^[%w_-]+$'),'Invalid stable ID');return s end
local function plain(s) assert(type(s)=='string' and #s<=512 and not s:find('[%c]'),'Invalid display text');return s end
local function rich(s)
    if type(s)=='table' then local blocks={};for _,block in ipairs(s)do assert(type(block)=='string','Text blocks must be strings');blocks[#blocks+1]=block end;s=table.concat(blocks,'\n\n')end
    assert(type(s)=='string' and #s<=65536 and not s:find('[%z\1-\8\11\12\14-\31]'),'Invalid rich text');return s
end
local function copy(t) local r={};for k,v in pairs(t)do r[k]=v end;return r end
function M.color_hex(v)
    if type(v)=='string' then local hex=v:gsub('^#','');assert(#hex==6 and hex:match('^%x+$'),'Use six HEX digits');return '#'..hex:upper()end
    assert(type(v)=='table','Expected HEX or RGB table');local parts={v.r or v[1],v.g or v[2],v.b or v[3]}
    for _,n in ipairs(parts)do assert(type(n)=='number' and n%1==0 and n>=0 and n<=255,'RGB channels must be integers 0-255')end
    assert(#parts==3,'Three RGB channels required');return string.format('#%02X%02X%02X',parts[1],parts[2],parts[3])
end
function M.color_rgb(v)local hex=M.color_hex(v);return {tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)}end
function M.hsv_rgb(h,s,v)
 local sector=math.floor(h*6)%6;local f=h*6-math.floor(h*6);local low=v*(1-s);local q=v*(1-f*s);local t=v*(1-(1-f)*s)
 local colors={{v,t,low},{q,v,low},{low,v,t},{low,q,v},{t,low,v},{v,low,q}};local c=colors[sector+1]
 return {math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5)}
end
function M.rgb_hsv(rgb)
 local r,g,b=rgb[1]/255,rgb[2]/255,rgb[3]/255;local hi,lo=math.max(r,g,b),math.min(r,g,b);local delta=hi-lo;local h=0
 if delta>0 then if hi==r then h=((g-b)/delta)%6 elseif hi==g then h=(b-r)/delta+2 else h=(r-g)/delta+4 end;h=h/6 end
 return h,hi==0 and 0 or delta/hi,hi
end
local function normalize(c,v)
    if c.type=='input' then assert(type(v)=='string' and #v<=48 and v:match('^[%w _-]+$'),'Use letters, numbers, spaces, underscores or hyphens');return v end
    if c.type=='color' then return M.color_hex(v)end
    if c.type=='toggle' then assert(type(v)=='boolean','Expected boolean');return v end
    assert(type(v)=='number' and v==v and math.abs(v)<1e12,'Expected finite number')
    if c.type=='slider' then
        assert(v>=c.min and v<=c.max,'Value outside slider range')
        local step=c.fine_step or c.step
        return math.min(c.max,c.min+math.floor((v-c.min)/step+.5)*step)
    end
    if c.type=='choice' then assert(v%1==0 and v>=1 and v<=#c.choices,'Invalid choice');return v end
    if c.type=='keybind' then assert(v%1==0 and v>=0 and v<=255,'Invalid virtual key');return v end
    error('Control has no stored value')
end
local function stored(c)return c.type=='input' or c.type=='toggle' or c.type=='slider' or c.type=='choice' or c.type=='keybind' or c.type=='color'end
function M.new(store,log,grouping,options)
    local api={api=1,version='0.1.58',color_hex=M.color_hex,color_rgb=M.color_rgb,hsv_rgb=M.hsv_rgb,rgb_hsv=M.rgb_hsv,mods={},revision=0};log=log or function()end
    options=options or {};local verbose_override
    local function safe_id(value)return type(value)=='string'and #value<=80 and value:match('^[%w_-]+$')~=nil end
    local function owned_log(owner,message,level)
        if safe_id(owner)and type(options.mod_log)=='function'then
            local ok,result=pcall(options.mod_log,owner,message,level or 'error')
            if ok and result~=false then return end
        end
        -- Logging must not interrupt persistence, callbacks or a registration error.
        pcall(log,message)
    end
    function api.get_verbose()
        if verbose_override~=nil then return verbose_override end
        if type(options.verbose)=='function'then local ok,value=pcall(options.verbose);return ok and value==true end
        return options.verbose==true
    end
    function api.set_verbose(value)assert(type(value)=='boolean','Verbose flag must be boolean');verbose_override=value;return value end
    api.storage_per_mod=true;api.presentation_links=true;api.text_swatches=true;api.category_page_links=true
    local palette=store and store.load('mcm_custom_palette') or {};local swatches={}
    for i=1,12 do local ok,v=pcall(M.color_hex,palette['swatch_'..i]);if ok then swatches[#swatches+1]=v end end
    function api.swatches()return copy(swatches)end
    function api.save_swatch(value)
        value=M.color_hex(value);for _,existing in ipairs(swatches)do if existing==value then return true end end
        local next_colors=copy(swatches);if #next_colors==12 then table.remove(next_colors,1)end;next_colors[#next_colors+1]=value
        local values={};for i,v in ipairs(next_colors)do values['swatch_'..i]=v end
        if store then local ok,err=store.save('mcm_custom_palette',values);if not ok then return false,err end end
        swatches=next_colors;return true
    end
    function api.replace_swatch(index,value)
        assert(type(index)=='number' and index%1==0 and swatches[index],'Unknown swatch')
        value=M.color_hex(value);local next_colors=copy(swatches);next_colors[index]=value
        local values={};for i,v in ipairs(next_colors)do values['swatch_'..i]=v end
        if store then local ok,err=store.save('mcm_custom_palette',values);if not ok then return false,err end end
        swatches=next_colors;return true
    end
    local function register(spec)
        assert(type(spec)=='table','Expected mod definition');id(spec.id);plain(spec.name);if spec.parent_name then plain(spec.parent_name)end
        local store=spec.storage or store
        assert(not store or(type(store.load)=='function'and type(store.save)=='function'),'Invalid mod storage provider')
        assert(not api.mods[spec.id],'Mod already registered; unregister before replacing')
        local mod={id=spec.id,name=spec.name,parent_name=spec.parent_name,description=rich(spec.description or ''),pages={},categories={},controls={},values={},on_change=spec.on_change}
        local categories={}
        for _,category in ipairs(spec.categories or {})do
            id(category.id);assert(not categories[category.id],'Duplicate category')
            assert(category.style==nil or category.style=='author' or category.style=='page','Invalid category style');assert(category.collapsed==nil or type(category.collapsed)=='boolean','Category collapsed must be boolean')
            local c={id=category.id,name=plain(category.name),parent=category.parent,style=category.style,collapsed=category.collapsed};if c.parent then id(c.parent)end
            categories[c.id]=c;mod.categories[#mod.categories+1]=c
        end
        for _,c in ipairs(mod.categories)do
            local seen={[c.id]=true};local parent=c.parent
            while parent do assert(categories[parent],'Unknown parent category');assert(not seen[parent],'Category cycle');seen[parent]=true;parent=categories[parent].parent end
        end
        assert(type(spec.pages)=='table' and #spec.pages>0,'At least one page required')
        local saved=store and store.load(mod.id) or {};local pages={}
        for _,definition in ipairs(spec.pages)do
            id(definition.id);assert(not pages[definition.id],'Duplicate page');pages[definition.id]=true
            assert(definition.require_confirmation==nil or type(definition.require_confirmation)=='boolean','require_confirmation must be boolean')
            assert(definition.style==nil or definition.style=='author','Invalid section style')
            assert(definition.category==nil or categories[definition.category],'Unknown page category')
            local page={style=definition.style,category=definition.category,id=definition.id,name=plain(definition.name),render_preview=definition.render_preview,preview_popout=definition.preview_popout==true,controls={},require_confirmation=definition.dynamic~=true and definition.require_confirmation~=false,pending={},actions={}}
            local flattened,group_ids={},{}
            local function flatten(items,parents,depth)
                assert(depth<=8,'Section nesting exceeds eight levels')
                for _,item in ipairs(items)do
                    local c=copy(item);c.groups=copy(parents);c.depth=depth;c.children=nil
                    if item.children~=nil then
                        assert(item.type=='section' and type(item.children)=='table','Only sections accept children')
                        id(item.id);assert(not group_ids[item.id],'Duplicate section ID');group_ids[item.id]=true
                        assert(item.collapsed==nil or type(item.collapsed)=='boolean','collapsed must be boolean')
                        c.collapsible=true
                    end
                    flattened[#flattened+1]=c
                    if c.collapsible then local ancestry=copy(parents);ancestry[#ancestry+1]=c.id;flatten(item.children,ancestry,depth+1)end
                end
            end
            flatten(definition.controls or {},{},0)
            for _,definition_control in ipairs(flattened)do
                local c=copy(definition_control);c.page=page;if c.type=='text' then c.label=rich(c.label or '')else plain(c.label or '')end;c.description=rich(c.description or '')
                assert(c.text_role==nil or c.text_role=='body' or c.text_role=='title' or c.text_role=='selection','Invalid text role')
                assert(({input=true,color=true,toggle=true,slider=true,choice=true,keybind=true,button=true,text=true,section=true})[c.type],'Unsupported control')
                assert(c.column==nil or c.column==1 or c.column==2,'Column must be 1 or 2')
                if c.type~='text' and c.type~='section' then
                    id(c.id);assert(not mod.controls[c.id],'Duplicate control ID');mod.controls[c.id]=c
                end
                if c.type=='slider' then
                    assert(type(c.min)=='number' and type(c.max)=='number' and type(c.step)=='number' and
                        c.min==c.min and c.max==c.max and c.step==c.step and math.abs(c.min)<1e12 and
                        math.abs(c.max)<1e12 and c.max>c.min and c.step>0 and c.step<=c.max-c.min,'Invalid slider')
                    assert(c.commit_on_blur==nil or type(c.commit_on_blur)=='boolean','commit_on_blur must be boolean')
                    assert(c.fine_step==nil or(type(c.fine_step)=='number'and c.fine_step==c.fine_step and c.fine_step>0 and c.fine_step<=c.step),'Invalid fine slider step')
                elseif c.type=='choice' then
                    assert(c.presentation==nil or c.presentation=='dropdown' or c.presentation=='selector' or c.presentation=='combined','Invalid choice presentation')
                    assert(type(c.choices)=='table' and #c.choices>0,'Choices required')
                    c.choices=copy(c.choices);for _,label in ipairs(c.choices)do plain(label)end
                elseif c.type=='button' then assert(type(c.on_activate)=='function','Button callback required');assert(c.require_confirmation==nil or type(c.require_confirmation)=='boolean','Action require_confirmation must be boolean') end
                if stored(c)then
                    c.default=normalize(c,c.default)
                    local ok,value=pcall(normalize,c,saved[c.id]);if ok then mod.values[c.id]=value else mod.values[c.id]=c.default end
                end
                page.controls[#page.controls+1]=c
            end
            mod.pages[#mod.pages+1]=page
        end
        api.mods[mod.id]=mod;api.revision=api.revision+1
        local handle={id=mod.id}
        local function validate(c,value)
            if not c.validate then return end
            local ok,result=pcall(c.validate,value)
            if not ok then owned_log(mod.id,'Validation callback failed for '..mod.id..'.'..c.id..': '..tostring(result),'error');error(result,0)end
            assert(result~=false,'Value rejected by mod')
        end
        function handle.get(key)assert(mod.controls[key],'Unknown control');return mod.values[key]end
        function handle.set(key,value)
            assert(api.mods[mod.id]==mod,'Retired registration')
            local c=assert(mod.controls[key],'Unknown control');assert(stored(c),'Control is not a setting')
            assert(not c.disabled,'Control disabled');value=normalize(c,value)
            validate(c,value)
            if value==mod.values[key]then return true end
            local next_values=copy(mod.values);next_values[key]=value
            if store then local ok,err=store.save(mod.id,next_values);if not ok then owned_log(mod.id,'Save failed for '..mod.id..'.'..key..': '..tostring(err),'error');return false,err end end
            local old=mod.values[key];mod.values=next_values
            for _,callback in ipairs({c.on_change or false,mod.on_change or false})do
                if callback then local ok,err=pcall(callback,value,key,old);if not ok then owned_log(mod.id,'Callback failed for '..mod.id..'.'..key..': '..tostring(err),'error')end end
            end
            api.revision=api.revision+1;log('Setting committed: '..mod.id..'.'..key);return true
        end
        function handle.preview(key)
            local c=assert(mod.controls[key],'Unknown control');local pending=c.page.pending
            if pending[key]~=nil then return pending[key]end;return handle.get(key)
        end
        function handle.edit(key,value)
            assert(api.mods[mod.id]==mod,'Retired registration')
            local c=assert(mod.controls[key],'Unknown control')
            if c.require_confirmation==false or not c.page.require_confirmation then return handle.set(key,value)end
            assert(stored(c) and not c.disabled,'Setting unavailable');value=normalize(c,value)
            validate(c,value)
            if value==handle.get(key)then c.page.pending[key]=nil else c.page.pending[key]=value end
            return true
        end
        local function page_by_id(page_id)
            assert(api.mods[mod.id]==mod,'Retired registration')
            for _,p in ipairs(mod.pages)do if p.id==page_id then return p end end;error('Unknown page')
        end
        function handle.queue(key)
            assert(api.mods[mod.id]==mod,'Retired registration')
            local c=assert(mod.controls[key],'Unknown control');assert(c.type=='button' and not c.disabled,'Button unavailable')
            if c.require_confirmation~=true then return handle.activate(key)end
            c.page.actions[key]=true;return true
        end
        function handle.discard(page_id)local p=page_by_id(page_id);p.pending={};p.actions={};return true end
        function handle.confirm(page_id)
            local p=page_by_id(page_id);local next_values=copy(mod.values);local changes={}
            for _,c in ipairs(p.controls)do local v=p.pending[c.id]
                if v~=nil then assert(not c.disabled,'Setting disabled');v=normalize(c,v)
                    validate(c,v)
                    if v~=mod.values[c.id] then next_values[c.id]=v;changes[#changes+1]={c=c,v=v,old=mod.values[c.id]}end
                end
                if p.actions[c.id] then assert(not c.disabled,'Action disabled')end
            end
            if #changes>0 and store then local ok,err=store.save(mod.id,next_values);if not ok then owned_log(mod.id,'Save failed for '..mod.id..'/'..p.id..': '..tostring(err),'error');return false,err end end
            mod.values=next_values;p.pending={}
            for _,change in ipairs(changes)do
                for _,callback in ipairs({change.c.on_change or false,mod.on_change or false})do
                    if callback then local ok,err=pcall(callback,change.v,change.c.id,change.old);if not ok then owned_log(mod.id,'Callback failed for '..mod.id..'.'..change.c.id..': '..tostring(err),'error')end end
                end
            end
            local actions=p.actions;p.actions={};api.revision=api.revision+1
            if #changes>0 then log('Page committed: '..mod.id..'/'..p.id..' ('..#changes..' settings)')end
            local messages={}
            for _,c in ipairs(p.controls)do if actions[c.id]then local ok,result=handle.activate(c.id);if not ok then return false,result end;if type(result)=='string' and #result>0 then messages[#messages+1]=result end end end
            return true,#messages>0 and table.concat(messages,'; ') or nil
        end
        -- Validate and persist a complete import before publishing any values or callbacks.
        function handle.set_many(values)
            assert(api.mods[mod.id]==mod,'Retired registration')
            assert(type(values)=='table','Settings table required')
            local next_values=copy(mod.values);local changes={};local keys={}
            for key in pairs(values)do keys[#keys+1]=key end;table.sort(keys)
            for _,key in ipairs(keys)do
                local c=assert(mod.controls[key],'Unknown control');assert(stored(c) and not c.disabled,'Setting unavailable')
                local value=normalize(c,values[key]);validate(c,value)
                if value~=mod.values[key]then next_values[key]=value;changes[#changes+1]={c=c,key=key,v=value,old=mod.values[key]}end
            end
            if #changes==0 then return true end
            if store then local ok,err=store.save(mod.id,next_values);if not ok then owned_log(mod.id,'Save failed for '..mod.id..' batch: '..tostring(err),'error');return false,err end end
            mod.values=next_values
            for _,change in ipairs(changes)do
                for _,callback in ipairs({change.c.on_change or false,mod.on_change or false})do
                    if callback then local ok,err=pcall(callback,change.v,change.key,change.old);if not ok then owned_log(mod.id,'Callback failed for '..mod.id..'.'..change.key..': '..tostring(err),'error')end end
                end
            end
            api.revision=api.revision+1;log('Settings batch committed: '..mod.id..' ('..#changes..' settings)');return true
        end
        function handle.reset(key)return handle.set(key,assert(mod.controls[key],'Unknown control').default)end
        function handle.activate(key)
            assert(api.mods[mod.id]==mod,'Retired registration')
            local c=assert(mod.controls[key],'Unknown control');assert(c.type=='button' and not c.disabled,'Button unavailable')
            local ok,result=pcall(c.on_activate)
            if ok then log('Action completed: '..mod.id..'.'..key)else owned_log(mod.id,'Action failed: '..mod.id..'.'..key..': '..tostring(result),'error')end
            return ok,result
        end
        function handle.unregister()if api.mods[mod.id]==mod then api.mods[mod.id]=nil;api.revision=api.revision+1 end end
        mod.handle=handle;return handle
    end
    function api.register(spec)
        local ok,result=pcall(register,spec)
        if not ok then
            local owner=type(spec)=='table'and rawget(spec,'id')or nil
            owned_log(safe_id(owner)and owner or nil,'Registration failed: '..tostring(result),'error')
            error(result,0)
        end
        if api.get_verbose()then
            local mod=api.mods[result.id];local controls=0;for _,page in ipairs(mod.pages)do controls=controls+#page.controls end
            owned_log(mod.id,'Registered mod: '..mod.id..' ('..#mod.pages..' pages, '..#mod.categories..' categories, '..controls..' controls)','debug')
        end
        return result
    end
    function api.mount(mod_id,parent_name)
        local mod=api.mods[mod_id];if not mod then return false end;plain(parent_name)
        if mod.parent_name~=parent_name then mod.parent_name=parent_name;api.revision=api.revision+1 end
        return true
    end
    function api.list()
        local list={};for _,mod in pairs(api.mods)do if not mod.hidden then list[#list+1]=mod end end
        table.sort(list,function(a,b)if a.name==b.name then return a.id<b.id end;return a.name<b.name end)
        return grouping and grouping.list(list) or list
    end
    function api.get(mod,key)local m=assert(api.mods[mod],'Unknown mod');return m.handle.get(key)end
    function api.set(mod,key,value)local m=assert(api.mods[mod],'Unknown mod');return m.handle.set(key,value)end
    return api
end
return M

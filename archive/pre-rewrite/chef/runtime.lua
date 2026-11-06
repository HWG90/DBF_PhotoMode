-- Chef-native controls, composition and solo time policy. Gameplay input is
-- never intercepted. Native writes are owned and unchanged state stays idle.
local M = {}
local OWNER = 'dbf.war_journalist.camera_owner'
local LIGHT_COLORS={{255,255,255},{255,190,130},{135,190,255},{255,70,70},{80,255,130},{195,120,255}}
local function finite(x) return type(x) == 'number' and x == x and math.abs(x) < 1e8 end

function M.new(chef, deps)
    assert(type(chef) == 'table' and type(chef.api) == 'number' and chef.api >= 3,
        'War Journalist needs Chef Shared Loader API 3')
    for _, capability in ipairs({'menu', 'events', 'share'}) do
        assert(chef.has(capability), 'Chef capability unavailable: ' .. capability)
    end
    local self = {version = '0.6.0', capabilities = {
        composition = true, camera_adjustment = true, free_mouse_camera = false,
        input_capture = false, screenshot = false, simulation = true, subject = false,
        lighting = false, scene_effects = false, numeric_dof = false,
    }}
    local token = {owner = chef.name, version = self.version}
    -- Chef 1.4.0 services are optional: each is used only when this loader has it.
    local features = deps.loader_features and deps.loader_features.probe(chef) or {}
    local capture
    self.capabilities.mouse_hold = features.mouse_hold == true
    self.capabilities.players_event = features.players_event == true
    local camera = deps.camera.new(chef, deps.portable_camera)
    local simulation = deps.simulation.new(chef, features)
    local shots=deps.shots and deps.shots.new(chef,deps.path)
    local bloom=deps.bloom and deps.bloom.new(chef)
    local dof=deps.bloom and deps.bloom.new(chef,'dof_enabled')
    local lights=deps.lights and deps.lights.new(chef,deps.shots.valid)
    local light_setups=lights and deps.light_setups and deps.light_setups.new(chef,lights,deps.lights,deps.shots)
    local subject=deps.subject and deps.subject.new(chef,deps.load_subject,simulation)
    local light_drag=lights and deps.light_drag and deps.light_drag.new(chef,lights)
    local light_memory=lights and deps.light_memory and deps.light_memory.new(chef,lights)
    self.capabilities.paths=shots~=nil;self.capabilities.camera_presets=shots~=nil;self.capabilities.bloom=bloom~=nil
    self.capabilities.lighting=lights~=nil
    self.capabilities.cinema=true;self.capabilities.native_dof_switch=dof~=nil
    self.capabilities.subject_preview=subject~=nil
    if deps.logos then for index,art in pairs(deps.logos) do deps.composition.logo_art[index]=art end end
    local controls,controls_reason = deps.controls.new(chef,deps.bindings,features)
    self.capabilities.free_mouse_camera = controls ~= nil
    self.capabilities.keyboard_freecam = controls ~= nil
    local values, subscriptions, option_specs = {}, {}, {}
    local state, motion, dirty, stopped = 'closed', nil, false, false
    local time_dirty, last_time_reason = false, nil
    local actions={};local apply_view=false;local bloom_dirty=false;local last_bloom_reason
    local dof_dirty,last_dof_reason=false,nil
    local shot,begin_shot,end_shot,end_camera
    local geometry, width, height
    local geometry_dirty = true
    local grain_geometry,grain_phase,grain_fault
    local changing = false
    local function log(message) chef.log('%s', 'WJ: ' .. tostring(message)) end
    local function set(id, value)
        local spec=option_specs[id]
        if spec and spec.type=='slider' and finite(value) then
            value=math.max(spec.min,math.min(spec.max,value))
            if spec.step and spec.step>0 then value=spec.min+math.floor((value-spec.min)/spec.step+.5)*spec.step end
            value=math.max(spec.min,math.min(spec.max,value))
        end
        changing = true
        local result, why = chef.set(id, value)
        changing = false
        if result ~= value then error('Chef option ' .. id .. ': ' .. tostring(why or 'value refused'), 0) end
        values[id] = value
    end
    local function release_owner()
        if chef.shared(OWNER) == token then chef.share(OWNER, nil) end
    end
    local function owns() return chef.shared(OWNER) == token end
    local close, update, render
    local function hooks()
        self.update = not stopped and (state == 'opening' or state == 'active' or time_dirty or simulation.owned
            or values.global_shortcuts and controls or #actions>0 or bloom_dirty or bloom and bloom.waiting()
            or dof_dirty or dof and dof.waiting() or capture and capture.pending()) and update or nil
        self.render = not stopped and (values.overlay or state=='active' and
            not values.capture_view and (values.show_legend or values.light_markers or values.light_swatch)) and render or nil
    end
    close = function(remember)
        actions={};apply_view=false
        shot=nil
        if light_memory then
            if remember==false or not values.remember_lights then light_memory.forget()
            elseif remember and state=='active' then
                local called,ok,why=pcall(light_memory.capture)
                if not called or not ok then log('Light reopen memory: '..tostring(called and why or ok)) end
            end
        end
        if values.capture_view then set('capture_view',false);geometry_dirty=true end
        if light_drag then light_drag.reset() end
        if shots then shots.reset() end
        local called, ok, why = pcall(camera.close)
        local lights_ok,lights_reason=true,nil
        if lights then lights_ok,lights_reason=lights.clear() end
        local subject_ok,subject_reason=true,nil
        if subject then subject_ok,subject_reason=subject.close();set('subject_preview',false) end
        motion, dirty = nil, false
        if controls then controls.reset() end
        set('camera', false)
        if not called or not ok or not lights_ok or not subject_ok then
            state = 'cleanup_pending'
            log('Photo cleanup pending: ' .. tostring(not subject_ok and subject_reason or not lights_ok and lights_reason or (called and why or ok)))
            hooks()
            return false
        end
        release_owner(); state = 'closed'; hooks(); return true
    end
    local function notify(message)
        log(message)
        if type(chef.notify)=='function' then chef.notify(message,3,255,230,90) end
    end
    capture = features.capture and deps.loader_features.capture_queue(chef, features, notify) or nil
    local function run_action(item)
        if capture and item.name=='capture_dds' then return capture.request() end
        if item.name=='camera_cleanup' then
            local closed=close();local ok,why=simulation.release(true)
            set('freeze',simulation.frozen);set('slow_motion',simulation.slow)
            return closed and ok,why or (not closed and 'Photo cleanup remains pending')
        end
        if subject and item.name=='subject_recover' then return subject.recover() end
        if subject and item.name=='subject_reset' then return subject.reset() end
        if subject and item.name=='subject_disable' then return subject.close() end
        if lights and item.name=='light_remove' then
            if light_memory then light_memory.forget(item.light_slot) end;return lights.remove(item.light_slot)
        end
        if lights and item.name=='light_clear' then
            if light_memory then light_memory.forget() end;return lights.clear()
        end
        if state~='active' or not motion or not shots then return false,'Open a photo camera first' end
        local name,index=item.name,item.slot
        local view=motion.view()
        if name=='cinema_begin' or name=='cinema_path' then return begin_shot(name=='cinema_path') end
        if name=='cinema_reposition' then return end_shot() end
        if name=='cinema_end' then return end_camera() end
        if name=='capture_view' then set('capture_view',not values.capture_view);geometry_dirty=true;hooks();return true end
        if subject and name:match('^subject_') then
            if not values.subject_preview then return false,'Enable experimental subject poses first' end
            if name=='subject_refresh' then return subject.refresh()
            elseif name=='subject_select' then return subject.select(item.subject)
            elseif name=='subject_apply' then return subject.apply(item.pose) end
        end
        if name=='camera_recenter' then
            shots.stop();motion.recenter(shots.origin());apply_view=true
            for _,id in ipairs({'right','forward','up','yaw','pitch','roll','fov'}) do set(id,0) end
            return true
        end
        if name=='camera_level' or name=='camera_portrait' or name=='camera_portrait_left' then
            shots.stop();motion.tilt(name=='camera_level' and 0 or name=='camera_portrait' and 90 or -90)
            apply_view=true;return true
        end
        if name=='lens_apply' then
            shots.stop();motion.lens(({24,35,50,85,135})[item.lens]);apply_view=true;return true
        end
        if lights and name=='light_place' then
            local ok,why=lights.apply(item.light_slot,item.light,view)
            return ok,ok and ('Placed photo light '..item.light_slot) or why
        end
        if lights and name=='light_edit' then return lights.edit(item.light_slot,item.light) end
        if lights and name=='light_read' then
            local definition,why=lights.definition(item.light_slot);if not definition then return false,why end
            local o=definition.options
            for _,field in ipairs({'intensity','enabled','cone','range','right','forward','up','follow'}) do set('light_'..field,o[field]) end
            set('light_kind',o.kind=='spot' and 2 or 1);set('light_color',o.rgb and 7 or o.color)
            local rgb=o.rgb or LIGHT_COLORS[o.color]
            for i,channel in ipairs({'red','green','blue'}) do set('light_'..channel,rgb[i]) end
            return true,'Selected light settings loaded'
        end
        if light_memory and name=='light_restore' then return light_memory.restore() end
        if lights and name=='light_aim' then
            local target={};for i=1,3 do target[i]=view.position[i]+view.forward[i]*item.target_distance end
            return lights.aim(item.light_slot,target)
        end
        if light_setups then
            if name=='light_rig_apply' then return light_setups.rig(item.rig,view,item.target_distance) end
            local action=name:match('^light_setup_(%w+)$')
            if action then return light_setups.action(action,item.setup_slot,view) end
        end
        if name=='path_record' then
            local ok,why=shots.record(view,item.duration,item.transition)
            return ok,ok and ('Recorded camera point '..shots.count()..'/32') or why
        elseif name=='path_play' then return shots.play()
        elseif name=='path_stop' then shots.stop();return true
        elseif name=='path_clear' then return shots.clear()
        elseif name=='path_remove' then return shots.remove()
        elseif name=='path_remove_selected' then return shots.remove(item.point)
        elseif name=='path_edit' then return shots.configure(item.point,item.duration,item.transition)
        elseif name=='path_recall' then
            local frame,why=shots.point(item.point);if not frame then return false,why end
            shots.stop();motion.replace(frame);apply_view=true;return true
        end
        local group,action=name:match('^(%w+)_(%w+)$')
        local result,why
        if group=='bookmark' then result,why=shots.bookmark(action,index,view)
        elseif group=='preset' then result,why=shots.preset(action,index,view)
        else return false,'Unknown camera action' end
        if type(result)=='table' then
            shots.stop();motion.replace(result);apply_view=true;return true,'Camera recalled'
        end
        return result,why
    end
    local function enqueue(name)
        if values[name]~=nil then set(name,false) end
        if #actions>=8 then notify('Camera action queue is full');return end
        actions[#actions+1]={name=name,slot=values.camera_slot,duration=values.path_duration,transition=values.path_transition,
            point=values.path_point,lens=values.focal_preset,
            subject=values.subject_slot,pose=((values.pose_page or 1)-1)*32+(values.pose_frame or 1),
            setup_slot=values.light_setup_slot,rig=values.light_rig,target_distance=values.light_target_distance or 5,
            light_slot=values.light_slot,light=lights and {right=values.light_right,forward=values.light_forward,up=values.light_up,
                color=math.min(values.light_color,6),intensity=values.light_intensity,
                rgb=values.light_color==7 and {values.light_red,values.light_green,values.light_blue} or nil,
                kind=values.light_kind==2 and 'spot' or 'omni',range=values.light_range,cone=values.light_cone,
                enabled=values.light_enabled,follow=values.light_follow} or nil}
        hooks()
    end
    local function drain_actions()
        if #actions==0 then return end
        local queued=actions;actions={}
        for _,item in ipairs(queued) do
            local called,ok,why=pcall(run_action,item)
            if not called or not ok then notify(called and why or ok)
            elseif why then notify(why) end
        end
    end
    local function fail(reason)
        log(reason)
        close(false)
    end
    local function open()
        if state ~= 'closed' and not close() then set('camera', false); return end
        if chef.shared(OWNER) ~= nil then set('camera', false); log('Another WJ camera owns this session'); return end
        chef.share(OWNER, token)
        -- Camera changes are session-local even though Chef saves menu rows.
        for _, id in ipairs({'right', 'forward', 'up', 'yaw', 'pitch', 'roll', 'fov'}) do set(id, 0) end
        local called, ok, why = pcall(camera.begin)
        if not called or not ok then fail(called and why or ok); return end
        state, dirty = 'opening', false
        set('camera', true); hooks()
    end
    local function sync_time(ok,why)
        if values.freeze~=simulation.frozen then set('freeze',simulation.frozen) end
        if values.slow_motion~=simulation.slow then set('slow_motion',simulation.slow) end
        if why and why~=last_time_reason then log(why) end
        last_time_reason=why
        hooks()
        return ok
    end
    local function release_time()
        time_dirty=false
        return sync_time(simulation.release(true))
    end
    end_camera=function()
        local ok=close(true)
        if ok and values.keep_slow_on_close then
            time_dirty=false;return sync_time(simulation.set(false,values.slow_motion,values.slow_rate))
        end
        local released=release_time();return ok and released
    end
    begin_shot=function(play_path)
        if shot then return false,'An action shot is already active' end
        if play_path and shots.count()<2 then return false,'Record at least two camera points' end
        local session=chef.call('Network.game_session')
        if type(session)~='userdata' then return false,'Cinema needs a current game session' end
        local frozen=simulation.frozen
        if subject then local ok,why=subject.reset();if not ok then return false,why end end
        if not sync_time(simulation.set(false,values.slow_motion,values.slow_rate)) then return false,'Could not resume action' end
        shots.stop();motion.reset_motion();if controls then controls.reset() end
        shot={refreeze=frozen,session=session}
        if play_path then
            local ok,why=shots.play();if not ok then end_shot();return false,why end
        end
        return true,values.cinema_notification and 'Cinema camera holds while you control gameplay' or nil
    end
    end_shot=function()
        if not shot then return false,'No action shot is active' end
        local frozen=shot.refreeze;shot=nil;shots.stop();motion.reset_motion();if controls then controls.reset() end
        if frozen then return sync_time(simulation.set(true,values.slow_motion,values.slow_rate)) end
        return true
    end
    local function camera_tick()
            if state ~= 'opening' and state ~= 'active' then return true end
            if not owns() then return false, 'Camera ownership changed' end
            if not camera.valid() then return false, 'Camera world or focus changed' end
            if shot and chef.call('Network.game_session')~=shot.session then return false,'Cinema session changed' end
            if state == 'opening' then
                local ready, reason = camera.step()
                if ready == nil then return true end
                if not ready then return false, reason end
                local baseline = camera.frame()
                if not baseline or not finite(baseline.fov) or baseline.fov <= 0 or baseline.fov >= math.pi then
                    return false, 'Camera lens unavailable'
                end
                state = 'active'
                motion = deps.motion.new(baseline)
                if shots then shots.begin(baseline) end
                if light_memory and values.remember_lights then
                    local ok,why=light_memory.restore(true);if not ok then notify(why) end
                end
            end
            if controls and controls.command then
                local command=controls.command()
                if command=='exit' then
                    if shot then local ok,why=end_shot();if not ok then return false,why end
                    else end_camera();return true end
                elseif command=='freeze' then if shot then shot.refreeze=false end;set('freeze',not values.freeze);time_dirty=true
                elseif command=='lock' then set('lock_camera',not values.lock_camera);motion.reset_motion();controls.reset()
                elseif command=='capture_view' then
                    set('capture_view',not values.capture_view);geometry_dirty=true;hooks()
                elseif command then enqueue(command) end
            end
            local changed=dirty
            if dirty then
                if shot then local ok,why=end_shot();if not ok then return false,why end end
                if shots then shots.stop() end
                motion.adjust(values)
                dirty = false
            end
            drain_actions()
            if state~='active' or not motion then return true end
            changed=apply_view or changed;apply_view=false
            local dragging=false
            if light_drag and controls and values.light_markers and values.light_drag and not values.capture_view and not shot then
                local pressed,fine=controls.drag();local reason
                dragging,reason=light_drag.tick(pressed,fine,motion.view())
                if reason then notify(reason) end
                if dragging and shots then shots.stop() end
            elseif light_drag then light_drag.reset() end
            if values.freecam and controls and not shot and not values.lock_camera and not dragging then
                local sample,reason=controls.sample(values.mouse_look,values.wheel_speed)
                if reason then return false,reason end
                if sample and sample.wheel~=0 and sample.wheel~=nil then
                    local speed=math.max(.1,math.min(50,values.move_speed*(1+values.wheel_step/100)^sample.wheel))
                    speed=math.min(50,.1+math.floor((speed-.1)/.1+.5)*.1)
                    if speed~=values.move_speed then set('move_speed',speed) end
                end
                if sample and shots then shots.stop() end
                changed=motion.step(sample,values) or changed
            else motion.reset_motion();if controls then controls.reset() end end
            if shots and shots.playing() then
                local frame,reason=shots.sample()
                if not frame then return false,reason or 'Path sample failed' end
                motion.replace(frame);changed=true
            end
            local view=motion.view()
            if lights and lights.following() then
                local ok,why=lights.tick(view);if not ok then notify(why) end
            end
            if changed then return camera.apply(view.position,view.forward,view.up,view.fov) end
            if values.freecam or shot or values.lock_camera then return camera.maintain(view) end
            return true
    end
    update = function()
        if values.global_shortcuts and controls and controls.global_command then
            local called,command=pcall(controls.global_command)
            if not called then
                log('Global shortcuts disabled: '..tostring(command));set('global_shortcuts',false)
            elseif command=='global_camera' then
                if shot then local ok,why=end_shot();if not ok then log(why) end
                elseif state=='active' or state=='opening' then end_camera()
                else open() end
                hooks();return
            elseif command=='global_slow' then
                if state=='cleanup_pending' then log('Retry photo cleanup before changing time')
                else
                    if shot then shot.refreeze=false end
                    set('slow_motion',not values.slow_motion);time_dirty=true
                end
            end
        end
        if state=='closed' or state=='cleanup_pending' then
            drain_actions()
        end
        if capture and capture.pending() then
            local ok,why=capture.tick();if not ok then notify(why) end
        end
        if bloom then
            local ok,why=true,nil
            if bloom_dirty then
                bloom_dirty=false
                if values.bloom==1 then ok,why=bloom.close() else ok,why=bloom.request(values.bloom==3) end
            end
            if bloom.waiting() then ok,why=bloom.tick() end
            if not ok and why~=last_bloom_reason then log(why) end
            last_bloom_reason=why
        end
        if dof then
            local ok,why=true,nil
            if dof_dirty then
                dof_dirty=false
                if values.native_dof==1 then ok,why=dof.close() else ok,why=dof.request(values.native_dof==3) end
            end
            if dof.waiting() then ok,why=dof.tick() end
            if not ok and why~=last_dof_reason then log(why) end
            last_dof_reason=why
        end
        if time_dirty then
            time_dirty=false
            local ok,why=true,nil
            if subject and not values.freeze then ok,why=subject.reset() end
            if ok then sync_time(simulation.set(values.freeze,values.slow_motion,values.slow_rate)) else sync_time(false,why) end
        end
        if simulation.owned then
            local was_frozen=simulation.frozen
            local ok,why=simulation.tick()
            if was_frozen and not simulation.frozen and subject then
                local restored,reason=subject.reset();if not restored then log(reason) end
            end
            -- No repeated option publication or logging in steady state.
            if why or values.freeze~=simulation.frozen or values.slow_motion~=simulation.slow then sync_time(ok,why) end
        end
        local called, ok, why = pcall(camera_tick)
        if not called or not ok then fail(called and why or ok); release_time() end
        hooks()
    end
    render = function()
        local w, h = chef.screen()
        if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return end
        if state=='active' and not values.capture_view and values.show_legend and type(chef.text)=='function' then
            local scale=values.legend_scale or 2
            local x,y=w*(values.legend_x or 2)/100,h*(values.legend_y or 3)/100
            local color=chef.color(255,230,140,math.floor((values.legend_opacity or 85)*2.55+.5))
            local text=shot and 'CINEMA: GAMEPLAY ACTIVE - RETURN TO PLACEMENT IN CHEF MENU' or
                'HOLD CAMERA CLUTCH TO MOVE - BINDINGS: WAR JOURNALIST CONTROLS IN CHEF MENU'
            if type(chef.text_fit)=='function' then text=chef.text_fit(text,scale,math.max(0,w-x)) end
            chef.text(x,y,text,scale,color,chef.TOP+103)
        end
        if state=='active' and not values.capture_view and values.light_markers and lights and type(chef.text)=='function' and type(chef.world_to_screen)=='function' then
            for _,marker in ipairs(lights.markers()) do
                local p=marker.position;local x,y=chef.world_to_screen(p[1],p[2],p[3])
                if finite(x) and finite(y) and x>=0 and y>=0 and x<=w and y<=h then
                    chef.text(x,y,tostring(marker.slot),2,chef.color(255,230,140,255),chef.TOP+104)
                end
            end
        end
        if state=='active' and not values.capture_view and values.light_swatch and lights and w>=100 and h>=50 then
            local rgb=LIGHT_COLORS[values.light_color]
            local r,g,b=values.light_red,values.light_green,values.light_blue
            if rgb then r,g,b=rgb[1],rgb[2],rgb[3] end
            chef.rect(12,12,48,20,chef.color(r,g,b,255),chef.TOP+104)
            if type(chef.text)=='function' then chef.text(12,34,'NEXT LIGHT',1,chef.color(255,255,255,255),chef.TOP+104) end
        end
        if not values.overlay then return end
        if geometry_dirty or width ~= w or height ~= h then
            width, height = w, h
            local visible=values
            if values.capture_view then visible={};for key,value in pairs(values) do visible[key]=value end;visible.grid=1 end
            geometry = deps.composition.layout_static(w, h, visible)
            geometry_dirty = false
            grain_phase,grain_fault=nil,nil
        end
        -- Engine drawing is immediate-mode. Only geometry is retained; colors
        -- are frame-owned engine values and must be made again for each draw.
        for _, rect in ipairs(geometry) do
            local c = rect.c
            local color=chef.color(c[1], c[2], c[3], math.floor(rect.a * 255 + .5))
            local layer=chef.TOP+(rect.layer or 100)
            if rect.type=='triangle' then
                local p=rect.points
                local native=chef.triangle(p[1],p[2],p[3],p[4],p[5],p[6],color,layer)
                if native==false and values.logo==2 and deps.crest_fallback then
                    -- Chef otherwise scan-converts every triangle every frame.
                    -- Pay for one probe, then use the pre-baked union of spans.
                    deps.composition.logo_art[2]=deps.crest_fallback;geometry_dirty=true
                    log('Crest uses bounded rectangle fallback');break
                end
            else chef.rect(rect.x, rect.y, rect.w, rect.h,color,layer) end
        end
        if (values.grain or 0)>0 and not grain_fault then
            local stamp=chef.call('Application.time_since_launch')
            if not finite(stamp) or stamp<0 then grain_fault=true;log('Grain clock unavailable');return end
            local phase=math.floor(stamp*12)%4096
            if phase~=grain_phase then grain_geometry=deps.composition.layout_grain(w,h,values,phase);grain_phase=phase end
            for _,r in ipairs(grain_geometry) do local c=r.c
                chef.rect(r.x,r.y,r.w,r.h,chef.color(c[1],c[2],c[3],math.floor(r.a*255+.5)),chef.TOP+101)
            end
        end
    end
    chef.title('War Journalist (Chef preview)')
    local function option(id, spec, changed)
        option_specs[id]=spec
        local value, why = chef.option(id, spec)
        assert(value ~= nil, 'Chef option ' .. id .. ': ' .. tostring(why))
        values[id] = value
        chef.on_change(id, function(v)
            values[id] = v
            if stopped or changing then return end
            if changed then changed(v) else geometry_dirty = true end
        end)
    end
    option('overlay', {type = 'toggle', label = 'Composition overlay', default = false}, function() hooks() end)
    option('frame', {type = 'choice', label = 'Frame', default = 1,
        choices = {'Full screen', '2.39:1', '16:9', 'Square', '4:5'}})
    option('grid', {type = 'choice', label = 'Guides', default = 1,
        choices = {'None', 'Thirds', 'Crosshair', 'Golden ratio'}})
    option('filter', {type = 'choice', label = 'Tint overlay', default = 1, choices = deps.composition.filter_names})
    option('filter_strength', {type = 'slider', label = 'Tint strength', min = 0, max = 100, step = 1, default = 25})
    option('vignette', {type = 'slider', label = 'Vignette overlay', min = 0, max = 100, step = 1, default = 0})
    option('vignette_width',{type='slider',label='Vignette width',min=1,max=50,step=1,default=18})
    option('grain',{type='slider',label='Film grain',min=0,max=100,step=1,default=0})
    option('grain_size',{type='slider',label='Grain size',min=1,max=4,step=.5,default=1.5})
    option('clean_view',{type='toggle',label='Clean composition (hide guides and logo)',default=false})
    option('capture_view',{type='toggle',label='External screenshot view (hide WJ guides/controls)',default=false},function()
        geometry_dirty=true;hooks()
    end);set('capture_view',false)
    if capture then
        -- Saved by the loader itself, as DDS, only for a mod its TRUSTED list grants
        -- screenshots; every other mod is told 'not available to this mod'.
        option('capture_dds',{type='toggle',label='Save screenshot after menu closes (DDS, needs Chef grant)',default=false},
            function(on) if on then enqueue('capture_dds') end end)
        set('capture_dds',false)
    end
    option('logo',{type='choice',label='Logo',default=1,choices={'None','Helldiver crest','DBF mark','Super Earth crest',
        'Helldivers 2','Arrowhead','Helldivers 2 wide','Helldivers 2 compact','Helldivers II crest',
        'Super Citizen Edition','Omens of Tyranny','Heart of Democracy','Into the Unjust'}})
    for _,o in ipairs({{'logo_size','Logo size',1,400,100},{'logo_opacity','Logo opacity',0,100,85},
        {'logo_x','Logo horizontal',0,100,90},{'logo_y','Logo vertical',0,100,8}}) do
        option(o[1],{type='slider',label=o[2],min=o[3],max=o[4],step=1,default=o[5]})
    end
    local colors={'#FFFFFF','#F6CA5C','#000000'}
    option('logo_tint',{type='choice',label='Logo color',default=1,choices={'White','Gold','Black','Custom RGB'}},function(v)
        if colors[v] then
            for index,channel in ipairs({'red','green','blue'}) do set('logo_'..channel,tonumber(colors[v]:sub(index*2,index*2+1),16)) end
        end
        values.logo_color=colors[v] or string.format('#%02X%02X%02X',values.logo_red,values.logo_green,values.logo_blue)
        geometry_dirty=true
    end)
    values.logo_color=colors[values.logo_tint] or '#FFFFFF'
    for index,channel in ipairs({'red','green','blue'}) do
        local id='logo_'..channel
        option(id,{type='slider',label='Logo '..channel,min=0,max=255,step=1,default=255},function()
            set('logo_tint',4)
            values.logo_color=string.format('#%02X%02X%02X',values.logo_red or 255,values.logo_green or 255,values.logo_blue or 255)
            geometry_dirty=true
        end)
    end
    if values.logo_tint==4 then
        values.logo_color=string.format('#%02X%02X%02X',values.logo_red,values.logo_green,values.logo_blue)
    else
        for index,channel in ipairs({'red','green','blue'}) do set('logo_'..channel,tonumber(values.logo_color:sub(index*2,index*2+1),16)) end
    end
    option('show_legend',{type='toggle',label='Show camera controls legend',default=false},function() hooks() end)
    for _,o in ipairs({{'legend_x','Legend horizontal',0,100,2},{'legend_y','Legend vertical',0,100,3},
        {'legend_scale','Legend text scale',1,4,2},{'legend_opacity','Legend opacity',0,100,85}}) do
        option(o[1],{type='slider',label=o[2],min=o[3],max=o[4],step=1,default=o[5]},function() end)
    end
    option('camera', {type = 'toggle', label = 'Photo camera (experimental)', default = false},
        function(on) if on then open() else end_camera() end end)
    option('global_shortcuts',{type='toggle',label='Enable gameplay shortcuts (shared keys, no chat detection)',default=false},function()
        if controls and controls.reset_global then controls.reset_global() end;hooks()
    end)
    option('freecam', {type='toggle',label='Free camera controls and hold',default=true},function()
        if controls then controls.reset() end
    end)
    option('lock_camera',{type='toggle',label='Lock camera movement',default=false},function()
        if motion then motion.reset_motion() end;if controls then controls.reset() end
    end)
    option('camera_smoothing',{type='toggle',label='Smooth camera movement and zoom',default=false},function()
        if motion then motion.reset_motion() end
    end)
    option('smoothing_strength',{type='slider',label='Camera smoothing',min=0,max=100,step=1,default=50},function() end)
    option('mouse_look', {type='toggle',label='Mouse look while holding control key',default=false},function()
        if controls then controls.reset() end
    end)
    option('move_speed', {type='slider',label='Camera speed (m/s)',min=.1,max=50,step=.1,default=3},function() end)
    option('wheel_speed',{type='toggle',label='Clutch + wheel adjusts camera speed',default=true},function() end)
    option('wheel_step',{type='slider',label='Wheel speed change (%)',min=5,max=100,step=5,default=20},function() end)
    option('vertical_world',{type='toggle',label='Vertical movement uses world up',default=false},function() end)
    option('roll_speed',{type='slider',label='Camera roll speed (degrees/s)',min=5,max=180,step=5,default=60},function() end)
    option('zoom_speed',{type='slider',label='Camera zoom speed (degrees/s)',min=5,max=90,step=5,default=45},function() end)
    option('turn_speed', {type='slider',label='Camera turn speed (degrees/s)',min=5,max=180,step=5,default=60},function() end)
    option('mouse_sensitivity', {type='slider',label='Mouse sensitivity',min=.01,max=1,step=.01,default=.12},function() end)
    local function time_changed() if shot then shot.refreeze=false end;time_dirty=true; hooks() end
    option('freeze', {type='toggle',label='Freeze action (solo)',default=false},time_changed)
    option('slow_motion', {type='toggle',label='Slow motion (solo)',default=false},time_changed)
    option('slow_rate', {type='slider',label='Slow-motion rate',min=.05,max=1,step=.05,default=.2},time_changed)
    option('keep_slow_on_close',{type='toggle',label='Keep chosen slow motion after manual camera close',default=false},function() end)
    option('cinema_notification',{type='toggle',label='Show three-second Cinema notification',default=true},function() end)
    if shots then
        option('focal_preset',{type='choice',label='Lens shortcut (24 mm sensor height)',default=3,
            choices={'24 mm','35 mm','50 mm','85 mm','135 mm'}},function() end)
        for _,a in ipairs({{'lens_apply','Apply lens shortcut'},{'camera_level','Level camera horizon'},
            {'camera_portrait','Portrait tilt +90'},{'camera_portrait_left','Portrait tilt -90'},
            {'camera_recenter','Return to opening camera'},{'camera_cleanup','Retry photo cleanup'},
            {'cinema_begin','Begin placed action shot'},
            {'cinema_path','Begin path action shot'},{'cinema_reposition','Return to camera placement'},{'cinema_end','End action shot'}}) do
            local id=a[1];option(id,{type='toggle',label=a[2],default=false},function(on) if on then enqueue(id) end end);set(id,false)
        end
        option('camera_slot',{type='choice',label='Camera slot',default=1,choices={'1','2','3','4','5'}},function() end)
        option('path_duration',{type='slider',label='Next path segment (seconds)',min=.1,max=60,step=.1,default=3},function() end)
        option('path_transition',{type='choice',label='Next path segment',default=1,choices={'Smooth','Cut'}},function() end)
        option('path_point',{type='slider',label='Selected recorded point',min=1,max=32,step=1,default=1},function() end)
        for _,a in ipairs({{'path_record','Record camera point'},{'path_play','Play camera path'},
            {'path_stop','Stop camera path'},{'path_remove','Remove last point'},{'path_clear','Clear camera path'},
            {'path_edit','Set selected segment duration/transition'},{'path_remove_selected','Remove selected point'},
            {'path_recall','Recall selected point'},
            {'bookmark_save','Save scene bookmark'},{'bookmark_recall','Recall scene bookmark'},
            {'preset_save','Save camera-relative preset'},{'preset_recall','Recall camera-relative preset'},
            {'preset_clear','Clear camera-relative preset'}}) do
            local id=a[1]
            option(id,{type='toggle',label=a[2],default=false},function(on) if on then enqueue(id) end end)
            set(id,false)
        end
    end
    if bloom then
        option('bloom',{type='choice',label='Native bloom (experimental)',default=1,choices={'Game setting','Off','On'}},function()
            bloom_dirty=true;hooks()
        end)
        set('bloom',1)
    end
    if dof then
        option('native_dof',{type='choice',label='Native depth of field (game focus)',default=1,choices={'Game setting','Off','On'}},function()
            dof_dirty=true;hooks()
        end);set('native_dof',1)
    end
    if lights then
        option('remember_lights',{type='toggle',label='Restore lights when reopening in the same scene',default=true},function(on)
            if not on and light_memory then light_memory.forget() end
        end)
        option('light_slot',{type='choice',label='Photo light slot',default=1,choices={'1','2','3'}},function() end)
        option('light_color',{type='choice',label='Next light color',default=1,
            choices={'White','Warm','Cool','Red','Green','Violet','Custom RGB'}},function() end)
        option('light_intensity',{type='slider',label='Next light intensity',min=0,max=10000,step=.1,default=3},function() end)
        option('light_enabled',{type='toggle',label='Next light enabled',default=true},function() end)
        option('light_kind',{type='choice',label='Next light type',default=1,choices={'Point','Spot'}},function() end)
        option('light_follow',{type='toggle',label='Next light follows photo camera',default=false},function() end)
        option('light_range',{type='slider',label='Next light range (requires native readback)',min=.1,max=1000,step=.1,default=8},function() end)
        option('light_cone',{type='slider',label='Next spot cone (degrees)',min=1,max=175,step=1,default=45},function() end)
        for _,channel in ipairs({'red','green','blue'}) do
            option('light_'..channel,{type='slider',label='Next light '..channel,min=0,max=255,step=1,default=255},function() end)
        end
        option('light_markers',{type='toggle',label='Show numbered photo light markers',default=false},function() hooks() end)
        option('light_swatch',{type='toggle',label='Preview next light color swatch',default=false},function() hooks() end)
        option('light_drag',{type='toggle',label='Clutch + middle button drags light markers',default=false},function()
            if light_drag then light_drag.reset() end
        end)
        for _,a in ipairs({{'right','Right',0},{'forward','Forward',2},{'up','Up',0}}) do
            option('light_'..a[1],{type='slider',label='Next light '..a[2]..' offset',min=-100,max=100,step=.1,default=a[3]},function() end)
        end
        for _,a in ipairs({{'light_place','Place/update selected light'},{'light_remove','Remove selected light'},
            {'light_read','Load selected light settings'},{'light_edit','Apply settings at existing light anchor'},
            {'light_restore','Retry remembered light restoration'},
            {'light_aim','Aim selected spot at lighting target'},
            {'light_clear','Remove all photo lights'}}) do
            local id=a[1];option(id,{type='toggle',label=a[2],default=false},function(on) if on then enqueue(id) end end)
            set(id,false)
        end
        if light_setups then
            option('light_setup_slot',{type='choice',label='Lighting setup slot',default=1,choices={'1','2','3','4','5'}},function() end)
            option('light_rig',{type='choice',label='Lighting rig',default=1,choices={'Key / Fill / Rim','Portrait','Dramatic side'}},function() end)
            option('light_target_distance',{type='slider',label='Lighting target ahead (m)',min=.1,max=100,step=.1,default=5},function() end)
            for _,a in ipairs({{'light_rig_apply','Replace with lighting rig'},{'light_setup_save','Save camera-relative lighting setup'},
                {'light_setup_recall','Recall camera-relative lighting setup'},{'light_setup_clear','Clear saved lighting setup'}}) do
                local id=a[1];option(id,{type='toggle',label=a[2],default=false},function(on) if on then enqueue(id) end end);set(id,false)
            end
        end
    end
    if subject then
        option('subject_preview',{type='toggle',label='Experimental selected-subject poses',default=false},function(on)
            enqueue(on and 'subject_refresh' or 'subject_disable')
        end);set('subject_preview',false)
        option('subject_slot',{type='choice',label='Photographic subject slot',default=1,choices={'1','2','3','4'}},function() end)
        option('pose_page',{type='choice',label='Pose catalogue page',default=1,
            choices={'1-32','33-64','65-96','97-128','129-160','161-192','193-213'}},function() end)
        option('pose_frame',{type='slider',label='Pose number within page',min=1,max=32,step=1,default=1},function() end)
        for _,a in ipairs({{'subject_refresh','Refresh photographic subjects'},{'subject_select','Select photographic subject'},
            {'subject_apply','Apply selected pose (requires Freeze)'},{'subject_reset','Reset selected pose'},
            {'subject_recover','Retry pending subject cleanup'}}) do
            local id=a[1];option(id,{type='toggle',label=a[2],default=false},function(on) if on then enqueue(id) end end);set(id,false)
        end
    end
    for _, item in ipairs({{'right', 'Right offset', -20, 20, .1}, {'forward', 'Forward offset', -20, 20, .1},
        {'up', 'Up offset', -20, 20, .1}, {'yaw', 'Yaw offset', -180, 180, 1},
        {'pitch', 'Pitch offset', -80, 80, 1}, {'roll', 'Roll offset', -180, 180, 1},
        {'fov', 'Vertical FOV (0 = original)', 0, 120, 1}}) do
        option(item[1], {type = 'slider', label = item[2], min = item[3], max = item[4], step = item[5], default = 0},
            function() if state == 'active' or state == 'opening' then dirty = true end end)
    end
    -- Never restore a persisted camera acquisition on startup.
    set('camera', false)
    set('freeze',false); set('slow_motion',false)
    for _, id in ipairs({'right', 'forward', 'up', 'yaw', 'pitch', 'roll', 'fov'}) do set(id, 0) end
    subscriptions[#subscriptions + 1] = chef.on('world', function()
        if light_memory then light_memory.forget() end
        if state ~= 'closed' then
            -- A settled world event may be a mission change inside the SAME
            -- engine world. Let close validate it; never blindly discard edits.
            close(false)
        end
        release_time()
        if bloom then bloom.close();set('bloom',1);bloom_dirty=false;hooks() end
        if dof then dof.close();set('native_dof',1);dof_dirty=false;hooks() end
    end)
    local function stop()
        if stopped then return state == 'closed' and not simulation.owned and (not bloom or bloom.state=='closed') and
            (not dof or dof.state=='closed') and (not lights or lights.count()==0) end
        stopped = true
        if capture then capture.cancel() end
        local ok = close(false)
        local time_ok = release_time()
        local bloom_ok=true
        if bloom then bloom_ok=bloom.close();if not bloom_ok then log('Bloom cleanup is pending at stop') end end
        local dof_ok=true
        if dof then dof_ok=dof.close();if not dof_ok then log('Native DoF cleanup is pending at stop') end end
        self.update, self.render = nil, nil
        for _, unsubscribe in ipairs(subscriptions) do unsubscribe() end
        subscriptions = {}
        return ok and time_ok and bloom_ok and dof_ok
    end
    self.on_stop, self.shutdown = stop, stop
    function self.status() return state end
    function self.time_status() return simulation.frozen,simulation.slow,simulation.pending end
    function self.shot_status() return shots and shots.count() or 0,shots and shots.playing() or false end
    function self.light_count() return lights and lights.count() or 0 end
    function self.cinema_active() return shot~=nil end
    function self.subject_status() return subject and subject.status() or nil end
    hooks()
    if controls_reason then log(controls_reason) end
    if deps.loader_features then log(deps.loader_features.describe(features)) end
    log('Chef photo preview ready; input is shared with gameplay; live validation pending')
    return self
end
return M

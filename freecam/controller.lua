-- ActionCam photomode adapter. Camera placement stays owned by ActionCam.
local M={}
function M.new(photo,settings,can_start,log,freeze,options,effects,menu_factory,catalog,saved_camera,screenshots,focus_sampler,lights,subject,director,unused_input_release,update_epoch,ai,poses)
    local roll_value;local self={};local api,handle,provider;local held=true;local retry=0;local controls={};local resume_after;local suppress_escape;local panel;local menu_focus=false;local controls_hidden=false;local recovery_menu=false;local focus_edge=false;local hide_edge=false;local slow_edge=false;local lock_edge=false;local escape_edge=false;local screenshot_edge=false
    local subject_pair;local subject_held;local subject_ready=false;local autofocus_write=false;local focus_deadline=0;local focus_elapsed=0;local focus_status='Manual focus';local focus_mode_seen;local menu_startup_reset=false
    local lighting_write=false;local lighting_revision=-1
    self._input_tick=0
    self._ai=ai
    function self._native_menu_state()
        local reader=api and api.camera_input and api.camera_input.native_menu_active
        if type(reader)~='function'then return false end
        local ok,active=pcall(reader)
        -- Once a native reader is attached, only exact false grants camera
        -- input. An unavailable/replaced UI stack cannot grant stale movement.
        return not ok or active~=false
    end
    function self.native_menu_blocked()return self._native_menu_state()end
    function self._external_menu_open()return api.is_open()or self._native_menu_blocked==true or self._native_menu_yield~=nil end
    function self.camera_suspended()
        return not photo.active or not api or not provider or self._native_menu_yield~=nil or self._native_menu_state()or api.is_open()or not api.camera_input.focused()
    end
    function self._release_input()
        if not provider then return true end
        local finish=self._native_menu_state()and provider.native_menu_handoff or provider.release
        local ok,why=finish();if ok~=false then provider=nil end
        return ok,why
    end
    self._poses=poses;self._pose_available=false;self._pose_caps={}
    function self._request_time_change(rate)
        if not freeze then return true end
        if rate~=0 and self._poses and(self._poses.active or self._poses.pending)then
            local waiting=self._pose_time_pending or{};waiting.rate=rate
            if not waiting.queued then
                local called,ok,why=pcall(self._poses.release)
                waiting.queued=called and ok~=false
                if not waiting.queued then log('Subject pose cleanup: '..tostring(called and why or ok))end
            end
            if self._poses.active or self._poses.pending then
                self._pose_time_pending=waiting;photo.input={}
                return true,'Restoring the original pose before changing simulation time'
            end
        end
        self._pose_time_pending=nil
        if rate~=nil then return freeze.start(rate)end
        return freeze.release()
    end
    function self._pose_action(stop)
        if not self._poses then return false,'Subject poses unavailable'end
        local method,id
        if stop then
            if not(self._poses.active or self._poses.pending)then return false,'No owned pose to reset'end
            method=self._poses.queue_stop
        else
            id=options and options.subject_poses and handle and options.subject_poses[handle.get('subject_pose')]
            if not(photo.active and not self._pose_stop_pending and not self._pose_time_pending and self._pose_available and self._pose_caps[id])then return false,'Pause entire action and wait for a supported local subject'end
            method=self._poses.queue
        end
        local called,ok,why=pcall(method,id)
        if not called or ok==false then
            local reason=tostring(called and why or ok);log('Photo subject pose: '..reason)
            if controls.subject_pose_status then controls.subject_pose_status.label=reason end
        end
        return called and ok~=false,called and why or ok
    end
    function self._refresh_poses(dt)
        if not controls.subject_pose then return end
        local ready,status,caps=false,'Subject pose service unavailable',{}
        if self._poses then
            local now;local input=api and api.camera_input
            if input and type(input.now)=='function'then local ok,value=pcall(input.now);if ok then now=value end end
            local called,a,b,c=pcall(self._poses.refresh,dt,now)
            if called then ready,status,caps=a,b,c or{}else status=tostring(a)end
        end
        self._pose_available=ready==true;self._pose_caps=caps
        local selected=options and options.subject_poses and options.subject_poses[handle.get('subject_pose')]
        local any=false;for _,id in ipairs(options and options.subject_poses or{})do if caps[id]==true then any=true end end
        controls.subject_pose.disabled=not(photo.active and not self._pose_stop_pending and not self._pose_time_pending and ready and any)
        controls.subject_pose_play.disabled=not(photo.active and not self._pose_stop_pending and not self._pose_time_pending and ready and caps[selected]==true)
        controls.subject_pose_stop.disabled=not(self._poses and(self._poses.active or self._poses.pending))
        if self._pose_stop_pending then status=self._poses.status or'Restoring the original pose before leaving Photo Mode'
        elseif self._pose_time_pending then status='Restoring the original pose before changing simulation time'
        elseif ready and not caps[selected]then status='Selected pose is unavailable for this subject'end
        controls.subject_pose_status.label=status or'Subject poses unavailable'
    end
    local ai_requested=1;local ai_sync=false;local ai_elapsed=.5;local ai_available=false;local ai_reason='Enemy behavior backend unavailable'
    function self._set_ai_value(value)
        if not(handle and controls.ai_behavior)then return end
        local control=controls.ai_behavior;local disabled=control.disabled
        control.disabled=false;ai_sync=true
        local called,ok,why=pcall(handle.set,'ai_behavior',value)
        ai_sync=false;control.disabled=disabled
        if not called or ok==false then log('Enemy behavior setting: '..tostring(called and why or ok))end
    end
    function self._ai_change(value)
        if ai_sync then return end
        local mode=options and options.ai_modes and options.ai_modes[value]
        if not mode or(mode~='normal'and not(photo.active and ai and ai_available))then
            self._set_ai_value(ai_requested)
            return
        end
        ai_requested=value
        if ai then local called,ok,why=pcall(ai.queue,mode);if not called or ok==false then log('Enemy behavior: '..tostring(called and why or ok))end end
    end
    function self._reset_ai()
        ai_requested=1;self._set_ai_value(1)
        if ai then ai.queue('normal')end
    end
    local function stop_ai()
        if ai and(ai_requested~=1 or ai.mode~='normal')then ai.queue('normal')end
        ai_requested=1
        if handle and controls.ai_behavior and handle.get('ai_behavior')~=1 then self._set_ai_value(1)end
    end
    function self._refresh_ai(dt)
        if not controls.ai_behavior then return end
        if ai and self._ai_solo_reset~=(ai.solo_reset or 0)then
            self._ai_solo_reset=ai.solo_reset or 0
            if self._ai_solo_reset>0 and ai.mode=='normal'then ai_requested=1;self._set_ai_value(1)end
        end
        ai_elapsed=ai_elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
        if ai and ai_elapsed>=.5 then
            ai_elapsed=0;local called,ready,why=pcall(ai.ready)
            ai_available=called and ready==true;ai_reason=called and why or tostring(ready)
        end
        -- Normal/Reset remain reachable for an active lease after authority loss.
        local outstanding=ai and(ai_requested~=1 or ai.pending or ai.count()>0)
        controls.ai_behavior.disabled=not(ai and photo.active and ai_available)
        controls.ai_reset.disabled=not(ai and(ai_available or outstanding))
        if not ai then controls.ai_status.label='Enemy behavior unavailable: '..ai_reason
        elseif ai.pending then controls.ai_status.label=ai_requested~=1 and'Enemy behavior: applying on next update'or'Enemy behavior: restoring on next update'
        elseif ai.count()>0 or ai.mode~='normal'then controls.ai_status.label=ai.status
        elseif not ai_available then controls.ai_status.label='Enemy behavior unavailable: '..tostring(ai_reason)
        else controls.ai_status.label='Enemy behavior: Normal (0 affected)'end
    end
    local director_elapsed=.5;local director_available=false;local director_reason='Director is waiting for a verified player'
    local subject_fields={'hide_player','hide_armour','hide_weapons'}
    local function subject_change()
        if not subject or not photo.active or not handle then return end
        local values={};for _,id in ipairs(subject_fields)do values[id]=handle.get(id)==true end
        local called,ok,why=pcall(subject.queue,values)
        if not called or ok==false then log('Photo subject: '..tostring(called and why or ok))end
    end
    local function director_action(action)
        if not director or not handle then return false end
        local called,ok,why=pcall(director[action],handle.get('director_slot'),handle)
        if not called or ok==false then log('Photo Director: '..tostring(called and why or ok));if controls.director_status then controls.director_status.label=tostring(called and why or ok)end end
        if action=='recall'and called and ok~=false then roll_value=nil end
        director_elapsed=.5;return called and ok~=false
    end
    local function refresh_subject_director(dt)
        if controls.subject_status then
            local ready,why,caps=false,'Subject renderer unavailable',{}
            if subject then local called,a,b,c=pcall(subject.refresh,dt);if called then ready,why,caps=a,b,c or{}else why=tostring(a)end end
            for _,id in ipairs(subject_fields)do if controls[id]then controls[id].disabled=not(photo.active and ready and caps[id])end end
            controls.subject_status.label=subject and subject.status or why
        end
        if controls.director_status then
            director_elapsed=director_elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
            if director and director_elapsed>=.5 then
                director_elapsed=0;local called,a,b=pcall(director.ready)
                director_available=called and a==true;director_reason=called and b or tostring(a)
            end
            local index=handle.get('director_slot');local occupied=director and director.occupied(index)
            controls.director_slot.choices=director and director.list()or controls.director_slot.choices
            controls.director_save.disabled=not(photo.active and director_available and photo.pos and photo.view)
            controls.director_recall.disabled=not(photo.active and director_available and occupied)
            controls.director_clear.disabled=not occupied
            controls.director_status.label=director and(director_available and director.status or director_reason)or'Director player context unavailable'
        end
    end
    local lens_preset_write=false
    local function lens_change(id,value)
        if lens_preset_write or not handle or not options then return end
        if id=='focal_preset'then
            local target=options.preset_fov and options.preset_fov(value)
            if target then lens_preset_write=true;local ran,ok,why=pcall(handle.set,'fov',target);lens_preset_write=false;if not ran or ok==false then log('Lens preset: '..tostring(ran and why or ok))end end
        elseif id=='fov'then
            if handle.get('focal_preset')~=1 then handle.set('focal_preset',1)end
        elseif id=='roll_preset'then
            local target=options.roll_presets and options.roll_presets[value]
            if target~=nil and target~=false then roll_value=nil;lens_preset_write=true;local ran,ok,why=pcall(handle.set,'roll',target);lens_preset_write=false;if not ran or ok==false then log('Tilt shortcut: '..tostring(ran and why or ok))end end
        elseif id=='roll'then
            if handle.get('roll_preset')~=1 then handle.set('roll_preset',1)end
        end
    end
    local function refresh_lens()
        if not options or not handle then return end
        if controls.focal_length_status and options.focal_length then
            local mm=options.focal_length(effects and effects.fov)
            controls.focal_length_status.label=mm and('Focal length: '..string.format('%.1f mm',mm)..(handle.get('fov')==0 and' (gameplay)'or''))or'Focal length: waiting for camera'
        end
        if controls.focal_preset then
            local target=options.preset_fov(handle.get('focal_preset'))
            if target and math.abs(handle.get('fov')-target)>.0011 then handle.set('focal_preset',1)end
        end
        if controls.roll_preset then
            local target=options.roll_presets[handle.get('roll_preset')]
            if target~=nil and target~=false and math.abs((roll_value or handle.get('roll'))-target)>.01 then handle.set('roll_preset',1)end
        end
    end
    local light_fields={light_enabled='enabled',light_intensity='intensity',light_color='color',light_range='range',light_cone='cone',light_right='right',light_forward='forward',light_up='up',light_follow='follow_camera'}
    local function light_request(action,value)
        if not lights or not photo.active then return false end
        local ok,why=lights.queue(action,value)
        if not ok then log('Photo lighting: '..tostring(why))end
        return ok,why
    end
    self._light_gizmo_factory=menu_factory and menu_factory.gizmo_factory
    if self._light_gizmo_factory and lights then self._light_gizmos=self._light_gizmo_factory.new(light_request)end
    function self._light_frame()
        local frame=photo.active and photo.light_context;if not frame then return nil end
        local epoch=frame.scene_epoch
        if lights and lights.scene_context then
            local ok,world,current=pcall(lights.scene_context)
            if not ok or world~=frame.world then self._light_subject=nil;return nil end
            epoch=current
        end
        if type(epoch)~='number'or epoch~=epoch or epoch<0 or epoch==math.huge then self._light_subject=nil;return nil end
        return{world=frame.world,scene_epoch=epoch,position=frame.position,forward=frame.forward,right=frame.right,up=frame.up}
    end
    function self._remember_light_subject(u,v,distance)
        local frame=self._light_frame();local factory=self._light_gizmo_factory
        if not frame or not factory or not api or not api.photo_resolution then return end
        local w,h=api.photo_resolution();local target=factory.target(frame,effects and effects.fov,w,h,u,v,distance)
        self._light_subject=target and{world=frame.world,epoch=frame.scene_epoch,position=target}or nil
    end
    function self._light_target()
        local frame=self._light_frame();local factory=self._light_gizmo_factory
        if not frame or not factory or not api or not api.photo_resolution then return nil end
        local saved=self._light_subject
        if saved and(saved.world~=frame.world or saved.epoch~=frame.scene_epoch)then self._light_subject=nil;saved=nil end
        if saved then return saved.position,frame end
        local w,h=api.photo_resolution()
        return factory.target(frame,effects and effects.fov,w,h,.5,.5,handle and handle.get('focus_distance')),frame
    end
    function self._light_aim()
        local target=self._light_target();if not target then return false,'Subject position unavailable'end
        return light_request('aim',{target=target})
    end
    function self._light_preset()
        local target,frame=self._light_target();local name=options and options.light_presets and options.light_presets[handle.get('light_preset')]
        if not target or not name then return false,'Subject lighting preset unavailable'end
        return light_request('preset',{name=name,target=target,frame=frame})
    end
    function self._light_setup(action)
        local presets=lights and lights.presets
        if not presets or not handle then return false,'Lighting setup storage unavailable'end
        local slot=handle.get('light_setup_slot');local ok,why
        if action=='clear'then ok,why=presets.clear(slot)
        else
            local target,frame=self._light_target();if not target then return false,'Subject position unavailable'end
            if action=='save'then
                local setup,reason=lights.export_setup();if not setup then ok,why=false,reason else ok,why=presets.save(slot,setup,target,frame)end
            elseif action=='recall'then
                local setup,reason=presets.recall(slot,target,frame);if not setup then ok,why=false,reason else ok,why=light_request('import_setup',setup)end
            else return false,'Unknown lighting setup action'end
        end
        if not ok then log('Photo lighting setup: '..tostring(why))end
        return ok,why
    end
    function self._sync_light_gizmos(w,h,focused,hidden)
        if not self._light_gizmos then return end
        local items=lights and lights.list and lights.list()or{}
        self._light_gizmos.update(items,self._light_frame(),effects and effects.fov,w,h,photo.active and not hidden)
        if not focused then self._light_gizmos.cancel()end
    end
    local function light_values()
        local values={kind=handle.get('light_kind')==2 and'spot'or'omni'}
        for id,key in pairs(light_fields)do values[key]=handle.get(id)end;return values
    end
    local function light_change(id,value)
        if lighting_write or not lights or not photo.active then return end
        if id=='light_selected'then light_request('select',value)
        elseif id=='light_kind'then light_request('update',{kind=value==2 and'spot'or'omni'})
        elseif light_fields[id]then light_request('update',{[light_fields[id]]=value})end
    end
    local function refresh_lights()
        if not controls.light_add then return end
        local context=photo.active and photo.light_context
        local ready,why,caps=false,'Photo lighting is waiting for a camera',{}
        if lights and context then ready,why,caps=lights.ready(context.world);caps=caps or{}end
        local values,index,count;if lights then values,index,count=lights.selected()end;count=count or 0
        local available=ready and context~=nil;local selected=available and values~=nil
        controls.light_add.disabled=not available or count>=3
        controls.light_selected.disabled=not selected
        controls.light_selected.choices={};for i=1,math.max(1,count)do controls.light_selected.choices[i]='Light '..i end
        for id in pairs(light_fields)do if controls[id]then controls[id].disabled=not selected end end
        controls.light_kind.disabled=not selected
        controls.light_kind.choices=caps.spot and{'Point','Spot'}or{'Point'}
        controls.light_range.disabled=not(selected and caps.range)
        controls.light_cone.disabled=not(selected and caps.spot and values.kind=='spot')
        controls.light_place.disabled=not selected;controls.light_remove.disabled=not selected;controls.light_clear.disabled=count==0
        local target=self._light_target()
        if controls.light_aim then controls.light_aim.disabled=not(selected and target)end
        if controls.light_apply_preset then controls.light_apply_preset.disabled=not(available and target)end
        if controls.light_setup_slot then
            local presets=lights and lights.presets
            controls.light_setup_slot.disabled=not presets
            if presets then controls.light_setup_slot.choices=presets.list()end
            controls.light_setup_save.disabled=not(presets and available and target and count>0 and not lights.pending)
            controls.light_setup_recall.disabled=not(presets and available and target and presets.occupied(handle.get('light_setup_slot')))
            controls.light_setup_clear.disabled=not(presets and presets.occupied(handle.get('light_setup_slot')))
            controls.light_setup_status.label=presets and presets.status or'Lighting setup storage unavailable'
        end
        controls.light_status.label=ready and lights.status or why
        if lights and not lights.pending and lighting_revision~=lights.revision then
            if selected and handle then
                local updates={light_selected=index,light_kind=values.kind=='spot'and 2 or 1}
                for id,key in pairs(light_fields)do if controls[id]and not controls[id].disabled then updates[id]=values[key]end end
                for id,value in pairs(updates)do if controls[id].disabled or handle.get(id)==value then updates[id]=nil end end
                lighting_write=true
                local called,accepted,err=pcall(function()
                    if next(updates)==nil then return true end
                    if handle.set_many then return handle.set_many(updates)end
                    for id,value in pairs(updates)do local ok,why=handle.set(id,value);if ok==false then return false,why end end
                    return true
                end)
                lighting_write=false
                if not called or accepted==false then log('Photo lighting readback: '..tostring(called and err or accepted));return end
            end
            lighting_revision=lights.revision
        end
    end
    local function focus_message(message)focus_status=message;if controls.focus_status then controls.focus_status.label=message end end
    local function clear_subject_click()
        subject_pair=nil;subject_held=nil;subject_ready=false
    end
    local function sample_focus(u,v,prefix)
        if not focus_sampler or type(focus_sampler.sample)~='function'then focus_message('Auto-focus unavailable');return false end
        local called,distance,why=pcall(focus_sampler.sample,u,v)
        if not called or type(distance)~='number'or distance~=distance or distance<=0 or distance==math.huge then
            focus_message(prefix..': '..tostring(called and why or distance or 'No scene depth'));return false
        end
        local control=controls.focus_distance;local minimum=control and control.min or .1;local maximum=control and control.max or 200
        distance=math.max(minimum,math.min(maximum,math.floor(distance*1000+.5)/1000))
        local success=true;local reason
        if math.abs((handle.get('focus_distance')or 0)-distance)>=.0005 then
            autofocus_write=true;local invoked,result,err=pcall(handle.set,'focus_distance',distance);autofocus_write=false
            success=invoked and result~=false;reason=invoked and err or result
        end
        if not success then focus_message(prefix..': '..tostring(reason));return false end
        if photo.options then photo.options.focus_distance=distance end
        self._remember_light_subject(u,v,distance)
        focus_message(prefix..': '..string.format('%.3f m',distance));return true
    end
    local function subject_click(input,w,h,time)
        if not input or not panel.contains_pointer or not subject_ready then
            subject_pair=nil;subject_held=input and input.click or nil;subject_ready=input~=nil;return
        end
        local pressed=input.click and not subject_held;subject_held=input.click
        local x,y=input.x,input.y
        if type(x)~='number'or type(y)~='number'or x~=x or y~=y or w<=0 or h<=0 or x<0 or x>w or y<0 or y>h or panel.contains_pointer(x,y)then subject_pair=nil;return end
        if subject_pair and(time<subject_pair.time or time-subject_pair.time>.35)then subject_pair=nil end
        if not pressed then return end
        local prior=subject_pair
        if prior and(x-prior.x)^2+(y-prior.y)^2<=64 then
            subject_pair=nil
            -- Native menu coordinates use bottom-left; scene depth uses top-left.
            sample_focus(x/w,1-y/h,'Subject focus')
        else subject_pair={x=x,y=y,time=time}end
    end
    function self.stop(preserve_resume)
        self._pending_start=nil
        self._native_menu_yield=nil
        local time_waiting=self._pose_time_pending;self._pose_time_pending=nil
        -- Bone leases are restored only by the owning update. Keep the paused
        -- camera/input ownership until that update acknowledges restoration.
        if self._poses and(self._poses.active or self._poses.pending or self._pose_stop_pending)then
            local waiting=self._pose_stop_pending or{preserve_resume=preserve_resume,queued=time_waiting and time_waiting.queued}
            if not preserve_resume then waiting.preserve_resume=nil end
            if not waiting.queued then
                local called,ok,why=pcall(self._poses.release)
                waiting.queued=called and ok~=false
                if not waiting.queued then log('Subject pose cleanup queued: '..tostring(called and why or ok))end
            end
            if self._poses.active or self._poses.pending then
                self._pose_stop_pending=waiting;photo.input={}
                if screenshots then screenshots.cancel()end
                return false,self._poses.status or'Subject pose restoration is waiting for an update'
            end
        end
        self._pose_stop_pending=nil
        self._light_subject=nil;if self._light_gizmos then self._light_gizmos.cancel()end
        clear_subject_click();focus_deadline=0;focus_mode_seen=nil;screenshot_edge=false
        if focus_sampler and focus_sampler.release then local ok,why=pcall(focus_sampler.release);if not ok then log('Auto-focus cleanup: '..tostring(why))end end
        if screenshots then screenshots.cancel()end
        if lights and(lights.count()>0 or lights.pending)then lights.queue('release','photo mode exited')end
        if subject and(subject.count()>0 or subject.pending)then subject.queue(nil)end
        if not preserve_resume then resume_after=nil end
        if roll_value and handle then handle.set('roll',roll_value);roll_value=nil end
        photo.active,photo.pos,photo.locked,photo.lock_pose=false,nil,false,nil
        photo.input={};photo.view=nil;photo.light_context=nil;suppress_escape=nil;menu_focus=false;controls_hidden=false;recovery_menu=false
        self._panel_close_pending=nil
        if panel then
            local called,ok,why=pcall(panel.close)
            if not called or ok==false then self._panel_close_pending=tostring(called and why or ok);log('Photo menu cleanup pending: '..self._panel_close_pending)end
        end
        local restored,reason=true,nil
        if effects then restored,reason=effects.release() end
        if freeze then local ok,why;if self.slowmo_active and handle then ok,why=freeze.start(handle.get('slowmo_speed'))else ok,why=freeze.release()end;if not ok then self.slowmo_active=false;freeze.release();restored,reason=false,why end end
        if freeze and freeze.needs_input_capture and freeze.needs_input_capture()then
            return false,reason or'Gameplay time restoration is pending; retaining input capture'
        end
        if provider then
            local ok,why=self._release_input()
            if ok==false then return false,why end
        end
        if self._panel_close_pending then return false,self._panel_close_pending end
        return restored,reason
    end
    local function bindings()
        local keys={}
        for _,name in ipairs({'forward','back','left','right','up','down'}) do keys[name]=handle.get(name..'_key') end
        keys.screenshot=handle.get('screenshot_key')
        return keys
    end
    local function key_down(key)
        local down=api.camera_input.down(key)
        if panel and panel.bound_key==key then
            if down then return false end;panel.bound_key=nil
        end
        return down
    end
    local function game_chat_active()
        -- The input service supplies an authoritative game text-entry reader.
        -- Physical keys and window foreground state do not identify chat.
        local reader=api and api.camera_input and api.camera_input.chat_active
        if type(reader)~='function'then return false end
        local ok,active=pcall(reader);return ok and active==true
    end
    function self.request_screenshot()
        if not photo.active or not screenshots then return false,'Open Photo Mode first'end
        if self._native_menu_state()or self._native_menu_yield then return false,'Close the native Escape/settings menu first'end
        clear_subject_click()
        local called,ok,why=pcall(screenshots.request)
        if not called or ok==false then local reason=called and why or ok;log('Screenshot: '..tostring(reason));return false,reason end
        return true
    end
    local function set_hidden(hidden)
        if hidden then clear_subject_click()end
        controls_hidden=hidden
        return handle.set('hide_controls',hidden)
    end
    local function switch_focus()
        clear_subject_click()
        local next_focus=not menu_focus
        if panel and not next_focus then
            if panel.blur then
                local ok,why=panel.blur();if ok==false then if why then log(tostring(why))end;return false end
            elseif panel.editing_text and panel.editing_text()then return false
            else panel.dismiss()end
        end
        menu_focus=next_focus;controls_hidden=false
        if provider and provider.set_focus then local ok,why=provider.set_focus(menu_focus);if not ok then log(tostring(why))end end
        return true
    end
    function self._start_camera()
        local input=api.camera_input
        local token,why=input.acquire(bindings())
        if not token then self.stop();return false,why end
        provider=input;photo.active,photo.pos=true,nil;controls_hidden=false
        if subject then subject_change()end;director_elapsed=.5;ai_elapsed=.5
        if saved_camera then saved_camera.restore(handle.get('saved_camera_radius'),handle)end
        focus_edge=input.down(handle.get('focus_key'));hide_edge=input.down(handle.get('hide_controls_key'));lock_edge=input.down(handle.get('lock_camera_key'));screenshot_edge=input.down(handle.get('screenshot_key'))
        if freeze and handle.get('freeze_player') and (not input.pause_allowed or input.pause_allowed()) then local ok,why=freeze.start();if why then log(why)end;if ok==false then self.stop();return false,why end end
        log('freecam: on');return true
    end
    function self._input_epoch()
        if not update_epoch then return self._input_tick end
        local ok,value=pcall(update_epoch);return ok and type(value)=='number'and value==value and value or nil
    end
    local function toggle(reveal_hidden)
        if self._native_menu_state()then return false,'Close the native Escape/settings menu first'end
        if self._pending_start then return self.stop()end
        if recovery_menu then
            local start=handle and handle.get('enabled')
            local ok,why=self.stop();if ok==false or not start then return ok,why end
        end
        if photo.active then
            if reveal_hidden and controls_hidden then controls_hidden=false;return true end
            return self.stop()
        end
        if not handle then return false,'Camera is unavailable'end
        if not handle.get('enabled')then
            -- Standalone has no separate settings host. P recovers its Controls
            -- panel without enabling, moving or pausing the camera.
            if reveal_hidden and api.photo_standalone and panel then
                local input=api.camera_input;local token,why=input.acquire(bindings())
                if not token then return false,why end
                provider=input;local ok,err=input.set_focus(true)
                if ok==false then self.stop();return false,err end
                recovery_menu=true;menu_focus=true;controls_hidden=false
                local controls_page=1;for index,page in ipairs(panel.pages or{})do if page.id=='camera'then controls_page=index;break end end
                panel.page,panel.selection,panel.scroll=controls_page,1,0;escape_edge=input.down(27)
                return true
            end
            return false,'Freecam is disabled; enable it in MCM'
        end
        if not can_start()then return false,'Camera is unavailable'end
        local input=api.camera_input
        if not input then return false,'Install the MCM freecam input candidate first' end
        local preparing=freeze and freeze.prepare and handle.get('freeze_player')and(not input.pause_allowed or input.pause_allowed())
        if not preparing then return self._start_camera()end
        -- Preserve held gameplay actions, including ADS. Only active hover
        -- needs an unpaused engine update to qualify its data-only pause guard.
        self.slowmo_active=false
        local restored,problem=freeze.release();if restored==false then return false,problem end
        local prepared,reason=freeze.prepare()
        if prepared~=true then self.stop();return false,reason end
        local needs_update=freeze.input_release_required and freeze.input_release_required()
        if not needs_update then return self._start_camera()end
        local before=self._input_epoch();if before==nil then self.stop();return false,'Gameplay update proof is unavailable'end
        self._pending_start={epoch=before,tick=self._input_tick,frames=0,elapsed=0,input=input,handle=handle,hover=true}
        return true
    end
    local function inform_toggle(reveal_hidden) if self._external_menu_open() then local closed,why=api.close();if closed==false then log(tostring(why));return end end;local ok,why=toggle(reveal_hidden);if ok==false then log('freecam: '..tostring(why)) end end
    function self.tick(dt)
        self._input_tick=self._input_tick+1
        if self._pose_stop_pending then
            self.stop(self._pose_stop_pending.preserve_resume)
            return
        end
        if self._pose_time_pending then
            local ok,why=self._request_time_change(self._pose_time_pending.rate)
            if ok==false then self.slowmo_active=false;log('Simulation time: '..tostring(why))end
        end
        local current=rawget(_G,'DBF_PHOTO_CAMERA_API')or rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
        if current~=api then
            self.slowmo_active=false
            local ok,why=self.stop();if ok==false then error(why) end
            if handle then handle.unregister();handle=nil end
            api=current;held=true;retry=0
        end
        retry=retry-math.max(0,tonumber(dt) or 0)
        if api and not handle and retry<=0 then
            retry=2
            local definition={id='dbf_freecam',name='Photo Mode',pages={{id='camera',name='Controls',require_confirmation=false,controls={
                {id='enabled',type='toggle',label='Enable freecam',default=true,on_change=function(v)if not v then self.stop()end end},
                {id='toggle_key',type='keybind',label='Photo mode toggle',default=80},
                {id='speed',type='slider',label='Movement speed (m/s)',default=3,min=0.1,max=50,step=0.1},
                {id='wheel_step',type='slider',label='Wheel speed change (%)',default=20,min=5,max=100,step=5},
                {id='toggle',type='button',label='Start / stop freecam',on_activate=inform_toggle},
                {id='forward_key',type='keybind',label='Move forward',default=87},
                {id='back_key',type='keybind',label='Move backward',default=83},
                {id='left_key',type='keybind',label='Move left',default=65},
                {id='right_key',type='keybind',label='Move right',default=68},
                {id='up_key',type='keybind',label='Move up',default=16},
                {id='down_key',type='keybind',label='Move down',default=17},
                {id='roll_left_key',type='keybind',label='Roll left',default=81},
                {id='roll_right_key',type='keybind',label='Roll right',default=69},
                {id='roll_speed',type='slider',label='Roll speed (degrees/s)',default=45,min=1,max=180,step=1},
                {id='freeze_player',type='toggle',label='Pause entire action (solo)',default=true,on_change=function(v)if not v then self._request_time_change(nil)end end},
                {id='look_sensitivity',type='slider',label='Camera look sensitivity',default=0.15,min=0.01,max=1,step=0.01},
                {id='focus_key',type='keybind',label='Switch camera / menu focus',default=9},
                {id='hide_controls_key',type='keybind',label='Show / hide photo controls',default=72},
                {id='lock_camera_key',type='keybind',label='Lock / unlock camera',default=76},
                {id='slowmo_key',type='keybind',label='Prototype slow-motion toggle (solo)',default=220},
                {id='slowmo_speed',type='slider',label='Prototype simulation speed',default=0.2,min=0.05,max=1,step=0.05},
                {id='screenshot_key',type='keybind',label='Screenshot key',default=19},
                {id='controls',type='text',label='Defaults: P toggles | WASD moves | Shift/Ctrl rise/descend | Q/E roll | Wheel: speed | L: lock camera | Backslash: slow motion | Escape: exit'},
            }}}}
            if options then
                local bindings_page=definition.pages[1];local kept={};local camera_controls={};local moved={}
                for _,id in ipairs({'speed','wheel_step','look_sensitivity','roll_speed','freeze_player','slowmo_speed'})do moved[id]=true end
                for _,control in ipairs(bindings_page.controls)do if moved[control.id]then moved[control.id]=control else kept[#kept+1]=control end end
                for _,id in ipairs({'speed','wheel_step','look_sensitivity','roll_speed','freeze_player','slowmo_speed'})do camera_controls[#camera_controls+1]=moved[id]end
                bindings_page.controls=kept
                local pages=options.pages(function()options.reset(handle,controls)end,function()
                    if saved_camera then saved_camera.clear('returned to player')end
                    local was_active=photo.active;local ok,why=self.stop();if not ok then log(tostring(why));return end
                    if was_active then resume_after=.1 end
                end,catalog,{
                    camera_controls=camera_controls,
                    lens_change=lens_change,
                    light_change=light_change,
                    light_add=lights and function()light_request('create',light_values())end,
                    light_place=lights and function()light_request('place_at_camera')end,
                    light_aim=lights and self._light_aim,
                    light_apply_preset=lights and self._light_preset,
                    light_setup_save=lights and function()self._light_setup('save')end,
                    light_setup_recall=lights and function()self._light_setup('recall')end,
                    light_setup_clear=lights and function()self._light_setup('clear')end,
                    light_remove=lights and function()light_request('remove')end,
                    light_clear=lights and function()light_request('release','removed manually')end,
                    subject_change=subject_change,
                    subject_pose_play=self._poses and function()return self._pose_action(false)end,
                    subject_pose_stop=self._poses and function()return self._pose_action(true)end,
                    subject_pose_change=self._poses and function()return self._pose_action(false)end,
                    ai_change=self._ai_change,
                    ai_reset=self._reset_ai,
                    director_save=director and function()director_action('save')end,
                    director_recall=director and function()director_action('recall')end,
                    director_clear=director and function()director_action('clear')end,
                    save=saved_camera and function()local ok,why=saved_camera.save(handle.get('saved_camera_radius'));if not ok then log(tostring(why))end end,
                    clear=saved_camera and function()saved_camera.clear('cleared manually')end,
                    screenshot=screenshots and function()self.request_screenshot()end})
                definition.pages={};for _,page in ipairs(pages)do definition.pages[#definition.pages+1]=page end
                definition.pages[#definition.pages+1]=bindings_page
            end
            for _,page in ipairs(definition.pages)do for _,control in ipairs(page.controls)do
                if control.type=='slider'then control.commit_on_blur=true end
                if control.id=='hide_controls'then
                    local previous=control.on_change
                    control.on_change=function(value)controls_hidden=value;if previous then previous(value)end end
                end
                controls[control.id]=control
            end end
            handle=api.register(definition)
            local stored_set=handle.set
            handle.set=function(key,value)
                local ok,why=stored_set(key,value)
                if key=='hide_controls'and ok~=false then controls_hidden=value end
                if key=='focus_distance'and not autofocus_write and ok~=false then
                    self._light_subject=nil
                    -- Typed values, slider drags and manual A/D edits take
                    -- priority over any automatic focus mode, including MCM.
                    if controls.focus_mode then stored_set('focus_mode',1)end;clear_subject_click();focus_deadline=0
                    focus_message('Manual focus: '..string.format('%.3f m',handle.get('focus_distance')))
                elseif key=='focus_mode'and ok~=false then
                    focus_deadline=0;clear_subject_click()
                elseif key=='hide_controls'and value and ok~=false then clear_subject_click()end
                return ok,why
            end
            if api.mods and api.mods.dbf_freecam then
                -- Text/status controls live on pages, outside MCM's stored/action index.
                controls={};for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id then controls[control.id]=control end end end
            end
            -- Session behavior survives Photo exit, but starts Normal after restart.
            self._set_ai_value(ai_requested)
            if not menu_startup_reset and options and options.reset_menu then
                local ok,why=options.reset_menu(handle);menu_startup_reset=true
                if ok==false then log('Photo menu startup reset: '..tostring(why))end
            end
            if menu_factory and api.create_photo_view then
                panel=menu_factory.new(api.create_photo_view(),{
                    focus=switch_focus,
                    hide=function()if recovery_menu then self.stop();return end;set_hidden(true);menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end,
                    hud=function()handle.set('hide_hud',not handle.get('hide_hud'))end,
                    exit=function()self.stop()end})
                panel.light_gizmos=self._light_gizmos;panel.prepare_light_gizmos=self._sync_light_gizmos
                local pages=api.mods and api.mods.dbf_freecam.pages or definition.pages
                local visible={}
                for _,page in ipairs(pages)do if page.id~='camera'or api.photo_standalone then local q={id=page.id,name=page.name,controls={}}
                    for _,control in ipairs(page.controls)do
                        if control.type~='keybind'or api.photo_standalone then q.controls[#q.controls+1]=control end
                    end
                    visible[#visible+1]=q
                end end
                -- Visibility belongs to this photo session. Fresh entry and P
                -- reveal recover it, while startup resets the saved UI layout once.
                local panel_handle={};for key,value in pairs(handle)do panel_handle[key]=value end
                panel_handle.get=function(key)if key=='hide_controls'then return controls_hidden end;return handle.get(key)end
                panel_handle.set=function(key,value)if key=='hide_controls'then return set_hidden(value)end;return handle.set(key,value)end
                panel.bind(panel_handle,visible)
            end
        end
        if not handle or not api.camera_input then self.stop();return end
        self._native_menu_blocked=self._native_menu_state()
        if self._native_menu_yield then
            local waiting=self._native_menu_yield;waiting.elapsed=waiting.elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
            if self._native_menu_blocked then waiting.seen=true
            elseif not key_down(27)and(waiting.seen or waiting.elapsed>=.75)then self._native_menu_yield=nil end
        end
        if saved_camera then
            local radius=handle.get('saved_camera_radius');saved_camera.hold(radius)
            if controls.saved_camera_status then controls.saved_camera_status.label=saved_camera.status(radius)end
        end
        local editing=panel and(panel.editing_key()or(panel.editing_text and panel.editing_text()))
        local key=key_down(handle.get('toggle_key'))
        if key and not held and not self._external_menu_open() and not editing then
            local opening=not self._pending_start and(not photo.active and not recovery_menu or photo.active and controls_hidden)
            if not(opening and game_chat_active())then inform_toggle(true)end
        end
        held=key
        local screenshot_key=key_down(handle.get('screenshot_key'))
        if screenshot_key and not screenshot_edge and photo.active and not recovery_menu and provider and api.camera_input.focused()and not self._external_menu_open()and not editing and not game_chat_active()and screenshots and not screenshots.active()then self.request_screenshot()end
        screenshot_edge=screenshot_key
        local slow_key=key_down(handle.get('slowmo_key'))
        if slow_key and not slow_edge and not editing and not self._external_menu_open()and freeze and not self._pending_start then
            self.slowmo_active=not self.slowmo_active
            local rate=self.slowmo_active and handle.get('slowmo_speed')or (photo.active and handle.get('freeze_player')and 0 or nil)
            local ok,why=self._request_time_change(rate)
            if not ok then self.slowmo_active=false;log('Slow motion: '..tostring(why))end
        end
        slow_edge=slow_key
        if self.slowmo_active and freeze then
            local ok,why=freeze.hold();if not ok then self.slowmo_active=false;log(tostring(why))end
        end
        if resume_after then
            resume_after=resume_after-math.max(.001,tonumber(dt)or 0)
            if resume_after<=0 and not self._external_menu_open()then resume_after=nil;local ok,why=toggle();if not ok then log(tostring(why))end end
        end
        if recovery_menu then
            if self._native_menu_blocked then
                clear_subject_click();if panel.suspend then panel.suspend()end
                local ok,why=self._release_input();if ok==false and why then log(tostring(why))end
                escape_edge=key_down(27);photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return
            end
            if not api.camera_input.focused()then
                if panel.suspend then panel.suspend()end
                if provider then local ok,why=self._release_input();if ok==false and why then log(tostring(why))end end
                return
            end
            if not provider then
                local token=api.camera_input.acquire(bindings());if not token then return end;provider=api.camera_input
                local ok,why=provider.set_focus(true);if ok==false then self.stop();if why then log(tostring(why))end;return end
            end
            local w,h=api.photo_resolution()
            local function label(v)return v==220 and '\\'or v==9 and 'TAB'or v>=32 and v<=126 and string.char(v)or('VK '..v)end
            panel.draw(w,h,true,false,{focus=label(handle.get('focus_key')),hide=label(handle.get('hide_controls_key')),slowmo=label(handle.get('slowmo_key'))})
            local escape=key_down(27)
            if escape and not escape_edge and not panel.editing_key()then
                if not panel.dismiss()then self.stop()end
            else panel.tick(provider.menu_sample(),provider.down)end
            escape_edge=escape;photo.input={};return
        end
        if self._pending_start then
            local waiting=self._pending_start
            waiting.frames=waiting.frames+1;waiting.elapsed=waiting.elapsed+math.max(.001,math.min(.1,tonumber(dt)or 0))
            if waiting.input~=api.camera_input or waiting.handle~=handle or not handle.get('enabled')or not can_start()or not api.camera_input.focused()or self._external_menu_open()or game_chat_active()or key_down(27)then self.stop();return end
            local current=self._input_epoch()
            if self._input_tick>waiting.tick and current and current>waiting.epoch then
                local called,ready,why=pcall(freeze.ready)
                waiting.reason=called and why or ready
                if called and ready==true then
                    self._pending_start=nil;local ok,problem=self._start_camera();if ok==false then log('freecam: '..tostring(problem))end
                elseif not called then
                    self.stop();log('freecam: hover pause could not be verified: '..tostring(ready));return
                end
            end
            if self._pending_start then
                if waiting.frames>=120 or waiting.elapsed>=.5 then self.stop();log('freecam: '..tostring(waiting.reason or'timed out waiting for a neutral hover control and unpaused gameplay update'))end
                photo.input={};return
            end
        end
        if not photo.active then self.stop(true);return end
        if not handle.get('enabled') or not can_start() then self.stop();return end
        if self._native_menu_blocked or self._native_menu_yield then
            clear_subject_click();if screenshots then screenshots.cancel()end
            if panel and panel.suspend then panel.suspend()end
            focus_edge=key_down(handle.get('focus_key'));hide_edge=key_down(handle.get('hide_controls_key'));lock_edge=key_down(handle.get('lock_camera_key'));escape_edge=key_down(27)
            suppress_escape=true
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
            if freeze and freeze.needs_input_capture and freeze.needs_input_capture()then
                self.slowmo_active=false;self.stop();log('Photo pause ended before native menu input handoff');return
            end
            local ok,why=self._release_input();if ok==false and why then log(tostring(why))end
            return
        end
        refresh_lens()
        refresh_lights()
        self._refresh_poses(dt)
        refresh_subject_director(dt)
        self._refresh_ai(dt)
        local lock_key=key_down(handle.get('lock_camera_key'))
        if lock_key and not lock_edge and not editing and not self._external_menu_open()then handle.set('lock_camera',not handle.get('lock_camera'))end
        lock_edge=lock_key
        local focus_key=key_down(handle.get('focus_key'))
        local hide_key=key_down(handle.get('hide_controls_key'))
        if panel and focus_key and not focus_edge and not self._external_menu_open()and not panel.editing_key()and(not editing or (panel.editing_text and panel.editing_text()and panel.blur))then
            if menu_focus or not game_chat_active()then switch_focus()end
        end
        if panel and hide_key and not hide_edge and not editing then
            if not controls_hidden or not game_chat_active()then
                local hidden=not controls_hidden;set_hidden(hidden)
                if hidden then menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end
            end
        end
        focus_edge,hide_edge=focus_key,hide_key
        if menu_focus and controls_hidden then menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end
        if options then photo.options=options.read(handle);photo.options.hide_controls=controls_hidden;if roll_value then photo.options.roll=roll_value end end
        local capturing=screenshots and screenshots.active()
        if capturing and photo.options then photo.options.hide_hud=true;photo.options.grid=1 end
        if panel then panel.warming_up_scene=effects and effects.warming_up_scene==true or false end
        if effects then
            if controls.known_issues then
                controls.known_issues.label=effects.native_dof_ready==true and 'Native focus and aperture active.' or
                    effects.native_dof_candidate==true and 'Native lens source waiting; Shader preview remains available.' or
                    'Manual native focus/aperture unavailable; use Shader preview.'
            end
            for _,entry in ipairs({{'lens_status','lens_status'},{'color_status','color_status'},{'shader_status','shader_status'},{'scene_status','scene_status'}})do
                if controls[entry[1]]and effects[entry[2]]then controls[entry[1]].label=effects[entry[2]]end
            end
            local profile=rawget(_G,'DBF_PHOTO_RENDER_PROFILE');local parameters=profile and profile.parameters or effects.parameters
            for _,key in ipairs({'dof','focus_distance','aperture','exposure','saturation','contrast','bloom','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do
                if controls[key]then
                    if key=='focus_distance'or key=='aperture'then
                        controls[key].disabled=not(((effects.custom_dof_candidate==true and effects.custom_dof_ready==true)or(effects.native_dof_candidate==true and effects.native_dof_ready==true))and effects.parameters and effects.parameters[key])
                    elseif key=='dof'and effects.custom_dof_candidate==true and effects.custom_dof_ready==true then
                        controls[key].disabled=not(effects.parameters and effects.parameters[key])
                    else controls[key].disabled=not(parameters and parameters[key])end
                end
            end
            for _,key in ipairs({'dof_quality','dof_strength','bokeh_shape'})do
                if controls[key]then controls[key].disabled=not(handle.get('dof_mode')==2 and effects.custom_dof_candidate==true and effects.custom_dof_ready==true)end
            end
        end
        local focus_available=focus_sampler and type(focus_sampler.sample)=='function'and controls.focus_distance and not controls.focus_distance.disabled
        -- Manual remains selectable when depth/lens support is temporarily
        -- unavailable; automatic modes report waiting instead of trapping it.
        if controls.focus_mode then controls.focus_mode.disabled=false end
        if freeze then
            local ok,why=freeze.hold();if ok==false then self.stop();if why then log(why)end;return end
        end
        -- A hover pause depends on continuous gameplay input suppression. Resume
        -- before handing off or releasing that input lease, including focus loss.
        if freeze and freeze.needs_input_capture and freeze.needs_input_capture()and(self._external_menu_open()or not api.camera_input.focused()or not provider)then
            self.slowmo_active=false;self.stop();log('Photo pause ended before gameplay input capture was released');return
        end
        -- Other pauses may retain their existing MCM/focus handoff behavior.
        if self._external_menu_open()then
            clear_subject_click()
            if screenshots then screenshots.cancel()end
            if panel then panel.close()end
            suppress_escape=true
            if provider then local ok,why=self._release_input();if not ok then log(tostring(why));return end end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
            return
        end
        if not api.camera_input.focused()then
            clear_subject_click()
            if screenshots then screenshots.cancel()end
            if panel and panel.suspend then panel.suspend()end
            if provider then local ok,why=self._release_input();if ok==false and why then log(tostring(why))end end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
            return -- Focus loss releases input, never the solo simulation pause.
        end
        if not provider then
            local token=api.camera_input.acquire(bindings());if not token then return end;provider=api.camera_input
            if provider.set_focus and menu_focus then provider.set_focus(true)end
        end
        local focus_mode=controls.focus_mode and handle.get('focus_mode')or 1
        if capturing or controls_hidden or not menu_focus or not focus_available or editing or focus_mode~=2 then clear_subject_click()end
        focus_elapsed=focus_elapsed+math.max(0,tonumber(dt)or 0)
        local timer=focus_sampler and focus_sampler.now or provider.now;local time=focus_elapsed
        if timer then local ok,value=pcall(timer);if ok and type(value)=='number'and value==value and math.abs(value)<math.huge then time=value end end
        if focus_mode~=focus_mode_seen then focus_mode_seen=focus_mode;focus_deadline=0
            clear_subject_click()
            if focus_mode==1 then focus_message('Manual focus: '..string.format('%.3f m',controls.focus_distance and handle.get('focus_distance')or 5))
            elseif focus_mode==2 then focus_message('Double-click a scene subject to lock focus.')end
        end
        if controls.focus_hint then
            local key=handle.get('focus_key');local label=key==9 and 'TAB'or key>=32 and key<=126 and string.char(key)or('VK '..key)
            controls.focus_hint.label=focus_mode==2 and(menu_focus and 'Double-click a scene subject. Hold Shift for 0.001 m focus steps.'or 'Press '..label..' for the cursor, then double-click a scene subject.')or 'Hold Shift for 0.001 m focus steps.'
        end
        if focus_mode==2 and not focus_available then focus_message('Subject focus: waiting for scene depth')end
        if focus_mode==3 and not focus_available then focus_message('Center focus: waiting for scene depth')end
        if focus_mode==3 and focus_available and not capturing and not editing then
            if time>=focus_deadline then
                focus_deadline=time+math.max(.5,tonumber(focus_sampler.interval)or 1)
                sample_focus(.5,.5,'Center focus')
            end
        end
        if panel then
            local w,h=api.photo_resolution()
            local function label(v)return v==220 and '\\'or v==9 and 'TAB'or v>=32 and v<=126 and string.char(v)or ('VK '..v)end
            panel.draw(w,h,menu_focus,controls_hidden or capturing,{focus=label(handle.get('focus_key')),hide=label(handle.get('hide_controls_key')),slowmo=label(handle.get('slowmo_key'))})
            if capturing then
                provider.sample(bindings())
                photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
                local _,status=screenshots.tick();if status then panel.notice=status end;return
            end
            if menu_focus then
                local escape=key_down(27)
                if escape and not escape_edge and not panel.editing_key()then
                    clear_subject_click()
                    if not panel.dismiss()then menu_focus=false;provider.set_focus(false);suppress_escape=true end
                else
                    local input=provider.menu_sample()
                    local captured=panel.scene_tick and panel.scene_tick(input,provider.down)
                    if captured then clear_subject_click()
                    else
                        if focus_mode==2 and focus_available and not controls_hidden and not editing then subject_click(input,w,h,time)end
                        panel.tick(input,provider.down,true)
                    end
                end
                escape_edge=escape
                photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return
            end
        end
        if capturing then screenshots.tick();photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return end
        local sample=provider.sample(bindings())
        if not sample then
            local ok,why=self._release_input();if ok==false and why then log(tostring(why))end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return
        end
        if not sample.escape then suppress_escape=nil end
        if sample.escape and not suppress_escape then
            if type(provider.native_menu_active)=='function'then
                -- Yield the actual key to native UI without abandoning this
                -- Photo camera. Stack observation, not Escape, proves it open.
                self._native_menu_yield={elapsed=0,seen=false};suppress_escape=true
                photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
                if freeze and freeze.needs_input_capture and freeze.needs_input_capture()then
                    self.slowmo_active=false;self.stop();log('Photo pause ended before native Escape input handoff');return
                end
                local ok,why=self._release_input();if ok==false and why then log(tostring(why))end
                return
            end
            self.stop();return
        end
        if photo.options and photo.options.lock_camera then
            for _,key in ipairs({'forward','back','left','right','up','down'})do sample[key]=false end
            sample.mouse_x,sample.mouse_y=0,0
        end
        if not (photo.options and photo.options.lock_camera) then
            local direction=(key_down(handle.get('roll_right_key'))and 1 or 0)-(key_down(handle.get('roll_left_key'))and 1 or 0)
            if direction~=0 then
                local roll=(roll_value or handle.get('roll'))+direction*handle.get('roll_speed')*math.max(0,math.min(.1,tonumber(sample.dt)or 0))
                roll=(roll+180)%360-180
                roll_value=roll;if photo.options then photo.options.roll=roll end
            elseif roll_value then handle.set('roll',roll_value);roll_value=nil
            end
        end
        if sample.wheel~=0 then
            local speed=handle.get('speed')*(1+handle.get('wheel_step')/100)^(sample.wheel/120)
            speed=math.floor(math.max(0.1,math.min(50,speed))*10+0.5)/10
            handle.set('speed',speed)
        end
        settings.PHOTO_SPEED=handle.get('speed')
        photo.sample_sequence=(photo.sample_sequence or 0)+1
        sample.sequence=photo.sample_sequence;sample.sensitivity=handle.get('look_sensitivity')
        photo.input=sample
        photo.input.fast=false
    end
    function self.close()
        if saved_camera then saved_camera.clear('shutdown')end
        self.slowmo_active=false
        stop_ai()
        local ok,why=self.stop()
        if self._poses and(self._poses.pending or self._poses.active)then return false,self._poses.status or'Subject pose cleanup is waiting for an update'end
        if ai and(ai.pending or ai.count()>0)then
            if not ai.pending then ai.queue('normal')end
            return false,ai.status or'Enemy restoration is waiting for an update'
        end
        if lights then local cleared,reason=lights.release('loader disabled');if not cleared then return false,reason end end
        if subject then local called,cleared,reason=pcall(subject.release);if not called or cleared==false then return false,called and reason or cleared end end
        if ok==false then return false,why end
        if freeze and freeze.cleanup_pending and freeze.cleanup_pending()then return false,'Hover restoration is waiting for a resumed update'end
        if handle then handle.unregister();handle=nil end
        return true
    end
    function self.entry_pending()return self._pending_start~=nil end
    function self.pose_cleanup_pending()return self._pose_stop_pending~=nil or self._pose_time_pending~=nil end
    return self
end
return M

-- ActionCam photomode adapter. Camera placement stays owned by ActionCam.
local M={}
function M.new(photo,settings,can_start,log,freeze,options,effects,menu_factory,catalog,saved_camera,screenshots)
    local roll_value;local self={};local api,handle,provider;local held=true;local retry=0;local controls={};local resume_after;local suppress_escape;local panel;local menu_focus=false;local controls_hidden=false;local recovery_menu=false;local focus_edge=false;local hide_edge=false;local slow_edge=false;local lock_edge=false;local escape_edge=false
    function self.stop(preserve_resume)
        if screenshots then screenshots.cancel()end
        if not preserve_resume then resume_after=nil end
        if roll_value and handle then handle.set('roll',roll_value);roll_value=nil end
        photo.active,photo.pos,photo.locked,photo.lock_pose=false,nil,false,nil
        photo.input={};photo.view=nil;suppress_escape=nil;menu_focus=false;controls_hidden=false;recovery_menu=false
        if panel then panel.close()end
        local restored,reason=true,nil
        if effects then restored,reason=effects.release() end
        if freeze then local ok,why;if self.slowmo_active and handle then ok,why=freeze.start(handle.get('slowmo_speed'))else ok,why=freeze.release()end;if not ok then self.slowmo_active=false;freeze.release();restored,reason=false,why end end
        if provider then
            local ok,why=provider.release()
            if ok==false then return false,why end
            provider=nil
        end
        return restored,reason
    end
    local function bindings()
        local keys={}
        for _,name in ipairs({'forward','back','left','right','up','down'}) do keys[name]=handle.get(name..'_key') end
        return keys
    end
    local function key_down(key)
        local down=api.camera_input.down(key)
        if panel and panel.bound_key==key then
            if down then return false end;panel.bound_key=nil
        end
        return down
    end
    local function set_hidden(hidden)
        controls_hidden=hidden
        return handle.set('hide_controls',hidden)
    end
    local function switch_focus()
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
    local function toggle(reveal_hidden)
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
                panel.page,panel.selection,panel.scroll=1,1,0;escape_edge=input.down(27)
                return true
            end
            return false,'Freecam is disabled; enable it in MCM'
        end
        if not can_start()then return false,'Camera is unavailable'end
        local input=api.camera_input
        if not input then return false,'Install the MCM freecam input candidate first' end
        local token,why=input.acquire(bindings())
        if not token then return false,why end
        provider=input;photo.active,photo.pos=true,nil;controls_hidden=false
        if saved_camera then saved_camera.restore(handle.get('saved_camera_radius'),handle)end
        focus_edge=input.down(handle.get('focus_key'));hide_edge=input.down(handle.get('hide_controls_key'));lock_edge=input.down(handle.get('lock_camera_key'))
        if freeze and handle.get('freeze_player') and (not input.pause_allowed or input.pause_allowed()) then local ok,why=freeze.start();if why then log(why)end;if ok==false then self.stop();return false,why end end
        log('freecam: on');return true
    end
    local function inform_toggle(reveal_hidden) if api.is_open() then local closed,why=api.close();if closed==false then log(tostring(why));return end end;local ok,why=toggle(reveal_hidden);if ok==false then log('freecam: '..tostring(why)) end end
    function self.tick(dt)
        local current=rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API')
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
                {id='freeze_player',type='toggle',label='Pause entire action (solo)',default=true,on_change=function(v)if not v and freeze then freeze.release()end end},
                {id='look_sensitivity',type='slider',label='Camera look sensitivity',default=0.15,min=0.01,max=1,step=0.01},
                {id='focus_key',type='keybind',label='Switch camera / menu focus',default=9},
                {id='hide_controls_key',type='keybind',label='Show / hide photo controls',default=72},
                {id='lock_camera_key',type='keybind',label='Lock / unlock camera',default=76},
                {id='slowmo_key',type='keybind',label='Prototype slow-motion toggle (solo)',default=220},
                {id='slowmo_speed',type='slider',label='Prototype simulation speed',default=0.2,min=0.05,max=1,step=0.05},
                {id='controls',type='text',label='Defaults: P toggles | WASD moves | Shift/Ctrl rise/descend | Q/E roll | Wheel: speed | L: lock camera | Backslash: slow motion | Escape: exit'},
            }}}}
            if options then
                local pages=options.pages(function()options.reset(handle,controls)end,function()
                    if saved_camera then saved_camera.clear('returned to player')end
                    local was_active=photo.active;local ok,why=self.stop();if not ok then log(tostring(why));return end
                    if was_active then resume_after=.1 end
                end,catalog,{
                    save=saved_camera and function()local ok,why=saved_camera.save(handle.get('saved_camera_radius'));if not ok then log(tostring(why))end end,
                    clear=saved_camera and function()saved_camera.clear('cleared manually')end,
                    screenshot=screenshots and function()if photo.active then local ok,why=screenshots.request();if not ok then log(tostring(why))end end end})
                for _,page in ipairs(pages)do definition.pages[#definition.pages+1]=page end
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
                return ok,why
            end
            if api.mods and api.mods.dbf_freecam then
                -- Text/status controls live on pages, outside MCM's stored/action index.
                controls={};for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,control in ipairs(page.controls)do if control.id then controls[control.id]=control end end end
            end
            if menu_factory and api.create_photo_view then
                panel=menu_factory.new(api.create_photo_view(),{
                    focus=switch_focus,
                    hide=function()if recovery_menu then self.stop();return end;set_hidden(true);menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end,
                    hud=function()handle.set('hide_hud',not handle.get('hide_hud'))end,
                    exit=function()self.stop()end})
                local pages=api.mods and api.mods.dbf_freecam.pages or definition.pages
                local visible={}
                for _,page in ipairs(pages)do if page.id~='camera'or api.photo_standalone then local q={id=page.id,name=page.name,controls={}}
                    for _,control in ipairs(page.controls)do
                        if control.type~='keybind'or api.photo_standalone then q.controls[#q.controls+1]=control end
                    end
                    visible[#visible+1]=q
                end end
                -- Visibility belongs to this photo session. Preserve old saved hidden
                -- flags, while each fresh entry and P reveal starts with a visible UI.
                local panel_handle={};for key,value in pairs(handle)do panel_handle[key]=value end
                panel_handle.get=function(key)if key=='hide_controls'then return controls_hidden end;return handle.get(key)end
                panel_handle.set=function(key,value)if key=='hide_controls'then return set_hidden(value)end;return handle.set(key,value)end
                panel.bind(panel_handle,visible)
            end
        end
        if not handle or not api.camera_input then self.stop();return end
        if saved_camera then
            local radius=handle.get('saved_camera_radius');saved_camera.hold(radius)
            if controls.saved_camera_status then controls.saved_camera_status.label=saved_camera.status(radius)end
        end
        local editing=panel and(panel.editing_key()or(panel.editing_text and panel.editing_text()))
        local key=key_down(handle.get('toggle_key'))
        if key and not held and not api.is_open() and not editing then inform_toggle(true) end
        held=key
        local slow_key=key_down(handle.get('slowmo_key'))
        if slow_key and not slow_edge and not editing and not api.is_open()and freeze then
            self.slowmo_active=not self.slowmo_active
            local rate=self.slowmo_active and handle.get('slowmo_speed')or (photo.active and handle.get('freeze_player')and 0 or nil)
            local ok,why;if rate then ok,why=freeze.start(rate)else ok,why=freeze.release()end
            if not ok then self.slowmo_active=false;log('Slow motion: '..tostring(why))end
        end
        slow_edge=slow_key
        if self.slowmo_active and freeze then
            local ok,why=freeze.hold();if not ok then self.slowmo_active=false;log(tostring(why))end
        end
        if resume_after then
            resume_after=resume_after-math.max(.001,tonumber(dt)or 0)
            if resume_after<=0 and not api.is_open()then resume_after=nil;local ok,why=toggle();if not ok then log(tostring(why))end end
        end
        if recovery_menu then
            if not api.camera_input.focused()then
                if panel.suspend then panel.suspend()end
                if provider then local ok,why=provider.release();if ok then provider=nil elseif why then log(tostring(why))end end
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
        if not photo.active then self.stop(true);return end
        if not handle.get('enabled') or not can_start() then self.stop();return end
        local lock_key=key_down(handle.get('lock_camera_key'))
        if lock_key and not lock_edge and not editing and not api.is_open()then handle.set('lock_camera',not handle.get('lock_camera'))end
        lock_edge=lock_key
        local focus_key=key_down(handle.get('focus_key'))
        local hide_key=key_down(handle.get('hide_controls_key'))
        if panel and focus_key and not focus_edge and not api.is_open()and not panel.editing_key()and(not editing or (panel.editing_text and panel.editing_text()and panel.blur))then
            switch_focus()
        end
        if panel and hide_key and not hide_edge and not editing then
            local hidden=not controls_hidden;set_hidden(hidden)
            if hidden then menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end
        end
        focus_edge,hide_edge=focus_key,hide_key
        if menu_focus and controls_hidden then menu_focus=false;if provider and provider.set_focus then provider.set_focus(false)end end
        if options then photo.options=options.read(handle);photo.options.hide_controls=controls_hidden;if roll_value then photo.options.roll=roll_value end end
        local capturing=screenshots and screenshots.active()
        if capturing and photo.options then photo.options.hide_hud=true;photo.options.grid=1 end
        if effects then
            for _,entry in ipairs({{'lens_status','lens_status'},{'color_status','color_status'},{'shader_status','shader_status'},{'scene_status','scene_status'}})do
                if controls[entry[1]]and effects[entry[2]]then controls[entry[1]].label=effects[entry[2]]end
            end
            local profile=rawget(_G,'DBF_PHOTO_RENDER_PROFILE');local parameters=profile and profile.parameters or effects.parameters
            for _,key in ipairs({'dof','focus_distance','aperture','exposure','saturation','contrast','bloom','scene_shader','scene_strength','fog_distance','fog_density','scene_depth_range'})do
                if controls[key]then
                    if key=='focus_distance'or key=='aperture'then
                        controls[key].disabled=not(effects.custom_dof_candidate==true and effects.custom_dof_ready==true and effects.parameters and effects.parameters[key])
                    elseif key=='dof'and effects.custom_dof_candidate==true and effects.custom_dof_ready==true then
                        controls[key].disabled=not(effects.parameters and effects.parameters[key])
                    else controls[key].disabled=not(parameters and parameters[key])end
                end
            end
            for _,key in ipairs({'dof_quality','bokeh_shape'})do
                if controls[key]then controls[key].disabled=not(effects.custom_dof_candidate==true and effects.custom_dof_ready==true)end
            end
        end
        if freeze then
            local ok,why=freeze.hold();if ok==false then self.stop();if why then log(why)end;return end
        end
        -- MCM takes the input lease while the photo and solo pause stay active.
        if api.is_open()then
            if screenshots then screenshots.cancel()end
            if panel then panel.close()end
            suppress_escape=true
            if provider then local ok,why=provider.release();if not ok then log(tostring(why));return end;provider=nil end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
            return
        end
        if not api.camera_input.focused()then
            if screenshots then screenshots.cancel()end
            if panel and panel.suspend then panel.suspend()end
            if provider then local ok,why=provider.release();if ok then provider=nil elseif why then log(tostring(why))end end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0}
            return -- Focus loss releases input, never the solo simulation pause.
        end
        if not provider then
            local token=api.camera_input.acquire(bindings());if not token then return end;provider=api.camera_input
            if provider.set_focus and menu_focus then provider.set_focus(true)end
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
                    if not panel.dismiss()then menu_focus=false;provider.set_focus(false);suppress_escape=true end
                else panel.tick(provider.menu_sample(),provider.down)end
                escape_edge=escape
                photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return
            end
        end
        if capturing then screenshots.tick();photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return end
        local sample=provider.sample(bindings())
        if not sample then
            local ok,why=provider.release();if ok then provider=nil elseif why then log(tostring(why))end
            photo.input={sequence=photo.sample_sequence or 0,mouse_x=0,mouse_y=0,wheel=0,dt=0};return
        end
        if not sample.escape then suppress_escape=nil end
        if sample.escape and not suppress_escape then self.stop();return end
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
        local ok,why=self.stop();if ok==false then return false,why end
        if handle then handle.unregister();handle=nil end
        return true
    end
    return self
end
return M

-- Retained Stingray GUI with a loaded HUD face and stock-font fallback.
local M={}
function M.new(sr,preview_only,diagnostic_log,shared_fonts)
    local font_state=shared_fonts or {guis={}}
    local preview_guis={}
    local gui,world;local ids={};local G=sr.Gui;local self={};local reported=false
    local partial_cleanup=false
    local stable_commands,stable_token,stable_font,stable_gui,stable_text_guis
    local split_commands,split_token,split_menu,split_preview,split_popup
    local function forget_draw()
        stable_commands,stable_token,stable_font,stable_gui,stable_text_guis=nil,nil,nil,nil,nil
    end
    local function forget_all()
        forget_draw();split_commands,split_token,split_menu,split_preview,split_popup=nil,nil,nil,nil,nil
    end
    local preview_materials={}
    local preview_view=not preview_only and M.new(sr,true,diagnostic_log,font_state) or nil
    local popup_view=not preview_only and M.new(sr,true,nil,font_state) or nil
    local function live()for _,w in pairs(sr.Application.worlds() or {})do if w==world then return true end end;return false end
    local function positive(value)return type(value)=='number' and value>0 and value<math.huge end
    local function drawable()
        if type(G.resolution)~='function' then return true end
        local ok,w,h=pcall(G.resolution);return ok and positive(w) and positive(h)
    end
    local debug_font='core/performance_hud/debug'
    local font_source,active_font
    local metrics,vertical_metrics={},{}
    local metric_generation,metric_ready,vertical_count=0,false,0
    self.font_key=debug_font;self.metric_key=debug_font..'|0'
    local function reset_metrics()
        metrics={};vertical_metrics={};vertical_count=0;metric_generation=metric_generation+1
        self.metric_key=self.font_key..'|'..metric_generation
    end
    local function font_id()return active_font and sr.IdString64.from_hex(active_font.font) or debug_font end
    local function descriptor_key(descriptor)
        return descriptor and table.concat({descriptor.font,descriptor.material,descriptor.atlas},'|') or debug_font
    end
    local function bind_font(target_gui,descriptor)
        local ok,success=pcall(function()
            local queried,handle=pcall(G.material,target_gui,sr.IdString64.from_hex(descriptor.material))
            if not queried then handle=nil end
            -- material() queries an assigned GUI instance; a cold GUI has
            -- drawn only stock text. Assign the already loaded HUD material
            -- before binding its atlas, never an invisible seeding text draw.
            if not handle and type(G.create_material)=='function' then
                handle=G.create_material(target_gui,sr.IdString64.from_hex(descriptor.material))
            end
            if not handle then return false end
            return sr.Material.set_texture(handle,sr.IdString64.from_hex('88BAC99B00000000'),sr.IdString64.from_hex(descriptor.atlas))~=false
        end)
        if not ok or not success then
            local key=descriptor_key(descriptor)
            if font_state.failed_key~=key and diagnostic_log then diagnostic_log('MCM game font unavailable; using stock font')end
            font_state.failed_key=key;return false
        end
        return true
    end
    function self._accept_font(descriptor)
        local key=descriptor_key(descriptor);local changed=key~=self.font_key
        if changed then
            active_font=descriptor and {font=descriptor.font,material=descriptor.material,atlas=descriptor.atlas} or nil
            self.font_key=key;reset_metrics()
        end
        if preview_view then preview_view._accept_font(descriptor)end
        if popup_view then popup_view._accept_font(descriptor)end
        return changed
    end
    function self.set_font_source(source)
        font_source=source;font_state.failed_key=nil
        if preview_view then preview_view.set_font_source(source)end
        if popup_view then popup_view.set_font_source(source)end
    end
    -- Called once before composition: layout and every GUI plane share a
    -- frozen HEX descriptor, never a retained frame-local native ID.
    function self.refresh_font()
        if not drawable()then return false end
        local descriptor
        if font_source and type(font_source.resolve)=='function' then
            local ok,value=pcall(font_source.resolve,sr)
            local function valid_hex(v)return type(v)=='string' and #v==16 and v:match('^%x+$')end
            if ok and type(value)=='table' and valid_hex(value.font) and valid_hex(value.material) and valid_hex(value.atlas)
                and sr.IdString64 and type(sr.IdString64.from_hex)=='function' and type(G.material)=='function'
                and sr.Material and type(sr.Material.set_texture)=='function' then descriptor=value end
        end
        local ready=gui~=nil and live()
        -- Cold first paint uses stock metrics; only a warm, bound GUI adopts.
        if not ready then
            if gui then font_state.failed_key=nil end
            descriptor=nil
        elseif descriptor then
            local key=descriptor_key(descriptor)
            if font_state.failed_key==key then descriptor=nil else
                local worlds=sr.Application.worlds() or {}
                for owned,owned_world in pairs(font_state.guis)do
                    local alive=false;for _,w in pairs(worlds)do if w==owned_world then alive=true;break end end
                    if not alive then font_state.guis[owned]=nil
                    elseif not bind_font(owned,descriptor)then descriptor=nil;break end
                end
            end
        end
        local changed=self._accept_font(descriptor)
        if ready~=metric_ready then metric_ready=ready;reset_metrics();changed=true end
        return changed
    end
    function self.text_metrics(size,label)
        if not positive(size)then return {min_y=0,max_y=0,height=0,optical_y=0}end
        label=label or 'Ag0#';local key=tostring(size)..'|'..label
        if vertical_metrics[key]then return vertical_metrics[key]end
        local result={min_y=0,max_y=size,height=size,optical_y=0}
        if drawable() and gui and live() and type(G.text_extents)=='function' and label~='' then
            local ok,lo,hi=pcall(G.text_extents,gui,label,font_id(),size)
            if ok and lo and hi and type(lo.y)=='number' and type(hi.y)=='number'
                and lo.y==lo.y and hi.y==hi.y and hi.y>lo.y and hi.y-lo.y<size*3 then
                result={min_y=lo.y,max_y=hi.y,height=hi.y-lo.y,optical_y=active_font and -size*.12 or 0}
                if vertical_count>=512 then vertical_metrics={};vertical_count=0 end
                vertical_metrics[key]=result;vertical_count=vertical_count+1
            end
        end
        return result
    end
    function self.measure(value,size)
        if value=='' or not positive(size)then return 0 end
        local key=value..'|'..size;if metrics[key]then return metrics[key]end
        local count=0;for _ in value:gmatch('[%z\1-\127\194-\244][\128-\191]*')do count=count+1 end
        local width=size*.62*count
        if drawable() and gui and live() and type(G.text_extents)=='function' then
            local ok,native_width=pcall(function()
                local lo,hi=G.text_extents(gui,value,font_id(),size)
                return math.max(hi.x,hi.x-lo.x)
            end)
            if ok and type(native_width)=='number'and native_width<math.huge and (native_width>0 or (count==0 and native_width==0))then width=native_width;metrics[key]=width end
        end
        return width
    end
    local function destroy_item(item)
        if item.bold_id then pcall(G.destroy_text,item.gui or gui,item.bold_id)end
        pcall(G['destroy_'..item.type],item.gui or gui,item.id);if item.extra_id then pcall(G.destroy_triangle,item.gui or gui,item.extra_id)end
    end
    local function triangle_points(c)
        -- Solid GUI triangles use X/Z positions, unlike rectangles' X/Y.
        -- Absolute screen coordinates keep icons in the same physical plane.
        local p=c.points
        if type(p)~='table' or #p~=6 then return nil end
        for index=1,6 do local value=p[index]
            if type(value)~='number' or value~=value or math.abs(value)==math.huge then return nil end
        end
        return p
    end
    function self.clear()
        if partial_cleanup then return false,'Preview cleanup pending'end
        forget_all()
        if gui and live()then for _,item in ipairs(ids)do destroy_item(item)end end;ids={}
    end
    function self.release()
        forget_all()
        if preview_view then local ok,why=preview_view.release();if ok==false then return false,why end end
        if popup_view then local ok,why=popup_view.release();if ok==false then return false,why end end;reported=false
        if gui and live()then
            if not partial_cleanup then
                self.clear()
                -- Whole-GUI retirement is the final ownership acknowledgement,
                -- even when individual primitive deletion appeared successful.
                -- A refusal/throw must block drawing until an explicit retry.
                partial_cleanup=true
            end
            for role,g in pairs(preview_guis)do
                local called,ok=pcall(sr.World.destroy_gui,world,g)
                if not called or ok==false then return false,'Preview cleanup pending'end
                font_state.guis[g]=nil;preview_guis[role]=nil
            end
            local called,ok=pcall(sr.World.destroy_gui,world,gui)
            if not called or ok==false then return false,'Preview cleanup pending'end
        end
        for _,g in pairs(preview_guis)do font_state.guis[g]=nil end
        if gui then font_state.guis[gui]=nil end
        preview_guis={};ids={};gui,world=nil,nil;partial_cleanup=false;metric_ready=false;reset_metrics()
    end
    -- Retained primitives compare scalar fields directly: no per-frame serialization.
    local fields={'type','text','x','y','w','h','size','a','layer','font_resource','font_material','preview_material','preview_role','text_bold'}
    local vector_fields={'points','preview_uv'}
    local function same_command(old,c)
        if type(old)~='table' or old.font_key~=(c.type=='text'and self.font_key or nil)then return false end
        for _,key in ipairs(fields)do if old[key]~=c[key]then return false end end
        for i=1,3 do if old.color[i]~=c.c[i]then return false end end
        for _,key in ipairs(vector_fields)do
            local a,b=old[key],c[key]
            if (a==nil)~=(b==nil)then return false end
            if a then if #a~=#b then return false end;for i=1,#a do if a[i]~=b[i]then return false end end end
        end
        return true
    end
    local function command_signature(c)
        local result={color={c.c[1],c.c[2],c.c[3]},font_key=c.type=='text'and self.font_key or nil}
        for _,key in ipairs(fields)do result[key]=c[key]end
        for _,key in ipairs(vector_fields)do if c[key]then local copy={};for i,v in ipairs(c[key])do copy[i]=v end;result[key]=copy end end
        return result
    end
    local function command_gui(c)
        if not c.preview_role then return gui end
        preview_guis[c.preview_role]=preview_guis[c.preview_role] or sr.World.create_screen_gui(world,'scale',1,1)
        font_state.guis[preview_guis[c.preview_role]]=world
        return preview_guis[c.preview_role]
    end
    -- A non-nil token is an explicit caller promise that this command table and
    -- its contents remain immutable until the token changes. Mutable callers
    -- keep the ordinary scalar diff. Native font handles are never retained.
    function self.draw(commands,immutable_token)
        if partial_cleanup then return false,'Preview cleanup pending'end
        if not drawable()then return false end
        if preview_view then
            if immutable_token==nil or split_token~=immutable_token or split_commands~=commands then
                local menu,preview,popup={},{},{}
                for _,c in ipairs(commands)do
                    local destination=c.hud_preview and preview or (c.popup and popup or menu)
                    destination[#destination+1]=c
                end
                split_commands,split_token,split_menu,split_preview,split_popup=commands,immutable_token,menu,preview,popup
            end
            local ok,why=preview_view.draw(split_preview,immutable_token)
            if ok==false then return false,why end
            ok,why=popup_view.draw(split_popup,immutable_token)
            if ok==false then return false,why end
            commands=split_menu
        end
        if active_font and font_state.failed_key==descriptor_key(active_font)then return false end
        if #commands==0 then return self.release()end
        local gui_live=gui and live()
        local retained=immutable_token~=nil and stable_token==immutable_token and stable_commands==commands
            and stable_font==self.font_key and stable_gui==gui and gui_live
        -- Required previews never become solid-color fallback rectangles.
        -- Check before changing native ownership or allocating a replacement GUI.
        -- Immutable static previews rely on explicit resource invalidation while
        -- their normal world/GUI lifetime remains valid.
        if not retained then for _,c in ipairs(commands)do
            if c.preview_required and c.preview_material and not sr.Application.can_get('material',c.preview_material)then
                return false,'Required preview material unavailable'
            end
        end end
        if gui and not gui_live then
            forget_draw()
            font_state.guis[gui]=nil;for _,g in pairs(preview_guis)do font_state.guis[g]=nil end
            font_state.failed_key=nil;gui,world=nil,nil;ids={};preview_guis={};metric_ready=false;reset_metrics()
        end
        if not gui then
            forget_draw()
            local main=sr.Application.main_world();world=main
            for _,w in pairs(sr.Application.worlds() or {})do if w~=main then world=w;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1)
            font_state.guis[gui]=world
        end
        if retained then
            -- Preserve frame-local atlas/material binding even when unchanged
            -- geometry needs no scanning, signature allocation or submission.
            if active_font then for owned in pairs(stable_text_guis)do
                if not bind_font(owned,active_font)then forget_draw();return false end
            end end
            return true
        end
        forget_draw()
        -- Newly opened planes bind before replacing retained primitives.
        local prepared={}
        if active_font then for _,c in ipairs(commands)do if c.type=='text' and not c.font_resource then
            local owned=command_gui(c)
            if not prepared[owned]then if not bind_font(owned,active_font)then return false end;prepared[owned]=true end
        end end end
        local report_now=diagnostic_log and not reported
        local report,seen;if report_now then report,seen={},{}end
        local old_ids=ids;ids={};local uniforms={}
        local signatures={};local cacheable=immutable_token~=nil;local incomplete_preview=false
        for index,c in ipairs(commands)do
            -- Static previews opt into the same immutable-token promise as
            -- geometry. Existing animated/mutable previews keep refreshing.
            if c.preview_material and c.preview_static~=true then cacheable=false end
            -- Sidebar command counts must not change unrelated content depth.
            local z=(c.layer or 100)+(c.type=='text' and 1 or 0)
            local old=old_ids[index]
            signatures[index]=old and same_command(old.signature,c)and old.signature or command_signature(c)
        end
        -- Destroy all stale IDs before allocations: engines may reuse IDs immediately.
        for index,old in ipairs(old_ids)do
            if old.signature~=signatures[index] then
                destroy_item(old);old_ids[index]=false
            end
        end
        for index,c in ipairs(commands)do
            -- Sidebar command counts must not change unrelated content depth.
            local z=(c.layer or 100)+(c.type=='text' and 1 or 0)
            local signature=signatures[index]
            local target_gui=command_gui(c)
            local old=old_ids[index]
            -- Refresh uniforms for retained preview triangles on every draw.
            local uniform_key=(c.preview_role or '')..':'..(c.preview_material or '')
            if c.preview_material and not uniforms[uniform_key] and sr.Application.can_get('material',c.preview_material) then
                local handle=G.material(target_gui,c.preview_material)
                if handle then
                    sr.Material.set_scalar(handle,'scissor_mode',0)
                    sr.Material.set_scalar(handle,'threshold_fade',0)
                    if c.preview_mapping then
                        local r=c.preview_mapping
                        sr.Material.set_vector4(handle,'scissor_rect',sr.Vector4(r[1],r[2],r[3],c.preview_time or 0))
                        sr.Material.set_vector4(handle,'atlas_scissor',sr.Vector4(r[4],r[5],r[6],c.preview_animation or 0))
                        sr.Material.set_vector4(handle,'clip_box',sr.Vector4(r[7],r[8],r[9],0))
                    end
                    uniforms[uniform_key]=true
                end
            end
            if report_now and c.type=='text' and not c.diagnostic_console then report[#report+1]=string.format('%d z=%.2f label=%q',index,z,c.text or '')end
            if old and old.signature==signature then
                ids[#ids+1]=old
            else
            local color=sr.Color(math.floor(c.a*255+.5),c.c[1],c.c[2],c.c[3]);local value;local primitive_type=c.type;local extra_id,bold_id
            if c.type=='triangle' then
                local p=triangle_points(c)
                if p and type(G.triangle)=='function' then
                    value=G.triangle(target_gui,sr.Vector3(p[1],0,p[2]),sr.Vector3(p[3],0,p[4]),sr.Vector3(p[5],0,p[6]),z,color)
                end
            elseif c.type=='rect' and c.preview_material and type(G.triangle)=='function' and sr.Application.can_get('material',c.preview_material) then
                local handle=assert(G.material(target_gui,c.preview_material),'Preview material unavailable')
                sr.Material.set_scalar(handle,'scissor_mode',0);sr.Material.set_scalar(handle,'threshold_fade',0)
                local a=sr.Vector3(c.x,0,c.y);local b=sr.Vector3(c.x+c.w,0,c.y)
                local d=sr.Vector3(c.x+c.w,0,c.y+c.h);local e=sr.Vector3(c.x,0,c.y+c.h)
                local uv=c.preview_uv
                local ua=uv and sr.Vector2(uv[1],uv[4]) or nil;local ub=uv and sr.Vector2(uv[3],uv[4]) or nil
                local ud=uv and sr.Vector2(uv[3],uv[2]) or nil;local ue=uv and sr.Vector2(uv[1],uv[2]) or nil
                value=G.triangle(target_gui,a,b,d,z,color,c.preview_material,ua,ub,ud)
                extra_id=G.triangle(target_gui,a,d,e,z,color,c.preview_material,ua,ud,ue);primitive_type='triangle'
                if not value or not extra_id then
                    incomplete_preview=true;cacheable=false
                    local survivor=value or extra_id
                    if survivor then
                        local called,removed=pcall(G.destroy_triangle,target_gui,survivor)
                        if not called or removed==false then
                            value,extra_id=survivor,nil;partial_cleanup=true
                        else value,extra_id=nil,nil end
                    end
                end
                if diagnostic_log and not preview_materials[c.preview_material] then preview_materials[c.preview_material]=true;diagnostic_log('MCM_PREVIEW_SHADER material='..c.preview_material..' triangles='..tostring(value)..','..tostring(extra_id)..' bounds='..c.x..','..c.y..','..c.w..','..c.h)end
            elseif c.type=='rect' and c.preview_required then
                -- A late availability/primitive loss after preflight must
                -- still fail closed. The GUI remains owned for caller cleanup.
                error('Required preview material unavailable',0)
            elseif c.type=='rect' then value=G.rect(target_gui,sr.Vector3(c.x,c.y,z),sr.Vector2(c.w,c.h),color)
            else
                local font,material=font_id(),active_font and sr.IdString64.from_hex(active_font.material) or debug_font
                if c.font_resource then font,material=c.font_resource,c.font_material end
                value=G.text(target_gui,c.text,font,c.size,material,sr.Vector3(c.x,c.y,z),color)
                if c.text_bold then
                    if active_font and not c.font_resource then font,material=font_id(),sr.IdString64.from_hex(active_font.material)end
                    bold_id=G.text(target_gui,c.text,font,c.size,material,sr.Vector3(c.x+.65,c.y,z),color)
                end
            end
            if report_now and c.type=='text' and not c.diagnostic_console then report[#report]=report[#report]..' allocation='..tostring(value)end
            if value then ids[#ids+1]={type=primitive_type,id=value,extra_id=extra_id,bold_id=bold_id,signature=signature,gui=target_gui}else ids[#ids+1]={type=c.type,id=nil,signature=nil};cacheable=false end
            end
        end
        if report_now then
            local duplicate=0;for _,item in ipairs(ids)do local key=item.type..':'..tostring(item.id);if seen[key]then duplicate=duplicate+1 end;seen[key]=true end
            diagnostic_log('MCM TEXT DIAGNOSTIC primitives='..#commands..' duplicate_handles='..duplicate)
            for _,line in ipairs(report)do diagnostic_log('MCM TEXT '..line)end
            reported=true
        end
        if cacheable then
            stable_commands,stable_token,stable_font,stable_gui,stable_text_guis=commands,immutable_token,self.font_key,gui,prepared
        end
        if partial_cleanup then return false,'Preview cleanup pending'end
        if incomplete_preview then return false end
    end
    return self
end
return M

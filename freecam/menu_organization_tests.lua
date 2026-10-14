local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local options=dofile(root..'photo_options.lua')
local function index(pages)
 local controls,page_map,count={},{},0
 for _,page in ipairs(pages)do
  assert(not page_map[page.id],'Duplicate page ID: '..page.id);page_map[page.id]=page
  for _,control in ipairs(page.controls)do
   assert(type(control.id)=='string'and not controls[control.id],'Duplicate control ID: '..tostring(control.id))
   controls[control.id]={control=control,page=page.id};count=count+1
  end
 end
 return controls,page_map,count
end
local reset,recenter=function()end,function()end
local pages=options.pages(reset,recenter)
local controls,page_map,count=index(pages)
local original_ids=[[
screenshot lock_camera save_camera clear_saved_camera recenter saved_camera_radius saved_camera_status reset_photo
fov dof dof_mode focus_mode focus_distance aperture roll focus_status focus_hint focal_preset focal_length_status roll_preset dof_quality dof_strength bokeh_shape lens_status known_issues
color_status filter filter_strength exposure saturation contrast bloom
scene_status scene_shader scene_strength scene_depth_range fog_distance fog_density shader shader_opacity shader_scale shader_animate vignette vignette_width grain grain_size shader_status
light_add light_preset light_apply_preset light_preset_hint light_selected light_aim light_drag_hint light_enabled light_kind light_intensity light_color light_range light_cone light_right light_forward light_up light_follow light_place light_remove light_clear light_setup_slot light_setup_save light_setup_recall light_setup_clear light_setup_status light_status
frame grid logo logo_size logo_x logo_y logo_opacity logo_color clean_view hide_hud hide_controls show_legend legend_open legend_docked legend_tab_y legend_columns legend_x legend_y legend_size menu_x menu_y menu_scale menu_opacity
cinema_begin cinema_reposition cinema_end cinema_status cinema_hint ai_behavior ai_reset ai_status ai_hint ai_limits director_slot director_save director_recall director_clear director_status director_hint
subject_pose subject_pose_play subject_pose_stop subject_pose_status subject_pose_hint hide_player hide_armour hide_weapons subject_status subject_hint
]]
local expected_count=0;for id in original_ids:gmatch('%S+')do expected_count=expected_count+1;assert(controls[id],'Existing control lost: '..id)end
assert(count==expected_count,'Organization introduced a stored or action ID')
assert(controls.reset_photo.control.on_activate==reset and controls.recenter.control.on_activate==recenter)
assert(#pages==9 and pages[9].id=='camera'and pages[9].name=='Settings')
local expected_orders={
 lens={'dof','dof_mode','focus_mode','focus_distance','aperture','focus_status','focus_hint','focal_preset','fov','focal_length_status','roll','roll_preset','dof_strength','dof_quality','bokeh_shape','lens_status','known_issues'},
 color={'color_status','exposure','contrast','saturation','bloom','filter','filter_strength'},
 lighting={'light_selected','light_add','light_enabled','light_kind','light_intensity','light_color','light_range','light_cone','light_remove','light_clear','light_status','light_aim','light_place','light_follow','light_right','light_forward','light_up','light_drag_hint','light_preset','light_apply_preset','light_preset_hint','light_setup_slot','light_setup_recall','light_setup_save','light_setup_clear','light_setup_status'},
 composition={'frame','grid','clean_view','logo','logo_size','logo_x','logo_y','logo_opacity','logo_color'},
 director={'cinema_begin','cinema_reposition','cinema_end','cinema_status','cinema_hint','director_slot','director_recall','director_save','director_clear','director_status','director_hint','ai_behavior','ai_reset','ai_status','ai_hint','ai_limits'}}
for page_id,ids in pairs(expected_orders)do for i,id in ipairs(ids)do assert(page_map[page_id].controls[i].id==id,'Unexpected group order: '..page_id..' / '..id)end end
for _,id in ipairs({'hide_hud','hide_controls','show_legend','legend_open','legend_docked','legend_tab_y','legend_columns','legend_size','legend_x','legend_y','menu_opacity','menu_scale','menu_x','menu_y','reset_photo'})do
 assert(controls[id].page=='camera','Interface setting must be reachable in Settings: '..id)
end
assert(not controls.focus_distance.control.photo_section_collapsed and controls.fov.control.photo_section_collapsed and controls.dof_quality.control.photo_section_collapsed)
assert(not controls.light_color.control.photo_section_collapsed and controls.light_right.control.photo_section_collapsed)
for _,page in ipairs(pages)do
 local closed,current={};for _,control in ipairs(page.controls)do
  assert(type(control.photo_section)=='string'and type(control.photo_section_label)=='string'and type(control.photo_section_collapsed)=='boolean')
  if control.photo_section~=current then
   assert(not closed[control.photo_section],'Groups must stay contiguous');if current then closed[current]=true end;current=control.photo_section
  end
 end
end
-- The live migration and fresh registration use the same pure organizer. Every
-- field outside presentation metadata, including closures and live gates, stays
-- exactly identical. Source pages and rows are never modified in place.
local unknown_callback=function()return'untouched'end
local input={}
for _,page in ipairs(pages)do
 local copy={};for k,v in pairs(page)do copy[k]=v end;copy.controls={}
 for _,control in ipairs(page.controls)do
  local row={};for k,v in pairs(control)do if not k:match('^photo_section')then row[k]=v end end
  row.disabled=not row.disabled;copy.controls[#copy.controls+1]=row
 end
 input[#input+1]=copy
end
input[#input+1]={id='future_tools',name='Future tools',controls={{id='future_action',type='button',label='Future action',on_activate=unknown_callback,disabled=true}}}
local before=index(input);local organized=options.organize_pages(input);local after=index(organized)
local original_count=0;for id,entry in pairs(before)do
 original_count=original_count+1;local row=assert(after[id]).control;assert(row~=entry.control)
 for k,v in pairs(entry.control)do assert(row[k]==v,'Control contract changed: '..id..' / '..k)end
 assert(entry.control.photo_section==nil,'Organizer mutated the source row')
end
local _,_,new_count=index(organized);assert(new_count==original_count and after.future_action.page=='future_tools')
assert(after.future_action.control.on_activate==unknown_callback and after.future_action.control.disabled)
local twice=index(options.organize_pages(organized));for id,entry in pairs(after)do
 assert(twice[id].page==entry.page);for k,v in pairs(entry.control)do assert(twice[id].control[k]==v,'Organizer is not idempotent: '..id)end
end

local core=dofile('src/core.lua');local controller=dofile(root..'controller.lua')
for _,standalone in ipairs({false,true})do
 local service=core.new(nil,function()end);service.photo_standalone=standalone
 service.is_open=function()return false end;service.create_photo_view=function()return {}end
 service.camera_input={down=function()return false end,focused=function()return true end,pause_allowed=function()return true end,
  acquire=function()return {}end,release=function()return true end,set_focus=function()return true end,sample=function()return {wheel=0,dt=.016}end}
 local visible;local fake_menu={new=function()return {bind=function(_,value)visible=value end,close=function()end,editing_key=function()return false end}end}
 if standalone then DBFMCM=nil;DBF_PHOTO_STANDALONE_API=service else DBFMCM=service;DBF_PHOTO_STANDALONE_API=nil end
 local adapter=controller.new({}, {},function()return true end,function()end,nil,options,nil,fake_menu);adapter.tick(.016)
 local registered,registered_pages=index(service.mods.dbf_freecam.pages);local shown,shown_pages=index(assert(visible))
 assert(#visible==9 and shown_pages.camera.name=='Settings'and registered_pages.camera.name=='Settings')
 for id in pairs(controls)do assert(registered[id]and shown[id],'Photo setting lost from visible organization: '..id)end
 for _,id in ipairs({'enabled','toggle','reset_photo','hide_controls','hide_hud'})do assert(shown[id].page=='camera')end
 for _,id in ipairs({'speed','wheel_step','look_sensitivity','roll_speed','freeze_player','slowmo_speed'})do assert(registered[id].page=='camera_tools')end
 for _,id in ipairs({'toggle_key','focus_key','screenshot_key','hide_controls_key','lock_camera_key','slowmo_key','forward_key','back_key','left_key','right_key','up_key','down_key','roll_left_key','roll_right_key'})do
  assert(registered[id].page=='camera'and (shown[id]~=nil)==standalone,'Keybind ownership changed: '..id)
 end
 local slow=registered.slowmo_speed.control;assert(slow.default==.2 and slow.min==.05 and slow.max==1 and slow.step==.05 and slow.fine_step==.01 and type(slow.on_change)=='function')
 local speed=registered.speed.control;assert(math.abs(speed.default-3)<1e-6 and speed.min==.1 and speed.max==50 and speed.step==.1)
 assert(type(registered.hide_controls.control.on_change)=='function','Moving hide_controls lost its session callback')
 assert(service.mods.dbf_freecam.handle.set('hide_controls',true));assert(service.mods.dbf_freecam.handle.get('hide_controls'))
 assert(service.mods.dbf_freecam.handle.set('hide_controls',false));assert(not service.mods.dbf_freecam.handle.get('hide_controls'))
 assert(adapter.close());DBFMCM=nil;DBF_PHOTO_STANDALONE_API=nil
end
print('Menu organization: exact ID closure, pure field/callback/availability preservation, contiguous groups, focus/light priorities and shared/standalone Settings ownership passed')

-- Stored photo controls; existing movement and toggle ids remain stable.
local M={}
M.defaults={fov=0,focal_preset=1,roll=0,roll_preset=1,saved_camera_radius=60,lock_camera=false,camera_smoothing=false,smoothing_strength=50,action_camera_mode=1,handycam_intensity=50,handycam_lag_ms=0,handycam_forward_cm=14,handycam_up_cm=7,handycam_right_cm=0,handycam_yaw_deg=0,handycam_pitch_deg=0,cinema_notification=false,dof=false,dof_mode=1,dof_quality=1,dof_strength=4,bokeh_shape=1,focus_mode=1,focus_distance=5,aperture=5.6,
 filter=1,filter_strength=25,exposure=0,saturation=100,contrast=100,bloom=true,
 shader=1,shader_opacity=10,shader_scale=1,shader_animate=true,scene_shader=1,scene_strength=100,fog_distance=25,fog_density=50,scene_depth_range=100,vignette=0,vignette_width=18,grain=0,grain_size=1.5,
 frame=1,grid=1,logo=1,logo_size=100,logo_x=90,logo_y=8,logo_opacity=85,logo_color='#FFFFFF',clean_view=false,hide_hud=true,hide_controls=false,
 light_selected=1,light_preset=1,light_setup_slot=1,light_kind=1,light_enabled=true,light_intensity=3,light_color='#FFFFFF',light_range=8,light_cone=45,light_right=0,light_forward=1,light_up=0,light_follow=false,light_follow_player=false,
 hide_player=false,hide_armour=false,hide_weapons=false,hide_cape=false,handycam_hide_helmet=false,handycam_hide_torso=false,handycam_hide_cape=false,subject_pose=1,director_slot=1,path_point=1,path_duration=3,path_transition=1,
 show_legend=true,legend_open=true,legend_docked=true,legend_tab_y=75,legend_columns=2,legend_x=2,legend_y=2,legend_size=38}
-- Enemy behavior is stored only when its rows exist (FFI AI backend; see pages).
M.ai_defaults={ai_behavior=1}
M.ai_modes={'normal','passive','dummy'}
M.subject_poses={'salute','wave','taunt'}
M.subject_pose_labels={'Salute','Wave','Taunt'}
function M.set_subject_poses(catalog)
 if type(catalog)~='table'or getmetatable(catalog)~=nil then return false,'Pose catalog must be a plain list'end
 local count,last=0,0
 for key in pairs(catalog)do
  if type(key)~='number'or key%1~=0 or key<1 or key>256 then return false,'Pose catalog supports at most 256 entries'end
  count=count+1;last=math.max(last,key)
 end
 if count<3 or count~=last then return false,'Pose catalog must be a dense list including the original three poses'end
 local ids,labels,seen_ids,seen_labels={},{},{},{}
 local prefix={'salute','wave','taunt'}
 for index=1,count do
  local entry=rawget(catalog,index)
  if type(entry)~='table'or getmetatable(entry)~=nil then return false,'Pose catalog entry must be a plain table'end
  local id,label=entry.id,entry.label
  if type(id)~='string'or#id>64 or not id:match('^[a-z][a-z0-9_]*$')or seen_ids[id]then return false,'Pose catalog IDs must be unique lowercase symbols'end
  if type(label)~='string'or#label>96 or not label:match('%S')or label:find('%c')or seen_labels[label]then return false,'Pose catalog labels must be unique, nonempty display text'end
  if prefix[index]and id~=prefix[index]then return false,'Pose catalog must retain Salute, Wave and Taunt as its first three entries'end
  ids[index],labels[index]=id,label;seen_ids[id],seen_labels[label]=true,true
 end
 -- Validate the complete catalog before replacing either menu mapping.
 M.subject_poses,M.subject_pose_labels=ids,labels
 return true
end
M.light_presets={'key_fill_rim','portrait','dramatic_side'}
M.menu_layout_defaults={menu_x=-1,menu_y=-1,menu_scale=1,menu_opacity=38,tab_layout=1}
-- Preset choices are commands/labels. FOV and roll remain the only settings
-- consumed by the lens; these helpers use the existing 24 mm sensor height.
M.focal_presets={false,24,35,50,85,135}
M.roll_presets={false,0,90,-90}
function M.preset_fov(index)local mm=M.focal_presets[index];return mm and math.deg(2*math.atan(12/mm))or nil end
function M.focal_length(radians)
 if type(radians)~='number'or radians~=radians or radians<=0 or radians>=math.pi then return nil end
 local tangent=math.tan(radians/2);if tangent<1e-9 then return nil end;return 12/tangent
end
function M.pages(reset,recenter,catalog,saved_actions)
 local function slider(id,label,min,max,step)return {id=id,type='slider',label=label,default=M.defaults[id],min=min,max=max,step=step,commit_on_blur=true,fine_step=(id=='focus_distance'or id=='fov')and .001 or (id=='handycam_forward_cm'or id=='handycam_up_cm'or id=='handycam_right_cm'or id=='handycam_yaw_deg'or id=='handycam_pitch_deg')and .01 or nil,disabled=({focus_distance=true,aperture=true,exposure=true,saturation=true,contrast=true,scene_strength=true,fog_distance=true,fog_density=true,scene_depth_range=true})[id]}end
 local function choice(id,label,choices)return {id=id,type='choice',label=label,default=M.defaults[id],choices=choices,presentation='dropdown',disabled=id=='scene_shader'or id=='subject_pose'or nil}end
 local function toggle(id,label)return {id=id,type='toggle',label=label,default=M.defaults[id]}end
 local function layout_setting(id,label,min,max,step)return{id=id,type='slider',label=label,default=M.menu_layout_defaults[id],min=min,max=max,step=step or .000001,layout_storage=true,commit_on_blur=true}end
 local function lens_control(control)
  control.on_change=function(value)if saved_actions and saved_actions.lens_change then saved_actions.lens_change(control.id,value)end end
  return control
 end
 local function light_control(control)
  control.disabled=true
  control.on_change=function(value)if saved_actions and saved_actions.light_change then saved_actions.light_change(control.id,value)end end
  return control
 end
 local function light_action(id,label,action)
  return{id=id,type='button',label=label,button_label=label,disabled=true,on_activate=saved_actions and saved_actions[action]or function()end}
 end
 local function subject_control(id,label)
  local control=toggle(id,label);control.disabled=true
  control.on_change=function(value)if saved_actions and saved_actions.subject_change then saved_actions.subject_change(id,value)end end
  return control
 end
 local function director_action(id,label,action)
  return{id=id,type='button',label=label,button_label=label,disabled=true,on_activate=saved_actions and saved_actions[action]or function()end}
 end
 local function path_control(control)
  control.disabled=true
  control.on_change=function(value)if saved_actions and saved_actions.path_change then saved_actions.path_change(control.id,value)end end
  return control
 end
 local function ai_control()
  local control=choice('ai_behavior','Enemy behavior',{'Normal','Passive','Dummy'});control.disabled=true;control.default=M.ai_defaults.ai_behavior
  control.on_change=function(value)if saved_actions and saved_actions.ai_change then saved_actions.ai_change(value)end end
  return control
 end
 local camera_controls={
 {id='screenshot',type='button',label='Screenshot',button_label='Take screenshot',disabled=not(saved_actions and saved_actions.screenshot),on_activate=saved_actions and saved_actions.screenshot or function()end},
 toggle('lock_camera','Lock camera movement'),toggle('camera_smoothing','Camera smoothing'),slider('smoothing_strength','Camera smoothing strength (%)',0,100,1),
 {id='save_camera',type='button',label='Save camera position',button_label='Save',disabled=not(saved_actions and saved_actions.save),on_activate=saved_actions and saved_actions.save or function()end},
 {id='clear_saved_camera',type='button',label='Clear saved camera position',button_label='Clear',disabled=not(saved_actions and saved_actions.clear),on_activate=saved_actions and saved_actions.clear or function()end},
 {id='recenter',type='button',label='Return to player',button_label='Return',on_activate=recenter},
 slider('saved_camera_radius','Saved camera retention radius (m)',5,60,1),
 {id='saved_camera_status',type='text',label='Saved camera: none'}}
 -- Move the existing controller-owned movement/pause definitions intact. Their
 -- IDs, defaults and callbacks remain shared with MCM and saved settings.
 for _,control in ipairs(saved_actions and saved_actions.camera_controls or{})do camera_controls[#camera_controls+1]=control end
 -- Enemy behavior needs the FFI AI backend; runtimes without one omit the rows.
 if not(saved_actions and saved_actions.without_ai)then
  for _,control in ipairs({ai_control(),director_action('ai_reset','Reset AI to Normal','ai_reset'),
   {id='ai_status',type='text',label='Enemy behavior unavailable: waiting for a verified solo mission'},
   {id='ai_hint',type='text',label='Solo only. Persists after Photo Mode exits; joining players reset behavior to Normal.'},
   {id='ai_limits',type='text',label='Passive allows movement; Dummy also stops voluntary movement. Physics, damage and active attacks can continue.'}})do
   control.photo_global_ai=true;camera_controls[#camera_controls+1]=control
  end
 end
 camera_controls[#camera_controls+1]={id='reset_photo',type='button',label='Reset photo adjustments',button_label='Reset',on_activate=reset}
 local definition={
 {id='camera_tools',name='Camera',require_confirmation=false,controls=camera_controls},
 {id='lens',name='Lens',require_confirmation=false,controls={
 lens_control(slider('fov','Field of view (0 = gameplay)',0,120,1)),
 toggle('dof','Depth of field'),choice('dof_mode','Depth of field method',{'Native camera','Shader (preview)'}),
 choice('focus_mode','Focus mode',{'Manual','Double-click to focus','Center auto-focus'}),
 slider('focus_distance','Focus distance (m)',0.1,200,0.01),slider('aperture','Aperture (f-stop)',1.2,22,0.1),
 lens_control(slider('roll','Camera tilt (degrees)',-180,180,0.01)),
 {id='focus_status',type='text',label='Manual focus'},
 {id='focus_hint',type='text',label='Hold Shift for 0.001 m focus steps.'},
 lens_control(choice('focal_preset','Lens preset',{'Custom','24 mm','35 mm','50 mm','85 mm','135 mm'})),
 {id='focal_length_status',type='text',label='Focal length: waiting for camera'},
 lens_control(choice('roll_preset','Tilt shortcut',{'Custom','Level (0)','Portrait (+90)','Portrait (-90)'})),
 choice('dof_quality','Shader blur quality',{'Standard','Smoother'}),slider('dof_strength','Shader blur strength',1,8,.25),choice('bokeh_shape','Bokeh shape',{'Round','Hexagonal'}),
 {id='lens_status',type='text',label='Depth-aware focus and aperture'},
 {id='known_issues',type='text',label='Native lens availability is shown above. Shader preview depth remains unverified.'}}},
 {id='color',name='Color',require_confirmation=false,controls={
 {id='color_status',type='text',label='Color grading: awaiting scene'},
 choice('filter','Filter',catalog and catalog.filter_names or {'Original','Warm film','Cool film','Sepia tint','Emerald','Crimson'}),
 slider('filter_strength','Filter strength (%)',0,100,1),slider('exposure','Exposure compensation (EV)',-4,4,0.1),
 slider('saturation','Saturation (%)',0,200,1),slider('contrast','Contrast (%)',50,200,1),toggle('bloom','Bloom')}},
 {id='effects',name='Effects',require_confirmation=false,controls={
 {id='scene_status',type='text',label='',status_only=true},
 choice('scene_shader','Scene effect',catalog and catalog.scene_names or {'None','Negative','Monochrome','Posterize','Field-report duotone','Solarize','Inverted depth','Thermal depth','Depth contours','Depth fog'}),
 slider('scene_strength','Scene effect strength (%)',0,100,1),slider('scene_depth_range','Depth display range (m)',1,200,1),
 slider('fog_distance','Fog half-density distance (m)',.1,200,.1),slider('fog_density','Maximum fog opacity (%)',0,100,1),
 choice('shader','Shader overlay',catalog and catalog.shader_names or {'None','CRT scanlines','RGB phosphor','Ordered dither','Ion interference','Scanner sweep'}),
 slider('shader_opacity','Shader opacity (%)',0,100,1),slider('shader_scale','Shader pattern scale',0.005,16,0.005),
 toggle('shader_animate','Animate shaders'),
 slider('vignette','Vignette (%)',0,100,1),slider('vignette_width','Vignette width (%)',1,40,1),slider('grain','Film grain (%)',0,100,1),slider('grain_size','Grain size (pixels)',0.1,8,0.1),
 {id='shader_status',type='text',label='',status_only=true}}},
 {id='lighting',name='Lighting',require_confirmation=false,controls={
 light_action('light_add','Add light','light_add'),
 choice('light_preset','Subject lighting preset',{'Key / Fill / Rim','Portrait','Dramatic side'}),
 light_action('light_apply_preset','Replace lights with preset','light_apply_preset'),
 {id='light_preset_hint',type='text',label='Presets replace current lights around the focused subject; center focus distance is the fallback.'},
 light_control(choice('light_selected','Selected light',{'Light 1','Light 2','Light 3'})),
 light_action('light_aim','Aim selected at subject','light_aim'),
 {id='light_drag_hint',type='text',label='Drag numbered scene markers to move lights. Hold Shift for finer movement.'},
 light_control(toggle('light_enabled','Light enabled')),light_control(choice('light_kind','Light type',{'Point','Spot'})),
 light_control(slider('light_intensity','Intensity',0,10000,.01)),
 light_control({id='light_color',type='color',label='Light color',default=M.defaults.light_color}),
 light_control(slider('light_range','Range (m)',.1,1000,.01)),light_control(slider('light_cone','Spot cone (degrees)',1,175,1)),
 light_control(slider('light_right','Right offset (m)',-20,20,.01)),light_control(slider('light_forward','Forward offset (m)',-20,20,.01)),light_control(slider('light_up','Up offset (m)',-20,20,.01)),
 light_control(toggle('light_follow','Follow camera')),light_control(toggle('light_follow_player','Follow Player')),
 light_action('light_place','Move to camera','light_place'),light_action('light_remove','Remove selected','light_remove'),light_action('light_clear','Remove all lights','light_clear'),
 choice('light_setup_slot','Saved lighting setup',{'Setup 1 — empty','Setup 2 — empty','Setup 3 — empty','Setup 4 — empty','Setup 5 — empty'}),
 light_action('light_setup_save','Save lighting setup','light_setup_save'),light_action('light_setup_recall','Recall lighting setup','light_setup_recall'),light_action('light_setup_clear','Clear saved setup','light_setup_clear'),
 {id='light_setup_status',type='text',label='Five lighting setups are saved relative to the subject.'},
 {id='light_status',type='text',label='Photo lighting is waiting for a camera'}}},
 {id='composition',name='Composition',require_confirmation=false,controls={
 choice('frame','Frame',{'Full screen','Cinematic 2.39:1','16:9','Square','Portrait 4:5'}),
 choice('grid','Composition guide',{'None','Rule of thirds','Center cross','Golden ratio'}),
 choice('logo','Logo',{'None','Helldiver crest','DBF','Super Earth crest','Helldivers 2','Arrowhead','Helldivers 2 — wide','Helldivers 2 — compact','Helldivers II crest','Super Citizen Edition','Omens of Tyranny','Heart of Democracy','Into the Unjust'}),slider('logo_size','Logo scale (%)',0.5,400,0.5),
 slider('logo_x','Logo horizontal position (%)',0,100,1),slider('logo_y','Logo vertical position (%)',0,100,1),
 slider('logo_opacity','Logo opacity (%)',0,100,1),{id='logo_color',type='color',label='Logo color',default='#FFFFFF'},
 toggle('clean_view','Hide guides and logo'),toggle('hide_hud','Hide gameplay HUD'),toggle('hide_controls','Hide photo controls'),
 toggle('show_legend','Show controls legend'),toggle('legend_open','Expand controls flyout'),toggle('legend_docked','Dock controls to left screen edge'),slider('legend_tab_y','Controls dock tab height (%)',0,100,.1),choice('legend_columns','Controls legend columns',{'Two','Three'}),
 slider('legend_x','Legend horizontal position (%)',0,100,.1),slider('legend_y','Legend vertical position (%)',0,100,.1),slider('legend_size','Legend size (% of screen short edge)',25,70,.1),
 {id='tab_layout',type='choice',label='Tab layout',default=M.menu_layout_defaults.tab_layout,choices={'Slim','Stacked'},presentation='dropdown'},
 layout_setting('menu_x','Saved menu horizontal position',-1,1),layout_setting('menu_y','Saved menu vertical position',-1,1),layout_setting('menu_scale','Saved menu size',.35,3),layout_setting('menu_opacity','Menu background opacity',10,100,1)}},
 {id='director',name='Director',require_confirmation=false,controls={
 director_action('cinema_begin','Begin action shot','cinema_begin'),
 director_action('cinema_reposition','Reposition cinema camera','cinema_reposition'),
 director_action('cinema_end','Return to gameplay camera','cinema_end'),
 {id='cinema_status',type='text',label='Place a camera, then begin an action shot'},
 choice('action_camera_mode','Action camera mode',{'Placed camera','First-person handycam'}),
 slider('handycam_intensity','Handycam shake intensity (%)',0,100,1),
 slider('handycam_lag_ms','Handycam movement lag (ms)',0,500,5),
 slider('handycam_forward_cm','POV camera forward (cm)',-30,30,1),
 slider('handycam_up_cm','POV camera up (cm)',-30,30,1),
 slider('handycam_right_cm','POV camera left / right (cm)',-30,30,1),
 slider('handycam_yaw_deg','POV camera yaw (degrees)',-180,180,1),
 slider('handycam_pitch_deg','POV camera pitch (degrees)',-89,89,1),
 director_action('handycam_position_handle','Drag camera position','handycam_position_handle'),
 {id='handycam_drag_hint',type='text',label='Handle: M1 drag moves. Wheel: forward/back. MMB drag: yaw/pitch. Shift: fine.'},
 subject_control('handycam_hide_helmet','Hide helmet (POV)'),
 subject_control('handycam_hide_torso','Hide torso (POV)'),
 subject_control('handycam_hide_cape','Hide cape (POV)'),
 {id='handycam_pov_status',type='text',label='POV visibility off'},
 {id='handycam_hint',type='text',label='Handycam follows your selected subject. POV hiding keeps arms and weapons visible.'},
 toggle('cinema_notification','Show Cinema camera notification'),
 {id='cinema_hint',type='text',label='The camera stays placed while you move and fight. Your Photo Mode key returns to placement; Screenshot still works.'},
 path_control(choice('path_point','Recorded camera point',{'No recorded points'})),
 director_action('path_add','Add camera point','path_add'),director_action('path_remove','Remove selected point','path_remove'),
 path_control(slider('path_duration','Segment duration (s)',.1,60,.1)),
 path_control(choice('path_transition','Transition to next point',{'Smooth','Cut'})),
 director_action('path_play','Play camera path','path_play'),director_action('path_clear','Clear camera path','path_clear'),
 {id='path_status',type='text',label='No camera points recorded'},
 {id='path_hint',type='text',label='Place the camera and add each point. Duration and transition lead to the next point; the final camera is held. Your Photo Mode key stops playback and returns to placement. Paths last for this scene only.'},
 choice('director_slot','Camera shot slot',{'Shot 1 — empty','Shot 2 — empty','Shot 3 — empty','Shot 4 — empty','Shot 5 — empty'}),
 director_action('director_save','Save relative shot','director_save'),director_action('director_recall','Recall relative shot','director_recall'),director_action('director_clear','Clear selected shot','director_clear'),
 {id='director_status',type='text',label='Shots store camera position and angle relative to the player.'},
 {id='director_hint',type='text',label='Five shots persist between game sessions.'}}},
 {id='subject',name='Subject',require_confirmation=false,controls={
 (function()local row=choice('subject_pose','Pose',M.subject_pose_labels);row.on_change=saved_actions and saved_actions.subject_pose_change;return row end)(),
 director_action('subject_pose_play','Apply pose','subject_pose_play'),director_action('subject_pose_stop','Reset pose','subject_pose_stop'),
 {id='subject_pose_status',type='text',label='Subject poses are waiting for a verified local player'},
 {id='subject_pose_hint',type='text',label='Pause entire action to hold a fixed pose. Choosing a pose applies it; Reset restores the original pose.'},
 subject_control('hide_player','Hide entire player'),subject_control('hide_armour','Hide armour and helmet'),subject_control('hide_weapons','Hide carried weapons'),subject_control('hide_cape','Hide cape'),
 {id='subject_status',type='text',label='Subject controls are waiting for a verified player'},
 {id='subject_hint',type='text',label='Visibility is restored when Photo Mode closes.'}}}}
 -- Group existing rows without introducing stored settings or collapsible UI.
 -- Keep the original row objects so live gates and callbacks retain ownership.
 local sections={
 camera_tools={{'Camera tools','screenshot','lock_camera','recenter'},{'Movement','speed','look_sensitivity','wheel_step','roll_speed','camera_smoothing','smoothing_strength','freeze_player','slowmo_speed'},
  {'Saved camera','save_camera','clear_saved_camera','saved_camera_radius','saved_camera_status'},
  {'Enemy behavior','ai_behavior','ai_reset','ai_status','ai_hint','ai_limits'},{'Reset','reset_photo'}},
 lens={{'Lens','fov','focal_preset','focal_length_status'},
  {'Focus & depth of field','dof','dof_mode','focus_mode','focus_distance','aperture','focus_status','focus_hint'},
  {'Camera tilt','roll','roll_preset'},
  {'Shader bokeh','dof_quality','dof_strength','bokeh_shape','lens_status','known_issues'}},
 color={{'Tone','color_status','exposure','contrast','saturation','bloom'},{'Filters','filter','filter_strength'}},
 effects={{'Scene effects','scene_status','scene_shader','scene_strength'},{'Depth & fog','scene_depth_range','fog_distance','fog_density'},
  {'Shader overlays','shader','shader_opacity','shader_scale','shader_animate','shader_status'},{'Finishing','vignette','vignette_width','grain','grain_size'}},
 lighting={{'Lights','light_add','light_selected','light_enabled','light_kind','light_status'},
  {'Appearance','light_intensity','light_color','light_range','light_cone'},
  {'Placement','light_aim','light_place','light_follow','light_follow_player','light_right','light_forward','light_up','light_drag_hint'},
  {'Subject presets','light_preset','light_apply_preset','light_preset_hint'},
  {'Saved setups','light_setup_slot','light_setup_recall','light_setup_save','light_setup_clear','light_setup_status'},
  {'Remove lights','light_remove','light_clear'}},
 composition={{'Framing','frame','grid','clean_view','hide_hud','hide_controls'},
  {'Logo','logo','logo_size','logo_color','logo_opacity','logo_x','logo_y'},
  {'Controls legend','show_legend','legend_open','legend_docked','legend_tab_y','legend_columns','legend_size','legend_x','legend_y'},
  {'Menu layout','tab_layout','menu_x','menu_y','menu_scale','menu_opacity'}},
 director={{'Action shots','cinema_begin','action_camera_mode','handycam_intensity','handycam_lag_ms','handycam_forward_cm','handycam_up_cm','handycam_right_cm','handycam_position_handle','handycam_yaw_deg','handycam_pitch_deg','handycam_drag_hint','handycam_hide_helmet','handycam_hide_torso','handycam_hide_cape','handycam_pov_status','handycam_hint','cinema_reposition','cinema_end','cinema_status','cinema_notification','cinema_hint'},
  {'Camera path','path_point','path_add','path_remove','path_duration','path_transition','path_play','path_clear','path_status','path_hint'},
  {'Saved shots','director_slot','director_recall','director_save','director_clear','director_status','director_hint'}},
 subject={{'Pose','subject_pose','subject_pose_play','subject_pose_stop','subject_pose_status','subject_pose_hint'},
  {'Visibility','hide_player','hide_armour','hide_weapons','hide_cape','subject_status','subject_hint'}}}
 if saved_actions and saved_actions.without_depth_shaders then
  local removed={dof_quality=true,dof_strength=true,bokeh_shape=true,scene_depth_range=true,fog_distance=true,fog_density=true}
  for _,page in ipairs(definition)do
   local controls={}
   for _,control in ipairs(page.controls)do if not removed[control.id]then
    if control.id=='dof_mode'then control.choices={'Native camera'}
    elseif control.id=='scene_shader'then
     local names={};for i=1,math.min(6,#control.choices)do names[i]=control.choices[i]end;control.choices=names
    elseif control.id=='known_issues'then control.label='Native camera DoF is supported. Depth shaders are unavailable in this Lua rewrite.'end
    controls[#controls+1]=control
   end end
   page.controls=controls
  end
 end
 for _,page in ipairs(definition)do
  local indexed,ordered,used={},{},{}
  for _,control in ipairs(page.controls)do indexed[control.id]=control end
  for _,group in ipairs(sections[page.id]or{})do
   local first=true
   for i=2,#group do local control=indexed[group[i]];if control then
    if first then control.photo_section=group[1];first=false end
    ordered[#ordered+1]=control;used[control]=true
   end end
  end
  for _,control in ipairs(page.controls)do if not used[control]then ordered[#ordered+1]=control end end
  page.controls=ordered
 end
 return definition
end
function M.read(handle,controls)
 local values={};for key,value in pairs(M.defaults)do if controls and not controls[key]then values[key]=value else values[key]=handle.get(key)end end;return values
end
-- Recover the transient hidden menu on a new runtime. Photo adjustments,
-- bindings, main-menu layout and controls-drawer preferences stay saved.
-- Navigation/edit state is reset by the panel independently.
function M.reset_menu(handle)
 local values={hide_controls=M.defaults.hide_controls}
 if handle.set_many then return handle.set_many(values)end
 for key,value in pairs(values)do local ok,why=handle.set(key,value);if ok==false then return false,why end end
 return true
end
function M.reset(handle,controls)
 for key,value in pairs(M.defaults)do if not controls or not controls[key]or not controls[key].disabled then handle.set(key,value)end end
 for key,value in pairs(M.ai_defaults)do if controls and controls[key]and not controls[key].disabled then handle.set(key,value)end end
end
return M


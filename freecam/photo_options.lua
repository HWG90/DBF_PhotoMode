-- Stored photo controls; existing movement and toggle ids remain stable.
local M={}
M.defaults={fov=0,roll=0,saved_camera_radius=60,lock_camera=false,dof=false,focus_distance=5,aperture=5.6,
 filter=1,filter_strength=25,exposure=0,saturation=100,contrast=100,bloom=true,
 shader=1,shader_opacity=10,shader_scale=1,shader_animate=true,vignette=0,vignette_width=18,grain=0,grain_size=1.5,
 frame=1,grid=1,logo=1,logo_size=100,logo_x=90,logo_y=8,logo_opacity=85,logo_color='#FFFFFF',clean_view=false,hide_hud=true,hide_controls=false}
function M.pages(reset,recenter,catalog,saved_actions)
 local function slider(id,label,min,max,step)return {id=id,type='slider',label=label,default=M.defaults[id],min=min,max=max,step=step,disabled=({focus_distance=true,aperture=true,exposure=true,saturation=true,contrast=true})[id]}end
 local function choice(id,label,choices)return {id=id,type='choice',label=label,default=M.defaults[id],choices=choices,presentation='dropdown'}end
 local function toggle(id,label)return {id=id,type='toggle',label=label,default=M.defaults[id]}end
 return {
 {id='lens',name='Camera',require_confirmation=false,controls={
 slider('fov','Vertical field of view (0 = gameplay)',0,120,1),slider('roll','Camera tilt (degrees)',-180,180,0.01),
 {id='screenshot',type='button',label='Screenshot',disabled=not(saved_actions and saved_actions.screenshot),on_activate=saved_actions and saved_actions.screenshot or function()end},
 {id='save_camera',type='button',label='Save Camera Position',disabled=not(saved_actions and saved_actions.save),on_activate=saved_actions and saved_actions.save or function()end},
 {id='clear_saved_camera',type='button',label='Clear Saved Camera Position',disabled=not(saved_actions and saved_actions.clear),on_activate=saved_actions and saved_actions.clear or function()end},
 slider('saved_camera_radius','Saved camera retention radius (m)',5,60,1),
 {id='saved_camera_status',type='text',label='Saved camera: none'},
 toggle('lock_camera','Lock camera movement'),{id='recenter',type='button',label='Return to player',on_activate=recenter},
 toggle('dof','Depth of field'),slider('focus_distance','Focus distance (m)',0.1,200,0.1),slider('aperture','Aperture (f-stop)',1.2,22,0.1),
 {id='lens_status',type='text',label='Focus/f-stop unavailable in this release'},
 {id='known_issues',type='text',label='Known issues: focus/f-stop and scene shaders disabled; exposure/contrast/saturation unavailable.'},
 {id='reset_photo',type='button',label='Reset photo adjustments',on_activate=reset}}},
 {id='color',name='Color',require_confirmation=false,controls={
 choice('filter','Filter',catalog and catalog.filter_names or {'Original','Warm film','Cool film','Sepia tint','Emerald','Crimson'}),
 slider('filter_strength','Filter strength (%)',0,100,1),slider('exposure','Exposure compensation (EV)',-4,4,0.1),
 slider('saturation','Saturation (%)',0,200,1),slider('contrast','Contrast (%)',50,200,1),toggle('bloom','Bloom'),
 {id='color_status',type='text',label='Color grading: awaiting scene'}}},
 {id='effects',name='Effects',require_confirmation=false,controls={
 choice('shader','Shader overlay',catalog and catalog.shader_names or {'None','CRT scanlines','RGB phosphor','Ordered dither','Ion interference','Scanner sweep'}),
 slider('shader_opacity','Shader opacity (%)',0,100,1),slider('shader_scale','Shader pattern scale',0.005,16,0.005),
 toggle('shader_animate','Animate shaders'),
 slider('vignette','Vignette (%)',0,100,1),slider('vignette_width','Vignette width (%)',1,40,1),slider('grain','Film grain (%)',0,100,1),slider('grain_size','Grain size (pixels)',0.1,8,0.1),
 {id='shader_status',type='text',label='',status_only=true}}},
 {id='composition',name='Composition',require_confirmation=false,controls={
 choice('frame','Frame',{'Full screen','Cinematic 2.39:1','16:9','Square','Portrait 4:5'}),
 choice('grid','Composition guide',{'None','Rule of thirds','Center cross','Golden ratio'}),
 choice('logo','Logo',{'None','Helldiver crest','DBF','Super Earth crest','Helldivers 2','Arrowhead'}),slider('logo_size','Logo scale (%)',0.5,400,0.5),
 slider('logo_x','Logo horizontal position (%)',0,100,1),slider('logo_y','Logo vertical position (%)',0,100,1),
 slider('logo_opacity','Logo opacity (%)',0,100,1),{id='logo_color',type='color',label='Logo color',default='#FFFFFF'},
 toggle('clean_view','Hide guides and logo'),toggle('hide_hud','Hide gameplay HUD'),toggle('hide_controls','Hide photo controls')}}}
end
function M.read(handle)
 local values={};for key in pairs(M.defaults)do values[key]=handle.get(key)end;return values
end
function M.reset(handle,controls)for key,value in pairs(M.defaults)do if not controls or not controls[key]or not controls[key].disabled then handle.set(key,value)end end end
return M


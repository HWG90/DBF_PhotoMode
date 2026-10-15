local root=assert(rawget(_G,'DBF_PHOTO_TEST_ROOT'))
local core=dofile(root..'vendor/core.lua');local options=dofile(root..'photo_options.lua');local menu=dofile(root..'photo_menu.lua');menu.legend_factory=dofile(root..'control_legend.lua')
local clock=0;local keys={};local mouse={x=700,y=200};local missing_pointer=false;local focused=true;local mcm=false;local mode=0;local lease=false;local commands;local calls={};local distance=3.456789;local fail=false;local retired=0;local settling_until
local provider={down=function(k)return keys[k]or false end,focused=function()return focused end,
 acquire=function()assert(mode==0);lease=true;mode=3;return {}end,release=function()lease=false;mode=0;return true end,
 set_focus=function(menu_focus)assert(lease);mode=menu_focus and 1 or 3;return true end,
 sample=function()assert(lease and(mode==1 or mode==3));return{wheel=0,escape=keys[27],mouse_x=0,mouse_y=0,dt=.016}end,
 menu_sample=function()assert(mode==1);if missing_pointer then return end;return{x=mouse.x,y=mouse.y,click=keys[1]or false,wheel=0,dt=.016}end}
local sampler={interval=.5,now=function()return clock end,release=function()retired=retired+1;return true end,
 sample=function(u,v)calls[#calls+1]={u,v};if fail then return nil,'No depth sample'end;if settling_until and clock<settling_until then return nil,'Auto-focus paused: display settling',{pending=true,retry_at=settling_until}end;return distance end}
local api=core.new(nil,function()end);api.is_open=function()return mcm end;api.close=function()mcm=false;return true end;api.camera_input=provider
api.photo_resolution=function()return 1920,1080 end;api.create_photo_view=function()return{draw=function(c)commands=c end,release=function()commands={}end}end;DBFMCM=api
local effects={native_dof_candidate=true,native_dof_ready=true,parameters={focus_distance=true,aperture=true,dof=true},release=function()return true end}
local photo={};local capture=false;local screenshots={active=function()return capture end,cancel=function()capture=false end,tick=function()return true end,request=function()capture=true;return true end}
local controller=dofile(root..'controller.lua').new(photo,{},function()return true end,function()end,nil,options,effects,menu,nil,nil,screenshots,sampler)
local function tick(dt)dt=dt or .016;clock=clock+dt;controller.tick(dt)end
local function press(k)keys[k]=true;tick();keys[k]=false;tick()end
local function double_click()press(1);press(1)end
local function near(a,b)return math.abs(a-b)<1e-7 end
local function find(role)for _,c in ipairs(commands)do if c.ui_role==role then return c end end;error('Missing '..role)end
tick();press(80);tick();local handle=api.mods.dbf_freecam.handle;assert(photo.active and mode==1 and handle.get('focus_mode')==1);press(9);assert(mode==3)
local controls={};for _,page in ipairs(api.mods.dbf_freecam.pages)do for _,c in ipairs(page.controls)do controls[c.id]=c end end
assert(not controls.pick_focus and controls.focus_mode.choices[2]=='Double-click to focus','Subject selection must not require a repeated Activate action')
keys[1]=true;handle.set('focus_mode',2);tick();tick();assert(mode==3 and #calls==0,'Selecting double-click mode must preserve camera input focus')
press(9);tick();assert(mode==1 and #calls==0,'A held mouse button must not select on entering menu focus')
press(69);tick() -- Lens is separate from the initial Camera actions tab.
keys[1]=false;tick();local panel=find('photo_panel');mouse={x=panel.x+3,y=panel.y+50};double_click();assert(#calls==0,'Opaque main menu must be excluded')
local flyout=find('control_legend');mouse={x=flyout.x+3,y=flyout.y+flyout.h/2};double_click();assert(#calls==0,'Opaque legend must be excluded')
local tab=find('legend_flyout_toggle');mouse={x=tab.x+tab.w/2,y=tab.y+tab.h/2};press(1);tick();assert(#calls==0 and handle.get('legend_open')==false,'Dock toggle must be excluded and still collapse the drawer')
tab=find('legend_flyout_toggle');mouse={x=tab.x+tab.w/2,y=tab.y+tab.h/2};press(1);tick();assert(#calls==0 and handle.get('legend_open')==true,'Left-edge opener must be excluded from subject selection')
local mode_field;local legend_hint=false;for _,c in ipairs(commands)do if c.ui_role=='field'and c.control_id=='focus_mode'then mode_field=c end;if c.full_text=='DOUBLE-CLICK'then legend_hint=true end end
assert(mode_field and legend_hint,'Menu must show the persistent focus mode and contextual double-click legend')
mouse={x=mode_field.x+mode_field.w/2,y=mode_field.y+mode_field.h/2};press(1);tick();find('dropdown_panel')
mouse={x=700,y=270};double_click();assert(#calls==0,'Modal dismissal must not click through to subject focus');tick(.4)
mouse={x=700,y=270};press(1);assert(#calls==0,'A single click must not perform a GPU depth sample')
keys[1]=true;tick();tick();tick();assert(#calls==1 and calls[1][1]==700/1920 and calls[1][2]==.75,'Double-click UV must convert bottom-left native pixels to top-left depth coordinates once')
keys[1]=false;tick();assert(near(handle.get('focus_distance'),3.457)and handle.get('focus_mode')==2 and mode==1 and photo.active,'Subject focus must persist without changing menu/camera ownership')
distance=4.876;double_click();assert(#calls==2 and near(handle.get('focus_distance'),4.876),'Another subject must be selectable without an Activate action')
local count=#calls;press(1);tick(.4);press(1);assert(#calls==count,'Slow clicks must not become a double click');tick(.4)
press(1);mouse.x=mouse.x+20;press(1);assert(#calls==count,'Separate subjects must not form a click pair');tick(.4)
mouse={x=0/0,y=270};double_click();mouse={x=-1,y=270};double_click();mouse={x=700,y=math.huge};double_click();assert(#calls==count,'Invalid native cursor coordinates must not sample depth')
mouse={x=700,y=270};fail=true;double_click();assert(#calls==count+1 and mode==1 and near(handle.get('focus_distance'),4.876),'No depth sample must preserve valid focus and persistent subject mode')
fail=false;count=#calls;press(1);missing_pointer=true;tick();missing_pointer=false;tick();press(1);assert(#calls==count,'A missing native pointer sample must discard pending subject clicks');tick(.4)
press(1);press(27);assert(mode==3 and photo.active,'Escape must abandon a partial click pair and return to camera')
press(9);tick();count=#calls;press(1);assert(#calls==count,'Returning to the cursor must not reuse the earlier partial pair');tick(.4)
press(1);capture=true;tick();capture=false;tick();press(1);assert(#calls==count,'Screenshot capture must discard pending subject clicks');tick(.4)
press(1);handle.set('hide_controls',true);tick();handle.set('hide_controls',false);press(9);tick();press(1);assert(#calls==count,'Hidden controls must discard pending subject clicks');tick(.4)
press(1);effects.native_dof_ready=false;tick();effects.native_dof_ready=true;tick();press(1);assert(#calls==count,'Unavailable native lens controls must discard pending subject clicks');tick(.4)
press(1);focused=false;tick();assert(mode==0 and photo.active,'Focus loss must release input without closing Photo Mode')
focused=true;tick();assert(mode==1 and photo.active,'Focus reacquisition must preserve the existing menu ownership');press(1);assert(#calls==count,'Focus loss must discard pending subject clicks');tick(.4)
press(1);mcm=true;tick();assert(mode==0 and photo.active,'MCM handoff must release photo input');mcm=false;tick();press(1);assert(mode==1 and #calls==count,'MCM handoff must discard pending subject clicks')
tick(.4);double_click();assert(#calls==count+1,'Subject mode must remain usable after input reacquisition')
handle.set('focus_mode',3);clock=1;tick();local center_count=#calls;assert(calls[center_count][1]==.5 and calls[center_count][2]==.5)
clock=1.1;tick();assert(#calls==center_count,'Center focus must throttle readbacks')
clock=1.5;distance=12.123;tick();assert(#calls==center_count+1 and near(handle.get('focus_distance'),12.123))
handle.set('focus_distance',1.405);clock=3;tick();assert(handle.get('focus_mode')==1 and near(handle.get('focus_distance'),1.405)and #calls==center_count+1,'Manual/typed authoritative writes must cancel automatic focus')
handle.set('focus_mode',3);capture=true;clock=4;tick();assert(#calls==center_count+1,'Screenshots must not trigger GPU autofocus readback');capture=false
handle.set('focus_mode',2);tick();count=#calls;press(1);handle.set('focus_distance',2.789);tick();press(1);assert(handle.get('focus_mode')==1 and #calls==count,'Manual/typed focus must cancel a pending double click')

-- One double-click must survive the sampler's mandatory cold/display-settle
-- pause. It retries only that UV, without repeated GPU work on every frame.
handle.set('focus_mode',2);tick();tick(.4);settling_until=clock+2;distance=6.543
count=#calls;double_click();local selected=calls[#calls]
assert(#calls==count+1 and near(handle.get('focus_distance'),2.789),'Cold subject focus must retain the previous valid distance while warming')
tick(.5);assert(#calls==count+1,'Pending subject focus must respect the sampler retry time')
tick(1.5);assert(#calls==count+2 and calls[#calls][1]==selected[1]and calls[#calls][2]==selected[2]and near(handle.get('focus_distance'),6.543),
 'The original double-click must focus its subject automatically once depth settles')
tick(1);assert(#calls==count+2,'Successful subject focus must consume its queued retry')
settling_until=nil
local function queued_subject()
 handle.set('focus_mode',2);if mode==3 then press(9)end;tick();tick(.4)
 mouse={x=700,y=270};settling_until=clock+2;count=#calls;double_click()
 assert(#calls==count+1,'Cancellation fixture must begin with one pending cold sample')
end
for _,cancel in ipairs({
 function()handle.set('focus_distance',2.222);tick()end,
 function()handle.set('focus_mode',1);tick()end,
 function()capture=true;tick();capture=false;tick()end,
 function()handle.set('hide_controls',true);tick();handle.set('hide_controls',false);tick()end,
 function()focused=false;tick();focused=true;tick()end,
 function()mcm=true;tick();mcm=false;tick()end,
 function()missing_pointer=true;tick();missing_pointer=false;tick()end,
 function()mouse={x=0/0,y=270};tick();mouse={x=700,y=270};tick()end,
 function()local p=find('photo_panel');mouse={x=p.x+3,y=p.y+50};press(1)end,
})do
 queued_subject();cancel();local after=#calls;local valid=handle.get('focus_distance');tick(3)
 assert(#calls==after and handle.get('focus_distance')==valid,'Cancelled subject focus must never apply a delayed depth result')
 settling_until=nil
end
queued_subject();settling_until=clock+60;tick(4.1)
assert(#calls==count+1,'A permanently settling display must expire the request instead of retrying indefinitely')
settling_until=nil;tick(1);assert(#calls==count+1,'Expired subject focus must require a new double-click')
queued_subject();settling_until=nil;distance=8.765;mouse={x=750,y=270};double_click();local latest=#calls;tick(3)
assert(#calls==latest and near(handle.get('focus_distance'),8.765),'A new subject must replace the old pending request without later overwriting it')
count=#calls;handle.set('focus_mode',2);tick();press(9);assert(mode==3);double_click();assert(#calls==count and mode==3,'Double-click mode must never steal camera input focus or use hidden cursor coordinates')
queued_subject();local pending_count=#calls;local before=retired;controller.stop();tick(3)
assert(mode==0 and not photo.active and retired>before and #calls==pending_count,'Photo exit must cancel pending focus and release the sampler and input');controller.close();DBFMCM=nil
print('Autofocus controls: persistent double-click subjects, bounded cold-depth retry, request replacement/cancellation, timing/position/held edges, UV/UI exclusions, unchanged input ownership, center sampling and exit cleanup passed')

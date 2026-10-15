-- Dedicated photo panel; authoritative MCM handles store every edit.
local M={}
local T={background={12,14,16},panel={19,21,23},header={25,27,29},border={62,66,69},border_hover={106,111,114},line={34,37,40},
 white={234,235,228},muted={154,159,159},gold={244,202,53},hover={29,31,33},selected={43,39,24},selected_hover={51,46,29},pressed={56,51,31},
 field={29,31,34},field_hover={39,42,45},enabled={176,205,176},disabled={105,111,113}}
local function glyphs(value)local result={};for c in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*')do result[#result+1]=c end;return result end
local function valid(v)return type(v)=='number'and v>0 and v<math.huge end
local PANEL_WIDTH,PANEL_HEIGHT,HUD_MARGIN=760,440,180
function M.new(view,actions,existing)
 local legend=M.legend_factory and M.legend_factory.new(view)
 local self=existing or{page=1,scroll=0,selection=1,size_scale=1};local nav_held={};local nav_time={};local nav_ready=false;local last_focus
 local rows={};local selected_hit;local hits={};local held=false;local drag;local resize;local scroll_drag;local move_panel;local geometry;local panel_bounds;local pointer_x,pointer_y;local pressed_key;local reveal_index;local row_scroll_max=0
 local layout_initialized=existing~=nil;local layout_dirty=false;local opacity_dirty=false
 local opacity_control={id='menu_opacity',type='slider',min=10,max=100,step=1,fine_step=1,default=38}
 local slowmo_control={id='slowmo_speed',type='slider',label='Slow motion speed',min=.05,max=1,step=.05,fine_step=.01}
 self.editing_value=nil;self.bound_key=nil;if legend and self.handle then legend.bind(self.handle)end
 local key_capture;local armed=false;local baseline={};local color_edit;local popup;local popup_close_on_release=false;local popup_scroll=0;local visible_count=1;local popup_count=1;local text_edit;local reset_regions={};local right_held
 local finish_number
 local function blur_number()if text_edit and text_edit.c.commit_on_blur==true then return finish_number()end;return true end
 local function stored_layout(key)
  if not self.handle or type(self.handle.get)~='function'then return end
  local ok,value=pcall(self.handle.get,key);if ok and type(value)=='number'and value==value and math.abs(value)<math.huge then return value end
 end
 local function menu_opacity()
  local v=opacity_dirty and self.menu_opacity or stored_layout('menu_opacity')or self.menu_opacity or opacity_control.default
  if type(v)~='number'or v~=v then v=opacity_control.default end
  return math.max(opacity_control.min,math.min(opacity_control.max,v))
 end
 local function finish_opacity()
  if not opacity_dirty then return end;opacity_dirty=false
  -- A same-object live migration can preview the slider before its saved key
  -- is registered. Fresh registrations persist one write per gesture.
  if stored_layout('menu_opacity')==nil then return end
  local ok,result=pcall(self.handle.set,'menu_opacity',self.menu_opacity)
  if not ok or result==false then self.notice='Menu opacity could not be saved' end
 end
 function self.persist_layout()
  if not geometry or not self.handle then return false end
  -- Older live registrations can display this layout safely before restarting;
  -- they cannot persist keys they have not registered yet.
  for _,key in ipairs({'menu_x','menu_y','menu_scale'})do if stored_layout(key)==nil then layout_dirty=false;return false end end
  local values={menu_x=math.max(0,math.min(1,geometry.x/(geometry.w-geometry.width))),menu_y=math.max(0,math.min(1,geometry.strip_bottom/(geometry.h-geometry.height))),menu_scale=math.max(.35,math.min(3,self.size_scale))}
  local ok,result
  if type(self.handle.set_many)=='function'then ok,result=pcall(self.handle.set_many,values)
  elseif type(self.handle.set)=='function'then ok=true;for key,value in pairs(values)do local called,accepted=pcall(self.handle.set,key,value);if not called or accepted==false then ok=false;break end end
  else return false end
  if not ok or result==false then self.notice='Menu layout could not be saved';return false end
  self.panel_x=stored_layout('menu_x');self.panel_y=stored_layout('menu_y');self.size_scale=stored_layout('menu_scale');layout_dirty=false;return true
 end
 local function finish_layout()if layout_dirty then layout_dirty=false;self.persist_layout()end;finish_opacity()end
 function self.close()blur_number();finish_layout();if self.light_gizmos then self.light_gizmos.cancel()end;if legend then legend.clear()end;view.release();panel_bounds=nil;hits={};drag=nil;resize=nil;scroll_drag=nil;move_panel=nil;key_capture=nil;text_edit=nil;color_edit=nil;popup=nil;popup_close_on_release=false;self.bound_key=nil;self.editing_value=nil;self.notice=nil;nav_ready=false;held=false;right_held=nil;pointer_x,pointer_y=nil,nil;pressed_key=nil;reveal_index=nil end
 local function suspend_input()blur_number();finish_layout();if self.light_gizmos then self.light_gizmos.cancel()end;if legend then legend.clear()end;nav_ready=false;held=false;right_held=nil;drag=nil;resize=nil;scroll_drag=nil;move_panel=nil;pressed_key=nil;pointer_x,pointer_y=nil,nil end
 function self.suspend()suspend_input();panel_bounds=nil;if legend then view.draw({})end end
 function self.bind(handle,pages)
  if self.handle~=handle then blur_number();finish_opacity();text_edit=nil;self.editing_value=nil end;self.handle=handle;self.pages=pages;if legend then legend.bind(handle)end
  for _,page in ipairs(pages)do for _,c in ipairs(page.controls or{})do if c.id=='slowmo_speed'then
   for _,key in ipairs({'min','max','step','fine_step'})do if type(c[key])=='number'then slowmo_control[key]=c[key]end end
  end end end
  if not layout_initialized then
   local x,y,size=stored_layout('menu_x'),stored_layout('menu_y'),stored_layout('menu_scale')
   self.panel_x=x and x>=0 and x<=1 and x or nil;self.panel_y=y and y>=0 and y<=1 and y or nil
   if size and size>=.35 and size<=3 then self.size_scale=size end
   layout_initialized=true
  end
 end
 function self.blur()return blur_number()end
 local function value(c)
  if c.type=='text'then return ''end;if c.type=='button'then return c.button_label or 'Activate'end
  local v=self.handle.get(c.id)
  if c.type=='choice'then return c.choices[v]or tostring(v)end
  if c.type=='toggle'then return v and 'ON'or 'OFF'end
  if c.type=='keybind'then local names={[0]='NONE',[9]='TAB',[13]='ENTER',[16]='SHIFT',[17]='CTRL',[18]='ALT',[19]='PAUSE',[27]='ESC',[32]='SPACE',[44]='PRINT SCREEN',[220]='\\'};return names[v]or(v>=32 and v<=126 and string.char(v)or('VK '..v))end
  if c.type=='slider'then local step=c.fine_step or c.step;return string.format(step<.01 and '%.3f'or step<1 and '%.2f'or '%.0f',v)end
  return tostring(v)
 end
 local function slider_value(c)
  if c==opacity_control then return menu_opacity()end
  if c.type=='color_channel'then return tonumber(self.handle.get(c.base):sub(c.channel*2,c.channel*2+1),16)end
  return self.handle.get(c.id)
 end
 local function write_slider(c,v,step)
  if c.disabled then return end
  v=c.min+math.floor((v-c.min)/step+.5)*step;v=math.min(c.max,math.max(c.min,v))
  if c==opacity_control then self.menu_opacity=v;opacity_dirty=true
  elseif c.type=='color_channel'then
   local hex=self.handle.get(c.base);local rgb={tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)}
   rgb[c.channel]=v;self.handle.set(c.base,string.format('#%02X%02X%02X',unpack(rgb)))
  else self.handle.set(c.id,v)end
 end
 local function set_slider(c,x,b)
  local t=math.max(0,math.min(1,(x-b.x)/b.w));write_slider(c,c.min+(c.max-c.min)*t,c.step)
 end
 local function begin_slider(c,x,b,fine)
  if not fine then set_slider(c,x,b)end
  drag={c=c,x=b.x,w=b.w,last_x=x,value=slider_value(c),relative=fine}
 end
 local function scrub_slider(x,fine)
  local c=drag.c;local delta=x-drag.last_x;drag.last_x=x
  if not drag.relative and not fine then set_slider(c,x,drag);drag.value=slider_value(c);return end
  -- Keep the pointer offset after Shift is released so changing sensitivity
  -- never snaps the value back to the pointer's absolute track position.
  drag.relative=true;if delta==0 then return end
  drag.value=math.max(c.min,math.min(c.max,drag.value+delta/drag.w*(c.max-c.min)*(fine and .1 or 1)))
  -- Retain sub-step movement between frames; only the stored value is rounded.
  write_slider(c,drag.value,c.fine_step or c.step)
 end
 local function measure(label,size)
  if view.measure then local ok,width=pcall(view.measure,label,size);if ok and type(width)=='number'and width>=0 and width<math.huge then return width end end
  return #glyphs(label)*size*.62
 end
 local function fit(label,width,size)
  label=tostring(label or ''):gsub('\n',' ');if measure(label,size)<=width then return label end
  local visible='';if measure('...',size)>width then return visible end
  for _,c in ipairs(glyphs(label))do if measure(visible..c..'...',size)>width then break end;visible=visible..c end
  return visible..'...'
 end
 local function selectable(c)return c and c.type~='text'and not c.disabled end
 local function reveal(index)
  reveal_index=index
  if index<=self.scroll then self.scroll=index-1 elseif index>self.scroll+visible_count then self.scroll=index-visible_count end
 end
 local function shift_value(c,direction,fine)
  if not selectable(c)then return end
  if c.type=='slider'then local step=fine and c.fine_step or c.step;self.handle.set(c.id,math.max(c.min,math.min(c.max,self.handle.get(c.id)+direction*step)))
  elseif c.type=='toggle'then self.handle.set(c.id,direction>0)
  elseif c.type=='choice'and #c.choices>0 then self.handle.set(c.id,(self.handle.get(c.id)-1+direction)%#c.choices+1)end
 end
 local function move_row(direction)
  for _=1,#rows do self.selection=(self.selection-1+direction)%#rows+1;if selectable(rows[self.selection])then break end end
  self.editing_value=nil;color_edit=nil;popup=nil;popup_close_on_release=false;scroll_drag=nil;reveal(self.selection)
 end
 local function begin_number(c)
  if text_edit and text_edit.c==c then return end
  if not blur_number()then return end
  self.editing_value=c;text_edit={c=c,handle=self.handle,text=tostring(self.handle.get(c.id)),replace=true,typing=false};self.notice=nil
 end
 finish_number=function()
  if not text_edit then return true end;local e=text_edit;local c=e.c
  local owned=e.handle==self.handle
  local found=false;for _,page in ipairs(self.pages or {})do for _,control in ipairs(page.controls or {})do if control==c then found=true end end end
  if not owned or not found or c.disabled then text_edit=nil;self.editing_value=nil;return true end
  local number=tonumber(e.text)
  if not number or number~=number or math.abs(number)==math.huge then e.error='Enter a valid number';return false end
  local step=c.fine_step or c.step
  number=math.max(c.min,math.min(c.max,number));number=math.min(c.max,c.min+math.floor((number-c.min)/step+.5)*step)
  local called,ok,why=pcall(e.handle.set,c.id,number);if not called or ok==false then e.error=tostring(called and why or ok);return false end
  text_edit=nil;self.editing_value=nil;self.notice=nil;return true
 end
 local function reset_default(c)
  if not c or c.disabled or c.default==nil or not({slider=true,toggle=true,choice=true,keybind=true,color=true})[c.type]then return false end
  if c==opacity_control then write_slider(c,c.default,c.step);finish_opacity();drag=nil;return true end
  local called,ok,why=pcall(self.handle.set,c.id,c.default)
  if not called or ok==false then self.notice=tostring(called and why or ok);return false end
  text_edit=nil;self.editing_value=nil;popup=nil;popup_close_on_release=false;drag=nil;color_edit=nil;self.notice=nil;return true
 end
 function self.draw_cinema(w,h,key,hidden)
  panel_bounds=nil;hits={};last_focus=false
  if legend then legend.clear()end
  if self.light_gizmos then self.light_gizmos.cancel()end
  if hidden or not valid(w)or not valid(h)then view.draw({});return end
  if view.refresh_font then view.refresh_font()end
  local scale=math.max(.75,math.min(w/1920,h/1080));local x,y=20*scale,h-48*scale
  view.draw({
   {type='rect',x=x-8*scale,y=y-10*scale,w=340*scale,h=38*scale,c=T.background,a=.68,layer=300,ui_role='cinema_indicator'},
   {type='rect',x=x-8*scale,y=y+27*scale,w=340*scale,h=2*scale,c=T.gold,a=1,layer=301},
   {type='text',text='CINEMA CAMERA',x=x,y=y+10*scale,size=12*scale,c=T.gold,a=1,layer=310,text_bold=true,text_role='title'},
   {type='text',text=key..': reposition  |  Screenshot key: capture',x=x,y=y-5*scale,size=10*scale,c=T.white,a=1,layer=310,text_role='body'}})
 end
 function self.draw(w,h,focused,hidden,keys)
  -- Tab changes input ownership inside the same visible panel. Preserve the
  -- retained GUI/font planes; explicit focus loss still clears via suspend().
  if focused~=last_focus then suspend_input();last_focus=focused end
  if self.prepare_light_gizmos then self.prepare_light_gizmos(w,h,focused,hidden)end
  if hidden or not valid(w)or not valid(h)or not self.pages or #self.pages==0 then finish_layout();if self.light_gizmos then self.light_gizmos.cancel()end;if legend then legend.clear()end;view.draw({});panel_bounds=nil;hits={};resize=nil;scroll_drag=nil;move_panel=nil;return end
  if view.refresh_font then view.refresh_font()end
  local footer_extra=actions.slowmo and 36 or 0
  local commands={};hits={};reset_regions={};local base=math.max(.75,math.min(w/1920,h/1080));local maximum=math.min(w/(PANEL_WIDTH+48),h/(PANEL_HEIGHT+102+HUD_MARGIN+footer_extra));local minimum=math.min(maximum,math.max(.35,base*.65))
  local s=math.max(minimum,math.min(maximum,base*self.size_scale));local width=PANEL_WIDTH*s;local footprint=(PANEL_HEIGHT+62+footer_extra)*s
  local x=self.panel_x and self.panel_x*(w-width)or w-width-24*s;local strip_bottom=self.panel_y and self.panel_y*(h-footprint)or(16+HUD_MARGIN)*s
  x=math.max(8*s,math.min(w-width-8*s,x));strip_bottom=math.max(8*s,math.min(h-footprint-8*s,strip_bottom))
  local bottom=strip_bottom+62*s;local top=bottom+(PANEL_HEIGHT+footer_extra)*s;local left=x+16*s
  geometry={base=base,scale=s,minimum=minimum,maximum=maximum,x=x,strip_bottom=strip_bottom,w=w,h=h,width=width,height=footprint,body_height=PANEL_HEIGHT+footer_extra}
  panel_bounds={x=x,y=strip_bottom,w=width,h=top-strip_bottom}
  local function over(b,modal)return focused and (modal or not popup)and pointer_x and pointer_y and pointer_x>=b.x and pointer_x<=b.x+b.w and pointer_y>=b.y and pointer_y<=b.y+b.h end
  local function rect(rx,ry,rw,rh,c,a,layer,modal,role)
   local command={type='rect',x=rx,y=ry,w=rw,h=rh,c=c,a=a or 1,layer=layer or 300,popup=modal or nil,ui_role=role};commands[#commands+1]=command;return command
  end
  local function border(b,c,layer,modal)
   local stroke=math.min(1,b.w/2,b.h/2)
   rect(b.x,b.y,b.w,stroke,c,1,layer,modal);rect(b.x,b.y+b.h-stroke,b.w,stroke,c,1,layer,modal)
   rect(b.x,b.y+stroke,stroke,b.h-2*stroke,c,1,layer,modal);rect(b.x+b.w-stroke,b.y+stroke,stroke,b.h-2*stroke,c,1,layer,modal)
  end
  local function text(label,rx,ry,rw,rh,size,c,layer,modal,role)
   local font_size=size*s;local full=tostring(label or '');local shown=fit(full,rw-((role=='title'or role=='heading')and .65 or 0),font_size);local low,high,optical=0,font_size,0
   if view.text_metrics then local ok,m=pcall(view.text_metrics,font_size,shown);if ok and type(m)=='table'and type(m.min_y)=='number'and type(m.max_y)=='number'and m.max_y>m.min_y and m.max_y-m.min_y<font_size*3 then low,high=m.min_y,m.max_y;optical=m.optical_y or 0 end end
   local baseline_y=ry+(rh-(high-low))/2-low+optical;if rh>=high-low+2 then baseline_y=math.max(ry-low+1,math.min(ry+rh-high-1,baseline_y))end
   local command={type='text',text=shown,full_text=full,x=rx,y=baseline_y,size=font_size,c=c or T.white,a=1,layer=layer or 310,popup=modal or nil,
    text_bold=role=='title'or role=='heading',text_role=role or 'body',text_width=rw,text_bounds={x=rx,y=ry,w=rw,h=rh}}
   commands[#commands+1]=command;return command
  end
  local function surface(b,selected,disabled,key,field,modal)
   local hover=not disabled and over(b,modal);local pressed=not disabled and held and (pressed_key==key and hover or (drag and drag.c==key))
   local fill=disabled and T.panel or pressed and T.pressed or selected and(hover and T.selected_hover or T.selected)or hover and(field and T.field_hover or T.hover)or(field and T.field or T.panel)
   local command=rect(b.x,b.y,b.w,b.h,fill,modal and 1 or field and(pressed and .18 or hover and .12 or .02)or(selected and .18 or .04),modal and 901 or 302,modal,field and 'field'or 'button');command.hovered=hover==true;command.pressed=pressed==true;command.control_id=type(key)=='table'and key.id or nil;command.ui_key=type(key)=='string'and key or nil
   if modal or not field and hover then border(b,disabled and T.line or selected and T.gold or hover and T.border_hover or T.border,modal and 903 or 305,modal)end
  end
  local function icon(id,b,color)
   local ix,iy=b.x+8*s,b.y+8*s
   local function line(dx,dy,rw,rh)rect(ix+dx*s,iy+dy*s,rw*s,rh*s,color,1,309,nil,'tab_icon')end
   if id=='camera_tools'then line(0,0,15,9);line(3,9,5,3);rect(ix+5*s,iy+2*s,5*s,5*s,T.background,1,310)
   elseif id=='lens'then line(0,0,3,10);line(11,0,3,10);line(3,0,8,2);line(3,8,8,2);line(6,3,2,4)
   elseif id=='color'then line(0,0,3,5);line(5,0,3,10);line(10,0,3,7)
   elseif id=='effects'then line(0,0,14,2);line(3,4,11,2);line(0,8,11,2)
   elseif id=='composition'then line(0,0,15,2);line(0,9,15,2);line(0,2,2,7);line(13,2,2,7);line(7,2,1,7)
   elseif id=='lighting'then line(5,3,5,5);line(6,10,3,2);line(6,-1,3,2);line(0,4,3,3);line(12,4,3,3)
   else line(5,0,4,12);line(1,4,12,4)end
  end
  local function button(label,b,action,key,selected,font,icon_id,disabled)
   surface(b,selected,disabled,key,false);local pad=icon_id and 28 or 9
   if icon_id then icon(icon_id,b,selected and T.gold or T.muted)end
   text(label,b.x+pad*s,b.y,b.w-(pad+9)*s,b.h,font or 12,disabled and T.disabled or selected and T.gold or T.white)
   if selected then rect(b.x,b.y,b.w,2*s,T.gold,1,306)end
   b.action=action;b.key=key;if not disabled then hits[#hits+1]=b end
  end
  local opacity=menu_opacity()
  rect(x,bottom,width,top-bottom,T.background,opacity/100,300,false,'photo_panel')
  rect(x,top-1*s,width,1*s,T.gold,.55,303)
  text('WAR JOURNALIST',left,top-24*s,width-210*s,22*s,14,T.white,310,nil,'title')
  text(self.warming_up_scene and 'WARMING UP SCENE'or 'PHOTO MODE',left,top-39*s,width-210*s,14*s,10,self.warming_up_scene and T.gold or T.muted)
  text(focused and 'MENU FOCUS'or 'CAMERA FOCUS',x+width-164*s,top-39*s,148*s,14*s,10,focused and T.gold or T.muted)
  local move_bounds={x=x+4*s,y=top-42*s,w=width-188*s,h=40*s,move=true,key='move'}
  rect(move_bounds.x,move_bounds.y,move_bounds.w,move_bounds.h,T.header,over(move_bounds)and .08 or 0,308,nil,'move_handle')
  if focused then hits[#hits+1]=move_bounds end
  button((focused and 'Camera'or 'Edit menu')..' ['..keys.focus..']',{x=x+width-174*s,y=top-24*s,w=158*s,h=20*s},actions.focus,'focus',false,11)

  self.page=math.max(1,math.min(#self.pages,self.page));local tab_widths={};local tab_total=0;local tab_budget=width-32*s
  for i,page in ipairs(self.pages)do tab_widths[i]=math.max(56*s,measure(page.name,12*s)+42*s);tab_total=tab_total+tab_widths[i]end
  local tab_columns=tab_total<=tab_budget and #self.pages or math.ceil(#self.pages/2);local tab_rows=math.ceil(#self.pages/tab_columns)
  for row_index=0,tab_rows-1 do
   local first=row_index*tab_columns+1;local last=math.min(#self.pages,first+tab_columns-1);local row_total=0;local tab_x=left
   for i=first,last do row_total=row_total+tab_widths[i]end
   for i=first,last do local index=i;local page=self.pages[i]
    local tabw=row_total<=tab_budget and tab_widths[i]+(tab_budget-row_total)/(last-first+1)or tab_budget*tab_widths[i]/row_total
    button(page.name,{x=tab_x,y=top-(68+29*row_index)*s,w=tabw-4*s,h=25*s},function()self.page=index;self.selection=1;self.scroll=0;self.editing_value=nil;text_edit=nil;color_edit=nil;key_capture=nil;popup=nil;scroll_drag=nil;reveal_index=nil end,'tab:'..i,i==self.page,12,page.id);tab_x=tab_x+tabw
   end
  end
  local tab_extra=(tab_rows-1)*29*s
  local page=self.pages[self.page];rows={};selected_hit=nil;local row_sections={};local pending_section
  for _,c in ipairs(page.controls)do
   if type(c.photo_section)=='string'and c.photo_section~=''then pending_section=c.photo_section end
   local neutral_status=c.type=='text'and((c.status_only and(c.label or '')=='')or(c.id=='shader_status'and c.label=='Shader overlay: none'))
   if c.id~='controls'and not(actions.freeze and c.id=='freeze_player')and not(actions.slowmo and(c.id=='slowmo_speed'or c.id=='lock_camera'))and not c.layout_storage and not neutral_status then rows[#rows+1]=c;row_sections[#rows]=pending_section;pending_section=nil end
  end
  self.selection=math.max(1,math.min(#rows,self.selection));if not selectable(rows[self.selection])then for i,c in ipairs(rows)do if selectable(c)then self.selection=i;break end end end
  if self.editing_value and self.editing_value.disabled then self.editing_value=nil;text_edit=nil end;if popup and popup.c.disabled then popup=nil end
  rect(left,top-71*s-tab_extra,width-32*s,1,T.border,.6,301)
  if footer_extra>0 then
   local toolbar_y=top-111*s-tab_extra
   rect(x+8*s,toolbar_y,width-16*s,36*s,T.background,math.min(1,math.max(.72,opacity/100+.22)),301,false,'photo_global_controls_strip')
   rect(left,toolbar_y,width-32*s,1*s,T.border,.85,303,false,'photo_global_controls_separator')
  end
  local content_top=top-(77+footer_extra)*s-tab_extra;local content_bottom=bottom+(color_edit and 100 or 16)*s;local row=32*s
  local available=content_top-content_bottom
  local function row_height(index)return row+(row_sections[index]and 18*s or 0)end
  local function fit_rows(offset)
   local count,used=0,0
   for index=offset+1,#rows do local height=row_height(index);if used+height>available then break end;count=count+1;used=used+height end
   return math.max(1,count)
  end
  local tail_height=0;row_scroll_max=#rows
  for index=#rows,1,-1 do local height=row_height(index);if tail_height+height>available then break end;tail_height=tail_height+height;row_scroll_max=index-1 end
  self.scroll=math.max(0,math.min(row_scroll_max,self.scroll))
  if reveal_index then
   local target=math.max(1,math.min(#rows,reveal_index));reveal_index=nil
   if target<=self.scroll then self.scroll=target-1 end
   while target>self.scroll+fit_rows(self.scroll)and self.scroll<row_scroll_max do self.scroll=self.scroll+1 end
  end
  visible_count=fit_rows(self.scroll)
  local hovered_control;local popup_anchor
  local cursor_y=content_top
  for i=self.scroll+1,math.min(#rows,self.scroll+visible_count)do
   if row_sections[i]then
    local caption=row_sections[i]:upper();local label_width=math.min(width-64*s,measure(caption,9*s)+12*s)
    local heading=text(caption,left+3*s,cursor_y-14*s,label_width,12*s,9,T.muted,310,nil,'photo_section_label');heading.ui_role='photo_section_label'
    rect(left+label_width+8*s,cursor_y-8*s,width-48*s-label_width,1*s,T.border,.65,301,false,'photo_section_divider')
    cursor_y=cursor_y-18*s
   end
   local c=rows[i];local y=cursor_y-29*s;cursor_y=cursor_y-row;local rb={x=left-4*s,y=y,w=width-34*s,h=29*s};local hover=over(rb);local selected=focused and i==self.selection and not c.disabled
   reset_regions[#reset_regions+1]={x=rb.x,y=rb.y,w=rb.w,h=rb.h,c=c}
   if hover then hovered_control=c end
   rect(rb.x,rb.y,rb.w,rb.h,selected and T.gold or T.hover,selected and .12 or hover and .09 or 0,301,false,'setting_row')
   if selected then rect(rb.x,rb.y,rb.w,1*s,T.gold,.8,304);rect(rb.x,rb.y+rb.h-1*s,rb.w,1*s,T.gold,.55,304)end
   if c.type=='text'then
    local label=tostring(c.label or '');local first,second=label,'';local chars=glyphs(label);local width_budget=(width-52*s)
    if measure(label,11*s)>width_budget then local count=0;for n=1,#chars do if measure(table.concat(chars,'',1,n),11*s)>width_budget then break end;count=n end;first=table.concat(chars,'',1,count);second=table.concat(chars,'',count+1)end
    text(first,left+8*s,y+(second~=''and 12*s or 0),width_budget,(second~=''and 12 or 29)*s,11,T.muted)
    if second~=''then text(second,left+8*s,y,width_budget,12*s,11,T.muted)end
   else
    local single_action=c.type=='button'and value(c)==tostring(c.label or '')
    local color=c.disabled and T.disabled or T.white;local label=text(c.label,left+3*s,y,single_action and width-50*s or 340*s,29*s,16,color);label.control_id=c.id
    local b={x=single_action and rb.x or left+356*s,y=y+1*s,w=single_action and rb.w or width-390*s,h=27*s,c=c,key=c,row=i};local editing=self.editing_value==c or key_capture==c or color_edit==c
    surface(b,selected or editing,c.disabled,c,true);if popup and popup.c==c then popup_anchor=b end
    local display=key_capture==c and 'Press key; Esc cancels'or text_edit and text_edit.c==c and(text_edit.text..'|')or value(c);local pad=(c.type=='toggle'or c.type=='choice')and 30 or c.type=='color'and 34 or 9;local right_pad=(c.type=='choice'or c.type=='toggle')and 30 or 9
    if c.type~='slider'and not single_action then text(display,b.x+pad*s,b.y,b.w-(pad+right_pad)*s,b.h,16,c.disabled and T.disabled or c.type=='toggle'and self.handle.get(c.id)and T.enabled or T.white)end
    if c.type=='choice'or c.type=='toggle'then text('<',b.x+8*s,b.y,16*s,b.h,14,c.disabled and T.disabled or T.muted);text('>',b.x+b.w-24*s,b.y,16*s,b.h,14,c.disabled and T.disabled or T.muted)
    elseif c.type=='slider'then
     local fraction=math.max(0,math.min(1,(self.handle.get(c.id)-c.min)/(c.max-c.min)));local ink=c.disabled and T.disabled or T.gold
     b.track={x=b.x+8*s,y=b.y+2*s,w=b.w-100*s,h=23*s,c=c};b.numeric={x=b.x+b.w-78*s,y=b.y,w=78*s,h=b.h}
     local track=rect(b.track.x,b.y+12*s,b.track.w,3*s,T.border,.8,306,false,'slider_track');track.control_id=c.id
     rect(b.track.x,b.y+12*s,b.track.w*fraction,3*s,ink,.8,307);rect(math.max(b.track.x,math.min(b.track.x+b.track.w-4*s,b.track.x+b.track.w*fraction-2*s)),b.y+3*s,4*s,21*s,selected and T.white or ink,1,308)
     surface(b.numeric,editing,c.disabled,c,true);text(display,b.numeric.x+5*s,b.numeric.y,b.numeric.w-10*s,b.numeric.h,16,c.disabled and T.disabled or T.white)
    elseif c.type=='color'then local hex=self.handle.get(c.id);rect(b.x+8*s,b.y+6*s,20*s,16*s,{tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)},1,307)end
    if not c.disabled then local index=i;hits[#hits+1]={x=rb.x,y=rb.y,w=rb.w,h=rb.h,action=function()self.selection=index;self.editing_value=nil;text_edit=nil end,key=c};hits[#hits+1]=b;if i==self.selection then selected_hit=b end end
   end
  end
  local function scrollbar(kind,b,total,count,offset,modal,scroll_max)
   if total<=count then return end;local thumb=math.max(24*s,b.h*count/total);local travel=b.h-thumb;local maximum_scroll=scroll_max or total-count;local ty=b.y+travel*(1-offset/maximum_scroll)
   rect(b.x+5*s,b.y,3*s,b.h,T.line,1,modal and 902 or 306,modal);local thumb_b={x=b.x+3*s,y=ty,w=7*s,h=thumb};rect(thumb_b.x,ty,thumb_b.w,thumb,over(b,modal)and T.gold or T.border_hover,1,modal and 904 or 307,modal,'scrollbar')
   local function set(my,grab)local progress=math.max(0,math.min(1,(my-grab-b.y)/travel));local offset_value=math.floor((1-progress)*maximum_scroll+.5);if kind=='popup'then popup_scroll=offset_value else self.scroll=offset_value end end
   b.key='scroll:'..kind;b.action=function(_,my)local grab=my>=ty and my<=ty+thumb and my-ty or thumb/2;scroll_drag={move=function(py)set(py,grab)end};set(my,grab)end;hits[#hits+1]=b
  end
  scrollbar('rows',{x=x+width-18*s,y=content_bottom,w=16*s,h=available},#rows,visible_count,self.scroll,false,row_scroll_max)
  if color_edit then
   text('COLOR CHANNELS',left,bottom+73*s,148*s,16*s,10,T.muted);local hex=self.handle.get(color_edit.id);local bw=(width-44*s)/3
   -- The source row may scroll out of view while the channel editor is open.
   -- Keep its current swatch and exact HEX value beside the editor's own Apply.
   local swatch={x=left+158*s,y=bottom+71*s,w=52*s,h=20*s}
   local rgb={tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)}
   local preview=rect(swatch.x,swatch.y,swatch.w,swatch.h,rgb,1,307,false,'color_preview');preview.control_id=color_edit.id
   border(swatch,T.white,308)
   local hex_label=text(hex,left+220*s,bottom+68*s,100*s,25*s,13,T.white);hex_label.ui_role='color_hex';hex_label.control_id=color_edit.id
   button('Apply',{x=x+width-120*s,y=bottom+68*s,w=104*s,h=25*s},function()color_edit=nil;drag=nil;self.notice=nil end,'color:apply',true,12)
   for n=1,3 do local v=tonumber(hex:sub(n*2,n*2+1),16);local bx=left+(n-1)*(bw+6*s);text(({'R','G','B'})[n]..' '..v,bx,bottom+51*s,bw,18*s,11,T.white)
    local c={type='color_channel',base=color_edit.id,channel=n,min=0,max=255,step=1};local b={x=bx,y=bottom+29*s,w=bw,h=18*s,c=c,key='channel:'..n}
    surface(b,false,false,b.key,true);rect(bx,b.y,bw*v/255,2*s,T.gold,1,307);hits[#hits+1]=b
   end
  end
  local hint=hovered_control or rows[self.selection];local label=hint and tostring(hint.label or '')or 'Photo settings'
  text(hint and hint.disabled and 'Unavailable in this scene' or text_edit and(text_edit.error or(text_edit.typing and 'Enter / Space saves  |  Esc cancels  |  Ctrl+A replaces' or text_edit.c.fine_step and 'A/D step  |  Shift+A/D fine  |  Esc cancels' or 'Type number or A/D step  |  Enter / Space saves  |  Esc cancels'))or key_capture and 'Press the new shortcut  |  Esc cancels' or self.notice or(label..(hint and hint.type=='slider'and '  |  Shift+drag fine  |  Enter edits'or '  |  A/D changes  |  Enter edits')),left+24*s,bottom+1*s,width-56*s,12*s,10,hint and hint.disabled and T.disabled or T.muted)
  rect(x,strip_bottom,width,54*s,T.background,math.min(1,opacity/100+.02),300,false,'photo_controls_strip');rect(x,strip_bottom+54*s,width,1*s,T.border,.5,301)
  button('Toggle HUD',{x=left,y=strip_bottom+29*s,w=120*s,h=21*s},actions.hud,'hud',false,11)
  button('Hide controls ['..keys.hide..']',{x=left+128*s,y=strip_bottom+29*s,w=166*s,h=21*s},actions.hide,'hide',false,11)
  button('Exit photo mode',{x=left+302*s,y=strip_bottom+29*s,w=156*s,h=21*s},actions.exit,'exit',false,11)
  if actions.freeze then
   local ok,frozen,enabled=pcall(actions.freeze_state or function()return false,false end)
   button(ok and frozen==true and 'Resume Action'or 'Freeze Action',{x=left+(footer_extra>0 and 0 or 470)*s,y=footer_extra>0 and top-103*s-tab_extra or strip_bottom+29*s,w=(footer_extra>0 and 126 or 142)*s,h=21*s},actions.freeze,'freeze_action',ok and frozen==true,11,nil,not(ok and enabled==true))
  end
  if actions.slowmo then
   local ok,active,enabled=pcall(actions.slowmo_state or function()return false,false end)
   slowmo_control.disabled=not(ok and enabled==true)
   button(ok and active==true and 'Slow Motion: ON'or 'Slow Motion: OFF',{x=left+134*s,y=top-103*s-tab_extra,w=134*s,h=21*s},actions.slowmo,'slowmo_action',ok and active==true,11,nil,slowmo_control.disabled)
   local b={x=left+312*s,y=top-105*s-tab_extra,w=140*s,h=25*s,c=slowmo_control,key='slowmo_speed'}
   local rate=tonumber(self.handle.get('slowmo_speed'))or .2;local fraction=math.max(0,math.min(1,(rate-slowmo_control.min)/(slowmo_control.max-slowmo_control.min)))
   local ink=slowmo_control.disabled and T.disabled or T.gold
   text('Speed',left+276*s,b.y,36*s,b.h,10,slowmo_control.disabled and T.disabled or T.muted)
   surface(b,false,slowmo_control.disabled,'slowmo_speed',true)
   local track=rect(b.x+6*s,b.y+11*s,b.w-12*s,3*s,T.border_hover,.85,306,false,'slowmo_speed_track');track.control_id='slowmo_speed'
   rect(track.x,track.y,track.w*fraction,track.h,ink,1,307)
   rect(track.x+math.max(0,track.w-4*s)*fraction,track.y-4*s,4*s,11*s,ink,1,308)
   local label=text(string.format('%.0f%%',rate*100),left+458*s,b.y,42*s,b.h,12,ink,310,nil,'slowmo_speed_value');label.control_id='slowmo_speed'
   b.track={x=track.x,y=b.y,w=track.w,h=b.h};if focused and not slowmo_control.disabled then hits[#hits+1]=b end
   local locked=self.handle.get('lock_camera')==true
   button(locked and 'Lock Camera: ON'or 'Lock Camera: OFF',{x=left+508*s,y=top-103*s-tab_extra,w=216*s,h=21*s},function()return self.handle.set('lock_camera',not self.handle.get('lock_camera'))end,'lock_camera_action',locked,11)
  end
  local opacity_bounds={x=x+width-116*s,y=strip_bottom+27*s,w=100*s,h=25*s,c=opacity_control,key='menu_opacity'}
  local opacity_track={x=opacity_bounds.x+6*s,y=opacity_bounds.y+3*s,w=88*s,h=3*s};opacity_bounds.track=opacity_track
  local opacity_ink=focused and(over(opacity_bounds)or drag and drag.c==opacity_control)and T.gold or T.muted
  local opacity_label=text('Opacity '..string.format('%.0f',opacity)..'%',opacity_bounds.x+6*s,opacity_bounds.y+10*s,88*s,14*s,9,opacity_ink,310,nil,'menu_opacity');opacity_label.control_id='menu_opacity'
  local track=rect(opacity_track.x,opacity_track.y,opacity_track.w,opacity_track.h,T.border_hover,.85,306,false,'menu_opacity_track');track.control_id='menu_opacity'
  local fraction=(opacity-opacity_control.min)/(opacity_control.max-opacity_control.min)
  rect(opacity_track.x,opacity_track.y,opacity_track.w*fraction,opacity_track.h,opacity_ink,1,307)
  rect(opacity_track.x+(opacity_track.w-4*s)*fraction,opacity_track.y-4*s,4*s,11*s,opacity_ink,1,308,false,'menu_opacity_thumb')
  reset_regions[#reset_regions+1]=opacity_bounds;if focused then hits[#hits+1]=opacity_bounds end
  text('W/S rows  |  A/D values  |  Q/E tabs  |  Enter edits  |  Right-click resets',left,strip_bottom+6*s,width-32*s,16*s,11,T.muted)
  local grip={x=x+4*s,y=bottom+4*s,w=20*s,h=20*s};local grip_hover=over(grip);local grip_pressed=resize~=nil
  local grip_command=rect(grip.x,grip.y,grip.w,grip.h,grip_pressed and T.pressed or grip_hover and T.field_hover or T.panel,1,320,false,'resize_grip');grip_command.resize=true;grip_command.hovered=grip_hover==true;grip_command.pressed=grip_pressed
  for i=0,2 do rect(x+(7+i*5)*s,bottom+(7+i*5)*s,3*s,3*s,focused and(grip_hover or grip_pressed)and T.gold or T.muted,1,321)end
  if focused then hits[#hits+1]={x=x,y=bottom,w=28*s,h=30*s,resize=true,key='resize'}end
  if popup then
   if popup_anchor then popup.x,popup.y,popup.w=popup_anchor.x,popup_anchor.y,popup_anchor.w end
   hits={} -- The dropdown owns pointer input, including outside-click dismissal.
   hits[#hits+1]={x=0,y=0,w=w,h=h,action=function()popup=nil;scroll_drag=nil end,key='dismiss'}
   local option_h=32*s;popup_count=math.max(1,math.min(10,#popup.c.choices,math.floor((top-bottom-64*s)/option_h)))
   popup_scroll=math.max(0,math.min(#popup.c.choices-popup_count,popup_scroll));local pw=math.min(math.max(340*s,popup.w),w-16*s);local ph=popup_count*option_h+30*s
   local px=math.max(8*s,math.min(w-pw-8*s,popup.x+popup.w-pw));local py=math.max(bottom+10*s,math.min(top-ph-8*s,popup.y-ph))
   rect(px,py,pw,ph,T.panel,1,900,true,'dropdown_panel');border({x=px,y=py,w=pw,h=ph},T.border_hover,905,true)
   rect(px+1,py+ph-29*s,pw-2,28*s,T.header,1,901,true);text(popup.c.label,px+10*s,py+ph-29*s,pw-30*s,28*s,12,T.gold,910,true,'hint')
   for i=popup_scroll+1,popup_scroll+popup_count do local index=i;local oy=py+(popup_count-(i-popup_scroll))*option_h;local b={x=px+4*s,y=oy+1*s,w=pw-23*s,h=option_h-2*s,key='option:'..i}
    local selected=(self.choice_selection or self.handle.get(popup.c.id))==i;local hover=over(b,true);local pressed=held and pressed_key==b.key and hover
    if selected or hover or pressed then rect(b.x,b.y,b.w,b.h,pressed and T.pressed or selected and T.selected or T.field_hover,1,902,true,'dropdown_option')end
    if self.handle.get(popup.c.id)==i then rect(px+4*s,b.y,2*s,b.h,T.gold,1,904,true)end
    local command=text((selected and '> 'or '  ')..popup.c.choices[i],px+10*s,oy,pw-34*s,option_h,15,T.white,910,true);command.hovered=hover==true;command.pressed=pressed==true
    b.action=function()if not popup.c.disabled then self.handle.set(popup.c.id,index);self.choice_selection=index end;popup_close_on_release=true;scroll_drag=nil end;hits[#hits+1]=b
   end
   scrollbar('popup',{x=px+pw-18*s,y=py+2*s,w=16*s,h=popup_count*option_h-4*s},#popup.c.choices,popup_count,popup_scroll,true)
  end
  if legend then legend.draw(commands,w,h,focused,false,{x=x,y=bottom,w=width,h=top-bottom,scale=s})end
  if self.light_gizmos then self.light_gizmos.draw(commands,self.scene_pointer_blocked,self.scene_input_blocked())end
  view.draw(commands)
 end
 local function activate(b)
  if not b then return end;if b.action then b.action();return end;local c=b.c;if not c or c.disabled then return end
  if c.type=='toggle'then self.handle.set(c.id,not self.handle.get(c.id))
  elseif c.type=='choice'then if popup and popup.c==c then popup=nil else popup=b;popup_close_on_release=false;popup_scroll=math.max(0,self.handle.get(c.id)-1);self.choice_selection=self.handle.get(c.id)end
  elseif c.type=='slider'then if self.editing_value==c then finish_number()else begin_number(c)end
  elseif c.type=='button'then self.handle.activate(c.id)
  elseif c.type=='keybind'then key_capture=c;armed=false;baseline={}
  elseif c.type=='color'then if color_edit==c then color_edit=nil else color_edit=c end end
 end
 function self.tick(input,down,scene_checked)
  if not input or last_focus~=true then self.suspend();return end
  if not scene_checked and self.scene_tick(input,down)then held=false;return end
  if input.x then pointer_x=input.x end;if input.y then pointer_y=input.y end
  if not input.click then finish_layout();drag=nil;scroll_drag=nil;move_panel=nil;pressed_key=nil;if popup_close_on_release then popup=nil;popup_close_on_release=false end end
  if move_panel and input.click then
   if type(input.x)=='number'and type(input.y)=='number'and input.x==input.x and input.y==input.y and math.abs(input.x)<math.huge and math.abs(input.y)<math.huge then
    local g=move_panel.geometry;local margin=8*g.scale
    local px=math.max(margin,math.min(g.w-g.width-margin,move_panel.left+input.x-move_panel.x))
    local py=math.max(margin,math.min(g.h-g.height-margin,move_panel.bottom+input.y-move_panel.y))
    self.panel_x=px/(g.w-g.width);self.panel_y=py/(g.h-g.height);layout_dirty=true
   end
   held=input.click;return
  end
  if legend and not popup and not key_capture and not resize and not drag and not scroll_drag then
   if input.click and legend.pointer_over(input)and not blur_number()then held=input.click;return end
   if legend.tick(input,down)then held=input.click;right_held=nil;nav_ready=false;pressed_key=nil;return end
  end
  if resize then if not input.click then resize=nil elseif input.x and input.y and geometry then
   local height=geometry.body_height or PANEL_HEIGHT;local delta=(-PANEL_WIDTH*(input.x-resize.x)+height*(input.y-resize.y))/(PANEL_WIDTH*PANEL_WIDTH+height*height);self.size_scale=math.max(geometry.minimum,math.min(geometry.maximum,resize.scale+delta))/geometry.base;layout_dirty=true;held=input.click;return end end
  if scroll_drag and input.click and input.y then scroll_drag.move(input.y);held=input.click;return end
  if key_capture then
   if not input.click then armed=true end
   if armed then for k=1,255 do if not down(k)then baseline[k]=nil end;if k~=1 and k~=2 and down(k)and not baseline[k]then self.bound_key=k;if k~=27 then self.handle.set(key_capture.id,k)end;key_capture=nil;armed=false;break end end end
   right_held=down(2);held=input.click;return
  end
  local numeric_keys={8,46,189,109,190,110};for k=48,57 do numeric_keys[#numeric_keys+1]=k end;for k=96,105 do numeric_keys[#numeric_keys+1]=k end
  local nav_keys={81,69,87,83,65,68,13,32};for _,k in ipairs(numeric_keys)do nav_keys[#nav_keys+1]=k end
  local right_now=input.right_click;if right_now==nil then right_now=down(2)end
  if not nav_ready then for _,k in ipairs(nav_keys)do nav_held[k]=down(k);nav_time[k]=0 end;nav_ready=true;right_held=right_now end
  local function pressed(k,repeatable)
   local held_now=down(k);local old=nav_held[k];nav_held[k]=held_now;if not held_now then nav_time[k]=0;return false end
   nav_time[k]=(nav_time[k]or 0)+math.max(0,math.min(.1,input.dt or .016));if not old then nav_time[k]=-.3;return true end;if repeatable and nav_time[k]>=.1 then nav_time[k]=0;return true end;return false
  end
  local prev,nexttab=pressed(81,false),pressed(69,false);local up,downrow=pressed(87,true),pressed(83,true);local left,right=pressed(65,true),pressed(68,true);local enter=pressed(13,false);local space=pressed(32,false);local choose=enter or space
  local numeric_pressed={};for _,k in ipairs(numeric_keys)do if pressed(k,true)then numeric_pressed[#numeric_pressed+1]=k end end
  if text_edit and text_edit.c.commit_on_blur==true and(prev or nexttab or up or downrow)then
   if not blur_number()then held=input.click;return end
  end
  if right_now and not right_held then
   local c=popup and popup.c or nil
   if not c and pointer_x and pointer_y then for _,b in ipairs(reset_regions)do if pointer_x>=b.x and pointer_x<=b.x+b.w and pointer_y>=b.y and pointer_y<=b.y+b.h then c=b.c;break end end end
   c=c or rows[self.selection]
   if not text_edit or c==text_edit.c or blur_number()then reset_default(c)end
  end;right_held=right_now
  if text_edit then
   local e=text_edit;local ctrl=down(17)
   if ctrl and left then e.replace=true;e.error=nil
   elseif not ctrl then
    for _,k in ipairs(numeric_pressed)do
     if k==8 then e.text=e.replace and ''or e.text:sub(1,-2);e.replace=false;e.typing=true;e.error=nil
     elseif k==46 then e.text='';e.replace=false;e.typing=true;e.error=nil
     else local char=k>=48 and k<=57 and string.char(k)or k>=96 and k<=105 and tostring(k-96)or(k==189 or k==109)and '-'or(k==190 or k==110)and '.'
      if char then if e.replace then e.text='';e.replace=false end;if #e.text<24 then e.text=e.text..char end;e.typing=true;e.error=nil end
     end
    end
     if not e.typing and(left or right)then local c=e.c;local step=down(16)and c.fine_step or c.step;self.handle.set(c.id,math.max(c.min,math.min(c.max,self.handle.get(c.id)+(left and -step or step))));e.text=tostring(self.handle.get(c.id));e.replace=true end
   end
   if choose then finish_number()end
  elseif prev or nexttab then
   self.page=(self.page-1+(prev and -1 or 1))%#self.pages+1;self.selection=1;self.scroll=0;color_edit=nil;self.editing_value=nil;popup=nil;scroll_drag=nil;reveal_index=nil
  elseif up or downrow then
   if #rows>0 then move_row(up and -1 or 1)end
  elseif popup then
   if left or right then shift_value(popup.c,left and -1 or 1,down(16));self.choice_selection=self.handle.get(popup.c.id)
    if self.choice_selection<=popup_scroll then popup_scroll=self.choice_selection-1 elseif self.choice_selection>popup_scroll+popup_count then popup_scroll=self.choice_selection-popup_count end
   end
   if choose then if not popup.c.disabled then self.handle.set(popup.c.id,self.choice_selection or self.handle.get(popup.c.id))end;popup=nil end
  else
   local c=rows[self.selection]
   if left or right then shift_value(c,left and -1 or 1,down(16));reveal(self.selection)end
   if choose then if not selected_hit or selected_hit.c~=c then reveal(self.selection)else activate(selected_hit)end;if key_capture then for k=1,255 do if down(k)then baseline[k]=true end end end end
  end
  if input.wheel and input.wheel~=0 then if popup then popup_scroll=math.max(0,math.min(#popup.c.choices-popup_count,popup_scroll-(input.wheel>0 and 1 or -1)))else self.scroll=math.max(0,math.min(row_scroll_max,self.scroll-(input.wheel>0 and 1 or -1)));color_edit=nil end end
  if input.click and drag and input.x then scrub_slider(input.x,down(16))end
  if input.click and not held and input.x and input.y then
   local target;for i=#hits,1,-1 do local b=hits[i];if input.x>=b.x and input.x<=b.x+b.w and input.y>=b.y and input.y<=b.y+b.h then target=b;break end end
   local same=text_edit and target and target.c==text_edit.c and target.numeric and input.x>=target.numeric.x
   if not same and not blur_number()then held=input.click;return end
   if same then held=input.click;return end
   for i=#hits,1,-1 do local b=hits[i]
   if input.x>=b.x and input.x<=b.x+b.w and input.y>=b.y and input.y<=b.y+b.h then
    pressed_key=b.key or b.c
    if b.move then move_panel={x=input.x,y=input.y,left=geometry.x,bottom=geometry.strip_bottom,geometry=geometry};drag=nil
    elseif b.resize then resize={x=input.x,y=input.y,scale=geometry.scale};drag=nil
    elseif b.action then b.action(input.x,input.y)
    else local c=b.c;if not c.disabled then if b.row then self.selection=b.row end
     if c.type=='slider'then
      if b.numeric and input.x>=b.numeric.x then begin_number(c)else text_edit=nil;self.editing_value=nil;begin_slider(c,input.x,b.track or b,down(16))end
     elseif c.type=='color_channel'then begin_slider(c,input.x,b,down(16))
     else text_edit=nil;self.editing_value=nil;activate(b);if key_capture then for k=1,255 do if down(k)then baseline[k]=true end end end end
    end end;break
   end
  end end
  held=input.click
 end
 function self.dismiss()if popup then popup=nil;popup_close_on_release=false;scroll_drag=nil;return true elseif self.editing_value then self.editing_value=nil;text_edit=nil;self.notice=nil;return true elseif color_edit then color_edit=nil;return true end;return false end
 function self.editing_key()return key_capture~=nil end
 function self.editing_text()return text_edit~=nil end
 function self.editing_control(id)return text_edit and text_edit.c.id==id or self.editing_value and self.editing_value.id==id or false end
 function self.scene_input_blocked()
  return popup~=nil or key_capture~=nil or text_edit~=nil or color_edit~=nil or self.editing_value~=nil or drag~=nil or resize~=nil or scroll_drag~=nil or move_panel~=nil or legend and legend.capturing_pointer()or false
 end
 function self.scene_pointer_blocked(x,y)
  -- A modal dropdown excludes all scene picking, including its outside-click
  -- dismissal. The opaque panel and flyout exclude their entire surfaces.
  if self.scene_input_blocked()then return true end
  local b=panel_bounds
  return type(x)=='number'and type(y)=='number'and((b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h)or legend and legend.pointer_over({x=x,y=y}))or false
 end
 function self.scene_tick(input,down)
  if not last_focus or not self.light_gizmos then return false end
  return self.light_gizmos.tick(input,down,self.scene_pointer_blocked,self.scene_input_blocked())
 end
 function self.contains_pointer(x,y)
  return self.scene_pointer_blocked(x,y)or self.light_gizmos and self.light_gizmos.hit(x,y,self.scene_pointer_blocked,self.scene_input_blocked())or false
 end
 return self
end
return M

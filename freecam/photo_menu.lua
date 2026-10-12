-- Dedicated photo panel; authoritative MCM handles store every edit.
local M={}
local T={background={12,14,16},panel={19,21,23},header={25,27,29},border={62,66,69},border_hover={106,111,114},line={34,37,40},
 white={234,235,228},muted={154,159,159},gold={244,202,53},hover={29,31,33},selected={43,39,24},selected_hover={51,46,29},pressed={56,51,31},
 field={29,31,34},field_hover={39,42,45},enabled={176,205,176},disabled={105,111,113}}
local function glyphs(value)local result={};for c in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*')do result[#result+1]=c end;return result end
local function valid(v)return type(v)=='number'and v>0 and v<math.huge end
function M.new(view,actions)
 local self={page=1,scroll=0,selection=1,size_scale=1};local nav_held={};local nav_time={};local nav_ready=false;local last_focus
 local rows={};local selected_hit;local hits={};local held=false;local drag;local resize;local scroll_drag;local geometry;local pointer_x,pointer_y;local pressed_key
 local key_capture;local armed=false;local baseline={};local color_edit;local popup;local popup_close_on_release=false;local popup_scroll=0;local visible_count=1;local popup_count=1;local text_edit;local reset_regions={};local right_held
 function self.close()view.release();hits={};drag=nil;resize=nil;scroll_drag=nil;key_capture=nil;text_edit=nil;color_edit=nil;popup=nil;popup_close_on_release=false;self.bound_key=nil;self.editing_value=nil;self.notice=nil;nav_ready=false;held=false;right_held=nil;pointer_x,pointer_y=nil,nil;pressed_key=nil end
 function self.suspend()nav_ready=false;held=false;right_held=nil;drag=nil;resize=nil;scroll_drag=nil;pressed_key=nil;pointer_x,pointer_y=nil,nil end
 function self.bind(handle,pages)self.handle=handle;self.pages=pages end
 local function value(c)
  if c.type=='text'then return ''end;if c.type=='button'then return c.button_label or 'Activate'end
  local v=self.handle.get(c.id)
  if c.type=='choice'then return c.choices[v]or tostring(v)end
  if c.type=='toggle'then return v and 'ON'or 'OFF'end
  if c.type=='keybind'then local names={[0]='NONE',[9]='TAB',[13]='ENTER',[16]='SHIFT',[17]='CTRL',[18]='ALT',[27]='ESC',[32]='SPACE',[220]='\\'};return names[v]or(v>=32 and v<=126 and string.char(v)or('VK '..v))end
  if c.type=='slider'then return string.format(c.step<.01 and '%.3f'or c.step<1 and '%.2f'or '%.0f',v)end
  return tostring(v)
 end
 local function set_slider(c,x,b)
  if c.disabled then return end
  local t=math.max(0,math.min(1,(x-b.x)/b.w));local v=c.min+math.floor(((c.max-c.min)*t)/c.step+.5)*c.step;v=math.min(c.max,math.max(c.min,v))
  if c.type=='color_channel'then
   local hex=self.handle.get(c.base);local rgb={tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)}
   rgb[c.channel]=v;self.handle.set(c.base,string.format('#%02X%02X%02X',unpack(rgb)))
  else self.handle.set(c.id,v)end
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
  if index<=self.scroll then self.scroll=index-1 elseif index>self.scroll+visible_count then self.scroll=index-visible_count end
 end
 local function begin_number(c)
  self.editing_value=c;text_edit={c=c,text=tostring(self.handle.get(c.id)),replace=true,typing=false};self.notice=nil
 end
 local function finish_number()
  if not text_edit then return true end;local e=text_edit;local c=e.c
  if c.disabled then text_edit=nil;self.editing_value=nil;return false end
  local number=tonumber(e.text)
  if not number or number~=number or math.abs(number)==math.huge then e.error='Enter a valid number';return false end
  number=math.max(c.min,math.min(c.max,number));number=math.min(c.max,c.min+math.floor((number-c.min)/c.step+.5)*c.step)
  local called,ok,why=pcall(self.handle.set,c.id,number);if not called or ok==false then e.error=tostring(called and why or ok);return false end
  text_edit=nil;self.editing_value=nil;self.notice=nil;return true
 end
 local function reset_default(c)
  if not c or c.disabled or c.default==nil or not({slider=true,toggle=true,choice=true,keybind=true,color=true})[c.type]then return false end
  local called,ok,why=pcall(self.handle.set,c.id,c.default)
  if not called or ok==false then self.notice=tostring(called and why or ok);return false end
  text_edit=nil;self.editing_value=nil;popup=nil;popup_close_on_release=false;drag=nil;color_edit=nil;self.notice=nil;return true
 end
 function self.draw(w,h,focused,hidden,keys)
  if focused~=last_focus then self.suspend();last_focus=focused end
  if hidden or not valid(w)or not valid(h)or not self.pages or #self.pages==0 then view.draw({});hits={};resize=nil;scroll_drag=nil;return end
  if view.refresh_font then view.refresh_font()end
  local commands={};hits={};reset_regions={};local base=math.min(w/1920,h/1080)*1.15;local maximum=math.min(w/568,h/868);local minimum=math.min(maximum,math.max(.5,base*.65))
  local s=math.max(minimum,math.min(maximum,base*self.size_scale));local width=520*s;local x=w-width-24*s;local top=h-24*s;local bottom=top-820*s;local left=x+16*s
  geometry={base=base,scale=s,minimum=minimum,maximum=maximum}
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
   local command=rect(b.x,b.y,b.w,b.h,fill,1,modal and 901 or 302,modal,field and 'field'or 'button');command.hovered=hover==true;command.pressed=pressed==true;command.control_id=type(key)=='table'and key.id or nil;command.ui_key=type(key)=='string'and key or nil
   border(b,disabled and T.line or selected and T.gold or hover and T.border_hover or T.border,modal and 903 or 305,modal)
  end
  local function button(label,b,action,key,selected)
   surface(b,selected,false,key,false);text(label,b.x+9*s,b.y,b.w-18*s,b.h,15,selected and T.gold or T.white)
   if selected then rect(b.x,b.y,b.w,2*s,T.gold,1,306)end
   b.action=action;b.key=key;hits[#hits+1]=b
  end
  rect(x,bottom,width,top-bottom,T.background,.99,300,false,'photo_panel');border({x=x,y=bottom,w=width,h=top-bottom},T.border,301)
  rect(x+1,top-74*s,width-2,73*s,T.header,1,302);rect(x+1,top-2*s,width-2,1*s,T.gold,1,303)
  text('WAR JOURNALIST',left,top-47*s,width-160*s,32*s,24,T.white,310,nil,'title')
  text('PHOTO MODE',left,top-68*s,width-32*s,18*s,12,T.muted)
  local badge={x=x+width-134*s,y=top-43*s,w=118*s,h=24*s};rect(badge.x,badge.y,badge.w,badge.h,focused and T.selected or T.field,1,304)
  text(focused and 'MENU FOCUS'or 'CAMERA FOCUS',badge.x+8*s,badge.y,badge.w-16*s,badge.h,11,focused and T.gold or T.muted)
  button((focused and 'Return to camera'or 'Edit photo settings')..' ['..keys.focus..']',{x=left,y=top-110*s,w=width-32*s,h=30*s},actions.focus,'focus')
  self.page=math.max(1,math.min(#self.pages,self.page));local tab_widths={};local tab_total=0;local tab_budget=width-32*s
  for i,page in ipairs(self.pages)do tab_widths[i]=math.max(64*s,measure(page.name,15*s)+22*s);tab_total=tab_total+tab_widths[i]end
  local tab_x=left
  for i,page in ipairs(self.pages)do local index=i
   local tabw=tab_total<=tab_budget and tab_widths[i]+(tab_budget-tab_total)/#self.pages or tab_budget*tab_widths[i]/tab_total
   button(page.name,{x=tab_x,y=top-150*s,w=tabw-4*s,h=30*s},function()self.page=index;self.selection=1;self.scroll=0;self.editing_value=nil;text_edit=nil;color_edit=nil;key_capture=nil;popup=nil;scroll_drag=nil end,'tab:'..i,i==self.page);tab_x=tab_x+tabw
  end
  local page=self.pages[self.page];rows={};selected_hit=nil
  for _,c in ipairs(page.controls)do
   local neutral_status=c.type=='text'and((c.status_only and(c.label or '')=='')or(c.id=='shader_status'and c.label=='Shader overlay: none'))
   if c.id~='controls'and not neutral_status then rows[#rows+1]=c end
  end
  self.selection=math.max(1,math.min(#rows,self.selection));if not selectable(rows[self.selection])then for i,c in ipairs(rows)do if selectable(c)then self.selection=i;break end end end
  if self.editing_value and self.editing_value.disabled then self.editing_value=nil;text_edit=nil end;if popup and popup.c.disabled then popup=nil end
  text(page.name,left,top-185*s,width-120*s,27*s,19,T.white,310,nil,'heading');text(tostring(#rows)..' settings',x+width-110*s,top-185*s,86*s,27*s,12,T.muted)
  rect(left,top-191*s,width-32*s,1,T.line,1,301)
  local content_top=top-207*s;local content_bottom=bottom+(color_edit and 224 or 164)*s;local row=40*s
  visible_count=math.max(1,math.floor((content_top-content_bottom)/row));self.scroll=math.max(0,math.min(math.max(0,#rows-visible_count),self.scroll))
  local hovered_control;local popup_anchor
  for i=self.scroll+1,math.min(#rows,self.scroll+visible_count)do
   local c=rows[i];local y=content_top-34*s-(i-self.scroll-1)*row;local rb={x=left-4*s,y=y,w=width-34*s,h=34*s};local hover=over(rb);local selected=focused and i==self.selection and not c.disabled
   reset_regions[#reset_regions+1]={x=rb.x,y=rb.y,w=rb.w,h=rb.h,c=c}
   if hover then hovered_control=c end
   rect(rb.x,rb.y,rb.w,rb.h,selected and T.selected or hover and T.hover or i%2==0 and T.panel or T.background,1,301,false,'setting_row')
   if selected then rect(rb.x,rb.y,2*s,rb.h,T.gold,1,304)end
   if c.type=='text'then
    local label=tostring(c.label or '');local first,second=label,'';local chars=glyphs(label);local width_budget=(width-52*s)
    if measure(label,13*s)>width_budget then local count=0;for n=1,#chars do if measure(table.concat(chars,'',1,n),13*s)>width_budget then break end;count=n end;first=table.concat(chars,'',1,count);second=table.concat(chars,'',count+1)end
    text(first,left+8*s,y+(second~=''and 16*s or 0),width_budget,(second~=''and 16 or 34)*s,13,T.muted)
    if second~=''then text(second,left+8*s,y,width_budget,16*s,13,T.muted)end
   else
    local color=c.disabled and T.disabled or T.white;local label=text(c.label,left+3*s,y,252*s,34*s,16,color);label.control_id=c.id
    local b={x=left+268*s,y=y+3*s,w=202*s,h=28*s,c=c,key=c,row=i};local editing=self.editing_value==c or key_capture==c or color_edit==c
    surface(b,selected or editing,c.disabled,c,true);if popup and popup.c==c then popup_anchor=b end
    local display=key_capture==c and 'Press key; Esc cancels'or text_edit and text_edit.c==c and(text_edit.text..'|')or value(c);local pad=c.type=='toggle'and 36 or c.type=='color'and 34 or 9;local right_pad=c.type=='choice'and 34 or 9
    if c.type~='slider'then text(display,b.x+pad*s,b.y,b.w-(pad+right_pad)*s,b.h,15,c.disabled and T.disabled or c.type=='toggle'and self.handle.get(c.id)and T.enabled or T.white)end
    if c.type=='choice'then text('v',b.x+b.w-24*s,b.y,16*s,b.h,14,c.disabled and T.disabled or T.muted)
    elseif c.type=='slider'then
     local fraction=math.max(0,math.min(1,(self.handle.get(c.id)-c.min)/(c.max-c.min)));local ink=c.disabled and T.disabled or T.gold
     b.track={x=b.x+8*s,y=b.y+3*s,w=118*s,h=22*s,c=c};b.numeric={x=b.x+134*s,y=b.y,w=68*s,h=b.h}
     local track=rect(b.track.x,b.y+11*s,b.track.w,6*s,T.line,1,306,false,'slider_track');track.control_id=c.id
     rect(b.track.x,b.y+12*s,b.track.w*fraction,4*s,ink,1,307);rect(math.max(b.track.x,math.min(b.track.x+b.track.w-4*s,b.track.x+b.track.w*fraction-2*s)),b.y+5*s,4*s,18*s,selected and T.white or ink,1,308)
     surface(b.numeric,editing,c.disabled,c,true);text(display,b.numeric.x+5*s,b.numeric.y,b.numeric.w-10*s,b.numeric.h,15,c.disabled and T.disabled or T.white)
    elseif c.type=='toggle'then local on=self.handle.get(c.id);rect(b.x+8*s,b.y+9*s,20*s,10*s,T.line,1,306);rect(b.x+(on and 19 or 9)*s,b.y+7*s,8*s,14*s,c.disabled and T.disabled or on and T.gold or T.muted,1,307)
    elseif c.type=='color'then local hex=self.handle.get(c.id);rect(b.x+8*s,b.y+6*s,20*s,16*s,{tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)},1,307)end
    if not c.disabled then local index=i;hits[#hits+1]={x=rb.x,y=rb.y,w=rb.w,h=rb.h,action=function()self.selection=index;self.editing_value=nil;text_edit=nil end,key=c};hits[#hits+1]=b;if i==self.selection then selected_hit=b end end
   end
  end
  local function scrollbar(kind,b,total,count,offset,modal)
   if total<=count then return end;local thumb=math.max(24*s,b.h*count/total);local travel=b.h-thumb;local maximum_scroll=total-count;local ty=b.y+travel*(1-offset/maximum_scroll)
   rect(b.x+5*s,b.y,3*s,b.h,T.line,1,modal and 902 or 306,modal);local thumb_b={x=b.x+3*s,y=ty,w=7*s,h=thumb};rect(thumb_b.x,ty,thumb_b.w,thumb,over(b,modal)and T.gold or T.border_hover,1,modal and 904 or 307,modal,'scrollbar')
   local function set(my,grab)local progress=math.max(0,math.min(1,(my-grab-b.y)/travel));local offset_value=math.floor((1-progress)*maximum_scroll+.5);if kind=='popup'then popup_scroll=offset_value else self.scroll=offset_value end end
   b.key='scroll:'..kind;b.action=function(_,my)local grab=my>=ty and my<=ty+thumb and my-ty or thumb/2;scroll_drag={move=function(py)set(py,grab)end};set(my,grab)end;hits[#hits+1]=b
  end
  scrollbar('rows',{x=x+width-18*s,y=content_top-visible_count*row,w=16*s,h=visible_count*row},#rows,visible_count,self.scroll)
  if color_edit then
   text('COLOR CHANNELS',left,bottom+196*s,width-32*s,18*s,12,T.muted);local hex=self.handle.get(color_edit.id);local bw=(width-44*s)/3
   for n=1,3 do local v=tonumber(hex:sub(n*2,n*2+1),16);local bx=left+(n-1)*(bw+6*s);text(({'R','G','B'})[n]..' '..v,bx,bottom+176*s,bw,20*s,13,T.white)
    local c={type='color_channel',base=color_edit.id,channel=n,min=0,max=255,step=1};local b={x=bx,y=bottom+155*s,w=bw,h=20*s,c=c,key='channel:'..n}
    surface(b,false,false,b.key,true);rect(bx,b.y,bw*v/255,2*s,T.gold,1,307);hits[#hits+1]=b
   end
  end
  local hint=hovered_control or rows[self.selection];local label=hint and tostring(hint.label or '')or 'Photo settings'
  text(label,left,bottom+136*s,width-32*s,18*s,12,T.muted)
  text(hint and hint.disabled and 'Unavailable in this scene' or text_edit and(text_edit.error or(text_edit.typing and 'Enter / Space saves  |  Esc cancels  |  Ctrl+A replaces' or 'Type number or A/D step  |  Enter / Space saves  |  Esc cancels'))or key_capture and 'Press the new shortcut  |  Esc cancels' or self.notice or 'Enter / Space edits  |  Right-click resets default',left,bottom+117*s,width-32*s,18*s,11,hint and hint.disabled and T.disabled or T.muted)
  rect(left,bottom+112*s,width-32*s,1,T.line,1,301)
  button('Toggle HUD',{x=left,y=bottom+76*s,w=154*s,h=30*s},actions.hud,'hud');button('Hide controls ['..keys.hide..']',{x=left+160*s,y=bottom+76*s,w=width-192*s,h=30*s},actions.hide,'hide')
  button('Exit photo mode',{x=left,y=bottom+38*s,w=width-32*s,h=30*s},actions.exit,'exit')
  text('Q/E tabs  |  WASD select/edit  |  Enter / Space choose',left+12*s,bottom+14*s,width-58*s,18*s,12,T.muted)
  local grip={x=x+4*s,y=bottom+4*s,w=20*s,h=20*s};local grip_hover=over(grip);local grip_pressed=resize~=nil
  local grip_command=rect(grip.x,grip.y,grip.w,grip.h,grip_pressed and T.pressed or grip_hover and T.field_hover or T.panel,1,320,false,'resize_grip');grip_command.resize=true;grip_command.hovered=grip_hover==true;grip_command.pressed=grip_pressed
  for i=0,2 do rect(x+(7+i*5)*s,bottom+(7+i*5)*s,3*s,3*s,focused and(grip_hover or grip_pressed)and T.gold or T.muted,1,321)end
  text('RESIZE',left+12*s,bottom+1*s,width-58*s,12*s,9,T.muted)
  if focused then hits[#hits+1]={x=x,y=bottom,w=28*s,h=30*s,resize=true,key='resize'}end
  if popup then
   if popup_anchor then popup.x,popup.y,popup.w=popup_anchor.x,popup_anchor.y,popup_anchor.w end
   hits={} -- The dropdown owns pointer input, including outside-click dismissal.
   hits[#hits+1]={x=0,y=0,w=w,h=h,action=function()popup=nil;scroll_drag=nil end,key='dismiss'}
   local option_h=32*s;popup_count=math.max(1,math.min(10,#popup.c.choices,math.floor((top-bottom-64*s)/option_h)))
   popup_scroll=math.max(0,math.min(#popup.c.choices-popup_count,popup_scroll));local pw=math.min(340*s,w-16*s);local ph=popup_count*option_h+30*s
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
 function self.tick(input,down)
  if not input or last_focus~=true then self.suspend();return end
  if input.x then pointer_x=input.x end;if input.y then pointer_y=input.y end
  if not input.click then drag=nil;scroll_drag=nil;pressed_key=nil;if popup_close_on_release then popup=nil;popup_close_on_release=false end end
  if resize then if not input.click then resize=nil elseif input.x and input.y and geometry then
   local delta=(-520*(input.x-resize.x)-820*(input.y-resize.y))/(520*520+820*820);self.size_scale=math.max(geometry.minimum,math.min(geometry.maximum,resize.scale+delta))/geometry.base;held=input.click;return end end
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
  if right_now and not right_held then
   local c=popup and popup.c or nil
   if not c and pointer_x and pointer_y then for _,b in ipairs(reset_regions)do if pointer_x>=b.x and pointer_x<=b.x+b.w and pointer_y>=b.y and pointer_y<=b.y+b.h then c=b.c;break end end end
   reset_default(c or rows[self.selection])
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
    if not e.typing and(left or right)then local c=e.c;self.handle.set(c.id,math.max(c.min,math.min(c.max,self.handle.get(c.id)+(left and -c.step or c.step))));e.text=tostring(self.handle.get(c.id));e.replace=true end
   end
   if choose then finish_number()end
  elseif prev or nexttab then
   self.page=(self.page-1+(prev and -1 or 1))%#self.pages+1;self.selection=1;self.scroll=0;color_edit=nil;self.editing_value=nil;popup=nil;scroll_drag=nil
  elseif popup then
   if up or downrow or left or right then self.choice_selection=math.max(1,math.min(#popup.c.choices,(self.choice_selection or self.handle.get(popup.c.id))+((up or left)and -1 or 1)))
    if self.choice_selection<=popup_scroll then popup_scroll=self.choice_selection-1 elseif self.choice_selection>popup_scroll+popup_count then popup_scroll=self.choice_selection-popup_count end
   end
   if choose then if not popup.c.disabled then self.handle.set(popup.c.id,self.choice_selection or self.handle.get(popup.c.id))end;popup=nil end
  else
   if #rows>0 and(up or downrow or((left or right)and not self.editing_value))then local index=self.selection
    for _=1,#rows do index=(index-1+((up or left)and -1 or 1))%#rows+1;if selectable(rows[index])then self.selection=index;break end end;self.editing_value=nil;reveal(self.selection)
   end
   local c=rows[self.selection]
   if selectable(c)and self.editing_value==c and(left or right)and c.type=='slider'then self.handle.set(c.id,math.max(c.min,math.min(c.max,self.handle.get(c.id)+(left and -c.step or c.step))))end
   if choose then if not selected_hit or selected_hit.c~=c then reveal(self.selection)else activate(selected_hit)end;if key_capture then for k=1,255 do if down(k)then baseline[k]=true end end end end
  end
  if input.wheel and input.wheel~=0 then if popup then popup_scroll=math.max(0,math.min(#popup.c.choices-popup_count,popup_scroll-(input.wheel>0 and 1 or -1)))else self.scroll=math.max(0,math.min(math.max(0,#rows-visible_count),self.scroll-(input.wheel>0 and 1 or -1)));color_edit=nil end end
  if input.click and drag and input.x then set_slider(drag.c,input.x,drag)end
  if input.click and not held and input.x and input.y then for i=#hits,1,-1 do local b=hits[i]
   if input.x>=b.x and input.x<=b.x+b.w and input.y>=b.y and input.y<=b.y+b.h then
    pressed_key=b.key or b.c
    if b.resize then resize={x=input.x,y=input.y,scale=geometry.scale};drag=nil
    elseif b.action then b.action(input.x,input.y)
    else local c=b.c;if not c.disabled then if b.row then self.selection=b.row end
     if c.type=='slider'then
      if b.numeric and input.x>=b.numeric.x then begin_number(c)else text_edit=nil;self.editing_value=nil;local track=b.track or b;set_slider(c,input.x,track);drag=track end
     elseif c.type=='color_channel'then set_slider(c,input.x,b);drag=b
     else text_edit=nil;self.editing_value=nil;activate(b);if key_capture then for k=1,255 do if down(k)then baseline[k]=true end end end end
    end end;break
   end
  end end
  held=input.click
 end
 function self.dismiss()if popup then popup=nil;popup_close_on_release=false;scroll_drag=nil;return true elseif self.editing_value then self.editing_value=nil;text_edit=nil;self.notice=nil;return true elseif color_edit then color_edit=nil;return true end;return false end
 function self.editing_key()return key_capture~=nil end
 function self.editing_text()return text_edit~=nil end
 return self
end
return M

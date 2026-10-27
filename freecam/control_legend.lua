-- Photo menu companion; stores normalized layout through the same author handle.
local M={}
local gold={244,202,53};local dark={12,14,16};local muted={154,159,159};local white={234,235,228}
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
function M.key_label(v)
 local names={[0]='NONE',[8]='BACKSPACE',[9]='TAB',[13]='ENTER',[16]='SHIFT',[17]='CTRL',[18]='ALT',[27]='ESC',[32]='SPACE',[33]='PG UP',[34]='PG DN',[35]='END',[36]='HOME',[37]='LEFT',[38]='UP',[39]='RIGHT',[40]='DOWN',[45]='INSERT',[46]='DELETE',[186]=';',[187]='=',[188]=',',[189]='-',[190]='.',[191]='/',[192]='`',[219]='[',[220]='\\',[221]=']',[222]="'"}
 if names[v]then return names[v]end
 if v and v>=112 and v<=123 then return 'F'..(v-111)end
 if v and v>=96 and v<=105 then return 'NUM '..(v-96)end
 if v and(v>=48 and v<=57 or v>=65 and v<=90)then return string.char(v)end
 return 'VK '..tostring(v)
end
-- A binding's label: the key a loader's bindings helper holds for it (hosted_label, set by the
-- runtime), else our stored virtual key.
function M.binding_label(id,handle)return M.hosted_label and M.hosted_label(id)or M.key_label(handle and handle.get(id))end
function M.new(view)
 local self={};local handle;local geometry;local gesture;local held=false;local visible=false;local owning=false;local pointer_x,pointer_y
 local function get(id,default)local v=handle and handle.get(id);if v==nil then return default end;return v end
 local function num(id,default)local v=get(id,default);return type(v)=='number'and v==v and math.abs(v)<math.huge and v or default end
 local function key(id,fallback)return M.hosted_label and M.hosted_label(id)or M.key_label(get(id,fallback))end
 function self.bind(value)if handle~=value then self.clear()end;handle=value end
 function self.clear()gesture=nil;held=false;visible=false;owning=false;geometry=nil;pointer_x,pointer_y=nil,nil end
 local function persist(g)
  handle.set('legend_x',g.w>g.size and clamp(g.x/(g.w-g.size)*100,0,100)or 0)
  handle.set('legend_y',g.h>g.size and clamp(g.y/(g.h-g.size)*100,0,100)or 0)
  handle.set('legend_size',clamp(g.size/math.min(g.w,g.h)*100,25,70))
 end
 local function inside(input,b)return input and input.x and input.y and b and input.x>=b.x and input.x<=b.x+b.w and input.y>=b.y and input.y<=b.y+b.h end
 function self.draw(commands,w,h,focused,hidden,parent)
  if hidden or get('show_legend',true)==false or not handle then self.clear();return end
  visible=true;owning=focused==true;if not owning then gesture=nil;held=false end
  local shortest=math.min(w,h);local size=shortest*clamp(num('legend_size',38),25,70)/100
  local x=(w-size)*clamp(num('legend_x',2),0,100)/100;local y=(h-size)*clamp(num('legend_y',2),0,100)/100
  local docked=get('legend_docked',true)==true;local open=get('legend_open',true)~=false
  local ps=parent and parent.scale or size/410;local tabw=24*ps;local tabh=38*ps
  local tab_y=(h-tabh)*clamp(num('legend_tab_y',75),0,100)/100
  if docked then
   x=0;y=clamp(tab_y+tabh-size,0,h-size)
  end
  local s=size/410;local pad=12*s;local stripe=10*s;local header=44*s
  local tab={x=docked and open and math.min(size,w-tabw)or 0,y=tab_y,w=tabw,h=tabh}
  local dock_button={x=x+size-75*s,y=y+size-37*s,w=63*s,h=24*s}
  geometry={x=x,y=y,size=size,w=w,h=h,grip=24*s,header=header,parent=parent,docked=docked,open=open,tab=tab,dock_button=dock_button,snap=24*ps}
  local function rect(rx,ry,rw,rh,c,role)commands[#commands+1]={type='rect',x=rx,y=ry,w=rw,h=rh,c=c,a=.96,layer=330,ui_role=role}end
  local function text(label,rx,ry,width,font,role)
   local shown=label;local budget=width;local function measure(v)return view.measure and view.measure(v,font)or #v*font*.62 end
   if measure(shown)>budget then while #shown>0 and measure(shown..'...')>budget do shown=shown:sub(1,-2)end;shown=shown..'...'end
   commands[#commands+1]={type='text',text=shown,full_text=label,x=rx,y=ry,size=font,c=role=='legend_key'and gold or role=='legend_hint'and muted or white,a=1,layer=340,text_role=role,text_bold=role=='legend_title',text_width=width,text_bounds={x=rx,y=ry,w=width,h=font*1.4}}
  end
  if tab then
   rect(tab.x,tab.y,tab.w,tab.h,{25,27,29},'legend_flyout_toggle');commands[#commands].a=1;commands[#commands].legend_open=open
   text(open and '<'or '>',tab.x+4*ps,tab.y+10*ps,tab.w-8*ps,14*ps,'legend_toggle_label')
  end
  if not open then if gesture and gesture.kind~='tab'then gesture=nil end;return end
  rect(x,y,size,size,dark,'control_legend');rect(x,y+size-stripe,size,stripe,gold,'legend_hazard');rect(x,y,size,stripe,gold,'legend_hazard')
  -- Clip diagonal bands at the panel edges, then fan-triangulate the polygon.
  local function hazard(yy)
   local band=14*s
   for dx=-stripe-band,size,band*2 do
    local p={{dx,0},{dx+band,0},{dx+band+stripe,stripe},{dx+stripe,stripe}}
    for _,edge in ipairs({0,size})do
     local out={};local a=p[#p]
     for _,b in ipairs(p)do
      local ai=edge==0 and a[1]>=edge or edge~=0 and a[1]<=edge;local bi=edge==0 and b[1]>=edge or edge~=0 and b[1]<=edge
      if ai~=bi then local t=(edge-a[1])/(b[1]-a[1]);out[#out+1]={edge,a[2]+t*(b[2]-a[2])}end
      if bi then out[#out+1]=b end;a=b
     end;p=out;if #p==0 then break end
    end
    for n=2,#p-1 do commands[#commands+1]={type='triangle',points={x+p[1][1],yy+p[1][2],x+p[n][1],yy+p[n][2],x+p[n+1][1],yy+p[n+1][2]},c=dark,a=1,layer=332,ui_role='legend_hazard_band'}end
   end
  end
  hazard(y);hazard(y+size-stripe)
  text(focused and 'MENU CONTROLS'or 'CAMERA CONTROLS',x+pad,y+size-35*s,size-2*pad-70*s,16*s,'legend_title')
  if parent then rect(dock_button.x,dock_button.y,dock_button.w,dock_button.h,{29,31,34},'legend_dock_button');text(docked and 'UNDOCK'or 'DOCK',dock_button.x+5*s,dock_button.y+7*s,dock_button.w-10*s,10*s,'legend_key')end
  local entries=focused and {
   {'W / S','Menu up / down'},{'A / D','Value / option'}, {'Q / E','Menu tabs'},
   {'ENTER / SPACE','Edit / save'},{'SHIFT + A / D','Fine focus step'},{'RIGHT CLICK','Reset value'},
   {'ESC','Cancel / return'},{key('focus_key',9),'Return to camera'},
   {key('toggle_key',80),'Photo on / off'},{key('handycam_key',122),'Start / end Handycam'},{key('hide_controls_key',72),'Show / hide controls'}
  }or {
   {key('forward_key',87)..' / '..key('back_key',83),'Forward / back'},
   {key('left_key',65)..' / '..key('right_key',68),'Left / right'},
   {key('up_key',16)..' / '..key('down_key',17),'Rise / descend'},
   {'MOUSE','Look around'}, {'WHEEL','Movement speed'},
   {key('roll_left_key',81)..' / '..key('roll_right_key',69),'Roll camera'},
   {key('lock_camera_key',76),'Lock camera'},{key('slowmo_key',220),'Solo slow motion'},
   {key('focus_key',9),'Edit photo menu'},{key('toggle_key',80),'Photo on / off'},
   {key('handycam_key',122),'Start / end Handycam'},{key('hide_controls_key',72),'Show / hide controls'},{'ESC','Exit photo mode'}}
  if focused and get('focus_mode',1)==2 then entries[#entries+1]={'DOUBLE-CLICK','Focus scene subject'}end
  local columns=get('legend_columns',2)==1 and 2 or 3;local rows=math.ceil(#entries/columns)
  local colw=(size-2*pad)/columns;local usable=size-header-stripe-34*s;local rowh=usable/rows
  local font=columns==2 and 12*s or 11*s
  for i,e in ipairs(entries)do local col=math.floor((i-1)/rows);local row=(i-1)%rows;local rx=x+pad+col*colw;local ry=y+size-header-(row+1)*rowh
   text(e[1],rx,ry+rowh*.55,colw-8*s,font,'legend_key');text(e[2],rx,ry+rowh*.18,colw-8*s,font,'legend_action')
  end
  text(focused and(docked and 'Drag tab up/down  |  Drag title to undock'or 'Drag to move  |  Snap to left edge to dock')or 'Switch to menu focus to move / resize',x+pad,y+stripe+12*s,size-2*pad-20*s,9*s,'legend_hint')
  -- Mirror the main panel's lower-left grip into this lower-right corner.
  local grip={x=x+size-24*s,y=y+stripe+4*s,w=20*s,h=20*s}
  local hover=focused and pointer_x and pointer_y and pointer_x>=grip.x and pointer_x<=grip.x+grip.w and pointer_y>=grip.y and pointer_y<=grip.y+grip.h
  local pressed=gesture and gesture.kind=='resize'or false
  rect(grip.x,grip.y,grip.w,grip.h,pressed and {56,51,31}or hover and {39,42,45}or {19,21,23},'legend_resize')
  local command=commands[#commands];command.a=1;command.layer=350;command.resize=true;command.hovered=hover==true;command.pressed=pressed
  for n=0,2 do rect(x+size-(10+n*5)*s,y+stripe+(7+n*5)*s,3*s,3*s,focused and(hover or pressed)and gold or muted,'legend_resize_dot');commands[#commands].a=1;commands[#commands].layer=351 end
 end
 function self.pointer_over(input)
  local g=geometry;return owning and visible and g and(inside(input,g.tab)or g.open and inside(input,{x=g.x,y=g.y,w=g.size,h=g.size}))
 end
 function self.capturing_pointer()return gesture~=nil end
 function self.tick(input,down)
  if not input or not visible or not owning or not geometry then self.clear();return false end
  if input.x then pointer_x=input.x end;if input.y then pointer_y=input.y end
  local g=geometry;local click=input.click==true;local consumed=false
  if gesture then
   consumed=true
   if click and input.x and input.y then
    if gesture.kind=='tab'then
     local delta=input.y-gesture.py
     if math.abs(delta)>3 or gesture.moved then gesture.moved=true;local ty=clamp(gesture.tab_y+delta,0,g.h-g.tab.h);handle.set('legend_tab_y',g.h>g.tab.h and ty/(g.h-g.tab.h)*100 or 0)end
    elseif gesture.kind=='move'then
     local dx,dy=input.x-gesture.px,input.y-gesture.py
     if not g.docked or math.abs(dx)+math.abs(dy)>3 then
      if g.docked then handle.set('legend_docked',false);g.docked=false end
      g.x=clamp(gesture.x+dx,0,g.w-g.size);g.y=clamp(gesture.y+dy,0,g.h-g.size);persist(g)
     end
    else local amount=((input.x-gesture.px)-(input.y-gesture.py))/2;g.size=clamp(gesture.size+amount,math.min(g.w,g.h)*.25,math.min(g.w,g.h)*.7);g.x=clamp(gesture.x,0,g.w-g.size);g.y=clamp(gesture.y+gesture.size-g.size,0,g.h-g.size)end
    if gesture.kind=='resize'then persist(g)end
   end
   if not click then
    if gesture.kind=='tab'and not gesture.moved then handle.set('legend_open',not g.open)
    elseif gesture.kind=='move'and not g.docked and g.x<=g.snap then handle.set('legend_docked',true)end
    gesture=nil
   end
  elseif self.pointer_over(input)then
   -- The entire opaque companion owns pointer/wheel events; never click through.
   consumed=click or input.wheel~=nil and input.wheel~=0 or input.right_click==true or down and down(2)==true
   if click and not held then
    if inside(input,g.tab)then gesture={kind='tab',tab_y=g.tab.y,px=input.x,py=input.y,moved=false}
    elseif g.parent and inside(input,g.dock_button)then if g.docked then persist(g)end;handle.set('legend_docked',not g.docked);gesture=nil
    else
     local kind=input.x>=g.x+g.size-g.grip and input.y<=g.y+g.grip+g.size/41 and 'resize'or input.y>=g.y+g.size-g.header and 'move'or nil
     if kind then gesture={kind=kind,x=g.x,y=g.y,size=g.size,px=input.x,py=input.y}end
    end
   end
  end
  held=click;return consumed
 end
 return self
end
return M

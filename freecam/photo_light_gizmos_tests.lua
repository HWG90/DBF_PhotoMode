local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'photo_light_gizmos.lua')
local function near(a,b)return math.abs(a-b)<1e-7 end
local frame={world='world',scene_epoch=1,position={0,0,0},right={1,0,0},forward={0,1,0},up={0,0,1}}
local fov=math.pi/2;local w,h=1920,1080
local point=factory.target(frame,fov,w,h,.75,.25,10)
assert(near(point[1],80/9)and near(point[2],10)and near(point[3],5),'Depth must be axial, with top-left UV and correct aspect')
local x,y,z=factory.project(frame,fov,w,h,point);assert(near(x,1440)and near(y,810)and near(z,10))
local rolled={position={10,20,30},forward={0,1,0},right={0,0,1},up={-1,0,0}}
point=factory.target(rolled,fov,w,h,.25,.75,4);x,y=factory.project(rolled,fov,w,h,point);assert(near(x,480)and near(y,270),'Roll must use camera basis')
assert(not factory.project(frame,fov,w,h,{0,-1,0}));assert(not factory.project(frame,fov,w,h,{0,.05,0}))
assert(not factory.target(frame,fov,0,h,.5,.5,10));assert(not factory.target(frame,0/0,w,h,.5,.5,10))
assert(not factory.target(frame,fov,w,h,1.1,.5,10));assert(not factory.target(frame,fov,w,h,.5,.5,math.huge))
local bad={position={0,0,0},right={1,0,0},forward={1,0,0},up={0,0,1}};assert(not factory.project(bad,fov,w,h,{1,1,1}),'Invalid camera basis accepted')
local queued={};local gizmos=factory.new(function(action,value)queued[#queued+1]={action=action,value=value};return true end)
local items={{id=51,index=1,position={0,10,0},values={color='#12ABEF',enabled=true},selected=true},{id=52,index=2,position={0,-10,0},values={color='#FFFFFF'}}}
local function update(shown)gizmos.update(items,frame,fov,w,h,shown~=false)end
local shift=false;local function tick(px,py,click,block,modal)return gizmos.tick({x=px,y=py,click=click},function(k)return k==16 and shift end,block,modal)end
update();local commands={};gizmos.draw(commands);assert(#commands==4 and commands[1].ui_role=='light_marker'and commands[3].c[2]==171,'Behind-camera marker or light color wrong')
local revision=gizmos.revision;for i=1,100 do update()end
assert(gizmos.revision==revision,'Unchanged marker projection must not invalidate panel commands')
items[1].values.color='#FFFFFF';update();assert(gizmos.revision==revision+1,'Marker color change must invalidate')
assert(not tick(960,540,true)and#queued==0,'Held button at activation must not grab a light')
tick(960,540,false);assert(tick(960,540,true)and queued[1].action=='select'and queued[1].value==1)
assert(gizmos.active()and gizmos.hit(1500,300),'Captured marker must block scene focus until release')
assert(tick(1068,540,true));local move=queued[#queued];assert(move.action=='move'and move.value.id==51 and near(move.value.position[1],2)and near(move.value.position[2],10),'Drag must stay on the same camera plane')
shift=true;tick(1176,540,true);move=queued[#queued];assert(near(move.value.position[1],2.2),'Shift must reduce drag sensitivity tenfold without jumping')
shift=false;tick(1176,648,true);assert(near(queued[#queued].value.position[3],2),'Upward screen drag must move camera-up')
local count=#queued;tick(1200,648,true,function()return true end);assert(#queued==count,'Drag must not write while over a blocked UI surface')
tick(1200,648,false);assert(not gizmos.active())
update();assert(not tick(960,540,true,function()return true end)and#queued==count,'Panel overlap must not select a light');tick(960,540,false)
assert(not tick(960,540,true,nil,true)and#queued==count,'Modal editor must own all scene input');tick(960,540,false)
update(false);commands={};gizmos.draw(commands);assert(#commands==0 and not gizmos.hit(960,540),'Hidden/capture state must remove markers and hits')
update();tick(960,540,false);tick(960,540,true);frame.scene_epoch=2;update();assert(not gizmos.active(),'Scene generation change retained a stale drag')
tick(960,540,false);tick(960,540,true);items={};update();assert(not gizmos.active(),'Removed light retained drag ownership')
-- Menu hit ownership also protects an older controller that checks focus before tick.
local values={v=1,color='#204060'};local rendered;local menu=dofile(root..'photo_menu.lua').new({draw=function(c)rendered=c end,release=function()end},{focus=function()end,hud=function()end,hide=function()end,exit=function()end})
menu.bind({get=function(id)return values[id]end,set=function(id,v)values[id]=v end},{{name='Lighting',controls={{id='color',type='color',label='Color'}}}})
menu.light_gizmos=gizmos;items={{id=51,index=1,position={-10,10,5},values={color='#12ABEF',enabled=true}}}
menu.prepare_light_gizmos=function(ww,hh,focused,hidden)gizmos.update(items,frame,fov,ww,hh,not hidden)end
for _,size in ipairs({{1920,1080},{640,480}})do
 menu.draw(size[1],size[2],true,false,{focus='TAB',hide='H'})
 local marker;for _,c in ipairs(rendered)do if c.ui_role=='light_marker'then marker=c end end
 if size[1]==1920 then
  assert(marker and marker.x>=0 and marker.y>=0 and marker.x+marker.w<=size[1]and marker.y+marker.h<=size[2])
  assert(near(marker.y+marker.h/2,810)and marker.y+marker.h/2>size[2]/2,'Positive camera-up must render above center in bottom-left menu coordinates')
  assert(menu.contains_pointer(marker.x+marker.w/2,marker.y+marker.h/2),'Light marker leaked into double-click focus')
 end
 for _,c in ipairs(rendered)do if c.ui_role=='light_marker'then assert(c.x>=0 and c.y>=0 and c.x+c.w<=size[1]and c.y+c.h<=size[2])end end
end
menu.draw(1920,1080,true,true,{focus='TAB',hide='H'});assert(#rendered==0)
print('Light gizmos: axial-depth/aspect/roll projection, invalid/behind points, queued selection and plane drag, Shift precision, held edges, modal/panel ownership, capture hiding, scene and removal cancellation passed')

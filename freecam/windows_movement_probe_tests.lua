local M=dofile('freecam/windows_movement_probe.lua')
local function fixture()
 local f={unit={},world={},angle=90,sets=0,gets=0,lines={},graph=107,index=3};local time=0
 f.frame={explicit_subject=true,root_handle=f.unit,world=f.world,identity='subject'}
 local U={alive=function()return not f.dead end,world=function()return f.world end,
  resource_name=function()return f.resource or'4d1c334d294dfa97'end,num_scene_graph_items=function()return f.graph end,
  has_animation_state_machine=function()return true end,animation_has_variable=function()return not f.absent end,
  animation_find_variable=function()return f.index end,
  animation_get_variable=function(_,index)assert(index==f.index);f.gets=f.gets+1;return f.angle end,
  animation_set_variable=function(_,index,value)
   assert(index==f.index);f.sets=f.sets+1
   if f.refuse_restore and value~=0 then return false end
   f.angle=value
   if f.throw_after_write and value==0 then error('post-write error')end
  end,
  world_pose=function()return{0,1,0}end}
 f.probe=M.new({Unit=U,Application={main_world=function()return f.world end},
  Matrix4x4={forward=function(p)return p end},Vector3={x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end}},
  function(s)f.lines[#f.lines+1]=s end,function()time=time+(f.slow and .003 or .000001);return time end)
 function f.tick(now,enabled,frame)return f.probe.tick(frame or f.frame,enabled~=false,now,{0,1,0})end
 return f
end
local f=fixture();for _=1,120 do assert(f.tick(0))end;assert(f.gets==0 and f.sets==0,'Unarmed probe is idle')
assert(f.probe.event('a',true,0));assert(f.tick(.05)and f.gets==0);assert(f.tick(.1)and f.sets==1 and f.angle==0)
assert(f.tick(.16)and f.tick(.22)and f.tick(.28));assert(f.angle==90 and f.sets==2,'Restore after bounded observation')
local reads=f.gets;for _=1,120 do f.tick(1);f.probe.event('a',true,1)end;assert(f.gets==reads and f.sets==2,'One trial per key, idle after completion')
for _,key in ipairs({'d','s'})do assert(f.probe.event(key,true,2));assert(f.tick(2.1));assert(f.probe.event(key,false,2.11));assert(f.angle==90)end
assert(f.sets==6,'At most three test writes and their restorations')
f=fixture();f.probe.event('d',true,0);f.tick(.1);f.angle=-90;assert(f.tick(.16));assert(f.sets==1 and f.angle==-90,'Preserve gameplay overwrite without fighting it')
assert(table.concat(f.lines):find('native overwrite observed',1,true))
f=fixture();f.angle=0;f.probe.event('s',true,0);for i=1,20 do f.tick(i*.05)end
assert(f.sets==0 and f.gets<=12,'No qualifying movement angle: bounded reads and no guessed write')
for _,kind in ipairs({'absent','graph','index','resource','dead'})do
 f=fixture();f[kind]=kind=='graph'and 106 or kind=='index'and 4096 or kind=='resource'and'foreign'or true
 f.probe.event('a',true,0);assert(f.tick(.1));assert(f.sets==0 and f.gets==0,'Validate subject and named variable before indexed access: '..kind)
end
f=fixture();f.throw_after_write=true;f.probe.event('s',true,0);assert(f.tick(.1));assert(f.sets==2 and f.angle==90,'Restore setter that throws after mutation')
f=fixture();f.probe.event('a',true,0);f.tick(.1);f.refuse_restore=true
assert(not f.probe.release('test'));assert(f.angle==0);f.refuse_restore=false;assert(f.probe.release('retry')and f.angle==90,'Failed restoration retains ownership for cleanup retry')
f=fixture();f.probe.event('a',true,0);f.tick(.1);f.dead=true;assert(f.probe.release('retired'));assert(f.sets==1,'Never restore a retired unit')
f=fixture();f.probe.event('a',true,0);f.tick(.1);assert(f.tick(.11,false)and f.angle==90,'ADS, freeze, focus loss and menu exit restore immediately')
f=fixture();f.probe.event('a',true,0);f.tick(.1);assert(f.tick(.16,true,{explicit_subject=true,root_handle={},world=f.world,identity='different'})and f.angle==90,'Selection change restores old still-valid owner')
f=fixture();f.slow=true;f.probe.event('a',true,0);assert(f.tick(.1)and f.angle==90 and f.sets==2,'Budget overrun stops and restores the test')
-- Only the exact fixed marker arms the experiment; claim failure stays inert.
do
 local open,rename=io.open,os.rename;local token='bad';local claims=0
 io.open=function(path,mode)assert(path=='folder/wj-movement-probe.request'and mode=='rb');return{read=function()return token end,close=function()end}end
 os.rename=function(a,b)claims=claims+1;assert(b==a..'.claimed.7');return true end
 assert(not M.consume('folder',7)and claims==0)
 token='move-angle-once-v1\n';assert(M.consume('folder',7)and claims==1)
 os.rename=function()return nil end;assert(not M.consume('folder',7))
 io.open,os.rename=open,rename
end
print('Windows movement probe: opt-in, bounded one-write trials, foreign-write preservation, lifecycle restoration, retirement and cleanup retry passed')

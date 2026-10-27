assert(_VERSION=='Lua 5.1')
local Probe=dofile('freecam/windows_freeze_pose_probe.lua')
local function copy(t)local c={};for k,v in pairs(t)do c[k]=v end;return c end
local function fixture(options)
 local f={epoch=1,reads=0,writes=0,modes=0,updates=0,alive=true,count=107,mode='position_and_rotation',poses={},logs={}}
 f.unit=newproxy();f.world=newproxy();f.session=newproxy();f.current_world=f.world;f.current_session=f.session
 for i=1,107 do f.poses[i]={1,0,0,0,1,0,0,0,1,i,0,0}end
 local temps={}
 local function temp(value)local u=newproxy();temps[u]={epoch=f.epoch,value=value};return u end
 local function value(u)local t=assert(temps[u]);assert(t.epoch==f.epoch,'Scratch temporary survived callback');return t.value end
 local function read(u)assert(u==f.unit);f.reads=f.reads+1 end
 local U={alive=function(u)read(u);return f.alive end,world=function(u)read(u);return f.world end,
  num_scene_graph_items=function(u)read(u);return f.count end,
  resource_name=function(u)read(u);return temp(f.resource or'4d1c334d294dfa97')end,
  has_node=function(u,n)read(u);local i=tonumber(n:match('^cape(%d)$'));return i~=nil and i>=1 and i<=8 end,
  node=function(u,n)read(u);return 34+assert(tonumber(n:match('^cape(%d)$')))+(f.bad_cape and 1 or 0)end,
  animation_bone_mode=function(u)read(u);return f.mode end,
  set_animation_bone_mode=function(u,m)read(u);f.modes=f.modes+1
   if m=='position_and_rotation'and f.restore_fail then error('Restore refused')end
   f.mode=m;if m=='ignore'and f.mode_throw then error('Mode changed then threw')end
  end,
  local_pose=function(u,i)read(u);return temp(copy(f.poses[i]))end,
  set_local_pose=function(u,i,p)read(u);f.writes=f.writes+1;f.last_write=i
   f.by_node=f.by_node or{};f.by_node[i]=(f.by_node[i]or 0)+1
   if not f.ignore_write then f.poses[i]=copy(value(p))end
   if f.node_throw then error('Node changed then threw')end
  end}
 local sr={Unit=U,World={update_unit=function(w,u)assert(w==f.world and u==f.unit);f.updates=f.updates+1 end},
  Application={main_world=function()return f.current_world end},Network={game_session=function()return f.current_session end},
  IdString64={from_hex=temp,equal=function(a,b)return value(a)==value(b)end},
  Matrix4x4={to_elements=function(p)return unpack(value(p))end,from_elements=function(...)return temp({...})end}}
 f.subject={tracking_frame=function()return{explicit_subject=true,identity=f.other_selection and'other'or'body-1',root_handle=f.unit,world=f.world}end}
 f.probe=Probe.new(sr,function(s)f.logs[#f.logs+1]=s end,function()f.clock=(f.clock or 0)+(f.slow and .009 or 0);return f.clock end,options)
 function f.start(t)return f.probe.start(f.subject,t or 0)end
 function f.render(t,on)f.epoch=f.epoch+1;return f.probe.render(on~=false,t or .01)end
 return f
end
do
 local f=fixture();for i=1,100 do assert(f.render(i)and f.probe.tick(false,i))end;assert(f.reads==0 and f.modes==0)
 assert(f.start());assert(f.modes==0 and f.writes==0,'Capture never changes mode or transforms')
 assert(f.render());assert(f.mode=='ignore'and f.writes==0 and f.updates==0,'Unchanged skeleton has no pose writes or refresh')
 -- Both root and terminal skeleton nodes must be held; not just authored 8..92.
 f.poses[1][1]=.5;f.poses[107][10]=999
 assert(f.render(.1)and f.writes==2 and f.updates==1 and f.poses[1][1]==1 and f.poses[107][10]==107)
 local writes=f.writes;for i=1,20 do assert(f.render(.1+i*.01))end;assert(f.writes==writes and f.updates==1,'Unchanged frames do not reapply poses')
 assert(f.probe.tick(true,6)and f.mode=='position_and_rotation'and not f.probe.active()and f.modes==2)
 local reads=f.reads;for i=1,100 do assert(f.render(7+i)and f.probe.release('idle'))end;assert(f.reads==reads)
 assert(f.start(200));assert(f.render(200.1));assert(f.probe.release('end'));assert(not f.start(300),'At most two explicit trials')
end
do
 local f=fixture();assert(f.start());assert(f.render(.01,false));assert(f.modes==0 and f.writes==0,'Lost exact zero before first render prevents acquisition')
 local g=fixture();assert(g.start());assert(g.render(7));assert(g.modes==0,'Expired capture never acquires a mode')
end
for _,issue in ipairs({'dead','world','session','count','resource','selection'})do
 local f=fixture();assert(f.start());assert(f.render())
 if issue=='dead'then f.alive=false elseif issue=='world'then f.current_world=newproxy()elseif issue=='session'then f.current_session=newproxy()
 elseif issue=='count'then f.count=108 elseif issue=='resource'then f.resource='other'else f.other_selection=true end
 local writes=f.writes;assert(not f.render(.1));assert(f.writes==writes,'Retired or replaced targets never receive pose writes')
 if issue=='count'or issue=='resource'then assert(f.probe.active(),'Unknown identity retains cleanup obligation without writes')end
end
do
 local f=fixture();assert(f.start());f.mode_throw=true;assert(not f.render()and f.mode=='position_and_rotation'and f.modes==2,'Partial mode write restores')
 local g=fixture();assert(g.start());g.poses[1][10]=99;g.node_throw=true;assert(not g.render()and g.mode=='position_and_rotation'and g.writes==1,'Partial pose write releases mode without replaying old simulation')
 local h=fixture();assert(h.start());h.poses[1][10]=99;h.ignore_write=true;assert(not h.render()and h.mode=='position_and_rotation','Readback mismatch stops the experiment')
end
do
 local f=fixture();assert(f.start());assert(f.render());f.mode='transform';assert(not f.render(.1)and f.mode=='transform'and f.modes==1,'Foreign bone mode is preserved')
 local g=fixture();g.mode='ignore';assert(not g.start()and g.modes==0)
end
do
 local f=fixture();assert(f.start());assert(f.render());f.restore_fail=true
 assert(not f.probe.tick(false,.1));local reads,modes=f.reads,f.modes
 for i=1,100 do assert(not f.render(i)and not f.probe.release('automatic'))end
 assert(f.reads==reads and f.modes==modes,'Failed cleanup stays idle until explicit retry')
 f.restore_fail=false;assert(f.probe.release('explicit',true)and f.mode=='position_and_rotation')
end
do
 local f=fixture();f.slow=true;assert(not f.start()and f.modes==0,'Slow capture stops before mode acquisition')
 local g=fixture();assert(g.start());g.slow=true;assert(not g.render()and g.mode=='position_and_rotation','Slow replay stops and releases mode')
end
do
 local f=fixture({continuous=true})
 assert(f.probe.prepare(nil,0)and not f.probe.active(),'Missing selection never invents a held body')
 for cycle=1,4 do
  assert(f.probe.prepare(f.subject,cycle*100)and f.modes==0,'Continuous hold never overrides engine bone-transfer mode')
  local original=f.poses[1][1];f.poses[1][1]=original+.25
  assert(f.render(cycle*100+.01)and f.poses[1][1]==original)
  assert(f.render(cycle*100+60)and f.probe.active(),'Integrated hold does not expire after six seconds')
  assert(f.mode=='position_and_rotation'and f.modes==0,'Normal native bone transfer remains enabled')
  assert(f.probe.release('Resume')and not f.probe.active())
 end
 assert(f.probe.prepare(f.subject,500));f.mode='transform';assert(not f.render(501)and f.modes==0,'Another bone-transfer owner ends continuous replay without overriding it')
end
do
 local f=fixture({continuous=true,exclude_cape=true})
 assert(f.probe.prepare(f.subject,0))
 for i=1,107 do f.poses[i][10]=i+500 end
 assert(f.render(.1)and f.writes==99 and f.modes==0)
 for i=1,107 do
  if i>=35 and i<=42 then assert(not f.by_node[i]and f.poses[i][10]==i+500,'Cape bones are never rewritten')
  else assert(f.by_node[i]==1 and f.poses[i][10]==i,'All remaining body nodes are held')end
 end
 for step=1,100 do
  for i=35,42 do f.poses[i][10]=i+step end
  assert(f.render(.1+step*.01))
 end
 assert(f.writes==99 and f.updates==1,'Cape changes alone trigger no writes or scene refresh')
 assert(f.probe.release('Resume')and f.modes==0 and f.writes==99,'Cleanup leaves cape and native bone mode alone')
 local bad=fixture({continuous=true,exclude_cape=true});bad.bad_cape=true
 assert(not bad.probe.prepare(bad.subject,0)and bad.writes==0,'A changed cape rig cannot silently write cape nodes')
end
print('Freeze pose hold: coherent capture, copied scalars, body-only cape exclusion, idle write silence, exact-zero gate, trial/continuous lifetime and cleanup passed')

-- Cape placement follows body scene refresh and keeps cleanup obligations on failure.
do
 local f;local applies,releases=0,0;local record={meshes={1,2,3},writes=0}
 local solver={capture=function()return record end,
  apply=function(r)assert(r==record and f.updates>0,'Cape applied before body refresh');applies=applies+1 end,
  release=function(r)assert(r==record);releases=releases+1;if releases==1 then error('Transient cape cleanup')end;return true end}
 f=fixture({continuous=true,exclude_cape=true,cape=solver})
 assert(f.probe.prepare(f.subject,0));f.poses[1][10]=999
 assert(f.render(.1)and applies==1)
 assert(not f.probe.release('Resume')and f.probe.active(),'Cape cleanup failure retains lease')
 assert(f.probe.release('Retry',true)and not f.probe.active()and releases==2)
end

-- Match the original ragdoll transfer lease while retaining bounded continuous
-- lifetime and excluding all cape bones from replay.
do
 local f=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(f.probe.prepare(f.subject,0)and f.mode=='position_and_rotation'and f.modes==0)
 for i=1,107 do f.poses[i][10]=i+100 end
 assert(f.render(.01)and f.mode=='ignore'and f.modes==1 and f.writes==99)
 for i=35,42 do assert(not f.by_node[i]and f.poses[i][10]==i+100,'Cape is excluded')end
 local writes=f.writes;for i=1,100 do assert(f.render(1+i))end
 assert(f.modes==1 and f.writes==writes,'Held transfer ownership never repeats the mode setter or unchanged poses')
 assert(f.probe.release('Resume')and f.mode=='position_and_rotation'and f.modes==2 and f.writes==writes)
 assert(f.probe.prepare(f.subject,200));f.mode_throw=true
 assert(not f.render(201)and f.mode=='position_and_rotation','Mutate-then-throw releases the transfer lease')
 local g=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(g.probe.prepare(g.subject,0)and g.render(.1));g.mode='transform'
 assert(not g.render(.2)and g.mode=='transform'and g.modes==1,'Foreign transfer owner is preserved')
 local h=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(h.probe.prepare(h.subject,0)and h.render(.1));h.restore_fail=true
 assert(not h.probe.release('Resume'));local reads=h.reads
 for i=1,100 do assert(not h.render(i))end
 assert(h.reads==reads,'Failed transfer cleanup remains idle until explicit retry')
 h.restore_fail=false;assert(h.probe.release('Explicit retry',true)and h.mode=='position_and_rotation')
end
print('Continuous transfer lease: single ignore acquisition, body-only replay, idle/foreign ownership, partial failure and resume restoration passed')

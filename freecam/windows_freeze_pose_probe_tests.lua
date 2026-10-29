assert(_VERSION=='Lua 5.1')
local Probe=dofile('freecam/windows_freeze_pose_probe.lua')
local function copy(t)local c={};for k,v in pairs(t)do c[k]=v end;return c end
-- The rig's carry sockets (steam_subject_poses indices).
local carry={attach_samplepouch=23,attach_intelpad=24,target_designator=25,sling=28,support_mg=31,support=32}
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
  has_node=function(u,n)read(u);if carry[n]then return true end;local i=tonumber(n:match('^cape(%d)$'));return i~=nil and i>=1 and i<=8 end,
  node=function(u,n)read(u);if carry[n]then return carry[n]+(f.bad_carry and 1 or 0)end;return 34+assert(tonumber(n:match('^cape(%d)$')))+(f.bad_cape and 1 or 0)end,
  animation_bone_mode=function(u)read(u);return f.mode end,
  -- The body's animation state machine (nil: none); the game only fights a hold while it runs.
  has_animation_state_machine=function(u)read(u);return f.machine~=nil end,
  -- Re-enabling restarts the animation from scratch (the arms came back wrong, live); the state
  -- getter/setter pair carries where it was.
  disable_animation_state_machine=function(u)read(u);f.machine_calls=(f.machine_calls or 0)+1;f.machine=false end,
  enable_animation_state_machine=function(u)read(u);f.machine_calls=(f.machine_calls or 0)+1;f.machine=true;f.anim={0,0,0}end,
  animation_get_state=function(u)read(u);return unpack(f.anim or{})end,
  animation_set_state=function(u,...)read(u);if f.pin_refuse then error('State refused')end;f.anim={...};f.restores=(f.restores or 0)+1 end,
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

-- The game re-places the carry sockets every frame; gear linked to them shows the game's value.
-- The hold leaves them alone so the body's sockets and the gear stay equal for Hide carried weapons.
do
 local f=fixture({continuous=true,exclude_cape=true,exclude_carry=true})
 assert(f.probe.prepare(f.subject,0))
 for i=1,107 do f.poses[i][10]=i+500 end
 assert(f.render(.1)and f.writes==93,'99 body nodes less six carry sockets: '..f.writes)
 for _,i in pairs(carry)do assert(not f.by_node[i]and f.poses[i][10]==i+500,'Carry sockets are never rewritten')end
 for step=1,50 do for _,i in pairs(carry)do f.poses[i][10]=i+step end;assert(f.render(.1+step*.01))end
 assert(f.writes==93 and f.updates==1,'Socket changes alone trigger no writes or scene refresh')
 assert(f.logs[1]:find('nodes=93; cape_bones=excluded; carry_sockets=excluded',1,true),f.logs[1])
 assert(f.probe.release('Resume'))
 local bad=fixture({continuous=true,exclude_cape=true,exclude_carry=true});bad.bad_carry=true
 assert(not bad.probe.prepare(bad.subject,0)and bad.writes==0,'A moved carry socket cannot silently release another node')
end
print('Freeze pose hold: carry sockets left to the game, checked against the rig, passed')

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
 -- Frozen mid-stride (live, 2026-10-29): the game's own animation puts the body's original
 -- mode back. Freeze takes it back and rewrites the held pose until Resume; any other mode
 -- is still a foreign owner (preserved above).
 local k=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(k.probe.prepare(k.subject,0));for i=1,107 do k.poses[i][10]=i+100 end
 assert(k.render(.01)and k.mode=='ignore'and k.modes==1);local held=k.poses[20][10]
 k.mode='position_and_rotation';k.poses[20][10]=held+7
 assert(k.render(.02),'The game resetting the original mode does not stop Freeze')
 assert(k.mode=='ignore'and k.modes==2 and k.probe.active(),'Freeze takes the mode back')
 assert(k.poses[20][10]==held,'The held pose is written back')
 for i=1,5 do k.mode='position_and_rotation';assert(k.render(.02+i/100))end
 assert(k.probe.release('Resume')and k.mode=='position_and_rotation','Resume still restores the original mode')

 -- Taken back only at render, the body showed one animated frame each time (flicker). The
 -- game resets the mode during its update, so the update takes it back too, before drawing.
 local u=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(u.probe.prepare(u.subject,0)and u.render(.01)and u.mode=='ignore')
 u.mode='position_and_rotation';assert(u.probe.tick(true,.015)and u.mode=='ignore','Update-time takeback')
 assert(u.render(.02)and u.mode=='ignore')
 u.mode='transform';assert(u.probe.tick(true,.025)and u.mode=='transform','A foreign owner is left alone at update')
 local v=fixture({continuous=true,exclude_cape=true,claim_transfer=true})
 assert(v.probe.prepare(v.subject,0)and v.render(.01));v.mode='position_and_rotation';assert(v.probe.tick(true,.015))
 assert(v.probe.release('Resume')and v.mode=='position_and_rotation','Resume restores the original mode after an update takeback')

 -- Taking the mode back every frame flickered and left the arms in a weird pose (live). After
 -- the first takeback, at update or render, the body's animation state machine is paused
 -- until release, which re-enables it before restoring the mode.
 local m=fixture({continuous=true,exclude_cape=true,claim_transfer=true,pause_animation=true});m.machine=true;m.anim={3,0.25,7}
 local function game_frame()if m.machine then m.mode='position_and_rotation'end end
 assert(m.probe.prepare(m.subject,0)and m.render(.01)and m.mode=='ignore')
 game_frame();assert(m.probe.tick(true,.015)and m.machine==false and m.mode=='ignore','The first update takeback pauses the animation')
 local modes=m.modes;for i=1,20 do game_frame();assert(m.probe.tick(true,.02+i/100)and m.render(.02+i/100))end
 assert(m.modes==modes and m.machine_calls==1,'A paused animation no longer fights the hold')
 -- With the animation paused, the game still places the body's root (bone 1) every frame
 -- where the moving body got to; writing the captured root back jittered (flicker, live).
 -- The root is the game's; every other bone stays held relative to it.
 local function root_count()return m.by_node and m.by_node[1]or 0 end
 local root_writes,held20=root_count(),m.poses[20][10]
 for i=1,10 do m.poses[1][10]=m.poses[1][10]+.01;local game_root=m.poses[1][10];m.poses[20][10]=held20+3
  assert(m.probe.tick(true,.3+i/100)and m.render(.3+i/100))
  assert(m.poses[1][10]==game_root,'The game keeps the root');assert(m.poses[20][10]==held20,'The body stays held')
 end
 assert(root_count()==root_writes,'No root writes while the animation is paused')
 assert(m.probe.release('Resume')and m.machine==true and m.mode=='position_and_rotation','Resume restores the animation, then the mode')
 assert(m.restores==1 and m.anim[1]==3 and m.anim[2]==0.25 and m.anim[3]==7,'Resume restores the animation state from before the pause')
 local r=fixture({continuous=true,exclude_cape=true,claim_transfer=true,pause_animation=true});r.machine=true
 assert(r.probe.prepare(r.subject,0)and r.render(.01));r.mode='position_and_rotation'
 assert(r.render(.02)and r.machine==false and r.mode=='ignore','A render takeback pauses it too')
 assert(r.probe.release('Photo Mode closed')and r.machine==true,'Close restores the animation')
 -- By default (the shipped Freeze) a fought body is only taken back: pausing its animation
 -- broke the arms after Resume (live), even with its state restored.
 local d=fixture({continuous=true,exclude_cape=true,claim_transfer=true});d.machine=true
 assert(d.probe.prepare(d.subject,0)and d.render(.01));d.mode='position_and_rotation'
 assert(d.probe.tick(true,.015)and d.mode=='ignore'and d.machine==true and d.machine_calls==nil,'Taken back, never paused by default')
 assert(d.probe.release('Resume')and d.mode=='position_and_rotation')
 -- Pinning (dev experiment): the animation keeps running but its state is put back to the
 -- frozen instant every update, so whatever the game draws is the held moment; the arm logic
 -- is never switched off, and the root is left to the game.
 local g=fixture({continuous=true,exclude_cape=true,claim_transfer=true,pin_animation=true});g.machine=true;g.anim={3,0.25,7}
 local function g_frame()g.anim={g.anim[1],g.anim[2]+.1,g.anim[3]};g.mode='position_and_rotation';g.poses[1][10]=g.poses[1][10]+.01 end
 assert(g.probe.prepare(g.subject,0)and g.render(.01))
 for i=1,10 do g_frame();local game_root=g.poses[1][10]
  assert(g.probe.tick(true,.01+i/100)and g.render(.01+i/100))
  assert(g.anim[1]==3 and g.anim[2]==.25 and g.anim[3]==7,'The animation is pinned to the frozen instant')
  assert(g.poses[1][10]==game_root,'The root is left to the game')
 end
 assert(g.machine==true and g.machine_calls==nil,'Pinning never switches the animation off')
 assert(g.probe.release('Resume')and g.mode=='position_and_rotation'and g.machine==true)
 -- A refused pin stops pinning for that freeze; the hold carries on.
 local e=fixture({continuous=true,exclude_cape=true,claim_transfer=true,pin_animation=true});e.machine=true;e.anim={1}
 assert(e.probe.prepare(e.subject,0)and e.render(.01));e.pin_refuse=true
 assert(e.probe.tick(true,.02)and e.render(.02)and e.probe.active())
 local refused=0;for _,line in ipairs(e.logs)do if line:find('animation pin stopped',1,true)then refused=refused+1 end end
 assert(refused==1,'A failed pin is reported once')
 assert(e.probe.release('Resume'))
 -- Standing freezes are never fought, so their animation is never paused.
 local n=fixture({continuous=true,exclude_cape=true,claim_transfer=true});n.machine=true
 assert(n.probe.prepare(n.subject,0));for i=1,10 do assert(n.probe.tick(true,i/100)and n.render(i/100))end
 assert(n.machine==true and n.machine_calls==nil,'No takeback, no pause')
 assert(n.probe.release('Resume')and n.machine_calls==nil)
end
print('Continuous transfer lease: single ignore acquisition, body-only replay, idle/foreign ownership, partial failure and resume restoration passed')

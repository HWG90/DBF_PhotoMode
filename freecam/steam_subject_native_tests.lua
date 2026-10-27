-- Actual Lua5.1; synthetic matrix storage doubles, never a game/ABI claim.
assert(_VERSION=='Lua 5.1'and not rawget(_G,'jit'))
local Native=dofile('freecam/steam_subject_native.lua')
local Subject=dofile('freecam/steam_subject.lua')
local function clone(value)if type(value)~='table'then return value end;local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out end
local function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function pack(...)return{n=select('#',...),...}end
local function float(value)
 if value==0 then return value end;local negative=value<0;if negative then value=-value end
 local m,e=math.frexp(value);local out=math.ldexp(math.floor(m*16777216+.5),e-24);return negative and-out or out
end
local assertions=0
local function check(ok,why)assertions=assertions+1;assert(ok,why)end
local function fixture()
 local f={frame=1,calls=0,writes=0,updates=0,unit_reads=0,math_calls=0,log={},failure={},alive=true,
  mode='position_and_rotation',count=107,resource='4d1c334d294dfa97',userdata={},q_drift=2^-24}
 local function opaque(kind,value,temporary)local ud=newproxy(true);f.userdata[ud]={kind=kind,value=value,frame=temporary and f.frame or nil};return ud end
 local function data(value,kind)
  local r=f.userdata[value];check(r and r.kind==kind,'Wrong native userdata kind')
  check(not r.frame or r.frame==f.frame,'Frame temporary escaped its callback');return r.value
 end
 local function call(name,read)f.calls=f.calls+1;f.log[#f.log+1]=name;if read then f.unit_reads=f.unit_reads+1 end;if f.on_call then f.on_call(name)end end
 local function unit(value)check(value==f.unit or f.extra and f.extra[value],'Wrong selected Unit')end
 local function matrix(values)local out={};for i=1,12 do out[i]=float(values[i])end;return opaque('matrix',out,true)end
 f.world,f.unit,f.session=opaque('world'),opaque('unit'),opaque('session');f.current_world,f.current_session=f.world,f.session
 f.units={f.unit};f.nodes={};f.rig={resource=f.resource,node_count=107,nodes={}}
 -- Synthetic twelve-scalar matrix payload: raw authority and a deliberately
 -- non-idempotent quaternion decomposition. Actual axis ABI is qualified apart.
 for i=1,107 do f.nodes[i]={pose={0,0,0,1,1,1,1,0,0,float(i/10),float(.2),float(.3)}};f.rig.nodes[i]={parent=i-1,name='bone_'..i}end
 f.original=clone(f.nodes)
 local A,W,U,I,V,Q,N,B={},{},{},{},{},{},{},{}
 A.main_world=function()call('main_world');return f.current_world end
 N.game_session=function()call('game_session');return f.current_session end
 I.from_hex=function(hex)call('from_hex');check(hex==f.resource);return opaque('id',hex,true)end
 I.equal=function(a,b)call('id_equal');return data(a,'id')==data(b,'id')end
 W.units_by_resource=function(world,id)call('units_by_resource');check(world==f.world and data(id,'id')==f.resource);return f.units end
 W.update_unit=function(world,value)
  call('update_unit');f.updates=f.updates+1;check(world==f.world);unit(value)
  if f.on_update then f.on_update(f)end;if f.update_throw then error(f.update_throw,0)end;if f.update_refuse then return false,'Refresh refused',nil end
 end
 U.alive=function(value)call('alive',true);unit(value);return f.alive and not(f.dead and f.dead[value])end
 U.world=function(value)call('unit_world',true);unit(value);return f.unit_world or f.world end
 U.resource_name=function(value)call('resource_name',true);unit(value);return opaque('id',f.actual_resource or f.resource,true)end
 U.num_scene_graph_items=function(value)call('node_count',true);unit(value);return f.count end
 U.animation_bone_mode=function(value)call('mode',true);unit(value);return f.mode end
 U.scene_graph_parent=function(value,index)
  call('parent',true);unit(value);check(index>=1 and index<=107 and index%1==0)
  if f.bad_parent==index then return index end;if index==1 then return end;return index-1
 end
 U.has_node=function(value,name)call('has_node',true);unit(value);return name~=f.missing_name end
 U.node=function(value,name)call('node',true);unit(value);return f.bad_name==name and 104 or tonumber(name:match('^bone_(%d+)$'))end
 U.local_pose=function(value,index)call('pose',true);unit(value);if f.nil_pose then return nil end;return matrix(f.nodes[index].pose)end
 U.set_local_pose=function(value,index,temporary)
  unit(value);local target=data(temporary,'matrix');f.writes=f.writes+1;call('set_pose');local fail=f.failure.pose
  if not fail or fail.effect=='all'then f.nodes[index].pose=clone(target)
  elseif fail.effect=='partial'then f.nodes[index].pose[10]=target[10]end
  if fail and fail.mutate then fail.mutate(f,index,target)end
  if fail and fail.throw then error(fail.object or'Pose setter threw',0)end
  if fail and fail.refuse then return false,fail.object or'Pose setter refused',nil end
  if f.return_temporary then return nil,opaque('matrix',clone(target),true),nil end
 end
 U.set_animation_bone_mode=function(value,mode)
  unit(value);f.writes=f.writes+1;call('set_mode');local fail=f.failure.mode
  if not fail or fail.effect=='all'then f.mode=mode end
  if fail and fail.mutate then fail.mutate(f,mode)end
  if fail and fail.throw then error(fail.object or'Mode setter threw',0)end
  if fail and fail.refuse then return false,fail.object or'Mode setter refused',nil end
 end
 setmetatable(V,{__call=function(_,x,y,z)call('vector');f.math_calls=f.math_calls+1;return opaque('vector',{float(x),float(y),float(z)},true)end})
 U.world_position=function(value,index)call('world_position',true);unit(value);check(index==1);return V(f.positions and f.positions[value]or 0,0,0)end
 for i,name in ipairs({'x','y','z'})do local index=i;V[name]=function(value)call('vector_'..name);return data(value,'vector')[index]end end
 Q.from_elements=function(x,y,z,w)call('quaternion');f.math_calls=f.math_calls+1;return opaque('quaternion',{float(x),float(y),float(z),float(w)},true)end
 Q.to_elements=function(value)call('quaternion_elements');return unpack(data(value,'quaternion'),1,4)end
 B.from_elements=function(...)
  call('matrix_from_elements');check(select('#',...)==12,'Strict documented twelve-scalar constructor')
  local values={...};if f.constructor_drift then values[1]=values[1]+2^-20 end;return matrix(values)
 end
 B.to_elements=function(value)call('matrix_to_elements');local values=data(value,'matrix');return unpack(values,1,f.matrix_count or 12)end
 B.from_quaternion_position=function(q,p)
  call('matrix_from_qp');local rotation,position=data(q,'quaternion'),data(p,'vector')
  return matrix({rotation[1],rotation[2],rotation[3],rotation[4],1,1,1,0,0,position[1],position[2],position[3]})
 end
 B.set_scale=function(value,s)
  call('matrix_set_scale');local values,scale=data(value,'matrix'),data(s,'vector');values[5],values[6],values[7]=scale[1],scale[2],scale[3]
  if f.scale_returns_value then return true end
 end
 B.translation=function(value)call('matrix_translation');local values=data(value,'matrix');return opaque('vector',{values[10],values[11],values[12]},true)end
 B.rotation=function(value)
  call('matrix_rotation');local values=data(value,'matrix');return opaque('quaternion',{float(values[1]+f.q_drift),values[2],values[3],values[4]},true)
 end
 B.scale=function(value)call('matrix_scale');local values=data(value,'matrix');return opaque('vector',{values[5],values[6],values[7]},true)end
 f.sr={Application=A,World=W,Unit=U,IdString64=I,Vector3=V,Quaternion=Q,Network=N,Matrix4x4=B}
 f.policy={qualified=true,contract='unit-pose-sync-v1',qualification='offline-fixture-only',session=f.session}
 function f.step()f.frame=f.frame+1 end
 function f.arm()f.adapter=assert(Native.new(f.sr,f.policy));return f.adapter end
 function f.discover()
  f:step();local choices,why=f.adapter.discover(f.resource,4,f.rig);check(choices,why);f.target=choices[1];check(#choices==1 and not f.target.unit and not f.target.world);return f.target
 end
 function f.snapshot()f:step();local value,why=f.adapter.snapshot(f.target,f.rig);check(value,why);return value end
 function f.ready()f:arm();f:discover();return f:snapshot()end
 function f:canonical(value)f:step();local result,why=f.adapter.canonical_node(f.target,f.rig,value);check(result,why);return result end
 function f:desired()return f:canonical({p={.123456789,.456789123,.9},q={0,.6,0,.8},s={1.0001,.9999,1}})end
 return f
end
-- NATIVE_FIXTURE_END: isolated source-only fixtures may reuse the prefix.

do
 local f=fixture();f.extra={};f.positions={[f.unit]=99};f.dead={};f.units={[7]=f.unit}
 local handles={}
 for i=1,6 do local u=newproxy();handles[i]=u;f.extra[u]=true;f.positions[u]=i;f.units[10+i*3]=u end
 f.dead[handles[1]]=true;f.units[60]=handles[2] -- Retired and duplicate entries do not consume slots.
 f:arm();local found,why=f.adapter.discover(f.resource,4,f.rig,{0,0,0});check(found,why);check(#found==4)
 for i=1,4 do check(f.adapter.locate(handles[i+1])==found[i],'Nearest four valid bodies from sparse mission inventory')end
 check(not f.adapter.locate(f.unit)and not f.adapter.locate(handles[6])and f.writes==0)
 local calls=f.calls;for i=1,10 do f.adapter.status()end;check(f.calls==calls,'Unchanged discovery is idle')
 f:step();check(f.adapter.valid(found[1],f.rig)==true,'Selected identities survive scratch-frame rollover')
 f.units={};for i=1,129 do f.units[i]=f.unit end
 local result,reason=f.adapter.discover(f.resource,4,f.rig,{0,0,0});check(result==nil and reason:find('128%-unit')and f.writes==0,'Oversized inventory fails within bounded work')
 check(f.adapter.locate(handles[2])==found[1],'Failed discovery never publishes partial records')
end

-- A click is an exact unit choice, not a request to pick four nearer roots.
do
 local f=fixture();f.extra={};f.positions={[f.unit]=99};f.units={[7]=f.unit};local handles={}
 for i=1,6 do local u=newproxy();handles[i]=u;f.extra[u]=true;f.positions[u]=i;f.units[10+i*3]=u end
 f:arm();local found=assert(f.adapter.discover(f.resource,4,f.rig,{0,0,0},f.unit))
 check(#found==4 and f.adapter.locate(f.unit)==found[1],'An explicitly clicked body must survive the four-subject root-distance cutoff')
 for i=1,3 do check(f.adapter.locate(handles[i])==found[i+1],'The other slots retain nearest-root ordering')end
 check(not f.adapter.locate(handles[4])and f.writes==0,'Priority neither expands the menu nor writes a transform')
 local stranger=newproxy();found=assert(f.adapter.discover(f.resource,4,f.rig,{0,0,0},stranger))
 check(not f.adapter.locate(stranger)and not f.adapter.locate(f.unit),'An unlisted preferred handle must not manufacture a candidate')
 for i=1,4 do check(f.adapter.locate(handles[i])==found[i],'Unknown click retains the qualified inventory')end
 local rejected=f.adapter.discover(f.resource,4,f.rig,{0,0,0},false)
 check(rejected==nil and f.writes==0,'Malformed explicit unit refuses before publishing new identities')
end

-- New contract is explicit. Old PQS receipts and incomplete bindings cannot admit.
do
 local f=fixture();check(Native.new(f.sr)==nil and f.calls==0)
 for _,policy in ipairs({{}, {qualified=true}, {qualified=true,contract='unit-pqs-sync-v1',qualification='old',session=f.session},
  {qualified=true,contract='unit-pose-sync-v1',qualification='',session=f.session}})do check(Native.new(f.sr,policy)==nil and f.calls==0)end
 check(Native.preview(f.sr,{contract='unit-pqs-preview-v1',session=f.session,trial_id='old',authorize=function()return true end})==nil)
 local a=f:arm();check(a.status().pose_scalars==12 and a.status().contract=='unit-pose-sync-v1'and f.calls==0)
 local count=f.calls;for _=1,100 do a.status()end;check(f.calls==count,'Idle status performs no engine calls')
end
for _,name in ipairs({'from_elements','to_elements','from_quaternion_position','set_scale','translation','rotation','scale'})do
 local f=fixture();f.sr.Matrix4x4[name]=nil;check(Native.new(f.sr,f.policy)==nil and f.calls==0,'Required matrix bindings fail closed')
end

-- Raw matrices survive quaternion decomposition drift and callback lifetime.
do
 local f=fixture();local original=f:ready().nodes[8];local canonical=f:canonical(original)
 check(same(canonical.pose,original.pose),'Existing raw pose must never rebuild its getter quaternion')
 local authored=clone(original);authored.pose=nil;local rebuilt=f:canonical(authored)
 check(not same(rebuilt.pose,original.pose),'Fixture deliberately models non-idempotent getter quaternion reconstruction')
 original.pose[1]=99;check(f.nodes[8].pose[1]~=99,'Snapshot owns its twelve numeric scalars')
 local reads=f.unit_reads;local desired=f:desired();check(f.unit_reads==reads,'Canonical target construction scans no Unit')
 check(desired.pose[10]==float(.123456789)and #desired.pose==12)
 f:step();local before=f:snapshot().nodes[8];check(f.adapter.set_mode(f.target,f.rig,f.mode,'ignore')==true)
 f:step();check(f.adapter.set_node(f.target,f.rig,8,before,desired,'ignore')==true)
 check(f.writes==2 and same(f.nodes[8].pose,desired.pose),'One whole-node pose setter follows owned mode')
 f:step();check(f.adapter.commit(f.target,f.rig)==true)
 f.q_drift=2^-23;local actual=f:snapshot().nodes[8]
 check(not same(actual.q,desired.q)and same(actual.pose,desired.pose),'Raw ownership tolerates a different finite validated quaternion decomposition')
 f:step();check(f.adapter.set_node(f.target,f.rig,8,desired,before,'ignore')==true)
 f:step();check(f.adapter.set_mode(f.target,f.rig,'ignore','position_and_rotation')==true and f.adapter.commit(f.target,f.rig)==true)
 check(same(f.nodes,f.original)and f.adapter.status().pending==0,'Restore original twelve scalars directly, without Q reconstruction')
 local idle=f.calls;check(f.adapter.commit(f.target,f.rig)==true and f.calls==idle,'Empty commit stays idle')
end
for _,mutate in ipairs({function(v)v.pose[12]=nil end,function(v)v.pose[13]=1 end,function(v)v.pose[1]=0/0 end,
 function(v)v.pose[1]=math.huge end,function(v)v.pose=setmetatable(v.pose,{})end,function(v)v.pose=nil end})do
 local f=fixture();local before=f:ready().nodes[8];local desired=f:desired();mutate(desired);f:step()
 check(f.adapter.set_node(f.target,f.rig,8,before,desired,f.mode)==false and f.writes==0,'Malformed/missing raw pose refuses before mutation')
end
for _,fault in ipairs({'count11','count16','nil','body_scale','qnorm','constructor','scale_return'})do
 local f=fixture();f:ready();local desired={p={0,0,0},q={0,0,0,1},s={1,1,1}}
 if fault=='count11'then f.matrix_count=11 elseif fault=='count16'then f.matrix_count=16 elseif fault=='nil'then f.nil_pose=true
 elseif fault=='body_scale'then f.nodes[8].pose[5]=1.5 elseif fault=='qnorm'then f.nodes[8].pose[4]=2
 elseif fault=='constructor'then f.constructor_drift=true;desired.pose=clone(f.nodes[8].pose)else f.scale_returns_value=true end
 f:step();local result=fault=='constructor'or fault=='scale_return'
 if result then result=f.adapter.canonical_node(f.target,f.rig,desired)else result=f.adapter.snapshot(f.target,f.rig)end
 check(result==nil and f.writes==0,'Unexpected matrix/scalar ABI refuses read/canonical work: '..fault)
end
for _,slot in ipairs({4,5})do
 local f=fixture();local before=f:ready().nodes[8];local desired=f:desired();desired.pose[slot]=2;f:step()
 check(f.adapter.set_node(f.target,f.rig,8,before,desired,f.mode)==false and f.writes==0 and f.adapter.status().pending==0,
  'Raw target-derived invalid quaternion/scale cannot hide behind valid claimed PQS')
end

-- Failed whole-matrix calls retain uncertainty. Only exact endpoints are known.
for _,throws in ipairs({false,true})do for _,effect in ipairs({'none','all'})do
 local f=fixture();local base=f:ready().nodes[8];local desired=f:desired();local problem={kind='pose-failure'}
 f.failure.pose={effect=effect,throw=throws,refuse=not throws,object=problem};f:step()
 local ok,why=f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode)
 check(ok==false and why==problem and f.writes==1 and f.adapter.status().pending==1)
 local actual=f:snapshot().nodes[8];check(same(actual.pose,effect=='all'and desired.pose or base.pose))
 local writes=f.writes;f:step();check(f.adapter.resolve_node(f.target,f.rig,8,base,desired,actual,f.mode)==true and f.writes==writes)
 f.failure={};f:step();check(f.adapter.set_node(f.target,f.rig,8,actual,base,f.mode)==true)
 f:step();check(f.adapter.commit(f.target,f.rig)==true and f.adapter.status().pending==0 and same(f.nodes,f.original))
end end
do
 local f=fixture();local base=f:ready().nodes[8];local desired=f:desired();f.failure.pose={effect='partial',refuse=true};f:step()
 check(f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode)==false)
 local actual=f:snapshot().nodes[8];local writes=f.writes;f:step()
 check(f.adapter.resolve_node(f.target,f.rig,8,base,desired,actual,f.mode)==false and f.writes==writes,'No element/axis prefix guesses for a partial matrix')
 f:step();check(f.adapter.set_node(f.target,f.rig,8,actual,base,f.mode)==false and f.writes==writes,'Unknown matrix cannot be overwritten')
 f.failure={};f.nodes[8]=clone(f.original[8]);f:snapshot();f:step();check(f.adapter.commit(f.target,f.rig)==true and f.adapter.status().pending==0)
end
do
 local f=fixture();local base=f:ready().nodes[8];local desired=f:desired();f.failure.pose={effect='all',mutate=function(state,index)state.nodes[index].pose[8]=2^-20 end};f:step()
 check(f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode)==false and f.adapter.status().pending==1)
 local diagnostic=f.adapter.status().pose_readback_mismatch
 check(diagnostic.index==8 and diagnostic.first_scalar==8 and diagnostic.max_abs_delta==2^-20 and #diagnostic.observed==12,'Exact raw-matrix readback diagnostic')
 f:step();local actual=f:snapshot().nodes[8];check(f.adapter.resolve_node(f.target,f.rig,8,base,desired,actual,f.mode)==false,'Foreign raw scalar cannot borrow matching PQS ownership')
 local function primitive(v)local k=type(v);check(k=='table'or k=='number'or k=='string','No opaque retained');if k=='table'then for _,item in pairs(v)do primitive(item)end end end
 primitive(diagnostic)
end

-- Scene refresh and original-mode restoration retain exact raw authority.
for _,throws in ipairs({false,true})do
 local f=fixture();local base=f:ready().nodes[8];local desired=f:desired();f:step();check(f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode))
 f.update_throw=throws and{}or nil;f.update_refuse=not throws;f:step();check(f.adapter.commit(f.target,f.rig)==false)
 f.nodes[8].pose[8]=2^-20;f:step();check(f.adapter.snapshot(f.target,f.rig)==nil,'Unknown commit needs exact raw proof')
 f.nodes[8].pose=clone(desired.pose);f:snapshot();f.update_throw=nil;f.update_refuse=nil;f:step();check(f.adapter.set_node(f.target,f.rig,8,desired,base,f.mode))
 f.on_update=function(state)state.nodes[8].pose[8]=2^-20 end;f:step();check(f.adapter.commit(f.target,f.rig)==false,'Original raw matrix remains guarded through scene refresh')
end
for _,change in ipairs({'binding','matrix_namespace','constructor_binding','dead','world','session','resource','topology','count'})do
 local f=fixture();local base=f:ready().nodes[8];local desired=f:desired();local calls=f.calls
 if change=='binding'then f.sr.Unit.local_pose=function()error('Foreign called')end elseif change=='matrix_namespace'then f.sr.Matrix4x4={}
 elseif change=='constructor_binding'then f.sr.Matrix4x4.from_elements=function()error('Foreign called')end
 elseif change=='dead'then f.alive=false elseif change=='world'then f.current_world=newproxy()elseif change=='session'then f.current_session=newproxy()
 elseif change=='resource'then f.actual_resource='foreign'elseif change=='topology'then f.bad_parent=8 else f.count=106 end
 f:step();check(f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode)==false and f.writes==0,'Fresh guard stops '..change)
 if change=='binding'or change=='matrix_namespace'or change=='constructor_binding'then check(f.calls==calls,'Changed bindings stop before native work')end
end

-- Preview authorizer labels describe one pose mutation, never components.
do
 local f=fixture();local labels={};local revoked=false;local policy={contract='unit-pose-preview-v1',trial_id='offline-preview',session=f.session,
  authorize=function(operation)labels[#labels+1]=operation;return not revoked or operation:match('^restore_')~=nil or operation=='commit' end}
 f.adapter=assert(Native.preview(f.sr,policy));f:discover();local base=f:snapshot().nodes[8];local desired=f:desired();f:step()
 check(f.adapter.set_mode(f.target,f.rig,f.mode,'ignore'));f:step();check(f.adapter.set_node(f.target,f.rig,8,base,desired,'ignore'));f:step();check(f.adapter.commit(f.target,f.rig))
 revoked=true;local other=f:desired();other.pose[10]=float(.25);local writes=f.writes;f:step();check(f.adapter.set_node(f.target,f.rig,8,desired,other,'ignore')==false and f.writes==writes and f.adapter.status().pending==0)
 policy.authorize=function()error('Captured authorizer replaced')end;f:step();check(f.adapter.set_node(f.target,f.rig,8,desired,base,'ignore'));f:step();check(f.adapter.set_mode(f.target,f.rig,'ignore','position_and_rotation')and f.adapter.commit(f.target,f.rig))
 check(table.concat(labels,',')=='set_mode,set_node.pose,commit,set_node.pose,restore_node.pose,restore_mode,commit')
 check(f.adapter.status().qualified==false and f.adapter.status().preview==true and same(f.nodes,f.original))
 local calls,authorizations=f.calls,#labels;for _=1,100 do f.adapter.status()end;check(f.calls==calls and #labels==authorizations,'Idle preview has no work')
end
for _,change in ipairs({'binding','session','pose','mode'})do
 local f=fixture();local auth=0;f.adapter=assert(Native.preview(f.sr,{contract='unit-pose-preview-v1',trial_id='fresh',session=f.session,authorize=function()
  auth=auth+1;if change=='binding'then f.sr.Unit.local_pose=function()error('Foreign')end elseif change=='session'then f.current_session=newproxy()
  elseif change=='pose'then f.nodes[8].pose[8]=2^-20 else f.mode='foreign'end;return true
 end}))
 f:discover();local base=f:snapshot().nodes[8];local desired=f:desired();f:step()
 check(f.adapter.set_node(f.target,f.rig,8,base,desired,f.mode)==false and auth==1 and f.writes==0 and f.adapter.status().pending==0,'Fresh post-authorizer guard leaves no unattempted ledger: '..change)
end

-- Full actual controller consumes matrix authority; original matrices survive
-- changed quaternion readback, full/upper poses and uncertain mode/body cleanup.
local function controller_fixture()
 local f=fixture();f:arm();local bank={version=1,rig=f.rig,catalog={{id='full',label='Full'},{id='upper',label='Upper'}},decode=function(id)
  local result={full_body=id=='full',nodes={}};for i=8,92 do result.nodes[i]={p={10+i/10,.2,.3},q={0,.6,0,.8},s={1,1,1}}end;return result
 end}
 f.controller=Subject.new(f.adapter,bank,function()return true end);check(f.controller.refresh());check(f.controller.select(f.controller.choices()[1].id));return f
end
do
 local f=controller_fixture();f:step();check(f.controller.hold_bone_transfer())
 check(f.mode=='ignore'and f.writes==1 and same(f.nodes,f.original),'Mode-only trial writes no root or body pose')
 f:step();check(f.controller.close()and f.mode=='position_and_rotation'and f.writes==2)
 check(same(f.nodes,f.original),'Mode-only restoration never rewinds transforms')
end
do
 local f=controller_fixture();f:step();check(f.controller.apply('full'));check(f.writes==86,'85 whole-pose writes plus mode')
 f.q_drift=2^-23;f:step();check(f.controller.apply('upper'));check(same(f.nodes[8],f.original[8]),'Upper body retains original root raw matrix')
 f:step();check(f.controller.reset()and f.controller.status().restored and same(f.nodes,f.original),'Controller restores every original raw matrix')
 local calls,writes=f.calls,f.writes;for _=1,100 do f.controller.status();f.controller.choices();check(f.controller.reset())end;check(f.calls==calls and f.writes==writes,'No lease means zero idle restore work')
end
do
 local f=controller_fixture();f.failure.pose={effect='partial',refuse=true};f:step();check(not f.controller.apply('full')and f.controller.status().pending)
 f:step();check(not f.controller.close()and f.mode=='position_and_rotation','Known mode can restore while raw matrix remains unknown')
 local calls,writes=f.calls,f.writes;for _=1,100 do check(not f.controller.close())end;check(f.calls==calls and f.writes==writes,'Unknown partial never retries automatically')
 f.failure={};f.nodes[8]=clone(f.original[8]);f:step();check(f.controller.recover()and same(f.nodes,f.original)and f.adapter.status().pending==0,'Explicit exact original observation retires unknown matrix receipt')
end
-- Shared cape solver is captured before body writes, maintained only while
-- held, and restored after body evaluation; another subject grants no access.
for _,local_subject in ipairs({true,false})do
 local f=fixture();local captures,applies,restores=0,0,0
 f.policy.cape_reader={pose_frame=function()return{root_handle=local_subject and f.unit or newproxy(),world=f.world}end,
  pose_valid=function()return true end}
 f.policy.cape_factory=function(sr,reader,guard)return{
  capture=function(frame)guard(frame,true);captures=captures+1;check(f.writes==0);return{{}}end,
  apply=function(lease)applies=applies+1;check(f.updates>0 and f.mode=='ignore')end,
  restore=function(lease)restores=restores+1;check(same(f.nodes,f.original)and f.mode=='position_and_rotation')end}end
 local base=f:ready().nodes[8];local desired=f:desired();f:step()
 check(f.adapter.set_mode(f.target,f.rig,f.mode,'ignore'))
 check(f.adapter.set_node(f.target,f.rig,8,base,desired,'ignore')and f.adapter.commit(f.target,f.rig))
 check(captures==(local_subject and 1 or 0)and applies==captures)
 check(f.adapter.maintain(f.target,f.rig));check(applies==captures*2)
 check(f.adapter.set_node(f.target,f.rig,8,desired,base,'ignore'))
 check(f.adapter.set_mode(f.target,f.rig,'ignore','position_and_rotation')and f.adapter.commit(f.target,f.rig))
 check(restores==captures)
end
-- Windows photographic cape association is independent of native local-player
-- ownership. Capture precedes pose writes; placement follows the commit event.
do
 local f=fixture();local captures,applies,restores=0,0,0;local lease={meshes={1,2,3}}
 f.policy.selected_cape={capture=function(frame)
  check(frame.explicit_subject and frame.root_handle==f.unit and frame.world==f.world)
  captures=captures+1;check(f.writes==0);return lease
 end,apply=function(record,frame)
  check(record==lease and frame.root_handle==f.unit and f.updates>0 and f.mode=='ignore')
  applies=applies+1;return 3
 end,release=function(record)
  check(record==lease and same(f.nodes,f.original)and f.mode=='position_and_rotation')
  restores=restores+1;return true
 end}
 local base=f:ready().nodes[8];local desired=f:desired();f:step()
 check(f.adapter.set_mode(f.target,f.rig,f.mode,'ignore'))
 check(f.adapter.set_node(f.target,f.rig,8,base,desired,'ignore')and f.adapter.commit(f.target,f.rig))
 check(captures==1 and applies==1)
 local calls=f.calls
 for _=1,100 do check(f.adapter.maintain(f.target,f.rig))end
 check(applies==1 and f.calls==calls,'Unchanged Windows pose does not poll cape placement')
 check(f.adapter.set_node(f.target,f.rig,8,desired,base,'ignore'))
 check(f.adapter.set_mode(f.target,f.rig,'ignore','position_and_rotation')and f.adapter.commit(f.target,f.rig))
 check(restores==1)
end
print('steam_subject_native_tests: '..assertions..' assertions passed (actual Lua5.1; strict matrix12; source only)')

do
 local f=fixture();local a=f:arm();check(a.session_current()==true)
 local writes=f.writes;f.current_session=newproxy();check(a.session_current()==false and f.writes==writes,'Session predicate is read-only')
 f.current_session=nil;local current,why=a.session_current();check(current==nil and type(why)=='string','Unavailable session is not a replacement session')
end

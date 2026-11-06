-- Reuse the established strict userdata/matrix fixture. The controller and
-- adapter exercised below come from the actual sandboxed Chef bundle.
local file=assert(io.open('freecam/steam_subject_native_tests.lua','rb'))
local fixture_source=file:read('*a');file:close()
local prefix=assert(fixture_source:match('^(.-)%-%- NATIVE_FIXTURE_END'))
local fixture=assert(loadstring(prefix..'\nreturn fixture'))()
local s,c,m,addon,shared,bindings,env=chef_fixture()
assert(m['wj.assets.poses']==nil and m['wj.steam_subject_native']==nil,'Pose payload is lazy until explicitly armed')
local f=fixture();s.world=f.world;s.session=f.session
local native_call=c.call
for index,name in ipairs({'right','forward','up'}) do
    local start=(index-1)*3+1
    f.sr.Matrix4x4[name]=function(matrix)
        local data=f.userdata[matrix];assert(data.kind=='matrix' and data.frame==f.frame)
        local vector=newproxy();f.userdata[vector]={kind='vector',frame=f.frame,value={data.value[start],data.value[start+1],data.value[start+2]}}
        return vector
    end
end
local skipped
function c.call(name,...)
    if name==skipped then return nil,'skipped',nil,nil end
    local family,method=name:match('^(%w+)%.([%w_]+)$')
    local fn=method and f.sr[family] and f.sr[family][method]
    if name=='Vector3' then fn=f.sr.Vector3 end
    if fn then
        local a,b,d,e=fn(...);return a,b,d,e -- actual Chef padded result shape
    end
    return native_call(name,...)
end
local bank={version=1,rig=f.rig,catalog={{id='test',label='Fixture pose'},{id='second',label='Second pose'}}}
function bank.decode(id)
    local out={full_body=true,nodes={}}
    for i=8,92 do out.nodes[i]={p={id=='test' and .1 or .2,.2,.3},q={0,0,0,1},s={1,1,1}} end
    return out
end
local loads=0
local function load()
    loads=loads+1
    return {model=env.require('wj.steam_subject'),native=env.require('wj.steam_subject_native'),bank=bank}
end
local simulation={frozen=false}
local subject=m['wj.chef.subject'].new(c,load,simulation)
local calls=f.calls
for _=1,1000 do assert(subject.status().state=='disabled') end
assert(f.calls==calls and loads==0)
local refreshed,reason=subject.refresh()
assert(refreshed,tostring(reason)..': '..tostring(subject.status().detail))
assert(#subject.choices()==1 and loads==1)
assert(subject.select(1) and not subject.apply(1) and f.writes==0)
simulation.frozen=true;f:step();assert(subject.apply(1) and subject.status().state=='posed')
assert(f.mode=='ignore' and f.nodes[8].pose[10]~=f.original[8].pose[10])
assert(not subject.refresh(),'Discovery cannot retire a held pose')
calls=f.calls;for _=1,1000 do subject.status() end;assert(f.calls==calls,'Held poses never poll')
f:step();assert(subject.reset() and f.mode=='position_and_rotation')
for i=8,92 do for j=1,12 do assert(f.nodes[i].pose[j]==f.original[i].pose[j]) end end
s.peers.second=true;assert(not subject.apply(2));s.peers.second=nil
skipped='Unit.set_local_pose';f:step();assert(not subject.apply(2) and subject.status().pending)
skipped=nil;f:step();assert(subject.recover() and subject.close())

-- Confirm the twelve-scalar adapter never calls the truncated multi-return
-- function, preserves exact axis storage and strips padding from void calls.
local bridge=m['wj.chef.subject'].engine(c)
local matrix=f.sr.Matrix4x4.from_elements(0,0,0,1,1,1,1,0,0,.1,.2,.3)
local values={bridge.Matrix4x4.to_elements(matrix)};assert(#values==12 and values[10]~=nil)
assert(select('#',bridge.Matrix4x4.set_scale(matrix,f.sr.Vector3(1,1,1)))==0)
skipped='Matrix4x4.set_scale';assert(not pcall(bridge.Matrix4x4.set_scale,matrix,f.sr.Vector3(1,1,1)));skipped=nil

-- Runtime restores a pose before an explicit thaw or Cinema handoff.
local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local runtime=m['wj.chef.runtime'].new(c,{
    camera={new=function() return {begin=function() return true end,valid=function() return s.focused end,
        step=function() return true end,frame=function() return frame end,apply=function() return true end,
        maintain=function() return true end,close=function() return true end} end},
    controls=m['wj.chef.controls'],bindings=bindings,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=m['wj.composition'],shots=m['wj.chef.shots'],path=m['wj.steam_path'],subject=m['wj.chef.subject'],load_subject=load,
})
c.set('camera',true);runtime.update();c.set('subject_preview',true);runtime.update()
c.set('subject_select',true);runtime.update();c.set('freeze',true);runtime.update()
c.set('subject_apply',true);runtime.update();assert(f.mode=='ignore' and runtime.subject_status().state=='posed')
c.set('freeze',false);runtime.update();assert(f.mode=='position_and_rotation' and s.rate==1)
c.set('freeze',true);runtime.update();c.set('subject_apply',true);runtime.update()
c.set('cinema_begin',true);runtime.update();assert(f.mode=='position_and_rotation' and runtime.cinema_active())
c.set('cinema_reposition',true);runtime.update();assert(s.rate==0)
c.set('subject_apply',true);runtime.update();s.focused=false;runtime.update()
assert(runtime.status()=='closed' and f.mode=='position_and_rotation' and s.rate==1)
assert(runtime.shutdown())
local full_bank=env.require('wj.assets.poses');assert(#full_bank.catalog==213 and full_bank.rig.node_count==107)
print('chef subjects: lazy payload, padded matrix bridge, explicit selection, exact restore, solo/freeze and Cinema handoff passed')

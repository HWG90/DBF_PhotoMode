local frame={position={1,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
local options={right=0,forward=2,up=0,color=1,intensity=3}
local function fixture()
    local s,c,m,addon,shared,bindings=chef_fixture()
    local native=c.call;local units={}
    s.spawned=0;s.destroyed=0;s.moved=0;s.light_writes=0;s.ledger=0;s.alive_reads=0
    function c.spawn(resource,x,y,z)
        assert(resource=='e07f49224f0a5759');if s.unloaded then return nil,'unit not loaded' end
        local u=newproxy();units[u]={alive=true,world=s.world,position={x,y,z}}
        s.spawned=s.spawned+1;s.ledger=s.ledger+1;return u
    end
    function c.despawn(u)
        assert(units[u] and not units[u].alive,'Only release the ledger after confirmed destruction')
        s.ledger=s.ledger-1;return true
    end
    function c.lights(u) assert(units[u].alive);return s.wrong_count and 2 or 1 end
    function c.light(u,index)
        assert(index==1 and units[u].alive and units[u].world==s.world)
        local function set(key,value)
            s.light_writes=s.light_writes+1
            if s.fail_light==key then if s.fail_once then s.fail_light=nil end;return false end
            units[u][key]=value;return true
        end
        return {
            set_color=function(r,g,b) return set('color',{r,g,b}) end,
            set_intensity=function(v) return set('intensity',v) end,
            set_enabled=function(on) return set('enabled',on) end,
            set_shadows=function(on) assert(on==false);return set('shadows',on) end,
            set_falloff=function(start,finish) assert(start==0);return set('range',finish) end,
        }
    end
    function c.call(name,...)
        if s.skip==name then return nil,'skipped' end
        if name=='Unit.alive' then
            local u=...;assert(units[u].world==s.world,'Never dereference a retired world')
            s.alive_reads=s.alive_reads+1;return units[u].alive,nil,nil,nil
        elseif name=='World.destroy_unit' then
            assert(select('#',...)==2);local w,u=...;assert(w==s.world and units[u].world==w)
            s.destroyed=s.destroyed+1;if not s.deferred then units[u].alive=false end
            return nil,nil,nil,nil
        elseif name=='Vector3' then assert(select('#',...)==3);return {...},nil,nil,nil
        elseif name=='Unit.light' then local u,index=...;assert(index==1 and units[u].alive);return u,nil,nil,nil
        elseif name=='Light.node' then return 1,nil,nil,nil
        elseif name=='Light.falloff_end' then local u=...;return s.bad_range and 0 or units[u].range or 8,nil,nil,nil
        elseif name=='Light.set_type' or name=='Light.set_spot_angle_end' then
            local u,value=...;units[u][name]=value;return nil,nil,nil,nil
        elseif name=='Quaternion.look' then assert(select('#',...)==2);return {...},nil,nil,nil
        elseif name=='Unit.set_local_rotation' then
            assert(select('#',...)==3);local u,node,q=...;assert(node==1);units[u].rotation=q;return nil,nil,nil,nil
        elseif name=='Unit.set_local_position' then
            assert(select('#',...)==3,'Never leak four padded Vector3 results into a native call')
            local u,node,position=...;assert(node==1 and units[u].alive);units[u].position=position
            s.moved=s.moved+1;return nil,nil,nil,nil
        elseif name=='World.update_unit' then
            assert(select('#',...)==2);local w,u=...;assert(w==s.world and units[u].alive);return nil,nil,nil,nil
        end
        return native(name,...)
    end
    return s,c,m['wj.chef.lights'].new(c,m['wj.chef.shots'].valid),m,bindings,units
end
local s,c,lights,m,bindings,units=fixture()
assert(lights.count()==0 and next(s.counts)==nil and not c.has('lights'))
assert(lights.apply(1,options,frame));assert(s.spawned==1 and s.ledger==1 and s.light_writes==4)
local unit,record=next(units);assert(record.position[1]==3 and record.position[2]==2 and record.enabled and not record.shadows)
for _=1,1000 do assert(lights.count()==1) end
assert(s.alive_reads==0,'Stationary lights never inspect the world or units')
assert(lights.apply(1,options,frame));assert(s.light_writes==4 and s.moved==0 and s.spawned==1)
local shifted={right=1,forward=2,up=3,color=2,intensity=4}
assert(lights.apply(1,shifted,frame));assert(s.moved==1 and s.light_writes==6)
assert(record.position[1]==3 and record.position[2]==1 and record.position[3]==6)
assert(lights.apply(2,options,frame) and lights.apply(3,options,frame) and lights.count()==3)
assert(not lights.apply(4,options,frame) and lights.count()==3 and s.spawned==3)
assert(lights.clear() and lights.count()==0 and s.ledger==0 and s.destroyed==3)

s,c,lights,m,bindings,units=fixture();s.unloaded=true
assert(not lights.apply(1,options,frame) and s.spawned==0 and lights.count()==0)
s.unloaded=false;s.fail_light='intensity'
assert(not lights.apply(1,options,frame) and s.destroyed==1 and lights.count()==0 and s.ledger==0)
s.fail_light=nil;s.wrong_count=true
assert(not lights.apply(1,options,frame) and s.destroyed==2 and lights.count()==0)
s.wrong_count=false;assert(lights.apply(1,options,frame))
s.skip='World.destroy_unit';assert(not lights.clear() and lights.count()==1 and s.ledger==1)
s.skip=nil;s.deferred=true;assert(not lights.clear() and lights.count()==1 and s.ledger==1)
s.deferred=false;assert(lights.clear() and lights.count()==0 and s.ledger==0)

-- World identity is checked before touching a unit, including at cleanup.
s,c,lights,m,bindings,units=fixture();assert(lights.apply(1,options,frame))
s.world={};local reads=s.alive_reads
assert(lights.clear() and s.alive_reads==reads and s.destroyed==0,'Retired worlds belong to loader cleanup')
assert(lights.apply(1,options,frame));s.generation=s.generation+1
assert(lights.clear() and s.destroyed==1,'A new scene in the same engine world still cleans owned lights')
assert(lights.apply(1,options,frame));assert(#lights.markers()==1)
s.world={};s.unloaded=true
assert(not lights.apply(1,options,frame) and #lights.markers()==0,'Failed spawn cannot retain a retired marker')

-- Explicit actions are queued; changing options alone does no light work.
s,c,lights,m,bindings,units=fixture()
local runtime=m['wj.chef.runtime'].new(c,{
    camera={new=function() return {begin=function() return true end,valid=function() return s.focused end,
        step=function() return true end,frame=function() return frame end,apply=function() return true end,
        maintain=function() return true end,close=function() return true end} end},
    controls=m['wj.chef.controls'],bindings=bindings,motion=m['wj.chef.motion'],simulation=m['wj.chef.simulation'],
    composition=m['wj.composition'],shots=m['wj.chef.shots'],path=m['wj.steam_path'],lights=m['wj.chef.lights'],
})
c.set('light_intensity',5);assert(runtime.update==nil and s.spawned==0)
c.set('light_place',true);runtime.update();assert(s.spawned==0 and runtime.update==nil)
c.set('camera',true);runtime.update();c.set('light_place',true);runtime.update()
assert(runtime.light_count()==1 and s.spawned==1 and s.values.light_place==false)
local swatches=0
function c.screen() return 1920,1080 end
function c.color(r,g,b,a) return {r,g,b,a} end
function c.rect(x,y,w,h,color) assert(color[1]==12 and color[2]==34 and color[3]==56);swatches=swatches+1 end
c.set('light_swatch',true);c.set('light_color',7)
c.set('light_red',12);c.set('light_green',34);c.set('light_blue',56);runtime.render();assert(swatches==1)
c.set('light_swatch',false);assert(runtime.render==nil);c.set('light_color',1)
reads=s.alive_reads;local writes=s.light_writes
for _=1,1000 do runtime.update() end
assert(s.alive_reads==reads and s.light_writes==writes,'Camera updates never poll static lights')
c.set('light_slot',2);c.set('light_color',3);c.set('light_place',true);runtime.update()
assert(runtime.light_count()==2)
s.skip='World.destroy_unit';c.set('camera',false)
assert(runtime.status()=='cleanup_pending' and runtime.light_count()==2 and runtime.update==nil)
s.skip=nil;c.set('light_clear',true);runtime.update();assert(runtime.light_count()==0)
c.set('camera',false);assert(runtime.status()=='cleanup_pending','Chef ignores unchanged toggles')
c.set('camera_cleanup',true);runtime.update();assert(runtime.status()=='closed' and runtime.update==nil)
c.set('camera',true);runtime.update();c.set('light_place',true);runtime.update();s.focused=false;runtime.update()
assert(runtime.status()=='closed' and runtime.light_count()==0 and runtime.update==nil)
assert(runtime.shutdown())

-- Spot/cone and RGB edits use only the owned component. Following is idle
-- unless the numeric camera changes; a bad range readback destroys that copy.
s,c,lights,m,bindings,units=fixture()
local advanced={right=1,forward=2,up=3,color=1,rgb={12,34,56},intensity=3,kind='spot',cone=35,range=12,follow=true}
assert(lights.apply(1,advanced,frame));unit,record=next(units)
assert(record.color[1]==12 and record.range==12 and record['Light.set_type']=='spot' and record.rotation)
local marker_list=lights.markers();assert(marker_list==lights.markers())
reads=s.alive_reads;writes=s.light_writes
for _=1,1000 do assert(lights.tick(frame)) end
assert(s.alive_reads==reads and s.light_writes==writes)
local shifted={position={3,2,3},forward={1,0,0},right={0,-1,0},up={0,0,1},fov=1}
assert(lights.tick(shifted) and s.moved==1 and lights.markers()~=marker_list)
s.bad_range=true;advanced.range=15
assert(not lights.apply(1,advanced,frame) and lights.count()==0)
s.bad_range=false;advanced.range=8;advanced.follow=false;assert(lights.apply(1,advanced,frame))

local data,loads,saves,fail_save=nil,0,0,false
function c.load_table(name) assert(name=='lighting_setups_v1');loads=loads+1;return data,data and nil or 'none saved' end
function c.save_table(name,next_data) saves=saves+1;if fail_save then return false,'disk full' end;data=next_data;return true end
local setups=m['wj.chef.light_setups'].new(c,lights,m['wj.chef.lights'],m['wj.chef.shots'])
assert(loads==0 and setups.action('save',1,frame) and saves==1)
assert(lights.clear());assert(setups.action('recall',1,shifted) and lights.count()==1)
local list=lights.export();assert(list[1].frame.position[1]==shifted.position[1] and list[1].options.rgb[3]==56)
fail_save=true;assert(not setups.action('clear',1,shifted));fail_save=false
assert(setups.action('recall',1,frame),'Failed save must preserve the cached setup')
assert(setups.rig(1,frame,5) and lights.count()==3)
s.fail_light='intensity';s.fail_once=true
assert(not setups.rig(2,frame,5) and lights.count()==3,'A partial replacement restores the previous definitions')
local bad={version=1,slots={[1]={[1]={frame=frame,options={kind='injected'}}}}};data=bad
local broken=m['wj.chef.light_setups'].new(c,lights,m['wj.chef.lights'],m['wj.chef.shots'])
local previous=saves;assert(not broken.action('save',1,frame) and saves==previous)
assert(lights.clear())
-- Marker drag uses a bounded press snapshot and preserves its plane/depth.
assert(lights.apply(1,options,frame))
local x,y,w,h=100,100,1920,1080
function c.cursor() return x,y end
function c.screen() return w,h end
function c.world_to_screen() return 100,100 end
local drag=m['wj.chef.light_drag'].new(c,lights)
reads=s.alive_reads
for _=1,100 do assert(not drag.tick(false,false,frame)) end
assert(s.alive_reads==reads)
assert(drag.tick(true,false,frame));local p=lights.markers()[1].position
local original_y=p[2];x=x+100;assert(drag.tick(true,false,frame))
local delta=original_y-lights.markers()[1].position[2];assert(delta>0)
local previous_y=lights.markers()[1].position[2];x=x+100;assert(drag.tick(true,true,frame))
assert(math.abs(previous_y-lights.markers()[1].position[2]-delta*.1)<1e-8)
w=1280;local ok,why=drag.tick(true,false,frame);assert(not ok and why)
reads=s.alive_reads;for _=1,100 do assert(not drag.tick(true,false,frame)) end
assert(s.alive_reads==reads,'A failed drag stays idle until released')
drag.tick(false,false,frame);assert(lights.aim(1,{8,2,3}));assert(lights.export()[1].options.kind=='spot')
assert(lights.clear())
print('chef lights: owned resource, explicit edits, padded ABI, failed cleanup, no idle work and world retirement passed')

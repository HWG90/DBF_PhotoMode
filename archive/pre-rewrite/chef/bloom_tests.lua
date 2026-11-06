local KEY='dbf.war_journalist.bloom_owner'
local function fixture(shared)
    local s,c,mods,addon,owners=chef_fixture(shared)
    local original=c.call
    s.bloom=true;s.dof=false;s.render_reads=0;s.render_writes={}
    function c.call(name,...)
        if s.skip==name then return nil,'skipped' end
        if name=='Application.render_setting' then
            assert(select('#',...)==1);local key=...;assert(key=='bloom_enabled' or key=='dof_enabled');s.render_reads=s.render_reads+1
            local value=s.bloom;if key=='dof_enabled' then value=s.dof end;return value,nil,nil,nil
        elseif name=='Application.set_render_setting' then
            assert(select('#',...)==2);local key,value=...
            assert((key=='bloom_enabled' or key=='dof_enabled') and (value=='true' or value=='false'))
            s.render_writes[#s.render_writes+1]=value
            if not s.async then if key=='dof_enabled' then s.dof=value=='true' else s.bloom=value=='true' end end
            return nil,nil,nil,nil
        end
        return original(name,...)
    end
    return s,c,mods['wj.chef.bloom'].new(c),addon,owners,mods
end
local s,c,bloom,addon,owners=fixture()
for _=1,1000 do assert(bloom.tick()) end
assert(s.render_reads==0 and #s.render_writes==0)
assert(bloom.request(false) and bloom.waiting() and #s.render_writes==1)
local reads=s.render_reads
for _=1,1000 do bloom.tick() end
assert(s.render_reads==reads,'Acknowledgement reads must be rate bounded')
s.now=s.now+.11;assert(bloom.tick() and bloom.state=='active' and not s.bloom)
reads=s.render_reads;local clocks=s.counts['Application.time_since_launch']
for _=1,1000 do bloom.tick() end
assert(s.render_reads==reads and s.counts['Application.time_since_launch']==clocks,'Settled state is idle')
assert(bloom.request(false) and #s.render_writes==1)
assert(bloom.close() and bloom.state=='closed' and s.bloom and owners[KEY]==nil)

-- Coalesce changing intent while a deferred setting is being acknowledged.
s,c,bloom=fixture();s.async=true
assert(bloom.request(false));assert(bloom.request(true));assert(bloom.request(false))
assert(#s.render_writes==1)
s.now=s.now+.11;bloom.tick();assert(bloom.waiting())
s.bloom=false;s.now=s.now+.11;bloom.tick();assert(bloom.state=='active')
assert(not bloom.close());s.bloom=true;s.now=s.now+.11
assert(bloom.tick() and bloom.state=='closed')

-- Returning to the game setting during an outstanding write must still
-- restore its observed baseline after that first write lands.
s,c,bloom=fixture();s.async=true;assert(bloom.request(false));assert(not bloom.close())
s.bloom=false;s.now=s.now+.11;bloom.tick()
assert(#s.render_writes==2 and s.render_writes[2]=='true' and bloom.waiting())
s.bloom=true;s.now=s.now+.11;bloom.tick();assert(bloom.state=='closed')

-- Foreign values and foreign leases are never overwritten during cleanup.
s,c,bloom,addon,owners=fixture();assert(bloom.request(false));s.now=s.now+.11;bloom.tick()
s.bloom=true;assert(bloom.close() and #s.render_writes==1 and s.bloom)
assert(bloom.request(false));s.now=s.now+.11;bloom.tick()
owners[KEY]={owner='other'};assert(bloom.close() and #s.render_writes==2 and owners[KEY].owner=='other')
assert(not bloom.request(true) and #s.render_writes==2)

-- Refused/late writes retain ownership. The bounded poll stops after two
-- seconds; only explicit cleanup retries acknowledge a late completion.
s,c,bloom,addon,owners=fixture();s.async=true;assert(bloom.request(false))
s.now=s.now+2.1;assert(not bloom.tick() and bloom.state=='blocked' and owners[KEY])
reads=s.render_reads;clocks=s.counts['Application.time_since_launch']
for _=1,1000 do assert(not bloom.tick()) end
assert(reads==s.render_reads and clocks==s.counts['Application.time_since_launch'])
assert(not bloom.close() and #s.render_writes==1)
s.bloom=false;s.async=false;assert(bloom.close() and s.bloom and owners[KEY]==nil)
s,c,bloom,addon,owners=fixture();s.skip='Application.set_render_setting'
assert(not bloom.request(false) and bloom.state=='blocked' and owners[KEY])
assert(not bloom.close() and owners[KEY],'Refused submission cannot advertise a clean stop')
s,c,bloom=fixture();assert(bloom.request(false));s.now=s.now-1
assert(not bloom.tick() and bloom.state=='blocked')

-- Runtime hooks appear only for transitions/acknowledgements.
s,c,bloom,addon,owners=fixture()
c.set('bloom',2);assert(addon.update);addon.update();assert(not s.bloom)
s.now=s.now+.11;addon.update();assert(addon.update==nil)
c.set('bloom',1);addon.update();assert(s.bloom and addon.update==nil)
c.set('bloom',2);addon.update();s.now=s.now+.11;addon.update()
s.events.world();assert(s.bloom and addon.update==nil and s.values.bloom==1)
c.set('bloom',2);addon.update();s.now=s.now+.11;addon.update()
assert(addon.shutdown() and s.bloom and owners[KEY]==nil)
s,c,bloom,addon,owners=fixture();s.async=true
c.set('bloom',2);addon.update();assert(not addon.shutdown() and owners[KEY] and addon.update==nil)
s,c,bloom,addon,owners=fixture()
c.set('native_dof',3);c.set('bloom',2);addon.update();s.now=s.now+.11;addon.update()
assert(s.dof and not s.bloom and owners['dbf.war_journalist.dof_owner'] and owners[KEY])
c.set('native_dof',1);addon.update();assert(not s.dof and not s.bloom and not owners['dbf.war_journalist.dof_owner'])
assert(addon.shutdown() and s.bloom and not s.dof)
print('chef bloom: bounded acknowledgements, idle behavior, external edits, coalescing and pending cleanup passed')

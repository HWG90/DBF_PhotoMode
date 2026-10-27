-- Fixture host only; never packaged. Each case executes only the bundled addon
-- in Chef's pinned sandbox, with a small engine and menu contract supplied here.
function chef_fixture(shared)
    local s={world={},generation=1,session=newproxy(),peers={local_peer=true},now=10,focused=true,
        writes={},counts={},rate=1,keys={},menu=false,values={},changes={},events={},specs={},logs={}}
    shared=shared or{}
    local c={api=3,name='mods/goose/war_journalist',TOP=1000}
    local capabilities={after_startup=true,settings=true,share=true,events=true,require=true,bind=true,menu=true,shims=true,
        dev=true,logs=true,own_log=true,units=true,spawn=true,timers=true,budget=true,session=true,settings_file=true,
        shapes=true,sprite_sheets=true,notify=true,typed=true,key_labels=true,save_table=true,mods=true,health=true,index=true}
    function c.has(name) return capabilities[name]==true end
    function c.title() end
    function c.log(fmt,...) s.logs[#s.logs+1]=string.format(fmt,...) end
    local option_specs={}
    local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function clean(spec,v)
        if spec.type=='toggle' then return v==true end
        if spec.type=='choice' then v=math.floor(tonumber(v) or 1);return v>=1 and v<=#spec.choices and v or 1 end
        if spec.type=='slider' then
            v=tonumber(v) or spec.default or spec.min;if v~=v then v=spec.min end
            v=math.max(spec.min,math.min(spec.max,v))
            if spec.step and spec.step>0 then v=spec.min+math.floor((v-spec.min)/spec.step+.5)*spec.step end
            return math.max(spec.min,math.min(spec.max,v))
        end
        return v
    end
    function c.option(id,spec)
        assert(type(id)=='string' and id:match('^[%w_%.%-]+$'),'Invalid Chef option id')
        assert(type(spec)=='table' and (spec.type=='toggle' or spec.type=='choice' or spec.type=='slider'),'Invalid Chef row')
        if spec.type=='choice' then assert(type(spec.choices)=='table' and #spec.choices>=2 and #spec.choices<=32,'Chef choice count') end
        if spec.type=='slider' then
            assert(finite(spec.min) and finite(spec.max) and spec.min<spec.max,'Chef slider range')
            assert(spec.step==nil or finite(spec.step) and spec.step>=0,'Chef slider step')
        end
        if option_specs[id] then return s.values[id] end
        option_specs[id]=spec;s.values[id]=clean(spec,spec.default);return s.values[id]
    end
    function c.set(id,v)
        if not option_specs[id] then return nil end
        v=clean(option_specs[id],v)
        if s.values[id]~=v then s.values[id]=v;if s.changes[id] then s.changes[id](v) end end
        return v
    end
    function c.on_change(id,fn) s.changes[id]=fn end
    function c.on(event,fn) s.events[event]=fn;return function() s.events[event]=nil end end
    function c.share(key,v) shared[key]=v;return true end
    function c.shared(key) return shared[key] end
    function c.world() return s.world end
    function c.world_id() return s.generation end
    function c.time() return 0 end -- deliberately frozen, even while wall time advances
    local engine={
        ['Application.time_since_launch']=function() return s.now end,
        ['Application.main_world']=function() return s.world end,
        ['Window.has_focus']=function() return s.focused end,
        ['Network.game_session']=function() return s.session end,
        ['GameSession.peers']=function(session) assert(session==s.session);return s.peers end,
        ['Application.set_time_step_policy']=function(key,value)
            assert(key=='external_multiplier');s.writes[#s.writes+1]=value
            if s.refuse and value==1 then return false end
            s.rate=value
        end,
        ['Mouse.axis_index']=function(name) assert(name=='mouse');return 0 end,
        ['Mouse.axis']=function(index) assert(index==0);return{s.dx or 0,s.dy or 0,0} end,
        ['Vector3.to_elements']=function(v) return unpack(v) end,
    }
    function c.call(name,...)
        s.counts[name]=(s.counts[name] or 0)+1
        if s.skip==name then return nil,'skipped' end
        if s.throw==name then error('call threw: '..name) end
        assert(engine[name],'Unapproved engine call: '..name)
        local a,b,c,d=engine[name](...)
        return a,b,c,d -- Chef's guarded ABI always pads its answers.
    end
    local bindings={}
    function bindings.register_binding(id,label,slot,options)
        s.specs[id]=options.default;return true
    end
    function bindings.is_down(id) return not s.menu and s.keys[id]==true end
    local sandbox=assert(loadstring(SANDBOX_SOURCE))().install({G=_G,io={},os={getenv=function() end},debug=debug,
        DIR='C:\\fixture\\',GAME_DIR='C:\\game\\',log=function() end})
    local env=sandbox.env(c.name)
    env.ModBindingsMenu=bindings -- the loader installs this shim per addon
    local chunk=assert(loadstring(CHEF_SOURCE));setfenv(chunk,env)
    local addon=chunk(c)
    return s,c,env.package.loaded,addon,shared,bindings,env
end

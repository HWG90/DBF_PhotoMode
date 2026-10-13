-- Data-only hover control override. No FFI, executable writes, or native hooks.
-- Backend contract (all functions may throw; unavailable reads must not say expired):
-- snapshot([expected]) returns {identity=<stable scalar>,generation=<lifetime token>,
--   active=bool,hover=bool,value=<definition +9C>,epoch=<completed engine update>,
--   dt=<that update's dt>,control={x=number,y=number,z=number},action=number}.
-- Without expected, resolve the local equipped pack. With expected, resolve that
-- exact old pack even when unequipped. Only explicit {expired=true} proves it gone.
-- set(expected,0), restore(expected,original) must compare the exact live identity,
-- generation and expected.value again before writing, returning true on success.
-- input_supported() must return true only for a currently verified input path;
-- connected/unknown controller routes bypassing keyboard capture must refuse.
-- A backend must reject unsupported game builds and shared definition fallbacks.
--
-- Static target: PE timestamp 6AB3B43F, image size 4744000. Jumppack manager is
-- [game+3326BB8]; entity->definition map +60, count +98, array pointer +A0,
-- stride118. The override is float +9C, never mode byte +99 or flight flag0.
-- Native control is rebuilt into manager+40 (12 bytes/row). Exact zero X/Y/Z at
-- 9B4E07..4E1F skips divisions 9B50FA/5127/512C to 9B5299. The backend must verify
-- those instructions against the approved dump; timestamp alone is insufficient.
-- +9C=0 selects jump action F00000002; controller release must keep this action
-- and movement neutral. Normal throttle-off effects still run: this is not a
-- complete flight-state freeze. Engine update epochs must not be Lua/UI ticks.
local M={}
local function finite(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function token(v)return type(v)=='string'or finite(v)end
local function same(a,b)return a.identity==b.identity and a.generation==b.generation end
local function neutral(s)
    local c=s.control
    return type(c)=='table'and c.x==0 and c.y==0 and c.z==0 and s.action==0
end
function M.new(backend)
    local self={pending=false};local phase='idle';local owned
    local function clear()owned=nil;phase='idle';self.pending=false end
    local function read(expected)
        if type(backend)~='table'or type(backend.snapshot)~='function'then return nil,'Hover pause backend unavailable'end
        local ok,s,why=pcall(backend.snapshot,expected)
        if not ok then return nil,tostring(s)end
        if type(s)~='table'then return nil,why or'Hover pack snapshot unavailable'end
        if s.expired==true then
            if expected then return s end
            return nil,'Current hover pack snapshot expired'
        end
        if not finite(s.epoch)or not finite(s.dt)then return nil,'Completed engine update unavailable'end
        if type(s.active)~='boolean'or type(s.hover)~='boolean'then return nil,'Hover pack activity unavailable'end
        if expected and not same(s,expected)then return nil,'Owned hover pack identity unresolved'end
        if expected and type(s.value)~='number'then return nil,'Owned hover definition read unavailable'end
        return s
    end
    local function input_supported()
        if type(backend.input_supported)~='function'then return false,'Hover pause input suppression unavailable'end
        local ok,supported,why=pcall(backend.input_supported)
        if not ok then return false,tostring(supported)end
        if supported~=true then return false,why or'Hover pause input route is unsupported'end
        return true
    end
    local function write(name,s,value)
        if type(backend[name])~='function'then return false,'Hover pause '..name..' unavailable'end
        local ok,result,why=pcall(backend[name],s,value)
        if not ok then return false,tostring(result)end
        if result~=true then return false,why or('Hover pause '..name..' failed')end
        return true
    end
    function self.release()
        if not owned then clear();return true end
        if phase~='releasing'then
            phase='releasing';self.pending=true
            local s=read(owned.expected)
            if s and s.expired then clear();return true end
            if s and s.value~=0 then clear();return true end -- Another writer owns it.
            owned.release_epoch=s and s.epoch or owned.last_epoch
        end
        return true
    end
    local function fail(why)
        self.release()
        return false,why
    end
    function self.prepare()
        if phase=='armed'then return self.hold()end
        if phase=='releasing'then return false,'Hover override is waiting for a resumed engine update'end
        if owned then return true end
        local s,why=read();if not s then return false,why end
        if not(s.active and s.hover)then phase='preparing';return true end
        local supported,reason=input_supported();if not supported then return false,reason end
        if not token(s.identity)or not token(s.generation)or not finite(s.value)then return false,'Owned hover definition unavailable'end
        -- Retain cleanup information before a write, including uncertain failures.
        owned={expected=s,original=s.value,
            changed=s.value~=0,applied_epoch=s.epoch,last_epoch=s.epoch}
        phase='preparing'
        if owned.changed then
            local ok,reason=write('set',s,0);if not ok then return fail(reason)end
        end
        local current,reason=read(owned.expected)
        if not current then return fail(reason)end
        if current.expired then clear();return false,'Hover pack expired during preparation'end
        if current.value~=0 then return fail('Hover override readback failed')end
        owned.last_epoch=current.epoch
        return true
    end
    function self.ready()
        if phase~='preparing'and phase~='armed'then return false,'Hover pause has not been prepared'end
        local s,why=read();if not s then return false,why end
        if not owned then
            if s.active and s.hover then return false,'Active hover pack appeared; prepare it before pause'end
            return true
        end
        if not same(s,owned.expected)then return fail('Local hover pack ownership changed')end
        if s.value~=0 then return fail('Hover override ownership lost')end
        local supported,reason=input_supported();if not supported then return fail(reason)end
        owned.last_epoch=s.epoch
        if s.epoch>owned.applied_epoch and s.dt>0 then owned.qualified=true end
        if not owned.qualified then return false,'Waiting for a positive engine update after hover neutralization'end
        if not neutral(s)then return false,'Hover jump or movement control is not neutral'end
        return true
    end
    function self.acquire()
        local ok,why=self.ready();if not ok then return false,why end
        phase='armed';return true
    end
    function self.hold()
        if phase~='armed'then return false,'Hover pause is not acquired'end
        local ok,why=self.ready()
        if not ok then self.release();return false,why end
        return true
    end
    function self.after_update()
        if phase~='releasing'then return true end
        local s,why=read(owned.expected);if not s then return false,why end
        if s.expired then clear();return true end
        if s.value~=0 then clear();return true end
        owned.last_epoch=s.epoch
        if s.epoch<=owned.release_epoch or s.dt<=0 then return false,'Waiting for a positive engine update before hover restore'end
        if not owned.changed then clear();return true end
        local ok,reason=write('restore',s,owned.original);if not ok then return false,reason end
        local current,problem=read(owned.expected);if not current then return false,problem end
        if current.expired or current.value==owned.original then clear();return true end
        if current.value~=0 then clear();return false,'Hover definition changed during restore'end
        return false,'Hover definition restore readback failed'
    end
    function self.status()
        return {phase=phase,pending=self.pending,owned=owned~=nil,identity=owned and owned.expected.identity,
            generation=owned and owned.expected.generation,original=owned and owned.original}
    end
    self.state=self.status
    return self
end
return M

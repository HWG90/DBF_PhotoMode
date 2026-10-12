-- Supported shipping engine: read policy state, mutate only through its Lua setter.
-- No code patches, process suspension, or world-pose substitution.
local M={}
function M.new(sr)
    local ffi=require('ffi')
    pcall(ffi.cdef,[[
        void *FCP_GetModuleHandleA(const char *) __asm__("GetModuleHandleA");
        void *FCP_GetCurrentProcess(void) __asm__("GetCurrentProcess");
        int FCP_ReadProcessMemory(void *,const void *,void *,size_t,size_t *) __asm__("ReadProcessMemory");
        unsigned long FCP_GetTickCount(void) __asm__("GetTickCount");
    ]])
    local kernel=ffi.load('kernel32')
    local base=tonumber(ffi.cast('uintptr_t',kernel.FCP_GetModuleHandleA(nil)))
    local process=kernel.FCP_GetCurrentProcess()
    local buffer=ffi.new('uint8_t[64]');local got=ffi.new('size_t[1]')
    local function read(address,size)
        assert(address>=65536 and address<2^47 and size<=64,'Invalid policy read')
        assert(kernel.FCP_ReadProcessMemory(process,ffi.cast('void *',address),buffer,size,got)~=0 and tonumber(got[0])==size,'Engine policy unreadable')
        return ffi.string(buffer,size)
    end
    local function pointer(address)
        local value=ffi.new('uint64_t[1]');ffi.copy(value,read(address,8),8)
        local p=tonumber(value[0]);assert(p>=65536 and p<2^47 and p%8==0,'Engine policy owner invalid');return p
    end
    local function owner()
        assert(require('jit.util').funcinfo(sr.Application.set_time_step_policy).addr==base+0x3fc630,'Unsupported time-step binding')
        assert(read(base+0x3fc630,8)=='\x48\x8b\xd1\xe9\xd8\xfb\xff\xff','Time-step binding guard changed')
        assert(read(base+0x3fc21e,7)=='\x4c\x8b\x35\x83\x5f\xf6\x01','Policy owner guard changed')
        assert(read(base+0x3fc4d8,9)=='\xf3\x41\x0f\x11\x8e\x94\x04\x00\x00','Multiplier setter guard changed')
        return pointer(base+0x23621a8)
    end
    local function get(expected)
        local app=owner();if expected then assert(app==expected,'Engine policy owner changed')end
        local value=ffi.new('float[1]');ffi.copy(value,read(app+0x494,4),4)
        local n=tonumber(value[0]);assert(n==n and n>=0 and n<=16,'Invalid simulation multiplier');return n,app
    end
    return {
        snapshot=function()local value,app=get();return {value=value,owner=app}end,
        value=function(s)return get(s.owner)end,
        set=function(s,value)
            value=tonumber(ffi.new('float[1]',value)[0])
            get(s.owner)
            local function set_multiplier()sr.Application.set_time_step_policy('external_multiplier',value)end
            if value~=s.value then
                local api=rawget(_G,'DBFMCM')or rawget(_G,'DBF_PHOTO_STANDALONE_API');local camera=api and api.camera_input
                assert(camera and camera.pause,'Native solo pause gate unavailable')
                local ok,why=camera.pause(set_multiplier);assert(ok,why)
            else set_multiplier()end
            assert(get(s.owner)==value,'Simulation multiplier readback mismatch')
        end,
        now=function()return tonumber(kernel.FCP_GetTickCount())/1000 end,
    }
end
return M

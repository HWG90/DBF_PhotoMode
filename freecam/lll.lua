-- Photo owns its global callbacks; activate once per process, never hot-reload.
local started,reported,failed=false,false,false;local standalone,camera_api,camera_owner
local function start()
        if started or failed then return end
        if rawget(_G,'DBF_PHOTO_MODE_OWNER')or rawget(_G,'DBF_PHOTO_MODE_STARTED')or rawget(_G,'DBF_PHOTO_SAFE_EFFECTS')or rawget(_G,'DBF_PHOTO_CAMERA_RUNTIME')then
            failed=true;mod.log('Another Photo Mode provider is already active; choose one package and restart.');return
        end
        camera_owner=camera_owner or mod.require('src/camera_ownership.lua').new(_G,mod.log)
        local ready,reason=camera_owner.refresh()
        if not ready then if not reported then mod.log(reason);reported=true end;return end
        rawset(_G,'DBF_PHOTO_CAMERA_OWNERSHIP',camera_owner)
        local mcm=rawget(_G,'DBFMCM')
        if mcm then
            if not mcm.camera_input or not mcm.camera_input.set_focus or not mcm.create_photo_view then
                if not reported then mod.log('Update MCM for shared photo input; standalone mode is available when MCM is disabled');reported=true end
                pcall(camera_owner.dispose);camera_owner=nil
                return
            end
            camera_api=mod.require('src/standalone.lua').shared(mod,assert(rawget(_G,'stingray')),mcm)
            rawset(_G,'DBF_PHOTO_CAMERA_API',camera_api)
        else
            local created,value=pcall(function()return mod.require('src/standalone.lua').new(mod,assert(rawget(_G,'stingray')))end)
            if not created then failed=true;pcall(camera_owner.dispose);mod.log('Photo Mode startup failed; restart before retrying: '..tostring(value));return end
            standalone=value
            rawset(_G,'DBF_PHOTO_STANDALONE_API',standalone)
        end
        local source=assert(mod.read('src/camera_runtime.lua'))
        rawset(_G,'DBF_PHOTO_PACKAGE_ROOT',mod.dir)
        local chunk=assert(loadstring(source,'@'..mod.dir..'/src/camera_runtime.lua'))
        setfenv(chunk,_G)
        local ok,why=pcall(chunk)
        if not ok then failed=true;pcall(camera_owner.dispose);mod.log('Photo Mode startup failed; restart before retrying: '..tostring(why));return end
        started=true
        mod.log('War Journalist installed; P toggles by default; Tab switches camera/menu focus')
end
return {live_lua_api=1,name='War Journalist',
    on_enable=function()mod.log('War Journalist ready; MCM is optional')end,
    on_update=start,
    on_disable=function()
        if started then return false,'Photo render hooks require a normal restart' end
        return true
    end,
}

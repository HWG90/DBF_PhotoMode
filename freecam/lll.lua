-- ActionCam owns global camera hooks; activate once per process, never hot-reload.
local started,reported=false,false;local standalone,camera_api
local function start()
        if started then return end
        if package.loaded['mods/actioncam/actioncam'] then
            if not reported then mod.log('Original ActionCam is already loaded; restart the game to activate Freecam');reported=true end
            return
        end
        local mcm=rawget(_G,'DBFMCM')
        if mcm then
            if not mcm.camera_input or not mcm.camera_input.set_focus or not mcm.create_photo_view then
                if not reported then mod.log('Update MCM for shared photo input; standalone mode is available when MCM is disabled');reported=true end
                return
            end
            camera_api=mod.require('src/standalone.lua').shared(mod,assert(rawget(_G,'stingray')),mcm)
            rawset(_G,'DBF_PHOTO_CAMERA_API',camera_api)
        else
            standalone=mod.require('src/standalone.lua').new(mod,assert(rawget(_G,'stingray')))
            rawset(_G,'DBF_PHOTO_STANDALONE_API',standalone)
        end
        local source=assert(mod.read('src/actioncam.lua'))
        rawset(_G,'DBF_PHOTO_PACKAGE_ROOT',mod.dir)
        local chunk=assert(loadstring(source,'@'..mod.dir..'/src/actioncam.lua'))
        setfenv(chunk,_G)
        started=true;chunk()
        mod.log('War Journalist installed; P toggles by default; Tab switches camera/menu focus')
end
return {live_lua_api=1,name='War Journalist',
    on_enable=function()mod.log('War Journalist ready; MCM is optional')end,
    on_update=start,
    on_disable=function()
        if started then return false,'ActionCam render hooks require a normal restart' end
        return true
    end,
}

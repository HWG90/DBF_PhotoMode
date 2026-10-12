local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local module=dofile(root..'controller.lua')
local active,focus,menu,held=false,true,false,false
local sample={wheel=0};local values;local spec
local provider={down=function(k)return k==80 and held end,focused=function()return focus end,
    acquire=function()if menu or not focus then return nil,'busy' end;active=true;return {} end,
    release=function()active=false;return true end,sample=function()return active and focus and not menu and sample or nil end}
DBFMCM={camera_input=provider,is_open=function()return menu end,close=function()menu=false;return true end,
    register=function(def)
        spec=def;values={};for _,c in ipairs(def.pages[1].controls)do values[c.id]=c.default end
        return {get=function(k)return values[k]end,set=function(k,v)values[k]=v;return true end,unregister=function()end}
    end}
local photo={active=false,input={}};local cfg={};local valid=true
local c=module.new(photo,cfg,function()return valid end,function()end)
c.tick(0.016);held=true;c.tick(0.016);assert(photo.active and active)
sample={wheel=120,forward=true};c.tick(0.016);assert(values.speed==3.6 and photo.input.forward and cfg.PHOTO_SPEED==3.6)
sample.wheel=120000;c.tick(0.016);assert(values.speed==50)
sample.wheel=-120000;c.tick(0.016);assert(values.speed==0.1)
sample.escape=true;c.tick(0.016);assert(not photo.active and not active)
held=false;c.tick(0.016);held=true;sample={wheel=0};c.tick(0.016);assert(active)
focus=false;c.tick(0.016);assert(photo.active and not active)
focus=true;c.tick(0.016);assert(photo.active and active);assert(c.stop())
focus=true;held=false;c.tick(0.016);held=true;c.tick(0.016);assert(active)
valid=false;c.tick(0.016);assert(not active)
valid=true;menu=true;spec.pages[1].controls[5].on_activate();assert(active and not menu)
DBFMCM=nil;c.tick(0.016);assert(not active and not photo.active)
assert(c.close())
-- Register against the real MCM schema and exercise its authoritative handle.
local core=dofile('src/core.lua')
DBFMCM=core.new(nil,function()end)
DBFMCM.camera_input=provider;DBFMCM.is_open=function()return menu end;DBFMCM.close=function()menu=false;return true end
held=false;focus=true;menu=false;valid=true;sample={wheel=0}
local real=module.new(photo,cfg,function()return valid end,function()end)
real.tick(0.016)
local h=assert(DBFMCM.mods.dbf_freecam).handle
assert(h.get('toggle_key')==80);assert(h.get('up_key')==16);assert(h.get('slowmo_key')==220);assert(h.set('forward_key',73));
assert(h.activate('toggle'));assert(active)
sample.wheel=120;real.tick(0.016);assert(math.abs(h.get('speed')-3.6)<1e-6)
assert(h.set('enabled',false));assert(not active and not photo.active)
assert(real.close());assert(not DBFMCM.mods.dbf_freecam)
local attempts=0;provider.pause_allowed=function()return false end
local freeze={start=function()attempts=attempts+1;return true end,hold=function()return true end,release=function()return true end}
local multiplayer=module.new(photo,cfg,function()return true end,function()end,freeze)
held=false;multiplayer.tick(0.016);held=true;multiplayer.tick(0.016)
assert(photo.active and active and attempts==0);assert(multiplayer.close())
-- Defaults never migrate or overwrite the user's saved activation/movement keys.
local persisted={toggle_key=78,forward_key=73,slowmo_key=84}
DBFMCM=core.new({load=function(id)return id=='dbf_freecam'and persisted or {}end,save=function()error('Registration must not write saved settings')end},function()end)
DBFMCM.camera_input=provider;DBFMCM.is_open=function()return false end;held=false
local retained=module.new({}, {},function()return true end,function()end);retained.tick(.016)
local saved_mod=DBFMCM.mods.dbf_freecam;assert(saved_mod.controls.slowmo_key.default==220)
assert(saved_mod.handle.get('toggle_key')==78 and saved_mod.handle.get('forward_key')==73 and saved_mod.handle.get('slowmo_key')==84)
assert(retained.close())
print('Freecam: key edges, wheel bounds, Escape/scene exit and focus retention, MCM button and provider replacement passed')

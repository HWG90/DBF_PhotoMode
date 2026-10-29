-- HD2-Addon: mods/goose/war_journalist
-- HD2-Requires: chef-shared-loader >= 1.2.3
-- Development entry; the build embeds its own modules into package.preload.
local chef = ...
local composition=require('wj.composition')
composition.logo_art={[2]=require('wj.assets.crest')}
return require('wj.chef.runtime').new(chef, {
    camera = require('wj.chef.camera'),
    portable_camera = require('wj.steam_camera'),
    composition = composition,
    controls = require('wj.chef.controls'), bindings = rawget(_G, 'ModBindingsMenu'),
    motion = require('wj.chef.motion'), simulation = require('wj.chef.simulation'),
    shots=require('wj.chef.shots'), path=require('wj.steam_path'), bloom=require('wj.chef.bloom'),
    lights=require('wj.chef.lights'),
    crest_fallback=require('wj.assets.crest_fallback'),
    logos=require('wj.assets.logos'),light_setups=require('wj.chef.light_setups'),
    light_drag=require('wj.chef.light_drag'),
    light_memory=require('wj.chef.light_memory'),
    subject=require('wj.chef.subject'),load_subject=function()
        return {native=require('wj.steam_subject_native'),model=require('wj.steam_subject'),bank=require('wj.assets.poses')}
    end,
})

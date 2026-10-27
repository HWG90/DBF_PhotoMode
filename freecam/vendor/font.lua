-- Read the already loaded HUD font; exact-build gates precede descriptor reads.
-- Layout provenance: Epic LUT src/platform/ui_font.lua and Pick-your-bots
-- Test36 Source/replace_automatons.lua:7061-7089. No scan or memory writes.
local F={}
local HIGH=4294967296
local function u32(bytes,offset)
    offset=offset or 0
    if type(bytes)~='string' or #bytes<offset+4 then return nil end
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    return a+b*256+c*65536+d*16777216
end
local function hash(bytes)
    if type(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if lo==0 and hi==0 then return nil end
    return string.format('%08x%08x',hi,lo)
end
local function pointer(bytes)
    if type(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if hi>=0x8000 then return nil end
    local address=hi*HIGH+lo
    if address<0x10000 or address>0x800000000000-32 then return nil end
    return address
end
-- No game binaries or font payloads are distributed by this module. The
-- font header's atlas name can differ from the texture actually loaded by
-- the HUD; admit only complete font/texture/material triples in this process.
local core_sans={
 -- Historical HUD globals, PE 6ab3b43f, recovered from the existing crash
 -- dump with that build's documented layout. Both resources remain in the
 -- current Latin package. Current can_get checks below are still mandatory.
 -- a21d... is byte-identical to the former Core Sans bitmap material except
 -- its default texture. c38a... uses the runtime-font shader and produced
 -- visibly broken glyphs with this bitmap atlas in portable.6.
 {font='b56d2abac5d17df2',atlas='d1ebb991c79f934b',material='a21d59a5cbcbb5c4'},
 -- packages/localization/latin; use the current game's runtime material.
 {font='28a718e0d452eff0',atlas='c2cffd6538624e20',material='c38a65a21fb3e8d0'},
 {font='5e83c5f2a9b02110',atlas='82df61208dee5f66',material='c38a65a21fb3e8d0'},
 {font='b56d2abac5d17df2',atlas='98b1ea89de621b24',material='c38a65a21fb3e8d0'},
 {font='e01b1c60bb279a7c',atlas='039ab81e76d9bf05',material='c38a65a21fb3e8d0'},
 {font='fbb35bee675f2295',atlas='29b689d1fb1cfad9',material='c38a65a21fb3e8d0'},
 {font='e007454455e2d2bb',atlas='1b0106d1d0ff112f',material='47c50c5fab67ccab'},
 {font='fca7631255290a2c',atlas='a324ffafb376edef',material='47c50c5fab67ccab'},
}
function F.new(memory,game,at,engine_resources,log)
    local function ensure_memory()
        if memory then return end
        local path=mod.require('src/host_native.lua').library('hd2_nativeinfo_f6d3465944c1aea1.dll')
        local entry=assert(package.loadlib(path,'luaopen_hd2_nativeinfo'))
        local native=assert(entry())
        game=assert(native.module_base('game.dll'))
        memory={read=native.read_memory,address=function(value)return value end}
    end

    local self={}
    local resolved,attempted
    function self.invalidate()resolved,attempted=nil,nil end
    function self.resolve(sr)
        if engine_resources then
            if attempted then return resolved end
            attempted=true
            if not(sr and sr.Application and type(sr.Application.can_get)=='function'and sr.IdString64 and type(sr.IdString64.from_hex)=='function')then return nil end
            -- These are runtime_font resources in the verified Latin package,
            -- distinct from the bitmap font/texture pairs below. Inventory only:
            -- do not hand an unqualified font type to native Gui.text.
            if log then
                for _,face in ipairs({'4f5bf47ac9acbc20','6cf40a417d2f6803','d2146b428bd7397a'})do
                    local ok,present=pcall(sr.Application.can_get,'runtime_font',sr.IdString64.from_hex(face))
                    log('Game runtime font '..face..': loaded='..tostring(ok and present==true))
                end
            end
            for _,descriptor in ipairs(core_sans)do
                local ok,loaded=pcall(function()
                    local id=sr.IdString64.from_hex
                    local face=sr.Application.can_get('font',id(descriptor.font))
                    local atlas=sr.Application.can_get('texture',id(descriptor.atlas))
                    local material=sr.Application.can_get('material',id(descriptor.material))
                    if log then log('Game font resources '..descriptor.font..': font='..tostring(face)..' atlas='..tostring(atlas)..' material='..tostring(material))end
                    return face and atlas and material
                end)
                if ok and loaded then resolved={font=descriptor.font,atlas=descriptor.atlas,material=descriptor.material};return resolved end
            end
            return nil
        end
        local ready=pcall(ensure_memory);if not ready then return nil end

        if not memory or type(memory.read)~='function' or type(memory.address)~='function' then return nil end
        if not sr or not sr.IdString64 or type(sr.IdString64.from_hex)~='function'
            or not sr.Application or type(sr.Application.can_get)~='function' then return nil end
        local ok,descriptor=pcall(function()
            -- Bingus memory.address converts pointers, never module names.
            -- Keep names separate so a Lua string's buffer cannot become the
            -- PE base (and silently leave the UI on the debug fallback).
            local module=game
            if type(module)=='string' then
                if type(memory.module)~='function' then return nil end
                module=memory.module(module)
                if module==nil then return nil end
            end
            local base=memory.address(module)
            if type(base)~='number' or base<0x10000 or base>=0x800000000000 or base~=math.floor(base) then return nil end
            local function read_address(address,count) return memory.read(at and at(address) or address,count) end
            local function read(offset,count) return read_address(base+offset,count) end
            local pe=u32(read(0x3c,4))
            if not pe or pe<0x40 or pe>0x1000 or u32(read(pe,4))~=0x4550
                or u32(read(pe+8,4))~=0x6AD7C05D
                or u32(read(pe+80,4))~=0x3382000
                or u32(read(pe+88,4))~=0x2ED14F0 then return nil end
            local font,atlas=hash(read(0x312D998,8)),hash(read(0x312E618,8))
            local owner=pointer(read(0x3180C08,8))
            local material=owner and hash(read_address(owner+24,8))
            if not font or not atlas or not material then return nil end
            local I,app=sr.IdString64,sr.Application
            if not app.can_get('font',I.from_hex(font))
                or not app.can_get('texture',I.from_hex(atlas))
                or not app.can_get('material',I.from_hex(material)) then return nil end
            return {font=font,material=material,atlas=atlas}
        end)
        if ok then return descriptor end
        return nil
    end
    return self
end
return F

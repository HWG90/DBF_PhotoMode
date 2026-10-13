-- Real photo compositor, with recorded native draw/material calls. The native
-- shaders still need visual acceptance; this checks their actual Lua contract.
local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local factory=dofile(root..'photo_runtime.lua');local catalog=dofile(root..'composition.lua')
local defaults=dofile(root..'photo_options.lua').defaults
local clock=100;local provider={now=function()return clock end};DBFMCM={camera_input=provider}
local vectors,bitmaps={},{};local layouts,created,destroyed,freed=0,0,0,0
local sr={Vector2=function(...)return {...}end,Vector3=function(...)return {...}end,Vector4=function(...)return {...}end,Color=function(...)return {...}end,
 Application={can_get=function()return true end,worlds=function()return {3}end},
 World={create_screen_gui=function()created=created+1;return created end,destroy_gui=function()freed=freed+1 end},
 Gui={resolution=function()return 1920,1080 end,material=function(_,name)return {name=name}end,
  bitmap=function(_,name,pos,size,color)bitmaps[#bitmaps+1]={name=name,pos=pos,size=size,color=color};return #bitmaps end,
  destroy_bitmap=function()destroyed=destroyed+1 end},
 Material={set_scalar=function()end,set_vector4=function(_,key,value)vectors[key]=value end}}
local composition={shaders=catalog.shaders,shader_colors=catalog.shader_colors,
 layout=function(...)layouts=layouts+1;return catalog.layout(...)end}
local runtime=factory.new(sr,{new=function()return {apply=function()return .9 end,release=function()return true end}end},composition,
 {new=function()return {parameters={},apply=function()return false,'test' end,release=function()return true end}end},function()end)
local o={};for key,value in pairs(defaults)do o[key]=value end
o.shader_opacity=40
local function index(name)for i,value in ipairs(catalog.shaders)do if name==value then return i end end;error(name)end
local function apply(dt)return runtime.apply(1,2,3,{0,1,0},{1,0,0},o,dt)end
local function near(a,b)assert(math.abs(a-b)<1e-7,tostring(a)..' ~= '..tostring(b))end
for _,name in ipairs({'oxidized_copper','stipple_gradient','hammered_metal'})do
 o.shader=index(name);apply(0)
 local draw=bitmaps[#bitmaps];assert(draw.name=='mods/dbf_hud/materials/mapped_'..name)
 assert(draw.color[1]==102 and draw.color[2]<200 and draw.color[3]<200 and draw.color[4]<200,'A colored material must not receive a white scene backing')
 if name=='oxidized_copper'then assert(draw.color[2]>draw.color[3]and draw.color[3]>draw.color[4],'Copper carrier must have its copper hue')end
 assert(draw.size[1]==1920 and draw.size[2]==1080 and vectors.atlas_scissor[4]==1,'Full-screen carrier and animation default changed')
end
local before=vectors.scissor_rect[4];local count,layout_count=#bitmaps,layouts
clock=clock+.05;apply(0);near(vectors.scissor_rect[4],before+.05)
assert(#bitmaps==count and layouts==layout_count,'Menu animation rebuilt geometry instead of updating the material')
o.roll=25;o.fov=65;clock=clock+.05;apply(0)
assert(#bitmaps==count and layouts==layout_count,'Camera lens changes rebuilt overlay/logo geometry')
o.shader_animate=false;clock=clock+.05;apply(0);assert(vectors.atlas_scissor[4]==0 and #bitmaps==count)
o.shader_animate=nil;apply(0);assert(vectors.atlas_scissor[4]==1)
for _,scale in ipairs({.005,1,16})do
 o.shader_scale=scale;apply(0);near(vectors.scissor_rect[1],4/scale);near(vectors.atlas_scissor[2],4/scale)
 assert(vectors.clip_box[3]==1 and vectors.clip_box[1]==0 and vectors.clip_box[2]==0,'Pattern scale changed the homogeneous UV denominator')
end
-- Clock resets/provider swaps cannot introduce a backwards jump or a huge one.
before=vectors.scissor_rect[4];clock=1;apply(0);near(vectors.scissor_rect[4],before)
provider.now=function()return 9000 end;apply(0);near(vectors.scissor_rect[4],before)
provider.now=function()return 0/0 end;apply(.016);near(vectors.scissor_rect[4],before+.016)
DBFMCM=nil;DBF_PHOTO_STANDALONE_API={camera_input={now=function()return clock end}}
apply(0);before=vectors.scissor_rect[4];clock=clock+.03;apply(0);near(vectors.scissor_rect[4],before+.03)
assert(runtime.release()and destroyed==#bitmaps-1 and freed==created);DBF_PHOTO_STANDALONE_API=nil
print('Photo shader runtime: colored carriers, default animation during paused/menu input, retained geometry, fine scales, clock recovery and standalone passed')

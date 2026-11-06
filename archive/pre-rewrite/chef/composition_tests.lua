local s,c,mods,addon=chef_fixture()
local composition=mods['wj.composition']
local static,grain=composition.layout_static,composition.layout_grain
local layouts,grains,rects,triangles=0,0,0,0
local w,h=1920,1080
composition.layout_static=function(...) layouts=layouts+1;return static(...) end
composition.layout_grain=function(...) grains=grains+1;return grain(...) end
function c.screen() return w,h end
function c.color(r,g,b,a)
    for _,v in ipairs({r,g,b,a}) do assert(type(v)=='number' and v>=0 and v<=255) end
    return {r,g,b,a}
end
function c.rect(x,y,rw,rh,color,layer)
    assert(x>=0 and y>=0 and rw>0 and rh>0 and x+rw<=w+.001 and y+rh<=h+.001)
    assert(layer>=c.TOP+100 and layer<=c.TOP+102);rects=rects+1
end
function c.triangle(x1,y1,x2,y2,x3,y3,color,layer)
    for _,x in ipairs({x1,x2,x3}) do assert(x>=0 and x<=w) end
    for _,y in ipairs({y1,y2,y3}) do assert(y>=0 and y<=h) end
    assert(layer==c.TOP+102);triangles=triangles+1
end
c.set('logo',2);c.set('overlay',true);addon.render()
assert(triangles==451 and rects==0 and layouts==1 and grains==0)
for _=1,100 do addon.render() end
assert(layouts==1 and next(s.counts)==nil,'Static overlays never read clocks or rebuild geometry')
c.set('logo_tint',3);c.set('logo_size',200);c.set('logo_x',100);c.set('logo_y',0)
addon.render();assert(layouts==2)
c.set('frame',5);c.set('filter',19);c.set('grid',4);c.set('grain',25);c.set('vignette',30)
addon.render();assert(grains==1 and layouts==3)
local previous=rects;addon.render();assert(grains==1 and layouts==3 and rects>previous)
s.now=s.now+1/12+.001;addon.render();assert(grains==2 and layouts==3 and c.time()==0)
local before=triangles;c.set('clean_view',true);addon.render();assert(triangles==before)
w,h=1280,720;addon.render();assert(layouts==5)
c.set('grain',0);addon.render();local clocks=s.counts['Application.time_since_launch']
for _=1,100 do addon.render() end
assert(s.counts['Application.time_since_launch']==clocks,'Disabled grain never polls a clock')
c.set('grain',30);s.skip='Application.time_since_launch';addon.render()
clocks=s.counts['Application.time_since_launch'];local logs=#s.logs
for _=1,100 do addon.render() end
assert(clocks==s.counts['Application.time_since_launch'] and logs==#s.logs,'A bad grain clock disables repeated failures')
c.set('overlay',false);assert(addon.render==nil and addon.update==nil)
assert(addon.shutdown())
-- Chef signals its costly scanline fallback with false. Probe only one
-- triangle; the next frame uses <=256 pre-baked rectangles with no raster work.
local fs,fc,fm,fa=chef_fixture()
local probes,draws=0,0
function fc.screen() return 1920,1080 end
function fc.color(...) return {...} end
function fc.triangle() probes=probes+1;return false end
function fc.rect() draws=draws+1 end
fc.set('logo',2);fc.set('overlay',true);fa.render();assert(probes==1)
fa.render();assert(probes==1 and draws>0 and draws<=256)
local per_frame=draws
for _=1,100 do fa.render() end
assert(probes==1 and draws==per_frame*101 and next(fs.counts)==nil)
assert(fa.shutdown())
-- All catalogue logos are emitted as bounded geometry and support custom RGB.
local ls,lc,lm,la=chef_fixture();local logo_draws=0;local tint
function lc.screen() return 1920,1080 end
function lc.color(r,g,b,a) tint={r,g,b,a};return tint end
function lc.rect() logo_draws=logo_draws+1 end
lc.set('overlay',true);lc.set('logo_red',12);lc.set('logo_green',34);lc.set('logo_blue',56)
assert(ls.values.logo_tint==4)
for index=4,13 do
    logo_draws=0;lc.set('logo',index);la.render()
    assert(logo_draws>0 and logo_draws<=512 and tint[1]==12 and tint[2]==34 and tint[3]==56)
end
lc.set('logo_tint',1);assert(ls.values.logo_red==255 and ls.values.logo_green==255 and ls.values.logo_blue==255)
assert(la.shutdown())
print('chef composition: crest triangles, cached geometry, bounded grain, clean view and resize passed')

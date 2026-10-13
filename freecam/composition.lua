-- Resolution-independent overlay geometry. Credited logo meshes are embedded.
local M={}
M.shaders={'','crt_scan','crt_phosphor','bayer','ion_noise','sweep','checker_fine','checker_coarse','diagonal_weave','dot_matrix','glass_sheen','brushed_steel','hammered_metal','ceramic','thermal','warning_hatch','pulse','circuit','hex_cells','heat_shimmer','blueprint','carbon','ribbed_alloy','oxidized_copper','etched_scale','micro_mesh','triangular_grille','caution_dots','ceramic_cracks','iridescent','amber_glass','cobalt_glass','frosted','gunmetal','leather','hazard_red','rail_glints','energy_threads','grid_nodes','stipple_gradient','prismatic'}
M.shader_names={'None','CRT scanlines','RGB phosphor','Ordered dither','Ion interference','Scanner sweep','Fine checker dither','Coarse VGA checker','Diagonal weave','Dot matrix','Glass sheen','Brushed steel','Hammered metal','Ceramic enamel','Thermal glow','Warning hatch','Warning pulse','Circuit traces','Hex-like cell lattice','Heat shimmer tint','Blueprint cross grid','Carbon weave','Ribbed alloy','Oxidized copper','Etched calibration','Micro mesh','Triangular grille','Caution dot tape','Cracked ceramic','Iridescent coating','Amber instrument glass','Cobalt instrument glass','Frosted diffusion','Gunmetal stipple','Grip leather','Red emergency hatch','Rail glints','Energy threads','PCB nodes','Stipple shading','Prismatic facets'}
-- These mapped HUD materials modulate their carrier color. White produces a
-- pale backing across the scene rather than copper, steel or dark stippling.
-- They remain decorative overlays; they do not sample the scene's color.
M.shader_colors={oxidized_copper={188,110,66},hammered_metal={122,133,144},stipple_gradient={80,80,80}}
M.scene_names={'None','Negative','Monochrome','Posterize','Field-report duotone','Solarize','Inverted depth','Thermal depth','Depth contours','Depth fog'}
M.filter_names={'Original','Warm film','Cool film','Sepia tint','Emerald','Crimson','Democracy Gold','Frostbite','Martian Sundown','Midnight Operations','Alien Haze','Lavender Fog','Toxic Atmosphere','Emergency Broadcast','Deep Ocean','Bronze Archive','Desert Film','Cold Steel','Crimson and Gold','Solar Eclipse','Neon Frontier','Amber Horizon'}
M.filter_colors={[2]={235,158,82},[3]={73,145,227},[4]={180,126,70},[5]={55,150,85},[6]={180,50,60},[7]={246,202,92},[8]={147,219,244},[9]={232,112,77},[10]={49,80,118},[11]={142,210,113},[12]={175,132,204},[13]={141,186,51},[14]={206,71,54},[15]={26,117,133},[16]={204,141,83},[17]={223,190,140},[18]={145,174,188},[19]={220,70,78},[20]={110,78,169},[21]={83,191,225},[22]={245,161,78}}
function M.layout(w,h,o,seconds)
 local out={};local function rect(x,y,width,height,alpha,color)
  if width>0 and height>0 and alpha>0 then out[#out+1]={kind='rect',x=x,y=y,w=width,h=height,a=alpha,c=color or {0,0,0}}end
 end
 local ratios={false,2.39,16/9,1,4/5};local ratio=ratios[o.frame or 1];local x,y,fw,fh=0,0,w,h
 if ratio then if w/h>ratio then fw=h*ratio;x=(w-fw)/2 else fh=w/ratio;y=(h-fh)/2 end end
 rect(0,0,x,h,1);rect(x+fw,0,x,h,1);rect(x,0,fw,y,1);rect(x,y+fh,fw,y,1)
 local tint=M.filter_colors[o.filter]
 if tint then
  local intensity=(o.filter_strength or 0)/100*.22
  if (o.filter or 1)>=19 then
   local other=({[19]={246,202,92},[20]={41,66,98},[21]={212,79,160},[22]={94,132,196}})[o.filter]
   for band=0,23 do local t=band/23;local rgb={};for channel=1,3 do rgb[channel]=math.floor(tint[channel]*(1-t)+other[channel]*t+.5)end
    rect(x,y+fh*band/24,fw,fh/24,intensity,rgb)
   end
  else rect(x,y,fw,fh,intensity,tint)end
 end
 local vig=(o.vignette or 0)/100
 if vig>0 then for i=0,11 do local t=i/12;local a=vig*(1-t)^2*.12;local vx=fw*(o.vignette_width or 18)/1200;local vy=fh*(o.vignette_width or 18)/1200
  rect(x+i*vx,y, vx,fh,a);rect(x+fw-(i+1)*vx,y,vx,fh,a)
  rect(x,y+i*vy,fw,vy,a);rect(x,y+fh-(i+1)*vy,fw,vy,a)
 end end
 -- Deterministic sparse grain, independent of paused game time.
 local grain=(o.grain or 0)/100
 if grain>0 then local seed=math.floor((seconds or 0)*12)%4096;for i=1,96 do
  local gx=((i*739+seed*47)%997)/997;local gy=((i*397+seed*89)%991)/991
  local size=o.grain_size or 1.5;rect(x+gx*math.max(0,fw-size),y+gy*math.max(0,fh-size),math.min(size,fw),math.min(size,fh),grain*.22,i%2==0 and {255,255,255}or {0,0,0})
 end end
 if o.clean_view then return out end
 local white={255,255,255};local grid=o.grid or 1
 if grid==2 or grid==4 then local divisions=grid==2 and {1/3,2/3}or {.382,.618};for _,t in ipairs(divisions)do
  rect(x+fw*t,y,1,fh,.35,white);rect(x,y+fh*t,fw,1,.35,white)
 end elseif grid==3 then rect(x+fw/2-12,y+fh/2,24,1,.6,white);rect(x+fw/2,y+fh/2-12,1,24,.6,white)end
 if (o.logo or 1)>1 then
  local size=math.min(fw,fh)*.09*(o.logo_size or 100)/100
  size=math.min(size,fw*.45,fh*.45)
  local lx=x+size+(fw-2*size)*(o.logo_x or 90)/100
  local ly=y+size+(fh-2*size)*(o.logo_y or 8)/100
  local a=(o.logo_opacity or 85)/100;local hex=o.logo_color or '#FFFFFF';local c={tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)}
  local function mark(rx,ry,rw,rh)rect(lx+rx*size,ly+ry*size,rw*size,rh*size,a,c)end
  if M.logo_art and M.logo_art[o.logo]then
   local art=M.logo_art[o.logo];local factor=2*size/math.max(art.width,art.height);local ax=lx-art.width*factor/2;local ay=ly-art.height*factor/2
   if hex=='#FFFFFF'then c=art.color end
   for _,r in ipairs(art.rects or{})do rect(ax+r[1]*factor,ay+(art.height-r[2]-r[4])*factor,r[3]*factor,r[4]*factor,a,c)end
   for _,t in ipairs(art.triangles or{})do
    local p={ax+t[1]*factor,ay+(art.height-t[2])*factor,ax+t[3]*factor,ay+(art.height-t[4])*factor,ax+t[5]*factor,ay+(art.height-t[6])*factor}
    local lowx,highx=math.min(p[1],p[3],p[5]),math.max(p[1],p[3],p[5]);local lowy,highy=math.min(p[2],p[4],p[6]),math.max(p[2],p[4],p[6])
    out[#out+1]={type='triangle',points=p,x=lowx,y=lowy,w=highx-lowx,h=highy-lowy,a=a,c=c}
   end
  elseif o.logo==2 then
   -- Winged skull: vector geometry retains sharp edges at any resolution.
   mark(-.2,-.1,.4,.45);mark(-.14,-.28,.28,.2)
   for i=0,3 do mark(-.8+i*.08,.18-i*.1,.52-i*.04,.06);mark(.28,.18-i*.1,.52-i*.04,.06)end
   rect(lx-.12*size,ly+.08*size,.08*size,.08*size,a,{0,0,0});rect(lx+.04*size,ly+.08*size,.08*size,.08*size,a,{0,0,0})
  elseif o.logo==4 then
   for i=0,19 do local angle=i*math.pi/10;mark(math.cos(angle)*.45-.025,math.sin(angle)*.45-.025,.05,.05)end
   mark(-.45,-.02,.9,.04);mark(-.02,-.45,.04,.9);mark(-.33,.22,.66,.04);mark(-.33,-.26,.66,.04)
  else
   -- DBF lettermark, 3x5 pixel glyphs.
   local glyphs={'110101101101110','110101110101110','111100110100100'}
   for g,bits in ipairs(glyphs)do for i=1,15 do if bits:sub(i,i)=='1'then mark(-.66+(g-1)*.45+((i-1)%3)*.12,.3-math.floor((i-1)/3)*.12,.1,.1)end end end
  end
 end
 return out
end
return M

"""Generate continuous material patterns without changing frozen 1.2.1 assets."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'freecam/assets/decorative-v2'
HELPERS='''
float noise2(float2 p) {
 float2 i=floor(p),f=frac(p);f=f*f*(3-2*f);
 return lerp(lerp(hash2(i),hash2(i+float2(1,0)),f.x),lerp(hash2(i+float2(0,1)),hash2(i+1),f.x),f.y);
}
float fbm(float2 p) { return .53*noise2(p)+.27*noise2(p*2.07)+.13*noise2(p*4.13)+.07*noise2(p*8.27); }
float cells(float2 p) {
 float2 i=floor(p),f=frac(p);float nearest=10;
 [unroll]for(int y=-1;y<=1;y++) [unroll]for(int x=-1;x<=1;x++) {
  float2 g=float2(x,y);float2 o=float2(hash2(i+g),hash2(i+g+19.7));
  float2 d=g+.15+.7*o-f;nearest=min(nearest,dot(d,d));
 }return sqrt(nearest);
}
'''
PATTERNS={
'oxidized_copper':'''float n=fbm(p*.035+float2(fbm(p*.012),fbm(p*.012+9))*3);
 float patina=smoothstep(.40,.62,n);float grain=fbm(p*.4);
 rgb=lerp(float3(.64,.27,.105),float3(.055,.38,.29),patina)*(.72+.28*grain);
 rgb+=float3(.13,.07,.025)*pow(saturate(1-cells(p*.10)),8)*(1-patina);
 rgb*=.96+.04*sin(p.x*.013+p.y*.02+animation*elapsed*.25);''',
'prismatic':'''float2 q=float2(p.x-p.y*.57735027,p.y*1.15470054)/22;
 float2 cell=floor(q);float2 f=frac(q);float tri=step(1,f.x+f.y);
 float n=hash2(cell+tri*float2(17.3,39.1));
 float edge=min(min(f.x,f.y),min(1-f.x,1-f.y));edge=min(edge,abs(f.x+f.y-1)*.7071);
 float aa=max(fwidth(edge),.001);
 rgb=(.5+.5*cos(n*6.283+float3(0,2.1,4.2)+animation*elapsed*.25))*(.45+.5*n);
 rgb*=lerp(.55,1,smoothstep(0,aa*1.5,edge));''',
'hammered_metal':'''float d=cells(p*.10);float bevel=exp(-d*5);float grain=fbm(p*.4);
 rgb=float3(.43,.49,.55)*(.65+.4*grain)+bevel*.26;
 rgb+=.10*sin(p.x*.009+p.y*.012+animation*elapsed*.3)*bevel;''',
'leather':'''float d=cells(p*.24);float grain=fbm(p*.2);
 rgb=float3(.19,.12,.085)*(.65+.55*grain)+.055*smoothstep(.05,.18,d);
 rgb*=.92+.08*noise2(p*.9);''',
'ceramic':'''float cloud=fbm(p*.02);float sheen=pow(.5+.5*sin(p.x*.009+p.y*.014+animation*elapsed*.2),10);
 rgb=float3(.79,.83,.81)*(.89+.1*cloud)+.1*sheen;''',
'gunmetal':'''float grain=noise2(float2(p.x*.3,p.y*2));float sheen=pow(.5+.5*sin(p.x*.012+p.y*.004+animation*elapsed*.2),8);
 rgb=float3(.21,.255,.29)*(.8+.2*grain)+float3(.12,.14,.16)*sheen;''',
'brushed_steel':'''float grain=noise2(float2(p.x*.025,p.y*1.8));float fine=noise2(float2(p.x*.06,p.y*5));
 float sheen=pow(.5+.5*sin(p.x*.009+animation*elapsed*.2),10);
 rgb=float3(.52,.57,.62)*(.7+.22*grain+.08*fine)+.18*sheen;''',
'frosted':'''float n=fbm(p*.16);float cloud=fbm(p*.014);
 rgb=float3(.65,.76,.82)*(.84+.12*n+.04*cloud);
 rgb+=animation*.015*sin(elapsed*.3+p.x*.01);''',
}
# The full-screen overlay maps 1024x512 cells across the view at scale 1, so
# the original floor(p) quantization shows as ~4px blocks and stair-steps.
# These keep each original formula and color but evaluate it on continuous
# coordinates. Edge widths come from derivatives of unwrapped coordinates;
# differentiating frac()-wrapped values would draw seams at tile boundaries.
AA_HELPERS='''
float aawidth(float2 v) { float2 w=fwidth(v);return max(max(w.x,w.y),1e-4)*.75; }
float aaband(float x,float period,float c,float h) {
 float w=max(fwidth(x),1e-4)*.75;float d=abs(frac((x-c)/period+.5)-.5)*period;
 return 1-smoothstep(h-w,h+w,d);
}
float aadisc(float d,float r,float w) { return 1-smoothstep(r-w,r+w,d); }
float aastep(float edge,float x) { float w=max(fwidth(x),1e-4)*.75;return smoothstep(edge-w,edge+w,x); }
'''
SMOOTH={
'amber_glass':'''rgb*=float3(1,.82,.55);rgb+=.03*pow(.5+.5*sin(p.x*.04+p.y*.03),8);
 rgb+=animation*float3(.06,.035,.008)*pow(saturate(1-abs(frac(p.x/256+p.y/200-elapsed*.07)-.5)*2),12);''',
'cobalt_glass':'''rgb*=float3(.65,.85,1);rgb+=float3(.015,.03,.045);
 rgb+=animation*float3(.012,.04,.08)*pow(saturate(1-abs(frac((p.x-p.y)/300-elapsed*.06)-.5)*2),16);''',
'glass_sheen':'''float shine=pow(max(0,1-abs(frac((p.x+p.y*.7)/140-animation*elapsed*.1)-.5)*2),18);
 rgb=lerp(rgb,float3(.8,.95,1),shine*.35);''',
'heat_shimmer':'''float wave=sin(p.y*.11+sin(p.x*.03)+EFFECT_TIME*3);rgb+=float3(.07,.02,-.01)*wave;''',
'iridescent':'''float3 sheen=.5+.5*cos(p.x*.018+animation*elapsed+float3(0,2,4));rgb=lerp(rgb,sheen,.18);''',
'thermal':'''float band=.5+.5*sin(p.x*.035-animation*elapsed);rgb=lerp(rgb,float3(1,.15,.035),band*.3);''',
'sweep':'''float band=pow(max(0,1-abs(frac(p.x/180-EFFECT_TIME*.2)-.5)*2),12);rgb+=float3(.08,.3,.35)*band;''',
'rail_glints':'''float f=pow(max(0,sin(p.y*.04-animation*elapsed)),24);rgb+=float3(.14,.18,.2)*f;''',
'ribbed_alloy':'''rgb*=.65+.35*abs(sin(p.x*.5));
 rgb+=animation*.08*abs(sin(p.x*.5))*pow(saturate(1-abs(frac(p.x/256-elapsed*.1)-.5)*2),14);''',
'energy_threads':'''float wave=abs(sin(p.y*.15+sin(p.x*.025)+animation*elapsed*3));rgb+=float3(.04,.14,.2)*aastep(.97,wave);''',
'ceramic_cracks':'''float a=sin(p.x*.09)+sin(p.y*.13);rgb*=lerp(1,.3,1-aastep(.055,abs(a)));
 rgb+=animation*float3(.04,.03,.015)*(1-smoothstep(.055,.15,abs(a)))*(.5+.5*sin(elapsed*1.5));''',
'carbon':'''float bx=aaband(p.x,8,2,2),by=aaband(p.y,8,2,2);float weave=bx*by+(1-bx)*(1-by);
 rgb*=lerp(1,.7,weave)*(.85+.15*sin((p.x+p.y)*.8));
 rgb*=1-animation*.12*(.5+.5*sin(elapsed*1.5+(p.x+p.y)*.08));''',
'stipple_gradient':'''float2 s=p/1.6;float2 i=floor(s),f=frac(s);float w=aawidth(s);float dark=0;
 // Soft low-frequency shading; the original frac(y/96) ramp reset drew
 // hard horizontal lines several times across a full-screen overlay.
 float density=.45*smoothstep(.32,.72,fbm(p*.006));
 [unroll]for(int y=-1;y<=1;y++) [unroll]for(int x=-1;x<=1;x++) {
  float2 g=float2(x,y);float2 c=i+g;
  float2 o=g+.15+.7*float2(hash2(c+7.3),hash2(c+3.1));
  dark=max(dark,step(hash2(c),density*2)*aadisc(length(f-o),.4,w));
 }
 rgb*=1-.5*dark;
 rgb*=1-animation*.15*(.5+.5*sin(p.y*.04-elapsed*1.5));''',
'ion_noise':'''float t=floor(EFFECT_TIME*12);float2 o=frac(t*float2(.1717,.0931))*97;
 float n=saturate((fbm(p/3+o)-.5)*1.8+.5);rgb*=.6+.4*n;
 rgb+=float3(.02,.06,.1)*step(.96,hash2(floor(p/3)+o))*aadisc(length(frac(p/3)*3-1.5),1.1,aawidth(p));''',
'warning_hatch':'''float band=aaband(p.x+p.y+animation*elapsed*8,16,12,4);rgb=lerp(rgb,float3(.04,.025,.01),band*.65);''',
'hazard_red':'''float hatch=aaband(p.x-p.y+4096+animation*elapsed*8,16,12,4);rgb=lerp(rgb,float3(.45,.025,.015),hatch*.35);''',
'diagonal_weave':'''rgb*=lerp(1,.55,aaband(p.x+p.y,6,1,1));
 rgb*=1-animation*.15*(.5+.5*sin((p.x-p.y)*.08-elapsed*2));''',
'triangular_grille':'''float2 q=frac(p/14)*14;float w=aawidth(p)*1.5;float edge=smoothstep(-w,w,q.y-abs(q.x-7)*1.5);
 rgb*=lerp(1,.5,edge);
 rgb+=animation*.07*edge*pow(saturate(1-abs(frac((p.x-p.y)/256-elapsed*.09)-.5)*2),18);''',
'caution_dots':'''float2 q=frac(p/10)*10-5.5;rgb*=lerp(1,.35,aadisc(length(q),2.05,aawidth(p)));
 rgb*=1-animation*.2*(.5+.5*sin(elapsed*3+floor(p.x/10)*3.14159));''',
'grid_nodes':'''float2 q=frac(p/24)*24-12.5;float node=aadisc(length(q),2.6,aawidth(p));rgb=rgb*.8+float3(.07,.2,.16)*node;
 rgb+=animation*float3(.025,.1,.055)*node*(.5+.5*sin(elapsed*3+floor(p.x/24)+floor(p.y/24)));''',
'dot_matrix':'''float2 q=frac(p/4)*4-2;float lit=aadisc(length(q),1.13,aawidth(p));rgb*=lerp(.35,1,lit);
 rgb+=animation*float3(.03,.08,.04)*pow(saturate(1-abs(frac(p.y/128-elapsed*.2)-.5)*2),30)*lit;''',
'circuit':'''float2 q=frac(p/32)*32;float w=max(fwidth(p.x-p.y),1e-4)*.75;
 float lines=max(aaband(p.x,32,.5,.5),aaband(p.y,32,.5,.5));
 float trace=max(lines,1-smoothstep(.5-w,.5+w,abs(q.x-q.y)));rgb=rgb*.75+float3(.05,.2,.22)*trace;
 rgb+=animation*float3(.02,.1,.12)*lines*pow(saturate(1-abs(frac((p.x+p.y)/96-elapsed*.25)-.5)*2),12);''',
}
def generate():
 FOLDER.mkdir(exist_ok=True)
 for name,pattern in list(PATTERNS.items())+list(SMOOTH.items()):
  original=(ROOT/'freecam/assets/shaders'/f'{name}.hlsl').read_text()
  header=original[:original.index('float4 hud_fill')]
  body=original[original.index('float4 hud_fill'):original.index('    float2 p=floor(')]
  # The first eight sources are deployed; keep their bytes (and content IDs) fixed.
  helpers=HELPERS+(AA_HELPERS if name in SMOOTH else '')
  source=header+helpers+body+'''    // Continuous coordinates; cell boundaries are antialiased in pattern code.
    float2 p=panel_uv*float2(256,128);float3 rgb=input.color.rgb;
    float animation=atlas_scissor.w > .5 ? 1:0;float elapsed=max(0,scissor_rect.w);
    '''+pattern+'''
    return float4(saturate(rgb),input.color.a);
}
'''
  (FOLDER/f'{name}.hlsl').write_text(source)
 return list(PATTERNS)+list(SMOOTH)
if __name__=='__main__':print(generate())

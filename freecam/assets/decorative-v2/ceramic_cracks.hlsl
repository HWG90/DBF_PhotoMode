// Shader lab: panel-local pattern. EFFECT_TIME is a frozen sample until a live time binding is validated.
#define EFFECT_TIME (0.75 + (atlas_scissor.w > 0.5 ? max(0,scissor_rect.w) : 0))
float hash2(float2 p) { return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
Texture2D<float> __tex_linear_depth : register(t0);
SamplerState __samp_linear_depth : register(s0);
cbuffer global_viewport : register(b0) { float4 screen_viewport : packoffset(c48); };
cbuffer c0 : register(b2) {
    float4 scissor_rect : packoffset(c0);
    float4 atlas_scissor : packoffset(c2);
    float4 clip_box : packoffset(c8);
    float scissor_mode : packoffset(c1.x);
    float threshold_fade : packoffset(c3.x);
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0;  };

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

float aawidth(float2 v) { float2 w=fwidth(v);return max(max(w.x,w.y),1e-4)*.75; }
float aaband(float x,float period,float c,float h) {
 float w=max(fwidth(x),1e-4)*.75;float d=abs(frac((x-c)/period+.5)-.5)*period;
 return 1-smoothstep(h-w,h+w,d);
}
float aadisc(float d,float r,float w) { return 1-smoothstep(r-w,r+w,d); }
float aastep(float edge,float x) { float w=max(fwidth(x),1e-4)*.75;return smoothstep(edge-w,edge+w,x); }
float4 hud_fill(Input input) : SV_TARGET {
    if (scissor_mode > 0.5) {
        float2 uv=input.position.xy/max(screen_viewport.xy,float2(1,1));
        clip(__tex_linear_depth.SampleLevel(__samp_linear_depth,uv,0)+0.01-threshold_fade);
    }
    float3 screen_point=float3(input.position.xy/max(screen_viewport.xy,float2(1,1)),1);
    float denominator=dot(clip_box.xyz,screen_point);
    clip(abs(denominator)-0.000001);
    float2 panel_uv=float2(dot(scissor_rect.xyz,screen_point),dot(atlas_scissor.xyz,screen_point))/denominator;
    // Continuous coordinates; cell boundaries are antialiased in pattern code.
    float2 p=panel_uv*float2(256,128);float3 rgb=input.color.rgb;
    float animation=atlas_scissor.w > .5 ? 1:0;float elapsed=max(0,scissor_rect.w);
    float a=sin(p.x*.09)+sin(p.y*.13);rgb*=lerp(1,.3,1-aastep(.055,abs(a)));
 rgb+=animation*float3(.04,.03,.015)*(1-smoothstep(.055,.15,abs(a)))*(.5+.5*sin(elapsed*1.5));
    return float4(saturate(rgb),input.color.a);
}

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
float4 hud_fill(Input input) : SV_TARGET {
    if (scissor_mode > 0.5) {
        float2 uv=input.position.xy/max(screen_viewport.xy,float2(1,1));
        clip(__tex_linear_depth.SampleLevel(__samp_linear_depth,uv,0)+0.01-threshold_fade);
    }
    float3 screen_point=float3(input.position.xy/max(screen_viewport.xy,float2(1,1)),1);
    float denominator=dot(clip_box.xyz,screen_point);
    clip(abs(denominator)-0.000001);
    float2 panel_uv=float2(dot(scissor_rect.xyz,screen_point),dot(atlas_scissor.xyz,screen_point))/denominator;
    float2 p=floor(panel_uv*float2(256,128));float3 rgb=input.color.rgb;
    float animation=atlas_scissor.w > .5 ? 1:0;float elapsed=max(0,scissor_rect.w);
    float n=hash2(floor(p/4));rgb*=.55+.45*n;
    rgb+=animation*.07*hash2(floor(p/4))*(.5+.5*sin(elapsed*1.7+hash2(floor(p/4))*6.283));
    return float4(saturate(rgb),input.color.a);
}

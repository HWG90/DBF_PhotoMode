// Depth-aware blur composited over the original scene so focused pixels stay sharp.
Texture2D<float4> __tex_hdr0_div4_fullres : register(t1);
SamplerState __samp_hdr0_div4_fullres : register(s1);
Texture2D<float> __tex_diffuse_map : register(t0);
SamplerState __samp_diffuse_map : register(s0);
cbuffer global_viewport : register(b0) { float4 screen_viewport : packoffset(c48); };
cbuffer c0 : register(b2) {
 float4 scissor_rect : packoffset(c0); // focus metres, f-stop, vertical FOV radians, maximum blur pixels
 float4 atlas_scissor : packoffset(c2); // depth scale, calibration view, unused, unused
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0; };
float4 photo_dof(Input input) : SV_TARGET {
 float2 resolution=max(screen_viewport.xy,float2(1,1));
 float2 uv=input.position.xy/resolution;
 float depth=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,uv,0)*max(.001,atlas_scissor.x));
 if(atlas_scissor.y>.5){float value=saturate(log2(1+depth)/8);return float4(value,value,value,input.color.a);}
 float focus=max(.1,scissor_rect.x);
 float aperture=clamp(scissor_rect.y,1.2,22);
 float focal=.012/tan(clamp(scissor_rect.z,.02,2.9)*.5);
 float coc=abs(focal*focal*(depth-focus)/(aperture*depth*max(.001,focus-focal)));
 float radius=min(max(1,scissor_rect.w),coc*resolution.y/.048);
 // The native HDR blur target already loses fine detail. Leave the original
 // framebuffer visible around the focus plane and for subpixel defocus.
 float opacity=smoothstep(.5,5.0,radius);
 if(opacity<=0)return float4(0,0,0,0);
 float3 color=__tex_hdr0_div4_fullres.SampleLevel(__samp_hdr0_div4_fullres,uv,0).rgb;
 float total=1;
 [unroll] for(int sample=0;sample<8;sample++){
  float angle=sample*.7853981634;
  float2 offset=float2(cos(angle),sin(angle))*radius/resolution;
  float2 tap_uv=saturate(uv+offset);
  float other=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,tap_uv,0)*max(.001,atlas_scissor.x));
  float weight=saturate(1-abs(other-depth)/max(.2,depth*.12));
  color+=__tex_hdr0_div4_fullres.SampleLevel(__samp_hdr0_div4_fullres,tap_uv,0).rgb*weight;
  total+=weight;
 }
 return float4(saturate(color/total),input.color.a*opacity);
}

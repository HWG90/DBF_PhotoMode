// Separate Photo scene shader. hdr0_div4_fullres is 960x540 in the verified
// viewport; this preview does not claim full-resolution color grading.
Texture2D<float4> __tex_hdr0_div4_fullres : register(t1);
SamplerState __samp_hdr0_div4_fullres : register(s1);
Texture2D<float> __tex_diffuse_map : register(t0);
SamplerState __samp_diffuse_map : register(s0);
cbuffer global_viewport : register(b0) { float4 screen_viewport : packoffset(c48); };
cbuffer c0 : register(b2) {
 float4 scissor_rect : packoffset(c0); // effect 0-9, strength, fog reach (m), fog density 0-1
 float4 atlas_scissor : packoffset(c2); // exposure EV, contrast, saturation, depth range (m)
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0; };
float3 decode_display(float3 color) {
 color=max(color,0);return float3(color.r<=.04045?color.r/12.92:pow((color.r+.055)/1.055,2.4),color.g<=.04045?color.g/12.92:pow((color.g+.055)/1.055,2.4),color.b<=.04045?color.b/12.92:pow((color.b+.055)/1.055,2.4));
}
float3 encode_display(float3 color) {
 color=max(color,0);return float3(color.r<=.0031308?color.r*12.92:1.055*pow(color.r,1/2.4)-.055,color.g<=.0031308?color.g*12.92:1.055*pow(color.g,1/2.4)-.055,color.b<=.0031308?color.b*12.92:1.055*pow(color.b,1/2.4)-.055);
}
float3 thermal(float value) {
 float3 low=float3(.015,.02,.16),blue=float3(.03,.35,.95),yellow=float3(1,.86,.05),red=float3(.95,.06,.01);
 float t=saturate(value)*3;
 return t<1?lerp(low,blue,t):(t<2?lerp(blue,yellow,t-1):lerp(yellow,red,t-2));
}
float4 photo_scene(Input input) : SV_TARGET {
 float2 uv=input.position.xy/max(screen_viewport.xy,float2(1,1));
 float3 source=__tex_hdr0_div4_fullres.SampleLevel(__samp_hdr0_div4_fullres,uv,0).rgb;
 float3 working=decode_display(source)*exp2(clamp(atlas_scissor.x,-4,4));
 working=max(0,(working-.18)*clamp(atlas_scissor.y,.5,2)+.18);
 float luminance=dot(working,float3(.2126,.7152,.0722));
 working=max(0,lerp(luminance.xxx,working,clamp(atlas_scissor.z,0,2)));
 float3 base=encode_display(working),effect=base;
 int mode=(int)round(scissor_rect.x);
 if(mode==1)effect=1-saturate(base); // Color inversion.
 else if(mode==2)effect=encode_display(luminance.xxx);
 else if(mode==3)effect=floor(saturate(base)*5+.5)/5;
 else if(mode==4)effect=lerp(float3(.04,.08,.14),float3(.95,.72,.29),saturate(dot(base,float3(.2126,.7152,.0722))));
 else if(mode==5)effect=float3(base.r>.5?1-base.r:base.r,base.g>.5?1-base.g:base.g,base.b>.5?1-base.b:base.b);
 else if(mode>=6){
  float depth=max(0,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,uv,0));
  float range=max(1,atlas_scissor.w);
  float normalized=saturate(log2(1+depth)/log2(1+range));
  if(mode==6)effect=(1-normalized).xxx;
  else if(mode==7)effect=thermal(1-normalized);
  else if(mode==8){
   float bands=depth/max(.1,range/20);
   float width=max(.02,min(.18,fwidth(bands)));
   float contour=1-smoothstep(width,width*2,abs(frac(bands+.5)-.5));
   effect=lerp(base,thermal(1-normalized)*.5,contour*.8);
  }else if(mode==9){
   float fog=(1-exp2(-depth/max(.1,scissor_rect.z)))*saturate(scissor_rect.w);
   effect=lerp(base,float3(.56,.64,.69),fog);
  }
 }
 return float4(lerp(base,effect,saturate(scissor_rect.y)),input.color.a);
}

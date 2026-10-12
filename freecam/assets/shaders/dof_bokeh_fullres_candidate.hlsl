// Explicit full-resolution bokeh candidate. GUI color-stage compatibility is unverified.
Texture2D<float4> __tex_hdr0_div4_fullres : register(t1);
SamplerState __samp_hdr0_div4_fullres : register(s1);
Texture2D<float> __tex_diffuse_map : register(t0);
SamplerState __samp_diffuse_map : register(s0);
cbuffer global_viewport : register(b0) { float4 screen_viewport : packoffset(c48); };
cbuffer c0 : register(b2) {
 float4 scissor_rect : packoffset(c0); // focus metres, f-stop, vertical FOV, maximum blur pixels
 float4 atlas_scissor : packoffset(c2); // depth scale, calibration, aperture blades (0=circle/6=hex), quality (0=32/1=64)
 float desaturate : packoffset(c3.y); // existing native scalar reused for highlight weight; 0 uses default .5
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0; };
float signed_radius(float depth,float focus,float aperture,float focal,float viewport_height) {
 float coc=focal*focal*(depth-focus)/(aperture*depth*max(.001,focus-focal));
 return clamp(coc*viewport_height/.048,-max(1,scissor_rect.w),max(1,scissor_rect.w));
}
float2 aperture_point(float2 disk_offset) {
 float blades=atlas_scissor.z;
 if(blades>=3){
  blades=clamp(round(blades),3,9);
  float sector=6.28318530718/blades;
  float angle=atan2(disk_offset.y,disk_offset.x);
  float folded=angle-sector*floor((angle+sector*.5)/sector);
  disk_offset*=cos(3.14159265359/blades)/max(.1,cos(folded));
 }
 return disk_offset;
}
float3 decode_display(float3 color) {
 color=max(color,0);return float3(color.r<=.04045?color.r/12.92:pow((color.r+.055)/1.055,2.4),color.g<=.04045?color.g/12.92:pow((color.g+.055)/1.055,2.4),color.b<=.04045?color.b/12.92:pow((color.b+.055)/1.055,2.4));
}
float3 encode_display(float3 color) {
 color=max(color,0);return float3(color.r<=.0031308?color.r*12.92:1.055*pow(color.r,1/2.4)-.055,color.g<=.0031308?color.g*12.92:1.055*pow(color.g,1/2.4)-.055,color.b<=.0031308?color.b*12.92:1.055*pow(color.b,1/2.4)-.055);
}
float light_weight(float3 color) {
 // Keep linear HDR color unclipped through the gather; matching GUI transfer is a later verified step.
 float luminance=max(0,dot(color,float3(.2126,.7152,.0722)));
 float strength=desaturate>0?min(desaturate,4):.5;
 return 1+strength*min(8,max(0,luminance-1));
}
float4 photo_dof(Input input) : SV_TARGET {
 float2 resolution=max(screen_viewport.xy,float2(1,1));
 float2 uv=input.position.xy/resolution;
 float scale=max(.001,atlas_scissor.x);
 float depth=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,uv,0)*scale);
 if(atlas_scissor.y>.5){float value=saturate(log2(1+depth)/8);return float4(value,value,value,input.color.a);}
 float focus=max(.1,scissor_rect.x),aperture=clamp(scissor_rect.y,1.2,22);
 float focal=.012/tan(clamp(scissor_rect.z,.02,2.9)*.5);
 float signed_coc=signed_radius(depth,focus,aperture,focal,resolution.y);
 float radius=abs(signed_coc),opacity=smoothstep(.5,5,radius);
 if(opacity<=0)return float4(0,0,0,0);
 float3 center=decode_display(__tex_hdr0_div4_fullres.SampleLevel(__samp_hdr0_div4_fullres,uv,0).rgb);
 float center_weight=light_weight(center);
 float3 color=center*center_weight;float total=center_weight;
 int count=atlas_scissor.w>=.5?64:32;
 [loop] for(int tap=0;tap<count;tap++){
  float angle=tap*2.39996322973;
  float2 disk_offset=aperture_point(float2(cos(angle),sin(angle))*sqrt((tap+.5)/count));
  float2 tap_uv=uv+disk_offset*radius/resolution;
  if(any(tap_uv<0)||any(tap_uv>1))continue;
  float other=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,tap_uv,0)*scale);
  float other_coc=signed_radius(other,focus,aperture,focal,resolution.y);
  if(signed_coc*other_coc<0)continue; // Avoid leaking defocused background over focused foreground.
  float edge_weight=exp2(-abs(other-depth)/max(.025,depth*.05));
  float distance=length(disk_offset)*radius;
  float coverage=smoothstep(max(0,distance-.5),distance+.5,abs(other_coc));
  float3 sample_color=decode_display(__tex_hdr0_div4_fullres.SampleLevel(__samp_hdr0_div4_fullres,tap_uv,0).rgb);
  float weight=edge_weight*coverage*light_weight(sample_color);
  color+=sample_color*weight;total+=weight;
 }
 return float4(encode_display(color/max(.0001,total)),input.color.a*opacity);
}

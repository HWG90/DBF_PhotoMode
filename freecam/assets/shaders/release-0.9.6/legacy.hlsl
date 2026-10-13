// Isolated combined scene/DoF candidate. The GUI color binding must be changed
// to a separately verified full-resolution target before deployment.
Texture2D<float4> __tex_photo_color : register(t1);
SamplerState __samp_photo_color : register(s1);
Texture2D<float> __tex_diffuse_map : register(t0);
SamplerState __samp_diffuse_map : register(s0);
cbuffer global_viewport : register(b0) { float4 screen_viewport : packoffset(c48); };
cbuffer c0 : register(b2) {
 float4 scissor_rect : packoffset(c0); // focus, aperture, FOV, blur maximum; w=0 disables DoF
 float scissor_mode : packoffset(c1.x); // scene effect 0-9
 float4 atlas_scissor : packoffset(c2); // scene depth range, calibration, aperture blades, quality
 float threshold_fade : packoffset(c3.x); // scene strength
 float desaturate : packoffset(c3.y); // fog half-density distance
 float4 clip_box : packoffset(c8); // exposure EV, contrast, saturation, fog maximum opacity
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0; };
float3 decode_display(float3 c) {
 c=max(c,0);return c<=.04045?c/12.92:pow((c+.055)/1.055,2.4);
}
float3 encode_display(float3 c) {
 c=max(c,0);return c<=.0031308?c*12.92:1.055*pow(c,1/2.4)-.055;
}
float3 thermal(float value) {
 float t=saturate(value)*3;
 return t<1?lerp(float3(.015,.02,.16),float3(.03,.35,.95),t):(t<2?lerp(float3(.03,.35,.95),float3(1,.86,.05),t-1):lerp(float3(1,.86,.05),float3(.95,.06,.01),t-2));
}
float radius(float d,float focus,float aperture,float focal,float height) {
 return clamp(focal*focal*(d-focus)/(aperture*d*max(.001,focus-focal))*height/.048,-scissor_rect.w,scissor_rect.w);
}
float4 photo_combined(Input input) : SV_TARGET {
 float2 resolution=max(screen_viewport.xy,float2(1,1)),uv=input.position.xy/resolution;
 float depth=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,uv,0));
 if(atlas_scissor.y>.5){float v=saturate(log2(1+depth)/8);return float4(v,v,v,input.color.a);}
 float3 source=decode_display(__tex_photo_color.SampleLevel(__samp_photo_color,uv,0).rgb);
 float opacity=0;
 if(scissor_rect.w>0){
  float focus=max(.1,scissor_rect.x),aperture=clamp(scissor_rect.y,1.2,22);
  float focal=.012/tan(clamp(scissor_rect.z,.02,2.9)*.5),signed_coc=radius(depth,focus,aperture,focal,resolution.y),blur=abs(signed_coc);
  opacity=smoothstep(.5,5,blur);
  if(opacity>0){
   float3 gathered=source;float total=1;int count=atlas_scissor.w>=.5?64:32;
   [loop]for(int tap=0;tap<count;tap++){
    float angle=tap*2.39996322973;float2 disk=float2(cos(angle),sin(angle))*sqrt((tap+.5)/count);
    if(atlas_scissor.z>=3){float sector=6.28318530718/atlas_scissor.z;float folded=angle-sector*floor((angle+sector*.5)/sector);disk*=cos(sector*.5)/max(.1,cos(folded));}
    float2 sample_uv=uv+disk*blur/resolution;
    if(any(sample_uv<0)||any(sample_uv>1))continue;
    float other=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,sample_uv,0)),coc=radius(other,focus,aperture,focal,resolution.y);
    if(signed_coc*coc<0)continue;
    float distance=length(disk)*blur;
    float3 color=decode_display(__tex_photo_color.SampleLevel(__samp_photo_color,sample_uv,0).rgb);
    float weight=exp2(-abs(other-depth)/max(.025,depth*.05))*smoothstep(max(0,distance-.5),distance+.5,abs(coc))*(1+.5*min(8,max(0,dot(color,float3(.2126,.7152,.0722))-1)));
    gathered+=color*weight;total+=weight;
   }
   source=lerp(source,gathered/max(.0001,total),opacity);
  }
 }
 int mode=(int)round(scissor_mode);
 bool scene=(mode>0&&threshold_fade>0)||clip_box.x!=0||clip_box.y!=1||clip_box.z!=1;
 if(!scene&&opacity<=0)return float4(0,0,0,0);
 if(!scene)return float4(encode_display(source),input.color.a); // full source at focus; one composite
 float3 working=max(0,(source*exp2(clamp(clip_box.x,-4,4))-.18)*clamp(clip_box.y,.5,2)+.18);
 float luminance=dot(working,float3(.2126,.7152,.0722));
 working=max(0,lerp(luminance.xxx,working,clamp(clip_box.z,0,2)));
 float3 base=encode_display(working),effect=base;
 if(mode==1)effect=1-saturate(base);
 else if(mode==2)effect=encode_display(luminance.xxx);
 else if(mode==3)effect=floor(saturate(base)*5+.5)/5;
 else if(mode==4)effect=lerp(float3(.04,.08,.14),float3(.95,.72,.29),saturate(dot(base,float3(.2126,.7152,.0722))));
 else if(mode==5)effect=base>.5?1-base:base;
 else if(mode>=6){
  float range=max(1,atlas_scissor.x),normalized=saturate(log2(1+depth)/log2(1+range));
  if(mode==6)effect=(1-normalized).xxx;
  else if(mode==7)effect=thermal(1-normalized);
  else if(mode==8){float bands=depth/max(.1,range/20),width=max(.02,min(.18,fwidth(bands)));float contour=1-smoothstep(width,width*2,abs(frac(bands+.5)-.5));effect=lerp(base,thermal(1-normalized)*.5,contour*.8);}
  else if(mode==9)effect=lerp(base,float3(.56,.64,.69),(1-exp2(-depth/max(.1,desaturate)))*saturate(clip_box.w));
 }
 return float4(lerp(base,effect,saturate(threshold_fade)),input.color.a);
}

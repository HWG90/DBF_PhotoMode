// Private development compositor. t1 is the separately verified, full-size
// output_target AFTER the game's scene grading and tone mapper, encoded as PQ.
// Decode to the native GUI working primaries, gather in linear light, then
// encode the GUI carrier exactly once. The final compositor applies sRGB EOTF.
// RGBA8 GUI output clips energy above UI white and colors outside GUI gamut.
Texture2D<float4> __tex_photo_color : register(t1);
SamplerState __samp_photo_color : register(s1);
Texture2D<float> __tex_diffuse_map : register(t0);
SamplerState __samp_diffuse_map : register(s0);
cbuffer global_viewport : register(b0) {
 float4 screen_viewport : packoffset(c48);
};
cbuffer c0 : register(b2) {
 float4 scissor_rect : packoffset(c0); // focus m, f-stop, FOV radians, max blur px; w=0 disables DoF
 float scissor_mode : packoffset(c1.x); // scene effect 0-9
 float4 atlas_scissor : packoffset(c2); // depth range, fog opacity + debug*1000, blades, quality
 float threshold_fade : packoffset(c3.x); // scene effect strength
 float desaturate : packoffset(c3.y); // fog half-density distance m
 float4 clip_box : packoffset(c8); // exposure EV, contrast, saturation, verified UI white nits
};
struct Input { float4 position : SV_POSITION; float4 color : COLOR0; };

float3 decode_resolved(float3 pq) {
 // ST2084 inverse to absolute nits. These are the same exact rational
 // constants as the native composit_image:BLEND_UI scene decoder.
 float3 p=pow(saturate(pq),32.0/2523.0);
 float3 nits=10000.0*pow(max(p-3424.0/4096.0,0.0)/max(2413.0/128.0-(2392.0/128.0)*p,.000001),16384.0/2610.0);
 float3 gui_nits=float3(dot(nits,float3(1.63504,-.60563,-.07635)),
                       dot(nits,float3(-.12325,1.13885,-.01029)),
                       dot(nits,float3(-.01716,-.10173,1.21073)));
 // Runtime must supply the typed, verified native ui_brightness value.
 // The fallback only keeps an invalid material payload finite; it does not
 // replace the runtime readiness check or calibrate scene exposure.
 float white=(isfinite(clip_box.w)&&clip_box.w>0.0)?clip_box.w:203.0;
 return max(gui_nits,0.0)/white;
}
float3 encode_display(float3 light) {
 light=max(light,0.0);
 return light<=.0031308?light*12.92:1.055*pow(light,1.0/2.4)-.055;
}
float3 thermal(float value) {
 float t=saturate(value)*3.0;
 return t<1.0?lerp(float3(.015,.02,.16),float3(.03,.35,.95),t):
        (t<2.0?lerp(float3(.03,.35,.95),float3(1,.86,.05),t-1.0):
                lerp(float3(1,.86,.05),float3(.95,.06,.01),t-2.0));
}
float radius(float depth,float focus,float aperture,float focal,float height) {
 return clamp(focal*focal*(depth-focus)/(aperture*depth*max(.001,focus-focal))*height/.048,
              -scissor_rect.w,scissor_rect.w);
}
float4 photo_resolved_v2(Input input) : SV_TARGET {
 float2 resolution=max(screen_viewport.xy,float2(1,1));
 float2 uv=input.position.xy/resolution;
 float depth=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,uv,0));
 bool calibration=atlas_scissor.y>=1000.0;
 float fog_opacity=saturate(atlas_scissor.y-(calibration?1000.0:0.0));
 if(calibration){float v=saturate(log2(1.0+depth)/8.0);return float4(v,v,v,input.color.a);}
 int mode=(int)round(scissor_mode);
 bool scene=(mode>0&&threshold_fade>0.0)||clip_box.x!=0.0||clip_box.y!=1.0||clip_box.z!=1.0;
 float3 source=decode_resolved(__tex_photo_color.SampleLevel(__samp_photo_color,uv,0).rgb);
 float opacity=0.0;
 if(scissor_rect.w>0.0){
  float focus=max(.1,scissor_rect.x),aperture=clamp(scissor_rect.y,1.2,22.0);
  float focal=.012/tan(clamp(scissor_rect.z,.02,2.9)*.5);
  float signed_coc=radius(depth,focus,aperture,focal,resolution.y),blur=abs(signed_coc);
  opacity=smoothstep(.5,5.0,blur);
  if(opacity>0.0){
   float3 gathered=source;float total=1.0;
   int count=atlas_scissor.w>=.5?64:32;
   [loop]for(int tap=0;tap<count;tap++){
    float angle=tap*2.39996322973;
    float2 disk=float2(cos(angle),sin(angle))*sqrt((tap+.5)/count);
    if(atlas_scissor.z>=3.0){
     float sector=6.28318530718/atlas_scissor.z;
     float folded=angle-sector*floor((angle+sector*.5)/sector);
     disk*=cos(sector*.5)/max(.1,cos(folded));
    }
    float2 sample_uv=uv+disk*blur/resolution;
    if(any(sample_uv<0.0)||any(sample_uv>1.0))continue;
    float other=max(.001,__tex_diffuse_map.SampleLevel(__samp_diffuse_map,sample_uv,0));
    float coc=radius(other,focus,aperture,focal,resolution.y);
    if(signed_coc*coc<0.0)continue;
    float distance=length(disk)*blur;
    float3 color=decode_resolved(__tex_photo_color.SampleLevel(__samp_photo_color,sample_uv,0).rgb);
    float weight=exp2(-abs(other-depth)/max(.025,depth*.05))*
                 smoothstep(max(0.0,distance-.5),distance+.5,abs(coc))*
                 (1.0+.5*min(8.0,max(0.0,dot(color,float3(.2126,.7152,.0722))-1.0)));
    gathered+=color*weight;total+=weight;
   }
   // Neutral DoF uses GUI alpha for its single transition into the gathered
   // result. Explicit scene effects replace the scene, so retain their
   // sharp-to-blurred interpolation here instead.
   float3 blurred=gathered/max(.0001,total);
   source=scene?lerp(source,blurred,opacity):blurred;
  }
 }
 if(!scene&&(scissor_rect.w<=0.0||opacity<=0.0))return float4(0,0,0,0);
 // Neutral focused pixels retain the original native HDR scene. Smooth
 // opacity avoids the old binary alpha jump at the first nonzero blur.
 if(!scene)return float4(encode_display(source),opacity*input.color.a);
 float3 working=max(0.0,(source*exp2(clamp(clip_box.x,-4.0,4.0))-.18)*clamp(clip_box.y,.5,2.0)+.18);
 float luminance=dot(working,float3(.2126,.7152,.0722));
 working=max(0.0,lerp(luminance.xxx,working,clamp(clip_box.z,0.0,2.0)));
 float3 base=encode_display(working),effect=base;
 if(mode==1)effect=1.0-saturate(base);
 else if(mode==2)effect=encode_display(luminance.xxx);
 else if(mode==3)effect=floor(saturate(base)*5.0+.5)/5.0;
 else if(mode==4)effect=lerp(float3(.04,.08,.14),float3(.95,.72,.29),saturate(dot(base,float3(.2126,.7152,.0722))));
 else if(mode==5)effect=base>.5?1.0-base:base;
 else if(mode>=6){
  float range=max(1.0,atlas_scissor.x),normalized=saturate(log2(1.0+depth)/log2(1.0+range));
  if(mode==6)effect=(1.0-normalized).xxx;
  else if(mode==7)effect=thermal(1.0-normalized);
  else if(mode==8){
   float bands=depth/max(.1,range/20.0),width=max(.02,min(.18,fwidth(bands)));
   float contour=1.0-smoothstep(width,width*2.0,abs(frac(bands+.5)-.5));
   effect=lerp(base,thermal(1.0-normalized)*.5,contour*.8);
  }
  else if(mode==9)effect=lerp(base,float3(.56,.64,.69),(1.0-exp2(-depth/max(.1,desaturate)))*fog_opacity);
 }
 return float4(lerp(base,effect,saturate(threshold_fade)),input.color.a);
}

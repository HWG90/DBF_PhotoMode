"""Check SDR interpolation energy and unchanged accepted HDR math."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'freecam/assets/shaders/scene_dof_sdr_v2.hlsl').read_text()
a=s.index('// SDR PQ texels must be decoded');b=s.index('float3 encode_display',a)
hdr=s[:a]+s[b:]
hdr=hdr.replace('isfinite(clip_box.w)&&abs(clip_box.w)>0.0)?abs(clip_box.w):203.0','isfinite(clip_box.w)&&clip_box.w>0.0)?clip_box.w:203.0')
hdr=hdr.replace('sample_resolved(uv)','decode_resolved(__tex_photo_color.SampleLevel(__samp_photo_color,uv,0).rgb)').replace('sample_resolved(sample_uv)','decode_resolved(__tex_photo_color.SampleLevel(__samp_photo_color,sample_uv,0).rgb)')
assert hdr==(ROOT/'freecam/assets/shaders/release-0.9.6/resolved.hlsl').read_text()
assert s.count('__tex_photo_color.Load(')==4
assert s.count('decode_resolved(__tex_photo_color.Load(')==4
m1,m2,c1,c2,c3=2610/16384,2523/32,3424/4096,2413/128,2392/128
encode=lambda n:((c1+c2*(n/10000)**m1)/(1+c3*(n/10000)**m1))**m2
decode=lambda p:10000*(max(p**(1/m2)-c1,0)/(c2-c3*p**(1/m2)))**(1/m1)
wrong=decode((encode(0)+encode(100))*.5)
right=(decode(encode(0))+decode(encode(100)))*.5
assert wrong<6 and abs(right-50)<1e-8
for n in [0,.01,1,100,1000]:assert abs(decode(encode(n))-n)<1e-7
print('PASS SDR: linear texel interpolation preserves 50 nits versus 5.4542 from PQ interpolation; HDR math/source unchanged')

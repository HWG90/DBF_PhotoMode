"""Offline converter tests: channels, row pitch, float encoding, rejection, and atomic output."""
import ctypes
import json
import math
import struct
import tempfile
from pathlib import Path

from PIL import Image

root=Path(__file__).resolve().parents[2]
build=root/'dist/photo-capture-native'
metadata=json.loads((build/'photo-capture-native.json').read_text())
library=ctypes.CDLL(str(build/metadata['library']),use_last_error=True)
convert=library.PhotoDDSConvert
convert.argtypes=[ctypes.c_wchar_p,ctypes.c_wchar_p]
convert.restype=ctypes.c_int

def header(width,height,format,pitch):
    data=bytearray(148)
    fields={0:0x20534444,4:124,8:0x100f,12:height,16:width,20:pitch,28:1,
            76:32,80:4,84:0x30315844,108:0x1000,128:format,132:3,140:1}
    for offset,value in fields.items():struct.pack_into('<I',data,offset,value)
    return data

def srgb(value):
    if math.isnan(value) or value<=0:return 0
    if value>=1:return 255
    encoded=12.92*value if value<=0.0031308 else 1.055*value**(1/2.4)-0.055
    return math.floor(encoded*255+.5)

with tempfile.TemporaryDirectory(prefix='photo-native-test-') as directory:
    folder=Path(directory)
    tested=0
    def good(name,data,width,height,expected):
        global tested
        source=folder/(name+'.dds');output=folder/(name+'.png')
        source.write_bytes(data)
        assert convert(str(source),str(output))==1,(name,ctypes.get_last_error())
        image=Image.open(output).convert('RGBA')
        assert image.size==(width,height)
        pixels=[image.getpixel((x,y))for y in range(height)for x in range(width)]
        assert pixels==expected,(name,pixels,expected)
        assert source.read_bytes()==data,'Converter must preserve its input'
        tested+=1
    colors=[(255,0,0,0),(0,255,0,100),(0,0,255,1),(12,34,56,200)]
    expected=[(r,g,b,255)for r,g,b,_ in colors]
    for format in (28,29,87,91,88,93,27,90,92):
        pitch=20
        rows=[]
        for y in range(2):
            row=bytearray()
            for red,green,blue,alpha in colors[y*2:y*2+2]:
                row.extend((red,green,blue,alpha)if format in (28,29,27)else(blue,green,red,alpha))
            rows.append(row+bytearray(b'padding-data'))
        good('format-'+str(format),header(2,2,format,pitch)+b''.join(rows),2,2,expected)
    packed=[(1023,0,0),(0,1023,0),(0,0,1023),(51,300,700)]
    payload=b''.join(struct.pack('<I',red|(green<<10)|(blue<<20))for red,green,blue in packed)
    expected10=[tuple((value*255+511)//1023 for value in pixel)+(255,)for pixel in packed]
    for format in (24,23):
        good('10-bit-'+str(format),header(4,1,format,16)+payload,4,1,expected10)
    values=[(0,.0031308,.5),(1,float('nan'),float('inf')),(-float('inf'),2,-.1)]
    for format,code,bytes_per_pixel in ((10,'e',8),(2,'f',16),(9,'e',8),(1,'f',16)):
        payload=b''.join(struct.pack('<'+code*4,*pixel,0)for pixel in values)
        decoded=[struct.unpack('<'+code*4,payload[i*bytes_per_pixel:(i+1)*bytes_per_pixel])[:3]for i in range(3)]
        expected_float=[tuple(srgb(value)for value in pixel)+(255,)for pixel in decoded]
        good('float-'+str(format),header(3,1,format,3*bytes_per_pixel)+payload,3,1,expected_float)
    good('Grüße-Σ-猫',header(1,1,28,4)+bytes((12,34,56,0)),1,1,[(12,34,56,255)])
    source=folder/'existing.dds';output=folder/'existing.png'
    source.write_bytes(header(1,1,28,4)+bytes((12,34,56,0)));output.write_bytes(b'preserve-existing-output')
    assert convert(str(source),str(output))==0
    assert ctypes.get_last_error()==80 and output.read_bytes()==b'preserve-existing-output'
    bad=[('not-dds',b'not an image'),('short-payload',header(2,2,28,8)+b'\0'*4),
         ('unsupported',header(1,1,98,4)+b'\0'*4),('too-wide',header(16385,1,28,65540)),
         ('small-pitch',header(2,1,28,4)+b'\0'*8),('large-pitch',header(1,1,28,1000000)+b'\0'*4)]
    for name,offset,value in [('array',140,2),('volume',132,4),('one-dimensional',132,2),('missing-dimension',132,0),('mips',28,2),('cube',112,0x200),('wrong-magic',0,0)]:
        data=header(1,1,28,4)+b'\0'*4;struct.pack_into('<I',data,offset,value);bad.append((name,data))
    for name,data in bad:
        source=folder/(name+'.dds');output=folder/(name+'.png');source.write_bytes(data)
        assert convert(str(source),str(output))==0,name
        assert not output.exists(),name
    assert not list(folder.glob('*.tmp-*')),'All partial sibling files must be cleaned'
print(f'{tested} valid DDS conversions, {len(bad)} malformed/unsupported rejections, Unicode paths, input preservation, atomic no-overwrite, and temp cleanup passed')

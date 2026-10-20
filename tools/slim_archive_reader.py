"""Bounded read-only DSAR/DSAA access, following filediver's public format."""
from pathlib import Path
import struct,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'dist/analysis-deps'))
from lz4.block import decompress
DATA=Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data')
def chunks(path):
 with path.open('rb')as f:
  header=f.read(32);assert header[:4]==b'DSAR'
  count=struct.unpack_from('<I',header,8)[0];assert count<=1000000
  return list(struct.iter_unpack('<QQIIBB6x',f.read(count*32)))
def chunk_data(path,chunk):
 _,at,unpacked,packed,kind,_=chunk
 assert 0<unpacked<=128*1024*1024 and 0<packed<=128*1024*1024
 with path.open('rb')as f:f.seek(at);data=f.read(packed)
 if kind==3:data=decompress(data,uncompressed_size=unpacked)
 else:assert kind==0
 assert len(data)==unpacked;return data
def index():
 path=DATA/'bundles.nxa';body=b''.join(chunk_data(path,c)for c in chunks(path));assert body[:4]==b'DSAA'
 nxa_count,archive_count=struct.unpack_from('<II',body,12)
 def string(at):return body[at:body.index(b'\0',at)].decode()
 bundles=[string(struct.unpack_from('<I',body,24+archive_count*24+i*4)[0])for i in range(nxa_count)]
 archives={}
 for i in range(archive_count):
  size,name,count,at=struct.unpack_from('<QIIQ',body,24+i*24)
  archives[string(name)]={'size':size,'entries':list(struct.iter_unpack('<I4xI3xB',body[at:at+count*16]))}
 return bundles,archives
class Reader:
 def __init__(self,name,bundles,archives):
  self.entries=sorted(archives[name]['entries']);self.bundles=bundles;self.tables={};self.cache={}
 def read(self,offset,size):
  assert offset>=0 and 0<size<=64*1024*1024
  result=bytearray()
  while len(result)<size:
   address=offset+len(result)
   start,uncompressed,bundle=max((e for e in self.entries if e[0]<=address),key=lambda e:e[0])
   path=DATA/self.bundles[bundle]
   if bundle not in self.tables:self.tables[bundle]=chunks(path)
   target=uncompressed+address-start
   chunk=next(c for c in self.tables[bundle]if c[0]<=target<c[0]+c[2]);key=(bundle,chunk[0])
   if key not in self.cache:self.cache[key]=chunk_data(path,chunk)
   data=self.cache[key];local=target-chunk[0]
   assert local<len(data),'Archive chunk mapping gap'
   amount=min(size-len(result),len(data)-local)
   following=[e[0]for e in self.entries if e[0]>address]
   if following:amount=min(amount,min(following)-address)
   result.extend(data[local:local+amount])
  return bytes(result)
if __name__=='__main__':
 bundles,archives=index();print('Bundles:',len(bundles),'archives:',len(archives))
 for name in ('9ba626afa44a3aa3','ee6b1ba7e22d71ed'):
  a=archives.get(name);print(name,{'size':a['size'],'entries':len(a['entries'])}if a else 'not bundled')

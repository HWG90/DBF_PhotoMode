"""Build a small hash witness for the stock render graph; never changes game files."""
from pathlib import Path
import hashlib,json,struct,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'dist/analysis-deps'),str(ROOT/'../LLL/tools')]
from steam_resources import SteamResources,DSAR

def build(data):
 store=SteamResources(data);archive='ee6b1ba7e22d71ed';kind=0x27862fe24795319c
 resource=next(row for row in store.resources(archive)if row[0]==int(archive,16)and row[1]==kind)
 _,_,offset,length=resource;body=store.read(archive,offset,length)
 def u(at):return struct.unpack_from('<I',body,at)[0]
 def text(at):return body[at:body.index(0,at)].decode('utf-8')
 def decode(tag,value,depth=0):
  assert depth<=32
  if tag==6:
   count=u(value);assert count<=10000
   return{text(u(value+4+i*12)):decode(u(value+8+i*12),u(value+12+i*12),depth+1)for i in range(count)}
  if tag==5:
   item,count=u(value),u(value+4);assert count<=100000
   return[decode(item,u(value+8+i*4),depth+1)for i in range(count)]
  if tag==4:return text(value)
  if tag==3:return struct.unpack('<f',struct.pack('<I',value))[0]
  if tag==2:return value
  if tag==1:return bool(value)
  raise ValueError('Unknown config variant '+str(tag))
 graph=decode(u(0),u(4));targets=[]
 def walk(value):
  if isinstance(value,dict):
   if value.get('name')in ['output_target','linear_depth']:targets.append(value)
   for child in value.values():walk(child)
  elif isinstance(value,list):
   for child in value:walk(child)
 walk(graph['global_resources'])
 color=[t for t in targets if t['name']=='output_target'];depth=[t for t in targets if t['name']=='linear_depth']
 assert len(color)==2 and len(depth)==1
 assert all(t['type']=='render_target'and t['format']=='R16G16B16A16F'and t['depends_on']=='back_buffer'and t['w_scale']==1 and t['h_scale']==1 for t in color)
 assert depth[0]['format']=='R32F'
 copy_generator={'modifiers':[{'type':'fullscreen_pass','input':['gbuffer1'],'output':['gbuffer1_copy'],'shader':'copy'}]}
 assert graph['resource_generators']['gbuffer_normal_copy']==copy_generator,'GPU copy pass differs'
 checks={}
 index=Path(data)/'bundles.nxa';checks[(index.name,0,index.stat().st_size)]=hashlib.sha256(index.read_bytes()).hexdigest()
 file_length,count,table=store.files[archive]
 for i in range(count):
  start,packed=struct.unpack_from('<QQ',store.index,table+i*16);end=struct.unpack_from('<Q',store.index,table+(i+1)*16)[0]if i+1<count else file_length
  if end<=offset or start>=offset+length:continue
  bundle,physical=packed>>56,packed&0x00ffffffffffffff
  name=f'bundles.{bundle:02}.nxa';p=Path(data)/name;reader=DSAR(p)
  low=physical+max(start,offset)-start;high=physical+min(end,offset+length)-start
  for logical,at,raw,size,codec in reader.blocks:
   if logical+raw<=low or logical>=high:continue
   with p.open('rb')as f:f.seek(at);compressed=f.read(size)
   checks[(name,at,size)]=hashlib.sha256(compressed).hexdigest()
 assert len(checks)<=32 and sum(size for _,_,size in checks)<=16*1024*1024
 manifest={'version':1,'resource':archive,'resource_type':'27862fe24795319c','render_config_sha256':hashlib.sha256(body).hexdigest(),'color':color[0],'depth':depth[0],'copy_generator':copy_generator,
  'checks':[{'file':name,'offset':off,'size':size,'sha256':sha}for(name,off,size),sha in sorted(checks.items())]}
 manifest['id']=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 review=ROOT/'dist/review/windows-color-contract';review.mkdir(parents=True,exist_ok=True);(review/'VERIFIED-CONTRACT.json').write_text(json.dumps(manifest,indent=2)+'\n')
 def lua(v):
  if isinstance(v,dict):return'{'+','.join('['+json.dumps(k)+']='+lua(x)for k,x in v.items())+'}'
  if isinstance(v,list):return'{'+','.join(lua(x)for x in v)+'}'
  if isinstance(v,str):return json.dumps(v)
  if isinstance(v,bool):return'true'if v else'false'
  return str(v)
 (ROOT/'freecam/engine_render_contract.lua').write_text('-- Generated from read-only stock render_config and DSAR block witnesses.\nreturn '+lua(manifest)+'\n')
 return manifest
if __name__=='__main__':
 m=build(Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2_steam/data'));print(json.dumps({'id':m['id'],'checks':len(m['checks']),'bytes':sum(x['size']for x in m['checks'])}))

"""Generate the source-only Lua 5.1 lazy pose bank from the authored numeric asset.

Requires lupa.lua51 only at build/test time. Runtime decoding uses plain Lua 5.1.
No runtime, manifest, package, installed file or original asset is modified.
"""
from __future__ import annotations
import argparse
from hashlib import sha256
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'freecam/assets/subject_pose_frames.lua'
OUTPUT = ROOT / 'freecam/assets/steam_subject_poses.lua'
COUNT, FIRST, LAST, MAX_ROWS = 213, 8, 92, 8192

DECODER = r"""
local count,first,last=213,8,92
assert(type(rows)=='table'and #rows>0 and #rows<=8192,'Pose row pool bound')
assert(type(indices)=='table'and #indices==count,'Pose index count')
assert(type(full_body)=='string'and #full_body==count and full_body:match('^[01]+$'),'Pose body flags')
assert(type(catalog)=='table'and #catalog==count,'Pose catalog count')
local lookup={}
for i=1,count do
 local item=catalog[i];local encoded=indices[i]
 assert(type(item)=='table'and type(item.id)=='string'and #item.id>0 and #item.id<=64
  and item.id:match('^[a-z0-9_]+$')and not lookup[item.id],'Pose catalog identity')
 assert(type(item.label)=='string'and #item.label>0 and #item.label<=256,'Pose catalog label')
 assert(type(encoded)=='string'and #encoded==340 and encoded:match('^[0-9A-F]+$'),'Pose index shape')
 lookup[item.id]=i
end
local function parse_row(text,values)
 if type(text)~='string'or #text<19 or #text>320 or text:find('[^%d%+%-%.,eE]')
  or text:sub(1,1)==','or text:sub(-1)==','or text:find(',,',1,true)then return nil,'Invalid pose row encoding'end
 local n=0
 for token in text:gmatch('[^,]+')do
  n=n+1;if n>10 or #token>32 then return nil,'Pose row scalar bound'end
  local value=tonumber(token)
  if type(value)~='number'or value~=value or math.abs(value)>=1e8 then return nil,'Invalid pose row number'end
  values[n]=value
 end
 if n~=10 then return nil,'Pose row needs ten scalars'end
 local norm=values[4]^2+values[5]^2+values[6]^2+values[7]^2
 if math.abs(norm-1)>=.002 then return nil,'Pose quaternion normalization'end
 for i=8,10 do if math.abs(values[i]-1)>=.002 then return nil,'Pose unit scale'end end
 return true
end
local function decode(id)
 if type(id)~='string'or #id>64 then return nil,'Unknown subject pose'end
 local index=lookup[id];if not index then return nil,'Unknown subject pose'end
 local encoded=indices[index];local body=full_body:sub(index,index)
 if type(encoded)~='string'or #encoded~=340 or not encoded:match('^[0-9A-F]+$')or(body~='0'and body~='1')then
  return nil,'Invalid selected pose index'
 end
 local nodes,values={},{}
 for node=first,last do
  local offset=(node-first)*4+1;local row_id=tonumber(encoded:sub(offset,offset+3),16)
  if not row_id or row_id<1 or row_id>#rows or row_id>8192 then return nil,'Pose row index outside pool'end
  local ok,why=parse_row(rows[row_id],values);if not ok then return nil,why end
  nodes[node]={p={values[1],values[2],values[3]},q={values[4],values[5],values[6],values[7]},s={values[8],values[9],values[10]}}
 end
 return{full_body=body=='1',nodes=nodes}
end
return{version=1,rig=rig,catalog=catalog,decode=decode}
"""

def decimal(value: float) -> str:
    value=float(value)
    if not math.isfinite(value):
        raise ValueError('Nonfinite authored number')
    result=repr(value)
    # Keep negative zero, and use the shortest integer spelling for exact .0.
    return result[:-2] if result.endswith('.0') and value != 0 else result if value != 0 else ('-0.0' if math.copysign(1,value)<0 else '0')


def quote(text: str) -> str:
    # Current authored strings are ASCII; Lua 5.1 does not understand JSON \u.
    if not text.isascii():
        raise ValueError('Non-ASCII metadata requires an explicit Lua UTF-8 encoder')
    return json.dumps(text,ensure_ascii=False)


def plain(value):
    from lupa.lua51 import lua_type
    if lua_type(value)=='table':
        return {plain(key):plain(item) for key,item in value.items()}
    if isinstance(value,(str,bool,int,float)) or value is None:
        return value
    raise ValueError(f'Unsupported authored value {type(value)}')


def lua_literal(value) -> str:
    if isinstance(value,dict):
        keys=sorted(value,key=lambda key:(isinstance(key,str),key))
        return '{'+','.join('['+lua_literal(key)+']='+lua_literal(value[key]) for key in keys)+'}'
    if isinstance(value,str):return quote(value)
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,(int,float)):return decimal(value)
    raise ValueError('Unsupported Lua metadata')


def generate(source: Path=SOURCE) -> tuple[bytes,dict]:
    from lupa.lua51 import LuaRuntime
    raw=source.read_bytes();lua=LuaRuntime()
    assert lua.eval('_VERSION')=='Lua 5.1'
    # Only authored literal tables/IIFEs execute; no IO, loader or engine globals.
    load=lua.eval("function(s)local f=assert(loadstring(s,'authored pose data'));setfenv(f,{});return f()end")
    data=load(raw.decode('utf-8'))
    assert data['version']==1 and len(data['catalog'])==COUNT
    rig=plain(data['rig'])
    assert rig['resource']=='4d1c334d294dfa97' and rig['node_count']==107 and len(rig['nodes'])==107
    catalog=[];indices=[];flags=[];rows=[];intern={};ids=set()
    for i in range(1,COUNT+1):
        item=plain(data['catalog'][i]);identity=item['id']
        assert set(item)=={'id','label'} and identity not in ids and 0<len(identity)<=64 and 0<len(item['label'])<=256
        assert all(char in 'abcdefghijklmnopqrstuvwxyz0123456789_' for char in identity)
        ids.add(identity);catalog.append(item);pose=data['poses'][identity]
        assert pose is not None and type(pose['full_body']) is bool and pose['label']==item['label']
        flags.append('1' if pose['full_body'] else '0');encoded=[]
        for node in range(FIRST,LAST+1):
            row=pose['nodes'][node];assert row is not None
            values=tuple(float(row[key][j]) for key,n in (('p',3),('q',4),('s',3)) for j in range(1,n+1))
            assert all(math.isfinite(value) and abs(value)<1e8 for value in values)
            assert abs(sum(value*value for value in values[3:7])-1)<.002
            assert all(abs(value-1)<.002 for value in values[7:])
            packed=struct.pack('>10d',*values)
            if packed not in intern:
                text=','.join(decimal(value) for value in values);assert 19<=len(text)<=320
                rows.append(text);intern[packed]=len(rows)
            encoded.append(f'{intern[packed]:04X}')
        indices.append(''.join(encoded))
    assert len(list(data['poses'].keys()))==COUNT and len(rows)<=MAX_ROWS
    header=('-- Generated by tools/build_steam_pose_bank.py; do not edit encoded data.\n'
            '-- Source SHA256 '+sha256(raw).hexdigest()+'\n'
            '-- Startup retains interned strings and metadata only; decode allocates one fresh pose.\n')
    text=header+'local rig='+lua_literal(rig)+'\nlocal catalog={\n'
    text+=''.join(' '+lua_literal(item)+',\n' for item in catalog)+'}\nlocal full_body='+quote(''.join(flags))+'\nlocal indices={\n'
    text+=''.join(' '+quote(value)+',\n' for value in indices)+'}\nlocal rows={\n'
    text+=''.join(' '+quote(row)+',\n' for row in rows)+'}\n'+DECODER.lstrip()
    result=text.encode('utf-8')
    return result,{'catalog_entries':COUNT,'body_nodes':LAST-FIRST+1,'authored_bone_rows':COUNT*(LAST-FIRST+1),
        'interned_bone_rows':len(rows),'source_bytes':len(raw),'bank_bytes':len(result),'source_sha256':sha256(raw).hexdigest(),'bank_sha256':sha256(result).hexdigest()}


def benchmark() -> dict:
    from lupa.lua51 import LuaRuntime
    results={}
    for label,path in (('original',SOURCE),('bank',OUTPUT)):
        lua=LuaRuntime();lua.globals().path=path.as_posix();lua.globals().kind=label
        stats=lua.execute("""
collectgarbage('collect');local before=collectgarbage('count');local started=os.clock()
local data=dofile(path);local load_seconds=os.clock()-started
collectgarbage('collect');local loaded=collectgarbage('count');local stats={load_seconds=load_seconds,load_live_kib=loaded-before}
if kind=='bank'then
 started=os.clock();local selected=assert(data.decode(data.catalog[1].id));stats.decode_seconds=os.clock()-started
 collectgarbage('collect');stats.selected_live_kib=collectgarbage('count')-loaded
 selected=nil;collectgarbage('collect');local baseline=collectgarbage('count');started=os.clock()
 for _,entry in ipairs(data.catalog)do local pose=assert(data.decode(entry.id))end
 stats.decode_all_seconds=os.clock()-started;collectgarbage('collect');stats.after_all_live_kib=collectgarbage('count')-baseline
end
return stats
""")
        results[label]=dict(stats.items())
    assert results['bank']['load_live_kib']<results['original']['load_live_kib']*.25
    assert results['bank']['selected_live_kib']<128 and results['bank']['after_all_live_kib']<32
    return results


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true',help='Reject generated-byte drift without writing')
    parser.add_argument('--benchmark',action='store_true',help='Measure isolated Lua 5.1 heap/CPU; assert heap limits only')
    args=parser.parse_args();content,summary=generate()
    if args.check:
        assert OUTPUT.read_bytes()==content,'Lazy pose bank differs; regenerate it'
    else:
        OUTPUT.write_bytes(content)
    # A second independent VM validates deterministic numeric parsing/intern order.
    assert generate()[0]==content,'Pose bank generation is nondeterministic'
    summary['checked']=args.check;summary['deterministic']=True
    if args.benchmark:summary['benchmark']=benchmark()
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()

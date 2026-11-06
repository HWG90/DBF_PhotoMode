"""Convert a stock Helldiver replacement animation into one War Journalist saved pose."""
import argparse
from pathlib import Path
from lupa.lua51 import LuaRuntime
from photo_assets import archive_index

ROOT = Path(__file__).resolve().parents[1]
ANIMATION = 0x931E336D7646CC26
# Channel numbers for scene nodes 8..92 in the stock 107-node Helldiver rig.
CHANNELS = [3,6,5,22,58,21,19,31,84,26,25,11,32,85,4,55,27,69,45,7,64,8,56,72,82,30,29,50,42,43,53,51,49,47,54,10,71,12,62,16,18,20,48,60,87,52,75,88,44,74,89,57,66,90,59,61,86,76,9,65,13,46,14,36,15,41,78,77,40,80,79,39,73,81,38,68,70,17,24,37,63,67,33,35,34]


def clip_bytes(path, resource):
    data = path.read_bytes()
    if path.suffix == '.bin':
        return data
    def size(suffix):
        sibling = Path(str(path) + suffix)
        return sibling.stat().st_size if sibling.exists() else 0
    rows = [r for r in archive_index(data, size('.gpu_resources'), size('.stream')) if r[1] == ANIMATION]
    if resource is not None:
        rows = [r for r in rows if r[0] == resource]
    if len(rows) != 1:
        raise ValueError('Select one animation with --resource. Matches: ' + ', '.join(f'{r[0]:016x}' for r in rows))
    row = rows[0]
    if row[8] or row[9]:
        raise ValueError('This animation requires external stream or GPU data')
    return data[row[2]:row[2]+row[7]]


def convert(data, seconds, label):
    lua = LuaRuntime(encoding=None)
    decoder = (ROOT/'tools/subject_pose_decoder.lua').read_bytes().rstrip()
    assert decoder.endswith(b'return Clip')
    sample = lua.execute(decoder[:-len(b'return Clip')] + b"""
return function(data,t,map)
 assert(#data<=Clip.MAX_BYTES,'Animation exceeds size limit')
 local clip=animation(data,90)
 assert(t>=0 and t<=clip.duration,'Sample time outside clip')
 local frame={nodes={}}
 for i,b in ipairs(map) do
  local c=clip.channels[b]
  frame.nodes[i+7]={p=curve(c.p,t),q=curve(c.q,t,true),s=curve(c.s,t)}
 end
 return frame
end""")
    files = lua.execute((ROOT/'freecam/pose_files.lua').read_bytes())
    frame = sample(data, seconds, lua.table_from(CHANNELS))
    result = files[b'encode'](frame, lua.table_from({b'label':label.encode(), b'source':b'emote'}))
    if isinstance(files[b'decode'](result),tuple):
        raise ValueError('Converted pose failed the in-game file checks')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path, help='Unpacked mod .patch_N or extracted animation .bin')
    parser.add_argument('output', type=Path, help='New wj-pose-NN.txt file')
    parser.add_argument('--resource', type=lambda s:int(s,16), help='Animation resource hash in a multi-clip patch')
    parser.add_argument('--time', type=float, default=0, help='Seconds from the start of the clip')
    parser.add_argument('--label', default='Converted emote')
    args = parser.parse_args()
    payload = convert(clip_bytes(args.input,args.resource),args.time,args.label)
    with args.output.open('xb') as output:
        output.write(payload)

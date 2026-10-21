"""Hot-update one portable module through LLL's supported cleanup/reload path."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import zipfile
from verify_installed_modules import audit

ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def update(candidate,review):
    candidate=candidate.resolve();review=review.resolve()
    assert candidate.is_relative_to(ROOT/'dist/review')and review.is_relative_to(ROOT/'dist/review')
    target=(Path(os.environ['LOCALAPPDATA'])/'LLL/Helldivers2/Mods/dbf_freecam').resolve()
    assert audit(candidate)['passed']and audit(target)['passed']
    assert (candidate/'main.lua').read_bytes()==(target/'main.lua').read_bytes(),'Entry change requires closed installation'
    assert (candidate/'manifest.json').read_bytes()==(target/'manifest.json').read_bytes(),'Module graph change requires closed installation'
    expected={}
    for row in (candidate/'FILES-SHA256.txt').read_text().splitlines():
        digest,name=row.split('  ',1);path=(candidate/name).resolve()
        assert path.is_relative_to(candidate)and sha(path)==digest
        expected[name]=digest
    changed=[name for name,value in expected.items()if sha(target/name)!=value]
    lua=[name for name in changed if name.endswith('.lua')]
    assert len(lua)<=1,'Multiple module changes require a closed installation'
    review.mkdir(parents=True,exist_ok=True)
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    rollback=review/('hot-rollback-'+stamp+'.zip')
    with zipfile.ZipFile(rollback,'x',zipfile.ZIP_DEFLATED)as archive:
        for name in [*changed,'FILES-SHA256.txt']:archive.write(target/name,name)
    # The single watched module is replaced last. LLL can then acquire one
    # complete new snapshot and invoke the old entry's supported on_disable.
    for name in [*[n for n in changed if n not in lua],'FILES-SHA256.txt',*lua]:
        destination=(target/name).resolve();assert destination.is_relative_to(target)
        temporary=destination.with_name(destination.name+'.steam-stage')
        temporary.write_bytes((candidate/name).read_bytes());os.replace(temporary,destination)
    report=audit(target);assert report['passed']
    for name,value in expected.items():assert sha(target/name)==value,name
    receipt={'updated':changed,'rollback':str(rollback),'module_audit':report,'expected_sha256':expected,
             'loader_acknowledgement':'pending','live_gameplay':'pending'}
    (review/('HOT-DEPLOYMENT-'+stamp+'.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('--review',type=Path,default=ROOT/'dist/review/steam-lua51/deployment')
    args=parser.parse_args();result=update(args.candidate,args.review)
    print(json.dumps({k:result[k]for k in ('updated','rollback','loader_acknowledgement')},indent=2))

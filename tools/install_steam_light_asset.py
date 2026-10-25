"""Install the owned light-only patch beside LLL, with game closed and rollback."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import zipfile

from install_steam_candidate import game_closed
import photo_assets
import photo_light_assets

ROOT=Path(__file__).resolve().parents[1]
DATA=Path(r'C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2_steam/data')
NAME='9ba626afa44a3aa3.patch_1'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def install(candidate,review):
    game_closed()
    candidate=candidate.resolve();review=review.resolve()
    assert candidate.is_relative_to(ROOT/'dist/review') and review.is_relative_to(ROOT/'dist/review')
    files=[NAME,NAME+'.gpu_resources',NAME+'.stream']
    source=candidate/'Assets'
    assert photo_assets.read_archive((source/NAME).read_bytes(),
        (source/(NAME+'.gpu_resources')).read_bytes(),(source/(NAME+'.stream')).read_bytes())==photo_light_assets.resources()
    expected={name:sha(source/name)for name in files}
    target={name:DATA/name for name in files}
    assert DATA.is_dir() and all(p.resolve().parent==DATA.resolve() for p in target.values())
    for name,path in target.items():
        assert not path.exists() or sha(path)==expected[name],f'Another owner already uses {path}'
    loader=DATA/'9ba626afa44a3aa3.patch_0'
    assert loader.is_file(),'LLL boot patch is missing'
    loader_hash=sha(loader)
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    review.mkdir(parents=True,exist_ok=True)
    rollback=review/('light-rollback-'+stamp+'.zip')
    assert not rollback.exists()
    prior={name:path.read_bytes() if path.exists()else None for name,path in target.items()}
    with zipfile.ZipFile(rollback,'w',zipfile.ZIP_DEFLATED)as archive:
        archive.writestr('STATE.json',json.dumps({name:body is not None for name,body in prior.items()}))
        for name,body in prior.items():
            if body is not None:archive.writestr(name,body)
    changed=[]
    try:
        # Resource payload is published last, after its empty sidecars.
        for name in files[1:]+files[:1]:
            game_closed()
            path=target[name]
            if path.exists():continue
            temporary=path.with_name(path.name+'.photo-stage')
            assert not temporary.exists(),'Staging file already exists'
            try:
                shutil.copyfile(source/name,temporary)
                assert sha(temporary)==expected[name]
                os.replace(temporary,path);changed.append(name)
            finally:
                if temporary.exists():temporary.unlink()
        assert all(sha(target[name])==expected[name]for name in files)
        assert sha(loader)==loader_hash,'LLL boot patch changed during installation'
    except BaseException:
        for name in reversed(changed):
            path=target[name]
            if path.exists()and sha(path)==expected[name]:path.unlink()
        raise
    result={'installed':True,'files_sha256':expected,'lll_boot_sha256':loader_hash,
        'rollback_zip':str(rollback),'loader_activation':'restart required',
        'native_light_readback':'pending','visible_illumination':'pending'}
    (review/'LIGHT-DEPLOYMENT.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--review',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(install(args.candidate,args.review),indent=2))

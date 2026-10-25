"""Scoped, game-closed installation with rollback, byte hashes and module audit."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import uuid
import zipfile

from verify_installed_modules import audit

ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def game_closed():
    result=subprocess.run(['powershell.exe','-NoProfile','-Command',
                           'if (Get-Process helldivers2 -ErrorAction SilentlyContinue) { exit 9 }'],capture_output=True)
    assert result.returncode==0,'Close Helldivers 2 before scoped installation'

def install(candidate,review):
    game_closed()
    candidate=candidate.resolve();review=review.resolve()
    assert review.is_relative_to(ROOT/'dist/review')
    assert audit(candidate)['passed'],'Invalid candidate modules'
    expected={}
    for row in (candidate/'FILES-SHA256.txt').read_text().splitlines():
        value,name=row.split('  ',1);p=(candidate/name).resolve()
        assert p.is_relative_to(candidate)and digest(p)==value,name
        expected[name]=value
    base=Path(os.environ['LOCALAPPDATA'])/'LLL/Helldivers2'
    target=(base/'Mods/dbf_freecam').resolve()
    assert target.parent==(base/'Mods').resolve()and target.name=='dbf_freecam'
    review.mkdir(parents=True,exist_ok=True)
    stamp=datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
    backup=base/'Backups'/('War-Journalist-before-steam51-'+stamp)
    stage=base/'Staging'/('War-Journalist-steam51-'+stamp)
    assert not backup.exists()and not stage.exists()
    stage.parent.mkdir(parents=True,exist_ok=True);backup.parent.mkdir(parents=True,exist_ok=True)
    shutil.copytree(candidate,stage)
    rollback=review/('rollback-'+stamp+'.zip')
    with zipfile.ZipFile(rollback,'w',zipfile.ZIP_DEFLATED)as archive:
        if target.exists():
            for p in target.rglob('*'):
                if p.is_file():archive.write(p,'dbf_freecam/'+p.relative_to(target).as_posix())
    game_closed()
    if target.exists():target.rename(backup)
    try:stage.rename(target)
    except BaseException:
        if backup.exists()and not target.exists():backup.rename(target)
        raise
    # User-authored presets and captures are never part of package bytes.
    preserved=[]
    for name in ('director-shots.ini','director-shots.ini.bak','lighting-presets.ini','Screenshots'):
        old=backup/name
        if old.is_file()and not(target/name).exists():
            shutil.copy2(old,target/name);preserved.append(name)
        elif old.is_dir():
            shutil.copytree(old,target/name,dirs_exist_ok=True);preserved.append(name+'/')
    migrated=None
    settings=base/'Settings/dbf_freecam/dbf_freecam.ini'
    if not settings.exists():
        for old in (base/'Settings/dbf_mcm/dbf_freecam.ini',base.parent/'Helldivers2backup/Settings/dbf_mcm/dbf_freecam.ini'):
            if old.is_file():
                settings.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(old,settings)
                migrated={'source':str(old),'target':str(settings),'sha256':digest(settings)};break
    report=audit(target)
    assert report['passed'],report['errors']
    for name,value in expected.items():assert digest(target/name)==value,name
    result={'installed':str(target),'backup_directory':str(backup),'rollback_zip':str(rollback),
            'rollback_sha256':digest(rollback),'module_audit':report,'file_sha256':expected,'settings_migration':migrated,'preserved_user_paths':preserved,
            'loader_activation':'not yet verified','live_gameplay':'not yet verified','full_feature_parity':'pending'}
    (review/'DEPLOYMENT.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',type=Path,default=ROOT/'dist/review/steam-lua51/package/candidate/dbf_freecam')
    parser.add_argument('--review',type=Path,default=ROOT/'dist/review/steam-lua51/deployment')
    args=parser.parse_args();result=install(args.candidate,args.review)
    print(json.dumps({k:result[k]for k in ('installed','rollback_zip','loader_activation','live_gameplay')},indent=2))

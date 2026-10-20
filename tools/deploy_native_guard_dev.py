"""Install the authorized Native/animation guard dev build with reversible backups."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.9-dev.20261013.3'
NAME = 'War-Journalist-0.9-Dev-20261013-3'
CANDIDATE = ROOT / 'dist/releases' / NAME
MOD = Path('C:/Users/david/AppData/Local/LLL/Helldivers2/Mods/dbf_freecam').resolve()
GAME = Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data').resolve()
ARSENAL = Path('C:/Users/david/AppData/Local/hd2arsenal/mods/War-Journalist-Scene-Depth-Candidate-Assets_AR192158').resolve()
assert MOD.as_posix().endswith('/LLL/Helldivers2/Mods/dbf_freecam')
assert GAME.as_posix().endswith('/Helldivers 2/data')
assert (ARSENAL / 'manifest.json').is_file()
assert json.loads((CANDIDATE / 'PACKAGE-VALIDATION.json').read_text())['passed']
provenance = json.loads((CANDIDATE / 'PROVENANCE.json').read_text())
assert provenance['native_profile_instances_supported']
assert provenance['animation_graph_guard_sites'] == 7
runtime = (CANDIDATE / 'Runtime/dbf_freecam/src/actioncam.lua').read_bytes()
assert runtime.count(b'pcall(H.dbf_animation_get_state,') == 7
assert b'pcall(sr.Unit.animation_get_state,' not in runtime
sha = lambda body: hashlib.sha256(body).hexdigest()
assert sha(runtime) == provenance['runtime_sha256']
BACKUP = ROOT / 'dist/deployment-backups' / ('native-guard-20261013-' + datetime.datetime.now().strftime('%H%M%S'))
BACKUP.mkdir(parents=True)
rows = []
retained_game_files = []

def install(target, body, category, relative, boundary):
    assert target.resolve().is_relative_to(boundary)
    changed = not target.exists() or target.read_bytes() != body
    if changed:
        if target.exists():
            backup = BACKUP / category / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
        target.parent.mkdir(parents=True, exist_ok=True)
        staged = target.with_name(target.name + '.dev-pending')
        staged.write_bytes(body)
        staged.replace(target)
    assert target.read_bytes() == body
    rows.append({'category': category, 'name': relative, 'sha256': sha(body), 'changed': changed})

for path in sorted((CANDIDATE / 'Runtime/dbf_freecam').rglob('*')):
    if path.is_file():
        relative = path.relative_to(CANDIDATE / 'Runtime/dbf_freecam').as_posix()
        install(MOD / relative, path.read_bytes(), 'Runtime', relative, MOD)
with zipfile.ZipFile(CANDIDATE / 'War-Journalist-Native-Legend-Assets.zip') as archive:
    assert archive.testzip() is None
    for name in sorted(archive.namelist()):
        if name in ('manifest.json', 'FILES-SHA256.txt', 'ASSET-RECEIPT.json') or name.startswith('Assets/'):
            install(ARSENAL / name, archive.read(name), 'Arsenal', name, ARSENAL)
        if name.startswith('Assets/'):
            game_name = Path(name).name.replace('9ba626afa44a3aa3.patch_0', '9ba626afa44a3aa3.patch_83')
            target = (GAME / game_name).resolve()
            assert target.is_relative_to(GAME)
            # Arsenal owns merged game archives. A runtime-only fix must never
            # replace them with an unmerged Photo asset archive.
            assert target.is_file(), 'Deploy missing shader assets through Arsenal first'
            retained_game_files.append({'name': game_name, 'sha256': sha(target.read_bytes()),
                                        'matches_photo_asset': target.read_bytes() == archive.read(name)})
assert (MOD / 'src/actioncam.lua').read_bytes() == runtime
assert json.loads((MOD / 'manifest.json').read_text())['version'] == VERSION
receipt = {'version': VERSION, 'installed': True, 'runtime_sha256': sha(runtime),
           'arsenal_photo_asset_source_verified': True, 'existing_game_archives_retained': True,
           'retained_game_files': retained_game_files, 'backup': str(BACKUP), 'files': rows,
           'saved_settings_written': False, 'game_restarted': False,
           'native_instance_fix_previous_live_user_verified': True,
           'animation_guard_previous_live_user_test_no_crash': True,
           'installed_full_build_live_verified': False,
           'hoverpack_zero_step_fixed': False}
(CANDIDATE / 'DEPLOYMENT-RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

borrow = ROOT / 'dist/releases' / (NAME + '-Borrow.zip')
assert not borrow.exists(), 'Preserve previous borrow archive'
files = {}
for loader in ('LLL', 'BSL'):
    body = (CANDIDATE / ('War-Journalist-Native-Legend-' + loader + '.zip')).read_bytes()
    filename = NAME + '-' + loader + '.zip'
    (CANDIDATE / filename).write_bytes(body)
    files[filename] = body
files['README.txt'] = b'''WAR JOURNALIST 0.9 DEVELOPMENT BUILD - 20261013.3

Choose ONE loader package: LLL or BSL. Both include the required shader assets.
LLL: install dbf_freecam in LLL Mods and deploy the included Arsenal assets.
BSL: import the full BSL ZIP, enable and deploy. MCM and Links are optional.
Restart normally after installation.

Includes the Native instanced-camera-profile acquisition fix and guards on all
seven Photo animation-state reads during respawn/ragdoll. The equivalent live
fix responded to focus/aperture and passed a user ragdoll/respawn check.
The approved compositor, menu and other existing dev features are retained.
43 isolated fixture groups and both standalone packaged bootstraps passed.
The complete newly installed build still needs normal-startup acceptance.

Includes held-input release on entry and exit. The native hoverpack hook was
withdrawn after a live crash and is excluded. A data-only hover pause candidate
neutralizes automatic thrust before zero time and restores it after resume.
It refuses the hover pause with connected or unidentified controllers.
Full crash-reproduction acceptance is pending. Mission photo-light availability remains
in development. This is a 0.9 dev candidate, not 0.9.5 RC1.
No logs, captures, saved settings or game binaries are included.
'''
files['FILES-SHA256.txt'] = ''.join(sha(body) + '  ' + name + '\n' for name, body in sorted(files.items())).encode()
with zipfile.ZipFile(borrow, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, body in files.items():
        archive.writestr(name, body)
with zipfile.ZipFile(borrow) as archive:
    assert archive.testzip() is None
    assert {name: archive.read(name) for name in archive.namelist()} == files
print(json.dumps({'version': VERSION, 'runtime_sha256': sha(runtime), 'installed_files': len(rows),
                  'changed_files': sum(row['changed'] for row in rows),
                  'game_asset_changes': sum(row['changed'] for row in rows if row['category'] == 'Game'),
                  'borrow_zip': str(borrow), 'borrow_sha256': sha(borrow.read_bytes()),
                  'backup': str(BACKUP)}, indent=2))

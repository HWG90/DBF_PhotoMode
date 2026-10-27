"""Stage the immutable menu review on disk without touching the active game."""
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'dist/releases/photo-menu-reopen-review'
LIVE = (Path.home() / 'AppData/Local/LLL/Helldivers2/Mods/dbf_freecam').resolve()
ARSENAL = (Path.home() / 'AppData/Local/hd2arsenal/mods/War-Journalist-DoF-Assets-Candidate_AR595142').resolve()
GAME_DATA = Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/data').resolve()
PREFERENCES = (Path.home() / 'AppData/Local/DBF/PhotoMode/settings/dbf_freecam.ini')
LLL_SHA = 'b0f4840535bf9482941268b6e406f828776f3b8b6d77aa19399b675614a09867'
BSL_SHA = 'b193b674f77fd11de2a7d2a35e7da44f9f6b443b70889128155a147026d2f060'
ASSET_SHA = '55dc61ebb6cb264aaae3138ebd047f174e12e398f1e2acb81867354758241aed'
ALLOWED_CHANGES = {'src/actioncam.lua', 'PROVENANCE.json', 'SOURCE-PROVENANCE.json',
                   'manifest.json', 'INSTALL.txt', 'FILES-SHA256.txt'}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def current(path):
    return path.read_bytes() if path.is_file() else None


def checked_path(folder, name):
    entry = PurePosixPath(name)
    assert not entry.is_absolute() and '..' not in entry.parts and '\\' not in name
    target = (folder / name).resolve()
    assert target.is_relative_to(folder) and target != folder
    return target


def archive(path, digest):
    assert sha(path.read_bytes()) == digest, 'Archive identity changed: ' + str(path)
    with zipfile.ZipFile(path) as zipped:
        assert zipped.testzip() is None
        assert len(zipped.namelist()) == len(set(zipped.namelist()))
        return {name: zipped.read(name) for name in zipped.namelist()}


def atomic_write(path, body):
    temporary = path.with_name('.' + path.name + '.menu-' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('xb') as stream:
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        assert temporary.read_bytes() == body
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def main():
    package = archive(REVIEW / 'War-Journalist-Menu-Reopen-LLL.zip', LLL_SHA)
    archive(REVIEW / 'War-Journalist-Menu-Reopen-BSL.zip', BSL_SHA)
    asset_name = 'War-Journalist-Fullres-Bokeh-Candidate-Assets.zip'
    assets = archive(REVIEW / asset_name, ASSET_SHA)
    assert package['Arsenal/' + asset_name] == (REVIEW / asset_name).read_bytes()
    manifest = json.loads(assets['manifest.json'])
    assert manifest['Guid'] == 'fd8637c5-b38f-488a-91e5-b3ba5f27a7df'
    assert manifest['Options'] == [{'Name': 'DoF shader assets and registry', 'Include': ['Assets']}]
    mapping = json.loads((REVIEW / 'INSTALL-MAP.json').read_text())
    assert Path(mapping['runtime_target']).resolve() == LIVE
    assert {name for name, item in mapping['files'].items() if item['changed']} == ALLOWED_CHANGES
    changes, protected = [], []
    for name, item in mapping['files'].items():
        target = checked_path(LIVE, name)
        assert target == Path(item['target']).resolve()
        before = current(target)
        assert (sha(before) if before is not None else None) == item['before_sha256'], 'Runtime prehash changed: ' + name
        body = package['dbf_freecam/' + name]
        assert sha(body) == item['after_sha256']
        assert (REVIEW / item['source']).read_bytes() == body
        if item['changed']:
            assert name in ALLOWED_CHANGES and before is not None and before != body
            changes.append({'name': name, 'target': target, 'before': before, 'after': body})
        else:
            assert before == body
            protected.append((target, before))
    # These exact asset bytes already provide the working cached shader. Verify,
    # then leave both the Arsenal source and installed game archives untouched.
    asset_entries = {name: body for name, body in assets.items() if name.startswith('Assets/')}
    assert len(asset_entries) == 6
    for name, body in asset_entries.items():
        source = checked_path(ARSENAL, name)
        game_name = PurePosixPath(name).name.replace('ee6b1ba7e22d71ed.patch_0', 'ee6b1ba7e22d71ed.patch_1').replace('9ba626afa44a3aa3.patch_0', '9ba626afa44a3aa3.patch_62')
        for target in (source, checked_path(GAME_DATA, game_name)):
            assert target.read_bytes() == body, 'Installed asset differs: ' + str(target)
            protected.append((target, body))
    preferences_before = current(PREFERENCES)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    backup = ROOT / 'dist/deployment-backups' / ('photo-menu-reopen-stage-' + stamp)
    backup.mkdir(parents=True)
    records = []
    for item in changes:
        path = backup / 'before/dbf_freecam' / item['name']
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(item['before'])
        assert path.read_bytes() == item['before']
        records.append({'file': item['name'], 'target': str(item['target']),
                        'before_sha256': sha(item['before']), 'after_sha256': sha(item['after']),
                        'backup': str(path)})
    receipt = {'status': 'prepared', 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
               'lll_zip_sha256': LLL_SHA, 'bsl_zip_sha256': BSL_SHA, 'asset_zip_sha256': ASSET_SHA,
               'asset_guid': manifest['Guid'], 'asset_option': manifest['Options'][0]['Name'],
               'backup': str(backup), 'files': records, 'unchanged_runtime_files': len(mapping['files']) - len(changes),
               'unchanged_asset_files': 12, 'atomic_writes': True, 'rollback_on_failure': True,
               'assets_modified': False, 'dlls_modified': False, 'preferences_modified': False,
               'preferences_file_existed': preferences_before is not None,
               'game_process_accessed': False, 'reload_requested': False, 'game_restarted': False,
               'bsl_installed': False, 'live_menu_reopen_verified': False, 'normal_restart_required': True}
    receipt_path = backup / 'STAGING-RECEIPT.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    applied = []
    try:
        for target, before in protected:
            assert current(target) == before, 'Protected file changed before staging: ' + str(target)
        assert current(PREFERENCES) == preferences_before
        for item in changes:
            assert current(item['target']) == item['before'], 'Runtime changed after backup: ' + item['name']
        for item in changes:
            assert current(item['target']) == item['before'], 'Runtime changed before write: ' + item['name']
            atomic_write(item['target'], item['after'])
            applied.append(item)
            assert current(item['target']) == item['after']
        for target, before in protected:
            assert current(target) == before, 'Protected file changed during staging: ' + str(target)
        assert current(PREFERENCES) == preferences_before
    except Exception as error:
        failures = []
        for item in reversed(applied):
            try:
                atomic_write(item['target'], item['before'])
                assert current(item['target']) == item['before']
            except Exception as rollback_error:
                failures.append({'target': str(item['target']), 'error': str(rollback_error)})
        receipt.update(status='rolled back' if not failures else 'rollback needs attention',
                       error=str(error), rollback_failures=failures)
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        raise
    receipt.update(status='staged on disk; awaiting normal restart',
                   runtime_files_verified=len(mapping['files']), changed_runtime_files=len(changes),
                   runtime_sha256=sha(package['dbf_freecam/src/actioncam.lua']),
                   active_runtime='Existing cached runtime retained; new menu recovery not live-tested')
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    (REVIEW / 'STAGING-RECEIPT.json').write_bytes(receipt_path.read_bytes())
    print(json.dumps({'status': receipt['status'], 'runtime_sha256': receipt['runtime_sha256'],
                      'changed_runtime_files': len(changes), 'runtime_files_verified': len(mapping['files']),
                      'unchanged_asset_files': 12, 'backup': str(backup), 'receipt': str(receipt_path),
                      'assets_modified': False, 'dlls_modified': False, 'preferences_modified': False,
                      'reload_requested': False}, indent=2))


if __name__ == '__main__':
    main()

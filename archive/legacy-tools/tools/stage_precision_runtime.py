"""Stage guarded Photo/MCM text payloads; never reload or restart the game."""
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PHOTO = ROOT / 'dist/releases/photo-focus-precision-review'
MCM = ROOT.parent / 'DBF-MCM/dist/releases/numeric-blur-installed-base-review'
MODS = (Path.home() / 'AppData/Local/LLL/Helldivers2/Mods')
PHOTO_ZIP_SHA = '61089223100fe4e7560184ac3aa47d3b67145d8a24ca1cd147e79460e5eae622'
MCM_ZIP_SHA = '22e81578a73bec7c57418efa439b6d122f66fcfaddde851b9a94b4daff441ec9'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def current(path):
    return path.read_bytes() if path.is_file() else None


def checked_target(mod, name):
    entry = PurePosixPath(name)
    assert not entry.is_absolute() and '..' not in entry.parts and '\\' not in name
    folder = (MODS / mod).resolve()
    target = (folder / name).resolve()
    assert target.is_relative_to(folder) and target != folder
    return target


def archive_files(path, digest):
    assert sha(path.read_bytes()) == digest, 'Package identity changed: ' + str(path)
    with zipfile.ZipFile(path) as zipped:
        assert zipped.testzip() is None and len(zipped.namelist()) == len(set(zipped.namelist()))
        return {name: zipped.read(name) for name in zipped.namelist()}


def atomic_write(path, body):
    temporary = path.with_name('.' + path.name + '.precision-' + uuid.uuid4().hex + '.tmp')
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
    photo_files = archive_files(PHOTO / 'War-Journalist-Focus-Precision-LLL.zip', PHOTO_ZIP_SHA)
    mcm_files = archive_files(MCM / 'DBF-MCM-Numeric-Blur-Installed-Base-Review.zip', MCM_ZIP_SHA)
    photo_map = json.loads((PHOTO / 'INSTALL-MAP.json').read_text())
    mcm_receipt = json.loads((MCM / 'MERGE-RECEIPT.json').read_text())
    allowed_photo = {'FILES-SHA256.txt', 'INSTALL.txt', 'PROVENANCE.json', 'SOURCE-PROVENANCE.json',
        'VENDOR-PROVENANCE.json', 'manifest.json', 'src/actioncam.lua', 'src/vendor/core.lua'}
    allowed_mcm = {'src/core.lua', 'src/menu.lua', 'src/ui/input.lua', 'src/ui/render.lua'}
    assert set(photo_map['changed_runtime_files']) == allowed_photo
    assert {item['file'] for item in mcm_receipt['files']} == allowed_mcm
    assert set(mcm_files) == {'dbf_mcm/' + name for name in allowed_mcm}
    changes, protected = [], []
    for name, item in photo_map['all_runtime_files'].items():
        target = checked_target('dbf_freecam', name)
        assert target == Path(item['target']).resolve()
        before = current(target)
        assert (sha(before) if before is not None else None) == item['before_sha256'], 'Photo prehash changed: ' + name
        body = photo_files['dbf_freecam/' + name]
        assert sha(body) == item['after_sha256']
        if name in allowed_photo:
            changes.append({'mod': 'dbf_freecam', 'name': name, 'target': target, 'before': before, 'after': body})
        else:
            assert before == body
            protected.append((target, sha(body)))
    for item in mcm_receipt['files']:
        name = item['file']
        target = checked_target('dbf_mcm', name)
        before = current(target)
        body = mcm_files['dbf_mcm/' + name]
        assert before is not None and sha(before) == item['before_sha256'], 'MCM prehash changed: ' + name
        assert sha(body) == item['candidate_sha256']
        changes.append({'mod': 'dbf_mcm', 'name': name, 'target': target, 'before': before, 'after': body})
    for name, digest in mcm_receipt['protected_identity_before'].items():
        target = checked_target('dbf_mcm', name)
        assert sha(target.read_bytes()) == digest, 'Protected MCM identity changed: ' + name
        protected.append((target, digest))
    assert len(changes) == 12 and all(item['before'] != item['after'] for item in changes)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    backup = ROOT / 'dist/deployment-backups' / ('photo-focus-precision-stage-' + stamp)
    backup.mkdir(parents=True)
    records = []
    for item in changes:
        path = backup / 'before' / item['mod'] / item['name']
        if item['before'] is not None:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(item['before'])
            assert path.read_bytes() == item['before']
        records.append({'mod': item['mod'], 'name': item['name'], 'target': str(item['target']),
            'existed_before': item['before'] is not None, 'before_sha256': sha(item['before']) if item['before'] is not None else None,
            'after_sha256': sha(item['after']), 'backup': str(path) if item['before'] is not None else None})
    receipt = {'status': 'prepared', 'photo_zip_sha256': PHOTO_ZIP_SHA, 'mcm_zip_sha256': MCM_ZIP_SHA,
        'files': records, 'protected_files_checked': len(protected), 'atomic_writes': True,
        'rollback_on_failure': True, 'reload_requested': False, 'game_restarted': False,
        'game_process_accessed': False, 'preferences_modified': False, 'assets_modified': False, 'dlls_modified': False}
    receipt_path = backup / 'STAGING-RECEIPT.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    applied = []
    try:
        # Recheck every input immediately before mutation, after backup creation.
        for item in changes:
            assert current(item['target']) == item['before'], 'Target changed after backup: ' + item['name']
        for item in changes:
            atomic_write(item['target'], item['after'])
            applied.append(item)
            assert item['target'].read_bytes() == item['after']
        for target, digest in protected:
            assert sha(target.read_bytes()) == digest, 'Protected file changed during stage: ' + str(target)
    except Exception as error:
        failures = []
        for item in reversed(applied):
            try:
                if item['before'] is None:
                    item['target'].unlink()
                else:
                    atomic_write(item['target'], item['before'])
                assert current(item['target']) == item['before']
            except Exception as rollback_error:
                failures.append({'target': str(item['target']), 'error': str(rollback_error)})
        receipt.update(status='rolled back' if not failures else 'rollback needs attention',
            error=str(error), rollback_failures=failures)
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        raise
    receipt.update(status='staged on disk; awaiting normal restart', installed_files_sha256_verified=12,
        active_runtime='Existing cached runtime retained; new precision code not live-verified')
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    (PHOTO / 'STAGING-RECEIPT.json').write_bytes(receipt_path.read_bytes())
    print(json.dumps({'status': receipt['status'], 'verified_files': 12, 'backup': str(backup),
        'receipt': str(receipt_path), 'reload_requested': False, 'preferences_modified': False,
        'assets_modified': False, 'dlls_modified': False}, indent=2))


if __name__ == '__main__':
    main()

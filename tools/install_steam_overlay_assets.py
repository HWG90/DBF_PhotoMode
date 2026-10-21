"""Build/install a reversible development-only decorative shader cold test.

Native registry selection and visible rendering remain pending live acceptance.
Builds write only a fresh dist/review child. Installation is always explicit.
"""
import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import re
import struct
import uuid
import zipfile

import build_steam_overlay_assets as builder
from install_steam_candidate import game_closed
import photo_assets as assets

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'dist/review'
DATA = Path('C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2_steam/data')
CORE = 'ee6b1ba7e22d71ed.patch_0'
SHARED = '9ba626afa44a3aa3.patch_2'
NAMES = tuple(name + suffix for name in (CORE, SHARED)
              for suffix in ('', '.gpu_resources', '.stream'))
PUBLISH_ORDER = tuple(name for name in NAMES if name not in (CORE, SHARED)) + (SHARED, CORE)
EMPTY_SHA = assets.sha256(b'')
EXPECTED_PRESERVED = {
    '9ba626afa44a3aa3.patch_0': 'dd119e7dc34ed1c7a8d7af3af1a32dc60945a29308b86ed82a9635291feb8218',
    '9ba626afa44a3aa3.patch_1': '189d76594e87bc251ea0b7a46bb147f6255392519d3b12f0bb2fb990d7c2fb72',
    **{name + suffix: EMPTY_SHA for name in ('9ba626afa44a3aa3.patch_0', '9ba626afa44a3aa3.patch_1')
       for suffix in ('.gpu_resources', '.stream')}}
EXPECTED_BASE = {
    'logical_archive': builder.CORE_ARCHIVE, 'logical_cpu_bytes': 630276,
    'native_table_sha256': 'c591f22bb54cac683e6fc121e0acb8335ba7dd07e242efc0d662372b09412e73',
    'registry_sha256': 'f62a82b5fc095c42958a1f30fe6a1f7846107d197960b3e5beb72bda18b86040',
    'registry_cpu_offset': 385648, 'registry_cpu_bytes': 640,
    'resources': 957, 'shader_libraries': 890, 'stock_ids': 77}
SOURCE_MANIFEST = '57c7927ac33757a66407f0c85990c7f6a5597dd59a5bd569241eac62d6648e7f'
KIND = 'dbf-photo-private-overlays-cold-test-v1'
NOTICE = ('DEVELOPMENT COLD TEST ONLY. Native shader selection and visible rendering '
          'are pending live acceptance. Not a public release. Install/rollback only '
          'with Helldivers 2 closed, using the matching guarded installer.\n')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def closed():
    require(game_closed() is not False, 'Close Helldivers 2 before changing native assets')


def review_path(path, fresh=False):
    path = Path(path).resolve()
    require(path != REVIEW.resolve() and path.is_relative_to(REVIEW.resolve()),
            'Path must be a child of dist/review')
    if fresh and path.exists():
        raise FileExistsError('Refusing to overwrite an existing review artifact')
    return path


def file_bytes(path, maximum=8 * 1024 * 1024):
    require(path.is_file() and not path.is_symlink(), 'Expected an ordinary file: ' + str(path))
    require(path.stat().st_size <= maximum, 'File exceeds bounded read: ' + str(path))
    return path.read_bytes()


def digest(path):
    return assets.sha256(file_bytes(path))


def exclusive(path, body):
    with path.open('xb') as stream:
        stream.write(body)
        stream.flush()
        os.fsync(stream.fileno())


def candidate_files():
    core, shared, source = builder.stock_union_resources()
    require(source['source_manifest_sha256'] == SOURCE_MANIFEST, 'Decorative source fingerprint changed')
    files = {}
    for name, rows in ((CORE, core), (SHARED, shared)):
        cpu, gpu = assets.archive_rows(rows)
        files.update({'Assets/' + name: cpu, 'Assets/' + name + '.gpu_resources': gpu,
                      'Assets/' + name + '.stream': b''})
    audit = {'schema': 1, 'kind': KIND, 'development_only': True, 'release_qualified': False,
             'native_selection_qualified': False, 'live_rendering_qualified': False,
             'source': source, 'required_base': EXPECTED_BASE, 'preserved_sha256': EXPECTED_PRESERVED,
             'assets_sha256': {name: assets.sha256(files['Assets/' + name]) for name in NAMES},
             'core_resources': 41, 'shared_resources': 40, 'registry_ids': 117}
    files['NATIVE-ASSET-CANDIDATE.json'] = builder.json_bytes(audit)
    files['DEVELOPMENT-ONLY.txt'] = NOTICE.encode('utf-8')
    files['FILES-SHA256.txt'] = ''.join(assets.sha256(body) + '  ' + name + '\n'
        for name, body in sorted(files.items())).encode('ascii')
    return files


def build(output):
    output = review_path(output, fresh=True)
    files = candidate_files()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()
    exclusive(output / 'DEVELOPMENT-ONLY.txt', files['DEVELOPMENT-ONLY.txt'])
    (output / 'Assets').mkdir()
    for name, body in sorted(files.items()):
        if name != 'DEVELOPMENT-ONLY.txt':
            exclusive(output / name, body)
    require(all(file_bytes(output / name) == body for name, body in files.items()),
            'Candidate write verification failed')
    return {'candidate': str(output), 'development_only': True, 'installed': False,
            'assets_sha256': json.loads(files['NATIVE-ASSET-CANDIDATE.json'])['assets_sha256']}


def load_candidate(candidate):
    candidate = review_path(candidate)
    expected = candidate_files()
    require(candidate.is_dir(), 'Candidate directory is missing')
    paths = list(candidate.rglob('*'))
    require(len(paths) <= 16 and not any(path.is_symlink() for path in paths), 'Unexpected candidate paths')
    actual = {path.relative_to(candidate).as_posix() for path in paths if path.is_file()}
    require(actual == set(expected), 'Candidate file set differs')
    require(all(file_bytes(candidate / name) == body for name, body in expected.items()),
            'Candidate bytes differ from the exact source-built closure')
    return candidate, {name: expected['Assets/' + name] for name in NAMES}


def native_table(prefix, cpu_size):
    require(len(prefix) >= 72, 'Native archive header missing')
    magic, nt, count = struct.unpack_from('<III', prefix)
    require(magic == 0xf0000011 and nt <= 128 and count <= 100000, 'Unsupported native archive header')
    start, end = 72 + nt * 32, 72 + nt * 32 + count * 80
    require(end <= len(prefix) and end <= cpu_size and end <= 1024 * 1024, 'Native table exceeds bound')
    types = list(struct.iter_unpack('<IIQIIII', prefix[72:start]))
    rows = list(struct.iter_unpack('<7Q6I', prefix[start:end]))
    require(len({row[2] for row in types}) == nt and len({row[:2] for row in rows}) == count,
            'Duplicate native table identity')
    require(Counter(row[1] for row in rows) == Counter({row[2]: row[3] for row in types}),
            'Native type/resource counts disagree')
    require(all(end <= row[2] and row[2] + row[7] <= cpu_size and
                row[10] in (16, 256) and row[2] % row[10] == 0 for row in rows),
            'Native CPU payload exceeds archive bounds/alignment')
    return rows, end


def table_length(head):
    require(len(head) == 72, 'Native archive header truncated')
    magic, nt, count = struct.unpack_from('<III', head)
    require(magic == 0xf0000011 and nt <= 128 and count <= 100000, 'Unsupported native archive header')
    length = 72 + nt * 32 + count * 80
    require(length <= 1024 * 1024, 'Native table exceeds 1 MiB')
    return length


def qualify_base(data):
    """Read bounded DSAA metadata plus the native table/registry; never game GPU payloads."""
    spec = importlib.util.spec_from_file_location('_photo_bounded_reader', ROOT / 'tools/slim_archive_reader.py')
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    reader.DATA = data.resolve()
    observed, stats = {}, {'compressed_bytes': 0, 'inflated_bytes': 0, 'chunks': 0}

    def observe(path):
        require(not path.is_symlink(), 'Bundle symlinks are not supported')
        path = path.resolve()
        require(path.parent == reader.DATA and path.is_file() and not path.is_symlink(), 'Bundle path escapes data')
        stat = path.stat()
        value = (stat.st_size, stat.st_mtime_ns)
        require(observed.setdefault(path.name, value) == value, 'Bundle changed during qualification')
        return path, value[0]

    def chunks(path):
        path, size = observe(path)
        with path.open('rb') as stream:
            head = stream.read(32)
            require(len(head) == 32 and head[:4] == b'DSAR', 'DSAR header missing')
            count = struct.unpack_from('<I', head, 8)[0]
            require(0 < count <= 100000 and 32 + count * 32 <= size, 'DSAR table exceeds bounds')
            body = stream.read(count * 32)
        require(len(body) == count * 32, 'DSAR table truncated')
        rows = list(struct.iter_unpack('<QQIIBB6x', body))
        require(all(0 < row[2] <= 128 * 1024 * 1024 and 0 < row[3] <= 128 * 1024 * 1024 and
                    row[1] + row[3] <= size and row[4] in (0, 3) for row in rows), 'DSAR chunk bounds invalid')
        return rows

    def chunk_data(path, chunk):
        path, size = observe(path)
        _, offset, unpacked, packed, kind, _ = chunk
        require(0 < unpacked <= 1024 * 1024 and 0 < packed <= 1024 * 1024 and offset + packed <= size,
                'Selected DSAR chunk exceeds 1 MiB or file bounds')
        require(stats['inflated_bytes'] + unpacked <= 18 * 1024 * 1024, 'DSAR inflation exceeds 18 MiB')
        with path.open('rb') as stream:
            stream.seek(offset)
            body = stream.read(packed)
        require(len(body) == packed, 'DSAR payload truncated')
        if kind == 3:
            body = reader.decompress(body, uncompressed_size=unpacked)
        else:
            require(kind == 0, 'Unsupported DSAR chunk compression')
        require(len(body) == unpacked, 'DSAR inflated size differs')
        stats['compressed_bytes'] += packed
        stats['inflated_bytes'] += unpacked
        stats['chunks'] += 1
        return body

    reader.chunks, reader.chunk_data = chunks, chunk_data
    index = b''.join(chunk_data(data / 'bundles.nxa', chunk) for chunk in chunks(data / 'bundles.nxa'))
    require(len(index) >= 24 and index[:4] == b'DSAA', 'DSAA index missing')
    bundle_count, archive_count = struct.unpack_from('<II', index, 12)
    require(0 < bundle_count <= 256 and 0 < archive_count <= 100000 and
            24 + archive_count * 24 + bundle_count * 4 <= len(index), 'DSAA counts exceed bounds')

    def string(offset):
        require(0 <= offset < len(index), 'DSAA string offset exceeds bounds')
        end = index.find(b'\0', offset, min(len(index), offset + 261))
        require(end >= offset, 'DSAA string missing/too long')
        return index[offset:end].decode('ascii')

    bundles = [string(struct.unpack_from('<I', index, 24 + archive_count * 24 + i * 4)[0])
               for i in range(bundle_count)]
    require(len(set(bundles)) == bundle_count and
            all(re.fullmatch(r'bundles(?:\.[0-9]+)?\.nxa', name) for name in bundles), 'DSAA bundle names invalid')
    archives = {}
    for i in range(archive_count):
        size, name_at, count, at = struct.unpack_from('<QIIQ', index, 24 + i * 24)
        name = string(name_at)
        require(name not in archives and at + count * 16 <= len(index), 'DSAA duplicate/archive bounds invalid')
        entries = list(struct.iter_unpack('<I4xI3xB', index[at:at + count * 16]))
        require(all(entry[0] < size and entry[2] < bundle_count for entry in entries), 'DSAA entry invalid')
        archives[name] = {'size': size, 'entries': entries}
    name = EXPECTED_BASE['logical_archive']
    require(name in archives and archives[name]['size'] == EXPECTED_BASE['logical_cpu_bytes'], 'Base CPU archive changed')
    logical = reader.Reader(name, bundles, archives)
    head = logical.read(0, 72)
    length = table_length(head)
    prefix = head + logical.read(72, length - 72)
    rows, _ = native_table(prefix, archives[name]['size'])
    require(assets.sha256(prefix) == EXPECTED_BASE['native_table_sha256'], 'Base native table fingerprint changed')
    libraries = {row[0] for row in rows if row[1] == assets.SHADER}
    groups = [row for row in rows if row[:2] == (assets.hash64(assets.GROUP_NAME), assets.GROUP)]
    require(len(groups) == 1, 'Base registry provider is ambiguous')
    group = groups[0]
    require(group[2] == EXPECTED_BASE['registry_cpu_offset'] and group[7] == EXPECTED_BASE['registry_cpu_bytes'],
            'Base registry location changed')
    body = logical.read(group[2], group[7])
    ids = assets.registry_ids(body)
    require(assets.sha256(body) == EXPECTED_BASE['registry_sha256'] and len(ids) == 77 and set(ids) <= libraries and
            len(libraries) == 890 and len(rows) == 957, 'Base registry/stock library closure changed')
    for name, value in observed.items():
        require(((data / name).stat().st_size, (data / name).stat().st_mtime_ns) == value,
                'Bundle changed during qualification')
    return {**EXPECTED_BASE, 'stock_ids_present': len(set(ids) & libraries), 'read_bounds': stats,
            'bundle_metadata': {name: {'bytes': value[0], 'mtime_ns': value[1]} for name, value in observed.items()}}


def preserved_files(data):
    for name, value in EXPECTED_PRESERVED.items():
        path = data / name
        if name.endswith(('.gpu_resources', '.stream')):
            require(path.is_file() and not path.is_symlink() and path.stat().st_size == 0,
                    'Expected empty preserved sidecar changed: ' + name)
        else:
            require(digest(path) == value, 'Expected loader/light patch changed: ' + name)
    return dict(EXPECTED_PRESERVED)


def scan_patches(data, owned=None):
    """Inspect immediate native CPU tables only; unknown shader owners are refused."""
    owned = owned or {}
    paths = list(data.iterdir())
    require(len(paths) <= 4096, 'Immediate data inventory exceeds bound')
    result, total = {}, 0
    private = {assets.hash64(builder.PRIVATE_PREFIX + overlay['id']) for overlay in
               json.loads((assets.ASSETS / 'manifest.json').read_bytes())['overlays']}
    for path in paths:
        if not re.fullmatch(r'[0-9a-f]{16}\.patch_[0-9]+', path.name, re.IGNORECASE):
            continue
        name = path.name.lower()
        require(path.is_file() and not path.is_symlink() and name not in result, 'Patch identity is ambiguous')
        if name in owned:
            require(digest(path) == owned[name], 'Owned patch changed: ' + name)
            continue
        with path.open('rb') as stream:
            head = stream.read(72)
            length = table_length(head)
            prefix = head + stream.read(length - 72)
        total += length
        require(total <= 8 * 1024 * 1024, 'Patch table reads exceed 8 MiB')
        rows, _ = native_table(prefix, path.stat().st_size)
        require(not any(row[1] in (assets.SHADER, assets.GROUP) or
                        (row[1] == assets.MATERIAL and row[0] in private) for row in rows),
                'Unknown competing shader registry/library or private material: ' + name)
        result[name] = assets.sha256(prefix)
    return result


def qualify_data(data, owned=None):
    require(data.is_dir(), 'Game data directory is missing')
    preserved = preserved_files(data)
    patches = scan_patches(data, owned)
    return {'base': qualify_base(data), 'preserved_sha256': preserved, 'native_patch_tables': patches}


def identity(path):
    stat = path.stat()
    return [stat.st_dev, stat.st_ino]


def append_owner(journal, name, stage, file_identity):
    with journal.open('ab') as stream:
        stream.write(builder.json_bytes({'name': name, 'stage': stage, 'identity': file_identity}).replace(b'\n', b'') + b'\n')
        stream.flush()
        os.fsync(stream.fileno())


def remove_owned(path, expected_hash, file_identity):
    if not path.exists():
        return False
    require(not path.is_symlink() and identity(path) == file_identity and digest(path) == expected_hash,
            'Refusing to remove changed/unowned file: ' + str(path))
    closed()
    path.unlink()
    return True


def load_owners(journal, state):
    owners = {}
    body = file_bytes(journal, 64 * 1024)
    for line in body.splitlines():
        record = json.loads(line)
        name = record['name']
        require(name in NAMES and record['stage'] == state['stages'][name] and name not in owners and
                isinstance(record['identity'], list) and len(record['identity']) == 2 and
                all(type(value) is int and value >= 0 for value in record['identity']) and record['identity'][1] != 0,
                'Ownership journal is invalid')
        owners[name] = record
    return owners


def stage_hash(path, body):
    """An interrupted exclusively-created stage may contain only an owned prefix."""
    actual = file_bytes(path)
    require(len(actual) <= len(body) and actual == body[:len(actual)], 'Staging bytes changed: ' + str(path))
    return assets.sha256(actual)


def cleanup(state, owners, bodies):
    removed, errors = [], []
    data = Path(state['data'])
    for name in reversed(PUBLISH_ORDER):
        if name not in owners:
            continue
        for leaf in (name, state['stages'][name]):
            try:
                path = data / leaf
                expected = state['files_sha256'][name]
                if leaf != name and path.exists():
                    expected = stage_hash(path, bodies[name])
                if remove_owned(path, expected, owners[name]['identity']):
                    removed.append(leaf)
            except BaseException as error:
                errors.append({'file': leaf, 'error': str(error)})
    return removed, errors


def install(candidate, review):
    closed()
    candidate, bodies = load_candidate(candidate)
    review = review_path(review, fresh=True)
    require(not review.is_relative_to(candidate), 'Deployment review must be outside the immutable candidate')
    data = DATA.resolve()
    qualification = qualify_data(data)
    require(all(not (data / name).exists() and not (data / name).is_symlink() for name in NAMES),
            'A candidate target slot is already occupied')
    run = uuid.uuid4().hex
    state = {'schema': 1, 'kind': KIND, 'run': run, 'data': str(data), 'candidate': str(candidate),
             'files_sha256': {name: assets.sha256(body) for name, body in bodies.items()},
             'stages': {name: '.dbf-photo-overlay-' + run + '-' + name + '.stage' for name in NAMES},
             'targets_previously_absent': True, 'preserved_sha256': dict(EXPECTED_PRESERVED)}
    review.parent.mkdir(parents=True, exist_ok=True)
    review.mkdir()
    archive = review / 'ROLLBACK.zip'
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr('STATE.json', builder.json_bytes(state))
        for name, body in bodies.items():
            bundle.writestr('candidate/' + name, body)
    with zipfile.ZipFile(archive) as bundle:
        require(bundle.testzip() is None and json.loads(bundle.read('STATE.json')) == state,
                'Rollback archive verification failed')
    plan = {'state': state, 'rollback_zip': str(archive), 'rollback_sha256': digest(archive)}
    exclusive(review / 'INSTALL-PLAN.json', builder.json_bytes(plan))
    journal = review / 'OWNERSHIP.jsonl'
    exclusive(journal, b'')
    owners = {}
    try:
        for name in NAMES:
            path = data / state['stages'][name]
            closed()
            with path.open('xb') as stream:
                file_identity = [os.fstat(stream.fileno()).st_dev, os.fstat(stream.fileno()).st_ino]
                owners[name] = {'name': name, 'stage': path.name, 'identity': file_identity}
                append_owner(journal, name, path.name, file_identity)
                stream.write(bodies[name])
                stream.flush()
                os.fsync(stream.fileno())
            require(digest(path) == state['files_sha256'][name], 'Staging byte verification failed')
        closed()
        qualify_data(data)
        require(all(not (data / name).exists() and not (data / name).is_symlink() for name in NAMES),
                'A target appeared while staging')
        for name in PUBLISH_ORDER:
            stage, target = data / state['stages'][name], data / name
            closed()
            # Same-volume hard linking publishes atomically and refuses an existing target.
            os.link(stage, target)
            remove_owned(stage, state['files_sha256'][name], owners[name]['identity'])
        require(all(digest(data / name) == state['files_sha256'][name] for name in NAMES),
                'Installed native byte verification failed')
        final = qualify_data(data, state['files_sha256'])
        result = {**plan, 'installed': True, 'development_only': True, 'qualification': final,
                  'prior_qualification': qualification, 'native_selection': 'pending cold-load test',
                  'visible_rendering': 'pending live acceptance', 'ownership_journal': str(journal)}
        exclusive(review / 'DEPLOYMENT.json', builder.json_bytes(result))
        return result
    except BaseException as error:
        removed, errors = cleanup(state, owners, bodies)
        failure = {**plan, 'installed': False, 'error': str(error), 'cleanup_removed': removed,
                   'cleanup_errors': errors, 'ownership_journal': str(journal)}
        try:
            exclusive(review / 'FAILURE.json', builder.json_bytes(failure))
        except OSError:
            pass
        raise


def rollback(receipt):
    closed()
    receipt = review_path(receipt)
    plan = json.loads(file_bytes(receipt, 512 * 1024))
    state = plan['state']
    require(state['kind'] == KIND and state['schema'] == 1 and re.fullmatch('[0-9a-f]{32}', state['run']) and
            Path(state['data']).resolve() == DATA.resolve() and state['targets_previously_absent'] is True and
            set(state['files_sha256']) == set(NAMES) and set(state['stages']) == set(NAMES) and
            set(state['preserved_sha256']) == set(EXPECTED_PRESERVED) and
            all(re.fullmatch('[0-9a-f]{64}', value) for value in state['files_sha256'].values()), 'Rollback state invalid')
    require(all(state['stages'][name] == '.dbf-photo-overlay-' + state['run'] + '-' + name + '.stage' for name in NAMES),
            'Rollback staging paths invalid')
    archive = review_path(plan['rollback_zip'])
    require(archive.parent == receipt.parent and digest(archive) == plan['rollback_sha256'], 'Rollback archive changed')
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        require(len(entries) == 7 and all(entry.file_size <= 8 * 1024 * 1024 for entry in entries) and
                sum(entry.file_size for entry in entries) <= 24 * 1024 * 1024, 'Rollback archive payload exceeds bound')
        require(json.loads(bundle.read('STATE.json')) == state, 'Rollback receipt differs from archived state')
        require(set(bundle.namelist()) == {'STATE.json'} | {'candidate/' + name for name in NAMES}, 'Rollback archive paths differ')
        require(all(assets.sha256(bundle.read('candidate/' + name)) == state['files_sha256'][name] for name in NAMES),
                'Rollback ownership payload differs')
        bodies = {name: bundle.read('candidate/' + name) for name in NAMES}
    journal = receipt.parent / 'OWNERSHIP.jsonl'
    owners = load_owners(journal, state)
    # Preflight every extant owned file before removing anything.
    for name in NAMES:
        require(name in owners or not any((DATA / leaf).exists() or (DATA / leaf).is_symlink()
                for leaf in (name, state['stages'][name])), 'Ownership journal is missing for an extant candidate path')
    for name, record in owners.items():
        for leaf in (name, state['stages'][name]):
            path = DATA.resolve() / leaf
            if path.exists() or path.is_symlink():
                expected = state['files_sha256'][name] if leaf == name else stage_hash(path, bodies[name])
                require(not path.is_symlink() and identity(path) == record['identity'] and
                        digest(path) == expected, 'Rollback refuses changed/unowned file: ' + leaf)
    removed, errors = cleanup(state, owners, bodies)
    result = {'rolled_back': not errors, 'removed': removed, 'errors': errors, 'receipt': str(receipt),
              'preserved_files_unchanged': {name: (DATA / name).is_file() and
                  ((DATA / name).stat().st_size == 0 if value == EMPTY_SHA else digest(DATA / name) == value)
                  for name, value in state['preserved_sha256'].items()}}
    report = receipt.parent / ('ROLLBACK-' + uuid.uuid4().hex + '.json')
    exclusive(report, builder.json_bytes(result))
    require(not errors, 'Rollback incomplete; inspect ' + str(report))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build_parser = commands.add_parser('build')
    build_parser.add_argument('--output', type=Path, required=True)
    install_parser = commands.add_parser('install')
    install_parser.add_argument('--candidate', type=Path, required=True)
    install_parser.add_argument('--review', type=Path, required=True)
    rollback_parser = commands.add_parser('rollback')
    rollback_parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    result = build(args.output) if args.command == 'build' else install(args.candidate, args.review) if args.command == 'install' else rollback(args.receipt)
    print(json.dumps(result, indent=2))

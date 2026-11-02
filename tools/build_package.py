"""Build the one War Journalist package: one ZIP whose mods/goose/war_journalist runs under
Boot Mod Loader or Chef Shared Loader. Proves the text offline on every host first (Lua 5.1,
Chef's own sandboxes, Boot Mod Loader 0.13.4's start-up checks). Writes under dist/review
only; never registers, deploys or installs.

Usage: python tools/build_package.py --dev N | --release [--sandbox PATH=VERSION]... [--assets DIR]"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct
import zipfile

import build_steam_candidate
import package_fixtures as fixtures
from package_head import (ARCHIVE, ASSETS_SHA256, GUID, ID, MINIMUM_CHEF, OPTION, RESOURCE, ROOT, TITLE,
                          build_id, check_size, compose)
from photo_assets import LUA, archive_rows, hash64, read_archive
from test_package import SANDBOXES, prove, sandbox_arg

# The 1.3.0 assets, as every release since has shipped them.
ASSETS = Path.home() / 'Worktrees/linux-hd2/wj-1.3.1-windows/dist/review/release-1.3.1/assets-1.3.0'
# Set by the release session with the release notes; a release build refuses without it.
RELEASE_DESCRIPTION = ('War Journalist 1.4.0: Photo Mode for Helldivers 2. One download for both Boot Mod Loader and Chef\'s '
                       'Shared Loader ' + MINIMUM_CHEF + ' or newer. New: bone posing in the Subject tab and up to 99 saved poses. '
                       'The Windows helper is now war_journalist_helper.exe and stays the same file across game updates. Center '
                       'auto-focus works as intended. On Chef there is no helper: your keys reach the game and screenshots are DDS. '
                       'AI control and depth shaders are gone for now. Use one War Journalist at a time.')
DEV_DESCRIPTION = ('War Journalist {version}, DEVELOPMENT build: one package for Boot Mod Loader and Chef Shared Loader '
                   + MINIMUM_CHEF + ' or newer. On Boot Mod Loader the helper gives keyboard isolation and PNG screenshots; '
                   'on Chef, arrow keys move the camera and screenshots are DDS. Bone posing on the Subject tab. Live Lua '
                   'reload on Boot Mod Loader once wj-dev-reload.enabled is armed. Not for players. Use one War Journalist at a time.')
INSTALL = '''War Journalist {version}: one package for Boot Mod Loader and Chef Shared Loader

Install one copy. Import this ZIP into HD2 Arsenal, make sure War Journalist is switched on, and Deploy with Helldivers 2 closed. Turn off any other War Journalist entry first, the Chef one included: this one replaces both.

Boot Mod Loader: the helper (war_journalist_helper.exe) starts on its own; there is nothing else to install. P opens Photo Mode. Page Down turns Handycam on and off. You can change both in the game's mod settings. Your keys, settings, presets and screenshots carry over.

Chef Shared Loader {chef} or newer: Chef can't start the helper, so your keys still reach the game while Photo Mode is open. P opens Photo Mode. The arrow keys move the camera and the panel, and Shift with Left or Right changes tabs. Change keys in F9 > War Journalist or in the panel. Screenshots are DDS files in the game's settings folder. Double-click focus and Center auto-focus need Chef 1.5.1 or newer.

KNOWN-ISSUES.md lists the known bugs.
'''
DEV_INSTALL = ('\nDevelopment build: under Boot Mod Loader, developer diagnostics are on and live Lua reload works once '
               'wj-dev-reload.enabled is armed. Not for players.\n')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def candidate_sources(folder):
    """The audited candidate's modules, keyed as the package carries them."""
    manifest = json.loads((folder / 'manifest.json').read_text())
    spec = manifest['lll']
    assert manifest['native_libraries'] == [], 'The candidate carries bridges'
    sources = {'main.lua': (folder / spec['entry']).read_text(encoding='utf-8')}
    for path in spec['modules']:
        sources[path] = (folder / path).read_text(encoding='utf-8')
    return sources


def files_sha256(folder):
    """FILES-SHA256.txt: every file but itself, sorted by path."""
    rows = [sha256(p.read_bytes()) + '  ' + p.relative_to(folder).as_posix() + '\n'
            for p in sorted(folder.rglob('*')) if p.is_file() and p.name != 'FILES-SHA256.txt']
    (folder / 'FILES-SHA256.txt').write_text(''.join(rows))


def clear_outputs(review, name):
    """The last build's ZIP, sums and receipt go first, so a failed rebuild never leaves them
    looking current; so does any candidate LLL ZIP, as the package is the only ZIP to ship."""
    for path in [review / (name + '.zip'), review / 'SHA256SUMS.txt', review / 'BUILD-RECEIPT.json',
                 *review.glob('candidate/*-LLL.zip')]:
        path.unlink(missing_ok=True)


def build(release, dev_number, sandboxes, assets):
    base = (ROOT / 'VERSION').read_text().strip()
    notes = ROOT / 'docs' / f'RELEASE-{base}.md'
    if release:
        assert re.fullmatch(r'\d+\.\d+\.\d+', base), 'A release takes a plain VERSION: ' + base
        assert notes.is_file(), 'Release notes missing: ' + notes.relative_to(ROOT).as_posix()
        assert RELEASE_DESCRIPTION, 'RELEASE_DESCRIPTION is not set in tools/build_package.py'
        version = base
    else:
        assert isinstance(dev_number, int) and dev_number >= 1, 'A dev build takes --dev N'
        version = f'{base}-dev.{dev_number}'
        notes = ROOT / 'docs' / f'RELEASE-{version}.md'
    review = (ROOT / 'dist/review/package' / version).resolve()
    assert review.is_relative_to(ROOT / 'dist/review'), 'Packages stay in dist/review'
    review.mkdir(parents=True, exist_ok=True)
    name = 'War-Journalist-' + version
    clear_outputs(review, name)
    # The audited module graph (runs the Lua 5.1 suite and the module audit).
    candidate = build_steam_candidate.build(review / 'candidate', release, bridges=False)
    sources = candidate_sources(Path(candidate['candidate']))
    Path(candidate['package']).unlink()
    assert sources == fixtures.current_sources(release), 'The candidate differs from this tree'
    text = compose(sources, version, build_id(), release)
    proofs = prove(text, release, sources, sandboxes)
    data = text.encode('utf-8')
    key = hash64(RESOURCE)
    assert key == 0xb42c756875139ce2, f'{key:016x}'
    envelope = struct.pack('<II', len(data), 2) + data
    body, gpu = archive_rows([(key, LUA, envelope, b'')])
    assert read_archive(body, gpu) == [(key, LUA, envelope, b'')] and gpu == b''
    folder = review / name
    if folder.exists():
        shutil.rmtree(folder)
    payload = folder / OPTION
    payload.mkdir(parents=True)
    (payload / ARCHIVE).write_bytes(body)
    for suffix in ('.stream', '.gpu_resources'):
        (payload / (ARCHIVE + suffix)).write_bytes(b'')
    # Source beside the archive, so Arsenal sees it as Lua.
    (payload / f'{key:016x}.lua').write_bytes(data)
    (folder / 'Assets').mkdir()
    for asset, digest in ASSETS_SHA256.items():
        blob = (assets / asset).read_bytes()
        assert sha256(blob) == digest, 'Asset differs from 1.3.0: ' + asset
        (folder / 'Assets' / asset).write_bytes(blob)
    assert sorted(p.name for p in assets.iterdir()) == sorted(ASSETS_SHA256), 'Unexpected files in ' + str(assets)
    for label in ('LICENSE-Link.txt', 'LICENSE-Bingus.txt'):
        shutil.copyfile(ROOT / 'freecam/vendor' / label, folder / label)
    shutil.copyfile(ROOT / 'tools/chef-LICENSE.txt', folder / 'Chef-LICENSE.txt')
    shutil.copyfile(ROOT / 'docs/KNOWN-ISSUES.md', folder / 'KNOWN-ISSUES.md')
    if notes.is_file():
        shutil.copyfile(notes, folder / 'RELEASE-NOTES.md')
    (folder / 'INSTALL.txt').write_text(INSTALL.format(version=version, chef=MINIMUM_CHEF) + ('' if release else DEV_INSTALL), encoding='utf-8')
    description = RELEASE_DESCRIPTION if release else DEV_DESCRIPTION.format(version=version)
    arsenal = {'Version': 1, 'Guid': GUID, 'Name': TITLE + ' ' + version, 'Description': description,
               'Options': [{'Name': OPTION, 'Description': 'Photo Mode and its assets.', 'Include': [OPTION, 'Assets']}]}
    (folder / 'manifest.json').write_text(json.dumps(arsenal, indent=2, ensure_ascii=False) + '\n')
    provenance = {'version': version, 'runtime': 'Lua 5.1', 'ffi': 'none', 'resource': RESOURCE, 'resource_key': f'{key:016x}',
                  'project': ID, 'hosts': {'boot_mod_loader': '0.13.4 starts it itself', 'chef_shared_loader': '>= ' + MINIMUM_CHEF,
                                           'lll': 'API 1 entry, no bridges'},
                  'addon_sha256': sha256(data), 'addon_bytes': len(data), 'archive_sha256': sha256(body),
                  'modules': len(sources) - 1, 'boot_only': list(fixtures.BOOT_ONLY), 'native_bridges': [],
                  'helper_sha256': fixtures.HELPER_SHA256,
                  'assets': {asset: sha256((folder / 'Assets' / asset).read_bytes()) for asset in sorted(ASSETS_SHA256)},
                  'verified': proofs, 'registered': False, 'deployed': False, 'live_acceptance': 'pending'}
    (folder / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    files_sha256(folder)
    package = review / (name + '.zip')
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(folder).as_posix())
    zipped = fixtures.verify_zip(package, release)
    (review / 'SHA256SUMS.txt').write_text(sha256(package.read_bytes()) + '  ' + package.name + '\n')
    receipt = {'version': version, 'release': release, 'package': str(package), 'package_sha256': sha256(package.read_bytes()),
               'folder': str(folder), 'addon_sha256': sha256(data), 'addon_bytes': len(data), 'modules': len(sources) - 1,
               'candidate': candidate['candidate'], 'candidate_sha256': candidate['sha256'], 'module_audit': candidate['module_audit']['passed'],
               'suite': len(candidate['fixtures']['fixtures']), 'proofs': proofs, 'zip': zipped,
               'installed': False, 'live_acceptance': 'pending'}
    (review / 'BUILD-RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    kind = parser.add_mutually_exclusive_group(required=True)
    kind.add_argument('--dev', type=int, metavar='N', help='development build 1.4.0-dev.N')
    kind.add_argument('--release', action='store_true', help='the public build; needs docs/RELEASE-<VERSION>.md and RELEASE_DESCRIPTION')
    parser.add_argument('--sandbox', type=sandbox_arg, action='append', default=None, metavar='PATH=VERSION')
    parser.add_argument('--assets', type=Path, default=ASSETS)
    args = parser.parse_args()
    receipt = build(args.release, args.dev, args.sandbox or SANDBOXES, args.assets)
    print(json.dumps({k: receipt[k] for k in ('version', 'package', 'package_sha256', 'addon_sha256', 'addon_bytes', 'modules')}, indent=2))

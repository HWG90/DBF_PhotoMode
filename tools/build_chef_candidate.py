"""Build a deterministic Chef preview under dist/releases. Does not install or publish."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from chef_archive import pack_candidate, unpack_candidate
import photo_light_assets

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = 'b7434c7289bbb9adbfeb2d3bdb57134218f2a509'
RESOURCE = 'mods/goose/war_journalist'
VERSION = '0.5.0-chef-preview.5'
MODULES = {
    'wj.chef.runtime': 'chef/runtime.lua',
    'wj.chef.camera': 'chef/camera.lua',
    'wj.chef.controls': 'chef/controls.lua',
    'wj.chef.motion': 'chef/motion.lua',
    'wj.chef.simulation': 'chef/simulation.lua',
    'wj.chef.shots': 'chef/shots.lua',
    'wj.steam_path': 'steam_path.lua',
    'wj.chef.bloom': 'chef/bloom.lua',
    'wj.chef.lights': 'chef/lights.lua',
    'wj.chef.light_setups': 'chef/light_setups.lua',
    'wj.chef.light_drag': 'chef/light_drag.lua',
    'wj.chef.light_memory': 'chef/light_memory.lua',
    'wj.chef.subject': 'chef/subject.lua',
    'wj.steam_subject': 'steam_subject.lua',
    'wj.steam_subject_native': 'steam_subject_native.lua',
    'wj.assets.poses': 'assets/steam_subject_poses.lua',
    'wj.assets.crest': 'assets/helldiver_crest.lua',
    'wj.steam_camera': 'steam_camera.lua',
    'wj.composition': 'composition.lua',
}
PATCH = 'core/9ba626afa44a3aa3.patch_0'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def bundle():
    entry = (ROOT / 'freecam/chef/main.lua').read_text(encoding='utf-8')
    header, body = entry.split('-- Development entry;', 1)
    parts = [header, '-- Generated modules stay inside this addon sandbox.\n']
    for name, path in MODULES.items():
        source = (ROOT / 'freecam' / path).read_text(encoding='utf-8')
        parts.append("package.preload[%s] = function(...)\n%s\nend\n" % (json.dumps(name), source))
    from chef_crest import fallback, logos
    parts.append("package.preload['wj.assets.crest_fallback'] = function(...)\n" +
                 fallback(ROOT / 'freecam/assets/helldiver_crest.lua') + '\nend\n')
    parts.append("package.preload['wj.assets.logos'] = function(...)\n" +
                 logos(ROOT / 'freecam/assets/logo_art.lua') + '\nend\n')
    parts.append('-- Development entry;' + body)
    return ''.join(parts).encode('utf-8')


def verify(package, expected=None):
    from lupa.lua51 import LuaRuntime
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        required = {PATCH, PATCH + '.stream', PATCH + '.gpu_resources',
                    'manifest.json', 'PROVENANCE.json', 'FILES-SHA256.json', 'Chef-LICENSE.txt', 'README.txt', 'ARTWORK-CREDITS.txt'}
        assert len(names) == len(set(names)) and set(names) == required, 'Unexpected package payload'
        data = {name: archive.read(name) for name in names}
    hashes = json.loads(data['FILES-SHA256.json'])
    assert set(hashes) == required - {'FILES-SHA256.json'}
    for name, sha in hashes.items():
        assert digest(data[name]) == sha, 'Checksum mismatch: ' + name
    assert data[PATCH + '.stream'] == data[PATCH + '.gpu_resources'] == b''
    source = unpack_candidate(data[PATCH], RESOURCE)
    if expected is not None:
        assert source == expected, 'Packaged Lua differs from source'
    assert source.startswith(('-- HD2-Addon: ' + RESOURCE + '\n').encode())
    assert b'\x1bLua' not in source and b'\x1bLJ' not in source
    lua = LuaRuntime()
    assert lua.eval('_VERSION') == 'Lua 5.1'
    lua.compile(source.decode('utf-8'))
    return source


def build(output, sandbox):
    from test_chef_port import run
    output = output.resolve()
    assert output.is_relative_to(ROOT / 'dist/releases'), 'Keep release artifacts under dist/releases'
    source = bundle()
    tests = run(source, sandbox)
    manifest = {'Version': 1, 'Guid': '7b18fc08-a506-4cd3-a506-dbed18445576',
                'Name': 'War Journalist ' + VERSION,
                'Description': 'Development preview for Chef 1.2.3+. Freecam, solo time, Cinema, paths, presets, composition, native render switches, photo lighting and experimental selected-subject poses. No shader effects or AI controls. In-game validation pending.',
                'Options': [{'Name': 'War Journalist (core)', 'Description': 'Chef preview addon.', 'Include': ['core']}]}
    provenance = {'version': VERSION, 'upstream': UPSTREAM, 'resource': RESOURCE,
                  'runtime': 'Lua 5.1 source', 'candidate_only': True, 'live_game_verified': False,
                  'installed': False, 'published': False,
                  'photo_light': photo_light_assets.validate_unit(photo_light_assets.resource()[2]), 'source_sha256': {
                      path: digest((ROOT / 'freecam' / path).read_bytes())
                      for path in [*MODULES.values(), 'chef/main.lua', 'assets/logo_art.lua', 'assets/logos/runtime-manifest.json']}}
    provenance['build_sources_sha256'] = {path: digest((ROOT / 'tools' / path).read_bytes()) for path in
                                         ['build_chef_candidate.py', 'chef_archive.py', 'chef_crest.py', 'photo_assets.py', 'photo_light_assets.py']}
    provenance['parity_reference'] = {'version': 'War Journalist 1.3.0 Steam Lua 5.1',
        'source_sha256': {path: digest((ROOT / path).read_bytes()) for path in
                         ['docs/RELEASE-1.3.0.md', 'freecam/steam_release/steam_runtime.lua',
                          'freecam/steam_lighting.lua', 'freecam/steam_input.lua', 'freecam/photo_options.lua']}}
    files = {PATCH: pack_candidate(RESOURCE, source), PATCH + '.stream': b'', PATCH + '.gpu_resources': b'',
             'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
             'PROVENANCE.json': (json.dumps(provenance, indent=2) + '\n').encode(),
             'Chef-LICENSE.txt': (ROOT / 'tools/chef-LICENSE.txt').read_bytes(),
             'ARTWORK-CREDITS.txt': (ROOT / 'docs/CHEF-ARTWORK-CREDITS.txt').read_bytes(),
             'README.txt': (ROOT / 'docs/CHEF-PREVIEW.txt').read_bytes()}
    files['FILES-SHA256.json'] = (json.dumps({name: digest(data) for name, data in sorted(files.items())}, indent=2) + '\n').encode()
    output.mkdir(parents=True, exist_ok=True)
    package = output / ('War-Journalist-' + VERSION + '.zip')
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2026, 10, 27, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compresslevel=9)
    packaged = verify(package, source)
    # Execute the bytes reconstructed from the archive; no external modules.
    packaged_tests = run(packaged, sandbox, shared_fixtures=False)
    report = {'package': str(package), 'sha256': digest(package.read_bytes()),
              'tests': tests, 'packaged_tests': packaged_tests,
              'installed': False, 'published': False, 'live_game_verified': False}
    (output / 'BUILD-RECEIPT.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/releases/chef-preview.5')
    parser.add_argument('--sandbox', type=Path, required=True, help='Chef 1.2.3 sandbox.lua at the documented upstream revision')
    args = parser.parse_args()
    result = build(args.output, args.sandbox)
    print(json.dumps({key: value for key, value in result.items() if key not in ('tests', 'packaged_tests')}, indent=2))

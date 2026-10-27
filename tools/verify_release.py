"""Verify owned-camera War Journalist packages and their immutable asset closure."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'dbf_freecam/'
SHADER_RELEASES = {'0.9.5': '0.9.5', '0.9.6': '0.9.6', '0.9.7': '0.9.6', '0.9.8': '0.9.6', '0.9.9': '0.9.6', '0.9.10': '0.9.6', '0.9.11': '0.9.6', '1.0': '0.9.6', '1.0.1': '0.9.6', '1.1.0': '0.9.6', '1.2.0': '0.9.6', '1.2.1': '0.9.6'}




def decode_literal(value):
    assert value.startswith('"') and value.endswith('"'), 'Unsupported embedded Lua literal'
    encoded=value[1:-1];out=bytearray();position=0
    while position<len(encoded):
        if encoded[position]=='\\':
            digits=encoded[position+1:position+4]
            assert len(digits)==3 and digits.isdigit(), 'Unexpected Lua escape'
            out.append(int(digits));position+=4
        else:out.append(ord(encoded[position]));position+=1
    return bytes(out)


def embedded_payload(startup):
    begin=startup.index('local files={\n')+len('local files={\n');end=startup.index('\n}\nlocal cache={}',begin)
    payload={}
    for line in startup[begin:end].splitlines():
        match=re.fullmatch(r'\[("[^"\n]+")\]=(.+),',line);assert match, 'Embedded file table contract changed'
        name=decode_literal(match[1]).decode();value=match[2];assert name not in payload
        payload[name]=bytes.fromhex(decode_literal(value[5:-1]).decode())if value.startswith('{hex=')else decode_literal(value)
    return payload






def _release_files(source):
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)) and archive.testzip() is None, 'ZIP paths/CRC invalid'
        for name in names:
            entry = PurePosixPath(name)
            assert not entry.is_absolute() and '..' not in entry.parts and '\\' not in name and ':' not in name and not name.endswith('/'), 'Unsafe ZIP path: '+name
            lower = name.lower()
            assert not any(token in lower for token in ('deployment-backup', '/screenshots/', 'photohoversguard', 'photohoverguard', 'minhook', 'hover-library')), 'Private/rejected artifact: '+name
            assert not lower.endswith(('.log', '.dds', '.dmp', '.pdb', '.obj', '.exe')), 'Unexpected artifact: '+name
        files = {name: archive.read(name) for name in names}
    expected = {}
    for line in files['FILES-SHA256.txt'].decode().splitlines():
        digest, name = line.split('  ', 1)
        assert name in files and name not in expected and re.fullmatch('[0-9a-f]{64}', digest), 'Invalid checksum entry'
        assert hashlib.sha256(files[name]).hexdigest() == digest, 'Packaged checksum mismatch: '+name
        expected[name] = digest
    assert set(expected) == set(files)-{'FILES-SHA256.txt'}, 'Checksum coverage differs from ZIP'
    return files


def _release_asset_closure(files, prefix, bsl, version, allow_legacy_registry=False):
    import photo_assets
    import lua_archive
    import photo_light_assets
    parsed = []
    for base in ('ee6b1ba7e22d71ed', '9ba626afa44a3aa3'):
        path = prefix+base+'.patch_0'
        assert files[path+'.stream'] == b'', 'Unexpected stream resources'
        parsed.append(photo_assets.read_archive(files[path], files[path+'.gpu_resources'], files[path+'.stream']))
    core, shared = parsed
    assert Counter(row[1] for row in core) == {photo_assets.SHADER: len(core)-1, photo_assets.GROUP: 1}, 'Core must contain shader libraries and exactly one registry'
    shared_types = {photo_assets.MATERIAL: 44, photo_light_assets.UNIT: 1}
    if bsl:
        shared_types[lua_archive.LUA_TYPE] = 1
    assert Counter(row[1] for row in shared) == shared_types, 'Shared resource closure differs'
    assert len({row[:2] for row in core+shared}) == len(core+shared), 'Cross-archive resource identity collision'
    light = [row for row in shared if row[1] == photo_light_assets.UNIT]
    assert light == [photo_light_assets.resource()], 'Dedicated light bytes or identity differ'
    photo_light_assets.validate_unit(light[0][2])
    # The existing 40 decorative assets remain byte-identical. Each of the four
    # Photo additions must have a matching shader/material variant and registry.
    decorations = photo_assets.load_resources()
    shader_version = SHADER_RELEASES[version]
    resolved_name = 'scene_dof_resolved_v2_'+('8a8fd1f00bd99bfa' if shader_version=='0.9.5' else '76ff992884d03475')
    resolved_sha = 'f5960f63e1247ac40af4bb37ccbd59ac26c9168aad9eb40936c082c9ddf40194' if shader_version=='0.9.5' else '0ee49d87cc1250ab5582934fba8f925d33bf63cb2555651f1974a52dfa55c9b7'
    extra_names = ('dof_local_depth_v1', 'scene_depth_color_v1', 'scene_dof_combined_v1', resolved_name)
    expected_shaders = {row[0] for row in decorations if row[1] == photo_assets.SHADER}
    expected_materials = {row[0] for row in decorations if row[1] == photo_assets.MATERIAL}
    expected_shaders.update(photo_assets.hash64('mods/dbf_photo/shaders/'+name) for name in extra_names)
    expected_materials.update(photo_assets.hash64('mods/dbf_photo/materials/'+name) for name in extra_names)
    shaders = {row[0]: row for row in core if row[1] == photo_assets.SHADER}
    materials = {row[0]: row for row in shared if row[1] == photo_assets.MATERIAL}
    owned_shader_ids = set(expected_shaders)
    if set(shaders) != expected_shaders:
        # Coexistence packages must match the exact source-built closure, not
        # merely register arbitrary IDs from an installed archive.
        import build_release
        compatible, _, _ = build_release.resources()
        compatible_shaders = {r[0]: r for r in compatible if r[1] == photo_assets.SHADER}
        assert shaders == compatible_shaders, 'Shared shader closure differs from source'
        expected_shaders = set(compatible_shaders)
    assert set(shaders) == expected_shaders and set(materials) == expected_materials, 'Shader/material identity closure differs'
    resolved = shaders[photo_assets.hash64('mods/dbf_photo/shaders/'+resolved_name)]
    assert hashlib.sha256(resolved[3]).hexdigest() == resolved_sha, 'Versioned compositor bytes changed'
    indexed = {row[:2]: row for row in core+shared}
    for row in decorations:
        assert indexed[row[:2]] == row, 'Existing decorative asset changed'
    for name, _, cpu, gpu in (r for r in shaders.values() if r[0] in owned_shader_ids):
        assert cpu == struct.pack('<I', 4) and len(gpu) > 0xe4, 'Invalid shader-library payload'
        assert struct.unpack_from('<I', gpu, 0xe0)[0] == name >> 32, 'Shader variant identity mismatch'
        assert len(photo_assets._dxbc_windows(gpu)) == 2, 'Shader must contain its vertex and pixel programs'
    variants = {name >> 32 for name in shaders}
    for _, _, cpu, gpu in materials.values():
        assert len(cpu) == 144 and not gpu and struct.unpack_from('<I', cpu, 128)[0] in variants, 'Material shader dependency missing'
    group = next(row for row in core if row[1] == photo_assets.GROUP)
    assert group[0] == photo_assets.hash64(photo_assets.GROUP_NAME) and not group[3], 'Wrong shader registry resource'
    ids = photo_assets.registry_ids(group[2])
    stock = photo_assets.registry_ids((ROOT/'freecam/assets/shaders/original-default-shaders.bin').read_bytes())
    expected_ids = set(stock) | expected_shaders
    dangling = set(ids) - expected_ids
    if allow_legacy_registry and dangling:
        base = (ROOT/'freecam/assets/shaders/dof_registry_base.bin').read_bytes()
        assert len(ids) == 319 and tuple(ids[:315]) == photo_assets.registry_ids(base), 'Unknown historical registry'
        assert set(ids[315:]) == {photo_assets.hash64('mods/dbf_photo/shaders/'+name) for name in extra_names}, 'Historical additions differ'
    else:
        assert len(ids) == len(expected_ids) and set(ids) == expected_ids, 'Shader registry contains missing or unbundled registrations'
        assert tuple(ids[:len(stock)]) == stock, 'Native shader registration order changed'
    assert expected_shaders <= set(ids), 'Unregistered packaged shader'
    lua_rows = [row for row in shared if row[1] == lua_archive.LUA_TYPE]
    startup = None
    if bsl:
        row = lua_rows[0]
        assert row[0] == lua_archive.hash_name('mods/dbf_photomode/startup') and not row[3], 'Unexpected Lua startup resource'
        body = row[2]
        assert len(body) >= 8 and struct.unpack_from('<II', body) == (len(body)-8, 2), 'BSL startup envelope invalid'
        startup = body[8:].decode()
    return {'shader_libraries': len(shaders), 'materials': 44, 'registry_ids': len(ids), 'dedicated_lights': 1,
            'unbundled_shader_registrations': len(dangling),
            'startup_resources': len(lua_rows), 'external_light_dependencies': [],
            'registry_sha256': hashlib.sha256(group[2]).hexdigest()}, startup


def verify_current(path, version, standalone=False, allow_legacy_registry=False, input_recovery_candidate=False):
    if input_recovery_candidate:
        assert version == '1.0.1', 'Input recovery exception applies only to the explicit 1.0.1 development candidate'
    import photo_assets
    from test_packaged_standalone import pe_imports
    files = _release_files(path)
    bsl = 'Addon/9ba626afa44a3aa3.patch_0' in files
    audit, startup = _release_asset_closure(files, 'Addon/' if bsl else 'GameData/', bsl, version, allow_legacy_registry)
    if bsl:
        loader = 'BSL'
        manifest = json.loads(files['manifest.json'])
        assert manifest['Version'] == 1 and manifest['Name'] == 'War Journalist '+version
        assert manifest['Options'][0]['Include'] == ['Addon'] and 'Bingus Shared Loader' in manifest['Description']
        runtime = embedded_payload(startup)
        assert 'DBF_PHOTO_MODE_OWNER' in startup and 'DBF_PHOTO_PACKAGE_ROOT' in startup
        assert 'mod.require' not in startup and 'mod.read' not in startup, 'LLL dependency in BSL'
        metadata = files
    else:
        runtime = {name.removeprefix(PREFIX): body for name, body in files.items() if name.startswith(PREFIX)}
        metadata = runtime
        manifest = json.loads(runtime['manifest.json'])
        assert manifest['id'] == 'dbf_freecam' and manifest['name'] == 'War Journalist' and manifest['version'] == version
        loader = 'LLL' if 'main.lua' in runtime else 'MDL'
        if loader == 'LLL':
            policy = manifest['lll']
            assert policy['entry'] == 'main.lua' and policy['restart_only'] is True and policy['retain_until_exit'] is True
            assert policy['modules'] == sorted(name for name in runtime if name.startswith('src/') and name.endswith('.lua'))
            assert json.loads(runtime['config/defaults.cfg']) == {}, 'Saved settings bundled'
        else:
            assert manifest['loader'] == 'MDL' and manifest['api'] == 2 and manifest['restart_required'] is True
            assert 'ctx.api==2' in runtime['mod.lua'].decode()
        if loader == 'MDL':
            installer = json.loads(files['manifest.json'])
            assert installer['Version'] == 1 and installer['Guid'] == '3e25431a-27e8-4b7a-b355-3956c1caa8d8'
            assert len(installer['Options']) == 1 and installer['Options'][0]['Include'] == ['GameData'], 'MDL Arsenal manifest must deploy assets only'
            assert all(name.startswith((PREFIX, 'GameData/')) or name in ('manifest.json', 'INSTALL.txt', 'FILES-SHA256.txt') for name in files), 'Foreign flat MDL files'
            assert not any(name.lower().endswith(('.zip', '.7z', '.rar', '.tar', '.gz', '.cab')) or zipfile.is_zipfile(io.BytesIO(body)) for name, body in files.items()), 'Nested archive in MDL package'
            assert b'Import this complete MDL ZIP into Arsenal' in files['INSTALL.txt'], 'Flat MDL install instructions missing'
        else:
            asset_zip = files['Arsenal/War-Journalist-'+version+'-Assets.zip']
            nested = _release_files(io.BytesIO(asset_zip))
            nested_audit, _ = _release_asset_closure(nested, 'Assets/', False, version, allow_legacy_registry)
            assert nested_audit == audit, 'Arsenal companion asset closure differs'
            for name, body in files.items():
                if name.startswith('GameData/'):
                    assert nested['Assets/'+name.removeprefix('GameData/')] == body, 'Arsenal and manual assets differ'
    for required in ('src/camera_runtime.lua', 'src/camera_ownership.lua', 'src/standalone.lua', 'standalone-library.txt'):
        assert required in runtime, 'Private runtime missing: '+required
    assert not any('actioncam' in name.lower() for name in runtime), 'Removed third-party camera payload included'
    code = runtime['src/camera_runtime.lua'].decode()
    assert 'actioncam' not in code.lower(), 'Third-party camera integration included'
    assert "DBF_PHOTO_CAMERA_ENGINE','independent'" in code, 'Owned camera engine missing'
    assert 'H.dbf_camera_ownership' in code and 'DBF_PHOTO_CAMERA_OWNERSHIP' in code, 'Local camera lease missing'
    ownership = runtime['src/camera_ownership.lua'].decode()
    assert 'actioncam' not in ownership.lower(), 'Third-party camera adapter included in local lease'
    provenance = json.loads(metadata['PROVENANCE.json'])
    assert provenance.get('camera_engine') == 'independent', 'Owned camera engine provenance missing'
    assert not any('actioncam' in name.lower() for name in provenance['source_modules_sha256']), 'Removed camera source included in provenance'
    assert "name='Photo Mode'" in code and 'H.dbf_hover_pause' in code and 'native_color_guard' in code
    for forbidden in ('PhotoHoverGuard', 'MH_CreateHook', 'hover-library.txt', 'MinHook'):
        assert forbidden not in code, 'Rejected native hover-hook code included'
    for logo in ('Super Earth crest', 'Super Citizen Edition', 'Heart of Democracy', 'Into the Unjust'):
        assert logo in code, 'Updated embedded logo missing: '+logo
    assert not any(word in code for word in ('Beddivers', 'Brasildivers', 'Shafts of Despair')), 'Excluded joke logo in runtime'
    if version in ('1.0', '1.0.1'):
        for feature in ('H.dbf_ragdoll_pause', 'function self.ragdoll_frame()', 'frame.ragdoll_active',
                        'Ragdoll pose held', 'path_snapshot', 'native_menu_resume', 'terminids={name="Terminids"'):
            assert feature in code, '1.0 runtime feature missing: '+feature
        provenance = json.loads(metadata['PROVENANCE.json'])
        if input_recovery_candidate:
            assert version == '1.0.1' and provenance.get('candidate_only') is True and provenance.get('candidate_profile') == 'input-recovery', 'Input recovery exception requires explicit development candidate provenance'
            assert provenance.get('camera_engine') == 'independent', 'Input recovery requires the owned camera engine'
            assert "rawset(_G,'DBF_PHOTO_INPUT_RECOVERY_CANDIDATE',true)" in code, 'Input recovery candidate marker missing'
            for feature in ('DBF_PHOTO_EDITOR_INPUT', 'DBF_PHOTO_INPUT_RECOVERY', 'H.dbf_input_recovery'):
                assert feature in code, 'Input recovery candidate feature missing: '+feature
            assert re.fullmatch('[0-9a-f]{64}', provenance['source_modules_sha256'].get('input_recovery.lua', '')), 'Input recovery source provenance missing'
        else:
            assert 'DBF_PHOTO_EDITOR_INPUT' not in code and 'self.editor_bridge' not in code and 'DBF_PHOTO_INPUT_RECOVERY' not in code, 'Unreleased external-editor bridge/recovery included; use the dedicated development candidate verifier'
        for module in ('ragdoll_pause.lua', 'cinema_camera.lua', 'assets/faction_art.lua'):
            assert re.fullmatch('[0-9a-f]{64}', provenance['source_modules_sha256'].get(module, '')), '1.0 source provenance missing: '+module
    if version in ('1.1.0','1.2.0','1.2.1'):
        assert provenance.get('candidate_only') is False and provenance.get('camera_engine')=='independent', 'Public camera release identity missing'
        assert 'CANDIDATE-README.txt' not in runtime, 'Development warning in public runtime'
        for feature in ('function self.passive_update(', 'player no aggro', 'passive_due=now+1', 'function self.set_follow_player('):
            assert feature in code, '1.1.0 feature missing: '+feature
        assert 'DBF_PHOTO_INPUT_RECOVERY' in code and 'H.dbf_ragdoll_pause' in code, 'Retained recovery/ragdoll feature missing'
    vendor = json.loads(metadata['VENDOR-PROVENANCE.json'])
    native_name = runtime['standalone-library.txt'].decode().strip()
    assert re.fullmatch(r'mcm_input_[0-9a-f]+\.dll', native_name)
    capture = vendor['capture_library']
    assert re.fullmatch(r'PhotoCapture_[0-9a-f]+\.dll', capture)
    libraries = {name: body for name, body in runtime.items() if name.endswith('.dll')}
    assert set(libraries) == {native_name, capture}, 'Unexpected native runtime DLL or missing private service'
    for name, body in runtime.items():
        if name.startswith('src/vendor/'):
            leaf = name.removeprefix('src/vendor/')
            assert hashlib.sha256(body).hexdigest() == vendor['runtime_sha256'][leaf], 'Vendor Lua hash mismatch: '+name
    imports = {}
    system32 = Path(os.environ['SystemRoot'])/'System32'
    for name, body in libraries.items():
        assert hashlib.sha256(body).hexdigest() == vendor['runtime_sha256'][name], 'Vendor DLL hash mismatch: '+name
        imports[name] = pe_imports(body)
        for dependency in imports[name]:
            assert not dependency.startswith(('vcruntime', 'msvcp', 'concrt')), 'Unbundled VC++ runtime prerequisite'
            assert dependency.startswith(('api-ms-win-', 'ext-ms-win-')) or (system32/dependency).is_file() or dependency in libraries, 'Unbundled native dependency: '+dependency
    assert b'CowboyBingus' in metadata['LICENSE-Bingus.txt'] and b'Zero-Clause BSD' in metadata['LICENSE-Bingus.txt']
    assert b'MIT License' in metadata['LICENSE-Link.txt'], 'Link reader license missing'
    for name in ('INSTALL.txt', 'KNOWN-ISSUES.md', 'RELEASE-NOTES.md', 'ASSET-MANIFEST.json'):
        assert metadata.get(name), 'Release metadata missing: '+name
    asset_manifest = json.loads(metadata['ASSET-MANIFEST.json'])
    if version in ('0.9.7', '0.9.8', '0.9.9', '0.9.10', '0.9.11', '1.0', '1.0.1'):
        assert asset_manifest['shader_asset_version'] == SHADER_RELEASES[version], 'Release must retain the frozen 0.9.6 shader assets'
    for key, expected in (('version', version), ('shader_libraries_core', audit['shader_libraries']), ('materials_shared', 44), ('registry_resources_core', 1), ('registry_ids', audit['registry_ids'])):
        assert asset_manifest[key] == expected, 'Packaged asset manifest disagrees with resource closure: '+key
    assert asset_manifest['lighting_status'] == 'Not tested fully' and asset_manifest['photo_light']['external_dependencies'] == []
    docs = b'\n'.join(metadata.get(name, b'') for name in ('INSTALL.txt', 'KNOWN-ISSUES.md', 'RELEASE-NOTES.md')).decode()
    assert 'Not tested fully' in docs, 'Mission-light test limitation must be disclosed'
    # Source credits and all selected original files are carried in each format.
    art_prefix = 'assets/logos/'
    artwork = files if bsl else runtime
    mesh_manifest = json.loads(artwork[art_prefix+'runtime-manifest.json'])
    assert {entry['index'] for entry in mesh_manifest['entries']} == {4, 7, 8, 9, 10, 11, 12, 13}
    for folder in ('steamgriddb-5403655', 'alphaccca', 'figma-community-1382854850516388445'):
        prefix = art_prefix+folder+'/'
        source_manifest = json.loads(artwork[prefix+'manifest.json'])
        assert artwork[prefix+'README.md']
        for entry in source_manifest['entries']:
            assert hashlib.sha256(artwork[prefix+entry['file']]).hexdigest() == entry['sha256'], 'Missing/changed credited logo original'
    result = {'version': version, 'format': loader, 'passed': True, 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
              'archive': path.name, 'archive_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'files': len(files), 'private_payload_files': len(runtime), 'asset_audit': audit, 'native_imports': imports,
              'game_process_accessed': False, 'standalone_executed': bool(standalone),
              'scope': 'Immutable ZIP/checksums, embedded runtime and logo closure, all shader/material registrations, dedicated light, licenses and native imports; no live rendering claim'}
    if standalone:
        from test_packaged_standalone import verify as verify_standalone
        result['standalone'] = verify_standalone(path.resolve())
    return result


def verify(path, standalone=False, allow_legacy_registry=False):
    # Dispatch from the immutable package identity, not this checkout's VERSION.
    with zipfile.ZipFile(path) as archive:
        name = PREFIX+'manifest.json' if PREFIX+'manifest.json' in archive.namelist() else 'manifest.json'
        manifest = json.loads(archive.read(name))
    version = manifest.get('version') or manifest.get('Name', '').removeprefix('War Journalist ')
    if version in SHADER_RELEASES:
        return verify_current(path, version, standalone, allow_legacy_registry)
    raise AssertionError('Unsupported current package version: '+str(version))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--standalone', action='store_true', help='Also execute the package-only mocked startup check; never attaches to the game')
    parser.add_argument('--allow-legacy-registry', action='store_true', help='Audit immutable historical packages with known external shader registrations; never use for a new release')
    args = parser.parse_args()
    try:
        result = verify(args.archive, args.standalone, args.allow_legacy_registry)
    except (AssertionError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print('FAIL: '+str(error), file=sys.stderr)
        return 1
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

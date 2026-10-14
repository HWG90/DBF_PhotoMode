"""Verify immutable War Journalist releases (0.9.5 through 0.9.8 and legacy gates)."""
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
SHADER_RELEASES = {'0.9.5': '0.9.5', '0.9.6': '0.9.6', '0.9.7': '0.9.6', '0.9.8': '0.9.6'}
REQUIRED = {'main.lua', 'src/actioncam.lua', 'src/standalone.lua', 'config/defaults.cfg',
            'INSTALL.txt', 'PROVENANCE.json', 'manifest.json', 'FILES-SHA256.txt',
            'LICENSE-Bingus.txt', 'PhotoCapture64.dll', 'standalone-library.txt'}


def verify_legacy(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate ZIP paths'
        assert archive.testzip() is None, 'ZIP CRC failed'
        for name in names:
            entry = PurePosixPath(name)
            assert name.startswith(PREFIX) and '\\' not in name and not entry.is_absolute() and '..' not in entry.parts, 'Unsafe or foreign ZIP entry: '+name
            assert not name.endswith('/'), 'Unexpected directory entry: '+name
            lowered = name.lower()
            assert not any(token in lowered for token in ('diagnostic', 'deployment-backup', '/screenshots/', 'scene_effects', 'photo-analysis', 'photo_camera_entity')), 'Private/experimental entry: '+name
            assert not lowered.endswith(('.log', '.dds', '.pdb', '.obj', '.exe')), 'Unexpected artifact: '+name
            if lowered.endswith('.dll'):
                assert entry.name == 'PhotoCapture64.dll' or re.fullmatch(r'mcm_input_[0-9a-f]+\.dll', entry.name), 'Unexpected DLL: '+name
        files = {name[len(PREFIX):]: archive.read(name) for name in names}
    assert REQUIRED <= files.keys(), 'Required release files missing: '+str(sorted(REQUIRED-files.keys()))
    manifest = json.loads(files['manifest.json'])
    version = (ROOT/'VERSION').read_text().strip()
    assert manifest['id'] == 'dbf_freecam' and manifest['name'] == 'War Journalist' and manifest['version'] == version, 'Release identity/version mismatch'
    assert manifest['lll']['restart_only'] is True and manifest['lll']['retain_until_exit'] is True, 'Camera hook lifecycle policy missing'
    actual_modules = sorted(name for name in files if name.startswith('src/') and name.endswith('.lua'))
    assert manifest['lll']['modules'] == actual_modules, 'Module manifest differs from packaged Lua source'
    assert json.loads(files['config/defaults.cfg']) == {}, 'Release includes saved settings'
    checksums = {}
    for line in files['FILES-SHA256.txt'].decode().splitlines():
        digest, name = line.split('  ', 1)
        assert name not in checksums and name in files and re.fullmatch('[0-9a-f]{64}', digest), 'Invalid checksum entry'
        assert hashlib.sha256(files[name]).hexdigest() == digest, 'Packaged checksum mismatch: '+name
        checksums[name] = digest
    assert set(checksums) == set(files)-{'FILES-SHA256.txt'}, 'Checksum list does not cover the exact release'
    native_name = files['standalone-library.txt'].decode().strip()
    assert native_name in files and re.fullmatch(r'mcm_input_[0-9a-f]+\.dll', native_name), 'Standalone input DLL manifest invalid'
    assert files['PhotoCapture64.dll'][:2] == b'MZ' and files[native_name][:2] == b'MZ', 'Native release payload is not PE'
    assert b'Zero-Clause BSD' in files['LICENSE-Bingus.txt'] and b'CowboyBingus' in files['LICENSE-Bingus.txt'], 'Vendored license/credit missing'
    documentation = files['INSTALL.txt'].decode(errors='replace')
    for required in ('War Journalist', 'MCM is optional', 'KNOWN ISSUES', 'disabled', 'ActionCam 2.3.1', 'CowboyBingus'):
        assert required in documentation, 'Release install/known-issues documentation missing: '+required
    bundled = files['src/actioncam.lua'].decode()
    assert 'name=\'Photo Mode\'' in bundled or "name='Photo Mode'" in bundled, 'Internal MCM category name changed'
    assert 'self.custom_dof_ready=false' in bundled, 'Custom lens release gate missing'
    assert 'self.parameters.focus_distance,self.parameters.aperture=nil,nil' in bundled, 'Deferred capability release gate missing'
    assert 'mods/dbf_photo/materials/' not in bundled, 'Experimental scene materials embedded in release'
    return {'version': version, 'checked_at_utc': datetime.now(timezone.utc).isoformat(), 'passed': True,
            'archive': path.name, 'archive_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'files': len(files), 'lua_modules': len(actual_modules), 'checksums_verified': len(checksums),
            'game_process_accessed': False, 'scope': 'LLL ZIP bytes, identity, license, documentation, native payloads and static release gates'}


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


def stable_runtime(payload):
    for name in ('src/actioncam.lua','src/standalone.lua','standalone-library.txt','PhotoCapture64.dll'):
        assert name in payload, 'Private runtime missing: '+name
    runtime=payload['src/actioncam.lua'].decode()
    assert "name='Photo Mode'" in runtime, 'Internal MCM category changed'
    assert 'self.custom_dof_ready=false' in runtime and 'self.parameters.focus_distance,self.parameters.aperture=nil,nil' in runtime, 'Deferred lens gates missing'
    assert 'mods/dbf_photo/materials/' not in runtime, 'Experimental scene materials embedded'
    assert "id='lock_camera_key'" in runtime and 'default=76' in runtime, 'Default L shortcut missing'
    private=payload['src/standalone.lua'].decode()
    assert 'host.config_dir' in private and 'host.require' in private and 'host.read' in private, 'Private standalone contract missing'
    name=payload['standalone-library.txt'].decode().strip()
    assert re.fullmatch(r'mcm_input_[0-9a-f]+\.dll',name)and name in payload, 'Private input DLL manifest invalid'
    assert payload[name][:2]==b'MZ'and payload['PhotoCapture64.dll'][:2]==b'MZ', 'Native payload not PE'
    for name in payload:assert 'scene_effects'not in name and 'scene_profile'not in name, 'Experimental module included'


def verify_legacy_stable(path):
    sys.path.insert(0,str(ROOT/'tools'));import lua_archive,photo_assets
    with zipfile.ZipFile(path)as archive:
        names=archive.namelist();assert len(names)==len(set(names))and archive.testzip()is None, 'ZIP paths/CRC invalid'
        for name in names:
            entry=PurePosixPath(name);lower=name.lower()
            assert not entry.is_absolute()and '..'not in entry.parts and '\\'not in name and not name.endswith('/'), 'Unsafe ZIP path'
            assert not any(token in lower for token in ('diagnostic','deployment-backup','/screenshots/','scene_effects','photo-analysis','photo_camera_entity')), 'Private/experimental ZIP entry'
            assert not lower.endswith(('.log','.dds','.pdb','.obj','.exe')), 'Unexpected artifact'
        files={name:archive.read(name)for name in names}
    version=(ROOT/'VERSION').read_text().strip()
    if 'Addon/9ba626afa44a3aa3.patch_0'in files:
        format='BSL';asset_prefix='Addon/';manifest=json.loads(files['manifest.json'])
        assert manifest['Version']==1 and manifest['Name']=='War Journalist '+version, 'BSL identity/version mismatch'
        assert manifest['Options'][0]['Include']==['Addon']and 'Bingus Shared Loader'in manifest['Description'], 'BSL install/dependency mismatch'
        rows=photo_assets.read_archive(files[asset_prefix+'9ba626afa44a3aa3.patch_0'],files[asset_prefix+'9ba626afa44a3aa3.patch_0.gpu_resources'])
        startup_rows=[row for row in rows if row[1]==lua_archive.LUA_TYPE]
        assert len(startup_rows)==1 and startup_rows[0][0]==lua_archive.hash_name('mods/dbf_photomode/startup'), 'BSL startup entry mismatch'
        body=startup_rows[0][2];assert body[4:8]==b'\x02\0\0\0'and int.from_bytes(body[:4],'little')==len(body)-8
        startup=body[8:].decode();payload=embedded_payload(startup)
        assert 'DBF_PHOTO_MODE_OWNER'in startup and 'DBF_PHOTO_PACKAGE_ROOT'in startup and 'config_dir=config'in startup, 'BSL ownership/private path missing'
        assert 'mod.require'not in startup and 'mod.read'not in startup, 'LLL dependency in BSL'
        doc=files['INSTALL.txt'].decode(errors='replace');license=files['LICENSE-Bingus.txt']
        asset_manifest=json.loads(files['ASSET-MANIFEST.json'])
    else:
        format='MDL';asset_prefix='GameData/'
        assert all(name.startswith(('dbf_freecam/','GameData/'))or name in ('INSTALL.txt','FILES-SHA256.txt')for name in files), 'Foreign MDL files'
        payload={name.removeprefix('dbf_freecam/'):body for name,body in files.items()if name.startswith('dbf_freecam/')};manifest=json.loads(payload['manifest.json'])
        assert manifest['id']=='dbf_freecam'and manifest['name']=='War Journalist'and manifest['version']==version and manifest['loader']=='MDL', 'MDL identity/version mismatch'
        assert manifest['api']==2 and manifest['restart_required']is True, 'MDL API/restart policy missing'
        startup=payload['mod.lua'].decode()
        assert 'DBF_PHOTO_MODE_OWNER'in startup and 'DBF_PHOTO_PACKAGE_ROOT'in startup and 'ctx.api==2'in startup, 'MDL bootstrap contract missing'
        assert 'mod.require'not in startup and 'mod.read'not in startup, 'LLL dependency in MDL'
        doc=payload['INSTALL.txt'].decode(errors='replace');license=payload['LICENSE-Bingus.txt']
        asset_manifest=json.loads(payload['ASSET-MANIFEST.json'])
        assert 'GameData'in doc and 'INSTALL BOTH INCLUDED PARTS'in doc, 'MDL bundled asset instructions missing'
    stable_runtime(payload)
    base=asset_prefix+'9ba626afa44a3aa3.patch_0'
    assert files[base+'.stream']==b'', 'Unexpected streamed resources'
    audit=photo_assets.validate_archive(files[base],files[base+'.gpu_resources'])
    assert audit==asset_manifest, 'Packaged asset audit differs from verified closure'
    registry_base=asset_prefix+'ee6b1ba7e22d71ed.patch_0'
    assert files[registry_base+'.stream']==b''and files[registry_base+'.gpu_resources']==b'', 'Unexpected registry sidecars'
    registry_rows=photo_assets.read_archive(files[registry_base])
    assert registry_rows==[photo_assets.registry_resource()], 'Shader registration closure mismatch'
    checksum_name='FILES-SHA256.txt';assert checksum_name in files;checksums={}
    for line in files[checksum_name].decode().splitlines():
        digest,name=line.split('  ',1)
        assert name not in checksums and name in files and re.fullmatch('[0-9a-f]{64}',digest)
        assert hashlib.sha256(files[name]).hexdigest()==digest, 'Checksum mismatch: '+name;checksums[name]=digest
    assert set(checksums)==set(files)-{checksum_name}, 'Checksum coverage differs from ZIP'
    assert b'Zero-Clause BSD'in license and b'CowboyBingus'in license
    for text in ('War Journalist','MCM is optional','KNOWN ISSUES','disabled','HuedPurple','CowboyBingus','40 decorative','MANUAL ASSET INSTALL'):assert text in doc, 'Missing install/known-issues/credit: '+text
    assert 'DBF-HUD asset pack'not in doc, 'HUD dependency remains in install notes'
    vendor=json.loads(files.get('VENDOR-PROVENANCE.json')or payload['VENDOR-PROVENANCE.json'])
    for name,digest in vendor['runtime_sha256'].items():
        packaged=payload['src/vendor/'+name]if name.endswith('.lua')else payload[name]
        assert hashlib.sha256(packaged).hexdigest()==digest, 'Vendored runtime identity mismatch: '+name
    return {'version':version,'format':format,'passed':True,'checked_at_utc':datetime.now(timezone.utc).isoformat(),'archive':path.name,
            'archive_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'files':len(files),'private_payload_files':len(payload),
            'checksums_verified':len(checksums),'asset_audit':audit,'game_process_accessed':False,
            'scope':'ZIP CRC/checksums, bootstrap/private input/capture, exact complete native resource closure and registration, stable gates, docs and credits'}


def _release_files(source):
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)) and archive.testzip() is None, 'ZIP paths/CRC invalid'
        for name in names:
            entry = PurePosixPath(name)
            assert not entry.is_absolute() and '..' not in entry.parts and '\\' not in name and ':' not in name and not name.endswith('/'), 'Unsafe ZIP path: '+name
            lower = name.lower()
            assert not any(token in lower for token in ('deployment-backup', '/screenshots/', 'photohoversguard', 'photohoverguard', 'minhook', 'hover-library', '.codex/')), 'Private/rejected artifact: '+name
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


def _release_asset_closure(files, prefix, bsl, version):
    import photo_assets
    import lua_archive
    import photo_light_assets
    parsed = []
    for base in ('ee6b1ba7e22d71ed', '9ba626afa44a3aa3'):
        path = prefix+base+'.patch_0'
        assert files[path+'.stream'] == b'', 'Unexpected stream resources'
        parsed.append(photo_assets.read_archive(files[path], files[path+'.gpu_resources'], files[path+'.stream']))
    core, shared = parsed
    assert Counter(row[1] for row in core) == {photo_assets.SHADER: 44, photo_assets.GROUP: 1}, 'Core must contain exactly 44 shader libraries and one registry'
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
    assert set(shaders) == expected_shaders and set(materials) == expected_materials, 'Shader/material identity closure differs'
    resolved = shaders[photo_assets.hash64('mods/dbf_photo/shaders/'+resolved_name)]
    assert hashlib.sha256(resolved[3]).hexdigest() == resolved_sha, 'Versioned compositor bytes changed'
    indexed = {row[:2]: row for row in core+shared}
    for row in decorations:
        assert indexed[row[:2]] == row, 'Existing decorative asset changed'
    for name, _, cpu, gpu in shaders.values():
        assert cpu == struct.pack('<I', 4) and len(gpu) > 0xe4, 'Invalid shader-library payload'
        assert struct.unpack_from('<I', gpu, 0xe0)[0] == name >> 32, 'Shader variant identity mismatch'
        assert len(photo_assets._dxbc_windows(gpu)) == 2, 'Shader must contain its vertex and pixel programs'
    variants = {name >> 32 for name in shaders}
    for _, _, cpu, gpu in materials.values():
        assert len(cpu) == 144 and not gpu and struct.unpack_from('<I', cpu, 128)[0] in variants, 'Material shader dependency missing'
    group = next(row for row in core if row[1] == photo_assets.GROUP)
    assert group[0] == photo_assets.hash64(photo_assets.GROUP_NAME) and not group[3], 'Wrong shader registry resource'
    ids = photo_assets.registry_ids(group[2])
    base = (ROOT/'freecam/assets/shaders/dof_registry_base.bin').read_bytes()
    assert len(ids) == 319 and tuple(ids[:315]) == photo_assets.registry_ids(base), 'Existing renderer registrations changed'
    assert set(ids[315:]) == {photo_assets.hash64('mods/dbf_photo/shaders/'+name) for name in extra_names}, 'Photo registration additions differ'
    assert expected_shaders <= set(ids), 'Unregistered packaged shader'
    lua_rows = [row for row in shared if row[1] == lua_archive.LUA_TYPE]
    startup = None
    if bsl:
        row = lua_rows[0]
        assert row[0] == lua_archive.hash_name('mods/dbf_photomode/startup') and not row[3], 'Unexpected Lua startup resource'
        body = row[2]
        assert len(body) >= 8 and struct.unpack_from('<II', body) == (len(body)-8, 2), 'BSL startup envelope invalid'
        startup = body[8:].decode()
    return {'shader_libraries': 44, 'materials': 44, 'registry_ids': 319, 'dedicated_lights': 1,
            'startup_resources': len(lua_rows), 'external_light_dependencies': [],
            'registry_sha256': hashlib.sha256(group[2]).hexdigest()}, startup


def verify_current(path, version, standalone=False):
    import photo_assets
    from test_packaged_standalone import pe_imports
    files = _release_files(path)
    bsl = 'Addon/9ba626afa44a3aa3.patch_0' in files
    audit, startup = _release_asset_closure(files, 'Addon/' if bsl else 'GameData/', bsl, version)
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
            nested_audit, _ = _release_asset_closure(nested, 'Assets/', False, version)
            assert nested_audit == audit, 'Arsenal companion asset closure differs'
            for name, body in files.items():
                if name.startswith('GameData/'):
                    assert nested['Assets/'+name.removeprefix('GameData/')] == body, 'Arsenal and manual assets differ'
    for required in ('src/actioncam.lua', 'src/standalone.lua', 'standalone-library.txt'):
        assert required in runtime, 'Private runtime missing: '+required
    code = runtime['src/actioncam.lua'].decode()
    assert "name='Photo Mode'" in code and 'H.dbf_hover_pause' in code and 'native_color_guard' in code
    for forbidden in ('PhotoHoverGuard', 'MH_CreateHook', 'hover-library.txt', 'MinHook'):
        assert forbidden not in code, 'Rejected native hover-hook code included'
    for logo in ('Super Earth crest', 'Super Citizen Edition', 'Heart of Democracy', 'Into the Unjust'):
        assert logo in code, 'Updated embedded logo missing: '+logo
    assert not any(word in code for word in ('Beddivers', 'Brasildivers', 'Shafts of Despair')), 'Excluded joke logo in runtime'
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
    if version in ('0.9.7', '0.9.8'):
        assert asset_manifest['shader_asset_version'] == SHADER_RELEASES[version], 'Release must retain the frozen 0.9.6 shader assets'
    for key, expected in (('version', version), ('shader_libraries_core', 44), ('materials_shared', 44), ('registry_resources_core', 1), ('registry_ids', 319)):
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


def verify(path, standalone=False):
    # Dispatch from the immutable package identity, not this checkout's VERSION.
    with zipfile.ZipFile(path) as archive:
        name = PREFIX+'manifest.json' if PREFIX+'manifest.json' in archive.namelist() else 'manifest.json'
        manifest = json.loads(archive.read(name))
    version = manifest.get('version') or manifest.get('Name', '').removeprefix('War Journalist ')
    if version in SHADER_RELEASES:
        return verify_current(path, version, standalone)
    assert not standalone, '--standalone in this verifier requires a supported release package'
    return verify_legacy_stable(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--standalone', action='store_true', help='Also execute the package-only mocked startup check; never attaches to the game')
    args = parser.parse_args()
    try:
        result = verify(args.archive, args.standalone)
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

"""Verify immutable War Journalist BSL/MDL ZIP bytes and stable release gates."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'dbf_freecam/'
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


def verify(path):
    sys.path.insert(0,str(ROOT/'tools'));import lua_archive
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
        format='BSL';prefix='';manifest=json.loads(files['manifest.json'])
        assert manifest['Version']==1 and manifest['Name']=='War Journalist '+version, 'BSL identity/version mismatch'
        assert manifest['Options'][0]['Include']==['Addon']and 'Bingus Shared Loader'in manifest['Description'], 'BSL install/dependency mismatch'
        assert files['Addon/9ba626afa44a3aa3.patch_0.stream']==b''and files['Addon/9ba626afa44a3aa3.patch_0.gpu_resources']==b'', 'Unexpected scene assets'
        resources=lua_archive.read(files['Addon/9ba626afa44a3aa3.patch_0']);key=lua_archive.hash_name('mods/dbf_photomode/startup')
        assert len(resources)==1 and key in resources, 'BSL startup entry mismatch'
        kind,body=resources[key];assert kind==lua_archive.LUA_TYPE and body[4:8]==b'\x02\0\0\0'
        startup=body[8:].rstrip(b'\0').decode();payload=embedded_payload(startup)
        assert 'DBF_PHOTO_MODE_OWNER'in startup and 'DBF_PHOTO_PACKAGE_ROOT'in startup and 'config_dir=config'in startup, 'BSL ownership/private path missing'
        assert 'mod.require'not in startup and 'mod.read'not in startup, 'LLL dependency in BSL'
    else:
        format='MDL';prefix='dbf_freecam/';assert all(name.startswith(prefix)for name in files), 'Foreign MDL files'
        payload={name[len(prefix):]:body for name,body in files.items()};manifest=json.loads(payload['manifest.json'])
        assert manifest['id']=='dbf_freecam'and manifest['name']=='War Journalist'and manifest['version']==version and manifest['loader']=='MDL', 'MDL identity/version mismatch'
        assert manifest['api']==2 and manifest['restart_required']is True, 'MDL API/restart policy missing'
        startup=payload['mod.lua'].decode()
        assert 'DBF_PHOTO_MODE_OWNER'in startup and 'DBF_PHOTO_PACKAGE_ROOT'in startup and 'ctx.api==2'in startup, 'MDL bootstrap contract missing'
        assert 'mod.require'not in startup and 'mod.read'not in startup, 'LLL dependency in MDL'
    stable_runtime(payload)
    checksum_name=prefix+'FILES-SHA256.txt';assert checksum_name in files;checksums={}
    for line in files[checksum_name].decode().splitlines():
        digest,name=line.split('  ',1);entry=prefix+name
        assert name not in checksums and entry in files and re.fullmatch('[0-9a-f]{64}',digest)
        assert hashlib.sha256(files[entry]).hexdigest()==digest, 'Checksum mismatch: '+entry;checksums[name]=digest
    assert {prefix+name for name in checksums}==set(files)-{checksum_name}, 'Checksum coverage differs from ZIP'
    license=files[prefix+'LICENSE-Bingus.txt'];doc=files[prefix+'INSTALL.txt'].decode(errors='replace')
    assert b'Zero-Clause BSD'in license and b'CowboyBingus'in license
    for text in ('War Journalist','MCM is optional','KNOWN ISSUES','disabled','HuedPurple','CowboyBingus'):assert text in doc, 'Missing install/known-issues/credit: '+text
    return {'version':version,'format':format,'passed':True,'checked_at_utc':datetime.now(timezone.utc).isoformat(),'archive':path.name,
            'archive_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'files':len(files),'private_payload_files':len(payload),
            'checksums_verified':len(checksums),'game_process_accessed':False,'scope':'ZIP CRC/checksums, bootstrap/private input/capture, stable gates, known issues and credits'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.archive)
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
